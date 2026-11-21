// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Features/TradingAgents/TradingAPIView.swift
// Description      : The trading API tab: keys (reading permissions and
//                    financial permissions kept apart, mandate binding, limits,
//                    last use), their creation / change / rotation through a
//                    review of the verified key intent and the passkey,
//                    revocation without one, the one-time secret sheet,
//                    webhooks with their deliveries, usage and rate limits, and
//                    the link to the server's API reference. The server lock on
//                    live execution is shown with its reason.
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

struct TradingAPIView: View {
    let model: AppModel
    let locks: [ExecutionLock]?
    enum Tab: String, CaseIterable { case keys = "Clés", webhooks = "Webhooks", usage = "Utilisation et état" }
    @State private var store: TradingAPIStore?
    @State private var tab: Tab = .keys
    @State private var editing: KeyEdit?

    struct KeyEdit: Identifiable { let id = UUID(); let key: APIKey? }

    var body: some View {
        Group {
            if let store {
                executionCard(store)
                Picker("Section", selection: $tab) { ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 420)
                if let n = store.notice { Banner(.info, n) }
                if let e = store.actionError, store.pending == nil { Banner(.danger, e) }
                switch tab {
                case .keys: keysCard(store)
                case .webhooks: WebhooksView(model: model, store: store)
                case .usage: APIUsageView(store: store)
                }
            } else { ProgressView() }
        }
        .task { if store == nil { store = TradingAPIStore(model: model) }; await store?.poll() }
        .sheet(item: $editing) { e in if let store, let info = store.keys { APIKeyFormSheet(model: model, store: store, info: info, key: e.key) { editing = nil } } }
        .sheet(isPresented: Binding(get: { store?.pending != nil && editing == nil }, set: { _ in })) { if let store, let p = store.pending { APIKeyApprovalSheet(model: model, store: store, pending: p, info: store.keys) } }
        .sheet(isPresented: Binding(get: { store?.shown != nil && store?.pending == nil && editing == nil }, set: { if !$0 { store?.dismissSecret() } })) { if let store, let s = store.shown { OneTimeSecretSheet(shown: s) { store.dismissSecret() } } }
    }

