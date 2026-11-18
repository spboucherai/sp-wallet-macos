// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/Dashboard/DashboardView.swift
// Description: The overview: estimated total, allocation, value history as observed by this Mac, pending and recent transactions, open derivative positions (real, testnet and paper books kept apart), unread alerts and the MacLustr connection state. Each block states where its figures come from; a block whose source failed says so instead of showing zero.
import SwiftUI
import Charts
import SPWalletCore

struct DashboardView: View {
    let model: AppModel
    @Bindable var nav: Navigator
    @State private var summary: DashboardSummary?
    @State private var summaryError: String?
    @State private var unread: AlertUnread?
    @State private var history: [ValuePoint] = []
    @State private var range = 30

    var body: some View {
        Page("Tableau de bord") {
            BalanceCard(model: model, nav: nav)
            statTiles
            HStack(alignment: .top, spacing: 16) {
                AllocationCard(model: model, by: .asset)
                AllocationCard(model: model, by: .network)
            }
            historyCard
            HStack(alignment: .top, spacing: 16) {
                recentCard
                VStack(spacing: 16) { connectionCard; alertsCard }
            }
            positionsCard
        }
        .task(id: model.portfolio?.fetchedAt) { await load() }
    }

    private func load() async {
        history = await ValueHistory.shared.series(currency: model.currency, since: Date().addingTimeInterval(-Double(range) * 86400))
        guard model.phase == .signedIn, !model.isOffline else { return }
        do { summary = try await DashboardAPI(model.client).summary(); summaryError = nil } catch { summaryError = model.describe(error) }
        unread = try? await AlertsAPI(model.client).unread()
    }

    private var statTiles: some View {
        let p = model.portfolio?.value
        let held = p?.balances.filter(\.isNonZero) ?? []
        let (level, text) = SecurityIndicator.assess(model)
        let nets = model.health?.value.networks ?? []
        let bad = nets.filter { $0.ok == false }.count
        return HStack(spacing: 14) {
            StatTile(symbol: "circle.hexagongrid.fill", label: "Actifs détenus", value: p == nil ? "—" : "\(held.count)", tint: Theme.series(0), detail: p == nil ? nil : "sur \(Set(held.map(\.network)).count) réseau(x)")
            StatTile(symbol: "network", label: "Réseaux joignables", value: nets.isEmpty ? "—" : "\(nets.count - bad) / \(nets.count)", tint: bad == 0 ? Theme.series(1) : Theme.warning, detail: nets.isEmpty ? "non mesuré" : bad == 0 ? "tous les RPC répondent" : "\(bad) RPC en échec")
            StatTile(symbol: "arrow.triangle.2.circlepath", label: "Opérations en cours", value: p == nil ? "—" : "\(p!.pending.count)", tint: Theme.series(4), detail: (p?.pending.isEmpty ?? true) ? "aucune en attente" : "à suivre dans Activité")
            StatTile(symbol: level.symbol, label: "Signataire isolé", value: level == .ok ? "Prêt" : level == .blocked ? "Arrêté" : level == .degraded ? "Dégradé" : "Inconnu", tint: level.color, detail: text)
        }
    }

