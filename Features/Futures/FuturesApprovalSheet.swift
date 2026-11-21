// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Features/Futures/FuturesApprovalSheet.swift
// Description      : The review sheet shown before every passkey approval of
//                    the live derivatives path. It renders the fields OF THE
//                    VERIFIED OBJECT — the venue authorization, the venue
//                    order, the leverage change, the collateral deposit intent,
//                    the venue withdrawal or the risk intent whose SHA-256 the
//                    Core proved to be the WebAuthn challenge — never the
//                    server's summary of it, followed by the binding proof. The
//                    server's estimates are shown apart and labelled as
//                    estimates. Nothing is approved without the explicit
//                    button; closing the sheet withdraws the pending proposal.
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

struct FutApprovalSheet: View {
    let model: AppModel
    let store: FuturesStore
    @Bindable var ops: FutLiveOps
    let sheet: FutLiveOps.Sheet

    private var mode: FutMode { store.mode }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FutSheetHeader(title: title, mode: mode)
            Divider()
            ScrollView { VStack(alignment: .leading, spacing: 14) { content }.padding(20) }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if let e = ops.sheetError { Banner(.danger, e) }
                if !model.canOperate { Banner(.warning, "Session ou portefeuille indisponible : l’approbation est désactivée.") }
                HStack {
                    Button(closeTitle, role: .destructive) { Task { await ops.dismiss() } }.disabled(ops.approving)
                    Spacer()
                    if ops.approving { ProgressView().controlSize(.small); Text("Passkey, puis signataire isolé…").foregroundStyle(.secondary) }
                    Button { Task { await ops.approve() } } label: { Label(approveTitle, systemImage: "touchid") }
                        .buttonStyle(.borderedProminent).tint(mode.color).controlSize(.large)
                        .disabled(ops.approving || !model.canOperate || needsAcknowledgement)
                }
            }.padding(16)
        }
        .frame(width: 740, height: 780)
        .interactiveDismissDisabled()
    }

    private var needsAcknowledgement: Bool { if case .authorization = sheet { return !ops.acknowledged }; return false }

    private var title: String {
        switch sheet {
        case .authorization: "Autoriser la clé de négociation"
        case .order(_, _, let close): close ? "Vérifier et approuver la clôture" : "Vérifier et approuver l’ordre"
        case .leverage: "Vérifier et approuver le changement de levier"
        case .deposit: "Vérifier et approuver le dépôt de collatéral"
        case .withdraw: "Vérifier et approuver le retrait de collatéral"
        case .risk(let r): r.intent.kind == .resume ? "Lever l’arrêt du compte" : r.intent.kind == .rebase ? "Accepter les positions de la plateforme" : "Assouplir les limites du compte"
        }
    }
    private var closeTitle: String {
        switch sheet {
        case .order: "Retirer la proposition"
        case .deposit, .withdraw: "Annuler l’opération"
        default: "Fermer sans approuver"
        }
    }
    private var approveTitle: String { "Approuver avec la passkey (\(mode.badge))" }

    @ViewBuilder private var content: some View {
        switch sheet {
        case .authorization(let p): authorization(p)
        case .order(let p, let a, let close): order(p, a, close: close)
        case .leverage(let l): leverage(l)
        case .deposit(let d): deposit(d)
        case .withdraw(let w): withdraw(w)
        case .risk(let r): risk(r)
        }
    }

    private static func date(seconds: Int) -> String { Fmt.dateSeconds(Date(timeIntervalSince1970: TimeInterval(seconds))) }
    private static func date(ms: Int) -> String { Fmt.dateSeconds(Date(timeIntervalSince1970: TimeInterval(ms) / 1000)) }

    // MARK: venue authorization

    @ViewBuilder private func authorization(_ p: LiveAuthorizationPreparation) -> some View {
        let x = p.authorization, pol = x.policy
        Banner(.warning, "Après cette approbation, la clé de négociation dédiée peut placer sur ce compte les ordres que vous approuverez un à un, dans les limites ci-dessous. Ces limites sont appliquées par le signataire isolé.")
        ReviewLines(lines: [
            .init(label: "Type d’opération", value: "Autorisation de négociation sur un compte de plateforme", style: .strong),
            .init(label: "Plateforme / réseau", value: "\(x.venue) · \(x.network)", style: .strong),
            .init(label: "Compte (votre adresse)", value: x.account, style: .address),
            .init(label: "Clé de négociation autorisée", value: x.agentAddress, style: .address),
            .init(label: "Nom de la clé", value: x.agentName),
            .init(label: "Mode accordé", value: x.mode),
            .init(label: "Instruments permis", value: pol.allowedInstruments.sorted().joined(separator: ", "), style: .strong),
            .init(label: "Levier maximal", value: "\(pol.maxLeverage)×", style: .strong),
            .init(label: "Notionnel max par ordre", value: "\(FutNum.exact(pol.maxOrderNotional)) $"),
            .init(label: "Notionnel max par position", value: "\(FutNum.exact(pol.maxPositionNotional)) $"),
            .init(label: "Exposition brute maximale", value: "\(FutNum.exact(pol.maxGrossExposure)) $"),
            .init(label: "Ordres par jour", value: String(pol.maxOrdersPerDay)),
            .init(label: "Écart de prix toléré", value: "\(pol.maxPriceDeviationBps) points de base"),
            .init(label: "Valide du", value: Self.date(seconds: x.createdAt)),
            .init(label: "Expire le", value: Self.date(seconds: x.expiresAt), style: .strong),
            .init(label: "Nonce de l’approbation", value: String(x.approveNonce)),
            .init(label: "Empreinte de l’avis lu", value: x.ackSha256),
            .init(label: "Identifiant", value: x.authorizationId),
            .init(label: "Clé du portefeuille", value: x.keyId),
        ])
        if let a = p.agent {
            if let can = a.can, !can.isEmpty { listBlock("Ce que la clé de négociation peut faire (selon le serveur)", can, color: Theme.warning) }
            if let cannot = a.cannot, !cannot.isEmpty { listBlock("Ce qu’elle ne peut pas faire", cannot, color: Theme.positive) }
            if let n = a.note { Text(n).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
        if let w = p.whatIsSigned {
            if let m = w.byMainKey { Field(label: "Signé par la clé du portefeuille", value: m) }
            if let k = w.byPasskey { Field(label: "Signé par votre passkey", value: k) }
        }
        if let e = p.venueState?.error { Banner(.warning, "État du compte illisible sur la plateforme au moment de la préparation : \(e)") }
        VStack(alignment: .leading, spacing: 8) {
            Text("Avis de juridiction (\(p.acknowledgement.venue), \(p.acknowledgement.locale))").font(.headline)
            Text(p.acknowledgement.text).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Toggle("J’ai lu cet avis et je confirme que je peux utiliser cette plateforme. L’autorisation s’engage sur l’empreinte de ce texte.", isOn: $ops.acknowledged).toggleStyle(.checkbox)
        }.padding(10).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        BindingProof(digest: p.approval.digest, expiry: nil)
    }

    private func listBlock(_ title: String, _ items: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout.weight(.medium))
            ForEach(items, id: \.self) { Label($0, systemImage: "circle.fill").labelStyle(.titleAndIcon).font(.callout).foregroundStyle(.primary).symbolRenderingMode(.monochrome).imageScale(.small).tint(color) }
        }
    }

    // MARK: venue order

    @ViewBuilder private func order(_ p: LiveOrderProposal, _ a: LiveOrderApproval, close: Bool) -> some View {
        let o = a.order
        if p.idempotent { Banner(.info, "Cette proposition existait déjà pour la même clé : c’est elle qui est affichée, rien n’a été créé une seconde fois.") }
        ReviewLines(lines: [
            .init(label: "Type d’opération", value: close ? "Clôture en réduction seule sur la plateforme" : "Ordre sur la plateforme", style: .strong),
            .init(label: "Plateforme / réseau", value: "\(o.venue) · \(o.network)", style: .strong),
            .init(label: "Compte", value: o.account, style: .address),
            .init(label: "Instrument", value: o.instrument, style: .strong),
            .init(label: "Sens", value: o.side == "buy" ? "ACHAT (buy)" : "VENTE (sell)", style: .strong),
            .init(label: "Taille", value: FutNum.exact(o.size), style: .strong),
            .init(label: "Type envoyé", value: "\(o.type) · \(o.tif)" + (o.type == "limit" && o.tif == "ioc" ? " — un ordre au marché est envoyé comme limite immédiate au pire prix ci-dessous" : "")),
            .init(label: o.tif == "ioc" ? "Pire prix accepté" : "Prix limite", value: FutNum.exact(o.price), style: .strong),
            .init(label: "Prix de déclenchement", value: o.triggerPrice.map { FutNum.exact($0) } ?? "aucun"),
            .init(label: "Réduction seule", value: o.reduceOnly ? "oui — ne peut qu’alléger la position" : "non — peut ouvrir ou augmenter une position", style: o.reduceOnly ? .normal : .warning),
            .init(label: "Identifiant d’ordre (plateforme)", value: o.clientId),
            .init(label: "Autorisation utilisée", value: o.authorizationId),
            .init(label: "Nonce / expiration", value: "\(o.nonce) · expire à \(Self.date(ms: o.expiresAt))"),
        ])
        if let e = p.estimate {
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("Estimations du serveur").font(.headline); ProvenanceTag(p: .estimate) }
                Field(label: "Exposition notionnelle", value: FutNum.usd(e.notional))
                Field(label: "Levier (plateforme)", value: (e.leverage.map { "\(FutNum.exact($0))×" } ?? "non lu") + (e.marginMode.map { " · marge \($0)" } ?? ""))
                Field(label: "Marge requise", value: FutNum.usd(e.initialMargin))
                Field(label: "Frais", value: FutNum.usd(e.fee) + (e.feeNote.map { " — \($0)" } ?? ""))
                Field(label: "Collatéral libre après", value: FutNum.usd(e.freeCollateralAfter))
                Field(label: "Prix de liquidation", value: e.liquidationNote ?? "aucune estimation avant l’ordre : la plateforme le publie une fois la position ouverte")
            }.padding(10).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
        if close, let pos = p.position {
            Field(label: "Position visée", value: "\(pos.side.uppercased()) \(FutNum.exact(pos.size)) \(pos.instrument) (entrée \(FutNum.exact(pos.entryPrice)))")
            if let b = p.slippageBoundBps { Field(label: "Borne de glissement", value: "\(b) points de base") }
        }
        Text(o.reduceOnly ? "Un ordre exécuté sur la plateforme est définitif. La perte latente de la partie clôturée devient réalisée."
             : "Un ordre exécuté sur la plateforme est définitif. Une position à effet de levier peut être liquidée : la marge, et en marge croisée tout le collatéral du compte, peuvent être perdus.")
            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        BindingProof(digest: a.approval.digest, expiry: o.expiry)
    }

    // MARK: leverage

    @ViewBuilder private func leverage(_ l: LiveLeverageApproval) -> some View {
        let c = l.change
        ReviewLines(lines: [
            .init(label: "Type d’opération", value: "Changement du réglage de levier sur la plateforme", style: .strong),
            .init(label: "Plateforme / réseau", value: "\(c.venue) · \(c.network)", style: .strong),
            .init(label: "Compte", value: c.account, style: .address),
            .init(label: "Instrument", value: c.instrument, style: .strong),
            .init(label: "Nouveau levier", value: "\(c.leverage)×", style: .strong),
            .init(label: "Mode de marge", value: c.marginMode == "cross" ? "croisée (cross) — tout le collatéral du compte garantit la position" : "isolée (isolated)", style: .strong),
            .init(label: "Réglage actuel de la plateforme", value: l.current.map { "\($0.leverage)× (\($0.marginMode))" } ?? "illisible"),
            .init(label: "Autorisation utilisée", value: c.authorizationId),
            .init(label: "Nonce / expiration", value: "\(c.nonce) · expire à \(Self.date(ms: c.expiresAt))"),
        ])
        if let cur = l.current.flatMap({ Int($0.leverage) }), c.leverage > cur {
            Banner(.warning, "Le levier augmente : le prix de liquidation d’une position ouverte sur cet instrument se rapproche du prix actuel.")
        }
        BindingProof(digest: l.approval.digest, expiry: c.expiry)
    }

    // MARK: collateral

    private func depositExtra(_ d: CollateralDepositApproval) -> [ReviewLine] {
        var extra: [ReviewLine] = []
        if let r = d.route {
            extra.append(.init(label: "Route (selon le serveur)", value: "\(r.networkName ?? r.network) → pont \(r.bridge)" + (r.expectedSeconds.map { " · crédit attendu en ≈ \($0) s" } ?? "")))
            if let m = r.venueMinimum { extra.append(.init(label: "Minimum de la plateforme", value: "\(m) USDC — en dessous, les fonds sont perdus", style: .warning)) }
        }
        if let f = d.fee { extra.append(.init(label: "Frais de réseau estimés", value: "\(f.estimate) \(f.symbol) (plafond signé : \(f.max) \(f.symbol))")) }
        if let l = d.liveness { extra.append(.init(label: "Contrôle du pont", value: (l.ok ? "dépôts récents crédités" : "NON CONFIRMÉ") + (l.detail.map { " — \($0)" } ?? "") + (l.checkedAt.map { " · vérifié \(Fmt.relative($0))" } ?? ""), style: l.ok ? .normal : .warning)) }
        if let b = d.venueBalance { extra.append(.init(label: "Solde actuel sur la plateforme", value: b.error.map { "illisible : \($0)" } ?? "\(b.total ?? b.equity ?? "—") USDC")) }
        return extra
    }

    @ViewBuilder private func deposit(_ d: CollateralDepositApproval) -> some View {
        Banner(.warning, "La plateforme crédite l’adresse EXPÉDITRICE : ce dépôt part de l’adresse de ce portefeuille vers le pont épinglé. Il n’est terminé que lorsque la plateforme l’a crédité.")
        TransactionReview(intent: d.intent, digest: d.approval.digest, network: model.network(d.intent.network),
                          ownAddresses: Dictionary((model.accounts?.value.accounts ?? []).map { ($0.network, $0.address) }, uniquingKeysWith: { a, _ in a }), warnings: [], extra: depositExtra(d))
    }

    @ViewBuilder private func withdraw(_ w: CollateralWithdrawApproval) -> some View {
        let x = w.withdrawal
        ReviewLines(lines: [
            .init(label: "Type d’opération", value: "Retrait de collatéral de la plateforme vers ce portefeuille", style: .strong),
            .init(label: "Plateforme / réseau", value: "\(x.venue) · \(x.network)", style: .strong),
            .init(label: "Compte débité", value: x.account, style: .address),
            .init(label: "Destination (votre adresse)", value: x.destination, style: .address),
            .init(label: "Montant demandé", value: "\(FutNum.exact(x.amount)) USDC", style: .strong),
            .init(label: "Frais de la plateforme", value: "\(FutNum.exact(x.fee)) USDC"),
            .init(label: "Vous recevez", value: "\(FutNum.exact(w.receive)) USDC (montant − frais, recalculé par l’app)", style: .strong),
            .init(label: "Horodatage de l’action", value: Self.date(ms: x.time)),
            .init(label: "Expire le", value: Self.date(seconds: x.expiresAt)),
            .init(label: "Identifiant", value: x.withdrawalId),
            .init(label: "Clé du portefeuille", value: x.keyId),
        ] + (w.action.map { [ReviewLine(label: "Action signée pour la plateforme", value: "\($0.type) sur \($0.hyperliquidChain) → \($0.destination), \($0.amount) USDC")] } ?? [])
          + (w.venueBalance.map { [ReviewLine(label: "Solde actuel sur la plateforme", value: $0.error.map { "illisible : \($0)" } ?? "retirable \($0.withdrawable ?? "—") USDC")] } ?? []))
        Text("Le retrait n’est terminé que lorsque ce portefeuille a vu les USDC arriver. Retirer du collatéral rapproche le prix de liquidation des positions ouvertes.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        BindingProof(digest: w.approval.digest, expiry: x.expiry)
    }

    // MARK: risk intent of the account

    @ViewBuilder private func risk(_ r: LiveRiskApproval) -> some View {
        let i = r.intent
        Banner(.warning, i.kind == .resume ? "Lever l’arrêt redonne au compte la possibilité de prendre du nouveau risque."
               : i.kind == .rebase ? "Vous acceptez les positions actuelles de la plateforme comme référence après une divergence."
               : "Ce changement ASSOUPLIT les protections du compte.")
        ReviewLines(lines: [
            .init(label: "Type d’opération", value: i.kind == .resume ? "Levée de l’arrêt du compte" : i.kind == .rebase ? "Acceptation des positions (re-base)" : "Nouvelle politique de risque du compte", style: .strong),
            .init(label: "Plateforme / réseau", value: "\(i.venue) · \(i.network)", style: .strong),
            .init(label: "Compte", value: i.account, style: .address),
            .init(label: "Identifiant du compte", value: i.accountId),
            .init(label: "Autorisation", value: i.authorizationId),
            .init(label: i.kind == .resume ? "Arrêt levé" : "Divergence acceptée", value: i.subject ?? "aucun"),
            .init(label: "Champs assouplis", value: i.loosened.isEmpty ? "aucun" : i.loosened.joined(separator: ", "), style: i.loosened.isEmpty ? .normal : .warning),
            .init(label: "Nonce", value: i.nonce),
        ] + (i.policy.map(Self.policyLines) ?? []))
        BindingProof(digest: r.approval.digest, expiry: i.expiry)
    }

    static func policyLines(_ p: DerivRiskPolicy) -> [ReviewLine] {
        [
            .init(label: "Politique — mode", value: p.mode),
            .init(label: "Instruments permis", value: p.allowedInstruments.isEmpty ? "aucun" : p.allowedInstruments.joined(separator: ", ")),
            .init(label: "Arrêt", value: p.halt ?? "aucun"),
            .init(label: "Levier maximal", value: "\(p.maxLeverage)×"),
            .init(label: "Notionnel max par ordre", value: p.maxOrderNotional),
            .init(label: "Notionnel max par position", value: p.maxPositionNotional),
            .init(label: "Exposition brute max", value: p.maxGrossExposure),
            .init(label: "Collatéral libre minimal", value: p.minFreeCollateral),
            .init(label: "Distance min. à la liquidation", value: "\(p.minLiquidationDistanceBps) pb"),
            .init(label: "Perte quotidienne max", value: p.maxDailyLoss),
            .init(label: "Perte totale max", value: p.maxTotalLoss),
            .init(label: "Ordres par minute / jour", value: "\(p.maxOrdersPerMinute) / \(p.maxOrdersPerDay)"),
            .init(label: "Âge max des données", value: "\(p.maxDataAgeMs) ms"),
            .init(label: "Écart de prix max", value: "\(p.maxDeviationBps) pb"),
            .init(label: "Écart mark / indice max", value: "\(p.maxMarkIndexBps) pb"),
        ]
    }
}
