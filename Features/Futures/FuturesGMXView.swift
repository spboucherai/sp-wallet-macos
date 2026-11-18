// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/Futures/FuturesGMXView.swift
// Description: GMX v2 on Arbitrum, exactly as the server reports it: its two server settings and every blocker with the server's sentence, the pinned contract set, the wallet's on-chain positions (their liquidation price is the server's ESTIMATE), pending orders and operations. This app does not offer opening GMX positions (the product offers Hyperliquid only); when the server reports GMX as not tradable the reasons are shown and there is no order control. What stays available is what only removes risk or authority: reducing a position (a verified wallet intent, reviewed and approved by passkey), the GMX halt and the revocation of the GMX authorization (no passkey).
import SwiftUI
import SPWalletCore

@MainActor @Observable final class FutGMXFlow {
    enum Sheet: Identifiable {
        case order(GmxOrderPreparation, GmxOrderApproval)
        case risk(GmxRiskApproval)
        var id: String { switch self { case .order(_, let a): "gmx-\(a.operationId)"; case .risk(let r): "gmxrisk-\(r.intent.nonce)" } }
    }
    let model: AppModel
    let store: FuturesStore
    private(set) var status = FutLoaded<GmxStatus>()
    private(set) var jurisdiction = FutLoaded<GmxJurisdictionAnswer>()
    var sheet: Sheet?
    private(set) var busy = false
    private(set) var approving = false
    var error: String?
    var sheetError: String?
    var notice: String?
    private(set) var tracked: GmxOperation?
    @ObservationIgnored private var closeKey: (key: String, fingerprint: String)?
    @ObservationIgnored private var trackTask: Task<Void, Never>?

    init(model: AppModel, store: FuturesStore) { self.model = model; self.store = store }
    private var gmx: DerivativesGMXAPI { store.gmx }

    func load() async {
        status.loading = true
        do { status.set(try await gmx.status(locale: store.locale)) } catch { status.fail(model.describe(error)) }
        if jurisdiction.value == nil { do { jurisdiction.set(try await gmx.jurisdiction()) } catch { jurisdiction.fail(model.describe(error)) } }
    }

    private func run(_ body: () async throws -> Void) async {
        guard model.canOperate, !busy, !approving else { return }
        busy = true; error = nil; notice = nil
        defer { busy = false }
        do { try await body() } catch { self.error = model.describe(error) }
    }

    func halt(reason: String) async {
        await run { let s = try await gmx.halt(reason: reason, locale: store.locale); status.set(s); notice = "Arrêt GMX engagé : aucune nouvelle position. Rien n’est annulé ni clôturé." + (s.risk?.note.map { " \($0)" } ?? "") }
    }
    func revoke() async {
        await run { status.set(try await gmx.revokeAuthorization(locale: store.locale)); notice = "Autorisation GMX révoquée. Les positions restent ouvertes." }
    }
    func prepareResume() async {
        guard let s = status.value else { return }
        await run {
            switch try await gmx.prepareResume(status: s) {
            case .notNeeded: notice = "Aucun arrêt GMX à lever."
            case .approval(let r): sheetError = nil; sheet = .risk(r)
            }
        }
    }

    func prepareClose(_ p: GmxPositionView, fraction: String, slippageBps: Int) async {
        guard let s = status.value, let side = GmxSide(rawValue: p.side) else { return }
        await run {
            guard let own = model.address(on: s.network) else { throw APIError(status: 0, code: "no_address", message: "L’adresse Arbitrum de ce portefeuille est inconnue de l’app : impossible de vérifier l’opération.") }
            let fp = "\(p.key)|\(p.sizeUsd)|\(fraction)|\(slippageBps)"
            if closeKey?.fingerprint != fp { closeKey = (APIClient.newIdempotencyKey(), fp) }
            let prep = try await gmx.prepareClose(GmxCloseRequest(market: p.market, side: side, fraction: fraction, slippageBps: slippageBps), position: p, status: s, ownAddress: own, idempotencyKey: closeKey!.key)
            if let a = prep.approvable { sheetError = nil; sheet = .order(prep, a) }
            else { closeKey = nil; follow(prep.operation); notice = "Cette opération existait déjà et n’attend plus d’approbation : état « \(prep.operation.state) »." }
        }
    }

