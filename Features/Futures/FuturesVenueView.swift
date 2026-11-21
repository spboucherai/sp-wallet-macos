// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Features/Futures/FuturesVenueView.swift
// Description      : The venue side of live derivatives: the jurisdiction
//                    notice and the server locks with their reasons, the venues
//                    as the server lists them (dYdX and edgeX are market data
//                    only, with the server's jurisdiction reason), the
//                    lifecycle of the live venue account (creation in
//                    read-only, authorization of the dedicated trading key with
//                    the instruments and limits the owner chooses, revocation,
//                    recovery after a lost answer), the account's halt and its
//                    lifting, and the collateral (deposit through the pinned
//                    Arbitrum bridge, withdrawal to the wallet's own address)
//                    followed until the venue or the wallet confirms. Every
//                    form here only PREPARES: the passkey is asked on the
//                    review sheet.
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

struct FutVenueView: View {
    let model: AppModel
    @Bindable var store: FuturesStore
    @Bindable var ops: FutLiveOps

    var body: some View {
        FutLocksCard(store: store)
        venuesCard
        if store.mode == .paper {
            Card("Mode simulation", trailing: AnyView(FutModeBadge(mode: .paper))) {
                Text("Un compte papier n’a ni compte de plateforme, ni clé, ni collatéral réel : rien à autoriser ni à déposer. Passez en mode Testnet ou Réel (en haut) pour gérer un compte de plateforme.").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        } else {
            FutJurisdictionCard(store: store)
            if let e = ops.error { Banner(.danger, e) }
            if let n = ops.notice { Banner(.info, n) }
            if ops.isBusy { HStack { ProgressView().controlSize(.small); Text(ops.busyText ?? "Approbation en cours…").foregroundStyle(.secondary) } }
            if let a = store.liveAccount {
                FutAuthorizationCard(model: model, store: store, ops: ops, account: a)
                FutHaltCard(model: model, store: store, ops: ops, account: a)
                FutCollateralCard(model: model, store: store, ops: ops, account: a)
                Card("Politique de risque du compte (côté serveur)", trailing: AnyView(FutModeBadge(mode: store.mode))) {
                    ReviewLines(lines: FutApprovalSheet.policyLines(a.policy))
                    Text("Ces limites propres au compte s’ajoutent à celles du signataire et au moteur de risque global (onglet Risque). Cette version de l’app les affiche sans les modifier.").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                createCard
            }
        }
    }

    private var venuesCard: some View {
        Card("Plateformes servies par le serveur") {
            if let e = store.venues.error { Banner(.danger, "Indisponible : \(e)") }
            ForEach(store.venues.value ?? []) { v in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(v.name).fontWeight(.medium)
                        Text(v.network).font(.caption).foregroundStyle(.secondary)
                        Text(v.status).font(.caption.weight(.medium)).foregroundStyle(v.status == "ok" ? Theme.positive : Theme.warning)
                        Spacer()
                        Text(v.restriction != nil ? "Données de marché seulement" : v.capabilities?.orders == true ? "Comptes et ordres possibles côté serveur" : "Lecture seule").font(.caption).foregroundStyle(v.restriction != nil ? Theme.warning : .secondary)
                        if v.paper == true { ProvenanceTag(p: .simulated, text: "papier disponible") }
                    }
                    if let r = v.restriction { Text(r).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) }
                    if let e = v.lastError, v.status != "ok" { Text("Dernière erreur : \(e)").font(.caption).foregroundStyle(Theme.warning) }
                }.padding(.vertical, 3)
            }
            Text("Comptes réels : le serveur n’en ouvre que sur Hyperliquid (\((store.config.value?.venues ?? []).map { "\($0.venue) : \($0.networks.joined(separator: ", "))" }.joined(separator: " ; "))). GMX v2 a son propre onglet.").font(.caption).foregroundStyle(.secondary)
        }
    }

    @State private var newLabel = "Hyperliquid"

    @ViewBuilder private var createCard: some View {
        let net = store.mode.network ?? ""
        let locked = store.mode == .mainnet && store.config.value?.mainnetEnabled != true
        Card("Créer le compte \(store.mode == .mainnet ? "réel" : "testnet") Hyperliquid", trailing: AnyView(FutModeBadge(mode: store.mode))) {
            if let e = store.liveAccounts.error { Banner(.danger, "Comptes illisibles : \(e)") }
            Text("Le compte de plateforme est l’adresse EVM de ce portefeuille. Il est créé en LECTURE SEULE : rien ne peut être négocié avant que vous n’autorisiez la clé de négociation.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if locked { Banner(.warning, store.config.value?.mainnet?.reason ?? store.config.error.map { "Configuration illisible : \($0)" } ?? "Le serveur garde le mainnet fermé : un compte réel ne peut pas être créé.") }
            else {
                HStack {
                    TextField("Nom du compte", text: $newLabel).textFieldStyle(.roundedBorder).frame(maxWidth: 280)
                    Spacer()
                    Button("Créer le compte (\(store.mode.badge), lecture seule)") { Task { await ops.createAccount(network: net, label: newLabel.trimmingCharacters(in: .whitespaces)) } }
                        .buttonStyle(.borderedProminent).tint(store.mode.color)
                        .disabled(!model.canOperate || ops.isBusy || newLabel.trimmingCharacters(in: .whitespaces).isEmpty || !store.liveActionsAllowed || store.liveAccounts.value == nil)
                }
                if !store.liveActionsAllowed { Text("Lisez et cochez l’avis de juridiction ci-dessus d’abord.").font(.caption).foregroundStyle(Theme.warning) }
            }
        }
    }
}