    private var historyCard: some View {
        Card("Historique de la valeur estimée", trailing: AnyView(Picker("", selection: $range) { Text("7 j").tag(7); Text("30 j").tag(30); Text("1 an").tag(365) }.pickerStyle(.segmented).frame(width: 170).onChange(of: range) { Task { await load() } })) {
            if history.count >= 2 {
                Chart(history) { p in
                    AreaMark(x: .value("Date", p.at), y: .value("Valeur", p.value)).interpolationMethod(.linear)
                        .foregroundStyle(LinearGradient(colors: [Theme.azure.opacity(0.28), Theme.azure.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Date", p.at), y: .value("Valeur", p.value)).interpolationMethod(.linear).foregroundStyle(Theme.azure).lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    if !p.complete { PointMark(x: .value("Date", p.at), y: .value("Valeur", p.value)).foregroundStyle(Theme.warning).symbolSize(18) }
                }
                .chartYScale(domain: .automatic(includesZero: false)).frame(height: 190)
                .chartXAxis { AxisMarks { _ in AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3])); AxisValueLabel() } }
                .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let d = v.as(Double.self) { Text(Fmt.compact(d, model.currency)) } } } }
            } else {
                Text("Pas encore assez de points.").foregroundStyle(.secondary).frame(height: 60)
            }
            Text("Estimations (soldes × prix affichés) relevées par ce Mac quand l’app était ouverte ; le serveur ne conserve pas cette série. Les interruptions sont de vraies absences de mesure\(history.contains { !$0.complete } ? " ; points orange = total incomplet" : "").").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var recentCard: some View {
        Card("Transactions", trailing: AnyView(Button("Tout voir") { nav.section = .activity }.buttonStyle(.link))) {
            let pending = model.portfolio?.value.pending ?? []
            if !pending.isEmpty {
                Text("En cours").font(.caption).foregroundStyle(.secondary)
                ForEach(pending) { p in
                    HStack { Text("\(Fmt.amount(p.amountDisplay, maxFraction: 8)) \(p.symbol) · \(p.networkName ?? p.network)"); Spacer(); StatusPill(raw: p.state.rawValue) }
                }
                Divider()
            }
            let items = (model.activity?.value ?? []).prefix(6)
            if items.isEmpty { Text(model.activity == nil ? "Historique non synchronisé." : "Aucune transaction.").foregroundStyle(.secondary) }
            ForEach(Array(items)) { TransactionRow(item: $0) }
        }
    }

    private var connectionCard: some View {
        Card("Connexion MacLustr") {
            SecurityIndicator(model: model)
            if let h = model.health?.value {
                let bad = h.networks.filter { $0.ok == false }
                Field(label: "Base de données", value: h.db ? "joignable" : "en échec")
                Field(label: "Réseaux (RPC)", value: bad.isEmpty ? "\(h.networks.count) joignables" : "\(bad.count) en échec sur \(h.networks.count) : " + bad.compactMap(\.network).joined(separator: ", "))
                Text("Relevé \(Fmt.relative(model.health?.fetchedAt))").font(.caption).foregroundStyle(.secondary)
            } else { Text("État des réseaux non lu.").foregroundStyle(.secondary) }
            if case .ok(let d, _)? = summary?.health, !d.connectors.failing.isEmpty {
                Text("Connecteurs en échec : " + d.connectors.failing.map(\.name).joined(separator: ", ")).font(.callout).foregroundStyle(Theme.warning)
            }
        }
    }

    private var alertsCard: some View {
        Card("Alertes", trailing: AnyView(Button("Ouvrir") { nav.section = .alerts }.buttonStyle(.link))) {
            if let u = unread {
                HStack(spacing: 16) {
                    Label("\(u.unread) non lue(s)", systemImage: "bell").foregroundStyle(u.unread > 0 ? .primary : .secondary)
                    if u.critical > 0 { Label("\(u.critical) critique(s)", systemImage: "exclamationmark.octagon.fill").foregroundStyle(Theme.negative) }
                }
            } else { Text("Compteur d’alertes non lu.").foregroundStyle(.secondary) }
            if case .ok(let r, _)? = summary?.risk {
                if r.switches.killSwitch.on { Banner(.danger, "Arrêt global du trading engagé\(r.switches.killSwitch.reason.map { " : \($0)" } ?? "").") }
                if r.switches.readOnly.on { Banner(.warning, "Trading en lecture seule.") }
            }
        }
    }

    @ViewBuilder private var positionsCard: some View {
        Card("Positions ouvertes (dérivés)", trailing: AnyView(Button("Contrats à terme") { nav.section = .futures }.buttonStyle(.link))) {
            if let s = summary {
                bookRows("Réel", s.books.live, color: Theme.negative)
                bookRows("Testnet", s.books.liveTestnet, color: Theme.warning)
                bookRows("Simulation (papier)", s.books.paper, color: .secondary)
                Text("Trois livres séparés : aucun chiffre du papier ou du testnet n’est additionné au réel.").font(.caption).foregroundStyle(.secondary)
            } else if let e = summaryError { Text("Indisponible : \(e)").foregroundStyle(.secondary) }
            else { Text(model.canOperate ? "Lecture…" : "Indisponible hors connexion.").foregroundStyle(.secondary) }
        }
    }
    @ViewBuilder private func bookRows(_ title: String, _ sec: DashboardSection<DashboardBook>, color: Color) -> some View {
        HStack { Text(title).font(.callout.weight(.semibold)).foregroundStyle(color); Spacer()
            if let a = sec.asOf { Text("relevé \(Fmt.relative(a))").font(.caption).foregroundStyle(.secondary) } }
        switch sec {
        case .failed(let code, _): Label("Indisponible (\(code)) — ce n’est pas « aucune position ».", systemImage: "xmark.octagon").foregroundStyle(Theme.warning).font(.callout)
        case .ok(let b, _):
            if b.positions.isEmpty { Text("Aucune position.").foregroundStyle(.secondary).font(.callout) }
            ForEach(b.positions, id: \.self) { p in
                HStack {
                    Text("\(p.instrument) · \(p.venue)").frame(width: 220, alignment: .leading)
                    Text(p.side == "long" ? "LONG" : "SHORT").font(.caption.weight(.bold)).foregroundStyle(p.side == "long" ? Theme.positive : Theme.negative).frame(width: 50)
                    Text("\(Fmt.amount(p.size, maxFraction: 6)) · notionnel \(Fmt.amount(p.notional, maxFraction: 2)) $ · levier \(Fmt.amount(p.leverage, maxFraction: 2))×").monospacedDigit()
                    Spacer()
                    Text("liq. \(p.liquidationPrice.map { Fmt.amount($0, maxFraction: 4) } ?? "—")").foregroundStyle(Theme.warning).monospacedDigit()
                    Text("PnL latent \(Fmt.amount(p.unrealizedPnl, maxFraction: 2)) $").monospacedDigit().foregroundStyle(p.unrealizedPnl.hasPrefix("-") ? Theme.negative : Theme.positive)
                }.font(.callout)
            }
            if !b.isComplete { Text("Lecture partielle : \(b.errors.joined(separator: " ; "))").font(.caption).foregroundStyle(Theme.warning) }
        }
    }
}

