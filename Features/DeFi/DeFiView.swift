// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/DeFi/DeFiView.swift
// Description: The DeFi hub, honest about what this wallet's backend integrates: DEX swap aggregation, Circle CCTP bridging, THORChain native swaps and multi-leg plans — and nothing else (no lending, staking, liquidity provision or dApp connection). The "connected protocols" table is built only from the server's own provider and capability endpoints: for each provider what it does, where, whether this wallet EXECUTES through it or only compares its quotes, and whether it needs a key the server has.
import SwiftUI
import SPWalletCore

/// One answer of a capability endpoint: fresh, or the last one kept on this Mac with its date, or unavailable with the reason.
struct HubAnswer<T: Codable & Sendable>: Sendable {
    var value: T?
    var at: Date?
    var cached = false
    var error: String?
}

@MainActor @Observable final class DeFiHub {
    let model: AppModel
    private(set) var providers = HubAnswer<SwapProviders>()
    private(set) var swap = HubAnswer<SwapExecutionInfo>()
    private(set) var bridge = HubAnswer<BridgeExecutionInfo>()
    private(set) var xswap = HubAnswer<XSwapExecutionInfo>()
    private(set) var plans = HubAnswer<PlanCapabilities>()
    private(set) var stats = HubAnswer<SwapStats>()
    private(set) var loading = false
    private(set) var loadedOnce = false

    init(model: AppModel) { self.model = model }

    private func fetch<T: Codable & Sendable>(_ key: String, _ call: @Sendable () async throws -> T) async -> HubAnswer<T> {
        if model.phase == .signedIn {
            do {
                let v = try await call()
                await SnapshotStore.shared.save(v, as: "defi.\(key)")
                return HubAnswer(value: v, at: Date(), cached: false, error: nil)
            } catch {
                let old: Snapshot<T>? = await SnapshotStore.shared.load("defi.\(key)")
                return HubAnswer(value: old?.value, at: old?.savedAt, cached: old != nil, error: model.describe(error))
            }
        }
        let old: Snapshot<T>? = await SnapshotStore.shared.load("defi.\(key)")
        return HubAnswer(value: old?.value, at: old?.savedAt, cached: old != nil, error: old == nil ? "Jamais synchronisé sur ce Mac." : nil)
    }

    func load() async {
        guard !loading else { return }
        loading = true; defer { loading = false; loadedOnce = true }
        let c = model.client
        async let a = fetch("providers") { try await SwapAPI(c).providers() }
        async let b = fetch("swap-execution") { try await SwapAPI(c).execution() }
        async let d = fetch("bridge-execution") { try await BridgeAPI(c).execution() }
        async let e = fetch("xswap-execution") { try await XSwapAPI(c).execution() }
        async let f = fetch("plan-capabilities") { try await PlanAPI(c).capabilities() }
        async let g = fetch("swap-stats") { try await SwapAPI(c).stats() }
        (providers, swap, bridge, xswap, plans, stats) = await (a, b, d, e, f, g)
    }

    struct Row: Identifiable {
        let id: String
        let name: String
        let does: String
        let networks: String
        let executes: Bool
        let execution: String
        let key: String
        let health: String
        let healthy: Bool
        let stats: String
    }

    private func names(_ ids: [String]) -> String { ids.map { model.network($0)?.name ?? $0 }.joined(separator: ", ") }

