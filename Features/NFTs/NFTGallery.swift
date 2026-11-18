// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/NFTs/NFTGallery.swift
// Description: State of the NFT gallery: the inventory as the server stores it (read page by page, spam included so nothing is hidden silently), the capability matrix that says which provider discovered what and when, the synchronisation the backend offers, and the local filters / search / sort / grouping over the served fields. The last inventory read is kept as an offline snapshot with its date; offline, nothing is fetched and nothing can be started.
import Foundation
import SPWalletCore

/// What is kept for offline reading: the rows exactly as served, and the matrix that explains where they come from.
struct NFTInventorySnapshot: Codable, Sendable {
    var items: [NFTSummary]
    var total: Int
    var complete: Bool
    var capabilities: NFTCapabilities?
    var lastSyncedAt: [String: Date]
}

struct NFTGallerySection: Identifiable {
    let id: String
    let title: String
    /// A collection key when the section is one collection (its page can be opened).
    let collectionKey: String?
    let items: [NFTSummary]
}

@MainActor @Observable final class NFTGallery {
    enum Status: String, CaseIterable, Identifiable {
        case all, inWallet, left, tracked
        var id: String { rawValue }
        var label: String {
            switch self { case .all: "Tout l’inventaire"; case .inWallet: "Détenus"; case .left: "Sortis du portefeuille"; case .tracked: "Suivis à la main" }
        }
    }
    enum Spam: String, CaseIterable, Identifiable {
        case hide, show, only
        var id: String { rawValue }
        var label: String { switch self { case .hide: "Masquer les signalés"; case .show: "Tout afficher"; case .only: "Signalés seulement" } }
    }
    enum Sort: String, CaseIterable, Identifiable {
        case recent, name, collection, network
        var id: String { rawValue }
        var label: String { switch self { case .recent: "Plus récents"; case .name: "Nom"; case .collection: "Collection"; case .network: "Réseau" } }
    }
    enum Grouping: String, CaseIterable, Identifiable {
        case none, collection, network
        var id: String { rawValue }
        var label: String { switch self { case .none: "Sans regroupement"; case .collection: "Par collection"; case .network: "Par réseau" } }
    }

    static let snapshotKey = "nft-inventory"
    /// The server never stores more than `NFT_INVENTORY_MAX` (at most 5 000) items; this is only a guard against an endless cursor.
    private static let maxItems = 6_000

    let model: AppModel
    let api: NFTAPI

    var chain = "" { didSet { refilter() } }
    var collection = "" { didSet { refilter() } }
    var status: Status = .all { didSet { refilter() } }
    var spam: Spam = .hide { didSet { refilter() } }
    var sort: Sort = .recent { didSet { refilter() } }
    var grouping: Grouping = .none { didSet { refilter() } }
    var search = "" { didSet { refilter() } }

    private(set) var items: [NFTSummary] = []
    private(set) var total = 0
    private(set) var complete = true
    private(set) var capabilities: NFTCapabilities?
    private(set) var lastSyncedAt: [String: Date] = [:]
    private(set) var syncRunning: [String] = []
    private(set) var fetchedAt: Date?
    private(set) var fromCache = false
    private(set) var loading = false
    private(set) var loadedOnce = false
    private(set) var syncStarting = false
    var error: String?
    var syncError: String?

    private(set) var sections: [NFTGallerySection] = []
    private(set) var visibleCount = 0
    private(set) var hiddenSpam = 0

    private var haystacks: [String: String] = [:]
    private var snapshotRead = false
    private var syncTask: Task<Void, Never>?

    init(model: AppModel) { self.model = model; api = NFTAPI(model.client) }

    /// Reads need a session; whether the wallet answers is found by asking.
    var canFetch: Bool { model.phase == .signedIn }
    var mediaAPI: NFTAPI? { model.canOperate ? api : nil }
    var mediaLimit: Int { NFTMediaStore.limit(capabilities?.mediaMaxBytes) }

    func networkName(_ id: String) -> String { model.network(id)?.name ?? capabilities?.chain(id)?.name ?? id }
    func summary(_ key: String) -> NFTSummary? { items.first { $0.key == key } }
    func items(inCollection key: String) -> [NFTSummary] { items.filter { $0.collection?.key == key } }

