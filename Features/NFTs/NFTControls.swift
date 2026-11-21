// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Features/NFTs/NFTControls.swift
// Description      : The two pieces of signer state that guard NFTs, each
//                    changed only through a passkey approval of a verified
//                    object: the list of destinations allowed to receive NFTs
//                    (and whether the signer's policy restricts transfers to
//                    it), and the Bitcoin-style outpoint lock list that keeps
//                    outputs which may carry inscriptions out of ordinary
//                    sends. Every change is prepared by the server, bound by
//                    the Core to its challenge, reviewed field by field, then
//                    approved. The heuristic "ordinary coin" declaration needs
//                    no passkey because it never lifts a signer lock — and the
//                    screen says so.
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

@MainActor @Observable final class NFTControls {
    enum Pending { case allow(NFTAllowApproval), locks(UTXOLockApproval) }
    enum Step: Equatable { case idle, preparing, review, approving }

    let model: AppModel
    let api: NFTAPI

    private(set) var allow: NFTAllowList?
    private(set) var allowError: String?
    private(set) var locks: UTXOLocksView?
    private(set) var locksError: String?
    private(set) var loadingLocks = false
    var locksNetwork = ""

    private(set) var pending: Pending?
    private(set) var step: Step = .idle
    var error: String?
    var result: String?

    init(model: AppModel) { self.model = model; api = NFTAPI(model.client) }

    func loadAllow() async {
        guard model.phase == .signedIn else { return }
        do { allow = try await api.allowList(); allowError = nil } catch { allowError = model.describe(error) }
    }

    func loadLocks() async {
        guard model.phase == .signedIn, !locksNetwork.isEmpty, !loadingLocks else { return }
        loadingLocks = true; defer { loadingLocks = false }
        do {
            let v = try await api.utxoLocks(network: locksNetwork)
            guard v.network == locksNetwork else { return }
            locks = v; locksError = nil
        } catch { locks = nil; locksError = model.describe(error) }
    }

    func prepareAllow(network: String, address: String, action: NFTAllowIntent.Action) async {
        guard model.canOperate, step == .idle else { return }
        step = .preparing; error = nil; result = nil
        do { pending = .allow(try await api.prepareAllowChange(NFTAllowRequest(network: network, address: address, action: action))); step = .review }
        catch { self.error = model.describe(error); step = .idle }
    }

    func prepareLocks(action: UTXOLockIntent.Action, outpoints: [String]) async {
        guard model.canOperate, step == .idle, !outpoints.isEmpty, !locksNetwork.isEmpty else { return }
        step = .preparing; error = nil; result = nil
        do { pending = .locks(try await api.prepareUTXOLocks(UTXOLockRequest(network: locksNetwork, action: action, reason: .owner, outpoints: outpoints))); step = .review }
        catch { self.error = model.describe(error); step = .idle }
    }

    func approve() async {
        guard let p = pending, step == .review else { return }
        step = .approving; error = nil
        do {
            switch p {
            case .allow(let a):
                let r = try await api.approveAllowChange(a, with: model.authenticator)
                result = "Liste des destinations modifiée par le signataire (\(r.action == "add" ? "ajout" : r.action == "remove" ? "retrait" : r.action) de \(r.address) sur \(r.network)) : \(r.entries) entrée(s) désormais. Empreinte acceptée : \(r.hash)"
            case .locks(let l):
                let r = try await api.approveUTXOLocks(l, with: model.authenticator)
                result = "Liste de verrous modifiée par le signataire sur \(r.network) : \(r.changed) sortie(s) changée(s), \(r.locked) verrouillée(s) désormais. Empreinte acceptée : \(r.hash)"
            }
            pending = nil; step = .idle
        } catch PasskeyError.cancelled { step = .review; return }
        catch {
            // whatever happened, the lists below are read again from the signer: they show the real state, nothing is assumed
            self.error = model.describe(error) + " — l’état réel est relu ci-dessous."
            pending = nil; step = .idle
        }
        async let a: Void = loadAllow()
        async let b: Void = loadLocks()
        _ = await (a, b)
    }

    func cancel() { guard step != .approving else { return }; pending = nil; step = .idle }

    /// No passkey: this only tells the server's coin selection that the owner looked at a HEURISTICALLY flagged output.
    func declare(outpoint: String, ordinary: Bool) async {
        guard model.canOperate, !locksNetwork.isEmpty else { return }
        error = nil
        do { _ = try await api.reviewUTXO(network: locksNetwork, outpoint: outpoint, ordinary: ordinary); await loadLocks() } catch { self.error = model.describe(error) }
    }
}

