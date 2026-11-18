// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/Bridge/BridgeView.swift
// Description: The cross-network USDC bridge (Circle CCTP): source and destination among the networks the server enables, both speeds with their fee ceiling and expected time, the review of the verified burn, then the two legs — burn on the source, Circle's attestation, mint on the destination — each with its own transaction id. A transfer is shown as received ONLY when the destination mint is confirmed. Interrupted transfers are listed on load with their real phase and the actions the server offers.
import SwiftUI
import SPWalletCore

struct BridgeView: View {
    let model: AppModel
    @State private var flow: BridgeFlow?

    var body: some View {
        Page("Pont inter-chaînes", subtitle: "USDC d’un réseau à l’autre par Circle CCTP : destruction sur la source, attestation de Circle, émission sur la destination — toujours de ce portefeuille à lui-même.") {
            if let flow {
                if !model.canOperate { Banner(.warning, "Transfert impossible pour l’instant : session ou portefeuille indisponible.") }
                if SwapText.isSimulatedServer(model) { Banner(.warning, "SERVEUR DE TEST : les transactions sont signées mais ne sont PAS diffusées. Aucun transfert réel n’aura lieu depuis ce serveur.") }
                if model.portfolio?.value.halted == true { Banner(.danger, "Arrêt d’urgence actif : le signataire ne signe plus rien.") }
                if let e = flow.loadError { Banner(.danger, "Capacités du pont illisibles : \(e)") }
                if let info = flow.info, !info.enabled { Banner(.warning, "Le serveur indique que le pont CCTP est désactivé.") }
                if flow.step == .tracking, let t = flow.tracker {
                    BridgeTrackingCard(model: model, flow: flow, tracker: t)
                } else {
                    BridgeRecoveryCard(model: model, flow: flow)
                    if flow.info != nil {
                        BridgeFormCard(model: model, flow: flow)
                        BridgeQuoteCard(model: model, flow: flow)
                    } else if flow.loadError == nil { ProgressView("Lecture des réseaux du pont…") }
                }
            } else { ProgressView() }
        }
        .task {
            if flow == nil { flow = BridgeFlow(model: model) }
            if flow?.info == nil { await flow?.load() }
        }
        .task(id: flow?.quoteKey) { await flow?.runQuote() }
        .task(id: flow?.tracker?.proposal.id) { await flow?.tracker?.follow() }
        .sheet(isPresented: Binding(get: { flow?.step == .review || flow?.step == .approving }, set: { _ in })) {
            if let flow, let op = flow.operation { BridgeReviewSheet(model: model, flow: flow, operation: op) }
        }
        .sheet(isPresented: Binding(get: { flow?.followUp != nil }, set: { _ in })) {
            if let flow, let f = flow.followUp { BridgeFollowUpSheet(model: model, flow: flow, followUp: f) }
        }
    }
}

// MARK: - Recovery

private struct BridgeRecoveryCard: View {
    let model: AppModel
    let flow: BridgeFlow

