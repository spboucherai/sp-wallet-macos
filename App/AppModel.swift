// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: App/AppModel.swift
// Description: The app's state: session phase, connectivity, and the read-only data every screen shares (networks, addresses, portfolio, activity, security). It never holds a key or a seed; the only secret it touches is the session token, which lives in the keychain.
import Foundation
import Network
import OSLog
import SPWalletCore

let log = Logger(subsystem: AppEnvironment.keychainService, category: "app")

/// A value with where it comes from: fresh from the server, or a local snapshot with its date.
struct Sourced<T: Sendable>: Sendable {
    var value: T
    var fetchedAt: Date
    var fromCache: Bool
}

@MainActor @Observable final class AppModel {
    enum Phase: Equatable {
        case launching
        /// The wallet has no owner passkey yet: setup is done on the signer's terms, not from this app (except the development stack).
        case setupRequired
        case signedOut
        case signedIn
        /// Read-only consultation of the last synchronized data, without a session. No operation is possible.
        case offlineBrowse
    }

    let configuration: APIConfiguration
    let client: APIClient
    let auth: AuthAPI
    let wallet: WalletAPI
    let transfers: TransfersAPI
    let authenticator: PasskeyAuthenticator
    let lock = AppLock()

    private(set) var phase: Phase = .launching
    /// The Mac has a network path. False = certainly offline; true says nothing about the wallet being reachable.
    private(set) var pathOnline = true
    /// The last request to the wallet failed for a transport reason.
    private(set) var serverUnreachable = false
    private(set) var busy = false
    var gateMessage: String?

