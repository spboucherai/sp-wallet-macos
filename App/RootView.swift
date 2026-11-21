// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : App/RootView.swift
// Description      : The main window: gate (sign-in), lock overlay, sidebar and
//                    the current section, plus the status strip that always
//                    says whether the data is live, cached or offline, and
//                    whether the signer can sign.
// Module           : App
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

struct RootView: View {
    let model: AppModel
    @Bindable var nav: Navigator

    var body: some View {
        content
            .overlay { if model.lock.locked && model.phase != .signedOut && model.phase != .launching { LockOverlay(model: model) } }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .launching: ProgressView("Connexion au portefeuille…").controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .signedOut, .setupRequired: GateView(model: model)
        case .signedIn, .offlineBrowse: shell
        }
    }

    private var shell: some View {
        NavigationSplitView {
            List(selection: Binding(get: { nav.section }, set: { if let s = $0 { nav.section = s } })) {
                ForEach(Section.groups, id: \.0) { group in
                    SwiftUI.Section(group.0) {
                        ForEach(group.1) { s in
                            Label(s.title, systemImage: s.symbol).tag(s)
                                .foregroundStyle(model.phase == .offlineBrowse && !s.readOnly ? .tertiary : .primary)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 232, max: 290)
            .safeAreaInset(edge: .top, spacing: 0) { SidebarHeader(model: model) }
            .safeAreaInset(edge: .bottom, spacing: 0) { SidebarFooter(model: model) }
        } detail: {
            // the strip is a top safe-area inset, NOT a VStack sibling of the page: a VStack here is laid out at twice the
            // window's height on macOS 27 and the top of the sidebar and of every page is clipped
            detail
                .safeAreaInset(edge: .top, spacing: 0) { StatusStrip(model: model) }
        }
        // alerts are watched (and notified) from sign-in, not only once the Alerts screen has been opened
        .task(id: model.phase) { if model.phase == .signedIn { AlertsCenter.shared(model).start() } else { AlertsCenter.shared(model).stop() } }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await model.refreshAll() } } label: { Label("Actualiser", systemImage: "arrow.clockwise") }
                    .disabled(model.phase != .signedIn).help("Relire les soldes, l’activité et l’état du signataire")
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if model.phase == .offlineBrowse && !nav.section.readOnly {
            EmptyState(symbol: "wifi.slash", title: "Indisponible hors connexion", detail: "Cette section prépare ou autorise des opérations : elle exige une session active et un portefeuille joignable.")
        } else {
            switch nav.section {
            case .dashboard: DashboardView(model: model, nav: nav)
            case .portfolio: PortfolioView(model: model, nav: nav)
            case .assets: AssetsView(model: model, nav: nav)
            case .send: SendView(model: model, nav: nav)
            case .receive: ReceiveView(model: model)
            case .swap: SwapView(model: model)
            case .bridge: BridgeView(model: model)
            case .nfts: NFTsView(model: model)
            case .defi: DeFiView(model: model, nav: nav)
            case .futures: FuturesView(model: model)
            case .agents: TradingAgentsView(model: model)
            case .alerts: AlertsView(model: model)
            case .activity: ActivityView(model: model)
            case .research: ResearchView(model: model)
            case .security: SecurityView(model: model)
            case .settings: SettingsView(model: model)
            }
        }
    }
}

/// Always visible under the title bar when something limits what the screen shows: offline, cached data, halt, unreachable signer.
/// Kept deliberately plain (fixed line count, no flexible-height text): this view sits in the detail column's top safe-area inset,
/// where a view of unbounded ideal height makes macOS 27 lay the whole split view out at twice the window's height.
struct StatusStrip: View {
    let model: AppModel

    private struct Item: Identifiable { let id: String; let kind: Banner.Kind; let text: String; var action: String?; var run: (@MainActor () async -> Void)? }