    /// One row per provider the server lists. "Executes" is the server's statement (`executors`), scoped by its execution endpoints.
    var rows: [Row] {
        guard let p = providers.value else { return [] }
        return p.providers.map { info in
            let cap = info.capabilities
            let does = (cap?.kinds ?? []).map { k -> String in
                switch k { case "swap": "Agrégation d’échanges (DEX)"; case "bridge": "Pont inter-chaînes"; case "native_swap": "Échange natif inter-chaînes"; default: k }
            }.joined(separator: " + ")
            let executes = p.isExecutor(info.id)
            let st = stats.value?.providers.first { $0.provider == info.id }
            let key: String = switch (cap?.needsKey, cap?.configured) {
            case (true?, true?): "Clé requise — configurée"
            case (true?, _): "Clé requise — NON configurée : jamais interrogé"
            case (false?, _): "Aucune clé requise"
            default: "Non indiqué"
            }
            let breaker: String = switch info.state { case "closed"?: "opérationnel"; case "open"?: "coupé (trop d’échecs)"; case "half_open"?: "en reprise"; case let s?: s; case nil: "état non indiqué" }
            return Row(id: info.id, name: SwapText.provider(info.id, providers: p, execution: swap.value),
                       does: does.isEmpty ? "Non indiqué" : does,
                       networks: cap.map { "\($0.networks.count) : \(names($0.networks))" + ($0.crossChain ? " (inter-chaînes)" : "") } ?? "Non indiqué",
                       executes: executes, execution: executes ? scope(info.id) : "Cotation seulement — sert à comparer les prix",
                       key: key, health: info.enabled ? breaker : "désactivé sur le serveur", healthy: info.enabled && info.state != "open",
                       stats: st.map { "\($0.calls ?? 0) appels · \($0.ok ?? 0) réussis · \($0.quotes ?? 0) cotations" + ($0.p50.map { " · médiane \(Int($0)) ms" } ?? "") } ?? "—")
        }
    }

    /// Where an executor really executes, from the matching execution endpoint; unknown when that endpoint could not be read.
    private func scope(_ id: String) -> String {
        if let s = swap.value {
            if s.provider == id { return s.enabled ? "Exécutable : échanges sur \(names(s.networks))" : "Exécuteur désactivé par le serveur" }
            if let sol = s.solana, sol.provider == id { return s.enabled ? "Exécutable : échanges sur \(names(sol.networks))" : "Exécuteur désactivé par le serveur" }
        }
        if let b = bridge.value, b.provider == id { return b.enabled ? "Exécutable : \(b.asset) entre \(names(b.networks))" : "Exécuteur désactivé par le serveur" }
        if let x = xswap.value, x.provider == id { return x.enabled ? "Exécutable : \(x.assets.count) actifs natifs (voir ci-dessous)" : "Exécuteur désactivé par le serveur" }
        return "Exécuteur déclaré par le serveur — périmètre illisible pour l’instant"
    }
}

struct DeFiView: View {
    let model: AppModel
    let nav: Navigator
    @State private var hub: DeFiHub?

    var body: some View {
        Page("DeFi", subtitle: "Ce que ce portefeuille sait réellement faire en finance décentralisée — d’après les capacités déclarées par son serveur, rien de plus.") {
            Banner(.info, "Ici, « DeFi » signifie : agrégation d’échanges sur DEX, pont USDC par Circle CCTP, échanges natifs inter-chaînes par THORChain, et parcours en plusieurs étapes qui les enchaînent. Aucun protocole de prêt, de staking ou de fourniture de liquidité n’est intégré.")
            if !model.canOperate { Banner(.warning, "Session ou portefeuille indisponible : les capacités affichées peuvent être les dernières synchronisées, et aucune opération n’est possible.") }
            if SwapText.isSimulatedServer(model) { Banner(.warning, "SERVEUR DE TEST : les transactions sont signées mais ne sont PAS diffusées.") }
            if let hub {
                ProtocolsCard(model: model, hub: hub)
                CapabilitiesCard(model: model, hub: hub, nav: nav)
            } else { ProgressView() }
            PlanPanel(model: model)
            unavailable
        }
        .task {
            if hub == nil { hub = DeFiHub(model: model) }
            await hub?.load()
        }
    }

    private var unavailable: some View {
        Card("Ce qui n’est PAS disponible") {
            ForEach([
                ("Prêt et emprunt", "Aucune intégration de protocole de prêt (Aave, Compound, Morpho…). Aucun rendement n’est proposé ni affiché."),
                ("Staking et staking liquide", "Aucune délégation, aucun jeton de staking liquide. Le portefeuille ne met rien en jeu."),
                ("Fourniture de liquidité", "Aucun dépôt dans des pools (Uniswap, Curve…) : le portefeuille échange à travers les DEX, il ne leur fournit pas de liquidité."),
                ("Connexion à des dApps", "Pas de WalletConnect ni de navigateur de dApps : le signataire ne signe que des opérations qu’il reconstruit et vérifie lui-même, jamais une transaction arbitraire présentée par un site."),
            ], id: \.0) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "minus.circle").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) { Text(item.0).fontWeight(.medium); Text(item.1).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                }
            }
            HStack {
                Text("Les dérivés (contrats à terme perpétuels) ont leur propre écran.").font(.callout).foregroundStyle(.secondary)
                Button("Ouvrir « Contrats à terme »") { nav.section = .futures }.buttonStyle(.link)
            }
        }
    }
}