    var body: some View {
        let rows = flow.recoverable
        if !rows.isEmpty {
            Card("Transferts en cours ou à reprendre (\(rows.count))", trailing: model.activity.map { AnyView(ProvenanceTag(p: $0.fromCache ? .stale : .verified, text: $0.fromCache ? "Activité du \(Fmt.date($0.fetchedAt))" : "Activité lue \(Fmt.relative($0.fetchedAt))")) }) {
                Text("Un transfert brûlé mais pas encore émis n’est pas perdu : les USDC restent réclamables sur la destination. Ouvrez-le pour voir sa phase réelle et les actions offertes par le serveur.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                ForEach(rows.prefix(25)) { r in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Fmt.amount(r.item.amountDisplay, maxFraction: 6)) \(r.item.symbol) · \(r.item.networkName ?? r.item.network) → \(r.section.map { $0.toNetworkName ?? $0.toNetwork } ?? "?")").fontWeight(.medium)
                            Text(status(r)).font(.callout).foregroundStyle(statusColor(r)).fixedSize(horizontal: false, vertical: true)
                            Text(Fmt.date(r.item.at)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if flow.opening == r.id { ProgressView().controlSize(.small) }
                        Button("Ouvrir") { Task { await flow.open(r) } }.disabled(flow.opening != nil || model.phase != .signedIn)
                    }
                    .padding(.vertical, 3)
                    Divider()
                }
                if rows.count > 25 { Text("\(rows.count - 25) autres dans « Activité ».").font(.caption).foregroundStyle(.secondary) }
                if let e = flow.openError { Banner(.danger, e) }
            }
        }
    }

    private func status(_ r: BridgeFlow.Recoverable) -> String {
        guard let b = r.section else { return "État illisible par cette version de l’app" }
        if b.isComplete, let s = b.sol?.reclaimState { return "Reçu sur la destination · dépôt Solana : \(BridgeText.reclaim(s))" }
        var s = SwapText.bridgeStage(b.stage)
        if b.needsPasskey == true { s += " — action requise" }
        else if let h = b.hold { s += " — en attente (\(h))" }
        return s
    }
    private func statusColor(_ r: BridgeFlow.Recoverable) -> Color {
        guard let b = r.section else { return Theme.warning }
        return b.needsPasskey == true || b.hold != nil ? Theme.warning : .secondary
    }
}

@MainActor enum BridgeText {
    static func reclaim(_ s: ReclaimState) -> String {
        switch s {
        case .pending: "la destruction n’est pas encore minée"
        case .locked: "verrouillé (fenêtre de cinq jours du programme)"
        case .available: "récupérable maintenant"
        case .sent: "récupération diffusée, non confirmée"
        case .done: "récupéré"
        case .failed: "dernière tentative échouée — le dépôt est toujours là"
        default: s.rawValue
        }
    }
    static func speed(_ s: BridgeSpeed?) -> String {
        switch s { case .some(.standard): "Standard"; case .some(.fast): "Rapide (Fast Transfer)"; case .some(let o): o.rawValue; case nil: "—" }
    }
}

// MARK: - Form and quote

private struct BridgeFormCard: View {
    let model: AppModel
    @Bindable var flow: BridgeFlow

