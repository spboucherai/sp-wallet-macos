// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Features/Futures/FuturesExplorerView.swift
// Description      : The read-only secondary tab: the markets hub (every spot
//                    and perpetual market the server lists across venues, with
//                    whether the wallet can trade it and why not), the venue
//                    comparator (an itemised cost ESTIMATE under the
//                    assumptions the server states, with its disclaimer
//                    verbatim) and the private-company contracts (display only
//                    — never tradable from the wallet; an implied valuation is
//                    shown only as an estimate, with its formula and the
//                    published source of that formula). Nothing here can
//                    prepare, place or sign anything.
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

struct FutExplorerView: View {
    let model: AppModel
    let store: FuturesStore
    @State private var section = 0

    var body: some View {
        Picker("Vue", selection: $section) { Text("Tous les marchés").tag(0); Text("Comparateur de plateformes").tag(1); Text("Marchés privés").tag(2) }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 560)
        switch section {
        case 0: FutHubView(model: model, store: store)
        case 1: FutCompareView(model: model, store: store)
        default: FutPrivateMarketsView(model: model, store: store)
        }
    }
}

// MARK: - hub

private struct FutHubView: View {
    let model: AppModel
    let store: FuturesStore
    @State private var list = FutLoaded<HubList>()
    @State private var search = ""
    @State private var kind = "perp"
    @State private var sort: HubQuery.Sort = .volume
    @State private var selection: String?

    private var queryId: String { "\(search)|\(kind)|\(sort.rawValue)" }

    private func load() async {
        let id = queryId
        list.loading = true
        try? await Task.sleep(for: .milliseconds(350))   // typing in the search field: one request once it settles
        guard !Task.isCancelled, id == queryId else { return }
        do {
            let l = try await store.markets.list(HubQuery(kind: kind.isEmpty ? nil : kind, search: search, sort: sort, descending: sort != .symbol, limit: 300))
            if id == queryId { list.set(l) }
        } catch { if id == queryId { list.fail(model.describe(error)) } }
    }

    var body: some View {
        Card("Explorateur de marchés", trailing: AnyView(ProvenanceTag(p: .estimate, text: "Lecture seule"))) {
            HStack {
                TextField("Rechercher", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 240)
                Picker("Type", selection: $kind) { Text("Perpétuels").tag("perp"); Text("Comptant").tag("spot"); Text("Tous").tag("") }.frame(maxWidth: 200)
                Picker("Tri", selection: $sort) {
                    Text("Volume").tag(HubQuery.Sort.volume); Text("Intérêt ouvert").tag(HubQuery.Sort.openInterest); Text("Financement").tag(HubQuery.Sort.funding); Text("Variation").tag(HubQuery.Sort.change); Text("Symbole").tag(HubQuery.Sort.symbol)
                }.frame(maxWidth: 220)
                Spacer()
                if list.loading { ProgressView().controlSize(.small) }
                if let l = list.value { Text("\(l.rows.count) sur \(l.total)" + (l.counts.map { " · \($0.stale) périmé(s)" } ?? "")).font(.caption).foregroundStyle(.secondary) }
            }
            if let e = list.error { Banner(.danger, "Explorateur indisponible : \(e)") }
            if let l = list.value {
                ForEach(l.errors, id: \.self) { Banner(.warning, "Source illisible — liste PARTIELLE : \($0.source) : \($0.message)") }
                ForEach(l.venues.filter { $0.status != "ok" || $0.restriction != nil }) { v in
                    Text("\(v.name) : \(v.status)" + (v.error.map { " — \($0)" } ?? "") + (v.restriction.map { " — \($0)" } ?? "")).font(.caption).foregroundStyle(Theme.warning).fixedSize(horizontal: false, vertical: true)
                }
                Table(l.rows, selection: $selection) {
                    TableColumn("Marché") { r in HStack(spacing: 6) { Text(r.symbol).fontWeight(.medium); Text(r.kind == "perp" ? "perp" : "spot").font(.caption2).foregroundStyle(.secondary); if r.stale { Image(systemName: "clock.badge.exclamationmark").foregroundStyle(Theme.warning).help("Donnée périmée") } } }.width(min: 130, ideal: 170)
                    TableColumn("Plateforme") { r in Text(r.venueName ?? r.venue).font(.callout) }.width(min: 90, ideal: 120)
                    TableColumn("Prix") { r in Text(FutNum.exact(r.price)).monospacedDigit().help(r.priceKind == "close_1h" ? "Clôture de la dernière barre horaire consolidée" : "Prix mark de la plateforme") }.width(min: 90, ideal: 120)
                    TableColumn("24 h") { r in Text(FutNum.pct(fraction: r.change24h)).monospacedDigit().foregroundStyle(Theme.change(FutNum.d(r.change24h))) }.width(min: 70, ideal: 80)
                    TableColumn("Volume 24 h") { r in Text(FutNum.compactUSD(r.volume24hUsd)).monospacedDigit() }.width(min: 90, ideal: 110)
                    TableColumn("Intérêt ouvert") { r in Text(FutNum.compactUSD(r.openInterestUsd)).monospacedDigit() }.width(min: 90, ideal: 110)
                    TableColumn("Financement / h") { r in Text(r.funding.map { FutNum.pct(fraction: $0.perHour, digits: 4) } ?? "—").monospacedDigit() }.width(min: 100, ideal: 120)
                    TableColumn("Depuis ce portefeuille") { r in
                        Text(r.tradable ? "négociable côté serveur" : (r.tradableReason ?? r.restriction ?? "non négociable")).font(.caption).foregroundStyle(r.tradable ? .secondary : Theme.warning).lineLimit(2).help(r.tradableReason ?? r.restriction ?? "")
                    }.width(min: 160, ideal: 260)
                }.frame(height: 460)
                if let id = selection, let r = l.rows.first(where: { $0.id == id }) {
                    Text("\(r.id) — source : \(r.source)" + (r.sourceDate.map { " · \(Fmt.relative($0))" } ?? "") + (r.priceOutlier == true ? " · PRIX ABERRANT par rapport aux autres sources" : "") + (r.mapping?.note.map { " · \($0)" } ?? "")).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            } else if list.error == nil { ProgressView().frame(maxWidth: .infinity, minHeight: 80) }
            Text("« Négociable côté serveur » décrit ce que le serveur permettrait, verrous compris ; cette app ne propose de nouveaux ordres que sur la plateforme offerte dans l’onglet Marchés.").font(.caption).foregroundStyle(.secondary)
        }
        .task(id: queryId) { await load() }
    }
}

// MARK: - comparator

private struct FutCompareView: View {
    let model: AppModel
    let store: FuturesStore
    @State private var underlying = ""
    @State private var side = "long"
    @State private var notional = ""
    @State private var leverage = "1"
    @State private var horizon = "24"
    @State private var result = FutLoaded<VenueComparison>()

