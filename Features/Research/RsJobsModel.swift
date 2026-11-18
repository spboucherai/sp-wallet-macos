// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/Research/RsJobsModel.swift
// Description: State of the automated research jobs (an AI coding agent on another machine develops a strategy within budgets the owner sets): runner availability, the list, creation, one job's detail and results, cancellation, and the live log through the Core's SSE stream with reconnection. Every state shown is the server's; creating a job is never retried blindly because the server's route is not idempotent.
import Foundation
import SPWalletCore

@MainActor @Observable final class RsJobsModel {
    let model: AppModel
    private let api: ResearchAPI

    private(set) var status: ResearchStatus?
    private(set) var statusError: String?
    /// The server's own sentence for the `research_runner` capability (why it is off, when it is).
    private(set) var runnerCapability: ServerCapability?
    private(set) var jobs: [ResearchJob] = []
    private(set) var jobsAt: Date?
    private(set) var jobsError: String?
    private(set) var loading = false

    var selectedId: String? { didSet { if selectedId != oldValue { selectionChanged() } } }
    private(set) var detail: ResearchJobDetail?
    private(set) var detailAt: Date?
    private(set) var detailError: String?
    private(set) var cancelling = false
    var actionError: String?

    // log of the selected job
    enum LogLive: Equatable { case idle, connecting, streaming, reconnecting(String), ended }
    private(set) var logLines: [ResearchLogLine] = []
    private(set) var logLive: LogLive = .idle
    private(set) var logTruncated = false
    private var logTask: Task<Void, Never>?
    private static let maxLogLines = 5000

    init(model: AppModel) { self.model = model; api = ResearchAPI(model.client) }

    var selectedJob: ResearchJob? { detail?.job.id == selectedId ? detail?.job : jobs.first { $0.id == selectedId } }
    var hasOpenJobs: Bool { jobs.contains { !$0.state.isFinal } }
    var canCreate: Bool { model.canOperate && (status.map { $0.openJobs < $0.maxOpenJobs } ?? false) }

    // MARK: reads

    func refresh() async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        async let s: Void = loadStatus()
        async let j: Void = loadJobs()
        _ = await (s, j)
        if selectedId != nil { await loadDetail() }
    }

    private func loadStatus() async {
        do { status = try await api.status(); statusError = nil } catch { statusError = model.describe(error) }
        if let h = try? await MonitorAPI(model.client).health() { runnerCapability = h.capability("research_runner") }
    }

    private func loadJobs() async {
        do { jobs = try await api.jobs(limit: 100); jobsAt = Date(); jobsError = nil } catch { jobsError = model.describe(error) }
    }

    func loadDetail() async {
        guard let id = selectedId else { return }
        do {
            let d = try await api.job(id)
            guard id == selectedId else { return }
            detail = d; detailAt = Date(); detailError = nil
        } catch { guard id == selectedId else { return }; detailError = model.describe(error) }
    }

    private func selectionChanged() {
        logTask?.cancel(); logTask = nil
        detail = nil; detailError = nil; detailAt = nil; logLines = []; logLive = .idle; logTruncated = false; actionError = nil
        guard selectedId != nil else { return }
        Task { await loadDetail() }
    }

    // MARK: operations

    /// Creates a job. The server's route has no idempotency key: when the answer is lost, the list is read again and the caller is told to check it before sending anything a second time.
    func create(_ request: ResearchJobRequest) async -> String? {
        guard model.canOperate else { return "Création impossible hors ligne ou sans session." }
        do {
            let job = try await api.create(request)
            await refresh()
            selectedId = job.id
            return nil
        } catch let e as APIError where e.isOffline {
            await loadJobs()
            return "La réponse du serveur a été perdue : la recherche a peut-être été créée. La liste vient d’être relue — vérifiez-la avant de relancer, pour ne pas payer deux fois."
        } catch { return model.describe(error) }
    }

    func cancel() async {
        guard let id = selectedId, model.canOperate, !cancelling else { return }
        cancelling = true; defer { cancelling = false }
        do {
            let job = try await api.cancel(id)
            if let i = jobs.firstIndex(where: { $0.id == job.id }) { jobs[i] = job }
            actionError = nil
            await loadDetail()
        } catch { actionError = model.describe(error); await loadDetail() }
    }

    // MARK: live log

    /// Follows the log of the selected job while its tab is on screen. Call from a `.task`; cancellation stops it.
    func followLog() async {
        guard let id = selectedId else { return }
        var backoff = OpsBackoff()
        var lastEventId: String?
        // what the job has already written, then the stream from there
        if logLines.isEmpty { await readLogPages(id) }
        while !Task.isCancelled, id == selectedId {
            if let s = selectedJob?.state, s.isFinal { await readLogPages(id); logLive = .ended; return }
            guard AppActivity.isActive, model.canOperate else { logLive = .idle; try? await Task.sleep(for: .seconds(3)); continue }
            guard let request = await api.logStreamRequest(id, after: logLines.last?.id ?? 0, lastEventId: lastEventId) else { logLive = .reconnecting("Session absente."); return }
            logLive = .connecting
            var ended = false, delivered = false, failure: String?
            do {
                for try await event in OpsEventStream.events(request, while: { AppActivity.isActive }) {
                    if Task.isCancelled || id != selectedId { return }
                    if let eid = event.id { lastEventId = eid }
                    delivered = true; logLive = .streaming
                    switch ResearchLogStreamEvent(event) {
                    case .log(let line)?: append([line])
                    case .state?: await loadDetail(); await loadJobs()
                    case .end?: ended = true
                    case nil: break
                    }
                    if ended { break }
                }
            } catch { failure = model.describe(error) }
            if Task.isCancelled || id != selectedId { return }
            if ended { await loadDetail(); await loadJobs(); logLive = .ended; return }
            if delivered { backoff.reset() }
            await loadDetail()
            let wait = failure == nil && delivered ? Duration.seconds(1) : backoff.next()
            logLive = .reconnecting(failure ?? "Flux terminé par le serveur (dix minutes au plus) ; reprise à la dernière ligne reçue.")
            try? await Task.sleep(for: wait)
        }
    }

    private func readLogPages(_ id: String) async {
        var after = logLines.last?.id ?? 0
        for _ in 0..<20 { // at most 20 000 lines per catch-up; the view keeps the most recent ones
            guard let page = try? await api.log(id, after: after, limit: 1000), id == selectedId else { return }
            append(page.lines)
            guard page.lines.count == 1000, let last = page.lastId else { return }
            after = last
        }
    }

    private func append(_ lines: [ResearchLogLine]) {
        let lastId = logLines.last?.id ?? 0
        logLines.append(contentsOf: lines.filter { $0.id > lastId })
        if logLines.count > Self.maxLogLines { logLines.removeFirst(logLines.count - Self.maxLogLines); logTruncated = true }
    }
}

