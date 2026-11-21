// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Features/Research/RsMarketsTab.swift
// Description      : The market explorer over the server's markets hub: search,
//                    filters, sort, and for each market its price (and what
//                    kind of price it is), 24 h change, volume, funding and
//                    open interest, with the source, its date and the stale /
//                    outlier flags the server sets. Opening a row shows the
//                    underlying's page. Viewing a market never prepares
//                    anything.
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

struct RsMarketsTab: View {
    let model: AppModel
    @State private var data: RsMarketsModel?
    @State private var selection: HubRow.ID?
    @State private var opened: String?

    var body: some View {
        Group {
            if let symbol = opened { RsInstrumentView(model: model, symbol: symbol) { opened = nil }.id(symbol) }
            else if let data { explorer(data) }
            else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .task {
            if data == nil { let d = RsMarketsModel(model: model); data = d; await d.reload() }
            // the hub's answer is cached a few seconds by the server; a slow refresh keeps prices from silently ageing on screen
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                if AppActivity.isActive, !model.isOffline, opened == nil, let d = data, d.rows.count <= 100 { await d.reload() }
            }
        }
    }

    private func explorer(_ data: RsMarketsModel) -> some View {
        VStack(spacing: 0) {
            RsMarketsFilters(data: data)
            VStack(alignment: .leading, spacing: 6) {
                if let e = data.error { Banner(.danger, e) }
                if !data.sourceErrors.isEmpty { Banner(.warning, "Liste PARTIELLE — sources sans réponse : " + data.sourceErrors.map { "\($0.source) (\($0.message))" }.joined(separator: " ; ")) }
                let bad = data.venues.filter { $0.status != "ok" }
                if !bad.isEmpty { Text("Plateformes dégradées : " + bad.map { "\($0.name) — \($0.status == "stale" ? "périmée" : $0.status == "error" ? "en erreur" : $0.status)\($0.error.map { " (\($0))" } ?? "")" }.joined(separator: " ; ")).font(.caption).foregroundStyle(Theme.warning) }
            }.padding(.horizontal, 24)
            Table(data.rows, selection: $selection) {
                TableColumn("Marché") { r in
                    HStack(spacing: 8) {
                        AssetBadge(symbol: r.base, size: 22)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(r.symbol).fontWeight(.medium).lineLimit(1)
                            Text("\(r.kind == "perp" ? "Perpétuel" : r.kind == "spot" ? "Comptant" : r.kind) · \(r.venueName ?? r.venue)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }.width(min: 170, ideal: 210)
                TableColumn("Prix") { r in
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(RsFmt.price(r.price)).monospacedDigit()
                        Text(RsMarketsText.priceKind(r.priceKind)).font(.caption2).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .trailing)
                }.width(min: 100, ideal: 120)
                TableColumn("24 h") { r in Text(RsFmt.fraction(r.change24h)).monospacedDigit().foregroundStyle(Theme.change(RsFmt.double(r.change24h))).frame(maxWidth: .infinity, alignment: .trailing) }.width(min: 70, ideal: 80)
                TableColumn("Volume 24 h") { r in Text(RsFmt.compactUsd(r.volume24hUsd)).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing) }.width(min: 90, ideal: 100)
                TableColumn("Financement (annualisé)") { r in Text(r.funding.map { RsFmt.fraction($0.annualised) } ?? "—").monospacedDigit().foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing) }.width(min: 90, ideal: 110)
                TableColumn("Intérêt ouvert") { r in Text(RsFmt.compactUsd(r.openInterestUsd)).monospacedDigit().foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing) }.width(min: 90, ideal: 100)
                TableColumn("Source et date") { r in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(r.priceSource ?? r.source).font(.caption).lineLimit(1)
                        Text(r.sourceDate.map { Fmt.dateSeconds($0) } ?? "date non fournie").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    }
                }.width(min: 130, ideal: 150)
                TableColumn("Signalements") { r in RsRowFlags(row: r) }.width(min: 150, ideal: 210)
            }
            .contextMenu(forSelectionType: HubRow.ID.self) { ids in
                if let id = ids.first, let r = data.rows.first(where: { $0.id == id }) { Button("Ouvrir la page de \(r.underlying ?? r.base)") { opened = r.underlying ?? r.base } }
            } primaryAction: { ids in
                if let id = ids.first, let r = data.rows.first(where: { $0.id == id }) { opened = r.underlying ?? r.base }
            }
            .overlay {
                if data.loading && data.rows.isEmpty { ProgressView() }
                else if data.rows.isEmpty { EmptyState(symbol: "chart.bar.xaxis", title: data.loadedAt == nil ? "Marchés non lus" : "Aucun marché ne correspond", detail: data.error) }
            }
            HStack(spacing: 12) {
                Text("\(data.rows.count) sur \(data.total) marchés").font(.callout).foregroundStyle(.secondary)
                if let c = data.counts { Text("\(c.spot) comptant · \(c.perp) perpétuels · \(c.tradable) négociables · \(c.stale) périmés").font(.callout).foregroundStyle(c.stale > 0 ? Theme.warning : .secondary) }
                if data.rows.count < data.total { Button(data.loadingMore ? "Chargement…" : "Charger la suite") { Task { await data.loadMore() } }.disabled(data.loadingMore) }
                Spacer()
                if let id = selection, let r = data.rows.first(where: { $0.id == id }) { Button("Ouvrir \(r.underlying ?? r.base)") { opened = r.underlying ?? r.base } }
                OpsAsOf(date: data.serverDate, prefix: "Réponse du serveur")
            }.padding(.horizontal, 24).padding(.vertical, 8)
            Text("Prix et volumes tels que servis par chaque source, avec leur date. La capitalisation boursière n’est pas publiée par le serveur et n’est donc pas affichée. Double-cliquez une ligne pour ouvrir la page du sous-jacent.")
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.bottom, 8)
        }
    }
}

