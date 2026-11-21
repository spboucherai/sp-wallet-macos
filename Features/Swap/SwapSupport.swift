// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Features/Swap/SwapSupport.swift
// Description      : What the swap, bridge and plan screens share: French
//                    wording of the server's codes (execution steps, holds,
//                    refusals), the tracker that follows a proposal until the
//                    chain — not the client — says it is over, the asset picker
//                    fed by the server's swap graph, the review sheet of a
//                    verified operation and the unified execution timeline.
//                    Nothing here decides a success: every status is read from
//                    the proposal.
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

// MARK: - Wording

@MainActor enum SwapText {
    /// The amount as the server parses it: a point as decimal separator, no grouping.
    static func normalize(_ amount: String) -> String {
        amount.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "\u{202F}", with: "").replacingOccurrences(of: " ", with: "")
    }

    static func sameId(_ a: String, _ b: String) -> Bool { a == b || (a.hasPrefix("0x") && b.hasPrefix("0x") && a.lowercased() == b.lowercased()) }

    static func balance(_ model: AppModel, of a: SwapAsset) -> Balance? {
        model.portfolio?.value.balances.first { $0.network == a.network && sameId($0.asset, a.asset) }
    }

    /// Base units rendered with the registry's decimals; without them the raw integer is shown as such.
    static func units(_ s: String, decimals: Int?) -> String {
        guard let decimals, let u = try? BaseUnits(s) else { return "\(s) (unités de base)" }
        return Fmt.amount(u.formatted(decimals: decimals))
    }

    static func assetDef(_ model: AppModel, network: String, asset: String) -> AssetDef? {
        guard let n = model.network(network) else { return nil }
        return asset == "native" ? n.native : n.tokens.first { sameId($0.id, asset) }
    }

    static func duration(_ s: Double?) -> String {
        guard let s else { return "durée non communiquée" }
        if s < 90 { return "≈ \(max(1, Int(s.rounded()))) s" }
        if s < 5400 { return "≈ \(Int((s / 60).rounded())) min" }
        return "≈ \((s / 3600).formatted(.number.precision(.fractionLength(1)))) h"
    }

    static func bps(_ b: Double?) -> String {
        guard let b else { return "—" }
        return (b / 100).formatted(.number.precision(.fractionLength(0...2))) + " %"
    }
    static func bps(_ b: Int?) -> String { bps(b.map(Double.init)) }

    static func usd(_ v: Double?) -> String {
        guard let v else { return "—" }
        return "≈ " + v.formatted(.currency(code: "USD").precision(.fractionLength(abs(v) < 1 && v != 0 ? 4 : 2)))
    }

    /// Display name of a provider: the server's own name; Jupiter keeps the label its licence requires.
    static func provider(_ id: String, providers: SwapProviders?, execution: SwapExecutionInfo? = nil) -> String {
        if let s = execution?.solana, s.provider == id { return s.label }
        return providers?.providers.first { $0.id == id }?.name ?? id
    }

    static func execState(_ s: ExecState) -> String {
        switch s {
        case .pending: "En attente"
        case .awaitingApproval: "En attente d’approbation"
        case .signing: "Signature en cours"
        case .broadcast: "Diffusée, non confirmée"
        case .confirming: "En cours de confirmation"
        case .confirmed: "Confirmée"
        case .failed: "Échouée"
        case .refunded: "Remboursée"
        case .unknown: "État inconnu"
        default: s.rawValue
        }
    }

    static func stepKind(_ k: String) -> String {
        switch k {
        case "approval": "Autorisation de dépense (ERC-20)"
        case "send": "Envoi"
        case "swap": "Échange"
        case "burn": "Destruction (burn) sur le réseau source"
        case "attestation": "Attestation de Circle"
        case "mint": "Émission (mint) sur le réseau de destination"
        case "deposit": "Dépôt au coffre THORChain"
        case "observation": "Observation du dépôt par THORChain"
        case "outbound": "Paiement sortant vers ce portefeuille"
        case "order": "Ordre"
        default: k
        }
    }

    static func bridgeStage(_ s: BridgeStage) -> String {
        switch s {
        case .review: "En attente d’approbation"
        case .burning: "Destruction (burn) en cours sur le réseau source"
        case .attesting: "Brûlé sur la source — attestation de Circle en attente"
        case .ready: "Attesté — émission sur la destination à lancer"
        case .minting: "Émission (mint) diffusée sur la destination, non confirmée"
        case .mintFailed: "Émission échouée — nouvelle signature requise (passkey)"
        case .done: "Reçu sur le réseau de destination"
        case .failed: "Échoué avant la destruction : rien n’a quitté le réseau source"
        default: s.rawValue
        }
    }

    static func xswapStage(_ s: XSwapStage) -> String {
        switch s {
        case .review: "En attente d’approbation"
        case .sending: "Dépôt en cours d’envoi au coffre"
        case .sent: "Dépôt diffusé — pas encore observé par THORChain"
        case .observed: "Dépôt observé par THORChain — échange en cours"
        case .outbound: "Paiement sortant annoncé — pas encore vu par ce portefeuille"
        case .received: "Reçu sur le réseau de destination"
        case .refunded: "Remboursé par THORChain : l’échange n’a pas eu lieu"
        case .failed: "Échoué"
        default: s.rawValue
        }
    }

    /// Why an operation is waiting. The server's own detail sentence is shown next to it, untouched.
    static func hold(_ code: String) -> String {
        switch code {
        case "destination_busy": "Une autre transaction est en vol sur le réseau de destination."
        case "destination_pending": "Une transaction précédente est encore en attente sur le réseau de destination."
        case "mint_would_fail": "L’émission échouerait maintenant sur la destination ; elle n’a pas été envoyée."
        case "fee_above_policy": "Les frais de réseau sur la destination dépassent le plafond du signataire pour l’instant."
        case "destination_gas": "Il manque de la monnaie native sur la destination pour payer l’émission."
        case "attestation_late": "Circle n’a pas encore attesté la destruction. Les fonds ne sont pas perdus : l’émission reste possible dès que l’attestation arrive."
        case "message_mismatch": "La réponse de Circle ne décrit pas le transfert approuvé ; elle n’a pas été utilisée."
        case "attestation_expired": "L’attestation rapide a expiré ; une nouvelle a été demandée à Circle."
        case "mint_reverted": "La transaction d’émission a été annulée (revert) sur la destination ; les USDC attendent toujours. Approuvez une nouvelle tentative avec la passkey."
        case "mint_replaced": "Une autre transaction a pris la place de l’émission ; les USDC attendent toujours. Approuvez une nouvelle tentative avec la passkey."
        case "mint_expired": "L’émission n’a pas été incluse à temps ; les USDC attendent toujours. Approuvez une nouvelle tentative avec la passkey."
        case "vault_churned": "Le coffre n’est plus confirmé comme actif et le dépôt n’est pas encore confirmé. Il ne peut pas être annulé ; THORChain surveille encore un coffre sortant, sans garantie."
        case "not_observed": "THORChain n’a pas encore signalé ce dépôt. Rien n’est marqué comme reçu tant que le portefeuille ne voit pas lui-même le paiement sortant."
        case "outbound_late": "THORChain a observé le dépôt mais n’a pas encore envoyé le paiement sortant."
        case "outbound_mismatch": "Le paiement sortant annoncé par THORChain ne paie pas à ce portefeuille ce qui était attendu ; il n’est pas compté comme reçu."
        case "below_minimum": "Le montant reçu est inférieur au minimum approuvé."
        case "outbound_not_seen": "THORChain annonce un paiement sortant que les sources de données du portefeuille ne voient pas encore confirmé."
        default: "En attente (\(code))."
        }
    }

    /// Why the wallet does not execute a quoted route (`RouteCard.reasonCode` / `executability`).
    static func notExecutable(_ r: SwapRoute) -> String {
        let code = r.card?.reasonCode ?? r.executability?.code ?? r.executability?.class
        switch code {
        case "quote_only": return "Comparaison de prix seulement : ce fournisseur ne fournit qu’une cotation."
        case "opaque", "opaque_transaction": return "Comparaison seulement : la transaction de ce fournisseur est opaque, le signataire ne peut pas en vérifier le destinataire ni le minimum."
        case "not_executable": return "Comparaison seulement : ce portefeuille n’exécute pas cette route."
        case nil: return "Comparaison seulement."
        case let c?: return "Comparaison seulement (\(c))" + (r.executability?.reason.map { " — \($0)" } ?? "")
        }
    }

    static func providerAnswer(_ a: SwapProviderAnswer) -> String {
        switch (a.status, a.code) {
        case ("no_route", _): "aucune route"
        case ("skipped", "not_configured"): "non interrogé (clé d’API non configurée sur le serveur)"
        case ("skipped", "disabled"): "non interrogé (désactivé)"
        case ("skipped", let c): "non interrogé" + (c.map { " (\($0))" } ?? "")
        case ("error", "timeout"): "délai dépassé"
        case ("error", "rate_limited"): "limite de débit atteinte"
        case ("error", "invalid_quote"): "cotation invalide, écartée"
        case ("error", let c): "erreur" + (c.map { " (\($0))" } ?? "")
        default: a.status + (a.code.map { " (\($0))" } ?? "")
        }
    }

    static func risk(_ l: RiskLevel?) -> String {
        switch l { case .some(.low): "faible"; case .some(.medium): "moyen"; case .some(.high): "élevé"; case .some(let o): o.rawValue; case nil: "—" }
    }

    private static let explanations: [String: String] = [
        "policy": "Refus du signataire isolé : l’opération dépasse une de ses limites (par transfert, par jour ou plafond de frais). Les limites se règlent sur la machine du signataire, pas depuis cette app.",
        "vault_unconfirmed": "Échec fermé : le coffre THORChain doit être confirmé à l’unanimité par au moins trois opérateurs THORNode indépendants. Un seul désaccord, ou moins de trois réponses, et rien n’est préparé.",
        "provider_unavailable": "Échec fermé : sans réponse des opérateurs ou du fournisseur, rien n’est préparé plutôt que d’agir à l’aveugle.",
        "chain_halted": "THORChain signale ce réseau arrêté ou en pause ; rien n’a été préparé.",
        "router_changed": "Le code du contrat sur la chaîne n’est plus celui qui a été revu ; l’opération est refusée.",
        "account_has_code": "L’adresse du portefeuille porte du code (délégation) ; l’opération est refusée.",
        "below_minimum": "Sous le minimum du protocole, un remboursement ne pourrait pas payer ses propres frais.",
        "insufficient_gas": "Ajoutez de la monnaie native sur ce réseau pour payer les frais.",
        "insufficient_funds": "Le solde lu sur la chaîne ne couvre pas le montant.",
        "token_account_missing": "Rien n’a été brûlé : ouvrez d’abord le compte de jetons USDC sur Solana, puis recommencez.",
        "fast_unavailable": "Utilisez la vitesse Standard.",
        "quote_mismatch": "La cotation affichée ne correspond plus à la demande ; les cotations sont rafraîchies.",
        "quote_not_executable": "La route affichée n’est pas exécutable par ce portefeuille.",
        "swap_not_enabled": "L’exécution d’échanges n’est pas activée sur ce réseau.",
        "xswap_not_enabled": "Cette paire n’est pas échangeable nativement par ce portefeuille.",
        "bridge_not_enabled": "Le transfert CCTP n’est pas activé entre ces réseaux.",
        "too_many_streams": "Fermez une recherche de cotations en cours ou patientez.",
        "reclaim_not_yet": "Le programme de Circle ne libère ce dépôt que cinq jours après la destruction, une fois celle-ci attestée.",
        "plan_open": "Un seul parcours peut être ouvert à la fois : terminez-le ou arrêtez-le (les fonds restent où ils sont).",
        "plan_not_startable": "Corrigez les points bloquants indiqués sur le parcours.",
        "floor_above_estimate": "Baissez le plancher ou retirez-le.",
        "rpc_degraded": "La chaîne n’a pas pu être lue de façon fiable ; rien n’a été préparé.",
        "provider_bad_answer": "La réponse du fournisseur a été refusée par les vérifications du serveur ; rien n’a été préparé.",
    ]

    /// `model.describe` plus what the refusal means in this domain. A moved quote carries its fresh figures.
    static func describe(_ error: Error, model: AppModel) -> String {
        if let m = error as? QuoteMoved {
            return "Le prix a bougé depuis la cotation affichée : la sortie ferme serait de \(Fmt.amount(m.fresh.amountOutDisplay, maxFraction: 8)) \(m.fresh.symbol ?? ""), sous le minimum affiché (\(Fmt.amount(m.quoted.minAmountOutDisplay, maxFraction: 8))). Rien n’a été préparé ; demandez une nouvelle cotation."
        }
        if case ApprovalError.inconsistent("minimum output below the minimum displayed")? = error as? ApprovalError {
            return "Refusé par l’app : le minimum garanti de la route ferme est inférieur au minimum de la cotation affichée. Rien n’a été signé ; la demande préparée sur le serveur expire seule. Une nouvelle cotation est demandée."
        }
        let base = model.describe(error)
        if let e = error as? APIError, let more = explanations[e.code] { return "\(base)\n\(more)" }
        return base
    }

    /// True when this server signs without relaying (test stack): every figure and button says so.
    static func isSimulatedServer(_ model: AppModel) -> Bool { model.security?.value.broadcast == false }

    static func ownAddresses(_ model: AppModel) -> [String: String] {
        Dictionary((model.accounts?.value.accounts ?? []).map { ($0.network, $0.address) }, uniquingKeysWith: { a, _ in a })
    }
}