// MARK: - Connected protocols

private struct ProtocolsCard: View {
    let model: AppModel
    let hub: DeFiHub

    var body: some View {
        let rows = hub.rows
        Card("Protocoles connectés", trailing: AnyView(HStack(spacing: 8) {
            if hub.loading { ProgressView().controlSize(.small) }
            if let at = hub.providers.at { ProvenanceTag(p: hub.providers.cached ? .stale : .verified, text: hub.providers.cached ? "Liste du \(Fmt.date(at))" : "Lu sur le serveur \(Fmt.relative(at))") }
            Button("Relire") { Task { await hub.load() } }.controlSize(.small).disabled(hub.loading)
        })) {
            if let e = hub.providers.error { Banner(hub.providers.value == nil ? .danger : .warning, "Liste des fournisseurs : \(e)") }
            if let p = hub.providers.value {
                if !p.executionEnabled { Banner(.danger, "Le serveur déclare l’exécution des échanges désactivée : tous les fournisseurs ci-dessous ne servent qu’à comparer.") }
                Text("« Exécutable » = ce portefeuille prépare, vérifie et signe lui-même l’opération à travers ce protocole (contrat revu, champs vérifiés par le signataire). Tous les autres fournisseurs ne font que coter : leurs prix servent de comparaison et ne peuvent pas être exécutés d’ici.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Table(rows) {
                    TableColumn("Protocole") { r in Text(r.name).fontWeight(.medium) }.width(min: 110, ideal: 140)
                    TableColumn("Fonction") { r in Text(r.does) }.width(min: 150, ideal: 190)
                    TableColumn("Exécution par ce portefeuille") { r in
                        Label(r.execution, systemImage: r.executes ? "checkmark.seal.fill" : "eye").foregroundStyle(r.executes ? Theme.positive : .secondary).help(r.execution)
                    }.width(min: 230, ideal: 320)
                    TableColumn("Clé d’API") { r in Text(r.key).foregroundStyle(r.key.contains("NON") ? Theme.warning : .primary) }.width(min: 140, ideal: 190)
                    TableColumn("État") { r in Text(r.health).foregroundStyle(r.healthy ? Color.primary : Theme.warning) }.width(min: 100, ideal: 130)
                    TableColumn("7 derniers jours") { r in Text(r.stats).foregroundStyle(.secondary).monospacedDigit().help(r.stats) }.width(min: 160, ideal: 240)
                }
                .frame(height: CGFloat(max(rows.count, 1)) * 28 + 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Réseaux couverts par fournisseur").font(.caption).foregroundStyle(.secondary)
                    ForEach(rows) { r in Text("\(r.name) — \(r.networks)").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) }
                }
                if !p.needsKey.isEmpty { Text("Présents dans le code du serveur mais jamais interrogés faute de clé d’API : \(p.needsKey.joined(separator: ", ")).").font(.callout).foregroundStyle(Theme.warning) }
                if let e = hub.stats.error { Text("Statistiques indisponibles : \(e)").font(.caption).foregroundStyle(.secondary) }
            } else if hub.loadedOnce {
                EmptyState(symbol: "xmark.octagon", title: "Liste des protocoles indisponible", detail: "Le serveur n’a pas répondu et aucune copie n’existe sur ce Mac. Rien n’est supposé.")
            } else { ProgressView() }
        }
    }
}

// MARK: - What is executable, endpoint by endpoint

private struct CapabilitiesCard: View {
    let model: AppModel
    let hub: DeFiHub
    let nav: Navigator

    private func names(_ ids: [String]) -> String { ids.isEmpty ? "aucun" : ids.map { model.network($0)?.name ?? $0 }.joined(separator: ", ") }