    func approve() async {
        guard let sheet, model.canOperate, !approving else { return }
        approving = true; sheetError = nil
        defer { approving = false }
        do {
            switch sheet {
            case .order(_, let a):
                let op = try await gmx.approve(a, with: model.authenticator)
                closeKey = nil; self.sheet = nil
                follow(op); await load()
            case .risk(let r):
                status.set(try await gmx.approveRiskChange(r, with: model.authenticator, locale: store.locale))
                self.sheet = nil; notice = "Arrêt GMX levé par le serveur."
            }
        } catch PasskeyError.cancelled {
        } catch {
            sheetError = model.describe(error)
            // a lost answer: read what the server holds for this operation instead of signing again
            if case .order(let p, let a) = sheet, let op = try? await gmx.operation(a.operationId), op.state != p.operation.state { closeKey = nil; self.sheet = nil; self.error = sheetError; follow(op) }
        }
    }

    func dismiss() async {
        guard let s = sheet, !approving else { return }
        sheet = nil; sheetError = nil
        if case .order(_, let a) = s { closeKey = nil; if (try? await gmx.withdraw(a.operationId)) != nil { notice = "Opération retirée : rien n’a été signé." }; await load() }
    }

    private func follow(_ op: GmxOperation) {
        tracked = op
        trackTask?.cancel()
        guard !op.final else { return }
        trackTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6))
                guard let self, !Task.isCancelled, let cur = self.tracked, cur.id == op.id else { return }
                guard AppActivity.isActive, let fresh = try? await self.store.gmx.operation(cur.id) else { continue }
                self.tracked = fresh
                if fresh.final {
                    Notifier.post(title: "Opération GMX : \(fresh.state)", body: (fresh.marketName ?? fresh.kind) + (fresh.error.map { " — \($0)" } ?? ""), id: "gmx-\(fresh.id)")
                    await self.load(); await self.model.refreshAll(); return
                }
            }
        }
    }
}

struct FutGMXView: View {
    let model: AppModel
    let store: FuturesStore
    @State private var flow: FutGMXFlow?

    var body: some View {
        Group { if let flow { FutGMXContent(model: model, store: store, flow: flow) } else { ProgressView() } }
            .task { if flow == nil { flow = FutGMXFlow(model: model, store: store) } }
    }
}

private struct FutGMXContent: View {
    let model: AppModel
    let store: FuturesStore
    @Bindable var flow: FutGMXFlow
    @State private var haltReason = ""
    @State private var confirmHalt = false
    @State private var confirmRevoke = false
    @State private var slippage = "50"

