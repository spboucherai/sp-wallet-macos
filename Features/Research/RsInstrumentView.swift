// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/Research/RsInstrumentView.swift
// Description: The page of one underlying: the candles of the server's consolidated series (candlestick or line), the indicators the app derives from those candles — each labelled as derived, with its window — the underlying's markets venue by venue, and the estimated cost of a hypothetical position across venues. Read-only; no figure here is advice and no control places an order.
import Charts
import SwiftUI
import SPWalletCore

struct RsInstrumentView: View {
    let model: AppModel
    let symbol: String
    let close: () -> Void
    @State private var data: RsInstrumentModel?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Button { close() } label: { Label("Marchés", systemImage: "chevron.left") }
                    AssetBadge(symbol: symbol, size: 34)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(symbol).font(.title.weight(.semibold))
                        if let c = data?.detail?.category { Text(RsMarketsText.category(c)).font(.callout).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Button { Task { await data?.load() } } label: { Label("Relire", systemImage: "arrow.clockwise") }
                }
                if let data {
                    RsChartCard(data: data)
                    RsVenuesCard(data: data)
                    RsCompareCard(data: data)
                } else { ProgressView().frame(maxWidth: .infinity).padding(40) }
            }.padding(24).frame(maxWidth: 1180, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { if data == nil { let d = RsInstrumentModel(model: model, symbol: symbol); data = d; await d.load() } }
    }
}

// MARK: - Chart and derived indicators

private struct RsChartCard: View {
    @Bindable var data: RsInstrumentModel
    @State private var style = "candles"
    @State private var smaWindow = 20
    @State private var emaWindow = 50
    @State private var showSMA = true
    @State private var showEMA = true
    private let rsiWindow = 14, volWindow = 30
    private static let windows = [10, 20, 50, 100, 200]