// MARK: - Tracking

/// Follows one proposal (swap, CCTP transfer, THORChain swap) by reading it. `completion` is the Core's answer to "is it done?":
/// for a cross-chain operation only the destination's confirmation counts.
@MainActor @Observable final class OperationTracker {
    let model: AppModel
    private(set) var proposal: Proposal
    private(set) var history: [(Date, String)] = []
    private(set) var readError: String?
    private var notified = false
    private var receiptReads = 0

    init(model: AppModel, proposal: Proposal) {
        self.model = model; self.proposal = proposal
        history = [(Date(), Self.label(proposal))]
        if isSettled { notified = true }
    }

    /// nil when the proposal's own section cannot be read: shown as unreadable, never guessed.
    var completion: OperationCompletion? { try? proposal.swapCompletion() }

    var isSettled: Bool {
        switch completion {
        case .complete, .refunded, .failed: true
        case .notStarted, .inProgress: false
        case nil: proposal.state.isFailure || proposal.state == .notBroadcast
        }
    }

    /// A same-network swap is final before its received amount has been read from the router's event: keep reading a little.
    private var awaitsReceipt: Bool {
        guard proposal.kind == "swap", completion == .complete, receiptReads < 10 else { return false }
        return (try? proposal.swapSection())??.received == nil
    }

