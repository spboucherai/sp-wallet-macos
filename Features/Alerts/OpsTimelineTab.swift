// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/Alerts/OpsTimelineTab.swift
// Description: The unified timeline of operations (wallet, plans, orders, agent decisions, audit) as the server assembles it: filters by kind, mode, venue or network and period; pages walked with the server's cursor; the server's own CSV saved through NSSavePanel. Every row carries the money it is about — simulated rows are visibly marked — and the screen says when a source is missing or the history is bounded.
import SwiftUI
import UniformTypeIdentifiers
import SPWalletCore

@MainActor @Observable final class OpsTimelineModel {
    enum Period: String, CaseIterable, Identifiable {
        case day, week, month, all, custom
        var id: String { rawValue }
        var label: String { switch self { case .day: "24 heures"; case .week: "7 jours"; case .month: "30 jours"; case .all: "Tout l’historique"; case .custom: "Dates choisies" } }
    }

    let model: AppModel
    private let api: DashboardAPI

    var kind = "" { didSet { changed(oldValue != kind) } }
    var mode = "" { didSet { changed(oldValue != mode) } }
    var venue = "" { didSet { changed(oldValue != venue) } }
    var principal = "" { didSet { changed(oldValue != principal) } }
    var period: Period = .week { didSet { changed(oldValue != period) } }
    var from = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date() { didSet { if period == .custom { changed(oldValue != from) } } }
    var to = Date() { didSet { if period == .custom { changed(oldValue != to) } } }

    private(set) var items: [TimelineItem] = []
    private(set) var nextCursor: String?
    private(set) var loadedAt: Date?
    private(set) var serverTs: Date?
    private(set) var sourceErrors: [TimelinePage.SourceError] = []
    private(set) var audit: TimelinePage.Audit?
    private(set) var bounds: TimelinePage.Bounds?
    private(set) var kinds: [String] = []
    private(set) var knownVenues: [String] = []
    private(set) var loading = false
    private(set) var loadingMore = false
    private(set) var exporting = false
    var error: String?
    var exportMessage: String?
    private var generation = 0

    init(model: AppModel) { self.model = model; api = DashboardAPI(model.client) }

    private func changed(_ really: Bool) { if really { Task { await reload() } } }

    /// The filter as sent to the server. A relative period is anchored when the first page is read, so every page of one walk uses the same window.
    private var anchoredQuery = TimelineQuery()
    private func makeQuery() -> TimelineQuery {
        let now = Date()
        let window: (Date?, Date?) = switch period {
        case .day: (now.addingTimeInterval(-86_400), nil)
        case .week: (now.addingTimeInterval(-7 * 86_400), nil)
        case .month: (now.addingTimeInterval(-30 * 86_400), nil)
        case .all: (nil, nil)
        case .custom: (Calendar.current.startOfDay(for: min(from, to)), Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: max(from, to))))
        }
        func opt(_ s: String) -> String? { let t = s.trimmingCharacters(in: .whitespaces); return t.isEmpty ? nil : t }
        return TimelineQuery(kind: opt(kind), mode: opt(mode), venue: opt(venue), principal: opt(principal), from: window.0, to: window.1)
    }

    func reload() async {
        generation += 1; let g = generation
        loading = true; defer { if g == generation { loading = false } }
        let q = makeQuery()
        do {
            let page = try await api.activity(q, limit: 100)
            guard g == generation else { return }
            anchoredQuery = q
            items = page.items; nextCursor = page.nextCursor; sourceErrors = page.errors; audit = page.audit; bounds = page.bounds
            if let k = page.kinds, !k.isEmpty { kinds = k }
            serverTs = page.ts; loadedAt = Date(); error = nil
            noteVenues(page.items)
        } catch { guard g == generation else { return }; self.error = model.describe(error) }
    }

    func loadMore() async {
        guard let cursor = nextCursor, !loadingMore, !loading else { return }
        loadingMore = true; defer { loadingMore = false }
        let g = generation
        do {
            let page = try await api.activity(anchoredQuery, limit: 100, cursor: cursor)
            guard g == generation else { return }
            let known = Set(items.map(\.id))
            items.append(contentsOf: page.items.filter { !known.contains($0.id) })
            nextCursor = page.nextCursor; error = nil
            // a source that fails on a later page makes the whole walk incomplete
            for e in page.errors where !sourceErrors.contains(e) { sourceErrors.append(e) }
            noteVenues(page.items)
        } catch { self.error = model.describe(error) }
    }

    private func noteVenues(_ rows: [TimelineItem]) {
        let seen = Set(knownVenues).union(rows.flatMap { [$0.venue, $0.network].compactMap { $0 } })
        knownVenues = seen.sorted()
    }

    /// The server's own CSV of the filtered timeline (its quoting, its bound of 2 500 rows).
    func exportCSV() async {
        guard !exporting else { return }
        exporting = true; exportMessage = nil; defer { exporting = false }
        let q = makeQuery()
        do {
            let data = try await api.activityCSV(q)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.commaSeparatedText]; panel.canCreateDirectories = true
            panel.nameFieldStringValue = "sp-wallet-operations-\(Date().formatted(.iso8601.year().month().day())).csv"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url, options: .atomic)
                let lines = data.reduce(into: 0) { if $1 == 0x0a { $0 += 1 } }
                exportMessage = "Exporté : \(url.lastPathComponent) (\(max(lines - 1, 0)) lignes ; le serveur en exporte 2 500 au plus). Les lignes simulées y portent leur mode."
            } catch { exportMessage = "Écriture impossible : \(error.localizedDescription)" }
        } catch { self.error = model.describe(error) }
    }
}

