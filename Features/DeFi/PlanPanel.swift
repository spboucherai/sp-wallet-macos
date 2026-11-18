// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/DeFi/PlanPanel.swift
// Description: The any-to-any plan screen inside the DeFi hub: the form and the candidate multi-leg routes (every leg with its provider, expected and worst-case amounts, fees, gas and signer-limit requirements), then the running plan — each leg's real state, what it actually spent and received, its attempts — with the one action that is the owner's at that moment: prepare a leg, approve it by passkey on its verified intent, wait, or decide after a pause (retry, re-plan, stop).
import SwiftUI
import SPWalletCore

struct PlanPanel: View {
    let model: AppModel
    @State private var flow: PlanFlow?

    var body: some View {
        Group {
            if let flow {
                if let e = flow.loadError { Card("Parcours multi-étapes") { Banner(.danger, "Parcours illisibles : \(e)") } }
                if let p = flow.plan { ActivePlanCard(model: model, flow: flow, plan: p) }
                else if flow.loaded {
                    PlanFormCard(model: model, flow: flow)
                    if let q = flow.quote { PlanCandidatesCard(model: model, flow: flow, quote: q) }
                }
                if !flow.recent.isEmpty, flow.plan?.isOpen != true { RecentPlansCard(plans: flow.recent) }
            } else { ProgressView() }
        }
        .task {
            if flow == nil { flow = PlanFlow(model: model) }
            await flow?.load()
        }
        .task(id: "\(flow?.plan?.id ?? "")|\(flow?.plan?.next.rawValue ?? "")|\(flow?.operation == nil)") { await flow?.follow() }
        .sheet(isPresented: Binding(get: { flow?.operation != nil }, set: { _ in })) {
            if let flow, let op = flow.operation, let p = flow.plan { PlanLegReviewSheet(model: model, flow: flow, plan: p, operation: op) }
        }
    }
}

