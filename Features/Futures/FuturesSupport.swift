// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/Futures/FuturesSupport.swift
// Description: Shared vocabulary of the derivatives terminal: the three trading modes that are never mixed (paper simulation, venue testnet, venue mainnet) with their colours, display helpers for the server's decimal strings (the strings stay exact; a Double is only ever used to sort, to draw or to label an approximation), and the small building blocks every sub-screen uses.
import SwiftUI
import SPWalletCore

/// The three books of the terminal. A figure of one mode is never added to a figure of another.
enum FutMode: String, CaseIterable, Identifiable, Sendable {
    case paper, testnet, mainnet
    var id: String { rawValue }
    var title: String {
        switch self { case .paper: "Simulation (papier)"; case .testnet: "Testnet de la plateforme"; case .mainnet: "Réel (mainnet)" }
    }
    var badge: String {
        switch self { case .paper: "SIMULATION"; case .testnet: "TESTNET"; case .mainnet: "RÉEL" }
    }
    var color: Color {
        switch self { case .paper: Color(red: 0.42, green: 0.36, blue: 0.82); case .testnet: Color(red: 0.10, green: 0.55, blue: 0.70); case .mainnet: Theme.negative }
    }
    var symbol: String {
        switch self { case .paper: "testtube.2"; case .testnet: "hammer"; case .mainnet: "bolt.shield" }
    }
    var explanation: String {
        switch self {
        case .paper: "Compte simulé par le serveur : aucune clé, aucun compte de plateforme, aucun fonds réel. Les ordres sont exécutés par le moteur papier contre le carnet réel."
        case .testnet: "Compte du testnet de la plateforme : vraie plateforme de test, collatéral fictif. Les ordres passent par le signataire isolé."
        case .mainnet: "Compte réel sur la plateforme : fonds réels. Chaque ordre est approuvé par votre passkey sur l’objet exact que la plateforme recevra."
        }
    }
    /// The venue network of a live mode; nil for paper.
    var network: String? { switch self { case .paper: nil; case .testnet: "testnet"; case .mainnet: "mainnet" } }
}

/// The mode's label on a figure or a button: colour AND text, never colour alone.
struct FutModeBadge: View {
    let mode: FutMode
    var body: some View {
        Label(mode.badge, systemImage: mode.symbol).font(.caption.weight(.bold)).foregroundStyle(mode.color)
            .padding(.horizontal, 7).padding(.vertical, 3).background(mode.color.opacity(0.14), in: Capsule())
            .accessibilityLabel("Mode \(mode.title)")
    }
}

/// Display of the server's decimal strings.
enum FutNum {
    /// For sorting, drawing and labelled approximations only — never to compute an amount that is sent or shown as exact.
    static func d(_ s: String?) -> Double? { guard let s, !s.isEmpty else { return nil }; return Double(s) }

    /// An exact decimal string, grouped; "—" when absent.
    static func exact(_ s: String?, maxFraction: Int? = nil) -> String { Fmt.amount(s, maxFraction: maxFraction) }

    /// A dollar figure of an account (equity, margin, notional…): the server's string cut to cents for reading.
    static func usd(_ s: String?) -> String { guard let s, !s.isEmpty else { return "—" }; return Fmt.amount(s, maxFraction: 2) + " $" }

    /// A fraction ("0.0123") as a signed percentage.
    static func pct(fraction s: String?, digits: Int = 2) -> String {
        guard let v = d(s) else { return "—" }
        return (v >= 0 ? "+" : "−") + abs(v * 100).formatted(.number.precision(.fractionLength(digits))) + " %"
    }

    static func compactUSD(_ s: String?) -> String {
        guard let v = d(s) else { return "—" }
        return v.formatted(.number.notation(.compactName).precision(.fractionLength(0...2))) + " $"
    }
    static func compact(_ s: String?) -> String {
        guard let v = d(s) else { return "—" }
        return v.formatted(.number.notation(.compactName).precision(.fractionLength(0...2)))
    }
    static func approx(_ v: Double?, digits: Int = 2) -> String {
        guard let v, v.isFinite else { return "—" }
        return "≈ " + v.formatted(.number.precision(.fractionLength(0...digits)))
    }
    static func ms(_ t: Int?) -> Date? { t.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) } }

    /// What the user typed, as the decimal text the server parses: dot separator, no grouping. Nil when it is not a plain positive decimal.
    static func input(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "\u{202F}", with: "").replacingOccurrences(of: " ", with: "")
        guard let v = VenueDecimal(t), v.isPositive else { return nil }
        return v.description
    }
}