    var body: some View {
        Card("Transfert") {
            Form {
                NetworkPicker(networks: flow.networks, selection: $flow.fromNetwork, label: "Réseau source")
                NetworkPicker(networks: flow.networks.filter { $0.id != flow.fromNetwork }, selection: $flow.toNetwork, label: "Réseau de destination")
                LabeledContent("Actif") {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(flow.info?.asset ?? "USDC") (émis par Circle) — seul actif de ce pont")
                        if let u = flow.usdc(on: flow.fromNetwork) { Text(u.id).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled) }
                    }
                }
                LabeledContent("Solde USDC sur la source") {
                    if let b = flow.sourceBalance, b.isAvailable { Text(model.settings.hideBalances ? "••••" : "\(Fmt.amount(b.display)) \(b.symbol)").monospacedDigit() }
                    else if flow.sourceBalance != nil { Text("Indisponible (lecture de chaîne en échec)").foregroundStyle(Theme.negative) }
                    else { Text("—") }
                }
                HStack {
                    TextField("Montant", text: $flow.amount, prompt: Text("0.0"))
                    Text("USDC").foregroundStyle(.secondary)
                    Button("Max") { flow.setMax() }.disabled(flow.sourceBalance?.isAvailable != true)
                }
                LabeledContent("Destinataire") {
                    Text(model.address(on: flow.toNetwork) ?? "adresse de ce portefeuille sur la destination").font(Theme.monoSmall).textSelection(.enabled)
                }
            }
            .formStyle(.grouped).scrollDisabled(true).disabled(flow.step != .form)
            HStack {
                Button { flow.flip() } label: { Label("Inverser les réseaux", systemImage: "arrow.up.arrow.down") }.disabled(flow.step != .form)
                Spacer()
                if let p = flow.formProblem, !flow.amount.isEmpty { Text(p).font(.callout).foregroundStyle(Theme.warning) }
            }
            Text("Le destinataire est toujours l’adresse de ce portefeuille sur le réseau de destination : le serveur et l’app refusent tout autre bénéficiaire.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct BridgeQuoteCard: View {
    let model: AppModel
    @Bindable var flow: BridgeFlow

    var body: some View {
        switch flow.quotePhase {
        case .idle: EmptyView()
        case .loading: Card("Devis") { HStack { ProgressView().controlSize(.small); Text("Lecture des frais de Circle et des frais de réseau…").foregroundStyle(.secondary) } }
        case .failed(let m):
            Card("Devis") { Banner(.danger, m); HStack { Spacer(); Button("Réessayer") { flow.refreshQuote() } } }
        case .done:
            if let q = flow.quote { quoteCard(q) }
        }
    }

    @ViewBuilder private func quoteCard(_ q: BridgeQuote) -> some View {
        Card("Devis — \(q.fromName ?? q.from) → \(q.toName ?? q.to)", trailing: AnyView(HStack(spacing: 8) {
            if let at = flow.quotedAt { Text("Lu \(Fmt.relative(at))").font(.caption).foregroundStyle(.secondary) }
            Button("Rafraîchir") { flow.refreshQuote() }.controlSize(.small).disabled(flow.step != .form)
        })) {
            Text("Route : destruction (burn) des USDC sur \(q.fromName ?? q.from) → attestation par Circle → émission (mint) sur \(q.toName ?? q.to). Une seule approbation par passkey couvre la destruction et la première émission.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(q.options, id: \.speed) { o in optionRow(o) }
            Divider()
            Field(label: "Frais d’émission (destination)", value: "≈ \(Fmt.amount(q.destinationGas.needDisplay, maxFraction: 8)) \(q.destinationGas.symbol) requis · le portefeuille détient \(Fmt.amount(q.destinationGas.balanceDisplay, maxFraction: 8)) \(q.destinationGas.symbol)")
            if !q.destinationGas.enough { Banner(.danger, "Pas assez de \(q.destinationGas.symbol) sur \(q.toName ?? q.to) pour payer l’émission. Le serveur refuse de brûler quoi que ce soit tant que la destination ne peut pas recevoir.") }
            if let s = q.solana { solana(s, q) }
            if let e = flow.error { Banner(.danger, e) }
            HStack {
                if let p = flow.prepareProblem, flow.formProblem == nil { Text(p).font(.callout).foregroundStyle(Theme.warning).fixedSize(horizontal: false, vertical: true) }
                Spacer()
                if flow.step == .preparing { ProgressView().controlSize(.small); Text("Contrats, frais, simulation, limites du signataire…").font(.callout).foregroundStyle(.secondary) }
                Button(SwapText.isSimulatedServer(model) ? "Préparer et vérifier (serveur de test)…" : "Préparer et vérifier…") { Task { await flow.prepare() } }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(flow.prepareProblem != nil || !model.canOperate || flow.step != .form)
            }
            Text("Préparer ne signe rien et ne brûle rien : le serveur vérifie le code des contrats de Circle, simule la destruction et contrôle les limites du signataire ; l’app vérifie ensuite que le défi de la passkey est l’empreinte du transfert affiché.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func optionRow(_ o: BridgeQuote.Option) -> some View {
        let selected = flow.speed == o.speed
        return Button { flow.speed = o.speed } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle").foregroundStyle(selected ? Theme.accent : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    HStack { Text(BridgeText.speed(o.speed)).fontWeight(.semibold); if !o.available { ProvenanceTag(p: .unavailable, text: "Indisponible maintenant") } }
                    Text("Frais Circle (plafond) : \(Fmt.amount(o.feeDisplay)) USDC  ·  Minimum reçu : \(Fmt.amount(o.minReceiveDisplay)) USDC  ·  Durée attendue : \(SwapText.duration(o.seconds))").font(.callout).monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                    if !o.available { Text(o.quote == nil ? "Le montant ne couvre pas ces frais." : "Circle n’offre pas cette vitesse pour ce montant en ce moment (frais ou allocation Fast).").font(.caption).foregroundStyle(Theme.warning) }
                }
                Spacer()
            }
            .padding(10).background(selected ? Theme.accent.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Theme.accent.opacity(0.5) : Theme.stroke.opacity(0.5)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(flow.step != .form)
        .accessibilityLabel("Vitesse \(BridgeText.speed(o.speed))\(selected ? ", sélectionnée" : "")")
    }

    @ViewBuilder private func solana(_ s: BridgeQuote.Solana, _ q: BridgeQuote) -> some View {
        Divider()
        if s.role == "source" {
            Field(label: "Dépôt Solana (remboursable)", value: "\(Fmt.amount(s.depositDisplay, maxFraction: 9)) \(s.symbol ?? "SOL") — loyer du compte d’événement créé par la destruction ; récupérable après \(s.reclaimAfterSeconds.map { "\($0 / 86400) jours" } ?? "le délai du programme"), par une transaction approuvée par passkey.")
            if let f = s.networkFeeDisplay { Field(label: "Frais de réseau Solana", value: "≈ \(Fmt.amount(f, maxFraction: 9)) \(s.symbol ?? "SOL")") }
        } else {
            if let r = s.recipient { Field(label: "Bénéficiaire (Solana)", value: r, mono: true) }
            if let t = s.tokenAccount { Field(label: "Compte de jetons USDC", value: t + (s.tokenAccountExists == true ? "  — existe" : s.tokenAccountExists == false ? "  — N’EXISTE PAS ENCORE" : ""), mono: true) }
            if let r = s.nonceRentDisplay { Field(label: "Loyer du compte de nonce", value: "\(Fmt.amount(r, maxFraction: 9)) \(s.symbol ?? "SOL") (payé par l’émission)") }
            if s.tokenAccountExists == false { tokenAccount(s) }
        }
    }

    @ViewBuilder private func tokenAccount(_ s: BridgeQuote.Solana) -> some View {
        Banner(.warning, "Le compte de jetons USDC de ce portefeuille n’existe pas encore sur Solana. La destruction le nomme et ne peut pas être redirigée : il doit être ouvert AVANT (petite transaction approuvée par passkey, dépôt de loyer ≈ \(Fmt.amount(s.tokenAccountRentDisplay, maxFraction: 9)) \(s.symbol ?? "SOL")).")
        if let why = flow.unavailable[.tokenAccount] { Banner(.danger, "Ouverture indisponible : \(why)") }
        if let c = flow.tokenAccountCreation {
            Banner(c.sent ? .info : .warning, c.sent ? "Transaction d’ouverture diffusée (non confirmée) : \(c.txid). Rafraîchissez le devis dans quelques secondes pour constater l’existence du compte." : "Serveur de test : la transaction d’ouverture a été signée mais PAS diffusée. Le compte n’a pas été créé.")
            SafeLink(title: "Ouvrir dans l’explorateur de blocs", url: c.explorer)
        }
        HStack {
            Spacer()
            if flow.busyAction == .tokenAccount { ProgressView().controlSize(.small) }
            Button("Ouvrir le compte de jetons USDC…") { Task { await flow.beginTokenAccount() } }
                .disabled(!model.canOperate || flow.busyAction != nil || flow.unavailable[.tokenAccount] != nil)
        }
    }
}

// MARK: - Review of the burn

private struct BridgeReviewSheet: View {
    let model: AppModel
    let flow: BridgeFlow
    let operation: ApprovableOperation

    var body: some View {
        OperationReviewSheet(model: model, title: "Vérifier et approuver le transfert inter-chaînes", operation: operation, notices: notices, extra: extra,
                             busy: flow.step == .approving, error: flow.error,
                             onReject: { Task { await flow.reject() } }, onApprove: { Task { await flow.approve() } })
    }

    private var notices: [(Banner.Kind, String)] {
        var out: [(Banner.Kind, String)] = [(.info, "Cette approbation couvre la destruction des USDC sur la source ET la première émission sur la destination. Après la destruction, le transfert ne peut plus être annulé ; il n’est terminé que lorsque l’émission est confirmée sur la destination.")]
        if let a = OperationReviewSheet.spendApproval(operation.intent, model: model) { out.append(a) }
        return out
    }

    private var extra: [ReviewLine] { OperationReviewSheet.contextLines(model: model, operation: operation) }
}

// MARK: - Follow-up approvals (objects that are not intents)

private struct BridgeFollowUpSheet: View {
    let model: AppModel
    let flow: BridgeFlow
    let followUp: BridgeFlow.FollowUp

    var body: some View {
        let simulated = SwapText.isSimulatedServer(model)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.title2.weight(.semibold))
                Spacer()
                if simulated { ProvenanceTag(p: .simulated, text: "Serveur de test : signé, non diffusé") }
            }.padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Banner(.info, explanation)
                    ReviewLines(lines: lines)
                    BindingProof(digest: digest, expiry: expiry)
                }.padding(20)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if let e = flow.followUpError { Banner(.danger, e) }
                HStack {
                    Button("Annuler") { flow.cancelFollowUp() }.disabled(flow.followUpBusy)
                    Spacer()
                    if flow.followUpBusy { ProgressView().controlSize(.small); Text("Passkey, puis signature isolée…").foregroundStyle(.secondary) }
                    Button { Task { await flow.confirmFollowUp() } } label: { Label(simulated ? "Approuver (test : ne sera pas diffusé)" : "Approuver avec la passkey", systemImage: "touchid") }
                        .buttonStyle(.borderedProminent).controlSize(.large).disabled(flow.followUpBusy || !model.canOperate)
                }
            }.padding(16)
        }
        .frame(width: 720, height: 640)
        .interactiveDismissDisabled()
    }

    private var title: String {
        switch followUp {
        case .retryMint: "Signer de nouveau l’émission (mint)"
        case .reclaim: "Récupérer le dépôt du compte d’événement Solana"
        case .tokenAccount: "Ouvrir le compte de jetons USDC sur Solana"
        }
    }
    private var explanation: String {
        switch followUp {
        case .retryMint: "La première émission a échoué, a été remplacée ou a expiré. Les USDC brûlés attendent toujours : cette approbation signe une nouvelle transaction d’émission pour le même message attesté par Circle, avec les paramètres de frais ci-dessous. Une émission renvoyée n’est pas une émission reçue."
        case .reclaim: "La destruction faite sur Solana a créé un compte d’événement dont le loyer vous revient cinq jours plus tard. Cette approbation signe la transaction qui ferme ce compte et rend le dépôt à ce portefeuille."
        case .tokenAccount: "Cette approbation signe une transaction Solana qui ouvre le compte de jetons USDC de ce portefeuille (dépôt de loyer). Elle ne déplace aucun USDC."
        }
    }
    private var digest: Data {
        switch followUp { case .retryMint(let a): a.approval.digest; case .reclaim(let a): a.approval.digest; case .tokenAccount(let a): a.approval.digest }
    }
    private var expiry: Date? { if case .tokenAccount(let a) = followUp { a.request.expiry } else { nil } }

    private func budget(_ b: SolanaBudget) -> [ReviewLine] {
        let sol = model.network("solana")?.native
        return [
            .init(label: "Blockhash récent", value: b.recentBlockhash, style: .address),
            .init(label: "Valide jusqu’au bloc", value: String(b.lastValidBlockHeight)),
            .init(label: "Budget de calcul", value: "\(b.computeUnitLimit) CU à \(b.computeUnitPrice) µlamports/CU"),
            .init(label: "Frais de réseau", value: b.singleSignerNetworkFee.map { "\(SwapText.units($0.description, decimals: sol?.decimals)) \(sol?.symbol ?? "SOL")" } ?? "non calculable", style: .strong),
        ]
    }

    /// Only fields of the object whose hash is the challenge, plus served figures the Core checked against it.
    private var lines: [ReviewLine] {
        let sol = model.network("solana")?.native
        switch followUp {
        case .retryMint(let a):
            let o = a.object
            let dest = (try? a.proposal.bridgeSection())?.toNetwork
            var out: [ReviewLine] = [
                .init(label: "Opération", value: "Nouvelle signature de l’émission CCTP", style: .strong),
                .init(label: "Transfert", value: o.proposalId),
                .init(label: "Message attesté (empreinte)", value: o.messageHash, style: .address),
                .init(label: "Réseau de destination", value: dest.map { model.network($0)?.name ?? $0 } ?? "—"),
                .init(label: "Montant du transfert", value: "\(Fmt.amount(a.proposal.amountDisplay)) \(a.proposal.symbol) (inchangé : fixé par le message attesté)"),
            ]
            switch o.parameters {
            case .evm(let g):
                let native = dest.flatMap { model.network($0)?.native }
                out.append(.init(label: "Paramètres EVM", value: "nonce \(g.nonce) · gaz \(g.gasLimit) · max \(g.maxFeePerGas) wei/gaz · priorité \(g.maxPriorityFeePerGas)"))
                out.append(.init(label: "Frais de réseau maximum", value: "\(SwapText.units(g.maxNetworkFee, decimals: native?.decimals)) \(native?.symbol ?? "")", style: .strong))
            case .solana(let b): out += budget(b)
            }
            return out
        case .reclaim(let a):
            let o = a.object
            return [
                .init(label: "Opération", value: "Fermeture du compte d’événement CCTP et retour du dépôt", style: .strong),
                .init(label: "Transfert", value: o.proposalId),
                .init(label: "Compte d’événement", value: o.eventAccount, style: .address),
                .init(label: "Message attesté (empreinte)", value: o.messageHash, style: .address),
                .init(label: "Dépôt rendu", value: "\(SwapText.units(a.deposit, decimals: sol?.decimals)) \(sol?.symbol ?? "SOL") (lu sur la chaîne par le serveur)", style: .strong),
                .init(label: "Bénéficiaire", value: model.address(on: "solana") ?? "adresse Solana de ce portefeuille", style: .address),
            ] + budget(o.budget)
        case .tokenAccount(let a):
            let q = a.request
            return [
                .init(label: "Opération", value: "Création du compte de jetons USDC (compte associé)", style: .strong),
                .init(label: "Réseau", value: "\(model.network(q.network)?.name ?? q.network)  (\(q.network), \(q.chainRef))"),
                .init(label: "Propriétaire", value: q.owner, style: .address),
                .init(label: "Jeton (mint USDC)", value: q.mint, style: .address),
                .init(label: "Compte de jetons créé", value: q.tokenAccount, style: .address),
                .init(label: "Dépôt de loyer", value: "\(SwapText.units(a.rent, decimals: sol?.decimals)) \(sol?.symbol ?? "SOL")"),
                .init(label: "Plafond total (loyer + frais)", value: "\(SwapText.units(q.maxFee, decimals: sol?.decimals)) \(sol?.symbol ?? "SOL")", style: .strong),
            ] + budget(q.budget) + [
                .init(label: "Clé du portefeuille", value: q.keyId),
                .init(label: "Politique du signataire", value: "version \(q.policyVersion)"),
                .init(label: "Demande", value: q.requestId),
            ]
        }
    }
}

