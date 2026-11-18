// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/TradingAgents/MarketMakingView.swift
// Description: Market making as the backend exposes it: the quoting session of ONE mode (paper = simulated fills on real books; live = a venue network), its dead-man switch, breakers, attribution and fills, the owner commands that always work (pull the quotes, flatten the inventory), the go-live checklist with the laboratory's evidence shown as it is, the quoting mandate and its revocation, and the server locks. With a lock closed the live controls are absent.
import SwiftUI
import SPWalletCore

@MainActor @Observable final class MarketMakingStore {
    let model: AppModel
    let api: AgentsAPI
    let id: String
    var mode: AgentMode = .paper { didSet { if oldValue != mode { Task { await refresh() } } } }
    private(set) var views: [AgentMode: MarketMakingView] = [:]
    private(set) var performance: [AgentMode: MarketMakingPerformance] = [:]
    private(set) var fills: [AgentMode: [MarketMakingFill]] = [:]
    private(set) var evidence: MarketMakingEvidence?
    private(set) var bounds: MarketMakingBounds?
    private(set) var errors: [String: String] = [:]
    private(set) var busy: String?
    var actionError: String?
    var notice: String?

    init(model: AppModel, id: String) { self.model = model; self.id = id; api = AgentsAPI(model.client) }

    var view: MarketMakingView? { views[mode] }
    private func note<T: Sendable>(_ key: String, _ r: Result<T, Error>) -> T? {
        switch r { case .success(let v): errors[key] = nil; return v; case .failure(let e): errors[key] = model.describe(e); return nil }
    }

    func refresh() async {
        guard model.phase == .signedIn else { return }
        let api = api, id = id, m = mode
        async let v = Result.catching { try await api.marketMaking(id, mode: m) }
        async let p = Result.catching { try await api.marketMakingPerformance(id, mode: m) }
        async let f = Result.catching { try await api.marketMakingFills(id, mode: m, limit: 200).value }
        if let x = note("view.\(m.rawValue)", await v) { views[m] = x }
        if let x = note("performance.\(m.rawValue)", await p) { performance[m] = x }
        if let x = note("fills.\(m.rawValue)", await f) { fills[m] = x }
        if evidence == nil, let x = note("evidence", await Result.catching { try await api.marketMakingEvidence(locale: "fr") }) { evidence = x }
        if bounds == nil, let x = note("bounds", await Result.catching { try await api.marketMakingBounds() }) { bounds = x }
    }

    func poll() async {
        await refresh()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(view?.session?.state == "running" ? 5 : 20))
            guard !Task.isCancelled else { return }
            if AppActivity.isActive, !model.isOffline, busy == nil { await refresh() }
        }
    }

    private func run(_ name: String, requireSession: Bool = true, _ body: () async throws -> String?) async {
        guard busy == nil, requireSession ? model.phase == .signedIn : model.canOperate else { return }
        busy = name; actionError = nil; notice = nil
        do { notice = try await body() } catch { actionError = model.describe(error) }
        busy = nil
        await refresh()
    }

    private func taken(_ r: MarketMakingCommandResult) -> String {
        let how = switch r.taken { case "engine": "prise par le moteur de la session"; case "queued": "mise en file pour le moteur"; case "direct": "exécutée directement sur la plateforme"; case "nothing": "sans objet : aucune session active et rien sur la plateforme"; default: r.taken }
        return "Commande « \(r.command) » \(how).\(r.note.map { " \($0)" } ?? "")"
    }
    /// Works under every lock and halt; no passkey.
    func pull() async { let api = api, id = id; await run("pull") { self.taken(try await api.pullQuotes(id)) } }
    func flatten() async { let api = api, id = id; await run("flatten") { self.taken(try await api.flattenInventory(id)) } }
    func resume() async { let api = api, id = id; await run("resume", requireSession: false) { self.taken(try await api.resumeQuoting(id)) } }

    func acknowledge(_ ack: MarketMakingAcknowledgement) async {
        let api = api, id = id
        await run("ack", requireSession: false) { let g = try await api.acknowledgeGoLive(id, ack, locale: "fr"); return "Étape enregistrée. Prochaine étape selon le serveur : \(g.nextStep?.id ?? "aucune")." }
    }

    /// Final, no passkey: the signer's copy is revoked first; resting quotes are cancelled.
    func revokeMandate(_ mandateId: String) async {
        let mandates = MandatesAPI(model.client)
        await run("revoke") {
            let r = try await mandates.revoke(id: mandateId, cancelOpenOrders: true, detail: "révoqué par le propriétaire depuis l’app macOS")
            return "Mandat de cotation : \(r.mandate.state) / \(r.mandate.phase). \(r.cancelled) annulation(s) demandée(s)." + (r.signerRevoked == false ? " Le signataire n’a PAS encore confirmé sa révocation\(r.signerError.map { " (\($0))" } ?? "") : elle sera redemandée." : r.signerRevoked == true ? " Révoqué au signataire." : "")
        }
    }

    func recover() async {
        let api = api
        await run("recover", requireSession: false) { let r = try await api.recoverMarketMaking(); return "Réconciliation : \(r.adopted.count) adopté(s), \(r.revoked.count) révoqué(s), \(r.pending.count) en attente." }
    }
}