struct NFTControlsPage: View {
    let model: AppModel
    let gallery: NFTGallery
    let back: () -> Void
    @State private var controls: NFTControls?

    var body: some View {
        Page("Contrôles NFT du signataire", subtitle: "État tenu par le signataire isolé. Chaque modification est approuvée par votre passkey sur l’objet exact, vérifié par cette app.") {
            NFTBackBar(title: "Galerie", back: back)
            if !model.canOperate { Banner(.warning, "Session ou portefeuille indisponible : consultation seule, aucune modification possible.") }
            if let c = controls {
                if let e = c.error { Banner(.danger, e) }
                if let r = c.result { Banner(.ok, r) }
                NFTAllowCard(model: model, gallery: gallery, controls: c)
                NFTLocksCard(model: model, controls: c)
            } else { ProgressView() }
        }
        .task {
            if controls == nil {
                let c = NFTControls(model: model)
                c.locksNetwork = (model.networks?.value ?? []).first { $0.family == "btc" }?.id ?? ""
                controls = c
            }
            async let a: Void? = controls?.loadAllow()
            async let b: Void? = controls?.loadLocks()
            _ = await (a, b)
        }
        .sheet(isPresented: Binding(get: { controls?.step == .review || controls?.step == .approving }, set: { _ in })) {
            if let c = controls, let p = c.pending { NFTControlsReview(model: model, controls: c, pending: p) }
        }
    }
}

// MARK: - Destination allow-list

private struct NFTAllowCard: View {
    let model: AppModel
    let gallery: NFTGallery
    let controls: NFTControls
    @State private var network = ""
    @State private var address = ""

    /// The allow-list exists on EVM networks and Solana (families of the server's registry), where the server prepares NFT transfers.
    private var networks: [SPWalletCore.Network] {
        (model.networks?.value ?? []).filter { n in (n.family == "evm" || n.family == "sol") && (gallery.capabilities?.chain(n.id)?.canPrepareTransfers ?? true) }
    }
    private var check: AddressCheck? {
        guard let n = model.network(network), !address.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return AddressValidator.check(address, network: n)
    }
    private var problem: String? {
        guard !network.isEmpty else { return "Choisissez un réseau." }
        switch check {
        case nil: return "Entrez l’adresse à autoriser."
        case .invalid(let r): return SendFlow.text(r)
        case .valid(let n): return n == model.address(on: network) ? "C’est l’adresse de ce portefeuille." : nil
        case .unverifiable: return nil
        }
    }

    var body: some View {
        Card("Destinations autorisées à recevoir des NFT") {
            if let e = controls.allowError { Banner(.danger, e) }
            if let a = controls.allow {
                if !a.supported { Banner(.warning, "La version du signataire ne prend pas en charge les transferts de NFT : cette liste n’existe pas encore.") }
                Banner(a.allowlistOnly ? .info : .warning, a.allowlistOnly
                       ? "Mode liste imposée : le signataire ne signe un transfert de NFT que vers une destination de cette liste."
                       : "Mode liste non imposée : le signataire signe un transfert de NFT vers toute destination valide ; cette liste n’est alors qu’un registre. Le mode se règle dans la politique du signataire, pas depuis cette app.")
                if a.entries.isEmpty { Text("Aucune destination dans la liste.").foregroundStyle(.secondary) }
                ForEach(a.entries, id: \.self) { e in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            NFTPlain(e.address).font(Theme.monoSmall).textSelection(.enabled)
                            NFTPlain("\(gallery.networkName(e.network))\(e.approvedAt.map { " · approuvée le \(Fmt.date(Date(timeIntervalSince1970: TimeInterval($0))))" } ?? "")").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Retirer…", role: .destructive) { Task { await controls.prepareAllow(network: e.network, address: e.address, action: .remove) } }
                            .disabled(!model.canOperate || controls.step != .idle || !a.supported)
                    }
                    Divider()
                }
                Text("Ajouter une destination").font(.subheadline.weight(.medium))
                HStack(alignment: .firstTextBaseline) {
                    Picker("Réseau", selection: $network) {
                        Text("Réseau…").tag("")
                        ForEach(networks) { NFTPlain($0.name).tag($0.id) }
                    }.labelsHidden().frame(width: 200)
                    TextField("Adresse", text: $address).font(Theme.monoSmall).textFieldStyle(.roundedBorder)
                    if controls.step == .preparing { ProgressView().controlSize(.small) }
                    Button("Préparer l’ajout…") { Task { await controls.prepareAllow(network: network, address: check?.normalized ?? address, action: .add) } }
                        .disabled(problem != nil || !model.canOperate || controls.step != .idle || !a.supported)
                }
                if let p = problem, !address.isEmpty { Text(p).font(.callout).foregroundStyle(Theme.negative) }
                else if case .unverifiable = check { Text("Format non vérifiable par cette version de l’app : le serveur validera l’adresse.").font(.callout).foregroundStyle(Theme.warning) }
                Text("Autoriser une destination donne au signataire le droit de signer des transferts de NFT vers elle : vérifiez chaque caractère sur l’écran d’approbation.").font(.caption).foregroundStyle(.secondary)
            } else if controls.allowError == nil {
                if model.phase == .signedIn { ProgressView().controlSize(.small) } else { Text("Indisponible hors connexion : cet état n’est lu que sur le signataire.").foregroundStyle(.secondary) }
            }
        }
    }
}

