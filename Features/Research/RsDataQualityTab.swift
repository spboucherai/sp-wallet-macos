// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/Research/RsDataQualityTab.swift
// Description: The status of the server's market-data worker: which symbols and intervals it follows, the consolidation rule and source priority, its quality verdict per series (freshness, last bar, gaps, agreement between sources, confirmations) and the coverage stored per source. Shown as served; a verdict that is not "ok" is spelled out, never softened.
import SwiftUI
import SPWalletCore

@MainActor @Observable final class RsDataQualityModel {
    struct Coverage: Identifiable, Sendable {
        let source: String, symbol: String, interval: String
        let bars: Int?
        let first: Date?, last: Date?
        var id: String { "\(source)|\(symbol)|\(interval)" }
    }

    let model: AppModel
    private let api: MarketsAPI
    private(set) var status: MarketDataStatus?
    private(set) var coverage: [Coverage] = []
    private(set) var loadedAt: Date?
    private(set) var loading = false
    private(set) var error: String?
    var symbolFilter = ""
    var onlyProblems = false

    init(model: AppModel) { self.model = model; api = MarketsAPI(model.client) }

    func load() async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        do {
            let s = try await api.marketDataStatus()
            status = s; loadedAt = Date(); error = nil
            coverage = (s.coverage?.arrayValue ?? []).compactMap { c in
                guard let source = c["source"]?.stringValue, let symbol = c["symbol"]?.stringValue, let interval = c["interval"]?.stringValue else { return nil }
                return Coverage(source: source, symbol: symbol, interval: interval, bars: c["bars"]?.intValue.map(Int.init), first: RsFmt.date(ms: c["first"]), last: RsFmt.date(ms: c["last"]))
            }
        } catch { self.error = model.describe(error) }
    }

    var quality: [MarketDataStatus.Quality] {
        let q = symbolFilter.trimmingCharacters(in: .whitespaces).uppercased()
        return (status?.quality ?? []).filter { (q.isEmpty || $0.symbol.uppercased().contains(q)) && (!onlyProblems || $0.status != "ok" || !$0.fresh) }
    }
    var shownCoverage: [Coverage] {
        let q = symbolFilter.trimmingCharacters(in: .whitespaces).uppercased()
        return coverage.filter { q.isEmpty || $0.symbol.uppercased().contains(q) }
    }
}

enum RsQualityText {
    static func status(_ s: String) -> String {
        switch s {
        case "ok": "Utilisable"
        case "stale": "Périmée"
        case "gap": "Trou dans la série"
        case "insufficient_history": "Historique insuffisant"
        case "insufficient_sources": "Sources insuffisantes"
        case "disagreement": "Désaccord entre sources"
        case "no_data": "Aucune donnée"
        case "unsupported": "Non prise en charge"
        default: s
        }
    }
    static func failures(_ v: JSONValue?) -> String {
        guard let list = v?.arrayValue, !list.isEmpty else { return "—" }
        return list.map { f in f["message"]?.stringValue ?? f["code"]?.stringValue ?? f.displayText }.joined(separator: " ; ")
    }
    /// Confirmations: the sources that had the series, with their own last bar when the server gives it.
    static func sources(_ v: JSONValue?) -> String {
        guard let v, !v.isNull else { return "—" }
        if let o = v.objectValue {
            return o.keys.sorted().map { k in
                let s = o[k]; let last = RsFmt.date(ms: s?["lastTs"]).map { Fmt.date($0) } ?? "aucune barre"
                return "\(k) : \(s?["bars"]?.intValue.map { "\($0) barres" } ?? "—"), dernière \(last)\((s?["gaps"]?.intValue ?? 0) > 0 ? ", \(s?["gaps"]?.intValue ?? 0) trous" : "")"
            }.joined(separator: " · ").opsIfEmpty("—")
        }
        return RsJSONText.inline(v)
    }
}

