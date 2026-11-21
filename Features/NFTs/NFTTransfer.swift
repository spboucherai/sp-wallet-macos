// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Features/NFTs/NFTTransfer.swift
// Description      : Sending one NFT: form (destination checked with the
//                    backend's own address rules, quantity for ERC-1155) →
//                    server preparation (chain re-read on every endpoint,
//                    simulation, policy pre-check) → the Core verifies that the
//                    passkey challenge is the SHA-256 of the NFT intent and
//                    that the intent is the transfer that was asked → a review
//                    sheet that renders the fields OF THAT VERIFIED INTENT in
//                    full, with what the server says it checked shown apart →
//                    passkey → isolated signer → tracking until a terminal
//                    state. The client decides nothing about success, and a
//                    lost answer is followed, never signed twice.
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

import SwiftUI
import SPWalletCore

@MainActor @Observable final class NFTTransferFlow {
    enum Step: Equatable { case form, preparing, review, approving, tracking }

    let model: AppModel
    let api: NFTAPI
    let asset: NFTAsset
    let verdict: NFTTransferVerdictAnswer?

    var to = ""
    var quantity = "1"

    private(set) var step: Step = .form
    private(set) var approval: NFTTransferApproval?
    private(set) var tracked: NFTTransfer?
    private(set) var history: [(Date, ProposalState)] = []
    /// True once something was approved: the item and the inventory must be read again.
    private(set) var changed = false
    var error: String?
    /// Kept while the form does not change, so a retried preparation answers the same proposal instead of creating a second one.
    private var idempotency: (key: String, fingerprint: String)?
    private var trackTask: Task<Void, Never>?

    init(model: AppModel, asset: NFTAsset, verdict: NFTTransferVerdictAnswer?) {
        self.model = model; self.asset = asset; self.verdict = verdict; api = NFTAPI(model.client)
    }

    var net: SPWalletCore.Network? { model.network(asset.chainId) }
    var isMultiUnit: Bool { asset.standard == .erc1155 }
    var trimmedTo: String { to.trimmingCharacters(in: .whitespacesAndNewlines) }
    var addressCheck: AddressCheck? { guard let n = net, !trimmedTo.isEmpty else { return nil }; return AddressValidator.check(trimmedTo, network: n) }
    var otherNetworks: [SPWalletCore.Network] {
        guard let all = model.networks?.value, addressCheck?.isValid == false else { return [] }
        return AddressValidator.plausibleNetworks(for: trimmedTo, among: all).filter { $0.id != asset.chainId }
    }
    private func same(_ a: String, _ b: String?) -> Bool {
        guard let b else { return false }
        return a.hasPrefix("0x") && b.hasPrefix("0x") ? a.lowercased() == b.lowercased() : a == b
    }
    var isOwnAddress: Bool {
        guard let n = addressCheck?.normalized else { return false }
        return same(n, model.address(on: asset.chainId)) || same(n, asset.ownerAddress)
    }
    var isAssetItself: Bool { guard let n = addressCheck?.normalized else { return false }; return same(n, asset.assetAddress) }
    var quantityUnits: BaseUnits? {
        let q = quantity.trimmingCharacters(in: .whitespaces)
        guard q.range(of: "^[1-9][0-9]{0,77}$", options: .regularExpression) != nil else { return nil }
        return try? BaseUnits(q)
    }

    var formProblem: String? {
        guard net != nil else { return "Le réseau de cet NFT n’est pas dans le registre lu par l’app." }
        switch addressCheck {
        case nil: return "Entrez l’adresse du destinataire."
        case .invalid(let r): return SendFlow.text(r)
        case .unverifiable, .valid: break
        }
        if isOwnAddress { return "La destination est l’adresse de ce portefeuille." }
        if isAssetItself { return "La destination est le contrat (ou le mint) de l’NFT lui-même : il serait perdu." }
        if isMultiUnit {
            guard let q = quantityUnits else { return "Quantité invalide : un entier d’au moins 1." }
            if let held = asset.quantityUnits, q > held { return "Quantité supérieure aux \(asset.quantity) unité(s) détenue(s)." }
            if let max = verdict?.signer.maxErc1155Quantity, let m = try? BaseUnits(max), q > m { return "La politique du signataire limite un transfert ERC-1155 à \(max) unité(s)." }
        }
        return nil
    }

