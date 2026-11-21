// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Features/TradingAgents/GoLiveFlow.swift
// Description      : Going real = approving a mandate with the passkey. Two
//                    state machines (spot vault mandate; perp venue mandate
//                    with its two prompts) built on the Core's verified
//                    approvals: the mandate is parsed strictly, compared with
//                    the limits the owner entered, and its hash must be the
//                    WebAuthn challenge before any sheet opens. After any
//                    failed submission the approval is discarded and the
//                    agent's real state is read — the same challenge is never
//                    signed twice.
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

import Foundation
import SPWalletCore

/// What the isolated signer bounds and what it does not, as written in the custody ADR (docs/adr/0001-custody.md of the backend).
enum CustodyFacts {
    static let spotCan = [
        "Échanger, par un seul fournisseur et sur un seul réseau, entre les actifs listés ci-dessus, sans passkey par ordre.",
        "Rester sous le plafond par ordre et le volume quotidien de chaque actif, le nombre d’ordres par jour et la garde de glissement, jusqu’à l’expiration.",
        "Renvoyer les fonds du coffre vers VOTRE propre adresse (sans limite de montant, même sous arrêt d’urgence).",
    ]
    static let spotCannot = [
        "Payer une autre adresse que la vôtre : un coffre ne paie que son propriétaire.",
        "Négocier un actif hors liste, passer par un autre fournisseur ou un autre réseau.",
        "Dépasser les plafonds du mandat, ou signer quoi que ce soit après l’expiration ou la révocation.",
    ]
    static let spotNotBounded = [
        "La perte de marché de ce que détient le coffre n’est PAS bornée par le signataire : tout ce que vous y déposez peut perdre de la valeur.",
        "La limite de perte et la part d’exposition de l’agent sont appliquées par le moteur de l’API seulement ; un écart de prix peut les dépasser et une API compromise n’y est pas tenue.",
        "L’identité de la stratégie (empreinte du code) est vérifiée par l’API seulement : le signataire ne peut pas savoir quel code demande un ordre.",
        "Une API compromise pourrait utiliser ce mandat à tout moment, jusqu’à ses bornes, tant qu’il est en vigueur (au plus 90 jours). Le gaz du coffre peut être dépensé.",
    ]
    static let perpCan = [
        "Signer des ordres, des annulations et des changements de levier sur CE compte de la plateforme, pour les instruments listés, sans passkey par ordre.",
        "Dans les bornes du mandat : notionnel par ordre, ordres par heure et par jour, rotation quotidienne, levier au plus celui du mandat, valeur du compte au moins égale au plancher (lue par le signataire lui-même).",
        "Après la fin du mandat : seulement des annulations et des ordres réducteurs, pendant 24 heures.",
    ]
    static let perpCannot = [
        "Retirer, transférer ou approuver une autre clé : la clé de trading ne peut que négocier.",
        "Négocier un instrument hors liste, ou augmenter le risque une fois la valeur du compte sous le plancher.",
    ]
    static let perpNotBounded = [
        "La taille des positions, l’exposition brute, les limites de perte, la distance de liquidation et la cadence par minute sont vérifiées par le moteur de risque de l’API : une API compromise n’y est pas tenue.",
        "L’empreinte de la stratégie et l’identité de l’agent sont vérifiées par l’API seulement.",
        "Le collatéral du compte peut être perdu, liquidation comprise. Un écart de prix peut franchir le plancher avant que le signataire ne refuse.",
        "Une API compromise pourrait utiliser ce mandat jusqu’à ses bornes tant qu’il est en vigueur (au plus 30 jours).",
    ]
}

@MainActor @Observable final class SpotGoLiveFlow {
    enum Step: Equatable { case idle, preparing, review, approving, done }
    let model: AppModel
    let api: AgentsAPI
    private(set) var step: Step = .idle
    private(set) var approval: SpotMandateApproval?
    /// The engine-side loss limit of the agent at preparation, shown as NOT enforced by the signer.
    private(set) var risk: SpotAgentRisk?
    private(set) var result: Agent?
    var error: String?

    init(model: AppModel) { self.model = model; api = AgentsAPI(model.client) }