// MARK: - Tracking: the two legs

private struct BridgeTrackingCard: View {
    let model: AppModel
    let flow: BridgeFlow
    let tracker: OperationTracker

    var body: some View {
        let p = tracker.proposal
        Card("Suivi du transfert inter-chaînes", trailing: SwapText.isSimulatedServer(model) ? AnyView(ProvenanceTag(p: .simulated, text: "Serveur de test")) : nil) {
            OperationHeadline(proposal: p, completion: tracker.completion)
            if let b = try? p.bridgeSection() { content(p, b) }
            else { Banner(.warning, "La section « pont » de cette opération est illisible par cette version de l’app : aucun état n’est déduit et aucune action n’est proposée.") }
            if let e = p.error { Banner(p.state.isFailure || p.state == .notBroadcast ? .danger : .warning, e) }
            if let e = tracker.readError { Banner(.warning, "Dernière lecture de l’état en échec : \(e)") }
            if let e = flow.error { Banner(.danger, e) }
            if let ex = try? p.executionStatus() { Divider(); ExecutionTimeline(model: model, status: ex) }
            Divider()
            StateHistory(history: tracker.history)
            HStack { Spacer(); Button(tracker.isSettled ? "Fermer" : "Fermer (le transfert reste listé ici et dans Activité)") { flow.closeTracking() } }
        }
    }

