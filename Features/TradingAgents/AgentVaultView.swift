// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/TradingAgents/AgentVaultView.swift
// Description: The vault of a spot agent: its address and real on-chain balances, funding it (an ordinary wallet transfer to the vault address, through the same verified transfer approval as Send), bringing a whole balance back to the owner's own address (the only destination the signer signs for a vault), the funds the same address holds on other networks, and the honest tracking of each return until the chain confirms it.
import SwiftUI
import SPWalletCore

struct AgentVaultSection: View {
    let model: AppModel
    let d: AgentDetailStore
    @State private var fund: SendFlow?
    @State private var gas: AgentNetworks.Network?
    @State private var pendingReturn: PendingReturn?

    struct PendingReturn: Identifiable { let id = UUID(); let asset: String; let symbol: String; let amount: String; let network: String?; let networkName: String }

    var body: some View {
        if case .spot(let s)? = d.detail {
            let a = s.agent
            Card("Coffre de l’agent", trailing: AnyView(ProvenanceTag(p: s.vault == nil ? .unavailable : .verified))) {
                Field(label: "Adresse du coffre", value: a.vaultAddress, mono: true)
                Text(Fmt.chunked(a.vaultAddress)).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                HStack { Field(label: "Réseau", value: "\(a.networkName ?? a.network)\(a.vaultIndex.map { " · coffre n° \($0)" } ?? "")"); Button("Copier l’adresse") { copyToPasteboard(a.vaultAddress) } }
                Banner(.info, "Le coffre contient de l’argent RÉEL, quel que soit le mode de l’agent. Sa clé est chez le signataire isolé : sans mandat elle ne peut que renvoyer les fonds à votre propre adresse. N’envoyez au coffre que sur le réseau \(a.networkName ?? a.network).")
                Divider()
                if let v = s.vault {
                    if v.isEmpty { Text("Le coffre ne détient rien sur ce réseau.").foregroundStyle(.secondary) }
                    ForEach(v) { b in
                        HStack(spacing: 10) {
                            VaultBalanceRow(balance: b)
                            Button("Rapatrier…") { pendingReturn = PendingReturn(asset: b.asset, symbol: b.assetSymbol, amount: b.display, network: nil, networkName: a.networkName ?? a.network) }
                                .disabled(!model.canOperate || d.busy != nil || b.units?.isZero != false || a.mode == .live)
                                .help(a.mode == .live ? "Révoquez d’abord le mandat : le serveur refuse un retour tant que l’agent est en réel sur ce réseau." : "Renvoie TOUT le solde de cet actif à votre propre adresse.")
                        }
                    }
                    if let g = gas?.gas { Text("Réserve de gaz requise avant un passage en réel : \(g.reserve) \(gas?.native ?? "") (≈ \(g.perOrder) par ordre).").font(.caption).foregroundStyle(.secondary) }
                    if a.mode == .live { Text("Agent en réel : un retour vers vous exige d’abord la révocation du mandat (onglet Mandat et risques).").font(.caption).foregroundStyle(Theme.warning) }
                } else { Banner(.danger, "Soldes illisibles sur la chaîne pour l’instant. Ce n’est pas un coffre vide.") }
                if let n = d.notice { Banner(.info, n) }
                if let e = d.actionError { Banner(.danger, e) }
            }
            fundCard(a)
            returnsCard
            elsewhereCard(a)
        }
    }

    // MARK: funding — the wallet's ordinary transfer, to the vault address