    static func label(_ p: Proposal) -> String {
        var s = ErrorText.state(p.state)
        if p.kind == "bridge", let b = try? p.bridgeSection() { s += " · " + SwapText.bridgeStage(b.stage) }
        if p.kind == "xswap", let x = try? p.xswapSection() { s += " · " + SwapText.xswapStage(x.stage) }
        return s
    }

    func update(_ p: Proposal) {
        guard p.id == proposal.id else { return }
        let l = Self.label(p)
        if l != history.last?.1 { history.append((Date(), l)) }
        proposal = p
        if isSettled, !notified {
            notified = true
            announce()
            Task { await model.refreshAll() }
        }
    }

    private func announce() {
        let p = proposal, what = "\(Fmt.amount(p.amountDisplay, maxFraction: 8)) \(p.symbol) · \(p.networkName ?? p.network)"
        let title: String
        switch completion {
        case .complete: title = p.kind == "bridge" ? "Transfert inter-chaînes reçu sur la destination" : p.kind == "xswap" ? "Échange inter-chaînes reçu" : "Échange finalisé"
        case .refunded: title = "Échange remboursé par THORChain"
        default: title = p.state == .notBroadcast ? "Signée, NON diffusée (serveur de test)" : "Opération : \(ErrorText.state(p.state))"
        }
        Notifier.post(title: title, body: what + (p.error.map { " — \($0)" } ?? ""), id: "op-\(p.id)")
    }

