// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/Futures/FuturesLiveOps.swift
// Description: Every operation on a LIVE venue account (testnet or mainnet): creating the account, authorizing and revoking the trading key, proposing an order or a reduce-only close, leverage changes, collateral deposit and withdrawal, the account's halt and its lifting. Each one that grants authority or moves funds is prepared by the server, verified by the Core against its WebAuthn challenge, shown in a review sheet, and only then approved with the passkey. Stopping (cancel, cancel-all, halt, revoke) needs no passkey. The client never infers an outcome: what is displayed afterwards is the order, action or operation as the server answers it.
import Foundation
import SPWalletCore

@MainActor @Observable final class FutLiveOps {
    /// What is waiting for the owner's review and passkey. Each case carries only objects the Core verified.
    enum Sheet: Identifiable {
        case authorization(LiveAuthorizationPreparation)
        case order(LiveOrderProposal, LiveOrderApproval, close: Bool)
        case leverage(LiveLeverageApproval)
        case deposit(CollateralDepositApproval)
        case withdraw(CollateralWithdrawApproval)
        case risk(LiveRiskApproval)
        var id: String {
            switch self {
            case .authorization(let p): "auth-\(p.authorization.authorizationId)"
            case .order(_, let a, _): "order-\(a.clientId)"
            case .leverage(let l): "lev-\(l.action.id)"
            case .deposit(let d): "dep-\(d.operation.id)"
            case .withdraw(let w): "wd-\(w.operation.id)"
            case .risk(let r): "risk-\(r.intent.nonce)"
            }
        }
    }

    let model: AppModel
    let store: FuturesStore

    var sheet: Sheet?
    /// The owner's own tick under the jurisdiction text of the authorization sheet.
    var acknowledged = false
    private(set) var busy: String?
    private(set) var approving = false
    var error: String?
    var sheetError: String?
    /// The server's last answer to a stop / maintenance action, in words.
    var notice: String?

    /// The last order that went through a proposal: as the server reports it, refreshed until it is final.
    private(set) var trackedOrder: LiveOrder?
    private(set) var trackedOrderVenue: LiveOrderResult.Venue?
    private(set) var leverageResult: LiveLeverageResult?
    private(set) var collateral = FutLoaded<CollateralStatus>()
    private(set) var trackedOperation: CollateralOperation?

    @ObservationIgnored private var orderKey: (key: String, fingerprint: String)?
    @ObservationIgnored private var closeKey: (key: String, fingerprint: String)?
    @ObservationIgnored private var orderTask: Task<Void, Never>?
    @ObservationIgnored private var operationTask: Task<Void, Never>?

    init(model: AppModel, store: FuturesStore) { self.model = model; self.store = store }

    private var live: DerivativesLiveAPI { store.live }
    var isBusy: Bool { busy != nil || approving }
    var busyText: String? { busy }

    private func run(_ what: String, _ body: () async throws -> Void) async {
        guard model.canOperate, !isBusy else { return }
        busy = what; error = nil; notice = nil
        defer { busy = nil }
        do { try await body() }
        catch PasskeyError.cancelled {}
        catch { self.error = model.describe(error) }
    }

    private func account() throws -> LiveAccount {
        guard let a = store.liveAccount else { throw APIError(status: 404, code: "no_account", message: "Aucun compte de plateforme dans ce mode.") }
        return a
    }

    // MARK: account, authorization

    func createAccount(network: String, label: String) async {
        await run("Création du compte…") {
            let d = try await live.createAccount(network: network, label: label)
            await store.loadAccounts(); store.adopt(d)
            notice = "Compte créé en lecture seule : il ne négocie rien tant que vous n’avez pas autorisé la clé de négociation."
        }
    }

    func prepareAuthorization(policy: VenuePolicy, days: Int) async {
        await run("Préparation de l’autorisation…") {
            let p = try await live.prepareAuthorization(for: try account(), policy: policy, days: days, locale: store.locale)
            acknowledged = false; sheetError = nil
            sheet = .authorization(p)
        }
    }

    func revoke(cancelOpenOrders: Bool) async {
        await run("Révocation…") {
            let d = try await live.revokeAuthorization(try account().id, cancelOpenOrders: cancelOpenOrders, locale: store.locale)
            store.adopt(d); await store.loadAccounts()
            var parts = ["Autorisation révoquée : le compte est en lecture seule. Les positions restent ouvertes."]
            if let c = d.cancelled { parts.append(Self.text(c)) }
            if let e = d.cancelError { parts.append("Annulation des ordres en échec : \(e.message) [\(e.code)]") }
            if let w = d.warning { parts.append(w) }
            notice = parts.joined(separator: " ")
        }
    }