    @ViewBuilder private func fundCard(_ a: Agent) -> some View {
        Card("Alimenter le coffre") {
            if let fund {
                if fund.step == .tracking {
                    TrackingCard(flow: fund)
                    Text("Le dépôt n’est acquis qu’à l’état « Finalisée ». Les soldes du coffre ci-dessus sont relus sur la chaîne.").font(.caption).foregroundStyle(.secondary)
                } else {
                    @Bindable var fund = fund
                    let net = model.network(a.network)
                    Form {
                        LabeledContent("Depuis") { Text(model.address(on: a.network) ?? "adresse inconnue").font(Theme.monoSmall).textSelection(.enabled) }
                        LabeledContent("Vers (coffre)") { Text(a.vaultAddress).font(Theme.monoSmall).textSelection(.enabled) }
                        LabeledContent("Réseau") { Text(net?.name ?? a.network) }
                        Picker("Actif", selection: $fund.asset) {
                            ForEach(fundable(a, net), id: \.id) { x in Text("\(x.symbol) — \(x.role)").tag(x.id) }
                        }
                        LabeledContent("Solde disponible du portefeuille") {
                            if let b = fund.balance, b.isAvailable { Text("\(Fmt.amount(b.display)) \(b.symbol)").monospacedDigit() } else { Text("Indisponible").foregroundStyle(Theme.negative) }
                        }
                        HStack { TextField("Montant", text: $fund.amount, prompt: Text("0.0")); Text(fund.assetDef?.symbol ?? "").foregroundStyle(.secondary) }
                    }.formStyle(.grouped).scrollDisabled(true).disabled(fund.step != .form)
                    if net == nil { Banner(.danger, "Le réseau \(a.network) n’est pas dans le registre de ce portefeuille : le dépôt ne peut pas être préparé ici.") }
                    if let e = fund.error { Banner(.danger, e) }
                    HStack {
                        if let p = fund.formProblem, !fund.amount.isEmpty { Text(p).font(.callout).foregroundStyle(.secondary) }
                        Spacer()
                        if fund.step == .preparing { ProgressView().controlSize(.small); Text("Validation, simulation et calcul des frais…").font(.callout).foregroundStyle(.secondary) }
                        Button("Préparer et vérifier le dépôt…") { Task { await fund.prepare() } }.buttonStyle(.borderedProminent).disabled(fund.formProblem != nil || !model.canOperate || fund.step != .form || net == nil)
                    }
                    Text("C’est un transfert ordinaire de votre portefeuille vers l’adresse du coffre, approuvé par votre passkey sur l’écran suivant. Déposer n’autorise aucun échange : seul un mandat le peut. Ce que vous déposez devient le budget que l’agent pourra engager s’il reçoit un mandat.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            } else { ProgressView() }
        }
        .task {
            if fund == nil { let f = SendFlow(model: model); f.network = a.network; f.asset = a.holdings?.first(where: \.isCash)?.asset ?? "native"; f.to = a.vaultAddress; fund = f }
            if gas == nil { gas = try? await d.api.networks().networks.first { $0.id == a.network } }
        }
        .onChange(of: fund?.step) { old, new in
            // a new deposit always targets this vault; a finished one refreshes the balances read on-chain
            if new == .form, let f = fund { f.network = a.network; f.to = a.vaultAddress }
            if old == .approving || new == .tracking { Task { await d.refresh() } }
        }
        .onChange(of: fund?.tracked?.state) { _, s in if s?.isTerminal == true { Task { await d.refresh() } } }
        .sheet(isPresented: Binding(get: { fund?.step == .review || fund?.step == .approving }, set: { _ in })) {
            if let fund, let ap = fund.approval { FundReviewSheet(model: model, flow: fund, approval: ap, agent: a) }
        }
    }

    private func fundable(_ a: Agent, _ net: SPWalletCore.Network?) -> [(id: String, symbol: String, role: String)] {
        var out: [(String, String, String)] = []
        for h in a.holdings ?? [] where net?.asset(h.asset) != nil { out.append((h.asset, h.assetSymbol, h.isCash ? "monnaie de règlement" : "actif négocié")) }
        if !out.contains(where: { $0.0 == "native" }), let n = net { out.append(("native", n.native.symbol, "gaz (frais de transaction du coffre)")) }
        return out
    }

    // MARK: returns to the owner

    @ViewBuilder private var returnsCard: some View {
        Card("Retours vers votre adresse") {
            if let r = d.returns {
                if r.broadcast == false { Banner(.warning, "Ce serveur signe mais ne diffuse pas les transactions : un retour s’y termine « signé, NON diffusé » et rien ne bouge sur la chaîne.") }
                if r.withdrawals.isEmpty { Text("Aucun retour demandé.").foregroundStyle(.secondary) }
                ForEach(r.withdrawals) { w in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Group {
                                if w.isSettled { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.positive) }
                                else if w.state == .failed || w.state == .notSent { Image(systemName: "xmark.octagon.fill").foregroundStyle(Theme.negative) }
                                else if w.state.isOpen { ProgressView().controlSize(.small) }
                                else { Image(systemName: "questionmark.circle").foregroundStyle(Theme.warning) }
                            }
                            Text("\(Fmt.amount(w.amount, maxFraction: 8)) \(w.symbol)").fontWeight(.medium).monospacedDigit()
                            Text(AgentText.returnState(w.state) + (w.state == .confirmed && !w.arrived ? " — paiement vers vous NON vu dans la transaction" : w.isSettled ? " — reçu à votre adresse" : "")).foregroundStyle(w.isSettled ? Theme.positive : w.state.isOpen ? Theme.warning : Theme.negative)
                            Spacer()
                            Text(Fmt.date(w.createdAt)).font(.caption).foregroundStyle(.secondary)
                        }
                        if let n = w.network { Text("Réseau : \(model.network(n)?.name ?? n)").font(.caption).foregroundStyle(.secondary) }
                        if let tx = w.txid { Text(tx).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled) }
                        if let e = w.error { Text(e).font(.caption).foregroundStyle(Theme.negative).textSelection(.enabled) }
                        if let url = AgentText.https(w.explorer) { Link("Ouvrir dans l’explorateur de blocs", destination: url).font(.caption) }
                    }
                    Divider()
                }
                Text("« Diffusé » n’est pas « confirmé » : un retour n’est acquis que lorsque la chaîne l’a confirmé ET que le paiement vers votre adresse y a été vu.").font(.caption).foregroundStyle(.secondary)
            } else { Unavailable(what: "Retours", error: d.error("returns")) }
        }
        .confirmationDialog("Rapatrier \(pendingReturn.map { "\(Fmt.amount($0.amount, maxFraction: 8)) \($0.symbol)" } ?? "") ?", isPresented: Binding(get: { pendingReturn != nil }, set: { if !$0 { pendingReturn = nil } }), titleVisibility: .visible, presenting: pendingReturn) { p in
            Button("Rapatrier tout le solde vers mon adresse") { Task { await d.returnToOwner(asset: p.asset, network: p.network) } }
            Button("Annuler", role: .cancel) {}
        } message: { p in
            Text("TOUT le solde de \(p.symbol) du coffre sur \(p.networkName) est envoyé à votre propre adresse de ce portefeuille (\(model.address(on: p.network ?? d.agent?.network ?? "") ?? "déterminée par le signataire")). Il n’y a ni montant ni destination à choisir : le signataire ne signe un paiement de coffre que vers son propriétaire. Aucune passkey n’est demandée. Les frais de réseau sont payés par le gaz du coffre.")
        }
    }

    // MARK: funds on other networks

    @ViewBuilder private func elsewhereCard(_ a: Agent) -> some View {
        Card("Fonds sur d’autres réseaux (même adresse)") {
            if let e = d.elsewhere {
                if e.holdings.isEmpty { Text("Rien n’a été trouvé à l’adresse du coffre sur les autres réseaux EVM consultés.").foregroundStyle(.secondary) }
                else {
                    Banner(.warning, "Des fonds ont été envoyés à l’adresse du coffre sur un autre réseau que celui de l’agent. L’agent ne peut pas les négocier ; vous pouvez les rapatrier vers votre adresse.")
                    ForEach(e.holdings) { h in
                        HStack(spacing: 10) {
                            AssetBadge(symbol: h.symbol, size: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(Fmt.amount(h.display, maxFraction: 8)) \(h.symbol) — \(h.networkName)").fontWeight(.medium)
                                Text(h.gasEnough == false || !h.hasGas ? "Gaz insuffisant sur ce réseau : \(h.gasHeld ?? "0") \(h.gas) détenus\(h.gasNeed.map { ", environ \($0) requis" } ?? ""). Envoyez d’abord un peu de \(h.gas) à l’adresse du coffre sur ce réseau." : "Gaz : \(h.gasHeld ?? "?") \(h.gas)\(h.gasNeed.map { " (besoin ≈ \($0))" } ?? "")")
                                    .font(.caption).foregroundStyle(h.gasEnough == false || !h.hasGas ? Theme.warning : .secondary).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Button("Rapatrier…") { pendingReturn = PendingReturn(asset: h.asset, symbol: h.symbol, amount: h.display, network: h.network, networkName: h.networkName) }
                                .disabled(!model.canOperate || d.busy != nil || (h.asset != "native" && (h.gasEnough == false || !h.hasGas)))
                        }
                    }
                }
            } else { Unavailable(what: "Lecture des autres réseaux", error: d.error("elsewhere")) }
        }
    }
}

