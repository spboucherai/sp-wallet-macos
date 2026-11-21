// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Features/TradingAgents/TradingAPIPanels.swift
// Description      : The webhooks of the trading API (list, creation to an
//                    https address only, enabling, signing-secret rotation,
//                    deletion, deliveries with their real state) and the usage
//                    panel (calls per key, rate limits, state of the API and of
//                    its services, server capabilities). A delivery is
//                    "delivered" only when the server says so.
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

struct WebhooksView: View {
    let model: AppModel
    let store: TradingAPIStore
    @State private var url = ""
    @State private var label = ""
    @State private var events: Set<String> = []
    @State private var confirmDelete: Webhook?
    @State private var confirmRotate: Webhook?

    private var urlProblem: String? {
        let t = url.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return "Entrez l’adresse du récepteur." }
        guard let u = URL(string: t), u.scheme == "https", u.host?.isEmpty == false else { return "Adresse https complète requise (les adresses non chiffrées sont refusées)." }
        if events.isEmpty { return "Choisissez au moins un événement." }
        return nil
    }

    var body: some View {
        Card("Webhooks") {
            if let w = store.webhooks {
                if w.webhooks.isEmpty { Text("Aucun webhook.").foregroundStyle(.secondary) }
                ForEach(w.webhooks) { h in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: h.enabled ? "circle.fill" : "circle").font(.caption2).foregroundStyle(h.enabled ? Theme.positive : .secondary)
                            Text(h.label?.isEmpty == false ? h.label! : "Webhook").fontWeight(.medium)
                            Text(h.enabled ? "activé" : "désactivé").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button(h.enabled ? "Désactiver" : "Activer") { Task { await store.setWebhook(h, enabled: !h.enabled) } }
                            Button("Nouveau secret…") { confirmRotate = h }
                            Button("Supprimer", role: .destructive) { confirmDelete = h }
                        }.disabled(!model.canOperate || store.busy != nil)
                        Text(h.url).font(Theme.monoSmall).textSelection(.enabled)
                        Text("Événements : \(h.events.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary)
                        Text("Créé \(Fmt.date(AgentText.ms(h.createdAt))) · dernière livraison réussie : \(h.lastOkAt.map { Fmt.relative(AgentText.ms($0)) } ?? "aucune")\(h.failures.map { $0 > 0 ? " · \($0) échec(s)" : "" } ?? "")\(h.hasSecret == false ? " · SANS secret de signature" : "")").font(.caption).foregroundStyle(.secondary)
                        if let e = h.lastError { Text("Dernière erreur : \(e)").font(.caption).foregroundStyle(Theme.warning).textSelection(.enabled) }
                    }
                    Divider()
                }
                if let s = w.signature { Text("Signature des livraisons : \(s)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                if let r = w.retry { Text("Nouvelles tentatives : \(r.attempts) au plus, après \(r.backoffSec.map { "\(Int($0)) s" }.joined(separator: ", ")).").font(.caption).foregroundStyle(.secondary) }
            } else { Unavailable(what: "Webhooks", error: store.errors["webhooks"]) }
        }
        .confirmationDialog("Supprimer ce webhook ?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible, presenting: confirmDelete) { h in
            Button("Supprimer", role: .destructive) { Task { await store.deleteWebhook(h) } }
            Button("Annuler", role: .cancel) {}
        } message: { h in Text("Plus aucun événement ne sera envoyé à \(h.url).") }
        .confirmationDialog("Générer un nouveau secret de signature ?", isPresented: Binding(get: { confirmRotate != nil }, set: { if !$0 { confirmRotate = nil } }), titleVisibility: .visible, presenting: confirmRotate) { h in
            Button("Générer un nouveau secret") { Task { await store.rotateWebhookSecret(h) } }
            Button("Annuler", role: .cancel) {}
        } message: { _ in Text("L’ancien secret cesse immédiatement de vérifier les livraisons. Le nouveau ne sera affiché qu’une seule fois.") }

        if let w = store.webhooks {
            Card("Nouveau webhook") {
                Form {
                    TextField("Adresse du récepteur (https)", text: $url, prompt: Text("https://exemple.org/webhook"))
                    TextField("Libellé", text: $label)
                }.formStyle(.grouped).scrollDisabled(true)
                Text("Événements").font(.callout.weight(.medium))
                ForEach(w.events, id: \.event) { e in
                    Toggle(isOn: Binding(get: { events.contains(e.event) }, set: { if $0 { events.insert(e.event) } else { events.remove(e.event) } })) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(e.event + (e.emitted ? "" : " — pas encore émis par ce serveur")).font(Theme.monoSmall).foregroundStyle(e.emitted ? Color.primary : Color.secondary)
                            Text(e.description).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }.toggleStyle(.checkbox)
                }
                HStack {
                    if let p = urlProblem, !url.isEmpty || !events.isEmpty { Text(p).font(.callout).foregroundStyle(.secondary) }
                    Spacer()
                    Button("Créer le webhook") { Task { if await store.createWebhook(url: url.trimmingCharacters(in: .whitespaces), events: events.sorted(), label: label.trimmingCharacters(in: .whitespaces)) { url = ""; label = ""; events = [] } } }
                        .buttonStyle(.borderedProminent).disabled(urlProblem != nil || !model.canOperate || store.busy != nil)
                }
                Text("Un webhook n’envoie que des notifications : il ne donne aucune autorité. Son secret de signature sera affiché une seule fois à la création.").font(.caption).foregroundStyle(.secondary)
            }
            Card("Livraisons récentes") {
                if w.deliveries.isEmpty { Text("Aucune livraison.").foregroundStyle(.secondary) }
                else {
                    Table(w.deliveries) {
                        TableColumn("Créée") { x in Text(Fmt.dateSeconds(AgentText.ms(x.createdAt))).monospacedDigit() }.width(150)
                        TableColumn("Événement") { x in Text(x.event).font(Theme.monoSmall) }.width(170)
                        TableColumn("État") { x in Text(x.state == "delivered" ? "livrée" : x.state == "failed" ? "échouée" : x.state == "pending" ? "en attente" : x.state).foregroundStyle(x.state == "delivered" ? Theme.positive : x.state == "failed" ? Theme.negative : Theme.warning) }.width(90)
                        TableColumn("Tentatives") { x in Text(x.attempts.map(String.init) ?? "—") }.width(70)
                        TableColumn("HTTP") { x in Text(x.lastStatus.map(String.init) ?? "—") }.width(50)
                        TableColumn("Détail") { x in Text(x.lastError ?? (x.deliveredAt.map { "livrée \(Fmt.dateSeconds(AgentText.ms($0)))" } ?? (x.nextAttemptAt.map { "prochaine tentative \(Fmt.relative(AgentText.ms($0)))" } ?? ""))).lineLimit(1).help(x.lastError ?? "") }
                    }.frame(height: min(CGFloat(w.deliveries.count) * 28 + 34, 340))
                }
            }
        }
    }
}

