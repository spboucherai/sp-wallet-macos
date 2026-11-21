// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : App/DevSelfTest.swift
// Description      : DEVELOPMENT VARIANT ONLY: scripted end-to-end checks of
//                    the SIGNED app against the local throwaway stack (real
//                    API, real isolated signer process, test keys, no real
//                    funds). Results: <container>/Library/Application
//                    Support/SPWallet/selftest.json.
// Module           : App
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

#if SPW_DEV
import Foundation
import SPWalletCore

@MainActor enum DevSelfTest {
    struct Result: Codable { let name: String; let ok: Bool; let detail: String }
    static var results: [Result] = []
    static func check(_ name: String, _ ok: Bool, _ detail: String = "") { results.append(Result(name: name, ok: ok, detail: detail)); log.info("selftest \(ok ? "PASS" : "FAIL", privacy: .public) \(name, privacy: .public) \(detail, privacy: .public)") }

    static func run(model: AppModel) async {
        results = []
        check("session.signed-in", model.phase == .signedIn, "\(model.phase)")
        await model.refreshAll()
        check("networks.loaded", (model.networks?.value.count ?? 0) >= 20, "\(model.networks?.value.count ?? 0) networks")
        check("accounts.from-signer", model.accounts?.value.signerReachable == true && !(model.accounts?.value.accounts.isEmpty ?? true), "\(model.accounts?.value.accounts.count ?? 0) addresses")
        check("portfolio.loaded", model.portfolio != nil && model.portfolio?.fromCache == false)
        check("portfolio.no-invented-balance", model.portfolio?.value.balances.allSatisfy { $0.amount != nil || $0.error != nil } ?? false)
        check("security.signer-reachable", model.security?.value.signer.reachable == true)
        check("security.not-halted", model.security?.value.signer.halted == false)
        // the session token is in the keychain, not in defaults or files
        check("session.token-in-keychain", KeychainTokenStore(service: AppEnvironment.keychainService).load() != nil)

        // --- transfer: wrong inputs are refused before anything is prepared
        let flow = SendFlow(model: model)
        flow.network = "base"; flow.asset = "native"; flow.to = "0x70997970C51812dc3A010C7d01b50e0d17dc79C9"; flow.amount = "0.001"
        check("send.bad-checksum-refused-locally", flow.formProblem != nil, flow.formProblem ?? "")
        flow.to = model.address(on: "base") ?? ""
        check("send.own-address-refused", flow.formProblem != nil, flow.formProblem ?? "")
        flow.to = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"; flow.amount = "0.0000000000000000001"
        check("send.too-many-decimals-refused", flow.formProblem != nil, flow.formProblem ?? "")

        // --- transfer on the local fork (only when the stack was started with `up-fork`: 1 fake ETH on a local Base fork)
        let funded = model.portfolio?.value.balances.first { $0.network == "base" && $0.asset == "native" }?.isNonZero == true
        if funded {
            // a fresh random destination: well-known test addresses carry code on mainnet and are refused as contracts
            flow.to = "0x" + (0..<20).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
            flow.amount = "0.001"
            await flow.prepare()
            check("send.prepared-and-verified", flow.step == .review && flow.approval != nil, flow.error ?? "")
            if let a = flow.approval {
                check("send.intent-matches-form", a.intent.to == flow.addressCheck?.normalized && a.intent.amount == "1000000000000000" && a.intent.network == "base" && a.intent.kind == .transfer)
                check("send.challenge-is-intent-hash", a.approval.options.challengeData == a.approval.digest)
                // a tampered intent must not verify against the same challenge
                var j = a.intent.served; if case .object(var o) = j { o["to"] = .string("0x000000000000000000000000000000000000dEaD"); j = .object(o) }
                let forged = try? Intent(served: j)
                let rejected: Bool = { guard let forged else { return true }; do { _ = try ApprovalBinding.verify(forged, options: a.approval.options, rpId: model.configuration.rpId); return false } catch { return true } }()
                check("send.tampered-intent-refused", rejected)
                // the owner dismisses the passkey sheet: nothing is signed, the proposal stays pending
                DevPasskey.refuse = true; await flow.approve(); DevPasskey.refuse = false
                let still = try? await model.transfers.proposal(a.proposal.id)
                check("send.cancelled-passkey-signs-nothing", flow.step == .review && still?.state == .pendingApproval, "\(String(describing: still?.state))")
                await flow.approve()
                check("send.approved-tracking", flow.step == .tracking, flow.error ?? "")
                var last: ProposalState?
                for _ in 0..<150 { last = flow.tracked?.state; if last?.isTerminal == true { break }; try? await Task.sleep(for: .seconds(1)) }
                check("send.terminal-state-from-chain", last == .finalized || last == .notBroadcast, "\(String(describing: last)) history=\(flow.history.map { $0.1.rawValue })")
                check("send.never-success-before-finalized", flow.history.filter { $0.1.isSuccess }.count <= 1 && flow.history.last?.1 == last)
                // replaying the same assertion-bearing approval is refused by the server
                do { _ = try await model.transfers.approve(a, with: model.authenticator); check("send.replay-refused", false) } catch { check("send.replay-refused", true, model.describe(error)) }
            }
        } else {
            flow.amount = "0.001"
            check("send.over-balance-refused-locally", flow.formProblem != nil, flow.formProblem ?? "")
            // and by the server, when asked directly
            do { _ = try await model.transfers.draft(TransferRequest(network: "base", asset: "native", to: "0x70997970C51812dc3A010C7d01b50e0d17dc79C8", amount: "0.001"), idempotencyKey: APIClient.newIdempotencyKey()); check("send.unfunded-refused-by-server", false, "a draft was created") }
            catch { check("send.unfunded-refused-by-server", true, model.describe(error)) }
        }

        // --- emergency halt is NOT exercised here on purpose when other tests follow; run with -spwSelfTestHalt YES
        if UserDefaults.standard.bool(forKey: "spwSelfTestHalt") {
            do { try await model.wallet.emergencyHalt(); await model.refreshAll()
                check("halt.engaged", model.security?.value.signer.halted == true && model.portfolio?.value.halted == true)
                let f2 = SendFlow(model: model); f2.network = "base"; f2.asset = "native"; f2.to = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"; f2.amount = "0.0001"
                await f2.prepare()
                check("halt.blocks-transfers", f2.step == .form && f2.error != nil, f2.error ?? "")
            } catch { check("halt.engaged", false, model.describe(error)) }
        }

        // --- offline: snapshots exist and survive a sign-out without erase
        let snap: Snapshot<Portfolio>? = await SnapshotStore.shared.load("portfolio")
        check("offline.snapshot-written", snap != nil)
        await model.signOut(eraseLocalData: false)
        check("signout.session-closed", model.phase == .signedOut && KeychainTokenStore(service: AppEnvironment.keychainService).load() == nil)
        check("offline.data-kept-for-consultation", model.hasSnapshots && model.portfolio != nil)
        do { _ = try await model.wallet.portfolio(); check("signout.api-refuses", false) } catch { check("signout.api-refuses", true) }
        await model.signIn()
        check("signin.again", model.phase == .signedIn)

        let url = AppEnvironment.supportDirectory.appendingPathComponent("selftest.json")
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted]
        try? enc.encode(results).write(to: url)
        log.info("selftest done: \(results.filter(\.ok).count)/\(results.count)")
    }
}
#endif
