// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Features/Bridge/BridgeFlow.swift
// Description      : State machine of a USDC transfer between networks through
//                    Circle CCTP: networks the server enables → quote of both
//                    speeds → firm burn verified by the Core against the
//                    challenge → passkey → the two legs followed until the
//                    destination mint is confirmed. Also the recovery of
//                    interrupted transfers (finish, passkey-approved new mint
//                    signature, reclaim of the Solana event-account deposit)
//                    and the opening of the wallet's USDC token account on
//                    Solana — each through the Core's verified approval, or
//                    shown as unavailable when the Core cannot verify it.
// Module           : Features
// Repository       : https://git.spboucher.ai/sp-wallet-macos
// Created          : 2026-11-18
// Last Modified    : 2026-11-18
//
// =============================================================================
// AUTHOR & PROFESSIONAL AFFILIATION
// =============================================================================
//
// Author           : Simon-Pierre Boucher
// Position         : Professor of Finance
// Institution      : Université du Québec en Outaouais (UQO)
// Department       : Département des sciences administratives
// Organization     : SP Boucher
//
// Website          : https://spboucher.ai
// Git              : https://git.spboucher.ai
//
// =============================================================================
// OFFICIAL CONTACT DIRECTORY
// =============================================================================
//
// General          : info@spboucher.ai
// Professional     : contact@spboucher.ai
// Direct           : simon@spboucher.ai
// Research         : research@spboucher.ai
// Development      : dev@spboucher.ai
// Support          : support@spboucher.ai
// Security/Admin   : admin@spboucher.ai
// Notifications    : notifications@spboucher.ai
//
// Preferred Contact: support@spboucher.ai
//
// =============================================================================
// COPYRIGHT & INTELLECTUAL PROPERTY
// =============================================================================
//
// Copyright (c) 2026
// Simon-Pierre Boucher
//
// All rights reserved where applicable.
//
// This file is governed by the applicable project license,
// copyright notices, institutional agreements and relevant law.
//
// Unless expressly authorized by the applicable license or
// rights holder, copying, redistribution, sublicensing,
// publication and commercial exploitation are not permitted.
//
// Existing third-party rights and notices remain unaffected.
//
// =============================================================================
// CONFIDENTIALITY & SECURITY
// =============================================================================
//
// Classification   : Public
// Distribution     : Public repository; use is governed by the project license
// Security Contact : admin@spboucher.ai
//
// Access to this source does not independently grant permission
// to redistribute or disclose confidential materials.
//
// Do not embed credentials, private keys, access tokens,
// certificates or confidential personal information.
//
// =============================================================================
// LICENSE & MAINTENANCE
// =============================================================================
//
// License          : None specified (no license file in this repository)
// Maintainer       : Simon-Pierre Boucher
// Technical Contact: dev@spboucher.ai
//
// =============================================================================
// END OF SP BOUCHER SOURCE HEADER
// =============================================================================

import Foundation
import SPWalletCore

@MainActor @Observable final class BridgeFlow {
    enum Step: Equatable { case form, preparing, review, approving, tracking }
    enum QuotePhase: Equatable { case idle, loading, done, failed(String) }
    /// A passkey approval that is not an intent: each carries the object the Core verified against its challenge.
    enum FollowUp { case retryMint(MintRetryApproval), reclaim(DepositReclaimApproval), tokenAccount(TokenAccountApproval) }
    enum Action: String { case finish, retryMint, reclaim, tokenAccount }

    /// One interrupted or unfinished transfer found in the activity feed.
    struct Recoverable: Identifiable {
        let item: ActivityItem
        /// nil when the server's bridge section cannot be read by this version: shown as such, never guessed.
        let section: BridgeSection?
        var id: String { item.id }
    }

    let model: AppModel
    var fromNetwork = "" { didSet { if fromNetwork == toNetwork, let other = networks.first(where: { $0.id != fromNetwork }) { toNetwork = other.id } } }
    var toNetwork = ""
    var amount = ""
    var speed: BridgeSpeed = .standard

