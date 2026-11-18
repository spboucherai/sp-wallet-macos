// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/Alerts/OpsMonitorModel.swift
// Description: The read-only monitoring data: capital, PnL, exposure, the three risk books, system health and the quote engine's statistics. Every section is read on its own, keeps its own date and its own failure: one failed read never blanks or zeroes the others, and a section that could not be refreshed keeps its last value marked as stale.
import Foundation
import SPWalletCore

/// One independently loaded block of the monitoring screen.
struct OpsSection<T: Sendable>: Sendable {
    var value: T?
    /// When the app received `value`.
    var fetchedAt: Date?
    /// The last read failed; `value` (if any) is the previous successful read.
    var error: String?
    var loading = false
    var isStale: Bool { value != nil && error != nil }
}

@MainActor @Observable final class OpsMonitorModel {
    let model: AppModel
    private let monitor: MonitorAPI
    private let dashboard: DashboardAPI

    private(set) var capital = OpsSection<MonitorCapital>()
    private(set) var pnl = OpsSection<MonitorPnl>()
    private(set) var exposure = OpsSection<MonitorExposure>()
    private(set) var health = OpsSection<MonitorHealth>()
    private(set) var quotes = OpsSection<QuoteStreamStats>()
    private(set) var summary = OpsSection<DashboardSummary>()
    private(set) var refreshing = false

    init(model: AppModel) { self.model = model; monitor = MonitorAPI(model.client); dashboard = DashboardAPI(model.client) }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true; defer { refreshing = false }
        async let a: Void = reloadCapital()
        async let b: Void = reloadPnl()
        async let c: Void = reloadExposure()
        async let e: Void = reloadHealth()
        async let f: Void = reloadQuotes()
        async let g: Void = reloadSummary()
        _ = await (a, b, c, e, f, g)
    }

    func reloadCapital() async { let m = monitor; await load(\.capital) { try await m.capital() } }
    func reloadPnl() async { let m = monitor; await load(\.pnl) { try await m.pnl() } }
    func reloadExposure() async { let m = monitor; await load(\.exposure) { try await m.exposure() } }
    func reloadHealth() async { let m = monitor; await load(\.health) { try await m.health() } }
    func reloadQuotes() async { let m = monitor; await load(\.quotes) { try await m.quoteStreamStats() } }
    func reloadSummary() async { let d = dashboard; await load(\.summary) { try await d.summary() } }

    private func load<T: Sendable>(_ path: ReferenceWritableKeyPath<OpsMonitorModel, OpsSection<T>>, _ call: @Sendable () async throws -> T) async {
        self[keyPath: path].loading = true
        do {
            let v = try await call()
            self[keyPath: path] = OpsSection(value: v, fetchedAt: Date(), error: nil, loading: false)
        } catch {
            self[keyPath: path].error = model.describe(error)
            self[keyPath: path].loading = false
        }
    }
}

enum OpsText {
    /// Reason codes of a failed dashboard section. The server's message is for logs; the screen shows the code's meaning.
    static func sectionError(_ code: String) -> String {
        switch code {
        case "timeout": "La source n’a pas répondu à temps."
        case "source_failed": "La source a échoué."
        default: "La source a répondu par une erreur (\(code))."
        }
    }
    static func connectorGroup(_ g: String) -> String {
        switch g {
        case "signer": "Signataire"; case "rpc": "RPC des réseaux"; case "market": "Données de marché"; case "venue": "Plateformes"
        case "swap": "Échange"; case "bridge": "Ponts"; case "database": "Base de données"; default: g
        }
    }
    static func capability(_ id: String) -> String {
        switch id {
        case "deriv_live_mainnet": "Dérivés réels sur réseau principal"
        case "deriv_mandate_mainnet": "Trading autonome (mandat) sur réseau principal"
        case "deriv_gmx_live": "Ordres GMX v2 réels"
        case "trading_api_execution": "Exécution par le service d’ordres"
        case "deriv_mm_mainnet": "Tenue de marché sur réseau principal"
        case "deriv_mm_testnet": "Tenue de marché sur testnet"
        case "research_runner": "Exécuteur de recherche (jobs IA)"
        case "research_readonly_db": "Base en lecture seule pour les backtests"
        case "broadcast": "Diffusion des transactions signées"
        case "workers": "Boucles d’arrière-plan"
        case "strategy_sandbox_enforced": "Confinement du code de stratégie"
        case "web_app": "App web servie par ce processus"
        case "market_data_apibricks": "Seconde source de prix (API Bricks)"
        default: id
        }
    }
    static func agentState(_ s: String) -> String {
        switch s {
        case "DRAFT": "Brouillon"; case "BACKTESTING": "Backtest"; case "PAPER_TRADING": "Papier"; case "LIVE": "Réel"; case "PAUSED": "En pause"
        case "STOPPED": "Arrêté"; case "RESEARCH": "Recherche"; default: s
        }
    }
    static func venueState(_ s: StreamVenueState) -> String {
        switch s { case .connected: "Connectée"; case .reconnecting: "Reconnexion"; case .stale: "Périmée"; case .down: "En panne"; case .idle: "Au repos"; case .unknown(let r): r }
    }
}