    func prepare(_ d: SpotAgentDetail) async {
        guard step == .idle, model.canOperate else { return }
        error = nil; step = .preparing
        do {
            guard let net = model.network(d.agent.network) else { throw ApprovalError.unsupported("le réseau \(d.agent.network) n’est pas dans le registre de ce portefeuille") }
            let expectation = try SpotMandateExpectation(detail: d, network: net)
            approval = try await api.prepareSpotMandate(agentId: d.agent.id, expecting: expectation)
            risk = d.agent.spotRisk
            step = .review
        } catch { self.error = model.describe(error); step = .idle }
    }

    func approve() async {
        guard let a = approval, step == .review else { return }
        error = nil; step = .approving
        do {
            result = try await api.approveSpotMandate(a, with: model.authenticator)
            approval = nil; step = .done
            Notifier.post(title: "Mandat approuvé", body: "L’agent « \(a.mandate.label) » est en mode RÉEL sous mandat.")
        } catch PasskeyError.cancelled { step = .review }
        catch {
            // never sign the same challenge twice: read what the server says the agent is now
            let message = model.describe(error)
            if case .spot(let d)? = try? await api.detail(a.agentId), d.agent.mode == .live, d.mandateStatus?.active == true { result = d.agent; approval = nil; step = .done }
            else { approval = nil; step = .idle; self.error = "\(message) L’approbation est abandonnée : préparez un nouveau mandat pour réessayer." }
        }
    }

    func cancel() { approval = nil; error = nil; step = .idle }
    func finish() { result = nil; step = .idle }
}

@MainActor @Observable final class PerpGoLiveFlow {
    enum Step: Equatable { case idle, preparing, review, approving, done }
    let model: AppModel
    let api: AgentsAPI
    let agentId: String
    private(set) var readiness: PerpLiveReadiness?
    private(set) var readinessError: String?
    private(set) var loading = false
    var accountId = ""
    /// Validity asked for, typed by the owner: never the server's "longest possible".
    var daysText = ""
    private(set) var step: Step = .idle
    private(set) var approval: PerpLiveApproval?
    private(set) var result: PerpAgentDetail?
    var error: String?

    init(model: AppModel, agentId: String) { self.model = model; self.agentId = agentId; api = AgentsAPI(model.client) }

    var days: Int? { guard let d = Int(daysText.trimmingCharacters(in: .whitespaces)), (1...AgentVenueMandate.maxDays).contains(d) else { return nil }; if let m = readiness?.proposal?.maxDays ?? readiness?.steps.account.authorization?.maxMandateDays, d > m { return nil }; return d }

    func load() async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        do {
            let r = try await api.perpLiveReadiness(agentId, account: accountId.isEmpty ? nil : accountId, locale: "fr", days: days)
            readiness = r; readinessError = nil
            if accountId.isEmpty, let a = r.accountId { accountId = a }
        } catch { readinessError = model.describe(error) }
    }

    func prepare(agent: Agent) async {
        guard step == .idle, model.canOperate, let days else { return }
        error = nil; step = .preparing
        do {
            // the checklist is read again for exactly this account and these days: the expectation is built from what is on screen
            let r = try await api.perpLiveReadiness(agentId, account: accountId, locale: "fr", days: days)
            readiness = r
            let expectation = try PerpLiveExpectation(agent: agent, readiness: r, days: days)
            approval = try await api.preparePerpLive(expecting: expectation, locale: "fr")
            step = .review
        } catch { self.error = model.describe(error); step = .idle }
    }

    func approve(acknowledged: Bool) async {
        guard let a = approval, step == .review, acknowledged else { return }
        error = nil; step = .approving
        do {
            result = try await api.approvePerpLive(a, acknowledged: true, with: model.authenticator)
            approval = nil; step = .done
            Notifier.post(title: "Mandat de dérivés approuvé", body: "L’agent est en mode RÉEL sur le compte \(Fmt.short(a.mandate.account)) (\(a.mandate.network)).")
        } catch PasskeyError.cancelled { step = .review }
        catch {
            let message = model.describe(error)
            if case .perp(let d)? = try? await api.detail(a.agentId), d.agent.mode == .live, d.live?.active == true { result = d; approval = nil; step = .done }
            else { approval = nil; step = .idle; self.error = "\(message) L’approbation est abandonnée : relisez la liste de contrôle et préparez un nouveau mandat pour réessayer." }
            await load()
        }
    }

    func cancel() { approval = nil; error = nil; step = .idle }
    func finish() { result = nil; step = .idle }
}