    private var interval: Double {
        if proposal.kind == "bridge", let b = try? proposal.bridgeSection(), b.needsPasskey == true { return 20 }
        switch proposal.state {
        case .approved, .signed: return 2
        case .broadcast, .confirming, .reorged: return 4
        default: return proposal.kind == "swap" ? 3 : 8
        }
    }

    /// Reads the proposal until the operation is settled or the calling task is cancelled (the view's `.task`).
    func follow() async {
        while !Task.isCancelled {
            if isSettled, !awaitsReceipt { return }
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            guard AppActivity.isActive, model.phase == .signedIn else { continue }
            if isSettled { receiptReads += 1 }
            do { update(try await TransfersAPI(model.client).proposal(proposal.id)); readError = nil }
            catch { readError = model.describe(error) }
        }
    }
}

// MARK: - Shared views

struct SafeLink: View {
    let title: String; let url: String?
    var body: some View {
        if let url, let u = URL(string: url), u.scheme == "https" { Link(title, destination: u).font(.callout) }
    }
}

/// A transaction identifier: full, selectable, with its explorer link when the server gives an https one.
struct TxField: View {
    let label: String; let txid: String?; var explorer: String?; var state: String?
    var body: some View {
        if let txid {
            VStack(alignment: .leading, spacing: 2) {
                Field(label: label, value: txid + (state.map { "  ·  \($0)" } ?? ""), mono: true)
                HStack { Spacer().frame(width: 182); SafeLink(title: "Ouvrir dans l’explorateur de blocs", url: explorer) }
            }
        }
    }
}