struct APIUsageView: View {
    let store: TradingAPIStore

    var body: some View {
        Card("État de l’API") {
            if let s = store.status {
                Field(label: "Version", value: "\(s.api.version) · préfixe \(s.api.prefix)")
                Field(label: "Opérations", value: "\(s.api.implemented) implémentées sur \(s.api.operations)\(s.api.notImplemented.isEmpty ? "" : " — non implémentées : \(s.api.notImplemented.joined(separator: ", "))")")
                if let k = s.keys { Field(label: "Clés", value: "\(k.active) active(s) sur \(k.total)") }
                Field(label: "Limites de cadence", value: "\(s.rateLimits.defaultPerMin) requêtes/min par défaut · \(s.rateLimits.maxPerMin) au plus · \(s.rateLimits.failedAuthPerMinPerAddress) échecs d’authentification/min par adresse")
                Field(label: "En-têtes de cadence", value: s.rateLimits.headers.joined(separator: ", "), mono: true)
                Divider()
                ForEach(s.services) { x in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: x.ok ? "checkmark.circle.fill" : "xmark.octagon.fill").foregroundStyle(x.ok ? Theme.positive : Theme.negative)
                        Text(x.id).font(Theme.monoSmall).frame(width: 170, alignment: .leading)
                        Text(x.detail + (x.lastOkAt.map { " · dernier succès \(Fmt.relative(AgentText.ms($0)))" } ?? "")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let c = s.capabilities, !c.isEmpty {
                    DisclosureGroup("Capacités et verrous du serveur (\(c.count))") { VStack(alignment: .leading, spacing: 6) { ForEach(c) { l in LockRow(name: l.id, open: l.on, reason: l.why) } }.padding(.top, 6) }
                }
                Text("État lu \(Fmt.relative(AgentText.ms(s.ts))).").font(.caption).foregroundStyle(.secondary)
            } else { Unavailable(what: "État", error: store.errors["status"]) }
        }
        Card("Utilisation par clé") {
            if let u = store.usage {
                if u.perKey.isEmpty { Text("Aucun appel enregistré.").foregroundStyle(.secondary) }
                ForEach(u.perKey, id: \.keyId) { k in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(k.keyId).font(Theme.monoSmall).frame(width: 170, alignment: .leading).textSelection(.enabled)
                        Text("\(k.calls24h) appel(s) en 24 h · \(k.errors24h) erreur(s) · \(k.rateLimited24h) refus de cadence · \(k.callsLastMinute) dans la dernière minute\(k.p95Ms.map { " · p95 \($0) ms" } ?? "") · dernier \(k.lastAt.map { Fmt.relative(AgentText.ms($0)) } ?? "—")").font(.callout).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("Sont enregistrés : méthode, modèle de route, statut et latence — jamais un corps, une requête ou un en-tête. Conservation : \(u.retentionDays) jour(s).").font(.caption).foregroundStyle(.secondary)
                if !u.items.isEmpty {
                    Table(u.items) {
                        TableColumn("Date") { x in Text(Fmt.dateSeconds(AgentText.ms(x.ts))).monospacedDigit() }.width(150)
                        TableColumn("Clé") { x in Text(x.keyId).font(.caption) }.width(140)
                        TableColumn("Appel") { x in Text("\(x.method) \(x.route)").font(Theme.monoSmall).lineLimit(1) }
                        TableColumn("Statut") { x in Text(String(x.status)).foregroundStyle(x.status >= 400 ? Theme.negative : .primary) }.width(60)
                        TableColumn("Latence") { x in Text(x.latencyMs.map { "\($0) ms" } ?? "—").monospacedDigit() }.width(80)
                    }.frame(height: min(CGFloat(u.items.count) * 28 + 34, 380))
                }
            } else { Unavailable(what: "Utilisation", error: store.errors["usage"]) }
        }
    }
}
