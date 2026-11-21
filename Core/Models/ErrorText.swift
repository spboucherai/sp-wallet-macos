// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Core/Models/ErrorText.swift
// Description      : French sentences for the errors of the wallet (API codes,
//                    approval refusals). Unknown codes show the server's own
//                    message verbatim: nothing is paraphrased into something
//                    milder.
// Module           : Core
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
        "policy": "Refusé par les limites du signataire.",
        "vault_unconfirmed": "Le coffre THORChain n’a pas pu être confirmé par assez d’opérateurs indépendants : l’opération est refusée par prudence.",
        "token_account_missing": "Le compte de jetons USDC du portefeuille n’existe pas encore sur Solana.",
        "signer_too_old": "Le signataire en service ne prend pas en charge cette opération.",
        "unsupported_network": "Réseau non pris en charge pour cette opération.",
        "nft_disabled": "Le module NFT est désactivé sur le serveur.",
        "nft_not_found": "NFT introuvable.",
        "mandate_required": "Un mandat approuvé par passkey est requis.",
        "insufficient_gas": "Solde insuffisant pour payer les frais de réseau.",
        "fee_ceiling": "Les frais dépassent le plafond fixé par le signataire.",
        "idempotency_mismatch": "Cette demande a déjà été utilisée pour une autre opération.",
        "bad_state": "L’opération n’est plus dans un état qui permet cette action.",
        "not_found": "Introuvable.",
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
        case "swap_needs_approval": "Une autorisation de dépense (approbation ERC-20 du montant exact) précède l’échange."
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