    func prepare() async {
        guard formProblem == nil, model.canOperate, step == .form else { return }
        error = nil; step = .preparing
        let destination = addressCheck?.normalized ?? trimmedTo
        let units = isMultiUnit ? (quantityUnits?.description ?? "1") : "1"
        let fingerprint = "\(asset.key)|\(destination)|\(units)"
        if idempotency?.fingerprint != fingerprint { idempotency = (APIClient.newIdempotencyKey(), fingerprint) }
        do {
            let request = try NFTTransferRequest(item: asset, to: destination, quantity: units)
            // the Core compares the intent with this request field by field and binds it to the challenge before anything is returned
            let a = try await api.prepareTransfer(request, idempotencyKey: idempotency!.key)
            guard a.transfer.state == .pendingApproval || a.transfer.state == .draft else {
                idempotency = nil
                throw APIError(status: 409, code: "bad_state", message: "Cette demande a déjà été traitée (\(ErrorText.state(a.transfer.state))). Préparez-la de nouveau.")
            }
            approval = a; step = .review
        } catch {
            if case ApprovalError.expired = error { idempotency = nil }
            self.error = model.describe(error); step = .form
        }
    }

    func approve() async {
        guard let a = approval, step == .review else { return }
        error = nil; step = .approving
        do {
            let t = try await api.approveTransfer(a, with: model.authenticator)
            idempotency = nil
            begin(tracking: t)
        } catch PasskeyError.cancelled { step = .review }
        catch let e as APIError where e.isOffline {
            // the answer was lost: the approval may have reached the signer — never sign twice, read the proposal instead
            self.error = "Réponse perdue pendant l’approbation. Lecture de l’état réel du transfert…"
            await recover(a)
        }
        catch {
            self.error = model.describe(error)
            await recover(a)
        }
    }

    private func recover(_ a: NFTTransferApproval) async {
        if let t = try? await api.transfer(id: a.transfer.id), t.state != .pendingApproval, t.state != .draft { idempotency = nil; begin(tracking: t) }
        else { step = .review }
    }

    func reject() async {
        guard let a = approval, step == .review else { return }
        do { _ = try await api.rejectTransfer(id: a.transfer.id) } catch { self.error = model.describe(error) }
        idempotency = nil; approval = nil; step = .form
    }

    private func begin(tracking t: NFTTransfer) {
        tracked = t; history = [(Date(), t.state)]; step = .tracking; changed = true
        Task { await model.refreshActivity() }
        if t.state.isTerminal { Notifier.proposal(t.proposal); return }
        trackTask?.cancel()
        trackTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let current = self.tracked, !current.state.isTerminal else { return }
                try? await Task.sleep(for: .seconds(current.state == .broadcast || current.state == .confirming ? 5 : 2))
                guard !Task.isCancelled, AppActivity.isActive else { continue }
                guard let t = try? await self.api.transfer(id: current.id) else { continue }
                if t.state != self.tracked?.state {
                    self.history.append((Date(), t.state))
                    if t.state.isTerminal { Notifier.proposal(t.proposal); await self.model.refreshAll() }
                }
                self.tracked = t
            }
        }
    }

    func stop() { trackTask?.cancel(); trackTask = nil }
}

// MARK: - Review of the verified intent