    @ViewBuilder private func content(_ p: Proposal, _ b: BridgeSection) -> some View {
        Field(label: "Étape", value: SwapText.bridgeStage(b.stage), emphasis: true)
        Field(label: "Route", value: "\(p.networkName ?? p.network) → \(b.toNetworkName ?? b.toNetwork) · Circle CCTP · \(BridgeText.speed(b.speed)) (\(SwapText.duration(b.expectedSeconds)))")
        Field(label: "Montant brûlé", value: "\(Fmt.amount(p.amountDisplay)) \(p.symbol)")
        Field(label: "Frais Circle", value: "plafond approuvé \(Fmt.amount(b.cctpMaxFeeDisplay)) \(p.symbol)" + (b.feeExecutedDisplay.map { " · prélevés \(Fmt.amount($0)) \(p.symbol)" } ?? " · montant prélevé pas encore connu"))
        Field(label: "Minimum reçu", value: "\(Fmt.amount(b.minReceiveDisplay)) \(p.symbol)")
        if let r = b.receivedDisplay, b.isComplete {
            HStack { Field(label: "Reçu sur la destination", value: "\(Fmt.amount(r)) \(p.symbol)", emphasis: true); ProvenanceTag(p: .verified) }
        } else {
            Field(label: "Reçu sur la destination", value: "— (pas encore : l’émission n’est pas confirmée)")
        }
        if let h = b.hold { Banner(.warning, SwapText.hold(h) + (b.holdDetail.map { "\nServeur : \($0)" } ?? "")) }

        Divider()
        Text("Jambe 1 — destruction sur \(p.networkName ?? p.network)").font(.headline)
        if b.needsApproval == true || b.approvalTxid != nil {
            TxField(label: "Autorisation ERC-20", txid: b.approvalTxid ?? "(pas encore diffusée)", state: b.approvalState.map { $0 == "confirmed" ? "confirmée" : $0 == "sent" ? "diffusée, non confirmée" : "en attente" })
        }
        if p.txid != nil { TxField(label: "Transaction de destruction", txid: p.txid, explorer: p.explorer, state: ErrorText.state(p.state)) }
        else { Field(label: "Transaction de destruction", value: "— (\(ErrorText.state(p.state)))") }
        if let c = p.confirmations, p.txid != nil { Field(label: "Confirmations", value: String(c)) }

        Text("Attestation de Circle").font(.headline)
        Field(label: "État", value: (b.attested == true ? "Reçue et conforme au transfert approuvé" : "Pas encore reçue") + (b.irisStatus.map { " · Circle : \($0)" } ?? "") + (b.delayReason.map { " · \($0)" } ?? ""))

        Text("Jambe 2 — émission sur \(b.toNetworkName ?? b.toNetwork)").font(.headline)
        if let m = b.mintTxid {
            TxField(label: "Transaction d’émission", txid: m, explorer: b.mintExplorer, state: b.isComplete ? "confirmée" : b.stage == .mintFailed ? "échouée" : "diffusée, non confirmée")
            if b.mintedBy == "other" { Field(label: "Émise par", value: "un tiers (l’émission est ouverte à tous) — les USDC sont bien arrivés à ce portefeuille") }
        } else { Field(label: "Transaction d’émission", value: "— (aucune pour l’instant)") }

        actions(b)
        if let s = b.sol { Divider(); solana(s) }
    }