    var body: some View {
        Card("Cours — série consolidée du serveur", trailing: AnyView(HStack(spacing: 8) {
            if data.loadingCandles { ProgressView().controlSize(.small) }
            if !data.bars.isEmpty { ProvenanceTag(p: .verified, text: "Barres observées (bourses)") }
            OpsAsOf(date: data.candlesAt, prefix: "Reçu")
        })) {
            if data.hasMarketData == false {
                OpsUnavailable(what: "Chandeliers de \(data.symbol)", reason: "Le collecteur de données de marché du serveur ne suit pas ce symbole : aucune série consolidée n’existe. Les prix par plateforme restent visibles ci-dessous.")
            } else {
                HStack(spacing: 10) {
                    Picker("Intervalle", selection: $data.interval) { ForEach(data.intervals.isEmpty ? [data.interval] : data.intervals, id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented).frame(width: 200)
                    Picker("Barres", selection: $data.barCount) { ForEach([100, 300, 500, 1000], id: \.self) { Text("\($0) barres").tag($0) } }.frame(width: 130)
                    Picker("Tracé", selection: $style) { Text("Chandeliers").tag("candles"); Text("Ligne (clôtures)").tag("line") }.pickerStyle(.segmented).frame(width: 240)
                    Spacer()
                    Toggle("MMS", isOn: $showSMA).toggleStyle(.checkbox)
                    Picker("MMS", selection: $smaWindow) { ForEach(Self.windows, id: \.self) { Text("\($0)").tag($0) } }.frame(width: 70).disabled(!showSMA)
                    Toggle("MME", isOn: $showEMA).toggleStyle(.checkbox)
                    Picker("MME", selection: $emaWindow) { ForEach(Self.windows, id: \.self) { Text("\($0)").tag($0) } }.frame(width: 70).disabled(!showEMA)
                }.labelsHidden()
                if let e = data.statusError { Text("État du collecteur illisible (\(e)) : la couverture de ce symbole n’est pas confirmée.").font(.caption).foregroundStyle(Theme.warning) }
                if let e = data.candlesError {
                    if data.bars.isEmpty { OpsUnavailable(what: "Chandeliers", reason: e) { Task { await data.loadCandles() } } }
                    else { Banner(.warning, "Dernière lecture en échec (\(e)). Le graphique date de la lecture précédente.") }
                }
                if !data.bars.isEmpty { charts } else if data.candlesError == nil && !data.loadingCandles { Text("Aucune barre servie pour cet intervalle.").foregroundStyle(.secondary) }
            }
        }
    }

    @ViewBuilder private var charts: some View {
        let bars = data.bars
        let sma = showSMA ? RsIndicators.sma(bars, window: smaWindow) : []
        let ema = showEMA ? RsIndicators.ema(bars, window: emaWindow) : []
        let width = max(1.0, min(9.0, 620.0 / Double(bars.count)))
        let lows = bars.map(\.low).min() ?? 0, highs = bars.map(\.high).max() ?? 1
        Chart {
            if style == "candles" {
                ForEach(bars) { b in
                    RuleMark(x: .value("Date", b.date), yStart: .value("Bas", b.low), yEnd: .value("Haut", b.high)).lineStyle(StrokeStyle(lineWidth: 1)).foregroundStyle(b.isUp ? Theme.positive : Theme.negative)
                    RectangleMark(x: .value("Date", b.date), yStart: .value("Ouverture", b.open), yEnd: .value("Clôture", b.close), width: .fixed(width)).foregroundStyle(b.isUp ? Theme.positive : Theme.negative)
                }
            } else {
                ForEach(bars) { b in LineMark(x: .value("Date", b.date), y: .value("Clôture", b.close), series: .value("Série", "Clôture")).foregroundStyle(Theme.accent) }
            }
            ForEach(sma) { p in LineMark(x: .value("Date", p.date), y: .value("MMS", p.value), series: .value("Série", "MMS")).foregroundStyle(.orange).lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 2])) }
            ForEach(ema) { p in LineMark(x: .value("Date", p.date), y: .value("MME", p.value), series: .value("Série", "MME")).foregroundStyle(.purple).lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 2])) }
        }
        .chartYScale(domain: (lows * 0.995)...(highs * 1.005))
        .frame(height: 320)
        .accessibilityLabel("Cours de \(data.symbol), \(bars.count) barres de \(data.interval)")

        HStack(spacing: 14) {
            if let last = bars.last {
                Text("Dernière barre close : \(Fmt.date(last.date)) UTC d’ouverture · O \(RsFmt.price(last.open)) H \(RsFmt.price(last.high)) B \(RsFmt.price(last.low)) C \(RsFmt.price(last.close))\(last.source.map { " · source \($0)" } ?? "")").font(.caption).monospacedDigit()
            }
            Spacer()
            if showSMA { RsLegend(color: .orange, text: "MMS \(smaWindow) — dérivé\(sma.isEmpty ? " (pas assez de barres)" : "")") }
            if showEMA { RsLegend(color: .purple, text: "MME \(emaWindow) — dérivé\(ema.isEmpty ? " (pas assez de barres)" : "")") }
        }
        provenance

        Divider()
        HStack { Text("Indicateurs calculés par l’app").font(.subheadline.weight(.semibold)); ProvenanceTag(p: .estimate, text: "Dérivé des barres affichées"); Spacer() }
        Text("Ces valeurs ne sont pas servies par le portefeuille : elles sont calculées sur ce Mac à partir des \(bars.count) barres ci-dessus, avec les fenêtres indiquées. Elles décrivent le passé observé et ne constituent ni une prévision ni un conseil.").font(.caption).foregroundStyle(.secondary)
        indicators(bars)
    }

    @ViewBuilder private var provenance: some View {
        if let c = data.candles {
            VStack(alignment: .leading, spacing: 2) {
                Text("Règle de consolidation du serveur : \(c.rule)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Text("Priorité des sources : \((c.priority ?? []).joined(separator: " > ").opsIfEmpty("non fournie")) · barres fournies par source : \(RsJSONText.inline(c.provided)) · heures d’ouverture manquantes dans la fenêtre : \(RsJSONText.inline(c.gaps))").font(.caption).foregroundStyle(.secondary)
                if (c.gaps?.intValue ?? 0) > 0 { Text("La série a des trous : les indicateurs ci-dessous sont calculés sur les barres présentes, sans interpolation.").font(.caption).foregroundStyle(Theme.warning) }
                if data.unreadableBars > 0 { Text("\(data.unreadableBars) barres servies n’ont pas pu être lues et ne sont pas tracées.").font(.caption).foregroundStyle(Theme.warning) }
            }
        }
    }

    @ViewBuilder private func indicators(_ bars: [RsBar]) -> some View {
        let rsi = RsIndicators.rsi(bars, window: rsiWindow)
        let dd = RsIndicators.drawdown(bars)
        let ppy = RsIndicators.periodsPerYear(interval: data.interval)
        let vol = ppy.flatMap { RsIndicators.realizedVolatility(bars, window: volWindow, periodsPerYear: $0) }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], alignment: .leading, spacing: 10) {
            OpsMini(label: "RSI (\(rsiWindow) barres, lissage de Wilder)", value: rsi.last.map { RsFmt.metric($0.value, digits: 1) } ?? "Pas assez de barres")
            OpsMini(label: "Volatilité réalisée (\(volWindow) rendements, annualisée)", value: vol.map { OpsFmt.fraction($0).replacingOccurrences(of: "+", with: "") } ?? (ppy == nil ? "Intervalle non annualisable" : "Pas assez de barres"))
            OpsMini(label: "Repli maximal sur la fenêtre (\(bars.count) barres)", value: dd.map(\.value).min().map { OpsFmt.fraction($0) } ?? "—")
            OpsMini(label: "Repli actuel depuis le plus haut de la fenêtre", value: dd.last.map { OpsFmt.fraction($0.value) } ?? "—")
        }
        if ppy != nil { Text("Annualisation : marché ouvert 24 h/24, 365 jours (\(Int(ppy ?? 0)) barres de \(data.interval) par an), écart-type des rendements logarithmiques clôture à clôture.").font(.caption).foregroundStyle(.secondary) }
        if !rsi.isEmpty {
            Text("RSI \(rsiWindow) — dérivé").font(.caption).foregroundStyle(.secondary)
            Chart {
                ForEach(rsi) { p in LineMark(x: .value("Date", p.date), y: .value("RSI", p.value)).foregroundStyle(Theme.accent) }
                RuleMark(y: .value("70", 70)).foregroundStyle(.secondary.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
                RuleMark(y: .value("30", 30)).foregroundStyle(.secondary.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
            }.chartYScale(domain: 0...100).frame(height: 110)
        }
        if dd.count > 1 {
            Text("Repli depuis le plus haut de la fenêtre — dérivé").font(.caption).foregroundStyle(.secondary)
            Chart(dd) { p in AreaMark(x: .value("Date", p.date), y: .value("Repli", p.value * 100)).foregroundStyle(Theme.negative.opacity(0.35)) }
                .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let d = v.as(Double.self) { Text("\(Int(d)) %") } } } }
                .frame(height: 110)
        }
    }
}

