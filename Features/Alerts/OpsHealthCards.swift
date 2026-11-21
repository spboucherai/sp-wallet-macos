// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Features/Alerts/OpsHealthCards.swift
// Description      : System health as the server measures it: signer,
//                    connectors, background loops, quote engine, backup, disk,
//                    audit chain, strategy sandbox, versions, and the server's
//                    optional capabilities — each lock that is off is shown as
//                    off with the server's own reason and the names of the
//                    settings that close it. A connector that was not measured
//                    is "non mesuré", never healthy.
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

struct OpsHealthCards: View {
    let data: OpsMonitorModel

    var body: some View {
        OpsSectionCard(title: "Santé du système", section: data.health, asOf: { $0.asOf }, retry: { Task { await data.reloadHealth() } }) { h in
            OpsSignerRow(signer: h.signer, versions: h.versions)
            Divider()
            OpsConnectors(connectors: h.connectors)
            Divider()
            OpsLoops(loops: h.loops)
            Divider()
            OpsInfra(health: h)
        }
        OpsSectionCard(title: "Capacités du serveur et verrous", section: data.health, asOf: { $0.asOf }, retry: { Task { await data.reloadHealth() } }) { h in
            if let caps = h.capabilities {
                Text("Chaque capacité optionnelle du serveur, avec la raison donnée par le serveur lorsqu’elle est fermée et le nom des réglages qui la ferment (jamais leur valeur). Un verrou fermé n’est pas une panne : c’est l’état voulu tant qu’il n’est pas ouvert sur le serveur.").font(.callout).foregroundStyle(.secondary)
                ForEach(caps) { c in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: c.on ? "lock.open.fill" : "lock.fill").foregroundStyle(c.on ? Theme.positive : .secondary).frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack { Text(OpsText.capability(c.id)).fontWeight(.medium); Text(c.id).font(.caption).foregroundStyle(.secondary); Spacer(); Text(c.on ? "Ouvert" : "Fermé").font(.callout.weight(.medium)).foregroundStyle(c.on ? Theme.positive : .secondary) }
                            Text(c.why).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                            if !c.on, !c.missing.isEmpty { Text("Réglages en cause : \(c.missing.joined(separator: ", "))").font(Theme.monoSmall).foregroundStyle(.secondary) }
                        }
                    }.padding(.vertical, 3)
                }
            } else { OpsUnavailable(what: "Liste des capacités", reason: "Ce serveur ne la publie pas dans sa réponse de santé.") }
        }
        OpsSectionCard(title: "Moteur de cotations en direct", section: data.quotes, asOf: { $0.ts }, retry: { Task { await data.reloadQuotes() } }) { q in
            OpsQuoteStats(stats: q, summary: data.health.value?.quotes)
        }
    }
}

private struct OpsOK: View {
    let ok: Bool?
    var body: some View {
        switch ok {
        case true?: Label("OK", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.positive)
        case false?: Label("En panne", systemImage: "xmark.octagon.fill").foregroundStyle(Theme.negative)
        case nil: Label("Non mesuré", systemImage: "questionmark.circle").foregroundStyle(.secondary)
        }
    }
}

private struct OpsSignerRow: View {
    let signer: SignerReachability
    let versions: MonitorHealth.Versions
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "key.horizontal.fill").foregroundStyle(signer.reachable && signer.halted == false ? Theme.positive : Theme.negative).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Signataire isolé").fontWeight(.medium)
                if !signer.reachable { Text("Injoignable : rien ne peut être signé, et son état d’arrêt est inconnu.").foregroundStyle(Theme.negative) }
                else {
                    switch signer.halted {
                    case true?: Text("Joignable — ARRÊT D’URGENCE ACTIF : il refuse de signer.").foregroundStyle(Theme.negative)
                    case false?: Text("Joignable, en service.").foregroundStyle(Theme.positive)
                    case nil: Text("Joignable ; état d’arrêt non renvoyé.").foregroundStyle(Theme.warning)
                    }
                }
                Text("Clé \(versions.signerKeyId ?? "—") · version de politique \(versions.signerPolicyVersion.map(String.init) ?? "—")").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Spacer()
        }
    }
}