    /// Networks that appear in the inventory, in the server's registry order when known.
    var chainsPresent: [String] {
        let present = Set(items.map(\.chain))
        let ordered = (capabilities?.chains.map(\.network) ?? []).filter(present.contains)
        return ordered + present.subtracting(ordered).sorted()
    }
    /// Collections of the inventory (optionally of one network) with the number of rows held, largest first.
    var collectionsPresent: [(key: String, name: String, count: Int)] {
        var counts: [String: (String, Int)] = [:]
        for i in items where chain.isEmpty || i.chain == chain {
            guard let c = i.collection else { continue }
            counts[c.key] = (NFTClean.line(c.name) ?? Fmt.short(c.key, head: 18, tail: 8), (counts[c.key]?.1 ?? 0) + 1)
        }
        return counts.map { (key: $0.key, name: $0.value.0, count: $0.value.1) }.sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
    }

    // MARK: - Loading

    func load() async {
        if !snapshotRead {
            snapshotRead = true
            if items.isEmpty, let s: Snapshot<NFTInventorySnapshot> = await SnapshotStore.shared.load(Self.snapshotKey) {
                apply(s.value.items, total: s.value.total, complete: s.value.complete)
                capabilities = s.value.capabilities; lastSyncedAt = s.value.lastSyncedAt
                fetchedAt = s.savedAt; fromCache = true
            }
        }
        guard canFetch, !loading else { loadedOnce = true; return }
        loading = true; defer { loading = false; loadedOnce = true }
        do {
            async let caps = api.capabilities()
            var all: [NFTSummary] = [], seen = Set<String>(), cursor: Int? = 0, last: NFTList?
            while let c = cursor, all.count < Self.maxItems {
                let page = try await api.list(NFTListQuery(sort: .recent, spam: .show, cursor: c, limit: 100))
                for i in page.items where seen.insert(i.key).inserted { all.append(i) }
                last = page
                cursor = page.items.isEmpty ? nil : page.cursor
                try Task.checkCancellation()
            }
            let matrix = try? await caps
            apply(all, total: last?.total ?? all.count, complete: cursor == nil)
            if let matrix { capabilities = matrix }
            if let s = last?.sync { syncRunning = s.running; if let l = s.lastSyncedAt { lastSyncedAt = l } }
            fetchedAt = Date(); fromCache = false; error = nil
            await SnapshotStore.shared.save(NFTInventorySnapshot(items: items, total: total, complete: complete, capabilities: capabilities, lastSyncedAt: lastSyncedAt), as: Self.snapshotKey)
            if !syncRunning.isEmpty { followSync() }
        } catch is CancellationError {
        } catch let e as APIError where e.code == "nft_disabled" || e.code == "nft_misconfigured" {
            self.error = e.code == "nft_disabled"
                ? "Le module NFT est désactivé sur ce serveur (réglage NFT_ENABLED) : aucun inventaire, aucun transfert ni aucune donnée de marché n’y sont servis."
                : "La configuration NFT du serveur est invalide : le module NFT ne répond pas."
            if !items.isEmpty { fromCache = true }
        } catch {
            self.error = model.describe(error)
            if !items.isEmpty { fromCache = true }
        }
    }

    func refresh() async {
        await NFTMediaStore.shared.forgetFailures()
        await load()
    }

    private func apply(_ rows: [NFTSummary], total: Int, complete: Bool) {
        items = rows; self.total = total; self.complete = complete
        haystacks = Dictionary(uniqueKeysWithValues: rows.map { ($0.key, NFTText.haystack($0)) })
        if !collection.isEmpty, !rows.contains(where: { $0.collection?.key == collection }) { collection = "" }
        if !chain.isEmpty, !rows.contains(where: { $0.chain == chain }) { chain = "" }
        refilter()
    }

    // MARK: - Filters (over the served fields; the predicates are those of the server's own `status` and `spam` filters)

