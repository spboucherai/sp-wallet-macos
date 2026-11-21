// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Features/Swap/SwapView.swift
// Description      : Swapping: the pair, the amount and the tolerance; the live
//                    comparison of every provider's quote with the one route
//                    this wallet can really execute put forward (the others are
//                    labelled comparison-only, with the reason); the review of
//                    the verified intent (router, calldata fingerprint,
//                    guaranteed minimum, exact-amount spend approval,
//                    simulation); the passkey; then the honest tracking —
//                    approval transaction, swap transaction, and the received
//                    amount only once it was read from the chain. Native
//                    cross-chain pairs (THORChain) use the same screen and say
//                    so.
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

struct SwapView: View {
    let model: AppModel
    @State private var flow: SwapFlow?

    var body: some View {
        Page("Échanger", subtitle: "Les cotations comparent plusieurs fournisseurs ; seule la route exécutable par ce portefeuille peut être préparée, puis approuvée par passkey.") {
            if let flow {
                if !model.canOperate { Banner(.warning, "Échange impossible pour l’instant : session ou portefeuille indisponible. Aucune cotation n’est demandée hors connexion.") }
                if SwapText.isSimulatedServer(model) { Banner(.warning, "SERVEUR DE TEST : les transactions sont signées mais ne sont PAS diffusées. Aucun échange réel n’aura lieu depuis ce serveur.") }
                if model.portfolio?.value.halted == true { Banner(.danger, "Arrêt d’urgence actif : le signataire ne signe plus rien.") }
                if let e = flow.loadError { Banner(.danger, "Capacités d’échange illisibles : \(e)") }
                if flow.step == .tracking, let t = flow.tracker {
                    SwapTrackingCard(model: model, flow: flow, tracker: t)
                } else if flow.loaded {
                    SwapFormCard(model: model, flow: flow)
                    SwapQuoteSection(model: model, flow: flow)
                } else if flow.loadError == nil { ProgressView("Lecture des actifs et des fournisseurs…") }
            } else { ProgressView() }
        }
        .task {
            if flow == nil { flow = SwapFlow(model: model) }
            if flow?.loaded != true { await flow?.load() }
        }
        .task(id: flow?.quoteKey) { await flow?.runQuotes() }
        .task(id: flow?.tracker?.proposal.id) { await flow?.tracker?.follow() }
        .sheet(isPresented: Binding(get: { flow?.step == .review || flow?.step == .approving }, set: { _ in })) {
            if let flow, let op = flow.operation { SwapReviewSheet(model: model, flow: flow, operation: op) }
        }
    }
}

// MARK: - Form

private struct SwapFormCard: View {
    let model: AppModel
    @Bindable var flow: SwapFlow

