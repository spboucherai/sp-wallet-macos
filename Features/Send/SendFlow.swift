// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/Send/SendFlow.swift
// Description: State machine of a transfer: form → server draft (validation, simulation, policy pre-check) → frozen intent verified against its challenge → passkey assertion → signer → broadcast → confirmations. The client decides nothing about success: every state shown is the server's, itself read from the chain.
import Foundation
import SPWalletCore

@MainActor @Observable final class SendFlow {
    enum Step: Equatable { case form, preparing, review, approving, tracking }

    let model: AppModel
    var network = ""
    var asset = "native"
    var to = ""
    var amount = ""
    var memo = ""
    var note = ""

    private(set) var step: Step = .form
    private(set) var draft: Proposal?
    private(set) var approval: TransferApproval?
    private(set) var tracked: Proposal?
    private(set) var history: [(Date, ProposalState)] = []
    var error: String?
    /// Kept while the form does not change, so a retried preparation answers the same draft instead of creating a second one.
    private var idempotency: (key: String, fingerprint: String)?
    private var trackTask: Task<Void, Never>?

    init(model: AppModel) { self.model = model }

    var net: SPWalletCore.Network? { model.network(network) }
    var assetDef: AssetDef? { net?.asset(asset) }
    var balance: Balance? { model.portfolio?.value.balances.first { $0.network == network && $0.asset == asset } }
    var addressCheck: AddressCheck? { guard let n = net, !to.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }; return AddressValidator.check(to, network: n) }
    var otherNetworks: [SPWalletCore.Network] {
        guard let all = model.networks?.value, addressCheck?.isValid == false else { return [] }
        return AddressValidator.plausibleNetworks(for: to, among: all).filter { $0.id != network }
    }
    var parsedAmount: BaseUnits? { guard let d = assetDef?.decimals else { return nil }; return try? BaseUnits.parse(normalizedAmount, decimals: d) }
    var normalizedAmount: String { amount.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "\u{202F}", with: "").replacingOccurrences(of: " ", with: "") }
    var exceedsBalance: Bool { guard let a = parsedAmount, let b = balance?.units else { return false }; return a > b }
    var isOwnAddress: Bool { guard let n = addressCheck?.normalized else { return false }; return model.address(on: network) == n }

    var formProblem: String? {
        guard net != nil, assetDef != nil else { return "Choisissez un réseau et un actif." }
        switch addressCheck {
        case nil: return "Entrez l’adresse du destinataire."
        case .invalid(let r): return SendFlow.text(r)
        case .unverifiable, .valid: break
        }
        if isOwnAddress { return "La destination est l’adresse de ce portefeuille." }
        if amount.isEmpty { return "Entrez un montant." }
        guard let a = parsedAmount, !a.isZero else { return "Montant invalide (au plus \(assetDef?.decimals ?? 0) décimales)." }
        if balance?.isAvailable == true, exceedsBalance { return "Montant supérieur au solde lu sur la chaîne." }
        if let m = net?.memo, m == "uint32", !memo.isEmpty, UInt32(memo) == nil { return "L’étiquette de destination doit être un entier." }
        return nil
    }

    static func text(_ r: AddressRejection) -> String {
        switch r {
        case .malformed: "Ce n’est pas la forme d’une adresse de ce réseau."
        case .badChecksum: "Somme de contrôle invalide : un caractère est probablement erroné."
        case .mixedCase: "Majuscules et minuscules mélangées : adresse invalide pour cet encodage."
        case .wrongNetwork: "Adresse bien formée, mais d’un autre réseau."
        case .unsupportedType: "Type d’adresse que ce portefeuille n’envoie pas."
        case .reserved: "Adresse nulle ou de destruction : les fonds y seraient perdus."
        case .nonCanonical: "Adresse non canonique : utilisez sa forme standard."
        }
    }

    func setMax() { if let b = balance, let d = b.display { amount = d } }

    func prepare() async {
        guard formProblem == nil, model.canOperate, step == .form else { return }
        error = nil; step = .preparing
        let req = TransferRequest(network: network, asset: asset, to: to.trimmingCharacters(in: .whitespacesAndNewlines), amount: normalizedAmount, note: note, memo: memo.isEmpty ? nil : memo)
        let fp = "\(req.network)|\(req.asset)|\(req.to)|\(req.amount)|\(req.note)|\(req.memo ?? "")"
        if idempotency?.fingerprint != fp { idempotency = (APIClient.newIdempotencyKey(), fp) }
        do {
            let d = try await model.transfers.draft(req, idempotencyKey: idempotency!.key)
            // the draft must be the transfer that was typed: the server normalizes the address, nothing else may differ
            guard d.network == req.network, d.asset == req.asset, d.amount == (parsedAmount?.description ?? "") else { throw ApprovalError.inconsistent("le brouillon du serveur ne correspond pas au formulaire") }
            if let local = addressCheck?.normalized, let dto = d.to, local != dto { throw ApprovalError.inconsistent("destination normalisée différemment par le serveur") }
            guard d.state == .draft || d.state == .pendingApproval else { throw APIError(status: 409, code: "bad_state", message: "Cette demande a déjà été traitée (\(ErrorText.state(d.state))). Modifiez le formulaire pour en créer une nouvelle.") }
            draft = d
            approval = try await model.transfers.requestApproval(for: d)
            step = .review
        } catch { self.error = model.describe(error); step = .form }
    }

    func approve() async {
        guard let a = approval, step == .review else { return }
        error = nil; step = .approving
        do {
            let p = try await model.transfers.approve(a, with: model.authenticator)
            idempotency = nil
            begin(tracking: p)
        } catch PasskeyError.cancelled { step = .review }
        catch let e as APIError where e.isOffline {
            // the answer was lost: the approval may have reached the signer — never sign twice, follow the proposal instead
            self.error = "Réponse perdue pendant l’approbation. Lecture de l’état réel de l’opération…"
            if let p = try? await model.transfers.proposal(a.proposal.id), p.state != .pendingApproval { idempotency = nil; begin(tracking: p) } else { step = .review }
        }
        catch {
            self.error = model.describe(error)
            if let p = try? await model.transfers.proposal(a.proposal.id), p.state != .pendingApproval { idempotency = nil; begin(tracking: p) } else { step = .review }
        }
    }

    func reject() async {
        guard let a = approval else { return }
        _ = try? await model.transfers.reject(a.proposal.id)
        idempotency = nil; approval = nil; draft = nil; step = .form
    }

    private func begin(tracking p: Proposal) {
        tracked = p; history = [(Date(), p.state)]; step = .tracking
        Task { await model.refreshActivity() }
        trackTask?.cancel()
        trackTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let cur = self.tracked, !cur.state.isTerminal else { return }
                try? await Task.sleep(for: .seconds(cur.state == .broadcast || cur.state == .confirming ? 5 : 2))
                guard let p = try? await self.model.transfers.proposal(cur.id) else { continue }
                if p.state != self.tracked?.state { self.history.append((Date(), p.state)); if p.state.isTerminal { Notifier.proposal(p); await self.model.refreshAll() } }
                self.tracked = p
            }
        }
    }

    func reset() {
        trackTask?.cancel(); tracked = nil; approval = nil; draft = nil; history = []; error = nil
        to = ""; amount = ""; memo = ""; note = ""; idempotency = nil; step = .form
    }
}