    var body: some View {
        Card("Ce que ce portefeuille exécute lui-même") {
            section("Échanges sur un même réseau", hub.swap, link: ("Ouvrir « Échanger »", .swap)) { s in
                Field(label: "État", value: s.enabled ? "Activé" : "Désactivé par le serveur", emphasis: true)
                Field(label: "\(SwapText.provider(s.provider, providers: hub.providers.value)) (EVM)", value: names(s.networks))
                if let r = s.router { Field(label: "Routeur revu", value: r, mono: true) }
                if let sol = s.solana {
                    Field(label: sol.label, value: names(sol.networks))
                    if let p = sol.program { Field(label: "Programme Solana", value: p, mono: true) }
                }
            }
            Divider()
            section("Pont USDC — Circle CCTP", hub.bridge, link: ("Ouvrir « Pont inter-chaînes »", .bridge)) { b in
                Field(label: "État", value: b.enabled ? "Activé" : "Désactivé par le serveur", emphasis: true)
                Field(label: "Actif", value: b.asset)
                Field(label: "Réseaux", value: names(b.networks))
                if let m = b.messenger { Field(label: "TokenMessenger", value: m, mono: true) }
                if let t = b.transmitter { Field(label: "MessageTransmitter", value: t, mono: true) }
            }
            Divider()
            section("Échanges natifs inter-chaînes — THORChain", hub.xswap, link: ("Ouvrir « Échanger »", .swap)) { x in
                Field(label: "État", value: x.enabled ? "Activé" : "Désactivé par le serveur", emphasis: true)
                Field(label: "Actifs", value: x.assets.map { "\($0.symbol) sur \(model.network($0.network)?.name ?? $0.network)\($0.source ? "" : " (destination seulement)")" }.joined(separator: " · "))
                Field(label: "Sécurité du coffre", value: "Unanimité d’au moins \(x.minOperators.map(String.init) ?? "—") opérateurs THORNode indépendants ; sinon rien n’est préparé ni signé (échec fermé)." + ((x.operators ?? []).isEmpty ? "" : "\nOpérateurs : \((x.operators ?? []).map { $0.host ?? $0.id }.joined(separator: ", "))"))
                if let r = x.routers, !r.isEmpty { Field(label: "Routeurs revus", value: r.keys.sorted().map { "\(model.network($0)?.name ?? $0) : \(r[$0] ?? "")" }.joined(separator: "\n"), mono: true) }
            }
            Divider()
            section("Parcours multi-étapes", hub.plans, link: nil) { c in
                Field(label: "Étapes au maximum", value: String(c.maxLegs))
                Field(label: "Actif intermédiaire", value: c.hub)
                Field(label: "Échanges chaînables", value: c.swap.keys.sorted().map { "\(model.network($0)?.name ?? $0) (\(SwapText.provider(c.swap[$0] ?? "", providers: hub.providers.value, execution: hub.swap.value)))" }.joined(separator: ", "))
                Field(label: "Pont CCTP entre", value: names(c.cctp))
                Field(label: "THORChain", value: c.thorchain.map { "\($0.symbol) (\($0.networkName ?? $0.network))\($0.source == true ? "" : " — destination seulement")" }.joined(separator: " · "))
            }
        }
    }

    @ViewBuilder private func section<T: Codable & Sendable, Content: View>(_ title: String, _ answer: HubAnswer<T>, link: (String, Section)?, @ViewBuilder content: (T) -> Content) -> some View {
        HStack {
            Text(title).font(.headline)
            if answer.cached, let at = answer.at { ProvenanceTag(p: .stale, text: "Copie du \(Fmt.date(at))") }
            Spacer()
            if let link { Button(link.0) { nav.section = link.1 }.buttonStyle(.link) }
        }
        if let v = answer.value {
            if let e = answer.error { Text("Lecture en échec (\(e)) — dernière copie affichée.").font(.caption).foregroundStyle(Theme.warning) }
            content(v)
        } else if let e = answer.error {
            HStack { ProvenanceTag(p: .unavailable); Text(e).font(.callout).foregroundStyle(.secondary) }
        } else { ProgressView().controlSize(.small) }
    }
}