private struct OpsConnectors: View {
    let connectors: [MonitorConnector]
    var body: some View {
        let failing = connectors.filter { $0.ok == false }.count, unknown = connectors.filter { $0.ok == nil }.count
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Connecteurs").font(.subheadline.weight(.semibold))
                Text("\(connectors.count - failing - unknown) OK · \(failing) en panne · \(unknown) non mesurés").font(.callout).foregroundStyle(failing > 0 ? Theme.negative : .secondary).monospacedDigit()
            }
            let groups = Dictionary(grouping: connectors, by: \.group)
            ForEach(groups.keys.sorted(), id: \.self) { g in
                DisclosureGroup {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                        ForEach(groups[g] ?? []) { c in
                            GridRow {
                                Text(c.name).lineLimit(1)
                                OpsOK(ok: c.ok).font(.callout)
                                Text(c.lastSuccessAt.map { "dernier succès \(Fmt.relative($0))" } ?? "aucun succès connu").font(.caption).foregroundStyle(.secondary)
                                Text(c.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                            }
                        }
                    }.padding(.leading, 6)
                } label: {
                    let list = groups[g] ?? [], bad = list.filter { $0.ok == false }.count, nm = list.filter { $0.ok == nil }.count
                    HStack {
                        Text(OpsText.connectorGroup(g))
                        Spacer()
                        Text("\(list.count - bad - nm)/\(list.count) OK\(bad > 0 ? " · \(bad) en panne" : "")\(nm > 0 ? " · \(nm) non mesurés" : "")").font(.callout).foregroundStyle(bad > 0 ? Theme.negative : .secondary).monospacedDigit()
                    }
                }
            }
        }
    }
}

private struct OpsLoops: View {
    let loops: [MonitorLoop]
    var body: some View {
        let late = loops.filter(\.late)
        DisclosureGroup {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                GridRow { Text("Boucle"); Text("Cadence"); Text("Dernier succès"); Text("Échecs"); Text("Dernière erreur") }.font(.caption).foregroundStyle(.secondary)
                ForEach(loops) { l in
                    GridRow {
                        HStack(spacing: 4) { if l.late { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning) }; Text(l.name).font(Theme.monoSmall) }
                        Text(l.everyMs.map { "toutes les \(OpsFmt.duration(ms: $0))" } ?? "—").font(.caption)
                        Text(l.lastOkAt.map { Fmt.relative($0) } ?? "jamais").font(.caption).foregroundStyle(l.late ? Theme.warning : .secondary)
                        Text(l.failures.map(String.init) ?? "—").monospacedDigit().foregroundStyle((l.failures ?? 0) > 0 ? Theme.warning : .secondary)
                        Text(l.lastError.map { "\($0)\(l.lastErrorAt.map { " (\(Fmt.relative($0)))" } ?? "")" } ?? "—").font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                    }
                }
            }.padding(.leading, 6)
        } label: {
            HStack {
                Text("Boucles d’arrière-plan").font(.subheadline.weight(.semibold))
                Spacer()
                Text(late.isEmpty ? "\(loops.count) boucles, aucune en retard" : "\(late.count) en retard sur \(loops.count) : \(late.map(\.name).joined(separator: ", "))").font(.callout).foregroundStyle(late.isEmpty ? Color.secondary : Theme.warning)
            }
        }
    }
}

private struct OpsInfra: View {
    let health: MonitorHealth
    var body: some View {
        let h = health
        VStack(alignment: .leading, spacing: 6) {
            Field(label: "Chaîne d’audit", value: h.audit.intact ? "Intacte — \(h.audit.total) événements, vérifiée \(Fmt.relative(h.audit.checkedAt))" : "ROMPUE à l’événement \(h.audit.brokenAt.map(String.init) ?? "?") (sur \(h.audit.total)) — vérifiée \(Fmt.relative(h.audit.checkedAt))", emphasis: !h.audit.intact)
            Field(label: "Sauvegarde", value: !h.backup.visible ? "Inconnu : le serveur ne voit pas le dossier de sauvegarde (ce n’est pas « aucune sauvegarde »)"
                  : h.backup.lastAt.map { "Dernière \(Fmt.relative($0)) (\(Fmt.date($0)))\(h.backup.ageHours.map { " · âge \(OpsFmt.number($0, digits: 1)) h" } ?? "") · \(h.backup.files) fichiers" } ?? "Aucune sauvegarde trouvée dans le dossier (\(h.backup.files) fichiers)")
            Field(label: "Disque du serveur", value: h.disk.map { "\(OpsFmt.number($0.freePct, digits: 1)) % libres — \(OpsFmt.number($0.freeGb, digits: 1)) Go sur \(OpsFmt.number($0.totalGb, digits: 1)) Go (\($0.path))" } ?? "Indisponible : le serveur n’a pas pu lire son disque")
            if let lab = h.lab {
                Field(label: "Bac à sable des stratégies", value: {
                    switch lab.mode {
                    case "sandbox-exec": lab.ok ? "Confiné (sandbox-exec), opérationnel" : "Confinement en échec : signaux et backtests ne tournent pas\(lab.reason.map { " — \($0)" } ?? "")"
                    case "off": "DÉSACTIVÉ (réglage de développement) : le code de stratégie n’est PAS confiné"
                    case "unavailable": "Indisponible : rien ne tourne (les agents attendent)\(lab.reason.map { " — \($0)" } ?? "")"
                    default: "\(lab.mode)\(lab.ok ? "" : " — en échec")\(lab.reason.map { " — \($0)" } ?? "")"
                    }
                }(), emphasis: !lab.ok || lab.mode == "off")
                if lab.calls != nil || lab.refused != nil { Field(label: "Appels au bac à sable", value: "\(lab.calls.map(String.init) ?? "—") appels, \(lab.refused.map(String.init) ?? "—") refusés\(lab.lastFailure.map { " · dernier échec : \($0) (\(Fmt.relative(lab.lastFailureAt)))" } ?? "")") }
            } else { Field(label: "Bac à sable des stratégies", value: "Non renvoyé par ce serveur") }
            if let ab = h.marketData?.apibricks { Field(label: "Source de prix à clé (API Bricks)", value: ab.displayText, mono: true) }
            Field(label: "Version de l’API", value: "\(h.versions.apiVersion)\(h.versions.apiCommit.map { " · commit \($0.prefix(12))" } ?? "") · Node \(h.versions.node) · démarrée \(Fmt.relative(h.versions.startedAt)) (\(Fmt.date(h.versions.startedAt)))")
        }
    }
}