struct RsLegend: View {
    let color: Color; let text: String
    var body: some View { HStack(spacing: 5) { RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 16, height: 3); Text(text).font(.caption).foregroundStyle(.secondary) } }
}

// MARK: - Venue by venue

private struct RsVenuesCard: View {
    let data: RsInstrumentModel

    var body: some View {
        Card("Marchés de \(data.symbol), plateforme par plateforme", trailing: AnyView(OpsAsOf(date: data.detailAt, prefix: "Reçu"))) {
            if let d = data.detail {
                if let e = data.detailError { Banner(.warning, "Dernière lecture en échec (\(e)). Le tableau date de la lecture précédente.") }
                if !d.errors.isEmpty { Banner(.warning, "Comparaison PARTIELLE — sources sans réponse : " + d.errors.map { "\($0.source) (\($0.message))" }.joined(separator: " ; ")) }
                Text("Lecture seule. Chaque ligne est le prix d’UNE plateforme à SA date ; les prix de plateformes différentes ne sont jamais moyennés.").font(.callout).foregroundStyle(.secondary)
                if d.spot.isEmpty && d.instruments.isEmpty { Text("Aucun marché rattaché à ce sous-jacent.").foregroundStyle(.secondary) }
                if !d.spot.isEmpty { table("Comptant", d.spot) }
                if !d.instruments.isEmpty { table("Perpétuels", d.instruments) }
                if !d.notCompared.isEmpty {
                    Divider()
                    Text("Même symbole, non rattaché à ce sous-jacent — affiché, jamais comparé").font(.subheadline.weight(.semibold))
                    table(nil, d.notCompared)
                }
            } else if let e = data.detailError { OpsUnavailable(what: "Marchés du sous-jacent", reason: e) { Task { await data.loadDetail() } } }
            else { ProgressView().controlSize(.small) }
        }
    }