enum RsJobText {
    static func state(_ s: ResearchState) -> String {
        switch s {
        case .queued: "En file d’attente"
        case .preparing: "Préparation par l’exécuteur"
        case .running: "Agent IA au travail"
        case .evaluating: "Évaluation par le serveur"
        case .submitted: "Stratégie soumise — en attente de votre décision"
        case .failed: "Échouée"
        case .cancelled: "Annulée"
        case .overBudget: "Arrêtée : budget dépassé"
        case .unknown(let r): r
        }
    }
    static func stateNote(_ s: ResearchState) -> String {
        switch s {
        case .queued: "Aucun exécuteur n’a encore pris cette recherche."
        case .preparing, .running: "L’agent n’a accès qu’aux données d’entraînement et de validation ; le serveur garde la période de test."
        case .evaluating: "L’agent a terminé. Le serveur rejoue lui-même la stratégie sur des données que l’agent n’a jamais vues."
        case .submitted: "« Soumise » ne veut dire ni approuvée ni rentable : un brouillon de stratégie attend votre décision, prise ailleurs avec votre passkey."
        case .failed, .cancelled, .overBudget: "État final : rien d’autre ne se produira pour cette recherche."
        case .unknown: "État inconnu de cette version de l’app, affiché tel que servi."
        }
    }
    static func provenance(_ p: ResearchProvenance) -> (Provenance, String) {
        let who = switch p.author { case .agent: "agent IA, non vérifié"; case .server: "serveur"; case .runner: "exécuteur, hors du contrôle de l’agent" }
        return switch p.nature {
        case .observedData: (.verified, "Donnée observée · \(who)")
        case .estimate: (.estimate, "Estimation statistique · \(who)")
        case .simulation: (.simulated, "Simulation (backtest) · \(who)")
        case .generatedAnalysis: (.ai, "Analyse générée par IA · \(who)")
        }
    }
    static func split(_ s: String) -> String {
        switch s { case "train": "Entraînement"; case "validation": "Validation"; case "test": "Test (hors échantillon)"; case "inner_test": "Test interne de l’agent"; default: s }
    }
    static func metric(_ m: String) -> String {
        switch m { case "total_return": "Rendement total"; case "sharpe": "Ratio de Sharpe"; case "max_drawdown": "Repli maximal"; case "trades": "Transactions simulées"; default: m }
    }
    static func stream(_ s: String) -> String {
        switch s { case "out": "agent"; case "err": "agent (erreur)"; case "sys": "exécuteur"; case "api": "serveur"; default: s }
    }
}