    private(set) var networks: Sourced<[SPWalletCore.Network]>?
    private(set) var accounts: Sourced<Accounts>?
    private(set) var portfolio: Sourced<Portfolio>?
    private(set) var activity: Sourced<[ActivityItem]>?
    private(set) var security: Sourced<SecurityOverview>?
    private(set) var health: Sourced<HealthReady>?
    private(set) var addressBook: [AddressBookEntry] = []
    /// Until the server answers: its own defaults (French, CAD, balances shown, prices on).
    private(set) var settings: WalletSettings = try! APICoding.decoder().decode(WalletSettings.self, from: Data(#"{"locale":"fr","currency":"CAD","hideBalances":false,"prices":true}"#.utf8))
    private(set) var hasSnapshots = false

    private var monitor: NWPathMonitor?
    private var pollTask: Task<Void, Never>?
    private var eventsTask: Task<Void, Never>?
    private let snapshots = SnapshotStore.shared

    var isOffline: Bool { !pathOnline || serverUnreachable }
    /// Operations (anything that prepares, approves or changes something) need a live session and a reachable wallet.
    var canOperate: Bool { phase == .signedIn && !isOffline }
    var currency: FiatCurrency { settings.currency }

    init() {
        configuration = AppEnvironment.configuration
        client = APIClient(configuration: configuration, tokens: KeychainTokenStore(service: AppEnvironment.keychainService))
        auth = AuthAPI(client); wallet = WalletAPI(client); transfers = TransfersAPI(client)
        #if SPW_DEV
        authenticator = DevPasskey(origin: configuration.originHeader)
        #else
        authenticator = SystemPasskeyAuthenticator()
        #endif
    }

    // MARK: - Lifecycle

    func start() async {
        guard monitor == nil else { return }
        let m = NWPathMonitor(); monitor = m
        m.pathUpdateHandler = { [weak self] path in
            let ok = path.status == .satisfied
            Task { @MainActor in
                guard let self, self.pathOnline != ok else { return }
                self.pathOnline = ok
                if ok, self.phase == .signedIn { await self.refreshAll() }
            }
        }
        m.start(queue: DispatchQueue(label: "spw.path"))
        eventsTask = Task { [weak self] in
            guard let self else { return }
            for await e in await self.client.events() { if e == .unauthenticated { self.sessionLost() } }
        }
        await loadSnapshots()
        await resolvePhase()
    }

    private func resolvePhase() async {
        do {
            let s = try await auth.state()
            serverUnreachable = false
            if s.setupRequired { phase = .setupRequired }
            else if s.authenticated { await enterSignedIn() }
            else { phase = .signedOut }
        } catch {
            noteTransport(error)
            phase = .signedOut
            gateMessage = isOffline ? "Le portefeuille est injoignable. Vérifiez la connexion, ou consultez les dernières données synchronisées." : describe(error)
        }
    }

    func retryConnection() async { gateMessage = nil; await resolvePhase() }

    func signIn() async {
        guard !busy else { return }
        busy = true; gateMessage = nil; defer { busy = false }
        do {
            try await auth.login(with: authenticator)
            serverUnreachable = false
            await enterSignedIn()
        } catch PasskeyError.cancelled { gateMessage = nil }
        catch { noteTransport(error); gateMessage = describe(error) }
    }

    /// The shell appears at once (with the local snapshot when there is one); the first reads complete in the background.
    private func enterSignedIn() async {
        phase = .signedIn
        startPolling()
        Task { await refreshAll() }
    }

    func signOut(eraseLocalData: Bool) async {
        pollTask?.cancel(); pollTask = nil
        await auth.logout()
        if eraseLocalData { await eraseLocal() }
        phase = .signedOut; gateMessage = nil
    }

    func revokeAllSessions() async throws {
        try await auth.revokeAllSessions()
        pollTask?.cancel(); pollTask = nil
        phase = .signedOut; gateMessage = "Toutes les sessions ont été révoquées."
    }

    private func sessionLost() {
        guard phase == .signedIn else { return }
        pollTask?.cancel(); pollTask = nil
        phase = .signedOut
        gateMessage = "La session a expiré (30 minutes d’inactivité ou 12 heures). Reconnectez-vous avec votre passkey."
    }

    /// Read-only consultation of the snapshots; the Mac's owner is verified first.
    func browseOffline() async {
        guard hasSnapshots else { return }
        if AppLock.available { await lock.unlockForBrowse(); if lock.browseDenied { return } }
        phase = .offlineBrowse
    }
    func leaveOfflineBrowse() async { phase = .signedOut; await resolvePhase() }

    func eraseLocal() async {
        await snapshots.eraseAll()
        networks = nil; accounts = nil; portfolio = nil; activity = nil; security = nil; health = nil; addressBook = []; hasSnapshots = false
    }

    #if SPW_DEV
    /// Development stack only: enrol the software passkey as the owner with the stack's one-time setup token.
    func devSetup(token: String) async {
        busy = true; defer { busy = false }
        do {
            struct Options: Decodable, Sendable { let challengeId: String; let options: PasskeyCreationOptions }
            let o: Options = try await client.post("/auth/setup/options")
            let reg = try await authenticator.register(o.options, rpId: configuration.rpId)
            struct Body: Encodable, Sendable { let challengeId: String; let response: PasskeyRegistration; let setupToken: String; let label: String }
            let _: OKResponse = try await client.post("/auth/setup/verify", body: Body(challengeId: o.challengeId, response: reg, setupToken: token, label: "SP Wallet Dev"))
            await enterSignedIn()
        } catch { gateMessage = describe(error) }
    }
    #endif

    // MARK: - Data

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self, self.phase == .signedIn, !Task.isCancelled else { return }
                // nothing is fetched while the app is in the background or the Mac is offline
                guard AppActivity.isActive, self.pathOnline else { continue }
                tick += 1
                await self.refreshPortfolio()
                if tick % 2 == 0 { await self.refreshActivity() }
                if tick % 4 == 0 { await self.refreshHealth() }
            }
        }
    }

    func refreshAll() async {
        guard phase == .signedIn else { return }
        async let a: Void = refreshStatic()
        async let b: Void = refreshPortfolio()
        async let c: Void = refreshActivity()
        async let d: Void = refreshSecurity()
        async let e: Void = refreshHealth()
        _ = await (a, b, c, d, e)
    }

    private func fetch<T: Codable & Sendable>(_ key: String, _ call: @Sendable () async throws -> T) async -> Sourced<T>? {
        do {
            let v = try await call()
            serverUnreachable = false
            await snapshots.save(v, as: key); hasSnapshots = true
            return Sourced(value: v, fetchedAt: Date(), fromCache: false)
        } catch { noteTransport(error); return nil }
    }

    func refreshStatic() async {
        let w = wallet
        if let v = await fetch("networks", { try await w.networks() }) { networks = v } else { networks?.fromCache = true }
        if let v = await fetch("accounts", { try await w.accounts() }) { accounts = v } else { accounts?.fromCache = true }
        if let s = try? await w.settings() { settings = s; await snapshots.save(s, as: "settings") }
        if let b = try? await w.addressBook() { addressBook = b; await snapshots.save(b, as: "addressbook") }
    }
    func refreshPortfolio() async {
        let w = wallet
        if let v = await fetch("portfolio", { try await w.portfolio() }) { portfolio = v; await ValueHistory.shared.record(v.value, currency: settings.currency) } else { portfolio?.fromCache = true }
    }
    func refreshActivity() async {
        let w = wallet
        if let v = await fetch("activity", { try await w.activity(limit: 500) }) { activity = v } else { activity?.fromCache = true }
    }
    func refreshSecurity() async {
        let w = wallet
        if let v = await fetch("security", { try await w.securityOverview() }) { security = v } else { security?.fromCache = true }
    }
    func refreshHealth() async {
        let w = wallet
        if let v = await fetch("health", { try await w.healthReady() }) { health = v } else { health?.fromCache = true }
    }
    func refreshAddressBook() async { if let b = try? await wallet.addressBook() { addressBook = b } }

    func update(settings s: WalletSettings) async {
        do { settings = try await wallet.update(settings: s) } catch { noteTransport(error) }
    }

    private func loadSnapshots() async {
        func cached<T: Codable & Sendable>(_ key: String) async -> Sourced<T>? {
            guard let s: Snapshot<T> = await snapshots.load(key) else { return nil }
            return Sourced(value: s.value, fetchedAt: s.savedAt, fromCache: true)
        }
        networks = await cached("networks"); accounts = await cached("accounts"); portfolio = await cached("portfolio")
        activity = await cached("activity"); security = await cached("security"); health = await cached("health")
        if let s: Snapshot<WalletSettings> = await snapshots.load("settings") { settings = s.value }
        if let b: Snapshot<[AddressBookEntry]> = await snapshots.load("addressbook") { addressBook = b.value }
        hasSnapshots = portfolio != nil || accounts != nil
    }

    // MARK: - Errors

    private func noteTransport(_ error: Error) {
        if let e = error as? APIError, e.isOffline { serverUnreachable = true }
        else if (error as? URLError) != nil { serverUnreachable = true }
    }

    func describe(_ error: Error) -> String {
        switch error {
        case PasskeyError.cancelled: return "Demande annulée."
        case PasskeyError.noCredential: return "Aucune passkey de ce portefeuille n’est disponible sur ce Mac. Vérifiez le trousseau iCloud, ou approuvez avec un appareil à proximité."
        case PasskeyError.notAvailable(let s): return "Ce Mac ne peut pas utiliser les passkeys de \(configuration.rpId) pour l’instant (\(s))."
        case PasskeyError.failed(let s): return "Passkey : \(s)"
        case let e as ApprovalError: return ErrorText.approval(e)
        case let e as APIError: return ErrorText.api(e)
        default: return error.localizedDescription
        }
    }

    // MARK: - Lookups

    func network(_ id: String) -> SPWalletCore.Network? { networks?.value.first { $0.id == id } }
    func address(on network: String) -> String? { accounts?.value.accounts.first { $0.network == network }?.address }
    func price(_ symbol: String) -> MarketPrice? { settings.prices ? portfolio?.value.prices?[symbol] : nil }
}

/// Whether the app is frontmost enough to deserve network traffic (set by the app delegate).
@MainActor enum AppActivity { static var isActive = true }