    /// After a lost answer of the signer during an authorization: the server adopts or removes what the passkey approved. No passkey.
    func recover() async {
        await run("Récupération…") {
            let d = try await live.recoverAuthorization(try account().id)
            store.adopt(d); await store.loadAccounts()
            notice = d.recovered.map { r in r.isEmpty ? "Rien à récupérer." : r.map { "\($0.what) \($0.id) : \($0.outcome) — \($0.detail)" }.joined(separator: " ; ") } ?? "Récupération terminée ; état du compte relu."
        }
    }

    func reconcile() async {
        await run("Rapprochement avec la plateforme…") {
            let r = try await live.reconcile(try account().id)
            store.adopt(r.account)
            notice = "Rapprochement : \(r.reconciled) ordre(s), \(r.fills) exécution(s), \(r.funding) paiement(s) de financement." + (r.divergence.map { " Divergence : \($0)" } ?? "")
        }
    }

    // MARK: orders

    func propose(_ request: LiveOrderRequest) async {
        await run("Proposition de l’ordre…") {
            let a = try account()
            let fp = "\(a.id)|\(request.instrument)|\(request.side.rawValue)|\(request.type.rawValue)|\(request.size)|\(request.price ?? "")|\(request.reduceOnly)|\(request.tif.rawValue)|\(request.slippageBps.map(String.init) ?? "")"
            if orderKey?.fingerprint != fp { orderKey = (APIClient.newIdempotencyKey(), fp) }
            let p = try await live.proposeOrder(for: a, order: request, idempotencyKey: orderKey!.key)
            present(p, close: false)
        }
    }

    func proposeClose(_ position: DerivPosition, fraction: String, slippageBps: Int) async {
        await run("Proposition de la clôture…") {
            let a = try account()
            let fp = "\(a.id)|\(position.instrument)|\(position.side)|\(position.size)|\(fraction)|\(slippageBps)"
            if closeKey?.fingerprint != fp { closeKey = (APIClient.newIdempotencyKey(), fp) }
            let p = try await live.proposeClose(for: a, position: position, fraction: fraction, slippageBps: slippageBps, idempotencyKey: closeKey!.key)
            present(p, close: true)
        }
    }

    private func present(_ p: LiveOrderProposal, close: Bool) {
        sheetError = nil
        if let approvable = p.approvable { sheet = .order(p, approvable, close: close) }
        else {
            // nothing (left) to approve: the stored order says why — refused by the risk engine, expired, or already handled
            orderKey = nil; closeKey = nil
            follow(p.order, venue: nil)
        }
    }

    func cancel(orderClientId: String) async {
        await run("Annulation…") {
            let r = try await live.cancelOrder(try account().id, clientId: orderClientId)
            notice = r.sent == false ? "Proposition retirée : rien n’avait été envoyé à la plateforme." : "Annulation demandée à la plateforme — état de l’ordre : \(FutOrderStatePill.text(r.order.state.rawValue))." + (r.venue?.error.map { " \($0)" } ?? "")
            if trackedOrder?.clientId == r.order.clientId { trackedOrder = r.order }
            await store.refreshAccount()
        }
    }

    func cancelAll() async {
        await run("Annulation de tous les ordres…") {
            let r = try await live.cancelAll(try account().id)
            notice = Self.text(r)
            await store.refreshAccount()
        }
    }

    static func text(_ c: LiveCancelAll) -> String {
        var s = "Annulation groupée : \(c.requested) demandé(s), \(c.accepted) accepté(s) par la plateforme"
        if !c.failed.isEmpty { s += ", \(c.failed.count) en échec (\(c.failed.map { "\($0.instrument) : \($0.error)" }.joined(separator: " ; ")))" }
        s += c.remaining.map { ". Ordres encore au carnet : \($0.count)." } ?? ". Ordres restants : lecture impossible."
        return s
    }

    private func follow(_ order: LiveOrder, venue: LiveOrderResult.Venue?) {
        trackedOrder = order; trackedOrderVenue = venue
        orderTask?.cancel()
        Task { await store.refreshAccount() }
        guard !order.final else { announce(order); return }
        orderTask = Task { [weak self] in
            for _ in 0..<60 {
                try? await Task.sleep(for: .seconds(3))
                guard let self, !Task.isCancelled, let cur = self.trackedOrder, cur.clientId == order.clientId else { return }
                await self.store.refreshAccount()
                guard let fresh = self.store.currentLiveDetail?.orders.first(where: { $0.clientId == cur.clientId }) else { continue }
                self.trackedOrder = fresh
                if fresh.final { self.announce(fresh); return }
            }
        }
    }