    @ViewBuilder private func table(_ title: String?, _ rows: [HubRow]) -> some View {
        if let title { Text(title).font(.subheadline.weight(.semibold)) }
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
            GridRow { Text("Plateforme"); Text("Marché"); Text("Prix"); Text("24 h"); Text("Volume 24 h"); Text("Financement / h"); Text("Intérêt ouvert"); Text("Date de la source"); Text("Signalements") }.font(.caption).foregroundStyle(.secondary)
            ForEach(rows) { r in
                GridRow {
                    Text(r.venueName ?? r.venue).lineLimit(1)
                    VStack(alignment: .leading, spacing: 0) { Text(r.symbol).lineLimit(1); if let m = r.multiplier, m != "1" { Text("multiplicateur \(m)").font(.caption2).foregroundStyle(.secondary) } }
                    VStack(alignment: .leading, spacing: 0) { Text(RsFmt.price(r.price)).monospacedDigit(); Text(RsMarketsText.priceKind(r.priceKind)).font(.caption2).foregroundStyle(.secondary) }
                    Text(RsFmt.fraction(r.change24h)).monospacedDigit().foregroundStyle(Theme.change(RsFmt.double(r.change24h)))
                    Text(RsFmt.compactUsd(r.volume24hUsd)).monospacedDigit()
                    Text(r.funding.map { RsFmt.fraction($0.perHour, digits: 4) } ?? "—").monospacedDigit()
                    Text(RsFmt.compactUsd(r.openInterestUsd)).monospacedDigit()
                    Text(r.sourceDate.map { Fmt.dateSeconds($0) } ?? "non fournie").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    RsRowFlags(row: r)
                }
            }
        }
    }
}

// MARK: - Cost of a hypothetical position across venues (estimate)

private struct RsCompareCard: View {
    @Bindable var data: RsInstrumentModel