    var body: some View {
        Card("GMX v2 — état rapporté par le serveur", trailing: AnyView(HStack { if flow.status.loading { ProgressView().controlSize(.small) }; Button("Actualiser") { Task { await flow.load() } }; FutModeBadge(mode: .mainnet) })) {
            Text("GMX n’a pas de compte de plateforme : le compte est l’adresse de ce portefeuille sur Arbitrum, et un ordre est une transaction du portefeuille qu’un « keeper » exécute ensuite. Il n’existe ni mode papier ni testnet pour GMX ici.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let e = flow.status.error { Banner(.danger, "État GMX indisponible : \(e)") }
            if let e = flow.error { Banner(.danger, e) }
            if let n = flow.notice { Banner(.info, n) }
        }
        .futPolling(every: 45, id: "gmx") { await flow.load() }
        .sheet(item: Binding(get: { flow.sheet }, set: { if $0 == nil, flow.sheet != nil { Task { await flow.dismiss() } } })) { s in FutGMXSheet(model: model, flow: flow, sheet: s) }

        if let s = flow.status.value {
            Card("Verrous et blocages") {
                FutLockRow(name: "SPW_DERIV_LIVE_MAINNET (dérivés réels)", on: s.settings.liveMainnet, reason: s.settings.liveMainnet ? nil : s.blockerText?["mainnet_setting_off"] ?? store.capability("deriv_live_mainnet")?.why)
                FutLockRow(name: "SPW_DERIV_GMX_LIVE (GMX)", on: s.settings.gmxLive, reason: s.settings.gmxLive ? nil : s.blockerText?["gmx_setting_off"] ?? store.capability("deriv_gmx_live")?.why)
                Divider()
                Label(s.tradable ? "Le serveur indique que des ordres GMX pourraient être préparés." : "Le serveur indique que GMX n’est PAS négociable maintenant.", systemImage: s.tradable ? "checkmark.circle" : "nosign").foregroundStyle(s.tradable ? Theme.positive : Theme.warning)
                ForEach(s.refusals, id: \.code) { r in
                    HStack(alignment: .firstTextBaseline) { Text(r.code).font(Theme.monoSmall).foregroundStyle(Theme.warning); Text(r.reason.isEmpty ? "(sans phrase du serveur)" : r.reason).font(.callout).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) }
                }
                Text("Cette app ne propose pas l’ouverture de positions GMX : le produit n’offre que Hyperliquid pour les nouveaux ordres. Réduire une position existante, arrêter et révoquer restent possibles ci-dessous.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let j = flow.jurisdiction.value {
                Card("Avis de juridiction — GMX") { Text((store.locale == "fr" ? j.fr : j.en).text).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
            } else if let e = flow.jurisdiction.error { Banner(.warning, "Avis de juridiction GMX indisponible : \(e)") }

            Card("Compte, portefeuille et autorisation") {
                if let a = s.account { Field(label: "Adresse (Arbitrum)", value: a.address, mono: true) } else { Field(label: "Adresse", value: "indisponible") }
                if let w = s.wallet { Field(label: "Portefeuille", value: "\(w.usdc) USDC · \(w.eth) ETH · \(w.weth) WETH" + (w.feeCeilingEth.map { " · plafond de frais \($0) ETH" } ?? "")) }
                else { Field(label: "Portefeuille", value: "illisible" + (s.walletError.map { " : \($0)" } ?? "")) }
                if let auth = s.authorization {
                    Field(label: "Autorisation GMX", value: "\(auth.state) · expire \(Fmt.date(auth.expiresAt))" + (auth.today.map { " · aujourd’hui : \($0.increases) hausse(s), \($0.reduces) réduction(s)" } ?? ""))
                    Field(label: "Limites approuvées", value: "levier ≤ \(auth.policy.maxLeverage)× · ordre ≤ \(auth.policy.maxOrderSizeUsd) $ · \(auth.policy.maxOrdersPerDay) ordres/jour · écart ≤ \(auth.policy.maxPriceDeviationBps) pb · \(auth.policy.allowedMarkets.count) marché(s)")
                } else { Field(label: "Autorisation GMX", value: "aucune") }
                if let r = s.risk {
                    Field(label: "Arrêt GMX", value: r.halt ?? "aucun")
                    Field(label: "Limites de perte", value: "quotidienne \(r.maxDailyLoss) $ · totale \(r.maxTotalLoss) $" + (r.realizedToday.map { " · réalisé aujourd’hui \($0) $" } ?? "") + (r.realizedTotal.map { " · total \($0) $" } ?? ""))
                }
                HStack {
                    TextField("Raison de l’arrêt (facultative)", text: $haltReason).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                    Button("Arrêter les nouvelles positions GMX…", role: .destructive) { confirmHalt = true }.disabled(!model.canOperate || flow.busy)
                        .confirmationDialog("Arrêter les nouvelles positions GMX ?", isPresented: $confirmHalt) {
                            Button("Arrêter maintenant", role: .destructive) { Task { await flow.halt(reason: String(haltReason.prefix(200))) } }
                        } message: { Text("Sans passkey. Rien n’est annulé ni clôturé.") }
                    if s.risk?.halt != nil { Button("Lever l’arrêt (passkey)…") { Task { await flow.prepareResume() } }.disabled(!model.canOperate || flow.busy) }
                    Spacer()
                    if s.authorization?.state == "active" {
                        Button("Révoquer l’autorisation GMX…", role: .destructive) { confirmRevoke = true }.disabled(!model.canOperate || flow.busy)
                            .confirmationDialog("Révoquer l’autorisation GMX ?", isPresented: $confirmRevoke) {
                                Button("Révoquer", role: .destructive) { Task { await flow.revoke() } }
                            } message: { Text("Sans passkey. Les positions restent ouvertes ; après révocation, les réduire depuis ce portefeuille n’est plus possible sans nouvelle autorisation.") }
                    }
                }
            }

            Card("Contrats épinglés", trailing: AnyView(Text(s.pins.ok == true ? "vérifiés" : s.pins.ok == false ? "PROBLÈME" : "non vérifiés").font(.caption.weight(.medium)).foregroundStyle(s.pins.ok == true ? Theme.positive : Theme.warning))) {
                Field(label: "Jeu de contrats", value: s.pins.id + (s.pins.reviewedAt.map { " · revu le \($0)" } ?? "") + (s.pins.checkedAt.map { " · contrôlé \(Fmt.relative($0))" } ?? ""))
                ForEach(s.pins.problems ?? [], id: \.self) { Banner(.danger, $0) }
                ForEach(s.pins.contracts, id: \.name) { c in Field(label: c.name, value: c.address, mono: true) }
            }

            Card("Positions lues sur la chaîne", trailing: AnyView(FutModeBadge(mode: .mainnet))) {
                if let e = s.positionsError { Banner(.danger, "Positions illisibles : \(e). Ce n’est pas une absence de position.") }
                else if s.positions.isEmpty { Text("Aucune position GMX pour cette adresse" + (s.positionsSource.map { " (source : \($0))" } ?? "") + ".").foregroundStyle(.secondary) }
                ForEach(s.positions, id: \.key) { p in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { FutSideText(side: p.side); Text(p.marketName ?? p.market).fontWeight(.medium); Spacer(); Text("PnL ≈ \(FutNum.usd(p.pnlUsd))").foregroundStyle(Theme.change(FutNum.d(p.pnlUsd))).monospacedDigit().help("Estimation au prix mark, avant frais") }
                        FutStatGrid(minimum: 130) {
                            FutStat("Taille", FutNum.usd(p.sizeUsd))
                            FutStat("Collatéral", "\(FutNum.exact(p.collateral, maxFraction: 6)) \(p.collateralSymbol ?? "")")
                            FutStat("Prix d’entrée", FutNum.exact(p.entryPrice, maxFraction: 6))
                            FutStat("Prix (mark)", FutNum.exact(p.markPrice, maxFraction: 6))
                            FutStat("Levier", p.leverage.map { "\(FutNum.exact($0, maxFraction: 2))×" } ?? "—")
                            FutStat("Liquidation", p.liquidationPrice.map { "≈ " + FutNum.exact($0, maxFraction: 6) } ?? "non calculable", color: Theme.warning, note: "ESTIMATION du serveur — GMX n’en publie pas")
                        }
                        if let v = p.venueApi, v.agrees == false { Text("L’API de GMX ne concorde pas avec la lecture de la chaîne : \(v.detail ?? "")").font(.caption).foregroundStyle(Theme.warning) }
                        HStack {
                            TextField("pb", text: $slippage).textFieldStyle(.roundedBorder).frame(width: 60); Text("pb de glissement max").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            ForEach(["0.25", "0.5", "1"], id: \.self) { f in
                                Button("Préparer la réduction de \(FutPositionsCard.percent(f))…") { if let b = Int(slippage) { Task { await flow.prepareClose(p, fraction: f, slippageBps: b) } } }
                                    .disabled(!model.canOperate || flow.busy || Int(slippage).map { (1...500).contains($0) } != true)
                            }
                        }
                        Text("Une réduction est une transaction du portefeuille : elle vous est montrée en entier puis approuvée par votre passkey. « Créée » n’est pas « exécutée » : un keeper l’exécute ou l’annule ensuite.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.padding(10).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            if let op = flow.tracked { Card("Suivi de l’opération GMX") { operation(op, tracked: true) } }
            if !s.pendingOrders.isEmpty {
                Card("Ordres GMX en attente d’un keeper") {
                    ForEach(s.pendingOrders, id: \.key) { o in
                        HStack { FutSideText(side: o.side); Text("\(o.marketName ?? o.market) · \(o.orderType)"); Spacer(); Text("\(FutNum.usd(o.sizeUsd)) · prix acceptable \(FutNum.exact(o.acceptablePrice, maxFraction: 6))" + (o.frozen ? " · GELÉ" : "")).font(.callout).monospacedDigit().foregroundStyle(.secondary) }
                    }
                }
            }
            Card("Marchés GMX épinglés") {
                ForEach(s.markets, id: \.market) { m in
                    HStack { Text(m.name).fontWeight(.medium); Text(m.instrument).font(.caption).foregroundStyle(.secondary); if !m.allowed { Text("hors autorisation").font(.caption2).foregroundStyle(.secondary) }; Spacer(); Text("mark \(FutNum.exact(m.mark, maxFraction: 6)) · oracle \(FutNum.exact(m.oracleMin, maxFraction: 6)) – \(FutNum.exact(m.oracleMax, maxFraction: 6))").font(.callout).monospacedDigit().foregroundStyle(.secondary) }
                }
                if let f = s.facts { Text("Exécution en deux temps" + (f.requestExpirationSec.map { " ; une demande non exécutée devient annulable après \($0) s" } ?? "") + ".").font(.caption).foregroundStyle(.secondary) }
            }
            if !s.operations.isEmpty {
                Card("Opérations GMX") { ForEach(s.operations.filter { $0.id != flow.tracked?.id }.prefix(20)) { operation($0, tracked: false) } }
            }
        } else if flow.status.error == nil {
            ProgressView().frame(maxWidth: .infinity, minHeight: 120)
        }
    }

    @ViewBuilder private func operation(_ op: GmxOperation, tracked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                if tracked, !op.final { ProgressView().controlSize(.small) }
                Text("\(op.kind) · \(op.marketName ?? op.market ?? "")" + (op.side.map { " · \($0)" } ?? "")).fontWeight(.medium)
                Text(op.state).font(.caption.weight(.medium)).foregroundStyle(op.state == "executed" ? Theme.positive : op.final ? Theme.negative : Theme.warning)
                    .padding(.horizontal, 7).padding(.vertical, 2).background(Color.secondary.opacity(0.12), in: Capsule())
                Spacer()
                Text(Fmt.date(op.createdAt)).font(.caption).foregroundStyle(.secondary)
            }
            if op.state == "created" { Text("Ordre créé sur la chaîne, PAS encore exécuté : un keeper GMX doit l’exécuter ou l’annuler.").font(.caption).foregroundStyle(Theme.warning) }
            if let size = op.sizeUsd { Text("Taille \(FutNum.usd(size))" + (op.acceptablePrice.map { " · prix acceptable \(FutNum.exact($0, maxFraction: 6))" } ?? "")).font(.caption).foregroundStyle(.secondary) }
            if let tx = op.txid { Text("Transaction \(tx)").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(1) }
            if let e = op.error { Text(e).font(.caption).foregroundStyle(Theme.negative).fixedSize(horizontal: false, vertical: true) }
            if let ex = op.explorer, let url = URL(string: ex), url.scheme == "https" { Link("Ouvrir dans l’explorateur de blocs", destination: url).font(.caption) }
        }.padding(.vertical, 3)
    }
}

private struct FutGMXSheet: View {
    let model: AppModel
    @Bindable var flow: FutGMXFlow
    let sheet: FutGMXFlow.Sheet

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FutSheetHeader(title: { if case .risk = sheet { return "Lever l’arrêt GMX" }; return "Vérifier et approuver la réduction GMX" }(), mode: .mainnet)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch sheet {
                    case .order(let prep, let a):
                        TransactionReview(intent: a.intent, digest: a.approval.digest, network: model.network(a.intent.network),
                                          ownAddresses: Dictionary((model.accounts?.value.accounts ?? []).map { ($0.network, $0.address) }, uniquingKeysWith: { x, _ in x }), warnings: [],
                                          extra: prep.fields.map { ReviewLine(label: "Lecture du serveur — \($0.label)", value: $0.value) } + prep.fixed.map { ReviewLine(label: "Fixé par le signataire — \($0.label)", value: $0.value) })
                        if let e = prep.estimate { VStack(alignment: .leading, spacing: 4) { HStack { Text("Estimations du serveur").font(.headline); ProvenanceTag(p: .estimate) }; Text(e.displayText).font(.system(.caption, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) } }
                    case .risk(let r):
                        let i = r.intent
                        Banner(.warning, "Lever l’arrêt permet de nouveau d’ouvrir des positions GMX.")
                        ReviewLines(lines: [
                            .init(label: "Type d’opération", value: "Levée de l’arrêt GMX", style: .strong),
                            .init(label: "Arrêt levé", value: i.subject ?? "—"),
                            .init(label: "Autorisation", value: i.authorizationId),
                            .init(label: "Champs assouplis", value: i.loosened.isEmpty ? "aucun" : i.loosened.joined(separator: ", ")),
                            .init(label: "Nonce", value: i.nonce),
                        ])
                        BindingProof(digest: r.approval.digest, expiry: i.expiry)
                    }
                }.padding(20)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if let e = flow.sheetError { Banner(.danger, e) }
                HStack {
                    Button("Fermer sans approuver", role: .destructive) { Task { await flow.dismiss() } }.disabled(flow.approving)
                    Spacer()
                    if flow.approving { ProgressView().controlSize(.small) }
                    Button { Task { await flow.approve() } } label: { Label("Approuver avec la passkey (RÉEL)", systemImage: "touchid") }
                        .buttonStyle(.borderedProminent).tint(FutMode.mainnet.color).controlSize(.large).disabled(flow.approving || !model.canOperate)
                }
            }.padding(16)
        }
        .frame(width: 740, height: 780).interactiveDismissDisabled()
    }
}