    @ViewBuilder private func actions(_ b: BridgeSection) -> some View {
        if b.needsPasskey == true {
            Banner(.warning, "L’émission doit être signée de nouveau : cela exige votre passkey sur un objet que l’app vérifie (transfert, message attesté, paramètres de frais).")
            if let why = flow.unavailable[.retryMint] { Banner(.danger, "Nouvelle signature indisponible : \(why)") }
            HStack {
                Spacer()
                if flow.busyAction == .retryMint { ProgressView().controlSize(.small) }
                Button("Préparer une nouvelle signature de l’émission…") { Task { await flow.beginRetryMint() } }
                    .buttonStyle(.borderedProminent).disabled(!model.canOperate || flow.busyAction != nil || flow.unavailable[.retryMint] != nil)
            }
        } else if b.canFinish == true {
            HStack {
                Text("« Terminer » demande au serveur d’exécuter l’étape suivante maintenant au lieu d’attendre son passage périodique. Aucune nouvelle signature : rien n’est signé au-delà de ce que l’approbation de la destruction couvrait.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer()
                if flow.busyAction == .finish { ProgressView().controlSize(.small) }
                Button("Terminer maintenant") { Task { await flow.finish() } }.disabled(!model.canOperate || flow.busyAction != nil)
            }
        }
    }

    @ViewBuilder private func solana(_ s: SolanaBridgeSection) -> some View {
        Text("Côté Solana").font(.headline)
        if s.role == "destination" {
            if let r = s.recipient { Field(label: "Bénéficiaire", value: r, mono: true) }
            if let t = s.tokenAccount { Field(label: "Compte de jetons crédité", value: t, mono: true) }
        } else {
            if let e = s.eventAccount { Field(label: "Compte d’événement", value: e, mono: true) }
            if let d = s.depositDisplay { Field(label: "Dépôt remboursable", value: "\(Fmt.amount(d, maxFraction: 9)) \(s.symbol ?? "SOL")") }
            if let st = s.reclaimState {
                Field(label: "Récupération du dépôt", value: BridgeText.reclaim(st), emphasis: true)
                if let at = s.reclaimableAt, !s.isReclaimed { Field(label: "Récupérable à partir du", value: Fmt.date(at) + (s.reclaimEstimated == true ? " (estimation : la destruction n’est pas encore minée ou le compte pas encore lu)" : "")) }
                if let e = s.reclaimError { Banner(.warning, "Dernière tentative : \(e)") }
                TxField(label: "Transaction de récupération", txid: s.reclaimTxid, explorer: s.reclaimExplorer, state: s.isReclaimed ? "confirmée" : "diffusée, non confirmée")
                if let r = s.reclaimedDisplay, s.isReclaimed { Field(label: "Récupéré", value: "\(Fmt.amount(r, maxFraction: 9)) \(s.symbol ?? "SOL")") }
                if let why = flow.unavailable[.reclaim] { Banner(.danger, "Récupération indisponible : \(why)") }
                if s.canReclaim {
                    HStack {
                        Spacer()
                        if flow.busyAction == .reclaim { ProgressView().controlSize(.small) }
                        Button("Récupérer le dépôt…") { Task { await flow.beginReclaim() } }
                            .buttonStyle(.borderedProminent).disabled(!model.canOperate || flow.busyAction != nil || flow.unavailable[.reclaim] != nil)
                    }
                } else if st == .locked || st == .pending {
                    Text("La récupération sera offerte ici une fois la fenêtre de cinq jours écoulée et la destruction attestée ; elle demandera votre passkey.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