/// Asset choice among the server's swap graph (never a hard-coded list): search, held assets first.
struct SwapAssetPicker: View {
    let model: AppModel
    let label: String
    let assets: [SwapAsset]
    @Binding var selection: String
    var exclude: String?
    @State private var open = false
    @State private var query = ""

    private var chosen: SwapAsset? { assets.first { $0.key == selection } }
    private var rows: [SwapAsset] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        func held(_ a: SwapAsset) -> Bool { SwapText.balance(model, of: a)?.isNonZero == true }
        return assets.filter { a in
            a.key != exclude && (q.isEmpty || a.symbol.lowercased().contains(q) || (a.name ?? "").lowercased().contains(q) || (a.networkName ?? a.network).lowercased().contains(q) || a.asset.lowercased() == q)
        }.sorted { a, b in
            let ha = held(a), hb = held(b)
            if ha != hb { return ha }
            if (a.native == true) != (b.native == true) { return a.native == true }
            return a.symbol == b.symbol ? a.network < b.network : a.symbol < b.symbol
        }
    }

    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 10) {
                if let c = chosen {
                    AssetBadge(symbol: c.symbol)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.symbol).fontWeight(.semibold)
                        Text(c.networkName ?? c.network).font(.caption).foregroundStyle(.secondary)
                    }
                } else { Text("Choisir un actif…").foregroundStyle(.secondary) }
                Spacer()
                Image(systemName: "chevron.up.chevron.down").foregroundStyle(.secondary)
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) : \(chosen.map { "\($0.symbol) sur \($0.networkName ?? $0.network)" } ?? "aucun actif choisi")")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(spacing: 0) {
                TextField("Rechercher (symbole, nom, réseau, contrat)", text: $query).textFieldStyle(.roundedBorder).padding(10)
                Divider()
                List(rows) { a in
                    Button { selection = a.key; open = false; query = "" } label: { row(a) }.buttonStyle(.plain)
                }
                .listStyle(.plain)
                .overlay { if rows.isEmpty { Text("Aucun actif ne correspond").foregroundStyle(.secondary) } }
            }
            .frame(width: 420, height: 440)
        }
    }

    private func row(_ a: SwapAsset) -> some View {
        let b = SwapText.balance(model, of: a)
        return HStack(spacing: 10) {
            AssetBadge(symbol: a.symbol, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(a.symbol).fontWeight(.medium) + Text(a.name.map { "  \($0)" } ?? "").foregroundStyle(.secondary)
                Text((a.networkName ?? a.network) + (a.asset == "native" ? "" : " · \(Fmt.short(a.asset))")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let b, b.isNonZero { Text(model.settings.hideBalances ? "••••" : Fmt.amount(b.display, maxFraction: 6)).monospacedDigit().font(.callout) }
        }
        .contentShape(Rectangle())
    }
}

/// The unified execution status of a proposal or a plan leg: one row per step, each with the server's state for it.
struct ExecutionTimeline: View {
    let model: AppModel
    let status: ExecutionStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Étapes d’exécution").font(.caption).foregroundStyle(.secondary)
            ForEach(status.steps) { s in
                HStack(alignment: .top, spacing: 10) {
                    icon(s.state).frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(SwapText.stepKind(s.kind)) — \(networkName(s.network))").fontWeight(.medium)
                        Text(SwapText.execState(s.state) + (s.code.map { " · \(SwapText.hold($0))" } ?? "")).font(.callout).foregroundStyle(color(s.state))
                            .fixedSize(horizontal: false, vertical: true)
                        if let tx = s.txid { Text(tx).font(.system(.caption, design: .monospaced)).textSelection(.enabled).foregroundStyle(.secondary) }
                        SafeLink(title: "Explorateur de blocs", url: s.explorer)
                    }
                }
            }
        }
    }

    private func networkName(_ id: String) -> String {
        switch id { case "circle": "Circle (hors chaîne)"; case "thorchain": "THORChain"; default: model.network(id)?.name ?? id }
    }
    private func color(_ s: ExecState) -> Color { s == .confirmed ? Theme.positive : s == .failed ? Theme.negative : s == .refunded ? Theme.warning : .secondary }
    @ViewBuilder private func icon(_ s: ExecState) -> some View {
        switch s {
        case .confirmed: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.positive)
        case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(Theme.negative)
        case .refunded: Image(systemName: "arrow.uturn.backward.circle.fill").foregroundStyle(Theme.warning)
        case .pending: Image(systemName: "circle").foregroundStyle(.tertiary)
        default: Image(systemName: "clock").foregroundStyle(Theme.warning)
        }
    }
}