    private func announce(_ o: LiveOrder) {
        Notifier.post(title: "Ordre \(o.instrument) : \(FutOrderStatePill.text(o.state.rawValue))", body: "\(o.side == "buy" ? "Achat" : "Vente") \(o.size)" + (o.reason.map { " — \($0)" } ?? ""), id: "deriv-\(o.clientId)")
    }

    func clearTrackedOrder() { orderTask?.cancel(); trackedOrder = nil; trackedOrderVenue = nil }

    // MARK: leverage, halt, risk

    func proposeLeverage(instrument: String, leverage: Int, marginMode: DerivMarginMode) async {
        await run("Préparation du changement de levier…") {
            let l = try await live.proposeLeverage(for: try account(), instrument: instrument, leverage: leverage, marginMode: marginMode)
            sheetError = nil; leverageResult = nil
            sheet = .leverage(l)
        }
    }

    func halt(reason: String) async {
        await run("Arrêt des nouveaux ordres…") {
            let d = try await live.halt(try account().id, reason: reason)
            store.adopt(d); await store.loadAccounts()
            notice = "Arrêt engagé sur ce compte." + (d.note.map { " \($0)" } ?? "")
        }
    }

    func prepareResume() async { await prepareRisk("Préparation de la levée de l’arrêt…") { try await self.live.prepareResume(for: $0) } }
    func prepareRebase() async { await prepareRisk("Préparation de l’acceptation des positions…") { try await self.live.prepareRebase(for: $0) } }

    private func prepareRisk(_ what: String, _ call: (LiveAccount) async throws -> LiveRiskPreparation) async {
        await run(what) {
            switch try await call(try account()) {
            case .notNeeded: notice = "Rien à approuver : il n’y a aucun arrêt ou aucune divergence à lever sur ce compte."; await store.refreshAccount()
            case .approval(let r): sheetError = nil; sheet = .risk(r)
            }
        }
    }

    // MARK: collateral

    func loadCollateral() async {
        guard let a = store.liveAccount else { return }
        collateral.loading = true
        do { collateral.set(try await store.collateral.status(a.id)) } catch { collateral.fail(model.describe(error)) }
    }
    func resetCollateral() { collateral = FutLoaded(); trackedOperation = nil; operationTask?.cancel() }

    private func ownAddress() throws -> String {
        guard let a = model.address(on: HyperliquidCollateralPins.network) else { throw APIError(status: 0, code: "no_address", message: "L’adresse Arbitrum de ce portefeuille est inconnue de l’app : impossible de vérifier l’opération.") }
        return a
    }

    func prepareDeposit(amount: String) async {
        await run("Préparation du dépôt…") {
            let d = try await store.collateral.prepareDeposit(for: try account(), amount: amount, ownAddress: try ownAddress())
            sheetError = nil; sheet = .deposit(d)
        }
    }

    func prepareWithdraw(amount: String) async {
        await run("Préparation du retrait…") {
            let w = try await store.collateral.prepareWithdraw(for: try account(), amount: amount, ownAddress: try ownAddress())
            sheetError = nil; sheet = .withdraw(w)
        }
    }

    func cancelOperation(_ id: String) async {
        await run("Annulation de l’opération…") {
            let op = try await store.collateral.cancel(try account().id, operationId: id)
            notice = "Opération \(op.kind == "deposit" ? "de dépôt" : "de retrait") : \(op.state). Rien n’a été signé."
            await loadCollateral()
        }
    }