@MainActor enum PlanText {
    static func kind(_ k: String) -> String {
        switch k { case "swap": "Échange sur le même réseau"; case "bridge": "Pont USDC (Circle CCTP)"; case "xswap": "Échange natif inter-chaînes (THORChain)"; default: k }
    }
    static func legState(_ s: PlanLegState) -> String {
        switch s {
        case .pending: "Pas encore son tour"
        case .ready: "Prête à être préparée"
        case .proposed: "Préparée — en attente de la passkey"
        case .inFlight: "Approuvée — en vol, pas encore réglée"
        case .settled: "Réglée (montant lu sur la chaîne)"
        default: s.rawValue
        }
    }
    static func planState(_ p: PlanView) -> String {
        switch p.state {
        case .active: "En cours"
        case .paused: "En pause — une décision est attendue"
        case .done: p.isComplete ? "Terminé : toutes les étapes sont réglées" : "Terminé"
        case .stopped: "Arrêté — les fonds sont restés où ils étaient"
        default: p.state.rawValue
        }
    }
    static func pause(_ code: String) -> String {
        switch code {
        case "no_funds": "Le portefeuille ne détient plus l’actif de cette étape."
        case "floor": "Le résultat final estimé est passé sous votre plancher."
        case "refused": "L’étape a été rejetée ou son approbation a expiré."
        case "refunded": "THORChain a remboursé l’actif source : l’étape n’a pas eu lieu."
        case "leg_failed": "L’étape a échoué."
        default: "La préparation de l’étape a été refusée (\(code))."
        }
    }
    static func issue(_ i: PlanIssue) -> String {
        let need = "\(Fmt.amount(i.needDisplay, maxFraction: 8)) \(i.symbol)", have = "\(Fmt.amount(i.haveDisplay, maxFraction: 8)) \(i.symbol)", net = i.networkName ?? i.network
        let leg = i.leg.map { "Étape \($0 + 1) : " } ?? ""
        let text: String = switch i.code {
        case "insufficient_balance": "solde insuffisant sur \(net) (requis \(need), détenu \(have))"
        case "limit_missing": "le signataire n’a aucune limite définie pour \(i.symbol) sur \(net)"
        case "limit_per_transfer": "dépasse la limite par transfert du signataire sur \(net) (requis \(need), limite \(have))"
        case "limit_daily": "dépasse ce qui reste de la limite quotidienne du signataire sur \(net) (requis \(need), reste \(have))"
        case "limit_margin": "trop proche de la limite du signataire sur \(net) (requis \(need), disponible \(have))"
        case "below_minimum": "sous le minimum du protocole (minimum \(need), prévu \(have))"
        case "gas_missing": "pas assez de \(i.symbol) sur \(net) pour les frais (requis \(need), détenu \(have))"
        case "gas_unknown": "le solde de \(i.symbol) sur \(net) n’a pas pu être lu (requis \(need))"
        default: "\(i.code) sur \(net) (requis \(need), disponible \(have))"
        }
        return leg + text
    }
    static func notExecutable(_ n: PlanQuote.NotExecutable, model: AppModel) -> String {
        switch n.code {
        case "same_asset": "Départ et arrivée sont le même actif."
        case "solana_evm_bridge": "Aucun parcours exécutable entre ces deux actifs avec les capacités actuelles du serveur (liaison Solana ↔ EVM non chaînable ici)."
        case "network_without_execution": "Le portefeuille n’exécute aucun échange sur \(n.network.map { model.network($0)?.name ?? $0 } ?? "ce réseau") : aucun parcours ne peut y commencer ou y finir par un échange."
        case "no_executable_path": "Aucun enchaînement d’étapes exécutables ne relie ces deux actifs."
        default: "Aucun parcours exécutable (\(n.code))."
        }
    }
    static func fee(_ f: PlanCandidate.Fee) -> String {
        let kind: String = switch f.kind { case "network": "Réseau"; case "protocol": "Protocole"; case "provider": "Fournisseur"; case "bridge": "Pont"; case "affiliate": "Affiliation"; default: f.kind }
        return "\(kind) : \(Fmt.amount(f.display, maxFraction: 8)) \(f.symbol) (\(f.networkName ?? f.network))" + (f.usd.map { " \(SwapText.usd($0))" } ?? "") + (f.includedInOutput == true ? " — déjà déduit" : " — en sus") + (f.estimated == true ? " — estimé" : "")
    }
    static func asset(_ a: SwapAsset) -> String { "\(a.symbol) sur \(a.networkName ?? a.network)" }
}

// MARK: - Form and candidates

private struct PlanFormCard: View {
    let model: AppModel
    @Bindable var flow: PlanFlow

