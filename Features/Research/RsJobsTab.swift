// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Features/Research/RsJobsTab.swift
// Description      : The automated research jobs: whether the server's research
//                    runner is available (and the server's reason when it is
//                    not), the list of jobs with their real state, creation,
//                    and the selected job's page. Results are AI-generated
//                    analysis and backtests and are labelled so on every block.
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

struct RsJobsTab: View {
    let model: AppModel
    @State private var data: RsJobsModel?
    @State private var creating = false

    var body: some View {
        Group {
            if let data {
                // an HStack, not an HSplitView (see Features/Assets/AssetsView.swift: the AppKit split view breaks the window's layout)
                HStack(spacing: 0) {
                    list(data).frame(width: 380)
                    Divider()
                    Group {
                        if data.selectedId != nil { RsJobDetailView(model: model, data: data) }
                        else { EmptyState(symbol: "sparkles.rectangle.stack", title: "Sélectionnez une recherche", detail: "Chaque recherche montre séparément ce que l’agent IA affirme, ce que le serveur a mesuré lui-même en backtest, et les données observées.") }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .task {
            let d = data ?? RsJobsModel(model: model); data = d
            await d.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(d.hasOpenJobs ? 15 : 60))
                guard !Task.isCancelled else { return }
                if AppActivity.isActive, !model.isOffline { await d.refresh() }
            }
        }
        .sheet(isPresented: $creating) { if let data { RsJobCreateSheet(model: model, jobs: data) { creating = false } } }
    }

    private func list(_ data: RsJobsModel) -> some View {
        @Bindable var data = data
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                RsRunnerStatus(data: data)
                HStack {
                    Button { creating = true } label: { Label("Nouvelle recherche…", systemImage: "plus") }.disabled(!data.canCreate)
                    Spacer()
                    if data.loading { ProgressView().controlSize(.small) }
                    Button { Task { await data.refresh() } } label: { Image(systemName: "arrow.clockwise") }.disabled(data.loading)
                }
                if let e = data.jobsError { Banner(data.jobs.isEmpty ? .danger : .warning, data.jobs.isEmpty ? e : "Liste non rafraîchie (\(e)) — lue \(Fmt.relative(data.jobsAt)).") }
            }.padding(14)
            Divider()
            List(data.jobs, selection: $data.selectedId) { j in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        RsJobStateDot(state: j.state)
                        Text(RsJobText.state(j.state)).font(.callout.weight(.medium)).lineLimit(1)
                        Spacer()
                        Text(Fmt.relative(j.createdAt)).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(verbatim: j.mission).font(.callout).lineLimit(2).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Text("\(j.kind == "perp" ? "Perp." : "Comptant") · \(j.universe.joined(separator: ", ")) · \(j.interval)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        if j.cancelRequested && !j.state.isFinal { Text("annulation demandée").font(.caption).foregroundStyle(Theme.warning) }
                        if j.claimsDiffer == true { Text("affirmations ≠ mesures").font(.caption).foregroundStyle(Theme.warning) }
                    }
                }.padding(.vertical, 3).tag(j.id)
            }
            .overlay { if data.jobs.isEmpty && data.jobsError == nil && !data.loading { EmptyState(symbol: "tray", title: "Aucune recherche", detail: "Les recherches lancées apparaîtront ici avec leur état réel.") } }
        }
    }
}

struct RsJobStateDot: View {
    let state: ResearchState
    var body: some View {
        let color: Color = switch state { case .submitted: Theme.positive; case .failed, .overBudget: Theme.negative; case .cancelled: .secondary; case .queued: Theme.warning; default: .blue }
        Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
    }
}

/// Whether the research runner is available, from the server: its capability, its last contact, the open-job quota.
private struct RsRunnerStatus: View {
    let data: RsJobsModel
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let s = data.status {
                HStack(spacing: 6) {
                    Image(systemName: s.runnerConfigured ? "cpu.fill" : "cpu").foregroundStyle(s.runnerConfigured ? Theme.positive : Theme.warning)
                    Text(s.runnerConfigured ? "Exécuteur de recherche : activé sur le serveur" : "Exécuteur de recherche : désactivé sur le serveur").fontWeight(.medium)
                }
                if !s.runnerConfigured {
                    Text(data.runnerCapability?.why ?? "Aucun secret d’exécuteur n’est configuré sur le serveur : les recherches créées restent en file d’attente.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let m = data.runnerCapability?.missing, !m.isEmpty { Text("Réglage en cause : \(m.joined(separator: ", "))").font(.caption.monospaced()).foregroundStyle(.secondary) }
                } else {
                    Text(s.lastRunnerContact.map { "Dernier contact d’un exécuteur : \(Fmt.relative($0)) (\(Fmt.date($0)))" } ?? "Activé, mais aucun exécuteur ne s’est encore manifesté : les recherches attendront en file.")
                        .font(.caption).foregroundStyle(s.lastRunnerContact == nil ? Theme.warning : .secondary).fixedSize(horizontal: false, vertical: true)
                }
                Text("Recherches ouvertes : \(s.openJobs) / \(s.maxOpenJobs)\(s.labCommit.map { " · laboratoire \($0.prefix(10))" } ?? " · version du laboratoire inconnue")").font(.caption).foregroundStyle(.secondary)
            } else if let e = data.statusError { OpsUnavailable(what: "État du service de recherche", reason: e) }
            else { ProgressView().controlSize(.small) }
        }
    }
}