    private(set) var info: BridgeExecutionInfo?
    private(set) var loadError: String?
    private(set) var quotePhase: QuotePhase = .idle
    private(set) var quote: BridgeQuote?
    private(set) var quotedAt: Date?
    private(set) var requote = 0

    private(set) var step: Step = .form
    private(set) var operation: ApprovableOperation?
    private(set) var tracker: OperationTracker?
    var error: String?
    private var idempotency: (key: String, fingerprint: String)?

    private(set) var followUp: FollowUp?
    private(set) var followUpBusy = false
    var followUpError: String?
    private(set) var busyAction: Action?
    /// Actions the Core refused to verify (`ApprovalError.unsupported`): no way around is offered.
    private(set) var unavailable: [Action: String] = [:]
    private(set) var tokenAccountCreation: SolanaTokenAccountCreation?
    private(set) var opening: String?
    private(set) var openError: String?

    init(model: AppModel) { self.model = model }

    // MARK: derived

    private var api: BridgeAPI { BridgeAPI(model.client) }
    /// The networks CCTP serves, in the server's order, limited to those the registry knows.
    var networks: [SPWalletCore.Network] { (info?.networks ?? []).compactMap { model.network($0) } }
    var normalizedAmount: String { SwapText.normalize(amount) }
    var parsedAmount: BaseUnits? { try? BaseUnits.parse(normalizedAmount, decimals: 6) } // USDC has six decimals on every CCTP network
    /// The registry id of USDC on a network — only when exactly one token carries that symbol (a symbol is not an identifier).
    func usdc(on network: String) -> AssetDef? {
        let hits = model.network(network)?.tokens.filter { $0.symbol == "USDC" } ?? []
        return hits.count == 1 ? hits[0] : nil
    }
    var sourceBalance: Balance? {
        guard let u = usdc(on: fromNetwork) else { return nil }
        return model.portfolio?.value.balances.first { $0.network == fromNetwork && SwapText.sameId($0.asset, u.id) }
    }
    var option: BridgeQuote.Option? { quote?.option(speed) }
    var tokenAccountMissing: Bool { quote?.solana?.role == "destination" && quote?.solana?.tokenAccountExists == false }

    var formProblem: String? {
        guard let info else { return "Capacités du pont non lues." }
        guard !fromNetwork.isEmpty, !toNetwork.isEmpty else { return "Choisissez le réseau source et le réseau de destination." }
        if fromNetwork == toNetwork { return "Choisissez deux réseaux différents." }
        if !info.canBridge(from: fromNetwork, to: toNetwork) { return "Le serveur n’active pas CCTP entre ces deux réseaux." }
        if amount.trimmingCharacters(in: .whitespaces).isEmpty { return "Entrez un montant." }
        guard let a = parsedAmount, !a.isZero else { return "Montant invalide (au plus 6 décimales)." }
        if let b = sourceBalance, b.isAvailable, let u = b.units, a > u { return "Montant supérieur au solde USDC lu sur la chaîne." }
        return nil
    }

    /// Why the selected option cannot be prepared right now; nil when it can.
    var prepareProblem: String? {
        if let p = formProblem { return p }
        guard let q = quote, quotePhase == .done else { return "En attente du devis." }
        guard let o = q.option(speed) else { return "Cette vitesse n’est pas offerte sur cette route." }
        if !o.available { return "Cette vitesse n’est pas disponible pour ce montant en ce moment." }
        if o.quote == nil { return "Le montant ne couvre pas les frais de Circle." }
        if !q.destinationGas.enough { return "Pas assez de \(q.destinationGas.symbol) sur la destination pour payer l’émission : le serveur refuse de brûler quoi que ce soit." }
        if tokenAccountMissing { return "Ouvrez d’abord le compte de jetons USDC sur Solana." }
        return nil
    }

    var quoteKey: String { "\(fromNetwork)|\(toNetwork)|\(normalizedAmount)|\(requote)|\(model.canOperate)" }