struct MarketMakingSection: View {
    let model: AppModel
    let d: AgentDetailStore
    let store: AgentsStore
    @State private var mm: MarketMakingStore?
    @State private var confirm: String?
    @State private var ackEvidence = false
    @State private var ackJurisdiction = false
    @State private var testnetNote = ""
    @State private var ackTestnet = false

    var body: some View {
        Group {
            if let mm { content(mm) } else { ProgressView() }
        }
        .task { if mm == nil { mm = MarketMakingStore(model: model, id: d.id) }; await mm?.poll() }
    }

    @ViewBuilder private func content(_ mm: MarketMakingStore) -> some View {
        @Bindable var mm = mm
        let network = mm.view?.session?.network ?? mm.view?.goLive.network
        let kind = ModeKind(mm.mode, liveNetwork: network)
        if let ev = mm.evidence { Banner(.warning, "Énoncé du laboratoire sur la tenue de marché : \(ev.statement)") }
        Card("Session de cotation") {
            Picker("Mode", selection: $mm.mode) { Text("PAPIER").tag(AgentMode.paper); Text("RÉEL").tag(AgentMode.live) }.pickerStyle(.segmented).frame(maxWidth: 260).labelsHidden()
            ModeHeaderBand(kind: kind)
            if let v = mm.view {
                if let s = v.session { session(s, kind) } else { Text("Aucune session en cours dans ce mode.").foregroundStyle(.secondary) }
                Divider()
                Text("Commandes du propriétaire — sans passkey ; retirer et aplanir fonctionnent sous tous les verrous et arrêts").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ModeButton(title: "Retirer les cotations", kind: kind, systemImage: "arrow.uturn.backward", role: .destructive) { confirm = "pull" }
                    ModeButton(title: "Retirer et aplanir l’inventaire", kind: kind, systemImage: "arrow.down.to.line", role: .destructive) { confirm = "flatten" }
                    if v.session?.state == "running", v.session?.status?.manual != nil { ModeButton(title: "Reprendre la cotation", kind: kind, systemImage: "play.fill") { Task { await mm.resume() } }.disabled(!model.canOperate) }
                    if mm.busy != nil { ProgressView().controlSize(.small) }
                    Spacer(minLength: 0)
                }.disabled(model.phase != .signedIn || mm.busy != nil)
                if !v.sessions.isEmpty {
                    DisclosureGroup("Sessions passées de ce mode (\(v.sessions.count))") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(v.sessions.prefix(30)) { s in
                                Text("\(Fmt.date(s.startedAt)) → \(Fmt.date(s.endedAt)) · \(s.instrument) · \(s.state)\(s.endReason.map { " — \($0)" } ?? "") · PnL \(s.pnl?.totalUsd ?? "—") USD · \(s.label)").font(.caption).textSelection(.enabled)
                            }
                        }.padding(.top, 6).modeFramed(kind)
                    }
                }
            } else { Unavailable(what: "Session", error: mm.errors["view.\(mm.mode.rawValue)"]) }
            if let n = mm.notice { Banner(.info, n) }
            if let e = mm.actionError { Banner(.danger, e) }
        }
        .confirmationDialog(confirm == "pull" ? "Retirer toutes les cotations ?" : "Retirer les cotations et aplanir l’inventaire ?", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), titleVisibility: .visible) {
            Button(confirm == "pull" ? "Retirer · \(kind.short)" : "Retirer et aplanir · \(kind.short)", role: .destructive) { let c = confirm; Task { if c == "pull" { await mm.pull() } else { await mm.flatten() } } }
            Button("Annuler", role: .cancel) {}
        } message: { Text(confirm == "pull" ? "Toutes les cotations au repos sont retirées maintenant. L’inventaire est conservé." : "Les cotations sont retirées et l’inventaire est fermé avec des ordres réducteurs, au prix du marché (résultat non garanti).") }

        Card(mm.mode == .paper ? "Attribution sur papier" : "Attribution en réel", trailing: AnyView(ModeTag(kind: kind))) {
            if let p = mm.performance[mm.mode] {
                let k = ModeKind(p.mode, liveNetwork: network)
                VStack(alignment: .leading, spacing: 8) {
                    Text(p.label).font(.callout.weight(.medium)).textSelection(.enabled)
                    Text("\(p.sessions) session(s) · \(p.fills) exécution(s) · volume \(Fmt.amount(p.volumeUsd, maxFraction: 2)) USD").font(.caption).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), alignment: .topLeading)], alignment: .leading, spacing: 10) {
                        ModeFigure(label: "PnL total", value: "\(Fmt.amount(p.attribution.totalUsd, maxFraction: 2)) USD", kind: k)
                        ModeFigure(label: "Capture d’écart", value: "\(Fmt.amount(p.attribution.spreadCaptureUsd, maxFraction: 2)) USD", kind: k)
                        ModeFigure(label: "PnL d’inventaire", value: "\(Fmt.amount(p.attribution.inventoryPnlUsd, maxFraction: 2)) USD", kind: k)
                        ModeFigure(label: "Frais", value: "\(Fmt.amount(p.attribution.feesUsd, maxFraction: 2)) USD", kind: k)
                        ModeFigure(label: "Financement", value: "\(Fmt.amount(p.attribution.fundingUsd, maxFraction: 2)) USD", kind: k)
                        ModeFigure(label: "Par volume", value: p.attribution.bpsOfVolume.map { "\($0) pb" }, kind: k, reason: "volume nul")
                    }
                    ForEach(p.markouts, id: \.horizon) { m in Text("Markout \(m.horizon) : \(m.meanBps.map { "\($0) pb en moyenne" } ?? "indisponible") sur \(m.fills) exécution(s)").font(.callout).monospacedDigit() }
                    if let n = p.note { Text(n).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                }.modeFramed(k)
            } else { Unavailable(what: "Attribution", error: mm.errors["performance.\(mm.mode.rawValue)"]) }
        }

        Card(mm.mode == .paper ? "Exécutions SIMULÉES" : "Exécutions réelles", trailing: AnyView(ModeTag(kind: kind))) {
            if let f = mm.fills[mm.mode] {
                if f.isEmpty { Text("Aucune exécution dans ce mode.").foregroundStyle(.secondary) }
                else {
                    Table(f) {
                        TableColumn("Date") { x in Text(Fmt.dateSeconds(x.ts)).monospacedDigit() }.width(150)
                        TableColumn("Sens") { x in Text(x.side + (x.reduce ? " · réducteur" : "") + (x.maker ? " · maker" : " · taker")) }.width(150)
                        TableColumn("Prix") { x in Text(Fmt.amount(x.price, maxFraction: 6)).monospacedDigit() }.width(110)
                        TableColumn("Taille") { x in Text(Fmt.amount(x.size, maxFraction: 8)).monospacedDigit() }.width(110)
                        TableColumn("Frais") { x in Text(Fmt.amount(x.fee, maxFraction: 6)).monospacedDigit() }.width(90)
                        TableColumn("Markouts 1 s / 10 s / 60 s (pb)") { x in Text("\(x.markoutsBps?.s1 ?? "—") / \(x.markoutsBps?.s10 ?? "—") / \(x.markoutsBps?.s60 ?? "—")" + (x.markoutsDone == false ? " (en cours)" : "")).monospacedDigit() }
                    }.frame(height: min(CGFloat(f.count) * 28 + 34, 380)).modeFramed(kind)
                }
            } else { Unavailable(what: "Exécutions", error: mm.errors["fills.\(mm.mode.rawValue)"]) }
        }
        mandateCard(mm)
        goLiveCard(mm)
        boundsCard(mm)
    }

    // MARK: session

    @ViewBuilder private func session(_ s: MarketMakingSession, _ kind: ModeKind) -> some View {
        let k = ModeKind(s.mode, liveNetwork: s.network)
        VStack(alignment: .leading, spacing: 6) {
            Text(s.label).font(.callout.weight(.semibold)).foregroundStyle(k.color).textSelection(.enabled)
            Field(label: "Instrument / état", value: "\(s.instrument) · \(s.state)\(s.status?.phase.map { " · \($0)" } ?? "")", emphasis: true)
            if s.stale { Banner(.warning, "Session en cours mais son travailleur n’a rien écrit depuis 20 secondes. Dernier battement \(Fmt.relative(s.heartbeatAt)).") }
            if let st = s.status {
                if let r = st.reason, !r.isEmpty { Field(label: "Raison", value: r) }
                Field(label: "Inventaire", value: "\(st.position ?? "—")\(st.positionUsd.map { " (\($0) USD)" } ?? "") · milieu \(st.mid ?? "—")")
                if let m = st.manual { Field(label: "Commande manuelle", value: m == "pull" ? "cotations retirées par vous" : m == "flatten" ? "aplanissement demandé par vous" : m) }
                if let l = st.lock { Field(label: "Verrou", value: l) }
                if let b = st.activeBreakers, !b.isEmpty { Field(label: "Disjoncteurs actifs", value: b.joined(separator: ", ")) }
                if let b = st.blockedSides, !b.isEmpty { Field(label: "Côtés bloqués", value: b.joined(separator: ", ")) }
                if let h = st.halted, !h.isNull, h.boolValue != false { Field(label: "Arrêt", value: JSONFlat.text(h)) }
                if let sw = st.switch {
                    Field(label: "Interrupteur d’homme mort", value: "\(sw.armed ? "ARMÉ" : "non armé")\(sw.deadline.map { " · annulation automatique par la plateforme \(Fmt.relative($0)) sans renouvellement" } ?? "")\(sw.lapsesToday.map { " · \($0) déclenchement(s) aujourd’hui" } ?? "")\(sw.venueTriggersPerDay.map { " (plateforme : \($0)/jour" + (sw.signerStopsAt.map { ", le signataire s’arrête à \($0))" } ?? ")") } ?? "")")
                    if s.mode == .live, !sw.armed, s.state == "running" { Banner(.danger, "L’interrupteur d’homme mort n’est PAS armé alors que la session réelle est en cours.") }
                }
                if let m = st.mandate { Field(label: "Mandat de cotation", value: "\(m.id) · \(m.phase ?? "—") · expire \(Fmt.relative(m.expiresAt)) · cotations restantes : \(m.quotesLeftHour.map(String.init) ?? "—")/h, \(m.quotesLeftDay.map(String.init) ?? "—")/j") }
                if let q = st.quotes, !q.isEmpty {
                    Text("Cotations au repos (\(q.count))").font(.caption.weight(.semibold))
                    ForEach(q, id: \.clientId) { x in Text("\(x.side) \(x.size) @ \(x.price) · \(x.state)\(x.distanceBps.map { " · à \($0) pb du milieu" } ?? "")\(x.ageMs.map { " · \(Int($0 / 1000)) s" } ?? "")").font(Theme.monoSmall) }
                }
            }
            if let p = s.pnl {
                HStack(spacing: 10) {
                    ModeFigure(label: "PnL de la session", value: p.totalUsd.map { "\($0) USD" }, kind: k, reason: "non rapporté")
                    ModeFigure(label: "Capture d’écart", value: p.spreadCaptureUsd.map { "\($0) USD" }, kind: k, reason: "non rapporté")
                    ModeFigure(label: "Frais", value: p.feesUsd.map { "\($0) USD" }, kind: k, reason: "non rapporté")
                    ModeFigure(label: "Exécutions", value: p.fills.map(String.init), kind: k, reason: "non rapporté")
                }
            }
            if let b = s.breakers, !b.isEmpty {
                DisclosureGroup("Disjoncteurs déclenchés (\(b.count))") { VStack(alignment: .leading, spacing: 3) { ForEach(Array(b.enumerated()), id: \.offset) { _, x in Text("\(Fmt.dateSeconds(x.ts)) · \(x.code) → \(x.action)").font(.caption) } }.padding(.top, 6) }
            }
            if let r = s.refusals, !r.isNull { DisclosureGroup("Refus et budget") { VStack(alignment: .leading) { JSONFacts(value: r, depth: 2); JSONFacts(value: s.budget, depth: 2, empty: "") }.padding(.top, 6) } }
        }.modeFramed(k)
    }

    // MARK: mandate

    private func closedLock(_ mm: MarketMakingStore, network: String?) -> MarketMakingBounds.Lock? {
        guard let l = mm.bounds?.locks else { return nil }
        return network == "mainnet" ? l.mainnet.lock : network == "testnet" ? l.testnet.lock : (l.mainnet.lock != nil && l.testnet.lock != nil ? l.testnet.lock : nil)
    }

    @ViewBuilder private func mandateCard(_ mm: MarketMakingStore) -> some View {
        Card("Mandat de cotation") {
            if let m = (mm.views[.live] ?? mm.view)?.mandate {
                let kind = ModeKind(.live, liveNetwork: mm.view?.goLive.network)
                VStack(alignment: .leading, spacing: 5) {
                    Field(label: "Mandat", value: m.id, mono: true)
                    Field(label: "État / phase", value: "\(m.state) · \(m.phase ?? "—")", emphasis: true)
                    Field(label: "Expiration", value: Fmt.date(m.expiresAt))
                    Field(label: "Empreinte", value: m.hash, mono: true)
                    if let i = m.integrity { Banner(.danger, "L’approbation enregistrée de ce mandat ne se vérifie plus : \(i)") }
                    if let mx = m.quoting?.maxima, !mx.isEmpty { Text("Maxima de cotation").font(.caption.weight(.semibold)); ForEach(mx.keys.sorted(), id: \.self) { k in Field(label: k, value: mx[k]!, mono: true) } }
                    if let sec = m.quoting?.section, !sec.isNull { DisclosureGroup("Section de cotation approuvée") { JSONFacts(value: sec, depth: 3).padding(.top, 6) } }
                    if let sg = m.signer, !sg.isNull { DisclosureGroup("Ce que le signataire rapporte") { JSONFacts(value: sg, depth: 3).padding(.top, 6) } }
                }.modeFramed(kind)
                if m.state == "active" || m.phase == "active" || m.phase == "wind_down" {
                    HStack(alignment: .top) {
                        Text("Révoquer est immédiat, définitif et sans passkey : les cotations sont annulées, seuls des ordres réducteurs restent possibles.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button(role: .destructive) { Task { await mm.revokeMandate(m.id); await store.refresh() } } label: { Label("Révoquer le mandat", systemImage: "xmark.shield.fill").fontWeight(.semibold) }
                            .buttonStyle(.borderedProminent).tint(Theme.negative).controlSize(.large).disabled(model.phase != .signedIn || mm.busy != nil)
                    }
                }
            } else { Text("Aucun mandat de cotation pour cet agent.").foregroundStyle(.secondary) }
            Text("Un mandat de cotation autorise le signataire à signer des lots de cotations « post-only » et l’annulation programmée de la plateforme (au plus 7 jours ; homme mort ≤ 120 s). Il ne permet ni retrait ni transfert.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack { Spacer(); Button("Réconcilier les mandats de cotation") { Task { await mm.recover() } }.disabled(!model.canOperate || mm.busy != nil).help("Règle une approbation dont la réponse a été perdue et révoque les mandats orphelins au signataire.") }
        }
    }

    // MARK: go-live checklist

    @ViewBuilder private func goLiveCard(_ mm: MarketMakingStore) -> some View {
        Card("Liste de contrôle du passage en réel") {
            if let g = mm.view?.goLive {
                let lock = closedLock(mm, network: g.network), locks = mm.bounds?.locks
                let allClosed = locks.map { $0.mainnet.lock != nil && $0.testnet.lock != nil } ?? false
                Field(label: "Réseau visé", value: g.network ?? "—")
                ForEach(g.steps) { s in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: s.done ? "checkmark.circle.fill" : "circle").foregroundStyle(s.done ? Theme.positive : .secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(stepTitle(s.id)).fontWeight(.medium)
                            if !s.done, let m = s.missing { Text(m).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) }
                        }
                    }
                }
                if let locks {
                    Divider()
                    LockRow(name: "tenue de marché · mainnet", open: locks.mainnet.lock == nil, reason: locks.mainnet.lock.map { "\($0.message) [\($0.setting)]" } ?? "réglages consultés : \(locks.mainnet.consulted.joined(separator: ", "))")
                    LockRow(name: "tenue de marché · testnet", open: locks.testnet.lock == nil, reason: locks.testnet.lock.map { "\($0.message) [\($0.setting)]" } ?? "réglages consultés : \(locks.testnet.consulted.joined(separator: ", "))")
                } else if let e = mm.errors["bounds"] { Banner(.warning, "État des verrous indisponible : \(e)") }
                Divider()
                if locks == nil || allClosed || lock != nil {
                    Label(locks == nil ? "Les verrous du serveur ne sont pas connus : aucune commande de passage en réel n’est proposée." : "Le serveur a fermé la tenue de marché réelle\(lock.map { " : \($0.message)" } ?? "."). Aucune commande de passage en réel n’est proposée.", systemImage: "lock.fill").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else if let next = g.nextStep { nextStep(next, mm) }
                else if g.ready { Banner(.info, "La liste de contrôle est complète selon le serveur. L’agent se démarre en réel depuis « Cycle de vie », sous le mandat de cotation en vigueur.") }
            } else { Unavailable(what: "Liste de contrôle", error: mm.errors["view.\(mm.mode.rawValue)"]) }
        }
    }

    private func stepTitle(_ id: String) -> String {
        switch id {
        case "paper": "Session sur papier d’une durée suffisante"
        case "evidence": "Lecture des résultats du laboratoire et de la simulation"
        case "jurisdiction": "Avis de juridiction"
        case "testnet": "Essai sur le réseau de test"
        case "mandate": "Mandat de cotation approuvé avec la passkey"
        case "locks": "Verrous du serveur ouverts"
        default: id
        }
    }

    @ViewBuilder private func nextStep(_ s: MarketMakingGoLive.Step, _ mm: MarketMakingStore) -> some View {
        switch s.id {
        case "paper":
            Text("Prochaine étape : faire tourner l’agent sur PAPIER\(mm.evidence.map { " au moins \(Int($0.minPaperMinutes)) minutes" } ?? "") (Cycle de vie → Démarrer · PAPIER).").font(.callout).foregroundStyle(.secondary)
        case "evidence":
            if let ev = mm.evidence {
                Text("Résultats du laboratoire et de la simulation, tels qu’ils sont").font(.callout.weight(.semibold))
                Text(ev.statement).fixedSize(horizontal: false, vertical: true).textSelection(.enabled).padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Theme.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                DisclosureGroup("Détail des résultats (backtest et simulation — jamais une promesse)") { JSONFacts(value: ev.evidence, depth: 3).padding(.top, 6).modeFramed(ModeKind(.research)) }
                AckToggle(isOn: $ackEvidence, text: "J’ai lu ces résultats, y compris lorsqu’ils sont négatifs, et je comprends que la tenue de marché réelle peut perdre de l’argent.")
                HStack { Spacer(); Button("Enregistrer cette lecture") { Task { await mm.acknowledge(.evidence(displayed: ev)); ackEvidence = false } }.disabled(!ackEvidence || !model.canOperate || mm.busy != nil) }
            } else { Unavailable(what: "Résultats du laboratoire", error: mm.errors["evidence"]) }
        case "jurisdiction":
            if let ev = mm.evidence {
                Text(ev.jurisdiction.text).font(.callout).fixedSize(horizontal: false, vertical: true).textSelection(.enabled).padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                AckToggle(isOn: $ackJurisdiction, text: "J’ai lu l’avis de juridiction et je l’accepte.")
                HStack { Spacer(); Button("Enregistrer l’acceptation") { Task { await mm.acknowledge(.jurisdiction(displayed: ev)); ackJurisdiction = false } }.disabled(!ackJurisdiction || !model.canOperate || mm.busy != nil) }
            } else { Unavailable(what: "Avis de juridiction", error: mm.errors["evidence"]) }
        case "testnet":
            TextField("Note sur votre essai sur le réseau de test (facultative)", text: $testnetNote, axis: .vertical).lineLimit(1...3)
            AckToggle(isOn: $ackTestnet, text: "J’atteste avoir moi-même fait tourner cet agent sur le réseau de test de la plateforme.")
            HStack { Spacer(); Button("Enregistrer l’attestation") { Task { await mm.acknowledge(.testnet(note: testnetNote)); ackTestnet = false } }.disabled(!ackTestnet || !model.canOperate || mm.busy != nil) }
        case "mandate":
            Banner(.warning, "Le mandat de cotation ne peut pas être vérifié par cette version de l’app : sa forme signée et sa section de cotation ne sont pas encore recalculées localement avant la passkey. L’app ne propose donc PAS de l’approuver, et il n’existe aucun contournement ici.")
        default:
            Text("Prochaine étape selon le serveur : \(stepTitle(s.id))\(s.missing.map { " — \($0)" } ?? "").").font(.callout).foregroundStyle(.secondary)
        }
    }

    // MARK: bounds

    @ViewBuilder private func boundsCard(_ mm: MarketMakingStore) -> some View {
        Card("Bornes de la tenue de marché (serveur)") {
            if let b = mm.bounds {
                DisclosureGroup("Maxima que le signataire applique à un mandat de cotation") { JSONFacts(value: .object(b.signer), depth: 3).padding(.top, 6) }
                DisclosureGroup("Bornes de la section de cotation") { JSONFacts(value: .object(b.section), depth: 3).padding(.top, 6) }
                DisclosureGroup("Disjoncteurs (\(b.breakers.count))") {
                    VStack(alignment: .leading, spacing: 3) { ForEach(b.breakers, id: \.code) { x in Text("\(x.code) — par défaut : \(x.default)\(x.alwaysStops ? " · arrête toujours" : "")").font(.callout) } }.padding(.top, 6)
                }
            } else { Unavailable(what: "Bornes", error: mm.errors["bounds"]) }
        }
    }
}