    var body: some View {
        Card("Paire et montant") {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Vous vendez").font(.caption).foregroundStyle(.secondary)
                    SwapAssetPicker(model: model, label: "Actif vendu", assets: flow.assets, selection: $flow.fromKey, exclude: flow.toKey)
                }
                Button { flow.flip() } label: { Image(systemName: "arrow.left.arrow.right") }.help("Inverser la paire").padding(.bottom, 10)
                    .accessibilityLabel("Inverser la paire")
                VStack(alignment: .leading, spacing: 4) {
                    Text("Vous achetez").font(.caption).foregroundStyle(.secondary)
                    SwapAssetPicker(model: model, label: "Actif acheté", assets: flow.assets, selection: $flow.toKey, exclude: flow.fromKey)
                }
            }
            .disabled(flow.step != .form)
            if let f = flow.from, let t = flow.to { pairFacts(f, t) }
            HStack {
                TextField("Montant vendu", text: $flow.amount, prompt: Text("0.0")).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                Text(flow.from?.symbol ?? "").foregroundStyle(.secondary)
                Button("Max") { flow.setMax() }.disabled(flow.balance?.isAvailable != true)
                    .help(flow.from?.asset == "native" ? "Solde entier : les frais de réseau devront en être déduits, le serveur refusera sinon." : "Solde entier de cet actif")
                Spacer()
                balanceText
            }
            .disabled(flow.step != .form)
            if let a = flow.parsedAmount, !a.isZero, let f = flow.from, let p = model.price(f.symbol) {
                HStack(spacing: 6) {
                    Text(Fmt.fiat(a.approximate(decimals: f.decimals) * p.value(in: model.currency), model.currency)).foregroundStyle(.secondary).font(.callout)
                    ProvenanceTag(p: p.stale ? .stale : .estimate)
                }
            }
            slippage
            if let p = flow.formProblem, !flow.amount.isEmpty { Text(p).font(.callout).foregroundStyle(Theme.warning) }
        }
    }

    @ViewBuilder private var balanceText: some View {
        if flow.from == nil { EmptyView() }
        else if let b = flow.balance, b.isAvailable { Text("Solde : \(model.settings.hideBalances ? "••••" : Fmt.amount(b.display)) \(b.symbol)").monospacedDigit().foregroundStyle(.secondary) }
        else if flow.balance != nil { Text("Solde indisponible (lecture de chaîne en échec)").foregroundStyle(Theme.negative) }
        else { Text("Solde : —").foregroundStyle(.secondary) }
    }

    @ViewBuilder private func pairFacts(_ f: SwapAsset, _ t: SwapAsset) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(f.network == t.network ? "Réseau : \(f.networkName ?? f.network)" : "Réseaux : \(f.networkName ?? f.network) → \(t.networkName ?? t.network)").font(.callout)
            if f.asset != "native" { Text("Contrat vendu : \(f.asset)").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled) }
            if t.asset != "native" { Text("Contrat acheté : \(t.asset)").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled) }
        }
        let hint = flow.capabilityHint
        if flow.isBridgePair {
            Banner(.info, "USDC → USDC entre deux réseaux est un transfert Circle CCTP : il se prépare dans « Pont inter-chaînes » (barre latérale), avec ses deux vitesses et leurs frais. Les cotations ci-dessous ne servent qu’à comparer.")
        } else if flow.isNativeCrossChain {
            Banner(.info, "Échange inter-chaînes natif par THORChain : un dépôt de l’actif vendu vers le coffre THORChain, puis un paiement sortant vers l’adresse de ce portefeuille sur \(t.networkName ?? t.network). Irréversible une fois le dépôt envoyé. Le coffre doit être confirmé à l’unanimité par au moins \(flow.xswapInfo?.minOperators.map(String.init) ?? "3") opérateurs THORNode : sinon rien n’est préparé (échec fermé)." + (f.decimals > 8 ? " THORChain ne crédite que 8 décimales : le montant est tronqué à 8 décimales par le serveur." : ""))
        } else if hint.isEmpty, f.key != t.key {
            Banner(.warning, f.network == t.network
                   ? "Ce portefeuille n’exécute pas d’échange sur \(f.networkName ?? f.network) : les cotations de cette paire sont des comparaisons seulement."
                   : "Aucune exécution directe pour cette paire inter-réseaux. Un parcours en plusieurs étapes est peut-être possible : voir « DeFi » → Parcours multi-étapes.")
        }
    }

    private var slippage: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Tolérance de glissement").foregroundStyle(.secondary)
                ForEach(SwapFlow.slippagePresets, id: \.self) { b in
                    Button(SwapText.bps(b)) { flow.setSlippage(bps: b) }.buttonStyle(.bordered).controlSize(.small)
                        .tint(flow.slippageBps == b ? Theme.accent : nil)
                }
                TextField("%", text: $flow.slippageText).textFieldStyle(.roundedBorder).frame(width: 64).multilineTextAlignment(.trailing)
                    .accessibilityLabel("Tolérance de glissement en pourcentage")
                Text("%").foregroundStyle(.secondary)
            }
            .disabled(flow.step != .form)
            Text("Le minimum reçu garanti est calculé avec cette tolérance ; sous ce minimum, la transaction échoue plutôt que de s’exécuter. Valeur par défaut du serveur : \(SwapText.bps(flow.isNativeCrossChain ? SwapFlow.defaultNativeSlippageBps : SwapFlow.defaultSlippageBps)) ; le serveur refuse toute valeur hors de 0,01 % – 3 %.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let b = flow.slippageBps, b > 100 { Text("Tolérance élevée : vous acceptez de recevoir jusqu’à \(SwapText.bps(b)) de moins que la cotation.").font(.caption).foregroundStyle(Theme.warning) }
        }
    }
}