    var body: some View {
        Card("Coût estimé d’une position hypothétique, par plateforme", trailing: AnyView(HStack(spacing: 8) { ProvenanceTag(p: .estimate); OpsAsOf(date: data.comparisonAt, prefix: "Reçu") })) {
            Text("Outil de comparaison en lecture seule : le serveur estime, sous les hypothèses qu’il énonce, ce que coûterait UNE position de cette taille sur chaque plateforme. Rien n’est préparé ni placé, et le résultat n’est pas une recommandation.").font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Picker("Sens", selection: $data.side) { Text("Long").tag("long"); Text("Short").tag("short") }.pickerStyle(.segmented).frame(width: 130)
                LabeledContent("Notionnel (USD)") { TextField("1000", text: $data.notional).frame(width: 90).textFieldStyle(.roundedBorder) }
                LabeledContent("Levier") { TextField("2", text: $data.leverage).frame(width: 50).textFieldStyle(.roundedBorder) }
                LabeledContent("Horizon (h)") { TextField("24", text: $data.horizonHours).frame(width: 60).textFieldStyle(.roundedBorder) }
                Picker("Liquidité", selection: $data.liquidity) { Text("Preneur").tag("taker"); Text("Teneur").tag("maker") }.frame(width: 110).labelsHidden()
                Spacer()
                if data.comparing { ProgressView().controlSize(.small) }
                Button("Estimer") { Task { await data.compare() } }.disabled(data.comparisonProblem != nil || data.comparing || data.model.isOffline)
            }
            if let p = data.comparisonProblem { Text(p).font(.caption).foregroundStyle(Theme.negative) }
            if let e = data.comparisonError { Banner(.danger, e) }
            if let c = data.comparison { result(c) }
        }
    }

    @ViewBuilder private func result(_ c: VenueComparison) -> some View {
        Banner(.info, c.texts.disclaimer)
        Text("Demande telle que comprise par le serveur : \(RsJSONText.inline(c.request))").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        if !c.errors.isEmpty { Banner(.warning, "Sources sans réponse : " + c.errors.map { "\($0.source) (\($0.message))" }.joined(separator: " ; ")) }
        ForEach(c.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(Theme.warning) }
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
            GridRow { Text("Plateforme"); Text("Coût total estimé"); Text("Frais entrée / sortie"); Text("Glissement entrée / sortie"); Text("Financement"); Text("Liquidation estimée"); Text("État") }.font(.caption).foregroundStyle(.secondary)
            ForEach(Array(c.rows.enumerated()), id: \.offset) { _, r in
                GridRow(alignment: .top) {
                    VStack(alignment: .leading, spacing: 0) { Text(r.venueName ?? r.venue); Text(r.instrument).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                    if let cost = r.cost {
                        VStack(alignment: .leading, spacing: 0) {
                            figure(cost.totalCostUsd, unit: "USD").fontWeight(.medium)
                            if let b = cost.totalCostBps?.value { Text(RsFmt.bps(b)).font(.caption).foregroundStyle(.secondary) }
                            if let m = cost.missing, !m.isEmpty { Text("Non estimé : \(m.joined(separator: ", ")) — pas de total partiel").font(.caption2).foregroundStyle(Theme.warning) }
                        }
                        VStack(alignment: .leading, spacing: 0) { figure(cost.entryFeeUsd, unit: "USD"); figure(cost.exitFeeUsd, unit: "USD") }
                        VStack(alignment: .leading, spacing: 0) { figure(cost.entrySlippageUsd, unit: "USD"); figure(cost.exitSlippageUsd, unit: "USD") }
                        figure(cost.fundingUsd, unit: "USD")
                        VStack(alignment: .leading, spacing: 0) { figure(cost.liquidationPrice, unit: ""); if let d = cost.liquidationDistanceBps?.value { Text("à \(RsFmt.bps(d))").font(.caption).foregroundStyle(.secondary) } }
                    } else {
                        Text("Indisponible").foregroundStyle(Theme.negative); Text("—"); Text("—"); Text("—"); Text("—")
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        if let e = r.error { Text(e).font(.caption).foregroundStyle(Theme.negative) }
                        if r.stale { ProvenanceTag(p: .stale) }
                        if r.priceOutlier { RsFlag(text: "Prix divergent", color: Theme.negative, symbol: "exclamationmark.triangle") }
                        if !r.tradable { RsFlag(text: "Non négociable", color: .secondary, symbol: "lock").help(r.tradableReason ?? "") }
                        if let f = r.fees { Text("Barème \(f.source), lu le \(f.asOf)").font(.caption2).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        let flagged = c.discrepancies.filter(\.flagged)
        if !c.discrepancies.isEmpty {
            DisclosureGroup("Écarts de prix entre plateformes (\(flagged.count) signalés sur \(c.discrepancies.count))") {
                VStack(alignment: .leading, spacing: 8) {
                    if let t = c.texts.discrepancy { Banner(.warning, t) }
                    ForEach(Array(c.discrepancies.enumerated()), id: \.offset) { _, d in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack { Text("Long \(d.longVenue) / short \(d.shortVenue)").fontWeight(.medium); ProvenanceTag(p: .estimate); if !d.actionableFromWallet { RsFlag(text: "Non réalisable depuis le portefeuille", color: .secondary, symbol: "lock") } }
                            Text("Écart brut \(RsFmt.bps(d.grossGapBps)) · écart net estimé \(RsFmt.bps(d.netEdgeEstimateBps))\(d.reason.map { " · \($0)" } ?? "")").font(.callout).monospacedDigit()
                            if !d.assumptions.isEmpty { Text("Hypothèses : " + d.assumptions.map(\.text).joined(separator: " ; ")).font(.caption).foregroundStyle(.secondary) }
                            if !d.risks.isEmpty { Text("Risques : " + d.risks.map(\.text).joined(separator: " ; ")).font(.caption).foregroundStyle(Theme.warning) }
                        }
                    }
                }.padding(.top, 4)
            }
        }
        if let a = c.texts.assumptions, !a.isEmpty { Text("Hypothèses du serveur : " + a.map(\.text).joined(separator: " ; ")).font(.caption).foregroundStyle(.secondary) }
    }

    private func figure(_ f: CostFigure?, unit: String) -> Text {
        guard let f else { return Text("—") }
        if let v = f.value { return Text("\(RsFmt.price(v))\(unit.isEmpty ? "" : " \(unit)")").monospacedDigit() }
        return Text(f.reason ?? "non estimé").font(.caption).foregroundStyle(.secondary)
    }
}

enum RsJSONText {
    /// A small server value on one line, as served ("—" when absent).
    static func inline(_ v: JSONValue?) -> String {
        guard let v, !v.isNull else { return "—" }
        switch v {
        case .object(let o): return o.keys.sorted().map { "\($0) : \(inline(o[$0]))" }.joined(separator: ", ").opsIfEmpty("—")
        case .array(let a): return a.map { inline($0) }.joined(separator: ", ").opsIfEmpty("—")
        default: return v.displayText
        }
    }
}