/// The headline of a tracked operation, from the Core's completion — never from the source transaction alone.
struct OperationHeadline: View {
    let proposal: Proposal
    let completion: OperationCompletion?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                switch completion {
                case .complete: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.positive)
                case .refunded: Image(systemName: "arrow.uturn.backward.circle.fill").foregroundStyle(Theme.warning)
                case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(Theme.negative)
                case nil: Image(systemName: "questionmark.circle.fill").foregroundStyle(Theme.warning)
                default: ProgressView().controlSize(.small)
                }
            }.font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.weight(.semibold))
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var crossChain: Bool { proposal.kind == "bridge" || proposal.kind == "xswap" }
    private var title: String {
        switch completion {
        case .complete: crossChain ? "Reçu sur le réseau de destination" : "Échange finalisé"
        case .refunded: "Remboursé — l’échange n’a pas eu lieu"
        case .failed: proposal.state == .notBroadcast ? "Signée, NON diffusée" : "Aucun succès : \(ErrorText.state(proposal.state))"
        case .inProgress: crossChain ? "En cours — pas encore reçu sur la destination" : "En cours — \(ErrorText.state(proposal.state))"
        case .notStarted: ErrorText.state(proposal.state)
        case nil: "État illisible"
        }
    }
    private var detail: String {
        switch completion {
        case .complete: crossChain ? "Le portefeuille a lui-même constaté l’arrivée des fonds sur le réseau de destination." : "La transaction d’échange est confirmée au seuil de finalité du réseau."
        case .refunded: "THORChain a renvoyé l’actif source, moins ses frais."
        case .failed: proposal.state == .notBroadcast ? "Ce serveur est en mode test : la transaction a été signée mais volontairement pas relayée. Rien n’a été envoyé." : "Vérifiez le détail ci-dessous."
        case .inProgress: crossChain ? "La transaction source (ci-dessous : « \(ErrorText.state(proposal.state)) ») n’est que la première jambe. L’opération n’est terminée que lorsque la destination est confirmée." : "Un identifiant de transaction n’est pas une confirmation."
        case .notStarted: "Rien n’est parti."
        case nil: "La section de cette opération ne peut pas être lue par cette version de l’app ; aucun état n’est déduit."
        }
    }
}

struct StateHistory: View {
    let history: [(Date, String)]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Historique des états observés").font(.caption).foregroundStyle(.secondary)
            ForEach(Array(history.enumerated()), id: \.offset) { _, h in
                HStack(alignment: .firstTextBaseline) { Text(Fmt.dateSeconds(h.0)).monospacedDigit().foregroundStyle(.secondary); Text(h.1) }.font(.callout)
            }
        }
    }
}