// MARK: - Quotes

private struct SwapQuoteSection: View {
    let model: AppModel
    @Bindable var flow: SwapFlow
    @State private var selection: SwapRoute.ID?

    var body: some View {
        switch flow.quotePhase {
        case .idle:
            if flow.from != nil, flow.to != nil, flow.formProblem == nil, !model.canOperate { EmptyView() }
            else { Card { EmptyState(symbol: "arrow.left.arrow.right", title: "Entrez une paire et un montant", detail: "Les cotations sont une lecture : rien n’est préparé ni signé tant que vous n’avez pas demandé la préparation puis approuvé avec la passkey.") } }
        case .failed(let message):
            Card("Cotations") {
                Banner(.danger, message)
                HStack { Spacer(); Button("Réessayer") { flow.refreshQuotes() } }
            }
        case .loading, .done:
            executableCard
            if !flow.routes.isEmpty { comparisonCard }
            if !flow.answers.isEmpty { answersCard }
        }
    }

    // The route the action executes — never the top-ranked quote of a comparison-only provider.
    @ViewBuilder private var executableCard: some View {
        Card("Route exécutable par ce portefeuille", trailing: AnyView(HStack(spacing: 8) {
            if flow.quotePhase == .loading { ProgressView().controlSize(.small); Text("Cotations en cours…").font(.caption).foregroundStyle(.secondary) }
            else if let at = flow.quotedAt { Text("Cotée \(Fmt.relative(at))").font(.caption).foregroundStyle(.secondary) }
            Button("Rafraîchir") { flow.refreshQuotes() }.controlSize(.small).disabled(flow.step != .form)
        })) {
            if let r = flow.executableRoute {
                TimelineView(.periodic(from: .now, by: 5)) { ctx in
                    let expired = flow.isExpired(r, now: ctx.date)
                    VStack(alignment: .leading, spacing: 10) {
                        hero(r)
                        RouteDetail(model: model, flow: flow, route: r)
                        if expired { Banner(.warning, "Cette cotation a expiré. Rafraîchissez avant de préparer.") }
                        if flow.isBridgePair { EmptyView() } else {
                            HStack {
                                Spacer()
                                if flow.step == .preparing { ProgressView().controlSize(.small); Text("Route ferme, simulation, limites du signataire…").font(.callout).foregroundStyle(.secondary) }
                                Button(SwapText.isSimulatedServer(model) ? "Préparer et vérifier (serveur de test)…" : "Préparer et vérifier…") { Task { await flow.prepare() } }
                                    .buttonStyle(.borderedProminent).controlSize(.large)
                                    .disabled(flow.formProblem != nil || !model.canOperate || flow.step != .form || expired)
                            }
                            Text("Préparer ne signe rien : le serveur demande une route ferme, vérifie le routeur et les données d’appel, simule, contrôle les limites du signataire, puis l’app vérifie que le défi de la passkey est l’empreinte de l’opération affichée. L’échange n’a lieu qu’après votre approbation sur l’écran suivant.")
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } else if flow.quotePhase == .loading {
                Text("En attente de la réponse de l’exécuteur…").foregroundStyle(.secondary)
            } else {
                noExecutable
            }
            if let e = flow.error { Banner(.danger, e) }
        }
    }

    @ViewBuilder private var noExecutable: some View {
        let executors = (flow.pairExecutors ?? []).filter { $0 != "cctp" }
        if flow.reachable == false {
            Banner(.warning, "Aucun fournisseur activé n’annonce cette paire.")
        } else if executors.isEmpty {
            Banner(.warning, flow.isBridgePair ? "Cette paire se traite dans « Pont inter-chaînes »." : "Le serveur n’indique aucun exécuteur pour cette paire : rien ici ne peut être exécuté par ce portefeuille. Les routes ci-dessous sont des comparaisons de prix seulement.")
        } else {
            Banner(.warning, "L’exécuteur de cette paire (\(executors.map { SwapText.provider($0, providers: flow.providers, execution: flow.execution) }.joined(separator: ", "))) n’a renvoyé aucune route pour l’instant. Rien ne peut être préparé ; réessayez.")
        }
    }

    private func hero(_ r: SwapRoute) -> some View {
        let toSym = flow.to?.symbol ?? r.path.last?.symbol ?? ""
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(Fmt.amount(r.amountOutDisplay, maxFraction: 8)) \(toSym)").font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit().textSelection(.enabled)
                ProvenanceTag(p: .estimate, text: "Estimation de la cotation")
                if SwapText.isSimulatedServer(model) { ProvenanceTag(p: .simulated, text: "Serveur de test") }
            }
            Text("Minimum reçu si la cotation est tenue : \(Fmt.amount(r.minAmountOutDisplay, maxFraction: 8)) \(toSym) — le minimum réellement garanti est celui de l’opération préparée, affiché avant l’approbation.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var comparisonCard: some View {
        let rows = flow.sortedRoutes
        let chosen = rows.first { $0.id == selection }
        return Card("Comparaison des cotations (\(rows.count))") {
            Text("Beaucoup de fournisseurs ne sont interrogés que pour comparer les prix. Seules les lignes « Exécutable » peuvent être préparées par ce portefeuille ; c’est le serveur qui le déclare, à partir de ses contrats revus.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Table(rows, selection: $selection) {
                TableColumn("Fournisseur") { r in Text(r.providers.map { SwapText.provider($0, providers: flow.providers, execution: flow.execution) }.joined(separator: " + ")) }.width(min: 120, ideal: 160)
                TableColumn("Reçu estimé") { r in Text(Fmt.amount(r.amountOutDisplay, maxFraction: 8)).monospacedDigit() }.width(min: 110, ideal: 140)
                TableColumn("Minimum") { r in Text(Fmt.amount(r.minAmountOutDisplay, maxFraction: 8)).monospacedDigit().foregroundStyle(.secondary) }.width(min: 110, ideal: 140)
                TableColumn("Impact prix") { r in Text(SwapText.bps(r.priceImpactBps)).monospacedDigit() }.width(76)
                TableColumn("Délai") { r in Text(SwapText.duration(r.estimatedSeconds)) }.width(min: 70, ideal: 90)
                TableColumn("Risque") { r in Text(SwapText.risk(r.risk?.level)).foregroundStyle(r.risk?.level == .high ? Theme.negative : r.risk?.level == .medium ? Theme.warning : .secondary) }.width(60)
                TableColumn("Exécution") { r in
                    if r.statedExecutor != nil { Label("Exécutable", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.positive) }
                    else { Text("Comparaison seulement").foregroundStyle(.secondary) }
                }.width(min: 150, ideal: 170)
            }
            .frame(height: CGFloat(min(rows.count, 10)) * 28 + 36)
            if let r = chosen {
                Divider()
                Text("Détail de la cotation sélectionnée").font(.headline)
                if r.statedExecutor == nil { Banner(.info, SwapText.notExecutable(r)) }
                RouteDetail(model: model, flow: flow, route: r)
            } else { Text("Sélectionnez une ligne pour voir sa route, ses frais et ses contrats.").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private var answersCard: some View {
        Card("Réponses des fournisseurs") {
            ForEach(Array(flow.answers.enumerated()), id: \.offset) { _, a in
                HStack {
                    Text(SwapText.provider(a.provider, providers: flow.providers, execution: flow.execution)).frame(width: 190, alignment: .leading)
                    Text(SwapText.providerAnswer(a)).foregroundStyle(.secondary)
                    Spacer()
                    if let ms = a.ms { Text("\(Int(ms)) ms").monospacedDigit().foregroundStyle(.tertiary) }
                }.font(.callout)
            }
            if let n = flow.providers?.needsKey, !n.isEmpty {
                Text("Non interrogés faute de clé d’API sur le serveur : \(n.map { SwapText.provider($0, providers: flow.providers) }.joined(separator: ", ")).").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Everything a quoted route says: price, impact, tolerance, route steps and venues, contracts, fees, time, risk.
private struct RouteDetail: View {
    let model: AppModel
    let flow: SwapFlow
    let route: SwapRoute

    var body: some View {
        let r = route
        VStack(alignment: .leading, spacing: 7) {
            Field(label: "Fournisseur", value: r.providers.map { SwapText.provider($0, providers: flow.providers, execution: flow.execution) }.joined(separator: " + ")
                  + (r.statedExecutor != nil ? "  — exécuté par ce portefeuille" : "  — comparaison seulement"))
            if let p = indicativePrice { Field(label: "Prix indicatif", value: p) }
            Field(label: "Impact de prix estimé", value: r.priceImpactBps.map { SwapText.bps($0) } ?? "non communiqué par le fournisseur")
            Field(label: "Tolérance de la cotation", value: SwapText.bps(r.card?.toleranceBps))
            Field(label: "Minimum reçu (cotation)", value: "\(Fmt.amount(r.minAmountOutDisplay)) \(r.path.last?.symbol ?? "")")
            Field(label: "Délai estimé", value: SwapText.duration(r.estimatedSeconds))
            if let steps = r.steps, !steps.isEmpty { Field(label: "Route", value: steps.enumerated().map { stepText($0.offset, $0.element) }.joined(separator: "\n")) }
            let contracts = (r.steps ?? []).flatMap { $0.contracts ?? [] }
            if !contracts.isEmpty { Field(label: "Contrats", value: contracts.map { "\($0.role) · \(model.network($0.network)?.name ?? $0.network)\n\($0.address)" }.joined(separator: "\n"), mono: true) }
            Field(label: "Frais", value: feesText)
            if let v = r.valuation {
                Field(label: "Valorisation (USD)", value: "entrée \(SwapText.usd(v.inUsd)) · sortie \(SwapText.usd(v.outUsd)) · frais en sus \(SwapText.usd(v.extraFeesUsd))" + ((v.unpricedFees ?? 0) > 0 ? " · certains frais sans prix ne sont pas comptés" : ""))
            }
            if let risk = r.risk {
                Field(label: "Risque", value: SwapText.risk(risk.level) + (risk.flags.isEmpty ? "" : " — " + risk.flags.map { $0.code + ($0.detail.map { " (\($0))" } ?? "") }.joined(separator: " ; ")))
            }
            if let a = r.atomic { Field(label: "Atomicité", value: a ? "Une seule transaction : tout ou rien." : "Plusieurs étapes : pas atomique.") }
            if r.statedExecutor != nil, let e = r.executability?.reason { Field(label: "Vérification", value: e) }
            if let exp = r.expiresAt ?? r.card?.expiresAt { Field(label: "Validité de la cotation", value: "jusqu’à \(Fmt.dateSeconds(Date(timeIntervalSince1970: Double(exp) / 1000)))") }
        }
    }

    /// Output per unit of input, from the quote's own figures: an estimate, labelled as such.
    private var indicativePrice: String? {
        guard let f = route.path.first, let t = route.path.last, let ain = route.amountIn ?? route.card?.amountIn,
              let i = try? BaseUnits(ain), let o = try? BaseUnits(route.amountOut), !i.isZero else { return nil }
        let p = o.approximate(decimals: t.decimals) / i.approximate(decimals: f.decimals)
        guard p.isFinite, p > 0 else { return nil }
        return "≈ \(p.formatted(.number.precision(.significantDigits(1...8)))) \(t.symbol) pour 1 \(f.symbol) (estimation, frais inclus dans la sortie)"
    }

    private func stepText(_ k: Int, _ s: SwapRoute.Step) -> String {
        let nets = s.from.network == s.to.network ? (s.from.networkName ?? s.from.network) : "\(s.from.networkName ?? s.from.network) → \(s.to.networkName ?? s.to.network)"
        let venues = (s.via ?? []).isEmpty ? "" : " — via \((s.via ?? []).joined(separator: ", "))"
        return "\(k + 1). \(s.kind) · \(SwapText.provider(s.provider, providers: flow.providers, execution: flow.execution)) · \(s.from.symbol) → \(s.to.symbol) · \(nets)\(venues)"
    }

    private var feesText: String {
        let fees = route.fees ?? []
        guard !fees.isEmpty else { return "Aucune ligne de frais communiquée par le fournisseur (les frais de réseau fermes sont affichés à la préparation)." }
        return fees.map { f in
            let kind: String = switch f.kind { case "network": "Réseau"; case "protocol": "Protocole"; case "provider": "Fournisseur"; case "bridge": "Pont"; case "affiliate": "Affiliation"; default: f.kind }
            let amount = f.display.map { "\(Fmt.amount($0, maxFraction: 8)) \(f.symbol ?? "")" } ?? "montant non communiqué"
            return "\(kind) : \(amount)" + (f.usd.map { " (\(SwapText.usd($0)))" } ?? "") + (f.includedInOutput == true ? " — déjà déduit de la sortie" : " — en sus") + (f.estimated == true ? " — estimé" : "")
        }.joined(separator: "\n")
    }
}

// MARK: - Review

private struct SwapReviewSheet: View {
    let model: AppModel
    let flow: SwapFlow
    let operation: ApprovableOperation

    var body: some View {
        OperationReviewSheet(model: model, title: operation.intent.kind == .xswap ? "Vérifier et approuver l’échange inter-chaînes" : "Vérifier et approuver l’échange",
                             operation: operation, notices: notices, extra: extra, busy: flow.step == .approving, error: flow.error,
                             onReject: { Task { await flow.reject() } }, onApprove: { Task { await flow.approve() } })
    }

    private var notices: [(Banner.Kind, String)] {
        var out: [(Banner.Kind, String)] = []
        if let a = OperationReviewSheet.spendApproval(operation.intent, model: model) { out.append(a) }
        if operation.intent.kind == .xswap {
            out.append((.info, "Le signataire isolé redemande lui-même à ses opérateurs THORNode si le coffre ci-dessous est authentique : sans unanimité d’au moins trois opérateurs, il refuse de signer (échec fermé) et rien ne part."))
        }
        return out
    }

    private var extra: [ReviewLine] { OperationReviewSheet.contextLines(model: model, operation: operation) }
}

// MARK: - Tracking

private struct SwapTrackingCard: View {
    let model: AppModel
    let flow: SwapFlow
    let tracker: OperationTracker

    var body: some View {
        let p = tracker.proposal
        Card(p.kind == "xswap" ? "Suivi de l’échange inter-chaînes" : "Suivi de l’échange", trailing: SwapText.isSimulatedServer(model) ? AnyView(ProvenanceTag(p: .simulated, text: "Serveur de test")) : nil) {
            OperationHeadline(proposal: p, completion: tracker.completion)
            Field(label: "Vendu", value: "\(Fmt.amount(p.amountDisplay)) \(p.symbol) · \(p.networkName ?? p.network)")
            if let s = try? p.swapSection() { swapFacts(p, s) }
            else if p.swap != nil { Banner(.warning, "La section d’échange de cette opération est illisible par cette version de l’app.") }
            if p.kind == "xswap" {
                if let x = try? p.xswapSection() { xswapFacts(p, x) }
                else { Banner(.warning, "La section inter-chaînes de cette opération est illisible par cette version de l’app.") }
            }
            if let e = p.error { Banner(p.state.isFailure || p.state == .notBroadcast ? .danger : .warning, e) }
            if let e = tracker.readError { Banner(.warning, "Dernière lecture de l’état en échec : \(e)") }
            if let e = flow.error { Banner(.danger, e) }
            if let ex = try? p.executionStatus() { Divider(); ExecutionTimeline(model: model, status: ex) }
            Divider()
            StateHistory(history: tracker.history)
            HStack {
                if p.kind == "xswap", !tracker.isSettled {
                    Button("Vérifier maintenant") { Task { await flow.refreshNow() } }.disabled(flow.refreshing || !model.canOperate)
                        .help("Demande au serveur de regarder tout de suite l’état côté THORChain. Ne signe rien.")
                }
                Spacer()
                Button(tracker.isSettled ? "Nouvel échange" : "Nouvel échange (le suivi continue dans Activité)") { flow.reset() }
            }
        }
    }

    @ViewBuilder private func swapFacts(_ p: Proposal, _ s: SwapSection) -> some View {
        Field(label: "Fournisseur", value: SwapText.provider(s.provider, providers: flow.providers, execution: flow.execution))
        Field(label: "Sortie attendue", value: "\(Fmt.amount(s.expectedOutDisplay)) \(s.toSymbol) (estimation)")
        Field(label: "Minimum garanti", value: "\(Fmt.amount(s.minOutDisplay)) \(s.toSymbol)")
        if p.kind == "swap" {
            if let r = s.receivedDisplay {
                HStack { Field(label: "Reçu", value: "\(Fmt.amount(r)) \(s.toSymbol)", emphasis: true); ProvenanceTag(p: .verified) }
            } else {
                Field(label: "Reçu", value: p.state == .finalized ? "Lecture du montant sur la chaîne en cours…" : "— (connu seulement une fois l’échange finalisé et lu sur la chaîne)")
            }
        }
        if s.needsApproval == true || s.approvalTxid != nil {
            TxField(label: "Autorisation ERC-20", txid: s.approvalTxid ?? "(pas encore diffusée)", state: approvalState(s.approvalState))
        }
        TxField(label: p.kind == "xswap" ? "Dépôt (source)" : "Transaction d’échange", txid: p.txid, explorer: p.explorer, state: ErrorText.state(p.state))
        if let c = p.confirmations, p.txid != nil { Field(label: "Confirmations", value: String(c)) }
    }

    private func approvalState(_ s: String?) -> String {
        switch s { case "pending": "en attente"; case "sent": "diffusée, non confirmée"; case "confirmed": "confirmée"; case nil: "aucune"; case let o?: o }
    }

    @ViewBuilder private func xswapFacts(_ p: Proposal, _ x: XSwapSection) -> some View {
        Field(label: "Étape", value: SwapText.xswapStage(x.stage), emphasis: true)
        Field(label: "Destination", value: "\(x.toSymbol) sur \(x.toNetworkName ?? x.toNetwork)")
        if let h = x.hold { Banner(x.isComplete ? .danger : .warning, SwapText.hold(h) + (x.holdDetail.map { "\nServeur : \($0)" } ?? "")) }
        if x.refundPlanned == true, !x.isRefunded { Banner(.warning, "THORChain annonce un remboursement de l’actif source.") }
        Field(label: "Coffre THORChain", value: x.vault, mono: true)
        Field(label: "Mémo", value: x.memo, mono: true)
        TxField(label: x.outKind == "refund" ? "Remboursement" : "Paiement sortant", txid: x.outTxid, explorer: x.outExplorer)
        if let r = x.receivedDisplay {
            HStack { Field(label: "Reçu", value: "\(Fmt.amount(r)) \(x.toSymbol)", emphasis: true); if x.isComplete { ProvenanceTag(p: .verified) } }
            if x.receivedBelowMinimum { Banner(.danger, "Reçu, mais moins que le minimum approuvé (\(Fmt.amount(x.minOutDisplay)) \(x.toSymbol)).") }
        } else if !x.isRefunded {
            Field(label: "Reçu", value: "— (connu seulement quand ce portefeuille voit lui-même le paiement sortant)")
        }
        if let r = x.refundedDisplay { Field(label: "Remboursé", value: "\(Fmt.amount(r)) \(p.symbol)", emphasis: true) }
        Field(label: "Délai estimé", value: SwapText.duration(x.estimatedSeconds))
    }
}
