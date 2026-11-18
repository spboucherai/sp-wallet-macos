// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/Alerts/AlertsText.swift
// Description: French labels of the alerts centre: severities, the catalogue's groups, the subjects an alert can be about, delivery states and parameter names. The sentence of an alert always comes from the Core's catalogue (the backend's own templates); nothing here rewrites its meaning.
import SwiftUI
import SPWalletCore

enum AlertsText {
    static func severity(_ s: AlertSeverity) -> String {
        switch s { case .info: "Information"; case .warning: "Avertissement"; case .critical: "Critique"; case .unknown(let r): "Gravité « \(r) »" }
    }
    static func color(_ s: AlertSeverity) -> Color {
        switch s { case .info: .blue; case .warning, .unknown: Theme.warning; case .critical: Theme.negative }
    }
    static func symbol(_ s: AlertSeverity) -> String {
        switch s { case .info: "info.circle.fill"; case .warning, .unknown: "exclamationmark.triangle.fill"; case .critical: "exclamationmark.octagon.fill" }
    }
    static func group(_ g: AlertGroup) -> String {
        switch g {
        case .transfers: "Transactions"; case .agents: "Agents"; case .derivatives: "Dérivés"; case .security: "Sécurité"; case .system: "Système"
        case .unknown(let r): r
        }
    }
    static func delivery(_ d: AlertDelivery) -> String {
        switch d {
        case .pending: "Pas encore examinée par le serveur pour la notification"
        case .inApp: "Dans l’app seulement (aucun appareil ni webhook configuré sur le serveur)"
        case .stale: "Non notifiée : datait de plus d’une heure quand le serveur l’a examinée"
        case .quiet: "Retenue par les heures calmes"
        case .capped: "Retenue par le plafond horaire"
        case .sent: "Remise aux canaux du serveur (push web, webhook)"
        case .unknown(let r): r
        }
    }
    static func subject(_ s: AlertSubject) -> String {
        let what: String
        switch s.type {
        case "proposal": what = "Opération"; case "agent": what = "Agent"; case "account": what = "Compte de dérivés"; case "network": what = "Réseau"
        case "deposit": what = "Dépôt"; case "plan": what = "Plan"; case "none": return "—"
        default: what = s.type
        }
        return [what, s.id, s.network.map { "réseau \($0)" }].compactMap { $0 }.joined(separator: " · ")
    }
    /// Where the same alert opens in the app (the Core ports the backend's `alertPath`).
    static func destination(_ path: String) -> String {
        if path.hasPrefix("/agents") { return "Agents de trading" }
        if path.hasPrefix("/plan") { return "Échange (plans)" }
        if path.hasPrefix("/futures") { return "Dérivés (comptes)" }
        if path.hasPrefix("/activity") { return "Activité" }
        if path.hasPrefix("/security") { return "Sécurité" }
        if path.hasPrefix("/monitor") { return "Supervision (cet écran)" }
        return "Alertes"
    }

    private static let params: [String: String] = [
        "agent": "Agent", "account": "Compte", "network": "Réseau", "to": "Vers", "from": "De", "what": "Objet", "mode": "Mode", "scope": "Portée", "count": "Occurrences",
        "minutes": "Minutes", "hours": "Heures", "seconds": "Secondes", "bars": "Barres", "interval": "Intervalle", "instrument": "Instrument", "name": "Nom", "loop": "Boucle",
        "pct": "Pourcentage", "positions": "Positions", "state": "État", "reason": "Motif", "amount": "Montant", "symbol": "Actif", "toSymbol": "Actif reçu", "size": "Taille",
        "price": "Prix", "side": "Sens", "steps": "Étapes", "step": "Étape", "ip": "Adresse IP", "seq": "Séquence", "pnl": "Résultat", "label": "Libellé", "device": "Appareil",
        "detail": "Détail", "clientId": "Identifiant client",
    ]
    static func param(_ key: String) -> String { params[key] ?? key }
    /// A parameter as served. `@word` values are vocabulary codes of the backend: the sentence above shows their translation; here the code is shown without its marker.
    static func value(_ v: JSONValue) -> String {
        if case .string(let s) = v { return s.hasPrefix("@") ? String(s.dropFirst()) : (s.isEmpty ? "—" : s) }
        return v.displayText
    }

    /// Title and body in French. A kind this version does not know is shown as its raw code, with nothing guessed.
    static func sentence(_ a: WalletAlert, detail: Bool = true) -> (title: String, body: String) {
        guard AlertCatalog.definition(a.kind) != nil else { return ("Alerte de type « \(a.kind.rawValue) »", "") }
        return a.text(locale: .fr, detail: detail)
    }
}

/// What an alert is about, finer than the catalogue's five groups. Derived from the catalogue's kinds only; two subjects
/// (insufficient balance, high fees) have no kind of their own on the server and are recognised from the reason it returned.
enum AlertsTheme: String, CaseIterable, Identifiable {
    case transactions, positions, orders, errors, insufficientBalance, highFees, rpc, signerFailure, limitExceeded, liquidation, agentState, signerState, security, system
    var id: String { rawValue }

