// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Components/TransactionReview.swift
// Description: The review of an operation before the passkey prompt. It renders ONLY the fields of the canonical intent whose SHA-256 the app has verified to be the WebAuthn challenge — not the server's summary of it — so what is displayed is what the passkey signs and what the isolated signer will rebuild. Nothing is abbreviated: full addresses, exact base-unit amounts, fee ceiling, expiry.
import SwiftUI
import SPWalletCore

/// One line of a review: label, exact value, and whether it deserves emphasis or a warning colour.
struct ReviewLine: Identifiable {
    enum Style { case normal, strong, address, warning }
    let id = UUID()
    let label: String; let value: String; var style: Style = .normal
}

enum IntentReview {
    static func kindTitle(_ k: Intent.Kind) -> String {
        switch k {
        case .transfer: "Transfert"
        case .swap: "Échange (swap) — sortie livrée à ce portefeuille"
        case .bridge: "Transfert inter-chaînes (Circle CCTP) — de ce portefeuille à lui-même"
        case .xswap: "Échange inter-chaînes natif (THORChain)"
        case .venueDeposit: "Dépôt de collatéral sur une plateforme de dérivés"
        case .gmx: "Ordre GMX v2"
        }
    }

    /// Every value-bearing field of the intent, in reading order. `network` supplies names and the fee coin; unknown → raw identifiers.
    static func lines(_ i: Intent, network n: SPWalletCore.Network?, ownAddresses: [String: String]) -> [ReviewLine] {
        var out: [ReviewLine] = []
        let feeSym = n?.native.symbol ?? "(monnaie native)", feeDec = n?.native.decimals
        func units(_ s: String, _ dec: Int?) -> String { guard let dec, let u = try? BaseUnits(s) else { return s + " (unités de base)" }; return Fmt.amount(u.formatted(decimals: dec)) }
        out.append(.init(label: "Type d’opération", value: kindTitle(i.kind), style: .strong))
        out.append(.init(label: "Réseau", value: "\(n?.name ?? i.network)  (\(i.network), \(i.chainRef))"))
        out.append(.init(label: "Actif", value: i.asset == "native" ? "\(i.symbol) (monnaie native)" : "\(i.symbol) — contrat \(i.asset)"))
        out.append(.init(label: "Montant", value: "\(units(i.amount, i.decimals)) \(i.symbol)", style: .strong))
        out.append(.init(label: "Montant exact", value: "\(i.amount) unités de base (\(i.decimals) décimales)"))
        out.append(.init(label: "Depuis", value: i.from, style: .address))
        let self_ = i.to == i.from || ownAddresses.values.contains(i.to)
        out.append(.init(label: i.kind == .transfer ? "Destinataire" : "Destination de la transaction", value: i.to, style: .address))
        if i.kind == .transfer, self_ { out.append(.init(label: "", value: "La destination est une adresse de ce portefeuille.")) }
        if let m = i.memo { out.append(.init(label: "Mémo / étiquette", value: m.isEmpty ? "(vide)" : m)) }
        // native-coin transfer: the fee comes on top of the amount, in the same coin
        if i.kind == .gmx { out.append(.init(label: "Plafond frais + exécution", value: "\(units(i.maxFee, feeDec)) \(feeSym)")) }
        else { out.append(.init(label: "Frais de réseau maximum", value: "\(units(i.maxFee, feeDec)) \(feeSym)")) }
        if i.asset == "native", i.kind == .transfer, let a = try? BaseUnits(i.amount), let f = try? BaseUnits(i.maxFee) {
            out.append(.init(label: "Total maximum débité", value: "\(Fmt.amount((a + f).formatted(decimals: i.decimals))) \(i.symbol)", style: .strong))
        } else if i.kind == .transfer {
            out.append(.init(label: "Total maximum débité", value: "\(units(i.amount, i.decimals)) \(i.symbol) + \(units(i.maxFee, feeDec)) \(feeSym) de frais", style: .strong))
        }
        if let s = i.swap {
            out.append(.init(label: "Fournisseur", value: s.provider))
            out.append(.init(label: "Actif reçu", value: s.toAsset == "native" ? "monnaie native" : "contrat \(s.toAsset)"))
            out.append(.init(label: "Minimum reçu garanti", value: "\(s.minOut) unités de base de l’actif reçu", style: .strong))
            out.append(.init(label: "Contrat appelé (routeur)", value: s.router, style: .address))
            out.append(.init(label: "Empreinte des données d’appel", value: s.dataHash))
            if s.approveGas != "0" { out.append(.init(label: "Autorisation de dépense", value: "Une approbation ERC-20 du montant exact au routeur précède l’échange (gaz \(s.approveGas)).", style: .warning)) }
        }
        if let b = i.bridge {
            out.append(.init(label: "Réseau de destination", value: "\(b.toNetwork) (domaine CCTP \(b.toDomain))", style: .strong))
            out.append(.init(label: "Bénéficiaire", value: b.recipient ?? i.from, style: .address))
            out.append(.init(label: "Frais Circle maximum", value: "\(units(b.maxFee, i.decimals)) \(i.symbol)"))
            if let a = try? BaseUnits(i.amount), let f = try? BaseUnits(b.maxFee), let m = try? a.subtracting(f) { out.append(.init(label: "Minimum reçu", value: "\(Fmt.amount(m.formatted(decimals: i.decimals))) \(i.symbol)", style: .strong)) }
            out.append(.init(label: "Seuil de finalité", value: String(b.minFinalityThreshold)))
            out.append(.init(label: "Contrats appelés", value: "TokenMessenger \(b.messenger)\nMessageTransmitter \(b.transmitter)", style: .address))
            if b.approveGas != "0" { out.append(.init(label: "Autorisation de dépense", value: "Une approbation du montant exact au TokenMessenger précède le transfert.", style: .warning)) }
        }
        if let x = i.xswap {
            out.append(.init(label: "Fournisseur", value: x.provider))
            out.append(.init(label: "Vous recevez sur", value: "\(x.toNetwork) — actif \(x.toAsset)", style: .strong))
            out.append(.init(label: "Minimum reçu", value: "\(x.minOut) unités de base", style: .strong))
            out.append(.init(label: "Coffre THORChain (destination)", value: x.vault, style: .address))
            out.append(.init(label: "Mémo THORChain", value: x.memo))
            if !x.router.isEmpty { out.append(.init(label: "Contrat appelé (routeur)", value: x.router, style: .address)) }
            out.append(.init(label: "Échéance du dépôt", value: Fmt.dateSeconds(Date(timeIntervalSince1970: TimeInterval(x.expiry)))))
            out.append(.init(label: "Risque", value: "Un échange natif inter-chaînes est irréversible une fois le dépôt envoyé ; en cas d’échec côté THORChain, un remboursement peut être émis moins les frais.", style: .warning))
        }
        if let v = i.venueDeposit {
            out.append(.init(label: "Plateforme", value: "\(v.venue) (\(v.venueNetwork)), route \(v.route)", style: .strong))
            out.append(.init(label: "Contrat du pont", value: v.bridge, style: .address))
            out.append(.init(label: "Minimum accepté", value: "\(units(v.minAmount, i.decimals)) \(i.symbol)"))
        }
        if let g = i.gmx {
            out.append(.init(label: "Action", value: "\(g.action) · \(g.orderType) · \(g.isLong ? "LONG" : "SHORT")", style: .strong))
            out.append(.init(label: "Taille (USD, 30 déc.)", value: g.sizeDeltaUsd))
            out.append(.init(label: "Prix acceptable", value: g.acceptablePrice))
            out.append(.init(label: "Frais d’exécution", value: "\(units(g.executionFee, feeDec)) \(feeSym)"))
            out.append(.init(label: "Marché", value: g.market, style: .address))
            out.append(.init(label: "Contrat appelé", value: g.exchangeRouter, style: .address))
            if let k = g.orderKey { out.append(.init(label: "Ordre visé", value: k)) }
        }
        if let e = i.evm { out.append(.init(label: "Paramètres EVM", value: "nonce \(e.nonce) · gaz \(e.gasLimit) · max \(e.maxFeePerGas) wei/gaz · priorité \(e.maxPriorityFeePerGas)")) }
        if let b = i.btc {
            out.append(.init(label: "Entrées dépensées", value: b.inputs.map { "\($0.txid):\($0.vout) — \($0.value)" }.joined(separator: "\n")))
            out.append(.init(label: "Monnaie rendue / frais", value: "\(b.change) / \(b.fee) (unités de base)"))
        }
        if let s = i.sol { out.append(.init(label: "Paramètres Solana", value: "valide jusqu’au bloc \(s.lastValidBlockHeight) · \(s.computeUnitLimit) CU à \(s.computeUnitPrice) µlamports" + (s.createAta ? " · crée le compte de jetons du destinataire" : ""))) }
        if let x = i.x, !x.isEmpty { out.append(.init(label: "Paramètres de chaîne", value: x.keys.sorted().map { "\($0) = \(x[$0]!.count > 90 ? String(x[$0]!.prefix(90)) + "…(\(x[$0]!.count) car.)" : x[$0]!)" }.joined(separator: "\n"))) }
        out.append(.init(label: "Clé du portefeuille", value: i.keyId))
        out.append(.init(label: "Politique du signataire", value: "version \(i.policyVersion)"))
        return out
    }
}