struct RsDataQualityTab: View {
    let model: AppModel
    @State private var data: RsDataQualityModel?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let data {
                    if let s = data.status {
                        if let e = data.error { Banner(.warning, "Dernière lecture en échec (\(e)). L’état ci-dessous date du \(Fmt.date(data.loadedAt)).") }
                        RsQualityOverview(data: data, status: s)
                        RsQualityTable(data: data)
                        RsCoverageCard(data: data)
                    } else if let e = data.error { Card { OpsUnavailable(what: "État du collecteur de données de marché", reason: e) { Task { await data.load() } } } }
                    else { ProgressView().frame(maxWidth: .infinity).padding(40) }
                } else { ProgressView() }
            }.padding(24).frame(maxWidth: 1180, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            let d = data ?? RsDataQualityModel(model: model); data = d
            await d.load()
            while !Task.isCancelled { // the server caches this answer for 30 s
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                if AppActivity.isActive, !model.isOffline { await d.load() }
            }
        }
    }
}

private struct RsQualityOverview: View {
    @Bindable var data: RsDataQualityModel
    let status: MarketDataStatus

    var body: some View {
        let all = status.quality, ok = all.filter { $0.status == "ok" && $0.fresh }.count
        Card("Collecteur de données de marché", trailing: AnyView(HStack(spacing: 8) {
            if data.loading { ProgressView().controlSize(.small) }
            OpsAsOf(date: data.loadedAt, prefix: "Reçu")
            Button { Task { await data.load() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless)
        })) {
            HStack(spacing: 22) {
                OpsMini(label: "Séries suivies", value: "\(all.count)")
                OpsMini(label: "Utilisables et fraîches", value: "\(ok)")
                OpsMini(label: "À problème", value: "\(all.count - ok)")
                OpsMini(label: "Symboles", value: "\(status.symbols.count)")
                OpsMini(label: "Intervalles", value: status.intervals.joined(separator: ", ").opsIfEmpty("—"))
                OpsMini(label: "Barres rejetées depuis le démarrage", value: RsJSONText.inline(status.rejectedSinceStart))
            }
            if all.count - ok > 0 { Banner(.warning, "\(all.count - ok) séries ne sont pas utilisables pour une décision selon le serveur : un agent qui en dépend attend, il ne décide pas sur une donnée douteuse.") }
            Field(label: "Règle de consolidation", value: status.rule)
            Field(label: "Priorité des sources", value: RsJSONText.inline(status.priority))
            Field(label: "Seuils de qualité", value: RsJSONText.inline(status.thresholds))
            if let sources = status.sources?.arrayValue, !sources.isEmpty {
                DisclosureGroup("Sources (\(sources.count))") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(sources.enumerated()), id: \.offset) { _, s in
                            Text("\(s["id"]?.stringValue ?? "?") — au plus \(RsJSONText.inline(s["maxBars"])) barres par requête ; historique accessible : \(s["historyBars"].map { $0.isNull ? "complet" : "\(RsJSONText.inline($0)) barres" } ?? "—") ; \(s["pairs"]?.objectValue?.count ?? 0) paires suivies")
                                .font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(.top, 4)
                }
            }
            HStack {
                TextField("Filtrer par symbole", text: $data.symbolFilter).textFieldStyle(.roundedBorder).frame(width: 200)
                Toggle("Seulement les séries à problème", isOn: $data.onlyProblems).toggleStyle(.checkbox)
                Spacer()
            }
        }
    }
}

private struct RsQualityTable: View {
    let data: RsDataQualityModel
    @State private var selection: String?

