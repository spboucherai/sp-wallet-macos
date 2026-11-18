// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/TradingAgents/TradingAPIStore.swift
// Description: State and operations of the programmable trading API as the owner manages it: keys, webhooks, usage, status. Creating, rotating or widening a key goes through the Core's verified key intent and the passkey; revoking and narrowing need the session only. A secret (key token or webhook signing secret) lives in memory only while its one-time sheet is open: it is never written to disk, defaults, logs or snapshots, and is dropped when the sheet closes.
import Foundation
import SPWalletCore

/// The form of a key (creation and edition). Nothing here is defaulted to "unlimited".
struct APIKeyForm: Equatable {
    var name = ""
    var scopes: Set<String> = []
    var days = ""
    var maxOrder = ""
    var maxDaily = ""
    var networks = ""
    var venues = ""
    var instruments = ""
    var ipAllow = ""
    var rate = ""
    var mandateId = ""

    init() {}
    init(key k: APIKey) {
        name = k.name; scopes = Set(k.scopes)
        maxOrder = k.limits.maxOrderNotionalUsd.value.map(AgentCreateForm.plain) ?? ""; maxDaily = k.limits.maxDailyNotionalUsd.value.map(AgentCreateForm.plain) ?? ""
        networks = k.restrictions.networks.joined(separator: ", "); venues = k.restrictions.venues.joined(separator: ", "); instruments = k.restrictions.instruments.joined(separator: ", ")
        ipAllow = k.restrictions.ipAllow.joined(separator: ", "); rate = String(k.rateLimitPerMin); mandateId = k.mandateId ?? ""
    }

    static func list(_ s: String) -> [String] { s.split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == " " }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
    var limits: APIKeyLimits { APIKeyLimits(maxOrderNotionalUsd: AgentText.decimal(maxOrder), maxDailyNotionalUsd: AgentText.decimal(maxDaily)) }
    var restrictions: APIKeyRestrictions { APIKeyRestrictions(networks: Self.list(networks), venues: Self.list(venues), instruments: Self.list(instruments), ipAllow: Self.list(ipAllow)) }

    /// Why the form cannot be submitted. A key with a financial scope must carry both notional limits: an unbounded financial key is refused here.
    func problem(_ info: APIKeyList, creating: Bool) -> String? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty || n.count > 60 { return "Nom : 1 à 60 caractères." }
        if scopes.isEmpty { return "Choisissez au moins une permission." }
        if !scopes.isSubset(of: Set(info.scopes.map(\.scope))) { return "Une permission choisie n’est pas offerte par ce serveur." }
        if creating {
            guard let d = Int(days.trimmingCharacters(in: .whitespaces)), (1...info.bounds.maxDays).contains(d) else { return "Expiration : entre 1 et \(info.bounds.maxDays) jours (obligatoire, aucune clé sans échéance)." }
            if info.keys.filter(\.isActive).count >= info.bounds.maxKeys { return "Nombre maximal de clés atteint (\(info.bounds.maxKeys))." }
        }
        guard let r = Int(rate.trimmingCharacters(in: .whitespaces)), (1...info.bounds.maxRatePerMin).contains(r) else { return "Cadence : entre 1 et \(info.bounds.maxRatePerMin) requêtes par minute (obligatoire)." }
        let financial = !scopes.isDisjoint(with: Set(info.scopes.filter(\.execution).map(\.scope)))
        for (text, label) in [(maxOrder, "Plafond par ordre"), (maxDaily, "Plafond quotidien")] {
            let empty = text.trimmingCharacters(in: .whitespaces).isEmpty
            if empty { if financial { return "\(label) (USD) : obligatoire pour une clé à permission financière — une clé financière sans plafond est refusée." }; continue }
            guard let v = AgentText.decimal(text), v > 0 else { return "\(label) (USD) : nombre positif." }
            if let max = info.bounds.maxNotionalUsd, v > max { return "\(label) : au plus \(AgentCreateForm.plain(max)) USD." }
        }
        if let o = AgentText.decimal(maxOrder), let d = AgentText.decimal(maxDaily), o > d { return "Le plafond par ordre ne peut pas dépasser le plafond quotidien." }
        return nil
    }

    func createRequest() -> APIKeyCreateRequest {
        APIKeyCreateRequest(name: name.trimmingCharacters(in: .whitespacesAndNewlines), scopes: scopes.sorted(), expiresInDays: Int(days.trimmingCharacters(in: .whitespaces)) ?? 0, limits: limits, restrictions: restrictions,
                            rateLimitPerMin: Int(rate.trimmingCharacters(in: .whitespaces)) ?? 0, mandateId: nil)
    }

    /// Only what differs from the key as the server holds it.
    func changes(from k: APIKey) -> APIKeyChanges {
        var c = APIKeyChanges()
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n != k.name { c.name = n }
        if scopes != Set(k.scopes) { c.scopes = scopes.sorted() }
        if limits != k.limits { c.limits = limits }
        if restrictions != k.restrictions { c.restrictions = restrictions }
        if let r = Int(rate.trimmingCharacters(in: .whitespaces)), r != k.rateLimitPerMin { c.rateLimitPerMin = r }
        if mandateId != (k.mandateId ?? "") { c.mandate = mandateId.isEmpty ? .unbind : .bind(mandateId) }
        return c
    }
}