    private func refilter() {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var hidden = 0
        var rows = items.filter { i in
            if !chain.isEmpty, i.chain != chain { return false }
            if !collection.isEmpty, i.collection?.key != collection { return false }
            switch status {
            case .all: break
            case .inWallet: if !i.inWallet { return false }
            case .left: if i.inWallet || i.origin != "discovered" { return false }
            case .tracked: if i.origin != "manual" { return false }
            }
            if !needle.isEmpty, haystacks[i.key]?.contains(needle) != true { return false }
            switch spam {
            case .hide: if i.spam != nil { hidden += 1; return false }
            case .only: if i.spam == nil { return false }
            case .show: break
            }
            return true
        }
        func name(_ i: NFTSummary) -> String { (i.displayName ?? "\u{10FFFF}").lowercased() }
        func collectionName(_ i: NFTSummary) -> String { (i.collection?.name ?? i.collection?.key ?? "\u{10FFFF}").lowercased() }
        switch sort {
        case .recent: break // the server's order: held first, then most recently seen
        case .name: rows.sort { name($0) != name($1) ? name($0) < name($1) : $0.key < $1.key }
        case .collection: rows.sort { collectionName($0) != collectionName($1) ? collectionName($0) < collectionName($1) : name($0) < name($1) }
        case .network: rows.sort { $0.chain != $1.chain ? networkName($0.chain) < networkName($1.chain) : name($0) < name($1) }
        }
        hiddenSpam = hidden; visibleCount = rows.count
        switch grouping {
        case .none: sections = rows.isEmpty ? [] : [NFTGallerySection(id: "all", title: "", collectionKey: nil, items: rows)]
        case .network:
            var order: [String] = [], groups: [String: [NFTSummary]] = [:]
            for i in rows { if groups[i.chain] == nil { order.append(i.chain) }; groups[i.chain, default: []].append(i) }
            sections = order.map { NFTGallerySection(id: "n:\($0)", title: networkName($0), collectionKey: nil, items: groups[$0] ?? []) }
        case .collection:
            var order: [String] = [], groups: [String: [NFTSummary]] = [:]
            for i in rows { let k = i.collection?.key ?? ""; if groups[k] == nil { order.append(k) }; groups[k, default: []].append(i) }
            sections = order.map { k in
                let first = groups[k]?.first
                let title = k.isEmpty ? "Sans collection" : "\(NFTClean.line(first?.collection?.name) ?? Fmt.short(k, head: 18, tail: 8)) · \(networkName(first?.chain ?? ""))"
                return NFTGallerySection(id: "c:\(k)", title: title, collectionKey: k.isEmpty ? nil : k, items: groups[k] ?? [])
            }
        }
    }

    // MARK: - Synchronisation (the server's own job; this app only starts it and reports its state)

    func startSync(chain: String?) async {
        guard model.canOperate, !syncStarting else { return }
        syncStarting = true; syncError = nil; defer { syncStarting = false }
        do {
            syncRunning = try await api.sync(chain: chain).running
            followSync()
        } catch { syncError = model.describe(error) }
    }

    /// Reads the server's sync state until it reports no running job (or two minutes passed), then reloads the inventory.
    private func followSync() {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            for _ in 0..<40 {
                try? await Task.sleep(for: .seconds(3))
                guard let self, !Task.isCancelled else { return }
                guard AppActivity.isActive, self.model.canOperate else { continue }
                guard let page = try? await self.api.list(NFTListQuery(limit: 1)), let s = page.sync else { continue }
                self.syncRunning = s.running
                if let l = s.lastSyncedAt { self.lastSyncedAt = l }
                if s.running.isEmpty { break }
            }
            guard let self, !Task.isCancelled else { return }
            await self.load()
        }
    }

    func stop() { syncTask?.cancel(); syncTask = nil }
}

/// Creator-controlled text is untrusted: before it is displayed (always as plain text), control characters and bidirectional overrides are removed and its length is bounded.
enum NFTClean {
    static func text(_ s: String?, max: Int) -> String? {
        guard let s else { return nil }
        var out = String.UnicodeScalarView()
        var n = 0
        for u in s.unicodeScalars {
            if n >= max { out.append("…"); break }
            if u == "\n" || u == "\t" { out.append(u); n += 1; continue }
            switch u.properties.generalCategory {
            case .control, .format, .privateUse, .surrogate, .unassigned, .lineSeparator, .paragraphSeparator: continue
            default: out.append(u); n += 1
            }
        }
        let t = String(out).trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
    /// One line (names, collection names, trait labels).
    static func line(_ s: String?, max: Int = 120) -> String? { text(s?.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " "), max: max) }
}