    @ViewBuilder private func executionCard(_ store: TradingAPIStore) -> some View {
        Card("API de trading programmable") {
            Text("Des programmes à vous peuvent lire le portefeuille et, avec une permission financière ET un mandat lié à la clé, passer des ordres dans les bornes de ce mandat. Une clé ne peut jamais dépasser son mandat ni retirer des fonds.").fixedSize(horizontal: false, vertical: true)
            if let x = store.keys?.execution {
                LockRow(name: "trading_api_execution", open: x.liveEnabled == true, reason: x.note ?? x.code ?? (x.liveEnabled == nil ? "état non publié par le serveur" : nil))
                if !x.wired { Text("L’exécution n’est pas câblée sur ce serveur : les permissions financières ne peuvent rien exécuter.").font(.caption).foregroundStyle(Theme.warning) }
            } else if let l = locks?.first(where: { $0.id == "trading_api_execution" }) { LockRow(name: l.id, open: l.on, reason: l.why) }
            if store.keys?.execution?.liveEnabled == false { Text("Verrou fermé : aucun nouvel ordre RÉEL ne passe par l’API ; le papier, les annulations et les ordres strictement réducteurs passent encore.").font(.caption).foregroundStyle(.secondary) }
            let url = model.configuration.origin.appendingPathComponent("api/v1/trading/docs")
            HStack(spacing: 8) {
                Image(systemName: "book")
                if url.scheme == "https" { Link("Référence de l’API sur le serveur", destination: url) } else { Text("Référence de l’API : \(url.absoluteString)").textSelection(.enabled); Text("(lien non https : non ouvert par l’app)").font(.caption).foregroundStyle(.secondary) }
            }
            Text("La référence exige une session du portefeuille dans le navigateur ou une clé d’API valide.").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func keysCard(_ store: TradingAPIStore) -> some View {
        Card("Clés d’API", trailing: AnyView(HStack {
            if store.busy != nil { ProgressView().controlSize(.small) }
            Button { editing = KeyEdit(key: nil) } label: { Label("Nouvelle clé…", systemImage: "plus") }.disabled(!model.canOperate || store.keys == nil || store.busy != nil)
        })) {
            if let info = store.keys {
                let financial = Set(info.scopes.filter(\.execution).map(\.scope))
                if info.keys.isEmpty { EmptyState(symbol: "key", title: "Aucune clé", detail: "Une clé se crée avec votre passkey ; sa valeur secrète n’est montrée qu’une seule fois.") }
                ForEach(info.keys) { k in keyRow(k, financial, store) ; Divider() }
                Text("Bornes du serveur : \(info.bounds.maxKeys) clés au plus · validité ≤ \(info.bounds.maxDays) jours · cadence ≤ \(info.bounds.maxRatePerMin) requêtes/min\(info.bounds.maxNotionalUsd.map { " · plafonds ≤ \(AgentCreateForm.plain($0)) USD" } ?? "").").font(.caption).foregroundStyle(.secondary)
            } else { Unavailable(what: "Clés", error: store.errors["keys"]) }
        }
    }

    @ViewBuilder private func keyRow(_ k: APIKey, _ financial: Set<String>, _ store: TradingAPIStore) -> some View {
        let read = k.scopes.filter { !financial.contains($0) }, fin = k.scopes.filter { financial.contains($0) }
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(k.name).font(.headline)
                Text(k.id).font(Theme.monoSmall).foregroundStyle(.secondary).textSelection(.enabled)
                Text(k.status == "active" ? "active" : k.status == "revoked" ? "révoquée" : k.status == "expired" ? "expirée" : k.status).font(.caption.weight(.semibold)).foregroundStyle(k.isActive ? Theme.positive : Theme.negative)
                    .padding(.horizontal, 7).padding(.vertical, 2).background((k.isActive ? Theme.positive : Theme.negative).opacity(0.13), in: Capsule())
                Spacer()
                if k.isActive {
                    Button("Modifier…") { editing = KeyEdit(key: k) }
                    Button("Renouveler…") { Task { await store.prepareRotate(k) } }.help("Nouvel identifiant et nouveau secret, mêmes permissions ; l’ancienne clé cesse de fonctionner. Passkey requise.")
                    Button("Révoquer", role: .destructive) { Task { await store.revoke(k) } }.help("Immédiat, sans passkey : révoquer ne fait que retirer une autorité.")
                }
            }.disabled(model.phase != .signedIn || store.busy != nil)
            scopeLine("Lecture", read, .secondary)
            if !fin.isEmpty {
                scopeLine("Financières", fin, Theme.negative)
                if !k.inertScopes.isEmpty { Label("Inertes (aucun mandat lié) : \(k.inertScopes.joined(separator: ", "))", systemImage: "moon.zzz").font(.caption).foregroundStyle(Theme.warning) }
            }
            Text("Mandat lié : \(k.mandateId.map { id in store.mandates(for: k.id).first { $0.id == id }.map { "\(id) — \($0.mode) · \($0.state)/\($0.phase)" } ?? id } ?? "aucun")").font(.callout).textSelection(.enabled)
            Text("Plafonds : par ordre \(k.limits.maxOrderNotionalUsd.value.map { AgentCreateForm.plain($0) + " USD" } ?? "non défini") · par jour \(k.limits.maxDailyNotionalUsd.value.map { AgentCreateForm.plain($0) + " USD" } ?? "non défini") · \(k.rateLimitPerMin) requêtes/min").font(.callout)
            let r = k.restrictions
            if !(r.networks.isEmpty && r.venues.isEmpty && r.instruments.isEmpty && r.ipAllow.isEmpty) {
                Text("Restrictions : " + [r.networks.isEmpty ? nil : "réseaux \(r.networks.joined(separator: ", "))", r.venues.isEmpty ? nil : "plateformes \(r.venues.joined(separator: ", "))", r.instruments.isEmpty ? nil : "marchés \(r.instruments.joined(separator: ", "))", r.ipAllow.isEmpty ? nil : "adresses IP \(r.ipAllow.joined(separator: ", "))"].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }
            Text("Créée \(Fmt.date(AgentText.ms(k.createdAt))) · expire \(Fmt.date(AgentText.ms(k.expiresAt))) · dernière utilisation : \(k.lastUsedAt.map { Fmt.relative(AgentText.ms($0)) + (k.lastUsedIp.map { " depuis \($0)" } ?? "") } ?? "jamais")\(k.rotatedFrom.map { " · renouvelée depuis \($0)" } ?? "")\(k.revokedAt.map { " · révoquée \(Fmt.date(AgentText.ms($0)))\(k.revokedReason.map { " (\($0))" } ?? "")" } ?? "")").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func scopeLine(_ title: String, _ scopes: [String], _ color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(color).frame(width: 80, alignment: .leading)
            Text(scopes.isEmpty ? "—" : scopes.joined(separator: " · ")).font(Theme.monoSmall).foregroundStyle(color == .secondary ? Color.primary : color)
        }
    }
}

// MARK: key form

struct APIKeyFormSheet: View {
    let model: AppModel
    let store: TradingAPIStore
    let info: APIKeyList
    let key: APIKey?
    let close: () -> Void
    @State private var form = APIKeyForm()
    @State private var accepted = 0

    var body: some View {
        let financialOffered = info.scopes.filter(\.execution), readOffered = info.scopes.filter { !$0.execution }
        let financial = !form.scopes.isDisjoint(with: Set(financialOffered.map(\.scope)))
        SheetScaffold(title: key == nil ? "Nouvelle clé d’API" : "Modifier la clé \(key!.id)", width: 700, height: 760) {
            Form {
                TextField("Nom", text: $form.name)
                if key == nil { TextField("Expiration (jours, 1 à \(info.bounds.maxDays))", text: $form.days, prompt: Text("à indiquer")) }
                TextField("Cadence (requêtes par minute, 1 à \(info.bounds.maxRatePerMin))", text: $form.rate, prompt: Text("à indiquer — suggestion du serveur : \(info.bounds.defaultRatePerMin)"))
            }.formStyle(.grouped).scrollDisabled(true)
            scopeGroup("Permissions de LECTURE", "Elles ne peuvent ni déplacer de fonds ni créer d’exposition.", readOffered, .secondary)
            scopeGroup("Permissions FINANCIÈRES (exécution)", "Elles peuvent engager des fonds ou de l’exposition — uniquement sous un mandat lié à la clé, et dans ses bornes. Sans mandat elles sont inertes.", financialOffered, Theme.negative)
            Form {
                SwiftUI.Section(financial ? "Plafonds — obligatoires pour une clé financière" : "Plafonds (facultatifs pour une clé de lecture)") {
                    TextField("Plafond par ordre (USD notionnel)", text: $form.maxOrder)
                    TextField("Plafond quotidien (USD notionnel)", text: $form.maxDaily)
                }
                SwiftUI.Section("Restrictions (listes séparées par des virgules ; vide = aucune restriction de ce type)") {
                    TextField("Réseaux", text: $form.networks); TextField("Plateformes", text: $form.venues); TextField("Marchés", text: $form.instruments); TextField("Adresses IP autorisées", text: $form.ipAllow)
                }
                if let key {
                    SwiftUI.Section("Mandat lié") {
                        let options = store.mandates(for: key.id)
                        Picker("Mandat", selection: $form.mandateId) {
                            Text("Aucun").tag("")
                            ForEach(options) { m in Text("\(m.label ?? m.id) — \(m.mode) · \(m.state)/\(m.phase)").tag(m.id) }
                            if !form.mandateId.isEmpty, !options.contains(where: { $0.id == form.mandateId }) { Text(form.mandateId).tag(form.mandateId) }
                        }
                        Text(options.isEmpty ? "Aucun mandat ne nomme cette clé. Un mandat de trading pour une clé se crée et s’approuve (passkey) depuis l’écran de risque du portefeuille." : "Seuls les mandats qui nomment cette clé peuvent lui être liés.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.formStyle(.grouped).scrollDisabled(true)
            if key == nil { Text("Un mandat nomme l’identifiant d’une clé : il ne peut être lié qu’après la création. D’ici là, les permissions financières de la clé sont inertes.").font(.caption).foregroundStyle(.secondary) }
            else { Text("Un changement qui réduit l’autorité de la clé passe avec la session seule. Tout élargissement (permission, plafond, cadence, restriction retirée, mandat) vous sera présenté et exigera votre passkey.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        } footer: {
            if let e = store.actionError { Banner(.danger, e) }
            HStack {
                if let p = form.problem(info, creating: key == nil) { Text(p).font(.callout).foregroundStyle(.secondary) }
                Spacer()
                if store.busy != nil { ProgressView().controlSize(.small) }
                Button("Annuler") { close() }
                Button(key == nil ? "Préparer et vérifier…" : "Enregistrer…") { Task { if let key { await store.update(key, form: form) } else { await store.prepareCreate(form) } } }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(form.problem(info, creating: key == nil) != nil || !model.canOperate || store.busy != nil)
            }
        }
        .onAppear { if let key { form = APIKeyForm(key: key) }; accepted = store.formAccepted }
        .onChange(of: store.formAccepted) { _, v in if v != accepted { close() } }
    }

    private func scopeGroup(_ title: String, _ note: String, _ scopes: [APIKeyList.ScopeInfo], _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.callout.weight(.semibold)).foregroundStyle(color == .secondary ? Color.primary : color)
            Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if scopes.isEmpty { Text("Aucune offerte par ce serveur.").font(.caption).foregroundStyle(.secondary) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), alignment: .leading)], alignment: .leading, spacing: 4) {
                ForEach(scopes, id: \.scope) { s in
                    Toggle(isOn: Binding(get: { form.scopes.contains(s.scope) }, set: { if $0 { form.scopes.insert(s.scope) } else { form.scopes.remove(s.scope) } })) { Text(s.scope).font(Theme.monoSmall) }.toggleStyle(.checkbox)
                }
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color.opacity(0.3)))
    }
}

// MARK: approval of a key intent

struct APIKeyApprovalSheet: View {
    let model: AppModel
    let store: TradingAPIStore
    let pending: TradingAPIStore.Pending
    let info: APIKeyList?
    @State private var understood = false

    var body: some View {
        let a = pending.approval, i = a.intent
        let financial = Set(info?.scopes.filter(\.execution).map(\.scope) ?? [])
        let grantsFinancial = !(Set(i.key?.scopes ?? []).union(i.changes?.scopes ?? [])).isDisjoint(with: financial)
        let needsAck = grantsFinancial || !(i.widening ?? []).isEmpty || i.action == "rotate"
        SheetScaffold(title: title(i.action), width: 720, height: 760) {
            ReviewLines(lines: lines(i, financial))
            if let w = i.widening, !w.isEmpty { Banner(.warning, "Ce changement ÉLARGIT l’autorité de la clé sur : \(w.joined(separator: ", ")).") }
            if grantsFinancial { Banner(.warning, "Cette clé porte des permissions FINANCIÈRES. Elles n’agissent que sous un mandat lié à la clé et dans ses bornes ; quiconque détient le secret de la clé peut les utiliser.") }
            if info?.scopes.isEmpty != false { Banner(.warning, "La liste des permissions du serveur n’a pas pu être relue : la distinction lecture / financière n’est pas affichée ici.") }
            BindingProof(digest: a.approval.digest, expiry: a.expiry)
            if needsAck { AckToggle(isOn: $understood, text: i.action == "rotate" ? "Je comprends que l’ancienne clé cessera de fonctionner et que le nouveau secret ne sera montré qu’une fois." : "Je comprends l’autorité accordée à cette clé et que son secret doit rester confidentiel.") }
        } footer: {
            if let e = store.actionError { Banner(.danger, e) }
            HStack {
                Button("Annuler — rien n’est approuvé") { store.cancelPending() }.disabled(store.approving)
                Spacer()
                if store.approving { ProgressView().controlSize(.small); Text("Passkey…").foregroundStyle(.secondary) }
                Button { Task { await store.approve() } } label: { Label("Approuver avec la passkey", systemImage: "touchid") }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled((needsAck && !understood) || store.approving || !model.canOperate)
            }
        }
        .interactiveDismissDisabled()
    }

    private func title(_ action: String) -> String {
        switch action { case "create": "Approuver la création de la clé"; case "rotate": "Approuver le renouvellement de la clé"; case "update": "Approuver l’élargissement de la clé"; default: "Approuver l’opération sur la clé" }
    }

    private func split(_ scopes: [String], _ financial: Set<String>) -> String {
        let r = scopes.filter { !financial.contains($0) }, f = scopes.filter { financial.contains($0) }
        return "Lecture : \(r.isEmpty ? "aucune" : r.joined(separator: ", "))\nFINANCIÈRES : \(f.isEmpty ? "aucune" : f.joined(separator: ", "))"
    }
    private func limits(_ l: APIKeyLimits) -> String { "par ordre \(l.maxOrderNotionalUsd.value.map { AgentCreateForm.plain($0) + " USD" } ?? "NON DÉFINI") · par jour \(l.maxDailyNotionalUsd.value.map { AgentCreateForm.plain($0) + " USD" } ?? "NON DÉFINI")" }
    private func restrictions(_ r: APIKeyRestrictions) -> String {
        "réseaux : \(r.networks.isEmpty ? "tous" : r.networks.joined(separator: ", "))\nplateformes : \(r.venues.isEmpty ? "toutes" : r.venues.joined(separator: ", "))\nmarchés : \(r.instruments.isEmpty ? "tous" : r.instruments.joined(separator: ", "))\nadresses IP : \(r.ipAllow.isEmpty ? "toutes" : r.ipAllow.joined(separator: ", "))"
    }

    private func lines(_ i: APIKeyIntent, _ financial: Set<String>) -> [ReviewLine] {
        var out: [ReviewLine] = [
            ReviewLine(label: "Opération", value: i.action == "create" ? "Création d’une clé d’API" : i.action == "rotate" ? "Renouvellement d’une clé d’API" : i.action == "update" ? "Modification d’une clé d’API" : i.action, style: .strong),
            ReviewLine(label: "Portefeuille (origine)", value: i.origin),
            ReviewLine(label: "Préparée le", value: i.preparedAt),
            ReviewLine(label: "Identifiant de l’intention", value: i.intentId, style: .address),
        ]
        if let id = i.keyId { out.append(ReviewLine(label: "Clé visée", value: id, style: .address)) }
        if let n = i.newKeyId { out.append(ReviewLine(label: "Nouvel identifiant", value: n, style: .address)) }
        if let k = i.key {
            out += [ReviewLine(label: "Identifiant de la clé", value: k.id, style: .address), ReviewLine(label: "Nom", value: k.name, style: .strong),
                    ReviewLine(label: "Permissions", value: split(k.scopes, financial), style: .strong), ReviewLine(label: "Expire le", value: k.expiresAt, style: .strong),
                    ReviewLine(label: "Plafonds (notionnel)", value: limits(k.limits)), ReviewLine(label: "Restrictions", value: restrictions(k.restrictions)),
                    ReviewLine(label: "Cadence", value: "\(k.rateLimitPerMin) requêtes par minute"), ReviewLine(label: "Mandat lié", value: k.mandateId.value ?? "aucun (permissions financières inertes)")]
        }
        if let c = i.changes {
            if let n = c.name { out.append(ReviewLine(label: "Nouveau nom", value: n)) }
            if let s = c.scopes { out.append(ReviewLine(label: "Nouvelles permissions", value: split(s, financial), style: .strong)) }
            if let e = c.expiresAt { out.append(ReviewLine(label: "Nouvelle expiration", value: e, style: .strong)) }
            if let l = c.limits { out.append(ReviewLine(label: "Nouveaux plafonds", value: limits(l), style: .strong)) }
            if let r = c.restrictions { out.append(ReviewLine(label: "Nouvelles restrictions", value: restrictions(r))) }
            if let r = c.rateLimitPerMin { out.append(ReviewLine(label: "Nouvelle cadence", value: "\(r) requêtes par minute")) }
            switch c.mandate { case .unchanged: break; case .unbind: out.append(ReviewLine(label: "Mandat", value: "délié")); case .bind(let id): out.append(ReviewLine(label: "Mandat à lier", value: id, style: .address)) }
        }
        return out
    }
}

// MARK: the secret, once

/// Shows a secret exactly once. The value exists only in this sheet's lifetime: closing it drops it from the app's memory.
struct OneTimeSecretSheet: View {
    let shown: TradingAPIStore.Shown
    let close: () -> Void
    @State private var saved = false
    @State private var copied = false

    var body: some View {
        SheetScaffold(title: shown.title, width: 680, height: 520) {
            ForEach(shown.problems, id: \.self) { Banner(.danger, $0) }
            Banner(.danger, "Ce secret n’est affiché QU’UNE SEULE FOIS. L’app ne le conserve pas et le serveur ne peut pas le redonner : copiez-le maintenant dans votre gestionnaire de secrets. Quiconque le détient agit avec l’autorité de la clé.")
            Field(label: "Objet", value: shown.subject)
            Text(shown.secret.reveal()).font(.system(.body, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                .privacySensitive()
            HStack {
                Button { copyToPasteboard(shown.secret.reveal()); copied = true } label: { Label(copied ? "Copié" : "Copier le secret", systemImage: copied ? "checkmark" : "doc.on.doc") }.buttonStyle(.borderedProminent)
                if copied { Text("Le presse-papiers contient maintenant le secret : collez-le en lieu sûr, puis copiez autre chose.").font(.caption).foregroundStyle(Theme.warning) }
            }
            ForEach(shown.notes, id: \.self) { Text($0).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) }
            AckToggle(isOn: $saved, text: "J’ai enregistré ce secret en lieu sûr. Je comprends qu’il ne sera plus jamais affiché.")
        } footer: {
            HStack { Spacer(); Button("Fermer et oublier le secret") { close() }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!saved) }
        }
        .interactiveDismissDisabled()
    }
}