    /// Transfers still in transit, waiting for a decision, or whose Solana deposit has not come back, most recent first.
    var recoverable: [Recoverable] {
        (model.activity?.value ?? []).compactMap { item -> Recoverable? in
            guard item.kind == "bridge", let raw = item.bridge, !raw.isNull else { return nil }
            guard let b = try? raw.decode(BridgeSection.self) else { return item.proposalState?.isFailure == true ? nil : Recoverable(item: item, section: nil) }
            let depositOut = b.sol?.role == "source" && b.sol?.reclaimState != nil && b.sol?.isReclaimed == false && !b.isFailed
            return b.isInTransit || depositOut ? Recoverable(item: item, section: b) : nil
        }
    }

    // MARK: loading and quote (read-only)

    func load() async {
        guard model.phase == .signedIn else { return }
        do {
            info = try await api.execution(); loadError = nil
            if fromNetwork.isEmpty, let first = networks.first { fromNetwork = first.id }
            if toNetwork.isEmpty, let second = networks.first(where: { $0.id != fromNetwork }) { toNetwork = second.id }
        } catch { loadError = model.describe(error) }
        await model.refreshActivity()
    }

    func refreshQuote() { requote += 1 }
    func setMax() { if let d = sourceBalance?.display { amount = d } }
    func flip() { let f = fromNetwork; fromNetwork = toNetwork; toNetwork = f }

    func runQuote() async {
        guard step == .form else { return }
        quote = nil; quotedAt = nil
        guard model.canOperate, formProblem == nil else { quotePhase = .idle; return }
        quotePhase = .loading
        try? await Task.sleep(for: .milliseconds(500))
        if Task.isCancelled { return }
        do {
            let q = try await api.quote(from: fromNetwork, to: toNetwork, amount: normalizedAmount)
            if Task.isCancelled { return }
            guard q.from == fromNetwork, q.to == toNetwork, q.symbol == "USDC" else { throw ApprovalError.inconsistent("le devis ne correspond pas à la route demandée") }
            quote = q; quotedAt = Date(); quotePhase = .done
            if q.option(speed) == nil { speed = .standard }
        } catch is CancellationError {
        } catch { if !Task.isCancelled { quotePhase = .failed(SwapText.describe(error, model: model)) } }
    }

    // MARK: preparation and approval of the burn

    func prepare() async {
        guard step == .form, model.canOperate, prepareProblem == nil, let o = option, let ref = o.quote else { return }
        guard let accounts = model.accounts?.value else { error = "Les adresses du portefeuille ne sont pas synchronisées ; l’opération ne peut pas être vérifiée."; return }
        error = nil; step = .preparing
        let fp = "\(fromNetwork)|\(toNetwork)|\(normalizedAmount)|\(speed.rawValue)|\(ref.fingerprint)"
        if idempotency?.fingerprint != fp { idempotency = (APIClient.newIdempotencyKey(), fp) }
        do {
            // the fee ceiling approved may not exceed the fee displayed; the asset burned must be the registry's USDC
            let prepared = try await api.prepare(BridgeRequest(fromNetwork: fromNetwork, toNetwork: toNetwork, amount: normalizedAmount, speed: speed, quote: ref),
                                                 accounts: accounts, sourceUSDC: usdc(on: fromNetwork)?.id, maxFee: o.fee, idempotencyKey: idempotency!.key)
            if let op = prepared.approvable { operation = op; step = .review }
            else { idempotency = nil; begin(tracking: prepared.proposal) }
        } catch {
            self.error = SwapText.describe(error, model: model)
            if (error as? APIError)?.isOffline != true { idempotency = nil; requote += 1 }
            step = .form
        }
    }

    func approve() async {
        guard let op = operation, step == .review else { return }
        error = nil; step = .approving
        do {
            let p = try await api.approve(op, with: model.authenticator)
            idempotency = nil; begin(tracking: p)
        } catch PasskeyError.cancelled { step = .review }
        catch {
            self.error = (error as? APIError)?.isOffline == true ? "Réponse perdue pendant l’approbation. Lecture de l’état réel de l’opération…" : SwapText.describe(error, model: model)
            if let p = try? await api.proposal(op.proposal.id), p.state != .pendingApproval { idempotency = nil; begin(tracking: p) } else { step = .review }
        }
    }

