// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Core/Models/ErrorText.swift
// Description: French sentences for the errors of the wallet (API codes, approval refusals). Unknown codes show the server's own message verbatim: nothing is paraphrased into something milder.
import Foundation
import SPWalletCore

enum ErrorText {
    static func approval(_ e: ApprovalError) -> String {
        switch e {
        case .challengeMismatch: "Refusé par l’app : le défi à signer ne correspond pas à l’opération affichée. Rien n’a été signé."
        case .wrongRelyingParty(let s): "Refusé par l’app : l’approbation a été émise pour un autre domaine (\(s ?? "inconnu")). Rien n’a été signé."
        case .userVerificationNotRequired: "Refusé par l’app : l’approbation n’exige pas la vérification de l’utilisateur. Rien n’a été signé."
        case .expired: "La fenêtre d’approbation est expirée. Recommencez."
        case .unsupported(let s): "Cette opération ne peut pas être vérifiée par cette version de l’app (\(s)). Rien n’a été signé."
        case .inconsistent(let s): "Refusé par l’app : l’opération à approuver diffère de ce qui a été demandé (\(s)). Rien n’a été signé."
        }
    }

    static let codes: [String: String] = [
        "offline": "Le portefeuille est injoignable.",
        "unauthenticated": "Session expirée. Reconnectez-vous.",
        "login_failed": "Authentification refusée.",
        "challenge_expired": "La demande a expiré. Réessayez.",
        "csrf": "Requête refusée par le serveur (origine).",
        "rate_limited": "Trop de requêtes. Patientez un instant.",
        "halted": "L’arrêt d’urgence est actif : plus rien ne peut être signé.",
        "signer_unreachable": "Le signataire isolé est injoignable : rien ne peut être signé pour l’instant.",
        "pending_tx": "Une opération précédente sur ce réseau n’est pas encore confirmée. Attendez sa confirmation.",
        "bad_address": "Adresse de destination invalide.",
        "bad_amount": "Montant invalide.",
        "bad_memo": "Mémo ou étiquette de destination invalide.",
        "unsupported_asset": "Cet actif n’est pas pris en charge sur ce réseau.",
        "expired": "La fenêtre d’approbation est expirée. Recommencez.",
        "conflict": "L’opération a changé entre-temps. Rechargez.",
        "simulation_failed": "La simulation de la transaction a échoué.",
        "internal": "Erreur interne du serveur.",
        "hash_mismatch": "Le signataire a répondu pour une autre intention. Rien n’a été diffusé.",
        "quote_moved": "Le prix a bougé depuis la cotation affichée. Rien n’a été préparé.",
        "mainnet_disabled": "Désactivé sur le serveur pour le réseau principal.",
        "execution_disabled": "L’exécution est désactivée sur le serveur.",
    ]

    static func api(_ e: APIError) -> String {
        let known = codes[e.code]
        // policy refusals, insufficient funds, fee ceilings…: the server's sentence carries the figures — keep it
        if let known { return e.message.isEmpty || ["offline", "unauthenticated", "internal", "csrf", "rate_limited"].contains(e.code) ? known : "\(known) — \(e.message)" }
        return e.message.isEmpty ? "Erreur \(e.status) (\(e.code))" : "\(e.message) [\(e.code)]"
    }

    /// Warnings attached to a proposal by the server.
    static func warning(_ code: String) -> String {
        switch code {
        case "new_destination": "Première fois que vous envoyez à cette adresse."
        case "address_poisoning_suspected": "ATTENTION : cette adresse ressemble à une adresse connue (mêmes début et fin) sans être la même. Vérifiez chaque caractère."
        case "contract_destination": "La destination est un contrat, pas un portefeuille."
        case "unfunded_destination": "Le compte de destination n’existe pas encore sur ce réseau."
        default: code
        }
    }

    static func state(_ s: ProposalState, raw: String? = nil) -> String {
        switch s {
        case .draft: "Brouillon"
        case .pendingApproval: "En attente d’approbation"
        case .approved: "Approuvée, signature en cours"
        case .signed: "Signée, non diffusée"
        case .broadcast: "Diffusée, non confirmée"
        case .confirming: "En cours de confirmation"
        case .finalized: "Finalisée"
        case .rejected: "Rejetée"
        case .expired: "Expirée"
        case .failed: "Échouée"
        case .replaced: "Remplacée"
        case .reorged: "Réorganisation de chaîne, à reconfirmer"
        case .notBroadcast: "Signée, NON diffusée (diffusion désactivée)"
        case .unknown: raw ?? "État inconnu"
        }
    }
    static func activityState(_ raw: String) -> String { ProposalState(rawValue: raw).map { state($0, raw: raw) } ?? raw }
}
