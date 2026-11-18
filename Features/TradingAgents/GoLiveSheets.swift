// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/TradingAgents/GoLiveSheets.swift
// Description: The approval sheets of a mandate. They render the fields of the VERIFIED mandate object (never the server's summary): every limit, the allowed assets or instruments, network, provider, slippage, leverage, floor, validity, then what the vault or trading key can and cannot do, and — plainly — what the signer does NOT bound. The Approve button enables only after each risk statement is ticked.
import SwiftUI
import SPWalletCore

/// A titled list of plain statements (what a key can do, cannot do, what is not bounded).
struct StatementList: View {
    let title: String
    let symbol: String
    let color: Color
    let items: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol).font(.callout.weight(.semibold)).foregroundStyle(color)
            ForEach(items, id: \.self) { s in
                HStack(alignment: .firstTextBaseline, spacing: 6) { Text("•").foregroundStyle(color); Text(s).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) }.font(.callout)
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color.opacity(0.3)))
    }
}

/// The canonical field list the passkey commits to, exactly as hashed.
struct CanonicalFields: View {
    let domain: String
    let fields: [(String, String)]
    var body: some View {
        DisclosureGroup("Champs canoniques signés (\(domain)) — \(fields.count) champs") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(fields.enumerated()), id: \.offset) { _, f in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(f.0).font(Theme.monoSmall).foregroundStyle(.secondary).frame(width: 210, alignment: .leading)
                        Text(f.1.isEmpty ? "(vide)" : f.1).font(Theme.monoSmall).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }.padding(.top, 6)
        }
    }
}

enum MandateText {
    static func validity(created: Int, expires: Int) -> String {
        let s = expires - created
        return s % 86_400 == 0 ? "\(s / 86_400) jour(s)" : String(format: "%.1f jour(s)", Double(s) / 86_400)
    }
    static func bps(_ v: Int) -> String { "\(v) points de base (\((Double(v) / 100).formatted(.number.precision(.fractionLength(0...2)))) %)" }
    static func stop(_ c: AgentTradingMandate.StopCondition) -> String {
        switch c {
        case .lossAtLeast(let usd): "perte ≥ \(usd) USD"
        case .drawdownAtLeast(let bps): "repli ≥ \(MandateText.bps(bps))"
        case .consecutiveRejectsAtLeast(let n): "\(n) refus consécutifs"
        case .dataStaleAtLeast(let ms): "données périmées depuis ≥ \(ms / 1000) s"
        case .signerUnreachableAtLeast(let ms): "signataire injoignable depuis ≥ \(ms / 1000) s"
        }
    }
    static func account(_ a: AgentTradingMandate.Account) -> String {
        switch a {
        case .vault(let n, let i, let addr): "coffre n° \(i) sur \(n) — \(addr)"
        case .venueAccount(let v, let n, let acct): "compte \(v) (\(n)) — \(acct)"
        }
    }
}

struct SpotMandateSheet: View {
    let model: AppModel
    let flow: SpotGoLiveFlow
    let approval: SpotMandateApproval
    @State private var ackLoss = false
    @State private var ackEngine = false
    @State private var ackAutonomy = false
    @State private var ackNoPromise = false