enum NFTIntentReview {
    /// Every field of the verified NFT intent, in reading order. Nothing is abbreviated and nothing comes from the server's summary.
    static func lines(_ i: NFTIntent, network n: SPWalletCore.Network?) -> [ReviewLine] {
        var out: [ReviewLine] = []
        let feeSymbol = n?.native.symbol ?? "(monnaie native)"
        let fee: String = n.map { Fmt.amount(i.maxFeeUnits.formatted(decimals: $0.native.decimals)) } ?? "\(i.maxFee) unités de base"
        out.append(.init(label: "Type d’opération", value: "Transfert d’un NFT (\(i.kind), version \(i.v))", style: .strong))
        out.append(.init(label: "Réseau", value: "\(n?.name ?? i.network)  (\(i.network), \(i.chainRef))"))
        out.append(.init(label: "Standard", value: NFTText.standard(NFTStandard(rawValue: i.standard.rawValue)), style: .strong))
        out.append(.init(label: "Appel effectué", value: i.standard.method))
        out.append(.init(label: i.standard.isEVM ? "Contrat du jeton" : i.standard == .metaplexCore ? "Adresse de l’actif" : "Mint", value: i.asset, style: .address))
        if let t = i.tokenId { out.append(.init(label: "Identifiant du jeton", value: t, style: .address)) }
        else { out.append(.init(label: "Identifiant du jeton", value: "Sans objet : sur Solana l’adresse ci-dessus est l’identité de l’NFT.")) }
        out.append(.init(label: "Quantité envoyée", value: i.standard == .erc1155 ? "\(Fmt.amount(i.quantity)) unité(s) de cet identifiant ERC-1155" : i.quantity, style: .strong))
        out.append(.init(label: i.standard.isEVM ? "Contrat appelé" : "Programme appelé", value: i.program, style: .address))
        out.append(.init(label: "Depuis", value: i.from, style: .address))
        out.append(.init(label: "Destinataire", value: i.to, style: .address))
        out.append(.init(label: "Frais de réseau maximum", value: "\(fee) \(feeSymbol)", style: .strong))
        out.append(.init(label: "Expiration de l’approbation", value: Fmt.dateSeconds(i.expiry)))
        if let e = i.evm { out.append(.init(label: "Paramètres EVM", value: "nonce \(e.nonce) · gaz \(e.gasLimit) · max \(e.maxFeePerGas) wei/gaz · priorité \(e.maxPriorityFeePerGas)")) }
        if let s = i.sol {
            out.append(.init(label: "Paramètres Solana", value: "blockhash \(s.recentBlockhash) · valide jusqu’au bloc \(s.lastValidBlockHeight) · \(s.computeUnitLimit) CU à \(s.computeUnitPrice) µlamports" + (s.tokenProgram.map { " · programme de jetons : \($0)" } ?? "")))
            if s.createAta == true { out.append(.init(label: "Compte créé", value: "La transaction crée d’abord le compte de jetons associé du destinataire : un loyer (rent) y est immobilisé, à vos frais.", style: .warning)) }
            if let r = s.ruleSet { out.append(.init(label: "Jeu de règles (pNFT)", value: r, style: .address)) }
            if let c = s.collection { out.append(.init(label: "Collection (Core)", value: c, style: .address)) }
        }
        out.append(.init(label: "Clé du portefeuille", value: i.keyId))
        out.append(.init(label: "Politique du signataire", value: "version \(i.policyVersion) · politique NFT version \(i.nftPolicyVersion)"))
        return out
    }

    static func toKind(_ k: String) -> String {
        switch k { case "account": "un compte ordinaire"; case "contract": "un CONTRAT"; case "new_account": "un compte qui n’existe pas encore sur ce réseau"; default: k }
    }
}

// MARK: - Sheet