@MainActor @Observable final class TradingAPIStore {
    enum Pending { case create(APIKeyApproval), rotate(APIKeyApproval, APIKey), update(APIKeyApproval, APIKey)
        var approval: APIKeyApproval { switch self { case .create(let a), .rotate(let a, _), .update(let a, _): a } }
    }
    /// A secret shown once. Dropped by `dismissSecret()`; never stored anywhere else.
    struct Shown { let title: String; let subject: String; let secret: OneTimeSecret; let notes: [String]; let problems: [String] }

    let model: AppModel
    let api: DeveloperAPI
    private(set) var keys: APIKeyList?
    private(set) var status: DeveloperStatus?
    private(set) var usage: APIKeyUsage?
    private(set) var webhooks: WebhookList?
    private(set) var mandates: [TradingMandateRecord]?
    private(set) var errors: [String: String] = [:]
    private(set) var busy: String?
    var actionError: String?
    var notice: String?
    private(set) var pending: Pending?
    private(set) var approving = false
    private(set) var shown: Shown?
    /// Set when a creation form was accepted by the server's preparation, so the form sheet can close.
    private(set) var formAccepted = 0

    init(model: AppModel) { self.model = model; api = DeveloperAPI(model.client) }

    private func note<T: Sendable>(_ key: String, _ r: Result<T, Error>) -> T? {
        switch r { case .success(let v): errors[key] = nil; return v; case .failure(let e): errors[key] = model.describe(e); return nil }
    }

    func refresh() async {
        guard model.phase == .signedIn else { return }
        let api = api, mandatesAPI = MandatesAPI(model.client)
        async let k = Result.catching { try await api.keys() }
        async let s = Result.catching { try await api.status() }
        async let u = Result.catching { try await api.usage(limit: 200) }
        async let w = Result.catching { try await api.webhooks() }
        async let m = Result.catching { try await mandatesAPI.list() }
        if let v = note("keys", await k) { keys = v }
        if let v = note("status", await s) { status = v }
        if let v = note("usage", await u) { usage = v }
        if let v = note("webhooks", await w) { webhooks = v }
        if let v = note("mandates", await m) { mandates = v }
    }

