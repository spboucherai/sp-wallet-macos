// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Core/Persistence/SnapshotStore.swift
// Description: Offline snapshots: the last answers of read-only endpoints, kept as files in the app's sandbox container so that balances, addresses, history and NFT lists can be consulted without a connection — always shown with their date. Nothing secret is stored (no session, no key); files are excluded from backups.
import Foundation
import SPWalletCore

struct Snapshot<T: Sendable>: Sendable { let value: T; let savedAt: Date }

actor SnapshotStore {
    static let shared = SnapshotStore(directory: AppEnvironment.supportDirectory.appendingPathComponent("snapshots", isDirectory: true))
    private let directory: URL
    private struct Envelope<T: Codable>: Codable { let savedAt: Date; let value: T }

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var d = directory; var v = URLResourceValues(); v.isExcludedFromBackup = true; try? d.setResourceValues(v)
    }

    private func url(_ key: String) -> URL { directory.appendingPathComponent(key.replacingOccurrences(of: "/", with: "_") + ".json") }

    func save<T: Codable & Sendable>(_ value: T, as key: String, at date: Date = Date()) {
        guard let data = try? APICoding.encoder().encode(Envelope(savedAt: date, value: value)) else { return }
        try? data.write(to: url(key), options: [.atomic, .completeFileProtection])
    }
    func load<T: Codable & Sendable>(_ key: String, as type: T.Type = T.self) -> Snapshot<T>? {
        guard let data = try? Data(contentsOf: url(key)), let e = try? APICoding.decoder().decode(Envelope<T>.self, from: data) else { return nil }
        return Snapshot(value: e.value, savedAt: e.savedAt)
    }
    /// Sign-out and "erase local data": everything this Mac remembered about the wallet goes.
    func eraseAll() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