// MARK: - authorization

private struct FutAuthorizationCard: View {
    let model: AppModel
    let store: FuturesStore
    let ops: FutLiveOps
    let account: LiveAccount

    @State private var instruments: Set<String> = []
    @State private var filter = ""
    @State private var maxLeverage = 1
    @State private var maxOrder = ""
    @State private var maxPosition = ""
    @State private var maxGross = ""
    @State private var ordersPerDay = ""
    @State private var deviationBps = ""
    @State private var days = ""
    @State private var cancelOnRevoke = true
    @State private var confirmRevoke = false

    private var pinned: [LivePinnedAsset] { account.network == "testnet" ? (store.config.value?.pinnedAssets.testnet ?? []) : (store.config.value?.pinnedAssets.mainnet ?? []) }
    private var bounds: LiveConfig.Bounds? { store.config.value?.bounds }
    private var leverageCeiling: Int {
        let chosen = pinned.filter { instruments.contains($0.instrument) }.map(\.maxLeverage).min() ?? 1
        return max(1, min(chosen, bounds?.maxLeverage ?? chosen))
    }
    private var policy: VenuePolicy? {
        guard !instruments.isEmpty, let o = FutNum.input(maxOrder), let p = FutNum.input(maxPosition), let g = FutNum.input(maxGross), let n = Int(ordersPerDay), n > 0, let b = Int(deviationBps), b > 0 else { return nil }
        return VenuePolicy(allowedInstruments: instruments.sorted(), maxLeverage: min(maxLeverage, leverageCeiling), maxOrderNotional: o, maxPositionNotional: p, maxGrossExposure: g, maxOrdersPerDay: n, maxPriceDeviationBps: b)
    }
    private var problem: String? {
        if store.config.value == nil { return "Configuration du serveur illisible : les instruments autorisables sont inconnus." }
        if instruments.isEmpty { return "Choisissez au moins un instrument." }
        if let m = bounds?.maxInstruments, instruments.count > m { return "Au plus \(m) instruments." }
        if policy == nil { return "Renseignez chaque limite (montants positifs, entiers positifs)." }
        if let n = Int(ordersPerDay), let m = bounds?.maxOrdersPerDay, n > m { return "Au plus \(m) ordres par jour." }
        if let b = Int(deviationBps), let lo = bounds?.minPriceBandBps, let hi = bounds?.maxPriceBandBps, !(lo...hi).contains(b) { return "Écart de prix : de \(lo) à \(hi) points de base." }
        guard let d = Int(days), d >= 1 else { return "Durée en jours (entier)." }
        if let m = bounds?.maxAuthorizationDays, d > m { return "Durée maximale : \(m) jours." }
        return nil
    }

