// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Components/SecurityIndicator.swift
// Description: A compact, always-truthful summary of whether signing is possible: signer reachable, halt state, session, connection.
import SwiftUI
import SPWalletCore

struct SecurityIndicator: View {
    let model: AppModel
    var compact = false

    enum Level { case ok, degraded, blocked, unknown
        var color: Color { switch self { case .ok: Theme.positive; case .degraded: Theme.warning; case .blocked: Theme.negative; case .unknown: .secondary } }
        var symbol: String { switch self { case .ok: "checkmark.shield.fill"; case .degraded: "exclamationmark.shield.fill"; case .blocked: "xmark.shield.fill"; case .unknown: "shield" } }
    }
    static func assess(_ model: AppModel) -> (Level, String) {
        if model.phase == .offlineBrowse { return (.unknown, "Hors connexion — lecture seule") }
        if model.isOffline { return (.degraded, "Portefeuille injoignable") }
        guard let p = model.portfolio?.value else { return (.unknown, "État inconnu") }
        if p.halted == true { return (.blocked, "Arrêt d’urgence actif") }
        if p.signer?.reachable == false || p.halted == nil { return (.degraded, "Signataire injoignable") }
        return (.ok, "Signataire isolé joignable")
    }
    var body: some View {
        let (level, text) = Self.assess(model)
        HStack(spacing: 6) {
            Image(systemName: level.symbol).foregroundStyle(level.color)
            Text(text).font(compact ? .caption : .callout).lineLimit(1)
        }
        .help("Les clés privées ne quittent jamais la machine du signataire ; ce Mac n’en détient aucune.")
        .accessibilityElement(children: .combine)
    }
}