/// A labelled figure of a summary grid. `value == nil` renders the explicit unavailable state, never a zero.
struct FutStat: View {
    let label: String
    let value: String?
    var color: Color = .primary
    var note: String?
    init(_ label: String, _ value: String?, color: Color = .primary, note: String? = nil) { self.label = label; self.value = value; self.color = color; self.note = note }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            if let value { Text(value).font(.title3.weight(.medium)).monospacedDigit().foregroundStyle(color).textSelection(.enabled).lineLimit(1).minimumScaleFactor(0.7) }
            else { Label("Indisponible", systemImage: "xmark.octagon").font(.callout).foregroundStyle(Theme.negative) }
            if let note { Text(note).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
}

/// A row of `FutStat`s that wraps on narrow windows.
struct FutStatGrid<Content: View>: View {
    var minimum: CGFloat = 150
    @ViewBuilder var content: Content
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum), spacing: 14, alignment: .topLeading)], alignment: .leading, spacing: 12) { content }
    }
}

/// A server lock or capability: ON / OFF with the server's own reason when it is off.
struct FutLockRow: View {
    let name: String
    let on: Bool?
    let reason: String?
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: on == true ? "lock.open.fill" : on == false ? "lock.fill" : "questionmark.circle").foregroundStyle(on == true ? Theme.positive : on == false ? Theme.warning : .secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(name).font(Theme.monoSmall)
                    Text(on == true ? "ouvert" : on == false ? "fermé par le serveur" : "état illisible").font(.caption.weight(.medium)).foregroundStyle(on == true ? Theme.positive : on == false ? Theme.warning : .secondary)
                }
                if let reason, !reason.isEmpty { Text(reason).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) }
            }
        }.accessibilityElement(children: .combine)
    }
}

/// The verbatim state of an order, coloured by what it means — only a state the server calls final and filled reads as done.
struct FutOrderStatePill: View {
    let raw: String
    static func text(_ raw: String) -> String {
        switch raw {
        case "proposed": "Proposé (rien n’est envoyé)"
        case "risk_checked": "Contrôlé, en attente de votre passkey"
        case "authorized": "Approuvé, signature en cours"
        case "signed": "Signé, non confirmé par la plateforme"
        case "submitted": "Envoyé, non confirmé par la plateforme"
        case "pending": "En attente"
        case "open": "Au carnet (en attente d’exécution)"
        case "partially_filled": "Partiellement exécuté"
        case "filled": "Exécuté"
        case "cancelled": "Annulé"
        case "rejected": "Rejeté"
        case "triggered": "Déclenché"
        case "unknown": "Inconnu : la plateforme n’a rien confirmé"
        default: raw
        }
    }
    var body: some View {
        let color: Color = raw == "filled" ? Theme.positive : ["rejected", "unknown"].contains(raw) ? Theme.negative : ["cancelled"].contains(raw) ? .secondary : Theme.warning
        Text(Self.text(raw)).font(.caption.weight(.medium)).foregroundStyle(color).padding(.horizontal, 7).padding(.vertical, 2).background(color.opacity(0.13), in: Capsule())
            .help("État rapporté par le serveur : \(raw)")
    }
}

/// How fresh a displayed price is, in words and colour.
struct FutFreshnessDot: View {
    let freshness: StreamFreshness?
    /// The date of the REST snapshot shown when no live quote exists.
    var snapshotAt: Date?
    var body: some View {
        let (color, text): (Color, String) = {
            switch freshness?.state {
            case .live: (Theme.positive, "En direct")
            case .delayed: (Theme.warning, "Retardé" + age)
            case .stale: (Theme.negative, "Périmé" + age)
            case .reconnecting: (Theme.warning, "Reconnexion du flux…")
            case .some(.none), nil: (.secondary, snapshotAt.map { "Instantané \(Fmt.relative($0))" } ?? "Aucune donnée")
            }
        }()
        Circle().fill(color).frame(width: 7, height: 7).help(text).accessibilityLabel(text)
    }
    private var age: String { freshness?.ageMs.map { " (\($0 / 1000) s)" } ?? "" }
}

struct FutSideText: View {
    let side: String
    var body: some View {
        let long = side == "long" || side == "buy"
        Text(side == "long" ? "LONG" : side == "short" ? "SHORT" : side == "buy" ? "ACHAT" : side == "sell" ? "VENTE" : side.uppercased())
            .font(.caption.weight(.bold)).foregroundStyle(long ? Theme.positive : Theme.negative)
    }
}

/// A result of the last read of one source: the value, or why it is unavailable — and when.
struct FutLoaded<T> {
    var value: T?
    var error: String?
    var at: Date?
    var loading = false
    mutating func set(_ v: T) { value = v; error = nil; at = Date(); loading = false }
    mutating func fail(_ e: String) { error = e; loading = false }
}

/// The header of a sheet that asks for a passkey: title, mode, and a close button that withdraws nothing by itself.
struct FutSheetHeader: View {
    let title: String
    var mode: FutMode?
    var body: some View {
        HStack { Text(title).font(.title2.weight(.semibold)); Spacer(); if let mode { FutModeBadge(mode: mode) } }.padding(20)
    }
}

extension View {
    /// Runs `action` now and then every `seconds` while the view is on screen and the app is active.
    func futPolling(every seconds: Double, id: some Equatable & Sendable, _ action: @escaping @MainActor () async -> Void) -> some View {
        task(id: id) {
            await action()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                if AppActivity.isActive { await action() }
            }
        }
    }
}
