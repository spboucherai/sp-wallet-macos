// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/Futures/FuturesMarketsView.swift
// Description: The markets list of one venue: every instrument the venue exposes, with price, 24 h change, volume, open interest, funding and maximum leverage; search and sortable columns in a virtualized table. Prices of the first rows come from the live quote stream with their freshness; the others show the REST snapshot with its age. The venue list and each venue's restriction (market data only, for jurisdiction reasons) are the server's.
import SwiftUI
import SPWalletCore

struct FutMarketRow: Identifiable {
    let id: String
    let symbol: String
    let base: String
    let status: String
    let category: String
    let mark: String?
    let freshness: StreamFreshness?
    let snapshotAt: Date?
    let change: String?
    let volume: String?
    let openInterest: String?
    let funding: String?
    let fundingIntervalSec: Int
    let maxLeverage: String
    // sort keys: a missing figure sorts last, it is never displayed as a number
    var markKey: Double { FutNum.d(mark) ?? -.infinity }
    var changeKey: Double { FutNum.d(change) ?? -.infinity }
    var volumeKey: Double { FutNum.d(volume) ?? -.infinity }
    var oiKey: Double { guard let o = FutNum.d(openInterest), let m = FutNum.d(mark) else { return -.infinity }; return o * m }
    var fundingKey: Double { FutNum.d(funding) ?? -.infinity }
    var leverageKey: Double { FutNum.d(maxLeverage) ?? 0 }
}

struct FutMarketsView: View {
    let model: AppModel
    @Bindable var store: FuturesStore
    let open: (String) -> Void
    @State private var search = ""
    @State private var sort = [KeyPathComparator(\FutMarketRow.volumeKey, order: .reverse)]
    @State private var selection: String?