private struct RsMarketsFilters: View {
    @Bindable var data: RsMarketsModel
    var body: some View {
        HStack(spacing: 10) {
            TextField("Rechercher un actif ou un marché", text: $data.search).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
            Picker("Nature", selection: $data.kind) { Text("Comptant et perpétuels").tag(""); Text("Comptant").tag("spot"); Text("Perpétuels").tag("perp") }.frame(width: 190)
            Picker("Plateforme", selection: $data.venue) { Text("Toutes plateformes").tag(""); ForEach(data.venues) { Text($0.name).tag($0.id) } }.frame(width: 180)
            Picker("Catégorie", selection: $data.category) {
                Text("Toutes catégories").tag("")
                ForEach(data.categories, id: \.self) { Text(RsMarketsText.category($0)).tag($0) }
                if !data.category.isEmpty, !data.categories.contains(data.category) { Text(RsMarketsText.category(data.category)).tag(data.category) }
            }.frame(width: 170)
            Picker("Tri", selection: $data.sort) { ForEach(HubQuery.Sort.allCases, id: \.self) { Text(RsMarketsText.sort($0)).tag($0) } }.frame(width: 170)
            Button { data.descending.toggle() } label: { Image(systemName: data.descending ? "arrow.down" : "arrow.up") }.help(data.descending ? "Décroissant" : "Croissant")
            Toggle("Négociables", isOn: $data.tradableOnly).toggleStyle(.checkbox).help("Seulement les marchés que le portefeuille peut négocier selon le serveur.")
            Spacer()
            if data.loading { ProgressView().controlSize(.small) }
            Button { Task { await data.reload() } } label: { Image(systemName: "arrow.clockwise") }.disabled(data.loading)
        }.labelsHidden().padding(.horizontal, 24).padding(.vertical, 10)
    }
}

/// The flags the server sets on a row: shown as text next to the figure, never only as a colour.
struct RsRowFlags: View {
    let row: HubRow
    var body: some View {
        HStack(spacing: 5) {
            if row.stale { ProvenanceTag(p: .stale, text: "Périmé\(row.ageMs.map { " · \(RsFmt.age(ms: $0))" } ?? "")") }
            if row.priceOutlier == true { RsFlag(text: "Prix divergent", color: Theme.negative, symbol: "exclamationmark.triangle") }
            if row.paper == true { RsFlag(text: "Papier", color: .blue, symbol: "testtube.2") }
            if !row.tradable { RsFlag(text: "Non négociable", color: .secondary, symbol: "lock").help(row.tradableReason ?? "Le serveur ne précise pas la raison.") }
            if let r = row.restriction { RsFlag(text: "Restriction", color: Theme.warning, symbol: "hand.raised").help(r) }
            if row.status != "active" && !row.status.isEmpty { RsFlag(text: row.status, color: .secondary, symbol: "pause.circle") }
        }
    }
}

struct RsFlag: View {
    let text: String; let color: Color; let symbol: String
    var body: some View {
        Label(text, systemImage: symbol).font(.caption).foregroundStyle(color).padding(.horizontal, 6).padding(.vertical, 2).background(color.opacity(0.12), in: Capsule())
    }
}

enum RsMarketsText {
    static func priceKind(_ k: String?) -> String {
        switch k { case "mark": "prix de référence (mark)"; case "close_1h": "clôture de la dernière barre 1 h"; case nil: "nature non précisée"; case let s?: s }
    }
    static func category(_ c: String) -> String {
        switch c { case "crypto": "Crypto"; case "equity": "Actions"; case "pre_ipo": "Pré-introduction"; case "commodity": "Matières premières"; case "fx": "Devises"; default: c }
    }
    static func sort(_ s: HubQuery.Sort) -> String {
        switch s { case .volume: "Volume 24 h"; case .openInterest: "Intérêt ouvert"; case .funding: "Financement"; case .change: "Variation 24 h"; case .symbol: "Symbole" }
    }
}