// MARK: - Outpoint locks

private struct NFTLocksCard: View {
    let model: AppModel
    @Bindable var controls: NFTControls
    @State private var selection = Set<String>()

    private var networks: [SPWalletCore.Network] { (model.networks?.value ?? []).filter { $0.family == "btc" } }

    static func reason(_ code: String) -> String {
        switch code {
        case "signer_locked": "verrouillée sur le signataire"
        case "ord_inscription": "inscription rapportée par le serveur ord"
        case "ord_rune": "rune rapportée par le serveur ord"
        case "ord_unindexed": "pas encore indexée par le serveur ord"
        case "ord_unlisted": "inconnue du serveur ord"
        case "ord_unavailable": "serveur ord injoignable : rien n’est dépensable"
        case "heuristic_small": "petite valeur (heuristique, pas une détection)"
        case "heuristic_envelope": "enveloppe d’inscription dans la transaction (heuristique)"
        default: code
        }
    }
    static func mode(_ m: String) -> String {
        switch m {
        case "ord": "Un serveur ord décide de ce qui porte une inscription ou une rune."
        case "heuristic": "Aucun serveur ord : seuls des indices (taille, enveloppe) signalent des sorties. Ce n’est PAS une détection d’inscriptions."
        case "locks_only": "Seuls les verrous du signataire protègent des sorties."
        case "ord_unavailable": "Le serveur ord configuré ne répond pas : par prudence, aucune sortie n’est dépensable par un envoi ordinaire."
        default: m
        }
    }