    func reject() async {
        guard let op = operation else { return }
        _ = try? await api.reject(op.proposal.id)
        idempotency = nil; operation = nil; error = nil; step = .form; requote += 1
    }

    private func begin(tracking p: Proposal) {
        operation = nil; unavailable = [:]; error = nil
        tracker = OperationTracker(model: model, proposal: p)
        step = .tracking
        Task { await model.refreshActivity() }
    }

    // MARK: recovery

    /// Open an existing transfer with its real, freshly read state.
    func open(_ r: Recoverable) async {
        guard opening == nil, step == .form || step == .tracking else { return }
        opening = r.id; defer { opening = nil }
        openError = nil
        do { begin(tracking: try await api.proposal(r.id)) }
        catch { openError = SwapText.describe(error, model: model) }
    }

    func closeTracking() {
        tracker = nil; error = nil; unavailable = [:]; step = .form; amount = ""; quote = nil; quotePhase = .idle
        Task { await model.refreshActivity() }
    }

    /// "Finish": the server runs the next step now. It signs nothing the burn approval did not cover.
    func finish() async {
        guard let t = tracker, busyAction == nil, model.canOperate else { return }
        busyAction = .finish; defer { busyAction = nil }
        do { t.update(try await api.finish(t.proposal.id)); error = nil }
        catch { self.error = SwapText.describe(error, model: model) }
    }

    private func request(_ action: Action, _ make: () async throws -> FollowUp) async {
        guard busyAction == nil, followUp == nil, model.canOperate else { return }
        busyAction = action; defer { busyAction = nil }
        error = nil; followUpError = nil
        do { followUp = try await make(); unavailable[action] = nil }
        catch let e as ApprovalError {
            // the Core could not verify the object to approve: the action is unavailable, with the reason, and nothing is signed
            if case .unsupported = e { unavailable[action] = model.describe(e) } else { self.error = model.describe(e) }
        }
        catch { self.error = SwapText.describe(error, model: model) }
        if let t = tracker, let p = try? await api.proposal(t.proposal.id) { t.update(p) }
    }

    func beginRetryMint() async {
        guard let id = tracker?.proposal.id else { return }
        let api = api
        await request(.retryMint) { .retryMint(try await api.retryMintOptions(id)) }
    }

    func beginReclaim() async {
        guard let id = tracker?.proposal.id else { return }
        let api = api
        await request(.reclaim) { .reclaim(try await api.reclaimOptions(id)) }
    }

    func beginTokenAccount() async {
        guard let accounts = model.accounts?.value else { error = "Les adresses du portefeuille ne sont pas synchronisées."; return }
        guard let mint = usdc(on: "solana")?.id else { unavailable[.tokenAccount] = "Le registre ne désigne pas un unique jeton USDC sur Solana : la demande ne peut pas être vérifiée."; return }
        let api = api
        await request(.tokenAccount) { .tokenAccount(try await api.solanaTokenAccountOptions(accounts: accounts, usdcMint: mint)) }
    }

    func cancelFollowUp() { guard !followUpBusy else { return }; followUp = nil; followUpError = nil }

    /// The passkey signs the verified challenge; the answer is never a completion (a mint sent again is not a mint received).
    func confirmFollowUp() async {
        guard let f = followUp, !followUpBusy, model.canOperate else { return }
        followUpBusy = true; defer { followUpBusy = false }
        followUpError = nil
        do {
            switch f {
            case .retryMint(let a): tracker?.update(try await api.retryMint(a, with: model.authenticator))
            case .reclaim(let a): tracker?.update(try await api.reclaim(a, with: model.authenticator))
            case .tokenAccount(let a):
                tokenAccountCreation = try await api.createSolanaTokenAccount(a, with: model.authenticator)
                requote += 1
            }
            followUp = nil
        } catch PasskeyError.cancelled {
        } catch {
            followUpError = SwapText.describe(error, model: model)
            // never sign twice on a lost answer: read what the server really did
            if let t = tracker, let p = try? await api.proposal(t.proposal.id) { t.update(p) }
        }
    }
}