    var body: some View {
        let rows = data.quality.map(RsQualityRow.init)
        Card("Verdict de qualité par série", trailing: AnyView(ProvenanceTag(p: .verified, text: "Mesuré par le serveur"))) {
            Table(rows, selection: $selection) {
                TableColumn("Série") { r in Text("\(r.q.symbol) · \(r.q.interval)").fontWeight(.medium) }.width(min: 90, ideal: 110)
                TableColumn("Verdict") { r in
                    Label(RsQualityText.status(r.q.status), systemImage: r.q.status == "ok" ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").foregroundStyle(r.q.status == "ok" ? Theme.positive : Theme.negative)
                }.width(min: 150, ideal: 180)
                TableColumn("Fraîcheur") { r in Text(r.q.fresh ? "Fraîche" : "Pas fraîche").foregroundStyle(r.q.fresh ? Color.secondary : Theme.warning) }.width(min: 80, ideal: 90)
                TableColumn("Dernière barre") { r in Text(RsFmt.date(ms: r.q.lastTs).map { Fmt.date($0) } ?? "aucune").monospacedDigit() }.width(min: 130, ideal: 150)
                TableColumn("Trous") { r in Text(RsJSONText.inline(r.q.gaps)).monospacedDigit().foregroundStyle((r.q.gaps?.intValue ?? 0) > 0 ? Theme.warning : .primary) }.width(50)
                TableColumn("Écart max entre sources") { r in Text(r.q.maxDeviationBps?.doubleValue.map { "\(OpsFmt.number($0, digits: 1)) pb" } ?? "non mesuré").monospacedDigit() }.width(min: 110, ideal: 140)
                TableColumn("Vérifiée") { r in Text(RsFmt.date(ms: r.q.checkedAt).map { Fmt.relative($0) } ?? "—").foregroundStyle(.secondary) }.width(min: 90, ideal: 110)
            }
            .frame(height: min(max(CGFloat(rows.count) * 28 + 34, 120), 420))
            .overlay { if rows.isEmpty { Text("Aucune série ne correspond.").foregroundStyle(.secondary) } }
            if let id = selection, let r = rows.first(where: { $0.id == id }) {
                Divider()
                Text("\(r.q.symbol) · \(r.q.interval)").font(.subheadline.weight(.semibold))
                Field(label: "Motifs du verdict", value: RsQualityText.failures(r.q.failures))
                Field(label: "Confirmations par source", value: RsQualityText.sources(r.q.sources))
                Field(label: "Barres fournies par source", value: RsJSONText.inline(r.q.provided))
                Field(label: "Fenêtre d’accord", value: RsJSONText.inline(r.q.window))
            } else { Text("Sélectionnez une série pour voir les motifs du verdict et les confirmations par source.").font(.caption).foregroundStyle(.secondary) }
        }
    }
}

private struct RsQualityRow: Identifiable {
    let q: MarketDataStatus.Quality
    var id: String { "\(q.symbol)|\(q.interval)" }
}

private struct RsCoverageCard: View {
    let data: RsDataQualityModel
    var body: some View {
        let rows = data.shownCoverage
        Card("Couverture enregistrée par source", trailing: AnyView(Text("\(rows.count) séries").font(.caption).foregroundStyle(.secondary))) {
            if data.coverage.isEmpty { Text("Le serveur ne rapporte aucune barre enregistrée.").foregroundStyle(.secondary) }
            else {
                Table(rows) {
                    TableColumn("Source") { Text($0.source) }.width(min: 90, ideal: 110)
                    TableColumn("Série") { Text("\($0.symbol) · \($0.interval)") }.width(min: 90, ideal: 110)
                    TableColumn("Barres") { Text($0.bars.map { $0.formatted() } ?? "—").monospacedDigit() }.width(min: 70, ideal: 90)
                    TableColumn("Première barre") { Text(Fmt.date($0.first)).monospacedDigit() }.width(min: 130, ideal: 160)
                    TableColumn("Dernière barre") { Text(Fmt.date($0.last)).monospacedDigit() }.width(min: 130, ideal: 160)
                }.frame(height: min(max(CGFloat(rows.count) * 28 + 34, 120), 420))
            }
        }
    }
}