private struct OpsQuoteStats: View {
    let stats: QuoteStreamStats
    let summary: QuoteEngineSummary?
    var body: some View {
        let q = stats
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 14)], alignment: .leading, spacing: 10) {
            OpsMini(label: "Connexions ouvertes", value: "\(q.connections.open) (total \(q.connections.total), refusées \(q.connections.refused))")
            OpsMini(label: "Abonnements", value: "\(q.subscriptions)")
            OpsMini(label: "Messages par seconde", value: OpsFmt.number(q.messagesPerSec, digits: 1))
            OpsMini(label: "Messages envoyés", value: "\(q.messagesSent)")
            OpsMini(label: "Octets envoyés", value: ByteCountFormatter.string(fromByteCount: Int64(q.bytesSent), countStyle: .binary))
            OpsMini(label: "Latence (ms) p50 / p95", value: "\(OpsFmt.number(q.lagMs.p50, digits: 0)) / \(OpsFmt.number(q.lagMs.p95, digits: 0)) · \(q.lagMs.samples) mesures")
            OpsMini(label: "Regroupés (conflation)", value: "\(q.backpressure.conflated)")
            OpsMini(label: "Transactions abandonnées", value: "\(q.backpressure.tradesDropped)")
            OpsMini(label: "Resynchronisations de carnet", value: "\(q.backpressure.bookResyncs)")
            OpsMini(label: "Clients lents fermés", value: "\(q.backpressure.slowConsumersClosed)")
            OpsMini(label: "Reconnexions amont", value: "\(q.upstreamReconnects)")
            OpsMini(label: "Tickets émis / utilisés / refusés", value: "\(q.tickets.issued) / \(q.tickets.used) / \(q.tickets.refused)")
            OpsMini(label: "Clients : trames invalides / limités", value: "\(q.clients.badFrames) / \(q.clients.rateLimited)")
            OpsMini(label: "Protocole", value: "v\(q.protocol)")
        }
        Text("Limites du serveur : \(q.limits.maxConnectionsOwner) connexions pour le propriétaire, \(q.limits.maxConnectionsTotal) au total, \(q.limits.maxSubscriptions) abonnements, \(q.limits.maxMessagesPerSec) messages/s par client.").font(.caption).foregroundStyle(.secondary)
        if let venues = summary?.venues, !venues.isEmpty {
            Divider(); Text("Sources amont").font(.subheadline.weight(.semibold))
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                GridRow { Text("Source"); Text("État"); Text("Âge"); Text("Transport"); Text("Flux"); Text("Reconnexions"); Text("Trous") }.font(.caption).foregroundStyle(.secondary)
                ForEach(venues) { v in
                    GridRow {
                        Text(v.venue); Text(OpsText.venueState(v.status)).font(.callout).foregroundStyle(v.status == .connected ? Theme.positive : v.status == .idle ? Color.secondary : Theme.warning)
                        Text(OpsFmt.duration(ms: v.ageMs)).monospacedDigit(); Text(v.transport).font(.caption)
                        Text("\(v.feeds)").monospacedDigit(); Text("\(v.reconnects)").monospacedDigit(); Text("\(v.gaps)").monospacedDigit().foregroundStyle(v.gaps > 0 ? Theme.warning : .primary)
                    }
                }
            }
        }
        if let m = stats.metered, !m.isNull {
            DisclosureGroup("Sources à quota (tel que servi)") { Text(OpsJSON.pretty(m)).font(Theme.monoSmall).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
        }
        DisclosureGroup("Diagnostic du concentrateur (tel que servi)") { Text(OpsJSON.pretty(stats.hub)).font(Theme.monoSmall).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
    }
}