/// The verified-binding footer shared by every approval sheet.
struct BindingProof: View {
    let digest: Data
    let expiry: Date?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Défi vérifié par cette app", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.positive).font(.callout.weight(.medium))
            Text("Le défi que votre passkey va signer est exactement l’empreinte SHA-256 de l’opération ci-dessus, recalculée sur ce Mac. Le signataire isolé reconstruit la transaction à partir de ces mêmes champs et refuse toute différence.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(digest.map { String(format: "%02x", $0) }.joined()).font(.system(.caption, design: .monospaced)).textSelection(.enabled).foregroundStyle(.secondary)
            if let expiry {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let left = Int(expiry.timeIntervalSince(ctx.date))
                    Text(left > 0 ? "Fenêtre d’approbation : \(left) s" : "Fenêtre d’approbation expirée").font(.caption.weight(.medium)).foregroundStyle(left > 15 ? Color.secondary : Theme.negative).monospacedDigit()
                }
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Theme.positive.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ReviewLines: View {
    let lines: [ReviewLine]
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(lines) { l in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(l.label).foregroundStyle(.secondary).frame(width: 190, alignment: .leading)
                    Group {
                        switch l.style {
                        case .address: Text(l.value).font(Theme.monoSmall)
                        case .strong: Text(l.value).fontWeight(.semibold)
                        case .warning: Label(l.value, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
                        case .normal: Text(l.value)
                        }
                    }.textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// The complete review of an intent-based operation (transfer, swap, bridge, cross-chain swap, venue deposit, GMX order).
struct TransactionReview: View {
    let intent: Intent
    let digest: Data
    let network: SPWalletCore.Network?
    let ownAddresses: [String: String]
    var warnings: [String] = []
    var extra: [ReviewLine] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(warnings, id: \.self) { w in Banner(w == "address_poisoning_suspected" ? .danger : .warning, ErrorText.warning(w)) }
            ReviewLines(lines: IntentReview.lines(intent, network: network, ownAddresses: ownAddresses) + extra)
            if intent.kind == .transfer {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Adresse du destinataire, par groupes de 4 caractères").font(.caption).foregroundStyle(.secondary)
                    Text(Fmt.chunked(intent.to)).font(.system(.title3, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            Text("Une transaction diffusée sur une blockchain est irréversible. Une adresse erronée ou un mauvais réseau signifie la perte des fonds.").font(.callout).foregroundStyle(.secondary)
            BindingProof(digest: digest, expiry: intent.expiry)
        }
    }
}
