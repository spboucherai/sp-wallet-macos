// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Features/Alerts/AlertsSettingsTab.swift
// Description      : The alert settings screen: per-type switches grouped as
//                    the catalogue groups them, quiet hours, hourly cap,
//                    thresholds, the webhook (URL, details, secret rotation
//                    shown once, signed test call) and the browsers subscribed
//                    to Web Push (listed, testable, removable — a native app
//                    cannot create one, and the screen says why).
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

struct AlertsSettingsTab: View {
    let model: AppModel
    @State private var flow: AlertsSettingsFlow?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let flow {
                    if let e = flow.error { Banner(.danger, e) }
                    if let n = flow.notice { Banner(.ok, n) }
                    if let v = flow.view {
                        AlertsChannelsCard(model: model, flow: flow, view: v)
                        AlertsRulesCard(model: model, flow: flow, view: v)
                        AlertsThresholdsCard(model: model, flow: flow)
                        AlertsWebhookCard(model: model, flow: flow, view: v)
                    } else if flow.loading { ProgressView().frame(maxWidth: .infinity).padding(40) }
                    else { Card { OpsUnavailable(what: "Réglages des alertes", reason: flow.error ?? "Le serveur n’a pas répondu.") { Task { await flow.load() } } } }
                    AlertsPushCard(model: model, flow: flow)
                } else { ProgressView() }
            }.padding(24).frame(maxWidth: 1180, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { if flow == nil { let f = AlertsSettingsFlow(model: model); flow = f; await f.load() } }
        .sheet(isPresented: Binding(get: { flow?.freshSecret != nil }, set: { if !$0 { flow?.forgetSecret() } })) {
            if let flow, let secret = flow.freshSecret { AlertsSecretSheet(secret: secret) { flow.forgetSecret() } }
        }
    }
}

private struct AlertsChannelsCard: View {
    let model: AppModel
    @Bindable var flow: AlertsSettingsFlow
    let view: AlertSettingsView

    var body: some View {
        Card("Diffusion par le serveur", trailing: AnyView(OpsAsOf(date: flow.loadedAt))) {
            Text("Ces réglages sont ceux du serveur : ils gouvernent ses notifications push web et son webhook. Les notifications macOS de cette app se règlent dans l’onglet Alertes ; une alerte existe toujours dans l’app, quels que soient ces réglages.").font(.callout).foregroundStyle(.secondary)
            Toggle("Montants, prix et motifs dans les notifications push (écran verrouillé)", isOn: Binding(get: { view.settings.showDetails }, set: { v in Task { await flow.setShowDetails(v) } }))
            HStack {
                Text("Plafond par heure (critiques exceptées)").frame(width: 290, alignment: .leading)
                TextField("20", text: $flow.capPerHour).frame(width: 70).textFieldStyle(.roundedBorder)
                Button("Enregistrer") { Task { await flow.saveCap() } }.disabled(flow.capProblem != nil || flow.capPerHour == String(view.settings.capPerHour))
                if let p = flow.capProblem { Text(p).font(.caption).foregroundStyle(Theme.negative) }
            }
            Divider()
            Toggle("Heures calmes (les critiques passent toujours)", isOn: Binding(get: { view.settings.quiet.enabled }, set: { v in Task { await flow.setQuietEnabled(v) } }))
            HStack {
                Text("De").foregroundStyle(.secondary); TextField("22:00", text: $flow.quietStart).frame(width: 64).textFieldStyle(.roundedBorder)
                Text("à").foregroundStyle(.secondary); TextField("07:00", text: $flow.quietEnd).frame(width: 64).textFieldStyle(.roundedBorder)
                Text("fuseau").foregroundStyle(.secondary); TextField("America/Toronto", text: $flow.quietTz).frame(width: 190).textFieldStyle(.roundedBorder)
                Button("Enregistrer") { Task { await flow.saveQuiet() } }
                    .disabled(flow.quietProblem != nil || (flow.quietStart == view.settings.quiet.start && flow.quietEnd == view.settings.quiet.end && flow.quietTz == view.settings.quiet.tz))
                if let p = flow.quietProblem { Text(p).font(.caption).foregroundStyle(Theme.negative) }
            }
            Text("Le début de la journée des écarts de résultat (onglet Supervision) suit ce fuseau.").font(.caption).foregroundStyle(.secondary)
        }.disabled(!model.canOperate || flow.saving)
    }
}