struct NFTTransferSheet: View {
    let model: AppModel
    let gallery: NFTGallery
    let asset: NFTAsset
    let verdict: NFTTransferVerdictAnswer?
    /// `true` when something was approved (the caller reads the item again).
    let close: (Bool) -> Void
    @State private var flow: NFTTransferFlow?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let flow {
                switch flow.step {
                case .form, .preparing: form(flow)
                case .review, .approving: if let a = flow.approval { review(flow, a) }
                case .tracking: tracking(flow)
                }
            } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .frame(width: 760, height: 800)
        .interactiveDismissDisabled()
        .task { if flow == nil { flow = NFTTransferFlow(model: model, asset: asset, verdict: verdict) } }
        .onDisappear { flow?.stop() }
    }

    private func header(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                NFTThumbView(mediaId: (asset.media.first { $0.role == "image" } ?? asset.media.first)?.id, kind: (asset.media.first { $0.role == "image" } ?? asset.media.first)?.kind,
                             pixels: NFTMediaStore.gridPixels, api: gallery.mediaAPI, maxBytes: gallery.mediaLimit).frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.title2.weight(.semibold))
                    NFTPlain("\(NFTClean.line(asset.displayName, max: 80) ?? "NFT sans nom") · \(gallery.networkName(asset.chainId)) — nom et image déclarés par le créateur, non vérifiés").font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
            }.padding(20)
            Divider()
        }
    }

    // MARK: form

    private func form(_ flow: NFTTransferFlow) -> some View {
        @Bindable var flow = flow
        return VStack(alignment: .leading, spacing: 0) {
            header("Envoyer cet NFT")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !model.canOperate { Banner(.warning, "Envoi impossible pour l’instant : session ou portefeuille indisponible.") }
                    if verdict?.broadcast == false { Banner(.warning, "SERVEUR DE TEST — il signe mais ne diffuse pas : rien ne quittera le portefeuille.") }
                    Card("Ce qui sera envoyé") {
                        Field(label: "Standard", value: NFTText.standard(asset.standard))
                        if let c = asset.contractAddress { Field(label: "Contrat", value: c, mono: true) }
                        if let m = asset.mintAddress { Field(label: "Mint / actif", value: m, mono: true) }
                        if let t = asset.tokenId { Field(label: "Identifiant du jeton", value: t, mono: true) }
                        Field(label: "Quantité détenue", value: Fmt.amount(asset.quantity))
                    }
                    Card("Destination") {
                        Form {
                            TextField("Destinataire", text: $flow.to, prompt: Text(verbatim: "Adresse sur \(flow.net?.name ?? asset.chainId)"), axis: .vertical).font(Theme.monoSmall).lineLimit(1...3)
                            addressFeedback(flow)
                            if flow.isMultiUnit {
                                TextField("Quantité (unités de cet identifiant ERC-1155)", text: $flow.quantity)
                                LabeledContent("") { Button("Tout (\(asset.quantity))") { flow.quantity = asset.quantity }.buttonStyle(.link) }
                            } else {
                                LabeledContent("Quantité") { Text("1 — ce standard s’envoie à l’unité") }
                            }
                        }.formStyle(.grouped).scrollDisabled(true).disabled(flow.step != .form)
                        if verdict?.signer.allowlistOnly == true {
                            Banner(.info, "La politique du signataire ne signe les transferts de NFT que vers les destinations de sa liste autorisée (« Contrôles du signataire »). Une autre destination sera refusée.")
                        }
                    }
                    ForEach(verdict?.warnings ?? asset.capabilities.transferWarnings ?? [], id: \.self) { w in Banner(.warning, NFTText.warning(w)) }
                    Text("Préparer ne signe rien et n’envoie rien : le serveur relit la propriété et le standard sur chaque point d’accès, simule le transfert, calcule les frais et vérifie la politique du signataire. L’envoi n’a lieu qu’après votre approbation par passkey sur l’écran suivant. Un NFT envoyé ne peut pas être récupéré.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(20)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if let e = flow.error { Banner(.danger, e) }
                HStack {
                    Button("Annuler") { close(flow.changed) }.disabled(flow.step == .preparing)
                    if let p = flow.formProblem, !flow.to.isEmpty { Text(p).foregroundStyle(.secondary).font(.callout).lineLimit(2) }
                    Spacer()
                    if flow.step == .preparing { ProgressView().controlSize(.small); Text("Relecture de la chaîne, simulation, frais…").font(.callout).foregroundStyle(.secondary) }
                    Button("Préparer et vérifier…") { Task { await flow.prepare() } }.buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(flow.formProblem != nil || !model.canOperate || flow.step != .form)
                }
            }.padding(16)
        }
    }

    @ViewBuilder private func addressFeedback(_ flow: NFTTransferFlow) -> some View {
        switch flow.addressCheck {
        case .valid(let n):
            let bad = flow.isOwnAddress || flow.isAssetItself
            LabeledContent("") {
                Label { NFTPlain(flow.isOwnAddress ? "C’est l’adresse de ce portefeuille" : flow.isAssetItself ? "C’est le contrat de l’NFT lui-même" : n == flow.trimmedTo ? "Adresse valide pour ce réseau" : "Valide — forme normalisée : \(n)") } icon: { Image(systemName: bad ? "xmark.circle" : "checkmark.circle") }
                    .foregroundStyle(bad ? Theme.negative : Theme.positive).font(.callout)
            }
        case .invalid(let r):
            LabeledContent("") {
                VStack(alignment: .leading) {
                    Label(SendFlow.text(r), systemImage: "xmark.circle").foregroundStyle(Theme.negative).font(.callout)
                    if !flow.otherNetworks.isEmpty { NFTPlain("Cette adresse est valide sur : \(flow.otherNetworks.map(\.name).joined(separator: ", ")). Un NFT n’existe que sur son réseau.").font(.caption).foregroundStyle(Theme.warning) }
                }
            }
        case .unverifiable: LabeledContent("") { Label("Format non vérifiable par cette version de l’app : le serveur validera l’adresse.", systemImage: "questionmark.circle").foregroundStyle(Theme.warning).font(.callout) }
        case nil: EmptyView()
        }
    }

    // MARK: review

    private func review(_ flow: NFTTransferFlow, _ a: NFTTransferApproval) -> some View {
        let i = a.intent
        return VStack(alignment: .leading, spacing: 0) {
            header("Vérifier et approuver l’envoi de l’NFT")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if verdict?.broadcast == false { Banner(.warning, "SERVEUR DE TEST — la transaction sera signée mais NON diffusée.") }
                    if a.replayed { Banner(.info, "Cette préparation avait déjà été faite : le serveur a répondu la même proposition et le même défi.") }
                    ForEach(a.transfer.proposal.warnings ?? a.review?.warnings ?? [], id: \.self) { w in Banner(w == "address_poisoning_suspected" ? .danger : .warning, NFTText.warning(w)) }
                    Text("Ce que votre passkey va signer").font(.headline)
                    ReviewLines(lines: NFTIntentReview.lines(i, network: model.network(i.network)))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Adresse du destinataire, par groupes de 4 caractères").font(.caption).foregroundStyle(.secondary)
                        NFTPlain(Fmt.chunked(i.to)).font(.system(.title3, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    if let r = a.review { serverChecks(r) }
                    Banner(.warning, "Un NFT envoyé est irréversible : une adresse erronée, un mauvais réseau ou un contrat qui ne sait pas le restituer signifient sa perte définitive.")
                    Text("Le signataire isolé reconstruit la transaction à partir des seuls champs ci-dessus et applique sa politique NFT (réseau et standard autorisés, plafond quotidien, liste de destinations, plafond de frais). Il ne lit pas la chaîne : il ne vérifie ni que ce portefeuille détient l’NFT, ni le standard du contrat. Ces deux points ont été établis par le serveur, comme indiqué ci-dessus, et la chaîne refusera un transfert que ce portefeuille ne peut pas faire.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    BindingProof(digest: a.approval.digest, expiry: i.expiry)
                }.padding(20)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if let e = flow.error { Banner(.danger, e) }
                HStack {
                    Button("Rejeter", role: .destructive) { Task { await flow.reject() } }.disabled(flow.step == .approving)
                    Spacer()
                    if flow.step == .approving { ProgressView().controlSize(.small); Text("Passkey, puis signature isolée…").foregroundStyle(.secondary) }
                    Button { Task { await flow.approve() } } label: { Label("Approuver avec la passkey", systemImage: "touchid") }
                        .buttonStyle(.borderedProminent).controlSize(.large).disabled(flow.step == .approving)
                }
            }.padding(16)
        }
    }

    /// The server's own account of what it read and simulated. Shown apart: it is not what the passkey signs.
    private func serverChecks(_ r: NFTReview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ce que le serveur déclare avoir vérifié et simulé (non signé)").font(.headline)
            Field(label: "Standard établi", value: r.verified.standard)
            Field(label: "Propriété établie", value: r.verified.ownership)
            Field(label: "Points d’accès concordants", value: "\(r.verified.endpoints)\(r.verified.at.map { " — le \(Fmt.dateSeconds($0))" } ?? "")")
            Field(label: "Nature de la destination", value: NFTIntentReview.toKind(r.toKind), emphasis: r.toKind != "account")
            Field(label: "Simulation", value: "\(r.simulation.ok ? "réussie" : "ÉCHEC") — \(r.simulation.detail)\(r.simulation.used.map { " (consommé : \($0))" } ?? "")", emphasis: !r.simulation.ok)
            ForEach(Array(r.simulation.changes.enumerated()), id: \.offset) { _, c in
                Field(label: "Effet simulé", value: "\(c.what) : \(c.before) → \(c.after)")
            }
            Field(label: "Frais estimés", value: "\(r.fee.estimateDisplay.map { Fmt.amount($0) } ?? r.fee.estimate) \(r.fee.symbol) (estimation ; le plafond signé est plus haut)")
            if let rent = r.fee.rent, rent != "0" {
                Field(label: "Loyer immobilisé", value: "\((try? BaseUnits(rent))?.formatted(decimals: r.fee.decimals) ?? rent) \(r.fee.symbol) — placé dans le compte créé pour le destinataire, pas un frais de réseau", emphasis: true)
            }
            if !r.accounts.isEmpty {
                Field(label: "Comptes de l’instruction", value: r.accounts.map { "\($0.role) : \($0.address) (\($0.derived))" }.joined(separator: "\n"), mono: true)
            }
            if let c = r.creatorMetadata, c.name != nil || c.collectionName != nil {
                NFTPlain("Déclaré par le créateur, NON vérifié, sans effet sur la transaction : \(NFTClean.line(c.name, max: 80) ?? "sans nom")\(NFTClean.line(c.collectionName, max: 80).map { " · collection « \($0) »" } ?? "")").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: tracking

    private func tracking(_ flow: NFTTransferFlow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Suivi du transfert")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let e = flow.error { Banner(.warning, e) }
                    if let t = flow.tracked {
                        Card {
                            ProposalStatusView(proposal: t.proposal)
                            if let r = t.review {
                                Field(label: r.standard.isEVMStandard ? "Contrat" : "Mint / actif", value: r.asset, mono: true)
                                if let id = r.tokenId { Field(label: "Identifiant du jeton", value: id, mono: true) }
                            }
                            Divider()
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Historique des états").font(.caption).foregroundStyle(.secondary)
                                ForEach(Array(flow.history.enumerated()), id: \.offset) { _, h in
                                    HStack { Text(Fmt.dateSeconds(h.0)).monospacedDigit().foregroundStyle(.secondary); Text(ErrorText.state(h.1)) }.font(.callout)
                                }
                            }
                        }
                        if !t.state.isTerminal { Text("Le transfert n’est acquis qu’à l’état « Finalisée ». Vous pouvez fermer cette fenêtre : le serveur poursuit le suivi, visible dans l’historique de la fiche et dans Activité.").font(.caption).foregroundStyle(.secondary) }
                    }
                }.padding(20)
            }
            Divider()
            HStack { Spacer(); Button("Fermer") { close(flow.changed) }.keyboardShortcut(.defaultAction) }.padding(16)
        }
    }
}

private extension NFTStandard {
    var isEVMStandard: Bool { rawValue == "erc721" || rawValue == "erc1155" || rawValue == "evm-nonstandard" }
}