    var body: some View {
        Card("Autorisation de négociation", trailing: AnyView(FutModeBadge(mode: store.mode))) {
            Field(label: "Compte", value: account.account, mono: true)
            Field(label: "Clé de négociation dédiée", value: account.agentAddress, mono: true)
            Field(label: "Mode", value: account.mode.rawValue)
            if let auth = account.authorization {
                Divider()
                HStack { Text("Autorisation \(auth.active ? "active" : auth.expired ? "EXPIRÉE" : "inactive")").font(.headline).foregroundStyle(auth.active ? Theme.positive : Theme.warning); Spacer(); Text("expire \(Fmt.date(auth.expiresAt))").font(.callout).foregroundStyle(.secondary) }
                let p = auth.policy
                Field(label: "Instruments permis", value: p.allowedInstruments.joined(separator: ", "))
                Field(label: "Levier maximal", value: "\(p.maxLeverage)×")
                Field(label: "Notionnel max ordre / position", value: "\(FutNum.exact(p.maxOrderNotional)) $ / \(FutNum.exact(p.maxPositionNotional)) $")
                Field(label: "Exposition brute max", value: "\(FutNum.exact(p.maxGrossExposure)) $")
                Field(label: "Ordres par jour · écart de prix", value: "\(p.maxOrdersPerDay) · \(p.maxPriceDeviationBps) pb")
                if let h = auth.hash { Field(label: "Empreinte approuvée", value: h, mono: true) }
                Toggle("Annuler aussi les ordres au carnet lors de la révocation", isOn: $cancelOnRevoke).toggleStyle(.checkbox)
                HStack {
                    Text("Révoquer ne demande pas de passkey : cela retire seulement de l’autorité. Les positions restent ouvertes ; pour changer les limites, révoquez puis autorisez de nouveau.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Révoquer l’autorisation…", role: .destructive) { confirmRevoke = true }.disabled(!model.canOperate || ops.isBusy)
                        .confirmationDialog("Révoquer l’autorisation de négociation ?", isPresented: $confirmRevoke) {
                            Button("Révoquer (\(store.mode.badge))", role: .destructive) { Task { await ops.revoke(cancelOpenOrders: cancelOnRevoke) } }
                        } message: { Text("Le compte repasse en lecture seule. Les positions ouvertes restent ouvertes et exposées au marché.") }
                }
            }
            if account.pendingAuthorization != nil {
                Banner(.warning, "Une autorisation préparée attend sa conclusion. Si une approbation a été interrompue (réponse perdue), « Récupérer » fait adopter ou retirer par le serveur ce que la passkey a réellement approuvé — sans passkey.")
                Button("Récupérer l’état de l’autorisation") { Task { await ops.recover() } }.disabled(!model.canOperate || ops.isBusy)
            }
            if account.mode == .readOnly {
                Divider()
                if account.isMainnet, !account.mainnetEnabled {
                    Banner(.warning, store.config.value?.mainnet?.reason ?? "Le serveur garde le mainnet fermé : aucune autorisation réelle ne peut être préparée.")
                } else { form }
            }
        }
        .onChange(of: instruments) { maxLeverage = min(maxLeverage, leverageCeiling) }
    }