private struct AlertsRulesCard: View {
    let model: AppModel
    let flow: AlertsSettingsFlow
    let view: AlertSettingsView
    @State private var expanded: Set<String> = []

    var body: some View {
        Card("Types d’alertes", trailing: AnyView(Text("\(view.kinds.count) types sur le serveur").font(.caption).foregroundStyle(.secondary))) {
            Text("Un type désactivé n’est plus notifié par le serveur (push web, webhook). Les types marqués « fixe » ne peuvent pas être coupés.").font(.callout).foregroundStyle(.secondary)
            let groups = AlertGroup.allCases + Array(Set(view.kinds.map(\.group))).filter { !AlertGroup.allCases.contains($0) }.sorted { $0.rawValue < $1.rawValue }
            ForEach(groups, id: \.self) { g in
                let kinds = view.kinds.filter { $0.group == g }
                if !kinds.isEmpty {
                    let on = kinds.filter { !$0.fixed && view.settings.isOn($0.kind) == true }.count, switchable = kinds.filter { !$0.fixed }.count
                    DisclosureGroup(isExpanded: Binding(get: { expanded.contains(g.rawValue) }, set: { if $0 { expanded.insert(g.rawValue) } else { expanded.remove(g.rawValue) } })) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Button("Tout activer") { Task { await flow.setGroup(g, on: true) } }.disabled(on == switchable)
                                Button("Tout désactiver") { Task { await flow.setGroup(g, on: false) } }.disabled(on == 0)
                            }.controlSize(.small).padding(.vertical, 2)
                            ForEach(kinds, id: \.kind) { k in AlertsRuleRow(flow: flow, info: k, isOn: view.settings.isOn(k.kind)) }
                        }.padding(.leading, 6)
                    } label: {
                        HStack { Text(AlertsText.group(g)).fontWeight(.medium); Spacer(); Text("\(on) / \(switchable) activés").font(.callout).foregroundStyle(.secondary).monospacedDigit() }
                    }
                }
            }
        }.disabled(!model.canOperate || flow.saving)
    }
}

private struct AlertsRuleRow: View {
    let flow: AlertsSettingsFlow
    let info: AlertKindInfo
    let isOn: Bool?

    var body: some View {
        let def = AlertCatalog.definition(info.kind)
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: AlertsText.symbol(info.severity)).foregroundStyle(AlertsText.color(info.severity)).font(.caption).help("Gravité par défaut : \(AlertsText.severity(info.severity))")
            VStack(alignment: .leading, spacing: 0) {
                Text(def?.title.first ?? info.kind.rawValue)
                Text(info.kind.rawValue + (def == nil ? " · type inconnu de cette version de l’app" : "")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if info.fixed { Text("Fixe — toujours actif").font(.caption).foregroundStyle(.secondary) }
            else if let isOn { Toggle("", isOn: Binding(get: { isOn }, set: { v in Task { await flow.setRule(info.kind, on: v) } })).labelsHidden().toggleStyle(.switch).controlSize(.small) }
            else { Text("État non renvoyé").font(.caption).foregroundStyle(Theme.warning) }
        }.padding(.vertical, 2)
    }
}

private struct AlertsThresholdsCard: View {
    let model: AppModel
    @Bindable var flow: AlertsSettingsFlow

    var body: some View {
        Card("Seuils de déclenchement") {
            ForEach(AlertsSettingsFlow.thresholdSpecs) { spec in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 0) { Text(spec.label); Text(spec.help).font(.caption).foregroundStyle(.secondary) }.frame(width: 470, alignment: .leading)
                    TextField("", text: Binding(get: { flow.thresholds[spec.key] ?? "" }, set: { flow.thresholds[spec.key] = $0 })).frame(width: 90).textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                    Text(spec.unit).foregroundStyle(.secondary).frame(width: 56, alignment: .leading)
                    if let p = flow.thresholdProblem(spec) { Text(p).font(.caption).foregroundStyle(Theme.negative) }
                    Spacer()
                }
            }
            HStack { Spacer(); if flow.saving { ProgressView().controlSize(.small) }; Button("Enregistrer les seuils") { Task { await flow.saveThresholds() } }.disabled(!flow.thresholdsValid) }
        }.disabled(!model.canOperate || flow.saving)
    }
}