/// The review of a verified intent-based operation, then the explicit passkey button. Everything shown comes from the intent
/// whose hash is the challenge; `extra` adds the server's context lines, labelled as such by the caller.
struct OperationReviewSheet: View {
    let model: AppModel
    let title: String
    let operation: ApprovableOperation
    var notices: [(Banner.Kind, String)] = []
    var extra: [ReviewLine] = []
    let busy: Bool
    let error: String?
    let onReject: () -> Void
    let onApprove: () -> Void

    var body: some View {
        let simulated = SwapText.isSimulatedServer(model)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.title2.weight(.semibold))
                Spacer()
                if simulated { ProvenanceTag(p: .simulated, text: "Serveur de test : signé, non diffusé") }
            }.padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(notices.enumerated()), id: \.offset) { _, n in Banner(n.0, n.1) }
                    TransactionReview(intent: operation.intent, digest: operation.approval.digest, network: model.network(operation.intent.network),
                                      ownAddresses: SwapText.ownAddresses(model),
                                      warnings: (operation.proposal.warnings ?? []).filter { $0 != "swap_needs_approval" }, extra: extra)
                }.padding(20)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if let error { Banner(.danger, error) }
                HStack {
                    Button("Rejeter", role: .destructive, action: onReject).disabled(busy)
                    Spacer()
                    if busy { ProgressView().controlSize(.small); Text("Passkey, puis signature isolée…").foregroundStyle(.secondary) }
                    Button(action: onApprove) { Label(simulated ? "Approuver (test : ne sera pas diffusé)" : "Approuver avec la passkey", systemImage: "touchid") }
                        .buttonStyle(.borderedProminent).controlSize(.large).disabled(busy || !model.canOperate)
                }
            }.padding(16)
        }
        .frame(width: 760, height: 800)
        .interactiveDismissDisabled()
    }

    /// The exact-amount ERC-20 spend approval that precedes a swap / a burn / a router deposit, spelled out from the intent.
    static func spendApproval(_ i: Intent, model: AppModel) -> (Banner.Kind, String)? {
        let amount = "\(SwapText.units(i.amount, decimals: i.decimals)) \(i.symbol)"
        if let s = i.swap, s.approveGas != "0" {
            return (.warning, "Autorisation de dépense ERC-20 : une première transaction autorise le routeur \(s.router) à dépenser exactement \(amount) (contrat \(i.asset)) — ni plus, ni illimité. Elle est couverte par cette même approbation et consommée par l’échange (gaz maximum de l’autorisation : \(s.approveGas)).")
        }
        if let b = i.bridge, b.approveGas != "0" {
            return (.warning, "Autorisation de dépense ERC-20 : une première transaction autorise le TokenMessenger de Circle \(b.messenger) à dépenser exactement \(amount) — ni plus, ni illimité. Elle est couverte par cette même approbation (gaz maximum de l’autorisation : \(b.approveGas)).")
        }
        if let x = i.xswap, x.approveGas != "0" {
            return (.warning, "Autorisation de dépense ERC-20 : une première transaction autorise le routeur THORChain \(x.router) à dépenser exactement \(amount) — ni plus, ni illimité. Elle est couverte par cette même approbation (gaz maximum de l’autorisation : \(x.approveGas)).")
        }
        return nil
    }

    static func simulationLine(_ simulated: Bool?, needsApproval: Bool?) -> ReviewLine {
        switch simulated {
        case true?: ReviewLine(label: "Simulation (serveur)", value: "Réussie à la préparation, contre l’état actuel de la chaîne.")
        case false?: ReviewLine(label: "Simulation (serveur)", value: needsApproval == true ? "Différée : la transaction principale sera simulée après la confirmation de l’autorisation de dépense, et ne partira pas si elle devait échouer." : "Non simulée à la préparation ; elle sera simulée contre l’état réel avant d’être relayée.", style: .warning)
        case nil: ReviewLine(label: "Simulation (serveur)", value: "Non indiquée par le serveur.", style: .warning)
        }
    }
}