/// The review of a vault deposit: the verified transfer intent, with the destination identified as the agent's vault.
struct FundReviewSheet: View {
    let model: AppModel
    let flow: SendFlow
    let approval: TransferApproval
    let agent: Agent

    var body: some View {
        let isVault = approval.intent.to.lowercased() == agent.vaultAddress.lowercased()
        SheetScaffold(title: "Vérifier et approuver le dépôt au coffre", width: 720, height: 780) {
            if isVault { Banner(.info, "Destination vérifiée : c’est l’adresse du coffre de l’agent « \(agent.name) ». Les fonds déposés ne reviennent que par « Rapatrier » (vers votre adresse).") }
            else { Banner(.danger, "La destination de l’intention n’est PAS l’adresse du coffre de cet agent. N’approuvez pas.") }
            TransactionReview(intent: approval.intent, digest: approval.approval.digest, network: model.network(approval.intent.network),
                              ownAddresses: Dictionary((model.accounts?.value.accounts ?? []).map { ($0.network, $0.address) }, uniquingKeysWith: { a, _ in a }),
                              warnings: approval.proposal.warnings ?? [],
                              extra: [ReviewLine(label: "Coffre de l’agent", value: "\(agent.name) — \(agent.vaultAddress)", style: .address)]
                                + (approval.proposal.feeDisplay.map { [ReviewLine(label: "Frais estimés", value: "\($0) \(approval.proposal.feeSymbol ?? "") (estimation ; le plafond ci-dessus est ce qui est signé)")] } ?? []))
        } footer: {
            if let e = flow.error { Banner(.danger, e) }
            HStack {
                Button("Rejeter", role: .destructive) { Task { await flow.reject() } }.disabled(flow.step == .approving)
                Spacer()
                if flow.step == .approving { ProgressView().controlSize(.small); Text("Passkey, puis signature isolée…").foregroundStyle(.secondary) }
                Button { Task { await flow.approve() } } label: { Label("Approuver avec la passkey", systemImage: "touchid") }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(flow.step == .approving || !isVault)
            }
        }
        .interactiveDismissDisabled()
    }
}