private struct AlertsWebhookCard: View {
    let model: AppModel
    @Bindable var flow: AlertsSettingsFlow
    let view: AlertSettingsView
    @State private var confirmRotate = false

    var body: some View {
        let w = view.settings.webhook
        Card("Webhook sortant") {
            Text("Le serveur appelle cette adresse à chaque alerte notifiée, en signant le corps avec un secret partagé. Activer le webhook envoie des informations du portefeuille à un service tiers : ne l’activez que vers un service que vous contrôlez.").font(.callout).foregroundStyle(.secondary)
            HStack {
                TextField("https://…", text: $flow.webhookURL).textFieldStyle(.roundedBorder).font(Theme.monoSmall)
                Button("Enregistrer l’adresse") { Task { await flow.saveWebhookURL() } }.disabled(flow.webhookURLProblem != nil || flow.webhookURL.trimmingCharacters(in: .whitespaces) == w.url)
            }
            if let p = flow.webhookURLProblem { Text(p).font(.caption).foregroundStyle(Theme.negative) }
            Field(label: "Secret partagé", value: view.webhook.secretSet ? "Défini sur le serveur (jamais relisible)" : "Aucun — à générer avant d’activer")
            HStack {
                Toggle("Webhook activé", isOn: Binding(get: { w.enabled }, set: { v in Task { await flow.setWebhookEnabled(v) } }))
                    .disabled(!w.enabled && (!view.webhook.secretSet || w.url.isEmpty))
                    .help(!view.webhook.secretSet || w.url.isEmpty ? "Le serveur exige une adresse https enregistrée et un secret généré." : "")
                Spacer()
                Toggle("Inclure montants, prix et motifs", isOn: Binding(get: { w.details }, set: { v in Task { await flow.setWebhookDetails(v) } }))
            }
            if let sample = view.webhookSample {
                DisclosureGroup("Exemple exact d’un appel avec ces réglages") {
                    Text(OpsJSON.pretty(sample)).font(Theme.monoSmall).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(8)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            HStack {
                Button(view.webhook.secretSet ? "Remplacer le secret…" : "Générer le secret…") { confirmRotate = true }.disabled(flow.webhookBusy)
                Button("Envoyer un appel de test") { Task { await flow.testWebhook() } }.disabled(flow.webhookBusy || !view.webhook.secretSet || w.url.isEmpty)
                if flow.webhookBusy { ProgressView().controlSize(.small) }
                Spacer()
            }
            if let t = flow.webhookTest {
                if t.ok { Banner(.ok, "Le destinataire a accepté l’appel de test signé (HTTP \(t.status)). Cela prouve que l’adresse répond, pas que la signature y est vérifiée.") }
                else { Banner(.danger, t.status == 0 ? "Aucune réponse du destinataire\(t.error.map { " : \($0)" } ?? "")." : "Le destinataire a refusé l’appel de test (HTTP \(t.status))\(t.error.map { " : \($0)" } ?? "").") }
            }
        }
        .disabled(!model.canOperate || flow.saving)
        .confirmationDialog(view.webhook.secretSet ? "Remplacer le secret du webhook ?" : "Générer le secret du webhook ?", isPresented: $confirmRotate) {
            Button(view.webhook.secretSet ? "Remplacer le secret" : "Générer le secret", role: view.webhook.secretSet ? .destructive : nil) { Task { await flow.rotateSecret() } }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text(view.webhook.secretSet ? "L’ancien secret cesse d’être valable immédiatement : le destinataire refusera les appels tant qu’il n’aura pas reçu le nouveau. Le nouveau secret n’est affiché qu’une fois."
                 : "Le secret est généré par le serveur et n’est affiché qu’une seule fois. L’app ne le conserve pas.")
        }
    }
}

private struct AlertsSecretSheet: View {
    let secret: String
    let done: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Secret du webhook").font(.title2.weight(.semibold))
            Banner(.warning, "Ce secret n’est affiché que cette fois. Copiez-le dans la configuration du destinataire : ni le serveur ni cette app ne pourront le remontrer. En fermant cette fenêtre, l’app l’oublie.")
            Text(secret).font(Theme.mono).textSelection(.enabled).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            HStack {
                Button(copied ? "Copié" : "Copier") { copyToPasteboard(secret); copied = true }
                Text("Le presse-papiers est lisible par les autres apps : collez puis videz-le.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("J’ai copié le secret — fermer") { done() }.buttonStyle(.borderedProminent)
            }
        }.padding(22).frame(width: 620).interactiveDismissDisabled()
    }
}

private struct AlertsPushCard: View {
    let model: AppModel
    let flow: AlertsSettingsFlow
    @State private var toRemove: PushSubscription?