    private var items: [Item] {
        var out: [Item] = []
        if model.phase == .offlineBrowse {
            out.append(Item(id: "browse", kind: .warning, text: "Consultation hors connexion — données du \(Fmt.date(model.portfolio?.fetchedAt)). Soldes et prix possiblement périmés. Aucune opération possible.", action: "Se reconnecter", run: { [model] in await model.leaveOfflineBrowse() }))
        } else if model.isOffline {
            out.append(Item(id: "offline", kind: .warning, text: "Portefeuille injoignable — dernières données synchronisées (\(Fmt.relative(model.portfolio?.fetchedAt))). Soldes et prix possiblement périmés ; aucune opération possible.", action: "Réessayer", run: { [model] in await model.refreshAll() }))
        }
        if model.portfolio?.value.halted == true {
            out.append(Item(id: "halt", kind: .danger, text: "ARRÊT D’URGENCE ACTIF — le signataire refuse tout ce qui déplace des fonds ou ajoute du risque. Levée : opérateur sur la machine du signataire."))
        } else if let s = model.portfolio?.value.signer, !s.reachable, !model.isOffline {
            out.append(Item(id: "signer", kind: .warning, text: "Signataire isolé injoignable — soldes lus par l’API aux dernières adresses connues ; rien ne peut être signé pour l’instant."))
        }
        if AppEnvironment.isDevelopment {
            out.append(Item(id: "dev", kind: .info, text: "VARIANTE DE DÉVELOPPEMENT — pile locale jetable (\(model.configuration.originHeader)), clés de test, passkey logicielle. Aucun fonds réel."))
        }
        return out
    }

    var body: some View {
        let list = items
        VStack(spacing: 0) {
            ForEach(list) { item in
                HStack(spacing: 10) {
                    Image(systemName: item.kind.symbol).foregroundStyle(item.kind.color)
                    Text(item.text).font(.callout).lineLimit(2).help(item.text)
                    Spacer(minLength: 8)
                    if let a = item.action, let run = item.run { Button(a) { Task { await run() } }.controlSize(.small) }
                }
                .padding(.horizontal, 16).frame(height: 36).frame(maxWidth: .infinity)
                .background(item.kind.color.opacity(0.13))
            }
        }
        .frame(height: CGFloat(list.count) * 36)
        .background(.bar)
    }
}

/// The wallet's identity at the top of the sidebar (fixed height: see the note on `StatusStrip`).
struct SidebarHeader: View {
    let model: AppModel
    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 0) {
                Text("SP Wallet").font(.system(.headline, design: .rounded).weight(.bold))
                Text(model.accounts?.value.keyId ?? (model.configuration.origin.host ?? "")).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).frame(height: 52)
    }
}

struct SidebarFooter: View {
    let model: AppModel
    var body: some View {
        let (level, text) = SecurityIndicator.assess(model)
        HStack(spacing: 8) {
            Image(systemName: level.symbol).foregroundStyle(level.color)
            VStack(alignment: .leading, spacing: 0) {
                Text(text).font(.caption.weight(.medium)).lineLimit(1)
                Text(model.configuration.origin.host ?? "").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).frame(height: 44)
        .background(level.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .padding(.horizontal, 10).padding(.bottom, 10).frame(height: 54)
        .help("Les clés privées ne quittent jamais la machine du signataire ; ce Mac n’en détient aucune.")
    }
}

struct LockOverlay: View {
    let model: AppModel
    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "lock.fill").font(.system(size: 42)).foregroundStyle(.secondary)
                Text("SP Wallet est verrouillé").font(.title2.weight(.semibold))
                Button("Déverrouiller avec \(AppLock.biometryName)") { Task { await model.lock.unlock() } }.controlSize(.large).keyboardShortcut(.defaultAction)
                if let e = model.lock.lastError { Text(e).foregroundStyle(Theme.negative).font(.callout) }
                Text("Le déverrouillage affiche les écrans ; il n’autorise aucune opération.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .task { await model.lock.unlock() }
    }
}
