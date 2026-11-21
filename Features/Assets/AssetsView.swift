// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Features/Assets/AssetsView.swift
// Description      : Tokens and coins: every asset of the backend's registry
//                    with its network, contract, decimals, exact balance and
//                    estimated value; a detail pane with the price chart
//                    (observed market data, labelled with its source), market
//                    facts and the asset's transactions. The registry is
//                    curated server-side: this app cannot add an arbitrary
//                    token, and says so.
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
import Charts
import SPWalletCore

struct AssetsView: View {
    let model: AppModel
    @Bindable var nav: Navigator
    @State private var search = ""
    @State private var heldOnly = true
    @State private var selection: String?

    private var rows: [Balance] {
        guard let p = model.portfolio?.value else { return [] }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return p.balances.filter { b in
            (!heldOnly || b.isNonZero || !b.isAvailable) &&
            (q.isEmpty || b.symbol.lowercased().contains(q) || b.name.lowercased().contains(q) || b.networkName.lowercased().contains(q) || b.asset.lowercased() == q)
        }.sorted { a, b in (p.estimatedValue(of: a, in: model.currency) ?? -1) > (p.estimatedValue(of: b, in: model.currency) ?? -1) }
    }

    var body: some View {
        // an HStack, not an HSplitView: the AppKit split view ignores the detail column's safe-area insets and its minimum widths push the sidebar out of the window
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    TextField("Rechercher (symbole, nom, réseau, contrat)", text: $search).textFieldStyle(.roundedBorder)
                    Toggle("Détenus", isOn: $heldOnly).toggleStyle(.checkbox)
                }.padding(12)
                Divider()
                if let p = model.portfolio?.value {
                    List(rows, selection: $selection) { b in
                        AssetRow(balance: b, portfolio: p, currency: model.currency, hide: model.settings.hideBalances, cached: model.portfolio?.fromCache ?? false).tag(b.id)
                    }
                    .overlay { if rows.isEmpty { EmptyState(symbol: "magnifyingglass", title: heldOnly ? "Aucun actif détenu ne correspond" : "Aucun actif ne correspond", detail: "Les jetons affichés sont ceux du registre vérifié du backend (émetteur, CoinGecko et chaîne concordants).") } }
                } else { EmptyState(symbol: "tray", title: "Soldes non synchronisés") }
                Divider()
                Text("Le registre des jetons est tenu côté serveur et vérifié contre l’émetteur et la chaîne. L’ajout d’un jeton personnalisé n’est pas pris en charge par le backend : un nom ou un logo ne prouve rien, seul le contrat identifie un jeton.")
                    .font(.caption).foregroundStyle(.secondary).padding(10).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 500)
            Divider()
            Group {
                if let id = selection, let b = model.portfolio?.value.balances.first(where: { $0.id == id }) { AssetDetail(model: model, nav: nav, balance: b).id(id) }
                else { EmptyState(symbol: "bitcoinsign.circle", title: "Choisissez un actif") }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Backdrop())
        .onAppear { if let f = nav.assetFocus { selection = f; heldOnly = false; nav.assetFocus = nil } }
        .onChange(of: nav.assetFocus) { if let f = nav.assetFocus { selection = f; nav.assetFocus = nil } }
    }
}

struct AssetDetail: View {
    let model: AppModel
    @Bindable var nav: Navigator
    let balance: Balance
    @State private var days = 7
    @State private var chart: MarketChart?
    @State private var chartError: String?