    var body: some View {
        Card("Verrous de sorties (réseaux de type Bitcoin)", trailing: controls.loadingLocks ? AnyView(ProgressView().controlSize(.small)) : nil) {
            Text("Une sortie verrouillée n’est jamais dépensée par un envoi ordinaire : c’est ce qui protège une inscription (Ordinals) reçue à l’adresse du portefeuille. Ce portefeuille ne liste ni ne transfère aucune inscription.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if networks.isEmpty { Text("Aucun réseau de type Bitcoin dans le registre du serveur.").foregroundStyle(.secondary) }
            else {
                HStack {
                    Picker("Réseau", selection: $controls.locksNetwork) { ForEach(networks) { NFTPlain($0.name).tag($0.id) } }.labelsHidden().frame(width: 220)
                    Button { Task { await controls.loadLocks() } } label: { Label("Relire", systemImage: "arrow.clockwise") }.disabled(model.phase != .signedIn || controls.loadingLocks)
                    Spacer()
                }
                .onChange(of: controls.locksNetwork) { selection = []; Task { await controls.loadLocks() } }
            }
            if let e = controls.locksError { Banner(.danger, e) }
            if let v = controls.locks { content(v) }
            else if model.phase != .signedIn { Text("Indisponible hors connexion : cet état n’est lu que sur le signataire et la chaîne.").foregroundStyle(.secondary) }
        }
    }

    @ViewBuilder private func content(_ v: UTXOLocksView) -> some View {
        Field(label: "Adresse", value: v.address, mono: true)
        Banner(v.mode == "ord" ? .info : .warning, Self.mode(v.mode) + (v.ordHost.map { " Serveur ord : \($0)." } ?? "") + (v.ordError.map { " Erreur : \($0)." } ?? ""))
        if !v.signerSupportsLocks { Banner(.warning, "La version du signataire ne prend pas en charge les verrous de sorties : rien ne peut être verrouillé.") }
        if v.utxos.isEmpty { Text("Aucune sortie non dépensée à cette adresse.").foregroundStyle(.secondary) }
        else {
            Table(v.utxos, selection: $selection) {
                TableColumn("Sortie (txid:index)") { u in NFTPlain(u.outpoint).font(.system(.caption, design: .monospaced)).textSelection(.enabled).help(u.outpoint) }.width(min: 260, ideal: 420)
                TableColumn("Valeur") { u in NFTPlain("\(Fmt.amount(BaseUnits(UInt64(max(0, u.value))).formatted(decimals: v.decimals))) \(v.symbol)").monospacedDigit() }.width(min: 110, ideal: 130)
                TableColumn("Envoi ordinaire") { u in
                    NFTPlain(u.spendable ? (u.reviewed ? "dépensable (déclarée ordinaire)" : "dépensable") : "exclue").foregroundStyle(u.spendable ? Color.primary : Theme.warning)
                }.width(min: 110, ideal: 170)
                TableColumn("Raisons") { u in
                    let parts = u.excludedBy.map(Self.reason) + (u.signerLock.map { ["verrou « \($0.reason) » du \(Fmt.date(Date(timeIntervalSince1970: TimeInterval($0.at))))"] } ?? [])
                        + (u.ord.map { o in (o.inscriptions.isEmpty ? [] : ["\(o.inscriptions.count) inscription(s)"]) + (o.runes.isEmpty ? [] : ["runes : \(o.runes.joined(separator: ", "))"]) } ?? [])
                    NFTPlain(parts.isEmpty ? "—" : parts.joined(separator: " · ")).font(.caption).help(parts.joined(separator: "\n"))
                }
            }
            .frame(height: min(420, CGFloat(v.utxos.count) * 28 + 40))
            let chosen = v.utxos.filter { selection.contains($0.outpoint) }
            let toLock = chosen.filter { $0.signerLock == nil }.map(\.outpoint), toUnlock = chosen.filter { $0.signerLock != nil }.map(\.outpoint)
            let heuristicOnly = chosen.filter { !$0.excludedBy.isEmpty && $0.excludedBy.allSatisfy { $0.hasPrefix("heuristic_") } || $0.reviewed }
            HStack {
                Text(chosen.isEmpty ? "Sélectionnez des sorties dans le tableau." : "\(chosen.count) sortie(s) sélectionnée(s)").font(.callout).foregroundStyle(.secondary)
                Spacer()
                if controls.step == .preparing { ProgressView().controlSize(.small) }
                Button("Verrouiller (\(toLock.count))…") { Task { await controls.prepareLocks(action: .lock, outpoints: toLock) } }
                    .disabled(toLock.isEmpty || toLock.count > 100 || !model.canOperate || controls.step != .idle || !v.signerSupportsLocks)
                Button("Déverrouiller (\(toUnlock.count))…", role: .destructive) { Task { await controls.prepareLocks(action: .unlock, outpoints: toUnlock) } }
                    .disabled(toUnlock.isEmpty || toUnlock.count > 100 || !model.canOperate || controls.step != .idle || !v.signerSupportsLocks)
            }
            if let h = heuristicOnly.first, heuristicOnly.count == 1, chosen.count == 1 {
                HStack {
                    Text("Cette sortie n’est signalée que par des indices. La déclarer « monnaie ordinaire » la rend dépensable par un envoi ordinaire. Cela ne demande pas de passkey : aucun verrou du signataire ni rapport ord n’est levé ainsi.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(h.reviewed ? "Retirer la déclaration" : "Déclarer monnaie ordinaire") { Task { await controls.declare(outpoint: h.outpoint, ordinary: !h.reviewed) } }.disabled(!model.canOperate)
                }
            }
        }
        if !v.staleLocks.isEmpty {
            Divider()
            Text("Verrous sans sortie correspondante").font(.subheadline.weight(.medium))
            Text("Ces sorties ne sont plus parmi les pièces du portefeuille (dépensées ailleurs, ou jamais reçues). Les verrous peuvent être retirés.").font(.caption).foregroundStyle(.secondary)
            ForEach(v.staleLocks, id: \.self) { l in
                HStack {
                    NFTPlain(l.outpoint).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    NFTPlain("« \(l.reason) » · \(Fmt.date(Date(timeIntervalSince1970: TimeInterval(l.at))))").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Déverrouiller…") { Task { await controls.prepareLocks(action: .unlock, outpoints: [l.outpoint]) } }.controlSize(.small)
                        .disabled(!model.canOperate || controls.step != .idle || !v.signerSupportsLocks)
                }
            }
        }
        if let t = v.transfer, t != "supported" { NFTPlain("Transfert d’inscriptions : non construit\(v.transferReason.map { " — \(NFTText.blockReason($0))" } ?? "")").font(.caption).foregroundStyle(.secondary) }
    }
}

// MARK: - Review of a verified change

private struct NFTControlsReview: View {
    let model: AppModel
    let controls: NFTControls
    let pending: NFTControls.Pending

    private var title: String { switch pending { case .allow: "Vérifier la modification de la liste des destinations NFT"; case .locks: "Vérifier la modification des verrous de sorties" } }
    private var digest: Data { switch pending { case .allow(let a): a.approval.digest; case .locks(let l): l.approval.digest } }
    private var expiry: Date { switch pending { case .allow(let a): a.intent.expiry; case .locks(let l): l.intent.expiry } }

    /// The fields of the verified object, in full.
    private var lines: [ReviewLine] {
        switch pending {
        case .allow(let a):
            let i = a.intent
            return [
                .init(label: "Type d’opération", value: "Liste des destinations NFT du signataire (\(i.kind), version \(i.v))", style: .strong),
                .init(label: "Action", value: i.action == .add ? "AJOUTER cette destination" : "RETIRER cette destination", style: .strong),
                .init(label: "Réseau", value: "\(model.network(i.network)?.name ?? i.network)  (\(i.network))"),
                .init(label: "Adresse", value: i.address, style: .address),
                .init(label: "Expiration de l’approbation", value: Fmt.dateSeconds(i.expiry)),
                .init(label: "Demande", value: i.requestId),
                .init(label: "Clé du portefeuille", value: i.keyId),
                .init(label: "Politique du signataire", value: "version \(i.policyVersion)"),
            ]
        case .locks(let l):
            let i = l.intent
            return [
                .init(label: "Type d’opération", value: "Verrous de sorties du signataire (\(i.kind), version \(i.v))", style: .strong),
                .init(label: "Action", value: i.action == .lock ? "VERROUILLER ces sorties" : "DÉVERROUILLER ces sorties", style: .strong),
                .init(label: "Motif enregistré", value: i.reason.rawValue),
                .init(label: "Réseau", value: "\(model.network(i.network)?.name ?? i.network)  (\(i.network))"),
                .init(label: "Sorties (\(i.outpoints.count))", value: i.outpoints.map(\.key).joined(separator: "\n"), style: .address),
                .init(label: "Expiration de l’approbation", value: Fmt.dateSeconds(i.expiry)),
                .init(label: "Demande", value: i.requestId),
                .init(label: "Clé du portefeuille", value: i.keyId),
                .init(label: "Politique du signataire", value: "version \(i.policyVersion)"),
            ]
        }
    }
    private var consequence: (Banner.Kind, String) {
        switch pending {
        case .allow(let a) where a.intent.action == .add: (.warning, "Après cet ajout, le signataire acceptera de signer des transferts de NFT vers cette adresse. Un NFT envoyé à une mauvaise adresse est perdu : comparez chaque caractère.")
        case .allow: (.info, "Après ce retrait, si la politique impose la liste, le signataire refusera tout transfert de NFT vers cette adresse.")
        case .locks(let l) where l.intent.action == .unlock: (.warning, "Après ce déverrouillage, ces sorties pourront être dépensées par un envoi ordinaire. Si l’une d’elles porte une inscription, celle-ci partirait comme de la simple monnaie, sans retour possible.")
        case .locks: (.info, "Après ce verrouillage, le signataire refusera ces sorties comme entrées de toute transaction, jusqu’à leur déverrouillage par passkey.")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.title2.weight(.semibold)).padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Ce que votre passkey va signer").font(.headline)
                    ReviewLines(lines: lines)
                    if case .allow(let a) = pending {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Adresse, par groupes de 4 caractères").font(.caption).foregroundStyle(.secondary)
                            NFTPlain(Fmt.chunked(a.intent.address)).font(.system(.title3, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                    Banner(consequence.0, consequence.1)
                    BindingProof(digest: digest, expiry: expiry)
                }.padding(20)
            }
            Divider()
            HStack {
                Button("Annuler") { controls.cancel() }.disabled(controls.step == .approving)
                Spacer()
                if controls.step == .approving { ProgressView().controlSize(.small); Text("Passkey, puis signataire isolé…").foregroundStyle(.secondary) }
                Button { Task { await controls.approve() } } label: { Label("Approuver avec la passkey", systemImage: "touchid") }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(controls.step == .approving)
            }.padding(16)
        }
        .frame(width: 720, height: 640)
        .interactiveDismissDisabled()
    }
}
