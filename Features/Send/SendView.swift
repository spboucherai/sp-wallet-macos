// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Features/Send/SendView.swift
// Description      : Sending crypto: form with live address validation (same
//                    rules as the backend), the review sheet of the verified
//                    intent, the passkey approval, then the honest tracking of
//                    the transaction until the chain finalizes it.
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

struct SendView: View {
    let model: AppModel
    @Bindable var nav: Navigator
    @State private var flow: SendFlow?

    var body: some View {
        Page("Envoyer", subtitle: "Chaque envoi est autorisé par votre passkey sur l’intention exacte, puis signé par le signataire isolé.") {
            if let flow {
                if !model.canOperate { Banner(.warning, "Envoi impossible pour l’instant : session ou portefeuille indisponible.") }
                switch flow.step {
                case .tracking: TrackingCard(flow: flow)
                default: SendForm(model: model, flow: flow)
                }
            } else { ProgressView() }
        }
        .task {
            if flow == nil { flow = SendFlow(model: model) }
            applyPreset()
        }
        .onChange(of: nav.sendPreset) { applyPreset() }
        .sheet(isPresented: Binding(get: { flow?.step == .review || flow?.step == .approving }, set: { _ in })) {
            if let flow, let a = flow.approval { ReviewSheet(model: model, flow: flow, approval: a) }
        }
    }
    private func applyPreset() {
        guard let flow, flow.step == .form else { return }
        if let p = nav.sendPreset { flow.network = p.network; flow.asset = p.asset; nav.sendPreset = nil }
        else if flow.network.isEmpty, let first = model.networks?.value.first { flow.network = first.id; flow.asset = "native" }
    }
}

private struct SendForm: View {
    let model: AppModel
    @Bindable var flow: SendFlow

    var body: some View {
        Card {
            Form {
                NetworkPicker(networks: model.networks?.value ?? [], selection: $flow.network)
                    .onChange(of: flow.network) { if flow.net?.asset(flow.asset) == nil { flow.asset = "native" } }
                AssetPicker(network: flow.net, selection: $flow.asset, balances: model.portfolio?.value.balances ?? [])
                if let a = flow.assetDef, !a.isNative { LabeledContent("Contrat") { Text(a.id).font(Theme.monoSmall).textSelection(.enabled) } }
                LabeledContent("Solde disponible") {
                    if let b = flow.balance, b.isAvailable { Text("\(Fmt.amount(b.display)) \(b.symbol)").monospacedDigit() }
                    else { Text("Indisponible (lecture de chaîne en échec)").foregroundStyle(Theme.negative) }
                }
                if let h = flow.net?.health, h.ok == false { LabeledContent("État RPC") { Text(h.readable == false ? "Chaîne illisible pour l’instant" : "Dégradé").foregroundStyle(Theme.warning) } }
                TextField("Destinataire", text: $flow.to, prompt: Text("Adresse sur \(flow.net?.name ?? "ce réseau")"), axis: .vertical).font(Theme.monoSmall).lineLimit(1...3)
                addressFeedback
                if !model.addressBook.filter({ $0.network == flow.network }).isEmpty {
                    Picker("Carnet d’adresses", selection: Binding(get: { "" }, set: { if !$0.isEmpty { flow.to = $0 } })) {
                        Text("Choisir…").tag("")
                        ForEach(model.addressBook.filter { $0.network == flow.network }) { e in Text("\(e.label) — \(Fmt.short(e.address))").tag(e.address) }
                    }
                }
                HStack {
                    TextField("Montant", text: $flow.amount, prompt: Text("0.0"))
                    Text(flow.assetDef?.symbol ?? "").foregroundStyle(.secondary)
                    Button("Max") { flow.setMax() }.disabled(flow.balance?.isAvailable != true).help(flow.assetDef?.isNative == true ? "Solde entier : les frais de réseau devront être déduits, le serveur refusera sinon." : "Solde entier de cet actif")
                }
                if let a = flow.parsedAmount, !a.isZero, let p = model.price(flow.assetDef?.symbol ?? ""), let d = flow.assetDef?.decimals {
                    LabeledContent("Valeur") { Text(Fmt.fiat(a.approximate(decimals: d) * p.value(in: model.currency), model.currency)).foregroundStyle(.secondary) }
                }
                if let m = flow.net?.memo { TextField(m == "uint32" ? "Étiquette de destination (entier)" : "Mémo", text: $flow.memo) }
                TextField("Note personnelle (non envoyée sur la chaîne)", text: $flow.note)
            }
            .formStyle(.grouped).scrollDisabled(true).disabled(flow.step != .form)
            if let e = flow.error { Banner(.danger, e) }
            HStack {
                if let p = flow.formProblem, !flow.to.isEmpty || !flow.amount.isEmpty { Text(p).foregroundStyle(.secondary).font(.callout) }
                Spacer()
                if flow.step == .preparing { ProgressView().controlSize(.small); Text("Validation, simulation et calcul des frais…").font(.callout).foregroundStyle(.secondary) }
                Button("Préparer et vérifier…") { Task { await flow.prepare() } }.buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(flow.formProblem != nil || !model.canOperate || flow.step != .form)
            }
            Text("Préparer ne signe rien et n’envoie rien : le serveur valide l’adresse, simule la transaction, calcule les frais et vérifie les limites du signataire. L’envoi n’a lieu qu’après votre approbation par passkey sur l’écran suivant.").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var addressFeedback: some View {
        switch flow.addressCheck {
        case .valid(let n):
            LabeledContent("") { Label(flow.isOwnAddress ? "C’est l’adresse de ce portefeuille" : n == flow.to.trimmingCharacters(in: .whitespaces) ? "Adresse valide pour ce réseau" : "Valide — forme normalisée : \(n)", systemImage: flow.isOwnAddress ? "xmark.circle" : "checkmark.circle").foregroundStyle(flow.isOwnAddress ? Theme.negative : Theme.positive).font(.callout) }
        case .invalid(let r):
            LabeledContent("") {
                VStack(alignment: .leading) {
                    Label(SendFlow.text(r), systemImage: "xmark.circle").foregroundStyle(Theme.negative).font(.callout)
                    if !flow.otherNetworks.isEmpty { Text("Cette adresse est valide sur : \(flow.otherNetworks.map(\.name).joined(separator: ", ")). Vérifiez le réseau choisi.").font(.caption).foregroundStyle(Theme.warning) }
                }
            }
        case .unverifiable: LabeledContent("") { Label("Format non vérifiable par cette version de l’app : le serveur validera l’adresse.", systemImage: "questionmark.circle").foregroundStyle(Theme.warning).font(.callout) }
        case nil: EmptyView()
        }
    }
}

private struct ReviewSheet: View {
    let model: AppModel
    let flow: SendFlow
    let approval: TransferApproval

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Vérifier et approuver l’envoi").font(.title2.weight(.semibold)).padding(20)
            Divider()
            ScrollView {
                TransactionReview(intent: approval.intent, digest: approval.approval.digest, network: model.network(approval.intent.network),
                                  ownAddresses: Dictionary(uniqueKeysWithValues: (model.accounts?.value.accounts ?? []).map { ($0.network, $0.address) }),
                                  warnings: approval.proposal.warnings ?? [],
                                  extra: approval.proposal.feeDisplay.map { [ReviewLine(label: "Frais estimés", value: "\($0) \(approval.proposal.feeSymbol ?? "") (estimation ; le plafond ci-dessus est ce qui est signé)")] } ?? [])
                    .padding(20)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if let e = flow.error { Banner(.danger, e) }
                HStack {
                    Button("Rejeter", role: .destructive) { Task { await flow.reject() } }.disabled(flow.step == .approving)
                    Spacer()
                    if flow.step == .approving { ProgressView().controlSize(.small); Text("Passkey, puis signature isolée…").foregroundStyle(.secondary) }
                    Button { Task { await flow.approve() } } label: { Label("Approuver avec la passkey", systemImage: "touchid") }
                        .buttonStyle(.borderedProminent).controlSize(.large).disabled(flow.step == .approving)
                }
            }.padding(16)
        }
        .frame(width: 720, height: 760)
        .interactiveDismissDisabled()
    }
}