enum OpsTimelineText {
    static func kind(_ k: String) -> String {
        switch k {
        case "transfer": "Envoi"; case "receive": "Réception"; case "swap": "Échange"; case "bridge": "Pont"; case "plan": "Plan"; case "order": "Ordre"
        case "agent": "Agent"; case "mandate": "Mandat"; case "risk": "Risque"; case "key": "Clé d’API"; case "security": "Sécurité"; default: k
        }
    }
    static func source(_ s: String) -> String {
        switch s { case "wallet": "Portefeuille"; case "plans": "Plans"; case "orders": "Ordres"; case "decisions": "Décisions d’agents"; case "audit": "Journal d’audit"; default: s }
    }
    static func principal(_ p: TimelineItem.Principal?) -> String {
        guard let p else { return "—" }
        switch p.kind {
        case "owner": return "Propriétaire"; case "agent": return "Agent \(p.id)"; case "api_key": return "Clé d’API \(p.id)"; case "system": return "Système"
        default: return "\(p.kind) \(p.id)"
        }
    }
    /// The status exactly as served, translated only for the wallet's own proposal states (broadcast is never shown as done).
    static func status(_ item: TimelineItem) -> String {
        guard let s = item.status else { return "—" }
        return item.source == "wallet" ? ErrorText.activityState(s) : s
    }
    static func quantity(_ q: TimelineItem.Quantity?) -> String? { q.map { "\(Fmt.amount($0.value, maxFraction: 8))\($0.symbol.map { " \($0)" } ?? "")" } }
}

struct OpsTimelineTab: View {
    let model: AppModel
    @State private var data: OpsTimelineModel?
    @State private var selection: TimelineItem.ID?