    private var rows: [FutMarketRow] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return (store.instruments.value ?? []).filter { q.isEmpty || $0.symbol.lowercased().contains(q) || $0.base.lowercased().contains(q) || ($0.category ?? "").lowercased().contains(q) }.map { i in
            let t = store.tickers[i.id], p = store.price(i.id), live = store.quotes[i.id]?.quote
            return FutMarketRow(id: i.id, symbol: i.symbol, base: i.base, status: i.status, category: i.category ?? "", mark: p.mark, freshness: p.freshness, snapshotAt: p.snapshotAt,
                                change: live?.change24h ?? t?.change24h, volume: live?.volume24h ?? t?.volume24h, openInterest: live?.openInterest ?? t?.openInterest,
                                funding: live?.funding ?? t?.funding, fundingIntervalSec: i.fundingIntervalSec, maxLeverage: i.maxLeverage)
        }.sorted(using: sort)
    }

    var body: some View {
        let rows = rows
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Picker("Plateforme", selection: $store.venue) {
                    ForEach(store.venues.value ?? []) { v in Text(v.name + (v.restriction != nil ? " — données seulement" : "") + (v.status != "ok" ? " (\(v.status))" : "")).tag(v.id) }
                }.frame(maxWidth: 330)
                TextField("Rechercher un instrument", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                Spacer()
                if store.instruments.loading { ProgressView().controlSize(.small) }
                Text("\(rows.count) instrument(s)" + (store.tickersAt.map { " · instantané \(Fmt.relative($0))" } ?? "")).font(.caption).foregroundStyle(.secondary)
                Button("Actualiser") { Task { await store.loadMarket() } }
                Button("Ouvrir") { if let s = selection { open(s) } }.buttonStyle(.borderedProminent).disabled(selection == nil)
            }
            if let e = store.venues.error { Banner(.danger, "Liste des plateformes indisponible : \(e)") }
            if let v = store.selectedVenue {
                if let r = v.restriction { Banner(.warning, "Données de marché seulement sur \(v.name). \(r)") }
                if v.status != "ok" { Banner(.warning, "\(v.name) : état « \(v.status) »" + (v.lastError.map { " — \($0)" } ?? "") + (v.lastOkAt.map { " · dernière lecture réussie \(Fmt.relative($0))" } ?? "")) }
            }
            if let e = store.instruments.error { Banner(.danger, "Instruments indisponibles : \(e)") }
            ForEach(store.venueErrors, id: \.self) { e in Banner(.warning, "\(e.venue) illisible : \(e.message)") }
            if let e = store.tickersError { Banner(.warning, "Prix instantanés indisponibles : \(e). Les colonnes sans donnée affichent « — ».") }

            Table(rows, selection: $selection, sortOrder: $sort) {
                TableColumn("Instrument", value: \.symbol) { r in
                    HStack(spacing: 8) {
                        AssetBadge(symbol: r.base, size: 22)
                        Text(r.symbol).fontWeight(.medium)
                        if r.status != "active" { Text(r.status == "reduce_only" ? "réduction seule" : r.status == "halted" ? "suspendu" : r.status).font(.caption2).foregroundStyle(Theme.warning) }
                        if !r.category.isEmpty { Text(r.category).font(.caption2).foregroundStyle(.secondary) }
                    }
                }.width(min: 170, ideal: 220)
                TableColumn("Prix (mark)", value: \.markKey) { r in
                    HStack(spacing: 6) { FutFreshnessDot(freshness: r.freshness, snapshotAt: r.snapshotAt); Text(FutNum.exact(r.mark)).monospacedDigit() }
                }.width(min: 110, ideal: 140)
                TableColumn("24 h", value: \.changeKey) { r in
                    Text(FutNum.pct(fraction: r.change)).monospacedDigit().foregroundStyle(Theme.change(FutNum.d(r.change)))
                }.width(min: 70, ideal: 85)
                TableColumn("Volume 24 h", value: \.volumeKey) { r in Text(FutNum.compactUSD(r.volume)).monospacedDigit() }.width(min: 90, ideal: 110)
                TableColumn("Intérêt ouvert", value: \.oiKey) { r in
                    Text(r.oiKey.isFinite ? "≈ " + FutNum.compactUSD(String(r.oiKey)) : "—").monospacedDigit()
                        .help(r.openInterest.map { "\(FutNum.exact($0)) \(r.base) selon la plateforme ; valeur en dollars estimée au prix affiché" } ?? "Non publié")
                }.width(min: 100, ideal: 120)
                TableColumn("Financement", value: \.fundingKey) { r in
                    Text(r.funding == nil ? "—" : "\(FutNum.pct(fraction: r.funding, digits: 4)) / \(Self.interval(r.fundingIntervalSec))").monospacedDigit().foregroundStyle(Theme.change(FutNum.d(r.funding).map { -$0 }))
                        .help("Taux par intervalle de financement ; positif : les positions longues paient.")
                }.width(min: 120, ideal: 140)
                TableColumn("Levier max", value: \.leverageKey) { r in Text("\(FutNum.exact(r.maxLeverage))×").monospacedDigit() }.width(min: 70, ideal: 80)
            }
            .contextMenu(forSelectionType: String.self) { ids in
                if let id = ids.first { Button("Ouvrir l’instrument") { open(id) }; Button("Copier l’identifiant") { copyToPasteboard(id) } }
            } primaryAction: { ids in if let id = ids.first { open(id) } }
            .overlay {
                if rows.isEmpty, !store.instruments.loading {
                    EmptyState(symbol: "chart.bar.xaxis", title: store.instruments.value == nil ? "Aucune donnée de marché" : "Aucun instrument ne correspond", detail: store.instruments.value == nil ? "La plateforme n’a pas pu être lue. Rien n’est affiché à la place." : nil)
                }
            }
            Text("Le maximum de levier est celui que la plateforme publie : ce n’est jamais une valeur proposée par défaut. Les \(FuturesStore.liveRows) premières lignes du tri courant sont suivies en direct ; les autres affichent l’instantané.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .onChange(of: rows.prefix(FuturesStore.liveRows).map(\.id), initial: true) { _, ids in store.setLiveRows(ids) }
    }

    static func interval(_ sec: Int) -> String { sec % 3600 == 0 ? "\(sec / 3600) h" : "\(sec / 60) min" }
}