extension OperationReviewSheet {
    /// Readable versions of the intent’s own figures (decimals from the registry), then the server’s context lines, labelled as such.
    static func contextLines(model: AppModel, operation: ApprovableOperation) -> [ReviewLine] {
        let i = operation.intent, p = operation.proposal
        var out: [ReviewLine] = []
        if let s = i.swap {
            let d = SwapText.assetDef(model, network: i.network, asset: s.toAsset)
            out.append(.init(label: "Minimum reçu (lisible)", value: "\(SwapText.units(s.minOut, decimals: d?.decimals)) \(d?.symbol ?? "")", style: .strong))
        }
        if let x = i.xswap {
            let d = SwapText.assetDef(model, network: x.toNetwork, asset: x.toAsset)
            out.append(.init(label: "Minimum reçu (lisible)", value: "\(SwapText.units(x.minOut, decimals: d?.decimals)) \(d?.symbol ?? "") sur \(model.network(x.toNetwork)?.name ?? x.toNetwork)", style: .strong))
        }
        if let sec = try? p.swapSection() {
            out.append(.init(label: "Sortie attendue", value: "\(Fmt.amount(sec.expectedOutDisplay)) \(sec.toSymbol) — estimation du serveur, non garantie ; seul le minimum est signé"))
            out.append(.init(label: "Tolérance de glissement", value: SwapText.bps(sec.slippageBps) + " (demandée ; le minimum ci-dessus en découle)"))
            out.append(simulationLine(sec.simulated, needsApproval: sec.needsApproval))
        }
        if let x = try? p.xswapSection() {
            if let f = x.outboundFeeDisplay { out.append(.init(label: "Frais sortants THORChain", value: "\(Fmt.amount(f)) \(x.toSymbol) — déjà déduits du minimum")) }
            if let f = x.liquidityFeeDisplay { out.append(.init(label: "Frais de liquidité", value: "\(Fmt.amount(f)) \(x.toSymbol) — déjà déduits")) }
            out.append(.init(label: "Délai estimé", value: SwapText.duration(x.estimatedSeconds)))
            if let ops = x.operators, !ops.isEmpty { out.append(.init(label: "Coffre confirmé par", value: "\(ops.count) opérateurs (côté serveur) : \(ops.joined(separator: ", "))" + (x.vaultMembers.map { " · \($0) membres du coffre" } ?? ""))) }
        }
        if let b = try? p.bridgeSection() {
            out.append(.init(label: "Vitesse", value: BridgeText.speed(b.speed) + " — durée attendue \(SwapText.duration(b.expectedSeconds)) (information du serveur)"))
            if let g = b.destGasNeedDisplay { out.append(.init(label: "Frais d’émission prévus", value: "≈ \(Fmt.amount(g, maxFraction: 8)) \(b.destGasSymbol ?? "") sur \(b.toNetworkName ?? b.toNetwork), payés par ce portefeuille (estimation)")) }
            out.append(simulationLine(b.simulated, needsApproval: b.needsApproval))
            if let s = b.sol, s.role == "source", let d = s.depositDisplay { out.append(.init(label: "Dépôt Solana remboursable", value: "\(Fmt.amount(d, maxFraction: 9)) \(s.symbol ?? "SOL") — récupérable cinq jours après la destruction", style: .warning)) }
            if let s = b.sol, s.role == "destination", let t = s.tokenAccount { out.append(.init(label: "Compte de jetons crédité", value: t, style: .address)) }
        }
        if let fee = p.feeDisplay { out.append(.init(label: "Frais de réseau estimés", value: "\(Fmt.amount(fee)) \(p.feeSymbol ?? "") (estimation ; le plafond ci-dessus est ce qui est signé)")) }
        if i.kind != .bridge {
            if let q = try? p.quoteRecord() {
                out.append(.init(label: "Écart avec la cotation", value: "\(SwapText.bps(Double(q.deviationBps))) (cotée \(Fmt.amount(q.quotedOutDisplay)), ferme \(Fmt.amount(q.firmOutDisplay)))", style: q.deviationBps < 0 ? .warning : .normal))
            } else { out.append(.init(label: "Cotation de référence", value: "Aucune référence comparée par le serveur : fiez-vous uniquement au minimum garanti ci-dessus.", style: .warning)) }
        }
        return out
    }
}