    var body: some View {
        Card("Appareils abonnés au push web (navigateurs)", trailing: AnyView(Button { Task { await flow.loadSubscriptions() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless))) {
            Banner(.info, "Le serveur ne parle que le Web Push des navigateurs (VAPID) : il n’a pas de route APNs et refuse toute adresse qui n’est pas un service push de navigateur. Cette app Mac ne peut donc pas s’abonner ; elle lit les alertes du serveur et lève elle-même des notifications macOS locales tant qu’elle est ouverte. Les abonnements ci-dessous ont été créés depuis l’app web ; ils sont listés ici en lecture seule et peuvent être retirés.")
            if let err = flow.subscriptionsError, flow.subscriptions == nil { OpsUnavailable(what: "Liste des appareils", reason: err) { Task { await flow.loadSubscriptions() } } }
            else if let subs = flow.subscriptions {
                if subs.isEmpty { Text("Aucun navigateur abonné.").foregroundStyle(.secondary) }
                ForEach(subs) { s in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "globe").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.label.isEmpty ? "Sans nom" : s.label).fontWeight(.medium)
                            Text("\(s.service) · …\(s.endpointTail) · langue \(s.locale)").font(.caption).foregroundStyle(.secondary)
                            Text(s.ua).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Text("Abonné le \(Fmt.date(s.createdAt)) · dernier envoi accepté : \(Fmt.date(s.lastOkAt))\(s.failures > 0 ? " · \(s.failures) échecs" : "")").font(.caption).foregroundStyle(.secondary)
                            if let e = s.lastError { Text("Dernière erreur : \(e)").font(.caption).foregroundStyle(Theme.negative) }
                            if let r = flow.pushTest?.results.first(where: { $0.id == s.id }) {
                                Text(r.ok ? "Test accepté par le service push (HTTP \(r.status)) — l’affichage dépend du navigateur." : "Test refusé (HTTP \(r.status))\(r.error.map { " : \($0)" } ?? "")\(r.removed ? " — abonnement retiré par le serveur" : "")")
                                    .font(.caption).foregroundStyle(r.ok ? Theme.positive : Theme.negative)
                            }
                        }
                        Spacer()
                        Button("Tester") { Task { await flow.testPush(s.id) } }.disabled(flow.pushBusy)
                        Button("Retirer…", role: .destructive) { toRemove = s }.disabled(flow.pushBusy)
                    }.padding(.vertical, 3)
                }
            } else { ProgressView().controlSize(.small) }
        }
        .disabled(!model.canOperate)
        .confirmationDialog("Retirer cet appareil ?", isPresented: Binding(get: { toRemove != nil }, set: { if !$0 { toRemove = nil } }), presenting: toRemove) { s in
            Button("Retirer l’abonnement", role: .destructive) { Task { await flow.removeSubscription(s.id) } }
            Button("Annuler", role: .cancel) {}
        } message: { s in Text("« \(s.label.isEmpty ? s.service : s.label) » ne recevra plus de notification push. Il faudra s’y réabonner depuis l’app web de ce navigateur.") }
    }
}

enum OpsJSON {
    /// Server data kept as served, indented for reading. Never interpreted.
    static func pretty(_ v: JSONValue) -> String {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? e.encode(v)).flatMap { String(data: $0, encoding: .utf8) } ?? v.displayText
    }
}