/// After approval: every state change as it happened. Success is announced only at `finalized`.
struct TrackingCard: View {
    let flow: SendFlow
    var body: some View {
        if let p = flow.tracked {
            Card("Suivi de la transaction") {
                ProposalStatusView(proposal: p)
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Historique des états").font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(flow.history.enumerated()), id: \.offset) { _, h in
                        HStack { Text(Fmt.dateSeconds(h.0)).monospacedDigit().foregroundStyle(.secondary); Text(ErrorText.state(h.1)) }.font(.callout)
                    }
                }
                HStack { Spacer(); Button(p.state.isTerminal ? "Nouvel envoi" : "Nouvel envoi (le suivi continue dans Activité)") { flow.reset() } }
            }
        }
    }
}

/// The state of one proposal, with the exact vocabulary: signed ≠ broadcast ≠ confirming ≠ finalized.
struct ProposalStatusView: View {
    let proposal: Proposal
    var body: some View {
        let p = proposal
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Group {
                    if p.state.isSuccess { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.positive) }
                    else if p.state.isFailure || p.state == .notBroadcast { Image(systemName: "xmark.octagon.fill").foregroundStyle(Theme.negative) }
                    else { ProgressView().controlSize(.small) }
                }.font(.title2)
                VStack(alignment: .leading) {
                    Text(ErrorText.state(p.state)).font(.title3.weight(.semibold))
                    Text(explanation(p.state)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Field(label: "Montant", value: "\(Fmt.amount(p.amountDisplay)) \(p.symbol) · \(p.networkName ?? p.network)")
            if let to = p.to { Field(label: "Destinataire", value: to, mono: true) }
            if let tx = p.txid { Field(label: "Identifiant de transaction", value: tx, mono: true) }
            if let c = p.confirmations, p.txid != nil { Field(label: "Confirmations", value: String(c)) }
            if let e = p.error { Banner(p.state.isFailure || p.state == .notBroadcast ? .danger : .warning, e) }
            if let ex = p.explorer, let url = URL(string: ex), url.scheme == "https" { Link("Ouvrir dans l’explorateur de blocs", destination: url) }
        }
    }
    private func explanation(_ s: ProposalState) -> String {
        switch s {
        case .approved: "Approbation transmise au signataire isolé."
        case .signed: "Transaction signée ; pas encore relayée au réseau."
        case .broadcast: "Relayée au réseau. Un identifiant de transaction n’est pas une confirmation : elle peut encore être abandonnée ou remplacée."
        case .confirming: "Incluse dans un bloc ; en attente du nombre de confirmations requis."
        case .finalized: "Confirmée par la chaîne au seuil de finalité du réseau."
        case .reorged: "Le bloc qui la contenait a été réorganisé ; la confirmation est à refaire."
        case .notBroadcast: "Le serveur est en mode test : la transaction a été signée mais volontairement pas relayée. Rien n’a été envoyé."
        case .failed, .rejected, .expired, .replaced: "Aucun succès. Vérifiez le détail ci-dessous."
        default: ""
        }
    }
}