    var body: some View {
        VStack(spacing: 0) {
            if let data {
                OpsTimelineFilters(model: model, data: data)
                OpsTimelineNotices(data: data).padding(.horizontal, 24)
                Table(data.items, selection: $selection) {
                    TableColumn("Date") { i in Text(Fmt.dateSeconds(i.at)).monospacedDigit() }.width(min: 150, ideal: 165)
                    TableColumn("Argent concerné") { i in OpsBookTag(kind: OpsBookKind(mode: i.mode)) }.width(min: 150, ideal: 180)
                    TableColumn("Type") { i in Text(OpsTimelineText.kind(i.kind)) }.width(min: 70, ideal: 90)
                    TableColumn("Code") { i in Text(i.code).font(Theme.monoSmall).lineLimit(1) }.width(min: 110, ideal: 160)
                    TableColumn("Objet") { i in
                        Text([i.instrument, i.side, OpsTimelineText.quantity(i.amount), OpsTimelineText.quantity(i.received).map { "→ \($0)" }].compactMap { $0 }.joined(separator: " · ").opsIfEmpty("—")).monospacedDigit().lineLimit(1)
                    }.width(min: 180, ideal: 280)
                    TableColumn("Lieu") { i in Text([i.venue, i.network].compactMap { $0 }.joined(separator: " · ").opsIfEmpty("—")).lineLimit(1) }.width(min: 90, ideal: 130)
                    TableColumn("État servi") { i in Text(OpsTimelineText.status(i)).lineLimit(1) }.width(min: 110, ideal: 170)
                    TableColumn("Auteur") { i in Text(OpsTimelineText.principal(i.principal)).lineLimit(1).foregroundStyle(.secondary) }.width(min: 90, ideal: 130)
                }
                .overlay {
                    if data.loading && data.items.isEmpty { ProgressView() }
                    else if data.items.isEmpty { EmptyState(symbol: "clock.arrow.circlepath", title: data.loadedAt == nil ? "Historique non lu" : "Aucune opération pour ces filtres", detail: data.error) }
                }
                HStack(spacing: 12) {
                    Text("\(data.items.count) opérations chargées").font(.callout).foregroundStyle(.secondary)
                    if data.nextCursor != nil { Button(data.loadingMore ? "Chargement…" : "Charger la page suivante") { Task { await data.loadMore() } }.disabled(data.loadingMore || data.loading) }
                    else if data.loadedAt != nil { Text("Fin de l’historique pour ces filtres.").font(.callout).foregroundStyle(.secondary) }
                    Spacer()
                    if let m = data.exportMessage { Text(m).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    OpsAsOf(date: data.serverTs ?? data.loadedAt, prefix: data.serverTs == nil ? "Reçu" : "Données du serveur")
                }.padding(.horizontal, 24).padding(.vertical, 8)
                if let id = selection, let item = data.items.first(where: { $0.id == id }) { Divider(); OpsTimelineDetail(item: item).frame(maxHeight: 260) }
            } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .task { if data == nil { let d = OpsTimelineModel(model: model); data = d; await d.reload() } }
    }
}

private struct OpsTimelineFilters: View {
    let model: AppModel
    @Bindable var data: OpsTimelineModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Picker("Type", selection: $data.kind) { Text("Tous types").tag(""); ForEach(data.kinds, id: \.self) { Text(OpsTimelineText.kind($0)).tag($0) } }.frame(width: 150)
                Picker("Mode", selection: $data.mode) {
                    Text("Tous modes").tag(""); Text("Réel").tag("live"); Text("Papier (simulé)").tag("paper"); Text("Recherche (backtest)").tag("research")
                }.frame(width: 190)
                Picker("Lieu", selection: $data.venue) {
                    Text("Toutes plateformes et réseaux").tag("")
                    ForEach(data.knownVenues, id: \.self) { Text(model.network($0)?.name ?? $0).tag($0) }
                    if !data.venue.isEmpty, !data.knownVenues.contains(data.venue) { Text(data.venue).tag(data.venue) }
                }.frame(width: 230).help("Plateformes et réseaux rencontrés dans les pages déjà lues.")
                Picker("Auteur", selection: $data.principal) {
                    Text("Tous auteurs").tag(""); Text("Propriétaire").tag("owner"); Text("Agents").tag("agent"); Text("Clés d’API").tag("api_key"); Text("Système").tag("system")
                }.frame(width: 150)
                Picker("Période", selection: $data.period) { ForEach(OpsTimelineModel.Period.allCases) { Text($0.label).tag($0) } }.frame(width: 170)
                Spacer()
                if data.exporting { ProgressView().controlSize(.small) }
                Button("Exporter en CSV…") { Task { await data.exportCSV() } }.disabled(data.exporting || model.isOffline).help("Le CSV est produit par le serveur avec les filtres affichés.")
                Button { Task { await data.reload() } } label: { Image(systemName: "arrow.clockwise") }.disabled(data.loading)
            }.labelsHidden()
            if data.period == .custom {
                HStack {
                    DatePicker("Du", selection: $data.from, displayedComponents: .date).frame(width: 180)
                    DatePicker("au", selection: $data.to, displayedComponents: .date).frame(width: 180)
                    Text("(jours entiers, heure locale)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }.padding(.horizontal, 24).padding(.vertical, 10)
    }
}

private struct OpsTimelineNotices: View {
    let data: OpsTimelineModel
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let e = data.error, !data.items.isEmpty { Banner(.danger, e) }
            if !data.sourceErrors.isEmpty {
                Banner(.warning, "Historique INCOMPLET — sources illisibles : " + data.sourceErrors.map { "\(OpsTimelineText.source($0.source)) (\($0.code))" }.joined(separator: ", ") + ". Des opérations peuvent manquer ci-dessous.")
            }
            if let a = data.audit, !a.intact { Banner(.danger, "La chaîne d’audit est rompue à l’événement \(a.brokenAt.map(String.init) ?? "?") : les lignes issues du journal d’audit ne sont plus prouvées intactes.") }
            if let b = data.bounds { Text("Le serveur remonte au plus \(b.perSource) lignes par source (\(b.plans) plans) : l’historique plus ancien n’apparaît pas ici. Aucun total n’est calculé entre modes.").font(.caption).foregroundStyle(.secondary) }
        }.padding(.bottom, data.sourceErrors.isEmpty && data.bounds == nil ? 0 : 6)
    }
}

private struct OpsTimelineDetail: View {
    let item: TimelineItem
    var body: some View {
        let i = item
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(OpsTimelineText.kind(i.kind)) · \(Fmt.dateSeconds(i.at))").font(.headline)
                    OpsBookTag(kind: OpsBookKind(mode: i.mode))
                    if i.isSimulated { ProvenanceTag(p: .simulated, text: "Simulation — aucun fonds réel") }
                    Spacer()
                }
                if i.mode == nil { Text("La source ne précise pas de quel argent il s’agit pour cette ligne.").font(.caption).foregroundStyle(.secondary) }
                Field(label: "Code", value: i.code, mono: true)
                Field(label: "Source", value: OpsTimelineText.source(i.source))
                Field(label: "État servi", value: OpsTimelineText.status(i))
                if let v = i.instrument { Field(label: "Instrument", value: v) }
                if let v = i.side { Field(label: "Sens", value: v) }
                if let v = OpsTimelineText.quantity(i.amount) { Field(label: "Montant", value: v) }
                if let v = OpsTimelineText.quantity(i.received) { Field(label: "Reçu", value: v) }
                if let v = i.venue { Field(label: "Plateforme", value: v) }
                if let v = i.network { Field(label: "Réseau", value: v) }
                Field(label: "Auteur", value: OpsTimelineText.principal(i.principal))
                Field(label: "Référence", value: "\(i.ref.type) \(i.ref.id)", mono: true)
                if let tx = i.txid {
                    Field(label: "Identifiant de transaction", value: tx, mono: true)
                    Text("Un identifiant de transaction n’est pas une confirmation : seul l’état servi fait foi.").font(.caption).foregroundStyle(.secondary)
                }
                if let ex = i.explorer, let url = URL(string: ex), url.scheme == "https" { Link("Ouvrir dans l’explorateur de blocs", destination: url) }
                if !i.params.isEmpty {
                    Divider(); Text("Paramètres servis").font(.caption).foregroundStyle(.secondary)
                    ForEach(i.params.keys.sorted(), id: \.self) { k in if let v = i.params[k] { Field(label: k, value: v.displayText, mono: true) } }
                }
            }.padding(16)
        }
    }
}