    @ViewBuilder private var form: some View {
        Text("Autoriser la négociation").font(.headline)
        Text("Vous choisissez chaque limite : aucune n’est proposée par défaut, et le levier part de 1×. Le signataire isolé refusera tout ordre qui les dépasse.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Filtrer les instruments", text: $filter).textFieldStyle(.roundedBorder)
                List(pinned.filter { filter.isEmpty || $0.instrument.lowercased().contains(filter.lowercased()) }, id: \.instrument) { a in
                    Toggle(isOn: Binding(get: { instruments.contains(a.instrument) }, set: { if $0 { instruments.insert(a.instrument) } else { instruments.remove(a.instrument) } })) {
                        HStack { Text(a.instrument).font(Theme.monoSmall); Spacer(); Text("max plateforme \(a.maxLeverage)×").font(.caption).foregroundStyle(.secondary) }
                    }.toggleStyle(.checkbox)
                }.frame(height: 210).listStyle(.bordered)
                Text("\(instruments.count) choisi(s)" + (bounds?.maxInstruments.map { " · au plus \($0)" } ?? "") + (store.config.value.map { " · table épinglée le \($0.pinnedAssets.pinnedAt)" } ?? "")).font(.caption).foregroundStyle(.secondary)
            }.frame(width: 330)
            Form {
                Stepper(value: $maxLeverage, in: 1...leverageCeiling) { Text("Levier maximal : \(min(maxLeverage, leverageCeiling))×  (plafond possible \(leverageCeiling)×)") }
                TextField("Notionnel max par ordre ($)", text: $maxOrder)
                TextField("Notionnel max par position ($)", text: $maxPosition)
                TextField("Exposition brute maximale ($)", text: $maxGross)
                TextField("Ordres par jour" + (bounds?.maxOrdersPerDay.map { " (≤ \($0))" } ?? ""), text: $ordersPerDay)
                TextField("Écart de prix toléré (pb" + ((bounds?.minPriceBandBps).flatMap { lo in bounds?.maxPriceBandBps.map { ", \(lo)–\($0)" } } ?? "") + ")", text: $deviationBps)
                TextField("Durée en jours" + (bounds?.maxAuthorizationDays.map { " (≤ \($0))" } ?? ""), text: $days)
            }.formStyle(.grouped).scrollDisabled(true)
        }
        HStack {
            if let p = problem { Text(p).font(.callout).foregroundStyle(.secondary) }
            else if !store.liveActionsAllowed { Text("Lisez et cochez l’avis de juridiction d’abord.").font(.callout).foregroundStyle(Theme.warning) }
            Spacer()
            Button("Préparer l’autorisation…") { if let p = policy, let d = Int(days) { Task { await ops.prepareAuthorization(policy: p, days: d) } } }
                .buttonStyle(.borderedProminent).tint(store.mode.color)
                .disabled(problem != nil || !model.canOperate || ops.isBusy || !store.liveActionsAllowed)
        }
    }
}

// MARK: - halt

private struct FutHaltCard: View {
    let model: AppModel
    let store: FuturesStore
    let ops: FutLiveOps
    let account: LiveAccount
    @State private var reason = ""
    @State private var confirm = false