    var body: some View {
        let net = model.network(balance.network), def = net?.asset(balance.asset)
        let p = model.portfolio?.value, price = model.price(balance.symbol)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    AssetBadge(symbol: balance.symbol, size: 44)
                    VStack(alignment: .leading) { Text(balance.name).font(.title2.weight(.semibold)); Text("\(balance.symbol) sur \(balance.networkName)").foregroundStyle(.secondary) }
                    Spacer()
                    Button("Envoyer") { nav.send(network: balance.network, asset: balance.asset) }.disabled(!model.canOperate || !balance.isNonZero)
                    Button("Recevoir") { nav.section = .receive }
                }
                Card("Solde") {
                    if balance.isAvailable {
                        Text(model.settings.hideBalances ? "••••" : "\(Fmt.amount(balance.display)) \(balance.symbol)").font(.title.weight(.semibold)).monospacedDigit().textSelection(.enabled)
                        HStack { ProvenanceTag(p: model.portfolio?.fromCache == true ? .stale : .verified, text: model.portfolio?.fromCache == true ? "Synchronisé le \(Fmt.date(model.portfolio?.fetchedAt))" : "Lu sur la chaîne \(Fmt.relative(p?.asOf))")
                            if let p, let v = p.estimatedValue(of: balance, in: model.currency) { Text(model.settings.hideBalances ? "" : Fmt.fiat(v, model.currency)).foregroundStyle(.secondary) } }
                    } else { Banner(.danger, "Solde indisponible : la lecture de la chaîne a échoué (\(balance.error ?? "sans détail")). Ce n’est pas un solde nul.") }
                }
                Card("Identité de l’actif") {
                    Field(label: "Réseau", value: "\(balance.networkName) (\(balance.network))")
                    Field(label: balance.asset == "native" ? "Type" : "Contrat", value: balance.asset == "native" ? "Monnaie native du réseau" : balance.asset, mono: balance.asset != "native")
                    Field(label: "Décimales", value: String(balance.decimals))
                    if let o = def?.onchainSymbol, o != balance.symbol { Field(label: "Symbole sur la chaîne", value: o) }
                    if let prog = def?.program { Field(label: "Programme", value: prog, mono: true) }
                    ProvenanceTag(p: .verified, text: "Jeton du registre vérifié du backend")
                    if balance.asset != "native", let ex = net?.explorerAddr, let u = URL(string: ex + balance.asset), u.scheme == "https" { Link("Voir le contrat dans l’explorateur", destination: u) }
                }
                Card("Prix", trailing: AnyView(Picker("", selection: $days) { Text("24 h").tag(1); Text("7 j").tag(7); Text("30 j").tag(30); Text("1 an").tag(365) }.pickerStyle(.segmented).frame(width: 220))) {
                    if let price {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(Fmt.price(price.value(in: model.currency), model.currency)).font(.title2.weight(.semibold)).monospacedDigit()
                            Text("24 h \(Fmt.percent(price.change24h))").foregroundStyle(Theme.change(price.change24h))
                            Text("7 j \(Fmt.percent(price.change7d))").foregroundStyle(Theme.change(price.change7d))
                            Spacer()
                            ProvenanceTag(p: price.stale ? .stale : .estimate, text: "Observé · \(price.source ?? "source inconnue")\(price.fallback == true ? " (secours)" : "") · \(Fmt.relative(price.priceAt))")
                        }
                        if price.divergent == true { Banner(.warning, "Les deux sources de prix divergent au-delà du seuil : traitez ce prix avec prudence.") }
                    } else { Text(model.settings.prices ? "Aucun prix pour cet actif." : "Prix désactivés dans les réglages.").foregroundStyle(.secondary) }
                    if let c = chart, c.points.count > 1 {
                        Chart(c.points, id: \.t) { LineMark(x: .value("Date", $0.date), y: .value("Prix", $0.p)).foregroundStyle(Theme.accent) }
                            .chartYScale(domain: .automatic(includesZero: false)).frame(height: 200)
                    } else if let e = chartError { Text("Graphique indisponible : \(e)").foregroundStyle(.secondary) }
                    else if price != nil { Text(model.isOffline ? "Graphique indisponible hors connexion." : "Aucune série de prix.").foregroundStyle(.secondary).frame(height: 40) }
                    if let m = price {
                        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 4) {
                            GridRow { Text("Capitalisation").foregroundStyle(.secondary); Text(Fmt.compact(m.marketCap, .usd)); Text("Volume 24 h").foregroundStyle(.secondary); Text(Fmt.compact(m.volume24h, .usd)) }
                            GridRow { Text("Plus haut 24 h").foregroundStyle(.secondary); Text(Fmt.price(m.high24h, .usd)); Text("Plus bas 24 h").foregroundStyle(.secondary); Text(Fmt.price(m.low24h, .usd)) }
                            GridRow { Text("Rang").foregroundStyle(.secondary); Text(m.rank.map(String.init) ?? "—"); Text("Sommet historique").foregroundStyle(.secondary); Text(Fmt.price(m.ath, .usd)) }
                        }.font(.callout)
                        Text("Données de marché observées (en USD), non vérifiées par cette app ; ce ne sont ni des conseils ni des prévisions.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Card("Transactions de cet actif") {
                    let items = (model.activity?.value ?? []).filter { $0.network == balance.network && ($0.asset == balance.asset || ($0.asset == nil && $0.symbol == balance.symbol)) }
                    if items.isEmpty { Text("Aucune transaction enregistrée pour cet actif.").foregroundStyle(.secondary) }
                    ForEach(items.prefix(25)) { TransactionRow(item: $0) }
                    if items.count > 25 { Button("Voir tout dans Activité") { nav.section = .activity }.buttonStyle(.link) }
                }
            }.padding(20)
        }
        .task(id: days) { await loadChart() }
    }
    private func loadChart() async {
        guard model.phase == .signedIn, !model.isOffline, model.settings.prices else { return }
        do { chart = try await model.wallet.chart(symbol: balance.symbol, days: days, currency: model.currency); chartError = nil } catch { chartError = model.describe(error) }
    }
}