/// Share of the estimated total per asset or per network (an estimate: balances × prices).
struct AllocationCard: View {
    enum Axis { case asset, network }
    let model: AppModel
    let by: Axis
    struct Slice: Identifiable { let id: String; let value: Double }

    var slices: [Slice] {
        guard let p = model.portfolio?.value, p.prices != nil, model.settings.prices else { return [] }
        var sums: [String: Double] = [:]
        for b in p.balances { if let v = p.estimatedValue(of: b, in: model.currency), v > 0 { sums[by == .asset ? b.symbol : b.networkName, default: 0] += v } }
        let sorted = sums.sorted { $0.value > $1.value }
        let top = sorted.prefix(7).map { Slice(id: $0.key, value: $0.value) }
        let rest = sorted.dropFirst(7).reduce(0) { $0 + $1.value }
        return rest > 0 ? top + [Slice(id: "Autres", value: rest)] : top
    }
    var body: some View {
        Card(by == .asset ? "Répartition par actif" : "Répartition par blockchain", trailing: AnyView(ProvenanceTag(p: .estimate))) {
            let s = slices; let total = s.reduce(0) { $0 + $1.value }
            if s.isEmpty { Text("Aucune valeur estimable (pas de solde, ou prix indisponibles).").foregroundStyle(.secondary).frame(height: 150) }
            else {
                HStack(spacing: 20) {
                    Chart(Array(s.enumerated()), id: \.element.id) { i, x in
                        SectorMark(angle: .value("Valeur", x.value), innerRadius: .ratio(0.68), angularInset: 1.5).cornerRadius(4).foregroundStyle(Theme.series(i))
                    }
                    .chartLegend(.hidden).frame(width: 150, height: 150).opacity(model.settings.hideBalances ? 0.25 : 1)
                    .overlay { VStack(spacing: 0) { Text("\(s.count)").font(Theme.figure(24)); Text(by == .asset ? "actifs" : "réseaux").font(.caption2).foregroundStyle(.secondary) } }
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(s.enumerated()), id: \.element.id) { i, x in
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 3).fill(Theme.series(i)).frame(width: 10, height: 10)
                                Text(x.id).lineLimit(1)
                                Spacer()
                                Text((x.value / total).formatted(.percent.precision(.fractionLength(1)))).monospacedDigit().foregroundStyle(.secondary)
                                Text(model.settings.hideBalances ? "••••" : Fmt.fiat(x.value, model.currency, estimate: false)).monospacedDigit().fontWeight(.medium).frame(width: 110, alignment: .trailing)
                            }.font(.callout)
                        }
                    }
                }
            }
        }
    }
}
