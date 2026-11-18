// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/TradingAgents/PerpAgentViews.swift
// Description: A perp agent: its simulated (paper) derivatives account, and the road to real execution exactly as the server exposes it — the go-live checklist (strategy, venue account, funding, mandate), the proposed mandate, the server locks, then the verified two-prompt passkey approval. When a lock is closed or the server cannot run a mandate, the live controls are absent and the server's reason is shown.
import SwiftUI
import SPWalletCore

struct PerpAgentSection: View {
    let model: AppModel
    let d: AgentDetailStore
    let store: AgentsStore
    @State private var flow: PerpGoLiveFlow?
    @State private var confirmFlatten = false
    @State private var confirmStop = false

    var body: some View {
        if case .perp(let p)? = d.detail {
            paper(p)
            live(p)
        }
    }

    // MARK: paper account

    @ViewBuilder private func paper(_ p: PerpAgentDetail) -> some View {
        let kind = ModeKind(.paper)
        Card("Compte de simulation", trailing: AnyView(ModeTag(kind: kind))) {
            if let acct = p.account {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Le moteur papier exécute contre le carnet réel de la plateforme, mais rien n’atteint la plateforme : positions, ordres, exécutions et financement ci-dessous sont SIMULÉS.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let h = acct.halt { Banner(.warning, "Disjoncteur du compte simulé : \(h)") }
                    Field(label: "Collatéral initial simulé", value: acct.initialCollateral.map { "\(Fmt.amount($0)) USDC" } ?? "—")
                    JSONFacts(value: acct.state, depth: 1, empty: "État du compte simulé indisponible.")
                    if let t = acct.totals, !t.isNull { Text("Totaux").font(.caption.weight(.semibold)); JSONFacts(value: t, depth: 2) }
                    DisclosureGroup("Positions simulées (\(acct.positions.count))") { JSONList(items: acct.positions, empty: "Aucune position.").padding(.top, 6) }
                    DisclosureGroup("Ordres ouverts simulés (\(acct.openOrders.count))") { JSONList(items: acct.openOrders, empty: "Aucun ordre ouvert.").padding(.top, 6) }
                    DisclosureGroup("Dernières exécutions simulées (\(acct.fills.count))") { JSONList(items: acct.fills, limit: 30, empty: "Aucune exécution.").padding(.top, 6) }
                    DisclosureGroup("Financement simulé (\(acct.funding.count))") { JSONList(items: acct.funding, limit: 30, empty: "Aucun paiement de financement.").padding(.top, 6) }
                    DisclosureGroup("Événements de risque (\(acct.riskEvents.count))") { JSONList(items: acct.riskEvents, limit: 30, empty: "Aucun événement.").padding(.top, 6) }
                    HStack {
                        Spacer()
                        ModeButton(title: "Fermer toutes les positions", kind: kind, systemImage: "arrow.down.to.line", role: .destructive) { confirmFlatten = true }
                            .disabled(!model.canOperate || d.busy != nil || acct.positions.isEmpty || p.agent.mode == .live)
                    }
                }.modeFramed(kind)
            } else { Text("Cet agent n’a pas de compte de simulation.").foregroundStyle(.secondary) }
            if let n = d.notice { Banner(.info, n) }
            if let e = d.actionError { Banner(.danger, e) }
        }
        .confirmationDialog("Fermer toutes les positions du compte PAPIER ?", isPresented: $confirmFlatten, titleVisibility: .visible) {
            Button("Fermer · PAPIER", role: .destructive) { Task { await d.flattenPaper() } }
            Button("Annuler", role: .cancel) {}
        } message: { Text("Des ordres réducteurs simulés ferment les positions du compte de simulation. Rien n’est envoyé à la plateforme.") }
    }

    // MARK: live

    @ViewBuilder private func live(_ p: PerpAgentDetail) -> some View {
        let a = p.agent, l = p.live
        let kind = ModeKind(.live, liveNetwork: l?.network ?? a.liveNetwork)
        Card("Exécution réelle sous mandat", trailing: AnyView(Group { if a.mode == .live { ModeTag(kind: kind) } })) {
            if let l, !l.available {
                Label("Ce serveur ne peut pas exécuter de mandat de dérivés\(l.reason.map { " : \($0)" } ?? ".")", systemImage: "lock.fill").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else if a.mode == .live, let l {
                VStack(alignment: .leading, spacing: 6) {
                    Field(label: "Réseau de la plateforme", value: l.network == "mainnet" ? "mainnet — ARGENT RÉEL" : "\(l.network ?? "—") — argent fictif", emphasis: true)
                    Field(label: "Mandat", value: l.mandateId ?? "—", mono: true)
                    Field(label: "En réel depuis", value: Fmt.date(l.since) + (l.paused ? " · EN PAUSE (positions conservées)" : ""))
                    if let c = l.capital { Field(label: "Capital de référence", value: "\(Fmt.amount(c)) USDC") }
                    Text("Compte de la plateforme (lu sur la plateforme)").font(.caption.weight(.semibold)); JSONFacts(value: l.account, depth: 2, empty: "Compte non lu.")
                    Text("Mandat et compteurs rapportés par le signataire").font(.caption.weight(.semibold)); JSONFacts(value: l.signer, depth: 3, empty: "Le signataire n’a rien rapporté.")
                }.modeFramed(kind)
                Divider()
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Arrêt et révocation").font(.headline)
                        Text("Sans passkey : le mandat est révoqué au signataire et les positions sont fermées avec des ordres réducteurs, au prix du marché (résultat non garanti). La pause, elle, conserve les positions et le mandat.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        Button(role: .destructive) { confirmStop = true } label: { Label("Arrêter et révoquer le mandat", systemImage: "xmark.shield.fill").fontWeight(.semibold) }.buttonStyle(.borderedProminent).tint(Theme.negative).controlSize(.large)
                        if l.paused { ModeButton(title: "Reprendre", kind: kind, systemImage: "play.fill") { Task { await d.resume() } } }
                        else { ModeButton(title: "Mettre en pause", kind: kind, systemImage: "pause.fill") { Task { await d.pause() } } }
                    }.disabled(!model.canOperate || d.busy != nil)
                }
            } else if let flow {
                readiness(flow, a)
            } else { ProgressView() }
        }
        .task(id: a.mode) { if flow == nil { flow = PerpGoLiveFlow(model: model, agentId: a.id) }; if a.mode != .live, l?.available != false { await flow?.load() } }
        .confirmationDialog("Arrêter l’agent et révoquer son mandat ?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Arrêter et révoquer · \(kind.short)", role: .destructive) { Task { await d.stop(); await store.refresh() } }
            Button("Annuler", role: .cancel) {}
        } message: { Text("Le mandat est révoqué au signataire. Les positions sont fermées avec des ordres réducteurs ; l’agent reste « arrêt en cours » jusqu’à la fin. Pendant 24 heures, seuls des annulations et des ordres réducteurs peuvent encore être signés.") }
        .sheet(isPresented: Binding(get: { flow?.step == .review || flow?.step == .approving }, set: { _ in })) {
            if let flow, let ap = flow.approval { PerpLiveSheet(model: model, flow: flow, approval: ap) }
        }
        .onChange(of: flow?.step) { _, s in if s == .done { Task { await d.refresh(); await store.refresh() } } }
    }

    /// The server locks that close the live path for the chosen venue account; empty = none known to be closed.
    private func closedLocks(_ r: PerpLiveReadiness) -> [(String, String?)] {
        var out: [(String, String?)] = []
        if let l = r.steps.mandate.lock { out.append((l.code, l.reason)) }
        var ids = ["trading_api_execution"]
        if r.account?.network == "mainnet" { ids += ["deriv_live_mainnet", "deriv_mandate_mainnet"] }
        for id in ids { if let l = store.lock(id), !l.on { out.append((l.id, l.why)) } }
        return out
    }

    @ViewBuilder private func readiness(_ flow: PerpGoLiveFlow, _ a: Agent) -> some View {
        @Bindable var flow = flow
        if let r = flow.readiness {
            let s = r.steps, locks = closedLocks(r)
            VStack(alignment: .leading, spacing: 8) {
                step(s.strategy.ok, "1 · Stratégie approuvée", s.strategy.ok ? "\(s.strategy.name ?? "") \(s.strategy.version ?? "")" : s.strategy.reason)
                step(s.account.ok, "2 · Compte de la plateforme autorisé", s.account.ok ? r.account.map { "\($0.label ?? $0.id) · \($0.network) · \($0.account)" } : s.account.reason ?? s.account.code)
                step(s.funded.ok, "3 · Compte approvisionné", s.funded.ok ? s.funded.equity.map { "valeur du compte : \(Fmt.amount($0)) USDC" } : (s.funded.reason ?? s.funded.code).map { "\($0)\(s.funded.minEquity.map { " (minimum \($0) USDC)" } ?? "")" })
                step(s.mandate.ok, "4 · Mandat approuvé avec la passkey", s.mandate.ok ? "mandat \(s.mandate.mandateId ?? "") — \(s.mandate.phase ?? "")" : s.mandate.phase.map { "phase : \($0)" })
            }
            if let missing = s.account.instrumentsMissing, !missing.isEmpty { Banner(.warning, "Instruments absents de l’autorisation du compte : \(missing.joined(separator: ", ")).") }
            if !r.accounts.isEmpty {
                Form {
                    Picker("Compte de la plateforme", selection: $flow.accountId) {
                        ForEach(r.accounts) { acct in
                            Text("\(acct.label ?? acct.id) — \(acct.network == "mainnet" ? "mainnet (argent réel)" : acct.network)\(acct.equity.map { " · \($0) USDC" } ?? "")\(acct.usedBy.map { " · utilisé par \($0.name)" } ?? "")").tag(acct.id)
                        }
                    }
                    TextField("Validité du mandat (jours, 1 à \(r.proposal?.maxDays ?? s.account.authorization?.maxMandateDays ?? AgentVenueMandate.maxDays))", text: $flow.daysText, prompt: Text("à indiquer"))
                }.formStyle(.grouped).scrollDisabled(true)
                    .onChange(of: flow.accountId) { Task { await flow.load() } }
                    .onChange(of: flow.days) { Task { await flow.load() } }
            } else {
                Text("Aucun compte de plateforme n’existe dans ce portefeuille. Un compte se crée, s’autorise (passkey) et s’approvisionne dans la section Contrats à terme.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let acct = r.account, let e = acct.error { Banner(.warning, "Compte illisible : \(e)") }
            if let pr = r.proposal { proposal(pr, r) }
            if !locks.isEmpty {
                Divider()
                Text("Passage en réel fermé par le serveur").font(.callout.weight(.semibold))
                ForEach(Array(locks.enumerated()), id: \.offset) { _, l in LockRow(name: l.0, open: false, reason: l.1) }
                Text("Tant qu’un de ces verrous est fermé, aucune commande de mandat réel n’est proposée ici.").font(.caption).foregroundStyle(.secondary)
            } else {
                Text(guidance(r.next)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let e = flow.error { Banner(.danger, e) }
                if flow.step == .done { Banner(.ok, "Mandat approuvé. État de l’agent selon le serveur : \(flow.result.map { AgentText.phase($0.agent.state) } ?? "—").") }
                if r.next == "mandate", r.proposal != nil {
                    let kind = ModeKind(.live, liveNetwork: r.account?.network)
                    HStack {
                        if flow.days == nil { Text("Indiquez la validité du mandat en jours : aucune durée par défaut n’est appliquée.").font(.callout).foregroundStyle(Theme.warning) }
                        Spacer()
                        if flow.step == .preparing { ProgressView().controlSize(.small); Text("Construction et vérification du mandat…").foregroundStyle(.secondary) }
                        ModeButton(title: "Préparer le mandat à approuver…", kind: kind, systemImage: "touchid", prominent: true) { Task { await flow.prepare(agent: a) } }
                            .disabled(!model.canOperate || flow.days == nil || (flow.step != .idle && flow.step != .done) || store.killSwitch?.engaged == true)
                    }
                    if store.killSwitch?.engaged == true { Text("Arrêt d’urgence engagé : aucun mandat n’est préparé.").font(.caption).foregroundStyle(Theme.negative) }
                }
            }
            HStack { Spacer(); if flow.loading { ProgressView().controlSize(.small) }; Button("Relire la liste de contrôle") { Task { await flow.load() } } }
        } else if let e = flow.readinessError { Banner(.danger, "Liste de contrôle indisponible : \(e)"); Button("Réessayer") { Task { await flow.load() } } }
        else { ProgressView() }
    }

    private func guidance(_ next: String) -> String {
        switch next {
        case "strategy": "Prochaine étape : approuver une version de stratégie testée (onglet Stratégie)."
        case "account": "Prochaine étape : un compte de la plateforme autorisé pour les instruments de l’agent (section Contrats à terme)."
        case "fund": "Prochaine étape : approvisionner le compte de la plateforme (section Contrats à terme)."
        case "mandate": "Tout est prêt pour le mandat. Préparer ne signe rien : vous verrez le mandat complet, vérifié par cette app, avant d’approuver avec votre passkey."
        case "live": "Un mandat est en vigueur : l’agent se démarre en réel depuis « Cycle de vie », en haut de la page."
        case "locked": "Le serveur a fermé cette voie."
        default: "Étape suivante selon le serveur : \(next)."
        }
    }

    private func step(_ ok: Bool, _ title: String, _ detail: String?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle").foregroundStyle(ok ? Theme.positive : .secondary)
            VStack(alignment: .leading, spacing: 1) { Text(title).fontWeight(.medium); if let detail, !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) } }
        }
    }

    @ViewBuilder private func proposal(_ pr: PerpLiveProposal, _ r: PerpLiveReadiness) -> some View {
        let kind = ModeKind(.live, liveNetwork: r.account?.network), b = pr.body
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text("Mandat que le serveur proposerait (aperçu — rien n’est préparé)").font(.callout.weight(.semibold)); ModeTag(kind: kind, compact: true) }
            Field(label: "Valeur du compte (référence)", value: "\(Fmt.amount(pr.capital)) USDC")
            Field(label: "Validité", value: "\(pr.days) jour(s) (maximum \(pr.maxDays))")
            Field(label: "Instruments", value: b.instruments.map { "\($0.instrument) — levier ≤ ×\($0.maxLeverage), position ≤ \(Fmt.amount($0.maxPositionNotional)) USDC" }.joined(separator: "\n"))
            Field(label: "Notionnel par ordre", value: "≤ \(Fmt.amount(b.maxOrderNotional)) USDC")
            Field(label: "Exposition brute", value: "≤ \(Fmt.amount(b.maxGrossExposure)) USDC")
            Field(label: "Volume quotidien", value: "≤ \(Fmt.amount(b.maxDailyTurnover)) USDC")
            Field(label: "Plancher de valeur du compte", value: "\(Fmt.amount(b.floorEquity)) USDC (limite de perte appliquée par le signataire)")
            Field(label: "Ordres", value: "≤ \(b.maxOrdersPerHour) par heure · ≤ \(b.maxOrdersPerDay) par jour")
            ForEach(pr.derived, id: \.field) { x in Text("\(x.field) = \(x.value) — \(x.from)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            ForEach(pr.notes, id: \.self) { n in Label(n, systemImage: "arrow.down.right").font(.caption).foregroundStyle(Theme.warning) }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading).modeFramed(kind).background(kind.color.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}