    func poll() async {
        await refresh()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            if AppActivity.isActive, !model.isOffline, busy == nil, pending == nil, shown == nil { await refresh() }
        }
    }

    /// The mandates that name this key: the only ones it can be bound to.
    func mandates(for keyId: String) -> [TradingMandateRecord] { (mandates ?? []).filter { $0.principal.kind == "api_key" && $0.principal.id == keyId } }

    private func run(_ name: String, sessionOnly: Bool = false, _ body: () async throws -> String?) async {
        guard busy == nil, sessionOnly ? model.phase == .signedIn : model.canOperate else { return }
        busy = name; actionError = nil; notice = nil
        do { notice = try await body() } catch { actionError = model.describe(error) }
        busy = nil
        await refresh()
    }

    // MARK: keys

    func prepareCreate(_ form: APIKeyForm) async {
        let api = api, r = form.createRequest()
        await run("prepare") { self.pending = .create(try await api.prepareCreate(r)); self.formAccepted += 1; return nil }
    }

    func prepareRotate(_ key: APIKey) async {
        let api = api
        await run("prepare") { self.pending = .rotate(try await api.prepareRotate(id: key.id), key); return nil }
    }

    /// Narrowing passes with the session alone. When the server says a change widens the key, the verified passkey intent is prepared instead.
    func update(_ key: APIKey, form: APIKeyForm) async {
        let api = api, changes = form.changes(from: key)
        guard !changes.isEmpty else { notice = "Aucun changement."; formAccepted += 1; return }
        await run("update") {
            do { _ = try await api.narrow(id: key.id, changes: changes); self.formAccepted += 1; return "Clé \(key.id) mise à jour (aucun élargissement : sans passkey)." }
            catch let e as APIError where e.code == "passkey_required" {
                self.pending = .update(try await api.prepareUpdate(id: key.id, changes: changes), key); self.formAccepted += 1
                return nil
            }
        }
    }

    func cancelPending() { pending = nil; actionError = nil }

    func approve() async {
        guard let p = pending, !approving, model.canOperate else { return }
        approving = true; actionError = nil; defer { approving = false }
        do {
            switch p {
            case .create(let a):
                let k = try await api.create(a, with: model.authenticator)
                pending = nil
                shown = Shown(title: "Clé d’API créée", subject: "\(k.key.name) · \(k.key.id)", secret: k.secret, notes: k.key.inertScopes.isEmpty ? [] : ["Permissions financières inertes tant qu’aucun mandat n’est lié à la clé : \(k.key.inertScopes.joined(separator: ", "))."],
                              problems: k.discrepancies.isEmpty ? [] : ["La clé créée DIFFÈRE de l’intention approuvée sur : \(k.discrepancies.joined(separator: ", ")). Elle existe : révoquez-la."])
            case .rotate(let a, let old):
                let k = try await api.rotate(a, with: model.authenticator)
                pending = nil
                shown = Shown(title: "Clé d’API renouvelée", subject: "\(k.key.name) · \(k.key.id)", secret: k.secret,
                              notes: ["L’ancienne clé \(k.revoked ?? old.id) ne fonctionne plus."] + (k.mandate.map { ["Mandat : \(JSONFlat.rows($0).map { "\($0.key) = \($0.value)" }.joined(separator: " · "))"] } ?? []),
                              problems: k.discrepancies.isEmpty ? [] : ["La réponse DIFFÈRE de l’intention approuvée sur : \(k.discrepancies.joined(separator: ", ")). Révoquez la nouvelle clé."])
            case .update(let a, let key):
                _ = try await api.update(a, with: model.authenticator)
                pending = nil; notice = "Clé \(key.id) mise à jour avec votre passkey."
            }
            await refresh()
        } catch PasskeyError.cancelled {
        } catch {
            // a key-management intent is single use; after a failure the real state is read, nothing is signed twice
            pending = nil
            var text = model.describe(error)
            if case .create = p { text += " Si la clé apparaît dans la liste, sa valeur secrète est perdue : révoquez-la et créez-en une autre." }
            if case .rotate = p { text += " Vérifiez la liste : si une nouvelle clé y figure, son secret est perdu — révoquez-la." }
            actionError = text
            await refresh()
        }
    }

    func revoke(_ key: APIKey) async {
        let api = api
        await run("revoke", sessionOnly: true) { let k = try await api.revoke(id: key.id, reason: "révoquée par le propriétaire depuis l’app macOS"); return "Clé \(k.id) : \(k.status)." }
    }

    func dismissSecret() { shown = nil }

    // MARK: webhooks

    func createWebhook(url: String, events: [String], label: String) async -> Bool {
        let api = api
        await run("webhook") {
            let w = try await api.createWebhook(url: url, events: events, label: label)
            self.shown = Shown(title: "Webhook créé", subject: w.webhook.url, secret: w.secret, notes: ["Ce secret signe chaque livraison ; il sert à vérifier qu’elle vient bien de votre portefeuille."], problems: [])
            return nil
        }
        return actionError == nil
    }

    func setWebhook(_ w: Webhook, enabled: Bool) async {
        let api = api, key = APIClient.newIdempotencyKey()
        await run("webhook") { let x = try await api.updateWebhook(id: w.id, enabled: enabled, idempotencyKey: key); return "Webhook \(x.enabled ? "activé" : "désactivé")." }
    }

    func rotateWebhookSecret(_ w: Webhook) async {
        let api = api
        await run("webhook") {
            let x = try await api.rotateWebhookSecret(id: w.id)
            self.shown = Shown(title: "Nouveau secret de signature", subject: x.webhook.url, secret: x.secret, notes: ["L’ancien secret ne vérifie plus rien : mettez à jour votre récepteur."], problems: [])
            return nil
        }
    }

    func deleteWebhook(_ w: Webhook) async {
        let api = api
        await run("webhook", sessionOnly: true) { try await api.deleteWebhook(id: w.id); return "Webhook supprimé." }
    }
}