    private func follow(_ op: CollateralOperation, account: LiveAccountID) {
        trackedOperation = op
        operationTask?.cancel()
        guard !op.final else { return }
        operationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6))
                guard let self, !Task.isCancelled, let cur = self.trackedOperation, cur.id == op.id else { return }
                guard AppActivity.isActive, let fresh = try? await self.store.collateral.operation(account, operationId: cur.id) else { continue }
                self.trackedOperation = fresh
                if fresh.final {
                    Notifier.post(title: fresh.isDone ? (fresh.kind == "deposit" ? "Dépôt crédité par la plateforme" : "Retrait reçu par le portefeuille") : "Opération de collatéral : \(fresh.state)",
                                  body: "\(fresh.amount) \(fresh.asset)" + (fresh.error.map { " — \($0)" } ?? ""), id: "coll-\(fresh.id)")
                    await self.loadCollateral(); await self.model.refreshAll(); await self.store.refreshAccount()
                    return
                }
            }
        }
    }

    // MARK: the passkey step

    /// Approves what the open sheet shows — and nothing else: each branch hands the Core the verified object the sheet rendered.
    func approve() async {
        guard let sheet, model.canOperate, !approving else { return }
        approving = true; sheetError = nil
        defer { approving = false }
        do {
            switch sheet {
            case .authorization(let p):
                let d = try await live.approveAuthorization(p, acknowledged: acknowledged, with: model.authenticator)
                store.adopt(d); await store.loadAccounts()
                notice = "Autorisation enregistrée par le signataire. Mode du compte : \(d.account.mode.rawValue)."
                self.sheet = nil
            case .order(_, let a, _):
                let r = try await live.approveOrder(a, with: model.authenticator)
                orderKey = nil; closeKey = nil
                self.sheet = nil
                follow(r.order, venue: r.venue)
            case .leverage(let l):
                let r = try await live.approveLeverage(l, with: model.authenticator)
                leverageResult = r
                notice = r.venue?.confirmed == true
                    ? "Levier confirmé par la plateforme : \(r.venue?.leverage.map { "\($0.leverage)× (\($0.marginMode))" } ?? "valeur non relue")."
                    : "Changement de levier envoyé — état : \(r.action.state). La plateforme ne confirme pas encore le nouveau réglage" + (r.action.error.map { " : \($0)" } ?? ".")
                self.sheet = nil
                await store.refreshAccount()
            case .deposit(let d):
                let op = try await store.collateral.approveDeposit(d, with: model.authenticator)
                self.sheet = nil
                follow(op, account: d.accountId); await loadCollateral()
            case .withdraw(let w):
                let op = try await store.collateral.approveWithdraw(w, with: model.authenticator)
                self.sheet = nil
                follow(op, account: w.accountId); await loadCollateral()
            case .risk(let r):
                let d = try await live.approveRiskChange(r, with: model.authenticator)
                store.adopt(d); await store.loadAccounts()
                notice = "Changement appliqué par le serveur. " + (d.account.halted.map { "Le compte reste arrêté : \($0)" } ?? "Aucun arrêt actif sur ce compte.")
                self.sheet = nil
            }
        } catch PasskeyError.cancelled {
            // the owner dismissed the passkey prompt: the sheet stays, nothing was signed
        } catch {
            sheetError = model.describe(error)
            await afterFailedApproval(sheet)
        }
    }

    /// The answer of an approval may be lost after the server acted on it: read the real state instead of asking for a second signature.
    private func afterFailedApproval(_ s: Sheet) async {
        switch s {
        case .order(_, let a, _):
            guard let d = try? await live.account(a.accountId), let o = d.orders.first(where: { $0.clientId == a.clientId }) else { return }
            store.adopt(d)
            if o.state != .riskChecked && o.state.rawValue != "proposed" { orderKey = nil; closeKey = nil; sheet = nil; error = sheetError; follow(o, venue: nil) }
        case .deposit(let d):
            if let op = try? await store.collateral.operation(d.accountId, operationId: d.operation.id), op.state != d.operation.state { sheet = nil; error = sheetError; follow(op, account: d.accountId) }
        case .withdraw(let w):
            if let op = try? await store.collateral.operation(w.accountId, operationId: w.operation.id), op.state != w.operation.state { sheet = nil; error = sheetError; follow(op, account: w.accountId) }
        case .authorization, .leverage, .risk:
            await store.refreshAccount()
        }
    }

    /// Closing a sheet without approving: a stored proposal or operation is withdrawn on the server so that nothing stays pending.
    func dismiss() async {
        guard let s = sheet, !approving else { return }
        sheet = nil; sheetError = nil
        switch s {
        case .order(_, let a, _):
            orderKey = nil; closeKey = nil
            if let r = try? await live.cancelOrder(a.accountId, clientId: a.clientId) { notice = r.sent == false ? "Proposition retirée : rien n’a été signé ni envoyé." : nil }
            await store.refreshAccount()
        case .deposit(let d): _ = try? await store.collateral.cancel(d.accountId, operationId: d.operation.id); await loadCollateral()
        case .withdraw(let w): _ = try? await store.collateral.cancel(w.accountId, operationId: w.operation.id); await loadCollateral()
        case .authorization, .leverage, .risk: break
        }
    }
}