    var body: some View {
        Card("Parcours multi-étapes — d’un actif sur un réseau à un autre actif sur un autre réseau") {
            Text("Un parcours enchaîne jusqu’à trois opérations ordinaires (échange, pont USDC, échange natif). Il ne détient jamais vos fonds : entre deux étapes, ils sont un solde ordinaire de ce portefeuille. Chaque étape exige sa propre approbation par passkey ; rien n’avance tout seul.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Départ").font(.caption).foregroundStyle(.secondary)
                    SwapAssetPicker(model: model, label: "Actif de départ", assets: flow.assets, selection: $flow.fromKey, exclude: flow.toKey)
                }
                Image(systemName: "arrow.right").foregroundStyle(.secondary).padding(.bottom, 14)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Arrivée").font(.caption).foregroundStyle(.secondary)
                    SwapAssetPicker(model: model, label: "Actif d’arrivée", assets: flow.assets, selection: $flow.toKey, exclude: flow.fromKey)
                }
            }
            HStack {
                TextField("Montant de départ", text: $flow.amount, prompt: Text("0.0")).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                Text(flow.from?.symbol ?? "").foregroundStyle(.secondary)
                if let f = flow.from, let b = SwapText.balance(model, of: f) {
                    Text(b.isAvailable ? "Solde : \(model.settings.hideBalances ? "••••" : Fmt.amount(b.display, maxFraction: 8))" : "Solde indisponible").font(.callout).foregroundStyle(b.isAvailable ? Color.secondary : Theme.negative)
                }
                Spacer()
            }
            HStack {
                Text("Tolérance par étape").foregroundStyle(.secondary)
                TextField("%", text: $flow.slippageText).textFieldStyle(.roundedBorder).frame(width: 64).multilineTextAlignment(.trailing)
                Text("%  (0,01 – 3 ; défaut du serveur 0,5)").foregroundStyle(.secondary)
                Spacer()
                Text("Plancher global (facultatif)").foregroundStyle(.secondary)
                TextField("aucun", text: $flow.floorText).textFieldStyle(.roundedBorder).frame(width: 130).multilineTextAlignment(.trailing)
                Text(flow.to?.symbol ?? "").foregroundStyle(.secondary)
            }
            Text("Plancher : avant chaque étape, si le résultat final estimé passe sous ce montant, le parcours se met en pause au lieu de continuer.").font(.caption).foregroundStyle(.secondary)
            if let e = flow.error { Banner(.danger, e) }
            HStack {
                if let p = flow.formProblem, !flow.amount.isEmpty { Text(p).font(.callout).foregroundStyle(Theme.warning) }
                Spacer()
                if flow.busy == .quoting { ProgressView().controlSize(.small); Text("Cotation réelle de chaque étape…").font(.callout).foregroundStyle(.secondary) }
                Button("Chercher des parcours") { Task { await flow.quotePlans() } }.buttonStyle(.borderedProminent)
                    .disabled(flow.formProblem != nil || !model.canOperate || flow.busy != nil)
            }
            Text("Chercher ne prépare rien, ne signe rien et n’enregistre rien.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct PlanCandidatesCard: View {
    let model: AppModel
    let flow: PlanFlow
    let quote: PlanQuote

    var body: some View {
        Card("Parcours possibles (\(quote.plans.count))", trailing: flow.quotedAt.map { AnyView(Text("Cotés \(Fmt.relative($0))").font(.caption).foregroundStyle(.secondary)) }) {
            if !flow.quoteIsCurrent { Banner(.warning, "Le formulaire a changé depuis cette recherche : relancez-la avant de démarrer un parcours.") }
            if let n = quote.notExecutable { Banner(.warning, PlanText.notExecutable(n, model: model)) }
            else if quote.plans.isEmpty { Banner(.warning, "Aucun parcours n’a de cotation en ce moment.") }
            ForEach(quote.plans) { c in candidate(c); Divider() }
            if !quote.skipped.isEmpty {
                Text("Formes écartées faute de cotation").font(.caption).foregroundStyle(.secondary)
                ForEach(Array(quote.skipped.enumerated()), id: \.offset) { _, s in
                    Text("• étape \(s.leg + 1) : \(s.message) [\(s.code)]").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder private func candidate(_ c: PlanCandidate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(c.legs.count) étape\(c.legs.count > 1 ? "s" : "") · \(c.approvals) approbation\(c.approvals > 1 ? "s" : "") par passkey · \(SwapText.duration(c.seconds))").font(.headline)
                Spacer()
                if c.executable { Label("Peut démarrer", systemImage: "checkmark.seal").foregroundStyle(Theme.positive).font(.callout) }
                else { Label("Ne peut pas démarrer", systemImage: "xmark.octagon").foregroundStyle(Theme.negative).font(.callout) }
            }
            HStack(spacing: 8) {
                Text("Attendu : \(Fmt.amount(c.expectedOutDisplay, maxFraction: 8)) \(c.to.symbol)").fontWeight(.semibold).monospacedDigit()
                ProvenanceTag(p: .estimate)
                Text("Pire cas (chaque étape à son minimum garanti) : \(Fmt.amount(c.worstOutDisplay, maxFraction: 8)) \(c.to.symbol)").monospacedDigit().foregroundStyle(.secondary)
            }
            if c.expectedUsd != nil || c.extraFeesUsd != nil {
                Text("Valorisation : entrée \(SwapText.usd(c.inUsd)) · sortie attendue \(SwapText.usd(c.expectedUsd)) · pire cas \(SwapText.usd(c.worstUsd)) · frais en sus \(SwapText.usd(c.extraFeesUsd))").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(c.legs.enumerated()), id: \.offset) { k, l in leg(k, l) }
            if let r = c.requirements, !r.gas.isEmpty || !r.limits.isEmpty { requirements(r) }
            ForEach(Array(c.issues.enumerated()), id: \.offset) { _, i in
                Label(PlanText.issue(i), systemImage: i.blocking ? "xmark.octagon.fill" : "exclamationmark.triangle.fill").font(.callout)
                    .foregroundStyle(i.blocking ? Theme.negative : Theme.warning).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                if flow.busy == .starting(c.id) { ProgressView().controlSize(.small) }
                Button("Démarrer ce parcours") { Task { await flow.start(c) } }
                    .disabled(!c.executable || !flow.quoteIsCurrent || !model.canOperate || flow.busy != nil)
                    .help("Enregistre le parcours sur le serveur. Rien n’est préparé ni signé : la première étape devient « prête ».")
            }
        }
    }

    private func leg(_ k: Int, _ l: PlanCandidate.Leg) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(k + 1). \(PlanText.kind(l.kind)) — \(l.label ?? l.via)\(l.speed.map { " · \($0)" } ?? "")").fontWeight(.medium)
            Text("\(PlanText.asset(l.from)) → \(PlanText.asset(l.to))" + ((l.venues ?? []).isEmpty ? "" : " · via \((l.venues ?? []).joined(separator: ", "))") + " · \(SwapText.duration(l.seconds))").font(.callout).foregroundStyle(.secondary)
            Text("Entrée attendue \(Fmt.amount(l.expectedInDisplay, maxFraction: 8)) \(l.from.symbol) (pire cas \(Fmt.amount(l.worstInDisplay, maxFraction: 8))) → sortie attendue \(Fmt.amount(l.expectedOutDisplay, maxFraction: 8)) \(l.to.symbol) · minimum \(Fmt.amount(l.worstOutDisplay, maxFraction: 8)) \(l.to.symbol)")
                .font(.callout).monospacedDigit().fixedSize(horizontal: false, vertical: true)
            ForEach(Array((l.fees ?? []).enumerated()), id: \.offset) { _, f in Text(PlanText.fee(f)).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private func requirements(_ r: PlanCandidate.Requirements) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Prérequis vérifiés par le serveur").font(.caption).foregroundStyle(.secondary)
            ForEach(Array(r.gas.enumerated()), id: \.offset) { _, g in
                Label("Frais sur \(g.networkName ?? g.network) : \(Fmt.amount(g.needDisplay, maxFraction: 8)) \(g.symbol) requis · détenu \(g.haveDisplay.map { Fmt.amount($0, maxFraction: 8) } ?? "illisible")", systemImage: g.ok ? "checkmark.circle" : "xmark.circle")
                    .font(.caption).foregroundStyle(g.ok ? Color.secondary : Theme.negative)
            }
            ForEach(Array(r.limits.enumerated()), id: \.offset) { _, l in
                Label("Limites du signataire, étape \(l.leg + 1) : \(Fmt.amount(l.needDisplay, maxFraction: 8)) \(l.symbol) requis · par transfert \(Fmt.amount(l.perTransferDisplay, maxFraction: 8)) · reste aujourd’hui \(Fmt.amount(l.leftTodayDisplay, maxFraction: 8))", systemImage: l.ok ? "checkmark.circle" : "xmark.circle")
                    .font(.caption).foregroundStyle(l.ok ? Color.secondary : Theme.negative)
            }
        }
    }
}

// MARK: - The running plan

private struct ActivePlanCard: View {
    let model: AppModel
    @Bindable var flow: PlanFlow
    let plan: PlanView

    var body: some View {
        Card("Parcours \(PlanText.asset(plan.from)) → \(PlanText.asset(plan.to))", trailing: AnyView(HStack(spacing: 8) {
            if SwapText.isSimulatedServer(model) { ProvenanceTag(p: .simulated, text: "Serveur de test") }
            Button("Relire") { Task { await flow.refresh() } }.controlSize(.small).disabled(flow.busy != nil || model.phase != .signedIn)
        })) {
            header
            if let pz = plan.pause, plan.state == .paused {
                Banner(.warning, "Pause à l’étape \(pz.leg + 1) — \(PlanText.pause(pz.code))\nServeur : \(pz.message)")
            }
            ForEach(plan.legs) { l in PlanLegRow(model: model, plan: plan, leg: l) }
            if let e = flow.readError { Banner(.warning, "Dernière lecture du parcours en échec : \(e)") }
            if let e = flow.error { Banner(.danger, e) }
            Divider()
            actions
        }
    }

    @ViewBuilder private var header: some View {
        HStack(spacing: 10) {
            Group {
                if plan.isComplete { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.positive) }
                else if plan.state == .stopped { Image(systemName: "stop.circle.fill").foregroundStyle(.secondary) }
                else if plan.state == .paused { Image(systemName: "pause.circle.fill").foregroundStyle(Theme.warning) }
                else if plan.next == .wait { ProgressView().controlSize(.small) }
                else { Image(systemName: "hand.raised.circle.fill").foregroundStyle(Theme.accent) }
            }.font(.title2)
            VStack(alignment: .leading) {
                Text(PlanText.planState(plan)).font(.title3.weight(.semibold))
                Text("Étape \(min(plan.current + 1, max(plan.legs.count, 1))) sur \(plan.legs.count)" + (plan.replans > 0 ? " · re-planifié \(plan.replans) fois" : "")).font(.callout).foregroundStyle(.secondary)
            }
        }
        Field(label: "Montant de départ", value: "\(Fmt.amount(plan.amountInDisplay)) \(plan.from.symbol)")
        Field(label: "Prévu au démarrage", value: "attendu \(Fmt.amount(plan.plannedExpectedDisplay, maxFraction: 8)) \(plan.to.symbol) · pire cas \(Fmt.amount(plan.plannedWorstDisplay, maxFraction: 8)) \(plan.to.symbol) (information, pas une promesse)")
        if let e = plan.estimate { Field(label: "Estimation actuelle", value: "attendu \(Fmt.amount(e.expectedOutDisplay, maxFraction: 8)) · pire cas \(Fmt.amount(e.worstOutDisplay, maxFraction: 8)) \(plan.to.symbol)" + (e.at.map { " — \(Fmt.relative($0))" } ?? "")) }
        Field(label: "Plancher global", value: plan.floorDisplay.map { "\(Fmt.amount($0, maxFraction: 8)) \(plan.to.symbol)" } ?? "aucun")
        Field(label: "Tolérance par étape", value: SwapText.bps(plan.slippageBps))
        if plan.isComplete, let r = plan.receivedDisplay {
            HStack { Field(label: "Reçu à l’arrivée", value: "\(Fmt.amount(r)) \(plan.to.symbol) sur \(plan.to.networkName ?? plan.to.network)", emphasis: true); ProvenanceTag(p: .verified) }
        } else {
            Field(label: "Où sont les fonds", value: "\(Fmt.amount(plan.holding.amountDisplay)) \(plan.holding.symbol) sur \(plan.holding.networkName ?? plan.holding.network) — solde ordinaire de ce portefeuille" + (plan.next == .wait ? " (une étape est en vol : ce chiffre date d’avant son départ)" : ""))
        }
    }

    @ViewBuilder private var actions: some View {
        let k = plan.current + 1
        switch plan.next {
        case .prepare:
            HStack {
                Text("L’étape \(k) est prête. La préparer demande une route ferme au serveur et ne signe rien ; vous approuverez ensuite sur l’écran de vérification.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer()
                secondary
                if flow.busy == .preparing { ProgressView().controlSize(.small) }
                Button("Préparer l’étape \(k)…") { Task { await flow.prepareLeg() } }.buttonStyle(.borderedProminent).disabled(!model.canOperate || flow.busy != nil)
            }
        case .approve:
            HStack {
                Text("Une demande d’approbation existe déjà pour l’étape \(k) mais cette app n’en détient pas le défi vérifié. La préparer de nouveau retire l’ancienne demande (jamais utilisée) et en émet une nouvelle, vérifiée avant toute signature.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer()
                secondary
                if flow.busy == .preparing { ProgressView().controlSize(.small) }
                Button("Préparer de nouveau l’étape \(k)…") { Task { await flow.prepareLeg() } }.buttonStyle(.borderedProminent).disabled(!model.canOperate || flow.busy != nil)
            }
        case .wait:
            HStack { ProgressView().controlSize(.small); Text("Étape \(k) en vol. La suivante ne sera proposée qu’une fois son résultat lu sur la chaîne. Un parcours ne peut pas être arrêté pendant qu’une étape est en vol.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        case .paused:
            VStack(alignment: .leading, spacing: 8) {
                Text("À vous de décider — aucune de ces actions ne signe quoi que ce soit :").font(.callout)
                HStack {
                    Button("Réessayer l’étape \(k)") { Task { await flow.retry(.unchanged) } }.buttonStyle(.borderedProminent)
                    if plan.floor != nil { Button("Réessayer sans plancher") { Task { await flow.retry(.remove) } } }
                    TextField("nouveau plancher", text: $flow.newFloorText).textFieldStyle(.roundedBorder).frame(width: 140)
                    Button("Réessayer avec ce plancher") { Task { await flow.retry(.set) } }.disabled(flow.newFloorText.trimmingCharacters(in: .whitespaces).isEmpty)
                    Spacer()
                    if flow.busy != nil { ProgressView().controlSize(.small) }
                }
                HStack { secondary; Spacer() }
            }.disabled(!model.canOperate || flow.busy != nil)
        case .done, .stopped:
            HStack {
                Text(plan.isComplete ? "Toutes les étapes sont réglées." : "Parcours clos. Les fonds sont un solde ordinaire du portefeuille.").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Nouveau parcours") { flow.dismissFinished() }
            }
        default:
            Text("Action suivante inconnue de cette version de l’app : « \(plan.next.rawValue) ». Aucune action n’est proposée.").foregroundStyle(Theme.warning)
        }
    }

    @ViewBuilder private var secondary: some View {
        Button("Re-planifier depuis l’actif détenu") { Task { await flow.replan() } }
            .help("Remplace les étapes restantes par la meilleure route exécutable depuis l’actif actuellement détenu, vers la même arrivée.")
            .disabled(!model.canOperate || flow.busy != nil)
        Button("Arrêter ici", role: .destructive) { Task { await flow.stop() } }
            .help("Définitif. Une demande d’approbation inutilisée est retirée ; les fonds restent où ils sont.")
            .disabled(!model.canOperate || flow.busy != nil)
    }
}

private struct PlanLegRow: View {
    let model: AppModel
    let plan: PlanView
    let leg: PlanView.Leg

    var body: some View {
        let current = leg.index == plan.current && plan.isOpen
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                icon
                Text("Étape \(leg.index + 1) — \(PlanText.kind(leg.kind))\((leg.label ?? leg.via).map { " · \($0)" } ?? "")\(leg.speed.map { " · \($0)" } ?? "")").fontWeight(.semibold)
                Spacer()
                Text(PlanText.legState(leg.state)).font(.callout).foregroundStyle(leg.isSettled ? Theme.positive : current ? Theme.warning : .secondary)
            }
            Text("\(PlanText.asset(leg.from)) → \(PlanText.asset(leg.to)) · \(SwapText.duration(leg.seconds))").font(.callout).foregroundStyle(.secondary)
            Text("Prévu : entrée \(Fmt.amount(leg.planned.expectedInDisplay, maxFraction: 8)) \(leg.from.symbol) → sortie \(Fmt.amount(leg.planned.expectedOutDisplay, maxFraction: 8)) \(leg.to.symbol) (minimum \(Fmt.amount(leg.planned.worstOutDisplay, maxFraction: 8)))")
                .font(.callout).monospacedDigit().fixedSize(horizontal: false, vertical: true)
            if leg.actual.inDisplay != nil || leg.actual.outDisplay != nil {
                HStack(spacing: 6) {
                    Text("Réel : entrée \(leg.actual.inDisplay.map { Fmt.amount($0, maxFraction: 8) } ?? "—") \(leg.from.symbol) → sortie \(leg.actual.outDisplay.map { Fmt.amount($0, maxFraction: 8) } ?? "pas encore lue") \(leg.to.symbol)").font(.callout).monospacedDigit().fontWeight(.medium)
                    if leg.isSettled { ProvenanceTag(p: .verified) }
                }
            }
            ForEach(Array(leg.attempts.enumerated()), id: \.offset) { n, a in
                if a.outcome != nil || a.error != nil {
                    Text("Tentative \(n + 1) : \(outcome(a.outcome))\(a.error.map { " — \($0)" } ?? "")\(a.at.map { " · \(Fmt.date($0))" } ?? "")").font(.caption)
                        .foregroundStyle(a.outcome == "settled" ? Color.secondary : Theme.warning).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let ex = leg.execution, leg.state == .proposed || leg.state == .inFlight || leg.isSettled { ExecutionTimeline(model: model, status: ex).padding(.top, 2) }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(current ? Theme.accent.opacity(0.06) : Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private var icon: some View {
        switch leg.state {
        case .settled: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.positive)
        case .inFlight: Image(systemName: "paperplane.circle.fill").foregroundStyle(Theme.warning)
        case .proposed: Image(systemName: "touchid").foregroundStyle(Theme.warning)
        case .ready: Image(systemName: "circle.dotted").foregroundStyle(Theme.accent)
        default: Image(systemName: "circle").foregroundStyle(.tertiary)
        }
    }
    private func outcome(_ o: String?) -> String {
        switch o { case "settled": "réglée"; case "failed": "échouée"; case "rejected": "rejetée"; case "expired": "expirée ou retirée"; case "refunded": "remboursée"; case nil: "en cours"; case let x?: x }
    }
}

private struct PlanLegReviewSheet: View {
    let model: AppModel
    let flow: PlanFlow
    let plan: PlanView
    let operation: ApprovableOperation

    var body: some View {
        OperationReviewSheet(model: model, title: "Étape \(plan.current + 1) sur \(plan.legs.count) — vérifier et approuver", operation: operation, notices: notices,
                             extra: OperationReviewSheet.contextLines(model: model, operation: operation),
                             busy: flow.busy == .approving, error: flow.reviewError,
                             onReject: { Task { await flow.rejectLeg() } }, onApprove: { Task { await flow.approveLeg() } })
    }

    private var notices: [(Banner.Kind, String)] {
        var out: [(Banner.Kind, String)] = [(.info, "Cette approbation ne couvre QUE cette étape du parcours. L’app a vérifié qu’elle correspond à l’étape affichée (même parcours, même position, mêmes actifs et réseaux), que son montant ne dépasse pas ce que le parcours détient, et que les deux extrémités sont des adresses de ce portefeuille. Une étape de parcours n’a pas de cotation de référence : le minimum garanti est celui affiché ci-dessous.")]
        if let a = OperationReviewSheet.spendApproval(operation.intent, model: model) { out.append(a) }
        if operation.intent.kind == .xswap { out.append((.info, "Le signataire isolé exige l’unanimité d’au moins trois opérateurs THORNode sur le coffre : sinon il refuse de signer (échec fermé) et le parcours se met en pause.")) }
        if operation.intent.kind == .bridge { out.append((.info, "Cette approbation couvre la destruction sur la source et la première émission sur la destination ; l’étape n’est réglée qu’une fois l’émission confirmée.")) }
        return out
    }
}

private struct RecentPlansCard: View {
    let plans: [PlanView]
    var body: some View {
        Card("Parcours précédents") {
            ForEach(plans) { p in
                HStack {
                    Text("\(Fmt.amount(p.amountInDisplay, maxFraction: 8)) \(p.from.symbol) (\(p.from.networkName ?? p.from.network)) → \(p.to.symbol) (\(p.to.networkName ?? p.to.network))")
                    Spacer()
                    Text(p.isComplete ? "Terminé — reçu \(p.receivedDisplay.map { Fmt.amount($0, maxFraction: 8) } ?? "—") \(p.to.symbol)" : PlanText.planState(p)).foregroundStyle(p.isComplete ? Theme.positive : .secondary)
                    Text(Fmt.date(p.updatedAt ?? p.createdAt)).foregroundStyle(.secondary).monospacedDigit()
                }.font(.callout)
            }
        }
    }
}