    var body: some View {
        Card("Arrêt des nouveaux ordres sur ce compte", trailing: AnyView(FutModeBadge(mode: store.mode))) {
            if let h = account.halted { Banner(.danger, "Arrêt en vigueur : \(h)") } else { Text("Aucun arrêt en vigueur.").foregroundStyle(.secondary) }
            if let d = account.divergence { Banner(.danger, "Divergence signalée : \(d)") }
            HStack {
                TextField("Raison (facultative)", text: $reason).textFieldStyle(.roundedBorder).frame(maxWidth: 320)
                Button("Arrêter les nouveaux ordres…", role: .destructive) { confirm = true }.disabled(!model.canOperate || ops.isBusy)
                    .confirmationDialog("Arrêter les nouveaux ordres sur ce compte ?", isPresented: $confirm) {
                        Button("Arrêter maintenant (\(store.mode.badge))", role: .destructive) { Task { await ops.halt(reason: String(reason.prefix(200))) } }
                    } message: { Text("Aucune passkey n’est requise pour arrêter. L’arrêt n’annule aucun ordre au carnet et ne clôture aucune position.") }
                Spacer()
                if account.halt != nil { Button("Lever l’arrêt (passkey)…") { Task { await ops.prepareResume() } }.disabled(!model.canOperate || ops.isBusy || !store.liveActionsAllowed) }
                if account.divergence != nil { Button("Accepter les positions de la plateforme (passkey)…") { Task { await ops.prepareRebase() } }.disabled(!model.canOperate || ops.isBusy || !store.liveActionsAllowed) }
            }
            Text("Arrêter est immédiat et sans passkey ; lever un arrêt redonne de l’autorité et exige votre passkey sur l’arrêt exact qui est levé.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - collateral

private struct FutCollateralCard: View {
    let model: AppModel
    let store: FuturesStore
    let ops: FutLiveOps
    let account: LiveAccount
    @State private var depositAmount = ""
    @State private var withdrawAmount = ""

    static func reason(_ code: String?) -> String {
        switch code {
        case "mainnet_disabled": "le serveur garde le mainnet fermé (deriv_live_mainnet)"
        case "halted": "un arrêt est en vigueur"
        case "no_route": "aucune route de dépôt n’existe pour ce réseau (le collatéral du testnet est fictif)"
        case "no_usdc": "le portefeuille n’a pas d’USDC sur le réseau de la route"
        case "no_gas": "le portefeuille n’a pas de quoi payer les frais de réseau"
        case "limit_reached": "la limite de transfert du signataire est atteinte"
        case "usdc_elsewhere": "les USDC du portefeuille sont sur un autre réseau : il faut d’abord les y amener"
        case "wallet_unreadable": "le solde du portefeuille est illisible"
        case "venue_unreadable": "la plateforme est illisible"
        case nil: "raison non précisée par le serveur"
        case .some(let c): c
        }
    }

    var body: some View {
        Card("Collatéral", trailing: AnyView(HStack { Button("Actualiser") { Task { await ops.loadCollateral() } }; FutModeBadge(mode: store.mode) })) {
            if let e = ops.collateral.error { Banner(.danger, "État du collatéral indisponible : \(e)") }
            if let s = ops.collateral.value {
                let b = s.venueBalance
                if let e = b.error { Banner(.danger, "Solde sur la plateforme illisible : \(e). Ce n’est pas un solde nul.") }
                FutStatGrid {
                    FutStat("Valeur sur la plateforme", b.error == nil ? FutNum.usd(b.equity) : nil)
                    FutStat("Retirable", b.error == nil ? FutNum.usd(b.withdrawable) : nil)
                    FutStat("USDC du portefeuille", s.wallet.map { "\(FutNum.exact($0.usdc)) USDC" }, note: s.wallet.map { "sur \($0.networkName)" } ?? s.walletError)
                    FutStat("Frais de réseau disponibles", s.wallet.map { "\(FutNum.exact($0.gas, maxFraction: 6)) \($0.gasSymbol)" })
                }
                if let w = s.wallet {
                    Field(label: "Limites du signataire", value: "par transfert \(w.limits.perTransfer) · par jour \(w.limits.perDay) · utilisé aujourd’hui \(w.limits.spentToday) · possible maintenant \(w.limits.maxNow)")
                    if let other = w.elsewhere, !other.isEmpty { Field(label: "USDC sur d’autres réseaux", value: other.map { "\($0.name) : \($0.usdc)" }.joined(separator: " · ")) }
                }
                Divider()
                Text("Dépôt").font(.headline)
                if let r = s.route {
                    Field(label: "Route épinglée", value: "\(r.networkName) → pont \(r.bridge)", mono: true)
                    Field(label: "Minimum", value: "\(r.minimum) \(r.asset) (minimum de la plateforme \(r.venueMinimum) : en dessous, les fonds sont perdus)")
                    Field(label: "Délai attendu", value: r.expectedSeconds.map { "≈ \($0) s" } ?? "non publié")
                    if let c = r.credits { Field(label: "Compte crédité", value: c) }
                } else { Text("Aucune route de dépôt pour ce réseau.").foregroundStyle(.secondary) }
                if s.deposit.available {
                    HStack {
                        TextField("Montant", text: $depositAmount, prompt: Text("USDC")).textFieldStyle(.roundedBorder).frame(width: 160)
                        Text("USDC").foregroundStyle(.secondary)
                        Spacer()
                        Button("Préparer le dépôt…") { if let a = FutNum.input(depositAmount) { Task { await ops.prepareDeposit(amount: a) } } }
                            .buttonStyle(.borderedProminent).tint(store.mode.color)
                            .disabled(FutNum.input(depositAmount) == nil || !model.canOperate || ops.isBusy || !store.liveActionsAllowed)
                    }
                } else {
                    Banner(.warning, "Dépôt impossible pour l’instant : \(Self.reason(s.deposit.reason))" + (s.deposit.reason.map { " [\($0)]" } ?? ""))
                }
                Divider()
                Text("Retrait").font(.headline)
                Field(label: "Destination", value: s.withdrawal.destination + " (l’adresse de ce portefeuille — la seule possible)", mono: true)
                Field(label: "Frais de la plateforme", value: "\(s.withdrawal.fee) USDC" + (s.withdrawal.expectedSeconds.map { " · délai attendu ≈ \($0) s" } ?? "") + (s.withdrawal.payoutNetworkName.map { " · versé sur \($0)" } ?? ""))
                if s.withdraw.available {
                    HStack {
                        TextField("Montant", text: $withdrawAmount, prompt: Text(s.withdrawal.available.map { "max \($0)" } ?? "USDC")).textFieldStyle(.roundedBorder).frame(width: 160)
                        Text("USDC").foregroundStyle(.secondary)
                        Spacer()
                        Button("Préparer le retrait…") { if let a = FutNum.input(withdrawAmount) { Task { await ops.prepareWithdraw(amount: a) } } }
                            .buttonStyle(.borderedProminent).tint(store.mode.color)
                            .disabled(FutNum.input(withdrawAmount) == nil || !model.canOperate || ops.isBusy || !store.liveActionsAllowed)
                    }
                } else {
                    Banner(.warning, "Retrait impossible pour l’instant : \(Self.reason(s.withdraw.reason))" + (s.withdraw.reason.map { " [\($0)]" } ?? ""))
                }
                if !store.liveActionsAllowed { Text("Lisez et cochez l’avis de juridiction d’abord.").font(.caption).foregroundStyle(Theme.warning) }
                if let op = ops.trackedOperation { Divider(); FutOperationRow(model: model, ops: ops, op: op, tracked: true) }
                if !s.operations.isEmpty {
                    Divider()
                    Text("Opérations").font(.headline)
                    ForEach(s.operations.filter { $0.id != ops.trackedOperation?.id }.prefix(15)) { op in FutOperationRow(model: model, ops: ops, op: op, tracked: false) }
                }
            } else if ops.collateral.error == nil {
                ProgressView().frame(maxWidth: .infinity, minHeight: 60)
            }
        }
        .task(id: account.id) { ops.resetCollateral(); await ops.loadCollateral() }
    }
}

/// One collateral operation with its state verbatim. A deposit is done only when CREDITED by the venue, a withdrawal only when the wallet SAW the funds.
private struct FutOperationRow: View {
    let model: AppModel
    let ops: FutLiveOps
    let op: CollateralOperation
    let tracked: Bool

    static func state(_ s: String) -> String {
        switch s {
        case "pending_approval": "En attente de votre passkey"
        case "signed": "Signée, non diffusée"
        case "sent": "Envoyée, non confirmée"
        case "awaiting_credit": "Confirmée sur la chaîne, en attente du crédit de la plateforme"
        case "credited": "Créditée par la plateforme"
        case "completed": "Reçue par le portefeuille"
        case "failed": "Échouée"
        case "expired": "Expirée"
        case "cancelled": "Annulée"
        default: s
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if tracked, !op.final { ProgressView().controlSize(.small) }
                Image(systemName: op.kind == "deposit" ? "arrow.down.to.line" : "arrow.up.to.line")
                Text("\(op.kind == "deposit" ? "Dépôt" : "Retrait") de \(FutNum.exact(op.amount)) \(op.asset)").fontWeight(.medium)
                Text(Self.state(op.state)).font(.caption.weight(.medium)).foregroundStyle(op.isDone ? Theme.positive : ["failed", "expired", "cancelled"].contains(op.state) ? Theme.negative : Theme.warning)
                    .padding(.horizontal, 7).padding(.vertical, 2).background(Color.secondary.opacity(0.12), in: Capsule()).help("État rapporté par le serveur : \(op.state)")
                Spacer()
                Text(Fmt.date(op.createdAt)).font(.caption).foregroundStyle(.secondary)
                if !op.final, op.state == "pending_approval" { Button("Annuler") { Task { await ops.cancelOperation(op.id) } }.disabled(ops.isBusy || !model.canOperate) }
            }
            if let tx = op.txid { Text("Transaction \(tx)").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(1) }
            if op.overdue == true { Text("Plus long que le délai attendu : l’opération est toujours suivie.").font(.caption).foregroundStyle(Theme.warning) }
            if let e = op.error { Text(e).font(.caption).foregroundStyle(Theme.negative).fixedSize(horizontal: false, vertical: true) }
            if let c = op.check, !c.isEmpty { Text(c.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            if let ex = op.explorer, let url = URL(string: ex), url.scheme == "https" { Link("Ouvrir dans l’explorateur de blocs", destination: url).font(.caption) }
        }.padding(.vertical, 3)
    }
}