    var body: some View {
        let m = approval.mandate, kind = ModeKind(.live)
        SheetScaffold(title: "Approuver le mandat — passage en RÉEL", height: 820) {
            ModeHeaderBand(kind: kind)
            Banner(.danger, "En approuvant, vous autorisez l’agent « \(m.label) » à échanger les fonds de son coffre SANS votre passkey à chaque ordre, dans les bornes ci-dessous, jusqu’à l’expiration ou jusqu’à votre révocation. Aucun rendement n’est promis ; vous pouvez perdre ce que le coffre détient.")
            ReviewLines(lines: lines(m))
            VStack(alignment: .leading, spacing: 6) {
                Text("Plafonds par actif (calculés par cette app à partir du mandat vérifié)").font(.callout.weight(.semibold))
                ForEach(approval.lines) { l in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(l.symbol + (l.isCash ? " (règlement)" : "")).fontWeight(.medium).frame(width: 150, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(l.maxOrder.map { "par ordre : \(Fmt.amount($0)) \(l.symbol)" } ?? "achetable, non vendable sous ce mandat").monospacedDigit()
                            if let d = l.maxDaily { Text("par jour (UTC) : \(Fmt.amount(d)) \(l.symbol)").monospacedDigit() }
                            Text(l.asset).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        Spacer(minLength: 0)
                    }
                }
                Text("Le plafond de la monnaie de règlement est exactement votre limite en USD. Les plafonds des autres actifs sont cette même limite convertie par le serveur au prix de la préparation : ils sont figés dans le mandat et ne suivent plus le prix ensuite.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let g = approval.gasReserve { Field(label: "Réserve de gaz du coffre", value: "\(g.held) \(g.symbol) détenus · \(g.required) \(g.symbol) requis par le serveur") }
            StatementList(title: "Ce que la clé du coffre PEUT faire sous ce mandat", symbol: "checkmark.circle", color: Theme.positive, items: CustodyFacts.spotCan)
            StatementList(title: "Ce qu’elle NE PEUT PAS faire", symbol: "xmark.circle", color: .secondary, items: CustodyFacts.spotCannot)
            StatementList(title: "Ce que le signataire NE BORNE PAS", symbol: "exclamationmark.triangle.fill", color: Theme.negative,
                          items: CustodyFacts.spotNotBounded + (flow.risk.map { ["Limites du moteur (API seulement, hors mandat) : arrêt à −\(AgentCreateForm.plain($0.maxLossPct)) % du capital, exposition ≤ \(AgentCreateForm.plain($0.maxExposurePct)) % du coffre."] } ?? []))
            Text("Budget : ce mandat n’a pas de plafond de capital. Son budget est TOUT ce que le coffre détient sur ce réseau, maintenant et après vos dépôts ultérieurs.").font(.callout.weight(.medium)).fixedSize(horizontal: false, vertical: true)
            CanonicalFields(domain: AgentSpotMandate.domain, fields: m.fields())
            BindingProof(digest: approval.approval.digest, expiry: nil)
            VStack(alignment: .leading, spacing: 8) {
                Text("Confirmations requises").font(.callout.weight(.semibold))
                AckToggle(isOn: $ackLoss, text: "Je comprends que le signataire ne limite pas la perte de marché : tout ce que le coffre détient peut être perdu.")
                AckToggle(isOn: $ackEngine, text: "Je comprends que la limite de perte et la part d’exposition ne sont appliquées que par le moteur de l’API, pas par le signataire.")
                AckToggle(isOn: $ackAutonomy, text: "Je comprends que l’agent négociera sans ma passkey à chaque ordre jusqu’au \(Fmt.date(m.expiry)), et que je peux révoquer le mandat à tout moment, sans passkey.")
                AckToggle(isOn: $ackNoPromise, text: "Je comprends qu’un backtest ou un résultat sur papier est une simulation, jamais une promesse de rendement.")
            }
        } footer: {
            if let e = flow.error { Banner(.danger, e) }
            HStack {
                Button("Annuler — rien n’est approuvé") { flow.cancel() }.disabled(flow.step == .approving)
                Spacer()
                if flow.step == .approving { ProgressView().controlSize(.small); Text("Passkey, puis enregistrement au signataire isolé…").foregroundStyle(.secondary) }
                Button { Task { await flow.approve() } } label: { Label("Approuver le mandat avec la passkey · RÉEL", systemImage: "touchid") }
                    .buttonStyle(.borderedProminent).tint(kind.color).controlSize(.large)
                    .disabled(!(ackLoss && ackEngine && ackAutonomy && ackNoPromise) || flow.step == .approving || !model.canOperate)
            }
        }
        .interactiveDismissDisabled()
    }

    private func lines(_ m: AgentSpotMandate) -> [ReviewLine] {
        [
            ReviewLine(label: "Type d’autorité", value: "Mandat d’échange au comptant du coffre d’un agent", style: .strong),
            ReviewLine(label: "Agent (libellé)", value: m.label),
            ReviewLine(label: "Identifiant du mandat", value: m.mandateId, style: .address),
            ReviewLine(label: "Coffre", value: m.vault, style: .address),
            ReviewLine(label: "Indice / clé du coffre", value: "n° \(m.vaultIndex) · clé \(m.keyId)"),
            ReviewLine(label: "Réseau autorisé", value: "\(approval.networkName ?? model.network(m.network)?.name ?? m.network)  (\(m.network))", style: .strong),
            ReviewLine(label: "Fournisseur autorisé", value: m.provider, style: .strong),
            ReviewLine(label: "Actifs autorisés (\(m.assets.count))", value: m.assets.map { id in approval.lines.first { $0.asset == id }.map { "\($0.symbol) — \(id)" } ?? id }.joined(separator: "\n"), style: .address),
            ReviewLine(label: "Ordres par jour", value: "au plus \(m.maxOrdersPerDay)", style: .strong),
            ReviewLine(label: "Glissement maximal", value: MandateText.bps(m.maxSlippageBps) + " — sortie garantie au moins à 1 − ce taux de la valeur"),
            ReviewLine(label: "Levier", value: "aucun (comptant)"),
            ReviewLine(label: "Limite de perte", value: "AUCUNE dans le mandat — le signataire ne borne pas la perte de marché", style: .warning),
            ReviewLine(label: "Créé le", value: Fmt.dateSeconds(AgentText.seconds(m.createdAt))),
            ReviewLine(label: "Expire le", value: "\(Fmt.dateSeconds(m.expiry)) — validité \(MandateText.validity(created: m.createdAt, expires: m.expiresAt))", style: .strong),
            ReviewLine(label: "Stratégie (SHA-256 du code)", value: m.strategySha256, style: .address),
        ]
    }
}

struct PerpLiveSheet: View {
    let model: AppModel
    let flow: PerpGoLiveFlow
    let approval: PerpLiveApproval
    @State private var ackJurisdiction = false
    @State private var ackLoss = false
    @State private var ackAPI = false
    @State private var ackAutonomy = false
    @State private var ackNoPromise = false

    var body: some View {
        let m = approval.mandate, t = approval.tradingMandate, kind = ModeKind(.live, liveNetwork: m.network)
        SheetScaffold(title: "Approuver le mandat de dérivés — passage en RÉEL", width: 800, height: 840) {
            ModeHeaderBand(kind: kind)
            Banner(m.isMainnet ? .danger : .warning, m.isMainnet
                   ? "ARGENT RÉEL. En approuvant, vous autorisez l’agent à négocier des perpétuels à effet de levier sur votre compte de la plateforme, sans passkey à chaque ordre. Le collatéral peut être perdu, liquidation comprise. Aucun rendement n’est promis."
                   : "Réseau de TEST de la plateforme : les ordres sont réellement signés et envoyés, mais l’argent est fictif.")
            if let w = approval.warning { Banner(.warning, w) }
            Text("1 · Mandat enregistré et appliqué par le signataire isolé").font(.headline)
            ReviewLines(lines: signerLines(m))
            Text("2 · Mandat de trading (dont les champs appliqués par l’API seulement)").font(.headline)
            ReviewLines(lines: tradingLines(t))
            StatementList(title: "Ce que la clé de trading PEUT faire sous ce mandat", symbol: "checkmark.circle", color: Theme.positive, items: CustodyFacts.perpCan)
            StatementList(title: "Ce qu’elle NE PEUT PAS faire", symbol: "xmark.circle", color: .secondary, items: CustodyFacts.perpCannot)
            StatementList(title: "Ce que le signataire NE BORNE PAS", symbol: "exclamationmark.triangle.fill", color: Theme.negative, items: CustodyFacts.perpNotBounded)
            serverStatements
            VStack(alignment: .leading, spacing: 6) {
                Text("Avis de juridiction (son empreinte est dans le mandat)").font(.callout.weight(.semibold))
                Text(approval.acknowledgement.text).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                if let v = approval.acknowledgement.version { Text("Version \(v)\(approval.acknowledgement.source.map { " · \($0)" } ?? "")").font(.caption).foregroundStyle(.secondary) }
            }
            CanonicalFields(domain: AgentVenueMandate.domain, fields: m.fields())
            CanonicalFields(domain: AgentTradingMandate.domain, fields: t.fields())
            Text("Première demande de passkey — le mandat du signataire").font(.callout.weight(.semibold))
            BindingProof(digest: approval.signer.digest, expiry: nil)
            Text("Seconde demande de passkey — l’intention qui lie le mandat de trading complet (empreinte \(approval.binding.object.tradingMandateHash)) au mandat du signataire").font(.callout.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            BindingProof(digest: approval.binding.digest, expiry: approval.binding.object.expiry)
            VStack(alignment: .leading, spacing: 8) {
                Text("Confirmations requises").font(.callout.weight(.semibold))
                AckToggle(isOn: $ackJurisdiction, text: "J’ai lu l’avis de juridiction ci-dessus et je l’accepte.")
                AckToggle(isOn: $ackLoss, text: "Je comprends que le collatéral du compte peut être perdu, liquidation comprise, et que le levier (jusqu’à ×\(m.maxLeverage)) amplifie les pertes.")
                AckToggle(isOn: $ackAPI, text: "Je comprends que la taille des positions, l’exposition, les limites de perte et la cadence par minute ne sont vérifiées que par l’API, pas par le signataire.")
                AckToggle(isOn: $ackAutonomy, text: "Je comprends que l’agent négociera sans ma passkey jusqu’au \(Fmt.date(m.expiry)), et que je peux l’arrêter et révoquer le mandat à tout moment, sans passkey.")
                AckToggle(isOn: $ackNoPromise, text: "Je comprends qu’un backtest ou un résultat sur papier est une simulation, jamais une promesse de rendement.")
            }
        } footer: {
            if let e = flow.error { Banner(.danger, e) }
            HStack {
                Button("Annuler — rien n’est approuvé") { flow.cancel() }.disabled(flow.step == .approving)
                Spacer()
                if flow.step == .approving { ProgressView().controlSize(.small); Text("Deux demandes de passkey, puis le signataire isolé…").foregroundStyle(.secondary) }
                Button { Task { await flow.approve(acknowledged: ackJurisdiction) } } label: { Label("Approuver avec la passkey (2 demandes) · \(kind.short)", systemImage: "touchid") }
                    .buttonStyle(.borderedProminent).tint(kind.color).controlSize(.large)
                    .disabled(!(ackJurisdiction && ackLoss && ackAPI && ackAutonomy && ackNoPromise) || flow.step == .approving || !model.canOperate)
            }
        }
        .interactiveDismissDisabled()
    }

    @ViewBuilder private var serverStatements: some View {
        let blocks: [(String, JSONValue?)] = [("Appliqué par le signataire (énoncé du serveur)", approval.enforcedBySigner), ("Cru sur parole par le signataire (énoncé du serveur)", approval.trustedBySigner),
                                               ("NON appliqué par le signataire (énoncé du serveur)", approval.notEnforced), ("Fin de mandat et fermeture (énoncé du serveur)", approval.windDown),
                                               ("Champ par champ : qui applique quoi (énoncé du serveur)", approval.enforcement)]
        ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
            if let v = b.1, !v.isNull {
                VStack(alignment: .leading, spacing: 5) {
                    Text(b.0).font(.callout.weight(.semibold))
                    if let a = v.arrayValue { JSONList(items: a, limit: 60) } else { JSONFacts(value: v, depth: 3) }
                }
            }
        }
    }

    private func signerLines(_ m: AgentVenueMandate) -> [ReviewLine] {
        [
            ReviewLine(label: "Type d’autorité", value: "Mandat de dérivés d’une stratégie automatique", style: .strong),
            ReviewLine(label: "Identifiant du mandat", value: m.mandateId, style: .address),
            ReviewLine(label: "Agent", value: m.agentId, style: .address),
            ReviewLine(label: "Plateforme / réseau", value: "\(m.venue) · \(m.network)\(m.isMainnet ? " — ARGENT RÉEL" : " — réseau de test")", style: .strong),
            ReviewLine(label: "Compte de la plateforme", value: m.account, style: .address),
            ReviewLine(label: "Clé de trading", value: "\(m.agentAddress)\nclé \(m.keyId) · autorisation \(m.authorizationId)", style: .address),
            ReviewLine(label: "Instruments autorisés", value: m.instruments.map { "\($0.instrument) — levier ≤ ×\($0.maxLeverage) · position ≤ \(Fmt.amount($0.maxPositionNotional)) USDC" }.joined(separator: "\n"), style: .strong),
            ReviewLine(label: "Levier maximal", value: "×\(m.maxLeverage)", style: .strong),
            ReviewLine(label: "Notionnel par ordre", value: "≤ \(Fmt.amount(m.maxOrderNotional)) USDC", style: .strong),
            ReviewLine(label: "Exposition brute", value: "≤ \(Fmt.amount(m.maxGrossExposure)) USDC"),
            ReviewLine(label: "Ordres", value: "≤ \(m.maxOrdersPerHour) par heure · ≤ \(m.maxOrdersPerDay) par jour", style: .strong),
            ReviewLine(label: "Volume quotidien", value: "≤ \(Fmt.amount(m.maxDailyTurnover)) USDC (plafond par ordre × ordres par jour, calculé par le serveur)"),
            ReviewLine(label: "Plancher de valeur du compte", value: "\(Fmt.amount(m.floorEquity)) USDC — en dessous, seuls annulations et ordres réducteurs sont signés", style: .strong),
            ReviewLine(label: "Écart de prix maximal", value: MandateText.bps(m.maxPriceDeviationBps)),
            ReviewLine(label: "Créé le", value: Fmt.dateSeconds(AgentText.seconds(m.createdAt))),
            ReviewLine(label: "Expire le", value: "\(Fmt.dateSeconds(m.expiry)) — validité \(MandateText.validity(created: m.createdAt, expires: m.expiresAt))", style: .strong),
            ReviewLine(label: "Après l’expiration", value: "annulations et ordres réducteurs seulement, jusqu’au \(Fmt.dateSeconds(m.windDownEnd))"),
            ReviewLine(label: "Stratégie (SHA-256 du code)", value: m.strategySha256, style: .address),
            ReviewLine(label: "Empreinte de l’avis", value: m.ackSha256, style: .address),
        ]
    }

    private func tradingLines(_ t: AgentTradingMandate) -> [ReviewLine] {
        [
            ReviewLine(label: "Mode", value: t.mode, style: .strong),
            ReviewLine(label: "Titulaire", value: "\(t.principalKind):\(t.principalId)", style: .address),
            ReviewLine(label: "Comptes", value: t.accounts.map(MandateText.account).joined(separator: "\n"), style: .address),
            ReviewLine(label: "Plateformes / réseaux", value: "\(t.venues.joined(separator: ", ")) · \(t.networks.joined(separator: ", "))"),
            ReviewLine(label: "Marchés autorisés", value: t.instruments.joined(separator: ", ")),
            ReviewLine(label: "Types de marché / d’ordre", value: "\(t.marketKinds.joined(separator: ", ")) · \(t.orderTypes.joined(separator: ", "))"),
            ReviewLine(label: "Budget (capital maximal)", value: "\(Fmt.amount(t.maxCapitalUsd)) USD", style: .strong),
            ReviewLine(label: "Plafond par ordre", value: "\(Fmt.amount(t.maxOrderNotionalUsd)) USD", style: .strong),
            ReviewLine(label: "Plafond de position", value: "\(Fmt.amount(t.maxPositionNotionalUsd)) USD"),
            ReviewLine(label: "Levier maximal", value: "×\(t.maxLeverage)", style: .strong),
            ReviewLine(label: "Limite de perte quotidienne", value: "\(Fmt.amount(t.maxDailyLossUsd)) USD — appliquée par l’API", style: .strong),
            ReviewLine(label: "Plancher de fonds propres", value: "\(Fmt.amount(t.floorEquityUsd)) USD", style: .strong),
            ReviewLine(label: "Cadence", value: "≤ \(t.perMinute) / minute · ≤ \(t.perHour) / heure · ≤ \(t.perDay) / jour"),
            ReviewLine(label: "Glissement maximal", value: MandateText.bps(t.maxSlippageBps)),
            ReviewLine(label: "Frais maximaux", value: "\(Fmt.amount(t.maxFeeUsd)) USD"),
            ReviewLine(label: "Conditions d’arrêt", value: t.stopConditions.isEmpty ? "aucune" : t.stopConditions.map(MandateText.stop).joined(separator: "\n")),
            ReviewLine(label: "Valide du / au", value: "\(Fmt.dateSeconds(AgentText.seconds(t.notBefore))) → \(Fmt.dateSeconds(t.expiry))", style: .strong),
            ReviewLine(label: "Libellé", value: t.label),
        ]
    }
}