    private var query: CompareQuery? {
        let u = underlying.trimmingCharacters(in: .whitespaces).uppercased()
        guard !u.isEmpty, let n = FutNum.input(notional), let l = FutNum.input(leverage), let h = FutNum.input(horizon) else { return nil }
        return CompareQuery(underlying: u, side: side, notional: n, leverage: l, horizonHours: h)
    }

    var body: some View {
        Card("Comparateur de plateformes", trailing: AnyView(ProvenanceTag(p: .estimate, text: "Estimations — lecture seule"))) {
            HStack {
                TextField("Sous-jacent (ex. BTC)", text: $underlying).textFieldStyle(.roundedBorder).frame(width: 150)
                Picker("Sens", selection: $side) { Text("Long").tag("long"); Text("Short").tag("short") }.pickerStyle(.segmented).labelsHidden().frame(width: 130)
                TextField("Notionnel ($)", text: $notional).textFieldStyle(.roundedBorder).frame(width: 130)
                TextField("Levier", text: $leverage).textFieldStyle(.roundedBorder).frame(width: 70).help("Hypothèse de calcul uniquement ; part de 1×")
                TextField("Horizon (h)", text: $horizon).textFieldStyle(.roundedBorder).frame(width: 90)
                Spacer()
                if result.loading { ProgressView().controlSize(.small) }
                Button("Comparer") {
                    guard let q = query else { return }
                    result.loading = true
                    Task { do { result.set(try await store.markets.compare(q)) } catch { result.fail(model.describe(error)) } }
                }.disabled(query == nil || result.loading)
            }
            if let e = result.error { Banner(.danger, "Comparaison indisponible : \(e)") }
            if let c = result.value {
                Banner(.info, c.texts.disclaimer)
                ForEach(c.warnings, id: \.self) { Banner(.warning, $0) }
                ForEach(c.errors, id: \.self) { Banner(.warning, "\($0.source) illisible : \($0.message)") }
                ForEach(c.rows, id: \.instrument) { r in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(r.venueName ?? r.venue).fontWeight(.semibold); Text(r.instrument).font(.caption).foregroundStyle(.secondary)
                            if r.stale { ProvenanceTag(p: .stale) }
                            if r.priceOutlier { ProvenanceTag(p: .stale, text: "Prix aberrant") }
                            Spacer()
                            Text(r.tradable ? "négociable côté serveur" : (r.tradableReason ?? r.restriction ?? "non négociable")).font(.caption).foregroundStyle(r.tradable ? .secondary : Theme.warning).lineLimit(2)
                        }
                        if let e = r.error { Text("Illisible : \(e)").font(.callout).foregroundStyle(Theme.negative) }
                        if let k = r.cost {
                            FutStatGrid(minimum: 150) {
                                figure("Coût total estimé", k.totalCostUsd, unit: " $")
                                figure("Coût total (pb)", k.totalCostBps, unit: " pb")
                                figure("Frais d’entrée", k.entryFeeUsd, unit: " $")
                                figure("Glissement d’entrée", k.entrySlippageUsd, unit: " $")
                                figure("Financement sur l’horizon", k.fundingUsd, unit: " $")
                                figure("Collatéral requis", k.collateralRequiredUsd, unit: " $")
                                figure("Liquidation estimée", k.liquidationPrice, unit: "")
                                figure("Levier max", k.maxLeverage, unit: "×")
                            }
                            if let m = k.missing, !m.isEmpty { Text("Postes non estimables : \(m.joined(separator: ", ")) — aucun total n’est présenté sans eux.").font(.caption).foregroundStyle(Theme.warning) }
                            if let a = k.assumptions, !a.isEmpty { Text("Hypothèses : \(a.joined(separator: " · "))").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                        }
                        if let f = r.fees { Text("Barème utilisé : preneur \(f.takerRate), teneur \(f.makerRate) — \(f.source), lu le \(f.asOf)").font(.caption).foregroundStyle(.secondary) }
                    }.padding(10).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }
                ForEach(Array(c.discrepancies.enumerated()), id: \.offset) { _, d in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Écart de prix \(d.longVenue) / \(d.shortVenue) : brut \(d.grossGapBps.map { FutNum.exact($0, maxFraction: 1) + " pb" } ?? "—"), net estimé \(d.netEdgeEstimateBps.map { FutNum.exact($0, maxFraction: 1) + " pb" } ?? "—")" + (d.reason.map { " — \($0)" } ?? "")).font(.callout)
                        ForEach(d.risks, id: \.code) { Text("Risque : \($0.text)").font(.caption).foregroundStyle(Theme.warning).fixedSize(horizontal: false, vertical: true) }
                        Text("Un écart est une estimation, jamais une instruction de négocier.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func figure(_ label: String, _ f: CostFigure?, unit: String) -> some View {
        FutStat(label, f.map { $0.value.map { "≈ " + FutNum.exact($0, maxFraction: 4) + unit } ?? "non calculable" } ?? "—", note: f?.value == nil ? f?.reason : f?.basis)
    }
}

// MARK: - private markets

private struct FutPrivateMarketsView: View {
    let model: AppModel
    let store: FuturesStore
    @State private var list = FutLoaded<PrivateMarketList>()
    @State private var selection: String?

    var body: some View {
        Card("Contrats sur sociétés privées", trailing: AnyView(ProvenanceTag(p: .unavailable, text: "Affichage seulement — non négociable"))) {
            if let e = list.error { Banner(.danger, "Marchés privés indisponibles : \(e)") }
            if let l = list.value {
                Banner(.warning, l.notice.text)
                ForEach(l.venues.filter { $0.status != "ok" }, id: \.venue) { v in Text("\(v.name ?? v.venue) : \(v.status)" + (v.error.map { " — \($0)" } ?? "")).font(.caption).foregroundStyle(Theme.warning) }
                Table(l.markets, selection: $selection) {
                    TableColumn("Société") { m in Text(m.company?.name ?? "—").fontWeight(.medium) }.width(min: 120, ideal: 160)
                    TableColumn("Contrat") { m in Text("\(m.symbol) · \(m.platform ?? m.venue)").font(.callout) }.width(min: 130, ideal: 180)
                    TableColumn("État") { m in Text(m.status + (m.market.frozen == true ? " · prix gelé" : "")).font(.caption).foregroundStyle(m.status == "live" ? .secondary : Theme.warning) }.width(min: 80, ideal: 110)
                    TableColumn("Prix synthétique") { m in
                        HStack(spacing: 4) { Text(FutNum.exact(m.valuation.syntheticPrice.value)).monospacedDigit(); if m.valuation.syntheticPrice.stale { Image(systemName: "clock.badge.exclamationmark").foregroundStyle(Theme.warning).help("Périmé") } }
                    }.width(min: 100, ideal: 130)
                    TableColumn("Unité") { m in Text(m.review.isReviewed ? m.contract.unit.label : "fiche non revue").font(.caption).foregroundStyle(.secondary).lineLimit(2) }.width(min: 110, ideal: 170)
                    TableColumn("Valorisation implicite (estimation)") { m in
                        let v = m.valuation.impliedValuation
                        Text(v.isDerived ? "≈ " + FutNum.compactUSD(v.value) : (v.reason ?? "non dérivée")).font(.callout).foregroundStyle(v.isDerived ? .primary : .secondary).lineLimit(2)
                    }.width(min: 170, ideal: 240)
                }.frame(height: 320)
                if let id = selection, let m = l.markets.first(where: { $0.id == id }) { detail(m) }
                else { Text("Sélectionnez un contrat pour voir la formule de sa valorisation implicite et sa source.").font(.caption).foregroundStyle(.secondary) }
                if let ex = l.excluded, !ex.isEmpty { Text("Contrats exclus par le serveur : " + ex.map { "\($0.id) (\($0.reason))" }.joined(separator: " ; ")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            } else if list.error == nil { ProgressView().frame(maxWidth: .infinity, minHeight: 80) }
        }
        .task { do { list.set(try await store.markets.privateMarkets()) } catch { list.fail(model.describe(error)) } }
    }

    @ViewBuilder private func detail(_ m: PrivateMarket) -> some View {
        let v = m.valuation, imp = v.impliedValuation
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text("\(m.company?.name ?? m.symbol) — \(m.id)").font(.headline); Spacer(); ProvenanceTag(p: .estimate, text: "Estimations") }
            if let nt = m.notTradable { Banner(.warning, "Non négociable depuis ce portefeuille [\(nt.code)] : \(nt.reasons.joined(separator: " ; "))") }
            if let e = m.error { Banner(.danger, e) }
            Field(label: "Prix synthétique", value: "\(FutNum.exact(v.syntheticPrice.value)) (\(v.syntheticPrice.priceKind ?? "mark")) — source \(v.syntheticPrice.source)" + (FutNum.ms(v.syntheticPrice.ts).map { ", \(Fmt.relative($0))" } ?? "") + (v.syntheticPrice.stale ? " — PÉRIMÉ" : ""))
            Field(label: "Fiche du contrat", value: "\(m.review.state)" + (m.review.validUntil.map { " · valide jusqu’au \($0)" } ?? "") + (m.review.reasons.isEmpty ? "" : " · \(m.review.reasons.joined(separator: " ; "))"))
            if imp.isDerived {
                Field(label: "Valorisation implicite", value: "≈ \(FutNum.exact(imp.value, maxFraction: 0)) $ — ESTIMATION" + (imp.label.map { " (\($0))" } ?? ""), emphasis: true)
                Field(label: "Formule", value: imp.formula ?? "—")
                if let s = imp.formulaSource {
                    Field(label: "Source publiée de la formule", value: "« \(s.quote) » — lu le \(s.readAt)")
                    if let url = URL(string: s.url), url.scheme == "https" { Link(s.url, destination: url).font(.caption) }
                }
            } else {
                Field(label: "Valorisation implicite", value: "non dérivée : \(imp.reason ?? imp.reasonCode ?? "raison non précisée")")
            }
            if let last = v.lastPrivateValuation {
                Field(label: "Dernière valorisation privée", value: "\(last.valueUsd.map { FutNum.compactUSD($0) } ?? last.value ?? "—") — \(last.kind), \(last.date), confiance \(last.confidence) — \(last.detail)")
                if let url = URL(string: last.sourceUrl), url.scheme == "https" { Link(last.sourceUrl, destination: url).font(.caption) }
            } else if let why = v.lastPrivateValuationReason { Field(label: "Dernière valorisation privée", value: "aucune : \(why)") }
            Field(label: "Prime / décote", value: v.premiumDiscount.premiumBps.map { "\(FutNum.exact($0, maxFraction: 0)) pb" + (v.premiumDiscount.caveat.map { " — \($0)" } ?? "") } ?? "non calculable : \(v.premiumDiscount.reason ?? "—")")
            ForEach(v.caveats, id: \.code) { Text("⚠︎ \($0.text)").font(.caption).foregroundStyle(Theme.warning).fixedSize(horizontal: false, vertical: true) }
            if let n = m.contract.nature { Field(label: "Nature du contrat", value: n) }
            if let s = m.contract.settlement { Field(label: "Règlement", value: s) }
            if let i = m.contract.ipoConversion { Field(label: "En cas d’introduction en bourse", value: i) }
        }.padding(10).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}