    var label: String {
        switch self {
        case .transactions: "Transactions"; case .positions: "Positions"; case .orders: "Ordres"; case .errors: "Erreurs et échecs"
        case .insufficientBalance: "Solde insuffisant"; case .highFees: "Frais élevés"; case .rpc: "Panne RPC / connecteur"; case .signerFailure: "Panne du signataire"
        case .limitExceeded: "Limite dépassée"; case .liquidation: "Liquidation possible"; case .agentState: "État des agents"; case .signerState: "État du signataire"
        case .security: "Sécurité du compte"; case .system: "Système"
        }
    }
    var derivedFromReason: Bool { self == .insufficientBalance || self == .highFees }

    static func of(_ a: WalletAlert) -> Set<AlertsTheme> {
        var out: Set<AlertsTheme> = []
        switch a.kind {
        case .transferConfirmed, .swapConfirmed, .bridgeConfirmed, .transferStuck, .depositReceived, .planStepReady, .planPaused, .planDone: out = [.transactions]
        case .transferFailed, .swapFailed, .bridgeFailed: out = [.transactions, .errors]
        case .agentOrderFilled: out = [.orders, .agentState]
        case .derivPaperFilled, .derivLiveFilled: out = [.orders]
        case .derivOrderRejected, .derivOrderUnknown: out = [.orders, .errors]
        case .derivPositionOpened, .derivPositionClosed, .derivFunding, .derivDivergence, .derivDivergenceCleared: out = [.positions]
        case .derivMarginWarning, .derivPaperLiquidation, .derivLiveLiquidation: out = [.liquidation, .positions]
        case .derivLossLimit, .derivHalt: out = [.limitExceeded]
        case .agentStoppedLoss, .agentStoppedMandate, .agentMmBreaker, .agentMmRateBudget: out = [.limitExceeded, .agentState]
        case .agentStopped, .agentMmHalted, .agentMmDeadManSwitch, .agentMmSessionEnded, .agentMandateRevoked, .mandateExpiring, .agentResearchSubmitted: out = [.agentState]
        case .agentMmSignerRefusals: out = [.agentState, .signerFailure]
        case .agentDataStale: out = [.agentState, .rpc]
        case .agentSignalFailures, .agentResearchFailed: out = [.agentState, .errors]
        case .derivAssetTableMismatch: out = [.errors]
        case .securitySignerUnreachable, .securityPinMismatch: out = [.signerFailure, .signerState]
        case .securitySignerRefused: out = [.signerFailure]
        case .securitySignerBack, .securitySignerHalted, .securitySignerUnhalted: out = [.signerState]
        case .securityPasskeyAdded, .securityNewDevice, .securityLoginFailed, .securityKillSwitchOn, .securityKillSwitchOff, .securityAuditBroken, .securityPolicyChanged: out = [.security]
        case .connDown, .connUp: out = [.rpc]
        case .systemWorkerFailing: out = [.system, .errors]
        case .systemApiRestarted, .systemBackupMissing, .systemDiskLow, .systemLabSandboxUnavailable, .systemLabSandboxBack, .systemLabSandboxOff, .systemAlertsCapped, .systemTest: out = [.system]
        case .unknown: out = []
        }
        // no dedicated kind on the server: read from the reason text it returned with a failure or a refusal
        if out.contains(.errors) || out.contains(.signerFailure) {
            let reason = ["reason", "detail"].compactMap { a.params[$0]?.stringValue?.lowercased() }.joined(separator: " ")
            if ["insufficient", "not enough", "balance", "solde", "funds"].contains(where: reason.contains) { out.insert(.insufficientBalance) }
            if ["fee", "gas", "frais"].contains(where: reason.contains) { out.insert(.highFees) }
            if ["limit", "limite", "cap ", "ceiling", "plafond"].contains(where: reason.contains) { out.insert(.limitExceeded) }
        }
        return out
    }
}

/// The owner's choice of which new alerts raise a macOS notification (this Mac only; the server's own switches are in Réglages).
enum AlertsNotifyLevel: String, CaseIterable, Identifiable {
    case off, critical, warning, info
    var id: String { rawValue }
    var label: String {
        switch self { case .off: "Aucune"; case .critical: "Critiques seulement"; case .warning: "Avertissements et critiques"; case .info: "Toutes (information comprise)" }
    }
    func allows(_ s: AlertSeverity) -> Bool {
        switch self { case .off: false; case .critical: s >= .critical; case .warning: s >= .warning; case .info: true }
    }
    private static let key = "alertsNotifyLevel", detailKey = "alertsNotifyDetails"
    static var stored: AlertsNotifyLevel {
        get { UserDefaults.standard.string(forKey: key).flatMap(AlertsNotifyLevel.init(rawValue:)) ?? .warning }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
    /// Amounts, prices and reasons in the notification text. Off by default, as on the server: a notification can be read on a locked screen.
    static var showDetails: Bool {
        get { UserDefaults.standard.bool(forKey: detailKey) }
        set { UserDefaults.standard.set(newValue, forKey: detailKey) }
    }
}
