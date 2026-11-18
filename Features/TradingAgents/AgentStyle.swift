// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/TradingAgents/AgentStyle.swift
// Description: The visual vocabulary of the trading agents. The three execution modes (research, paper, real) each own ONE colour and ONE label, used on every row, header, figure and button, so that a simulated number can never be read as money. Also the shared small views of the section (mode-tagged figures and buttons, verbatim rendering of server JSON, server locks).
import SwiftUI
import SPWalletCore

/// A mode as it must be shown: the mode itself plus, for a live perp agent, whether the venue network is the test network.
struct ModeKind: Hashable {
    let mode: AgentMode
    var liveNetwork: String?

    init(_ mode: AgentMode, liveNetwork: String? = nil) { self.mode = mode; self.liveNetwork = mode == .live ? liveNetwork : nil }
    init(agent a: Agent) { self.init(a.mode, liveNetwork: a.liveNetwork) }

    var isTestnet: Bool { mode == .live && liveNetwork == "testnet" }
    /// Real money is at stake: live, and not on a venue's test network.
    var isRealMoney: Bool { mode == .live && !isTestnet }

    var color: Color {
        switch mode {
        case .research: Color(red: 0.33, green: 0.36, blue: 0.80)
        case .paper: Color(red: 0.05, green: 0.55, blue: 0.62)
        case .live: isTestnet ? Color(red: 0.62, green: 0.45, blue: 0.10) : Color(red: 0.78, green: 0.12, blue: 0.24)
        case .unknown: .gray
        }
    }
    /// The label written on bands, headers and tags.
    var title: String {
        switch mode {
        case .research: "RECHERCHE — simulation"
        case .paper: "PAPIER — simulé"
        case .live: isTestnet ? "RÉEL · TESTNET — argent fictif" : "RÉEL — argent réel"
        case .unknown: "MODE INCONNU"
        }
    }
    /// The suffix written on buttons and next to figures.
    var short: String {
        switch mode {
        case .research: "RECHERCHE"
        case .paper: "PAPIER"
        case .live: isTestnet ? "RÉEL · TESTNET" : "RÉEL"
        case .unknown: "INCONNU"
        }
    }
    var symbol: String {
        switch mode { case .research: "testtube.2"; case .paper: "doc.plaintext"; case .live: isTestnet ? "hammer" : "bolt.fill"; case .unknown: "questionmark" }
    }
    var explanation: String {
        switch mode {
        case .research: "Recherche : backtests et décisions sur données historiques. Aucun ordre n’est émis, rien n’est signé."
        case .paper: "Papier : ordres et exécutions simulés sur des prix réels. Aucun argent ne bouge, rien n’est signé."
        case .live: isTestnet ? "Réel sur le réseau de test de la plateforme : les ordres sont signés et envoyés, mais l’argent est fictif." : "Réel : des ordres signés sous mandat atteignent une chaîne ou une plateforme. L’argent engagé peut être perdu."
        case .unknown: "Mode inconnu de cette version de l’app : rien n’est présumé simulé ni réel."
        }
    }
}

/// The capsule that names the mode. Never colour alone: the label is always written.
struct ModeTag: View {
    let kind: ModeKind
    var compact = false
    var body: some View {
        Label(compact ? kind.short : kind.title, systemImage: kind.symbol)
            .font(.caption.weight(.bold)).foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 3).background(kind.color, in: Capsule())
            .help(kind.explanation)
            .accessibilityLabel("Mode : \(kind.title)")
    }
}

/// A full-width band under a header: colour, label and what the mode means.
struct ModeHeaderBand: View {
    let kind: ModeKind
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: kind.symbol).font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.title).font(.headline)
                Text(kind.explanation).font(.caption).opacity(0.92).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading).background(kind.color, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Frames a block of content that belongs to ONE mode: a coloured band on the leading edge and a tinted stroke.
    func modeFramed(_ kind: ModeKind) -> some View {
        self.padding(.leading, 12)
            .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(kind.color).frame(width: 5) }
    }
}

/// One figure with its mode written under it. A missing value shows the server's reason, never zero.
struct ModeFigure: View {
    let label: String
    let value: String?
    let kind: ModeKind
    var reason: String?
    var partial = false
    var tint: Color?
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value ?? "—").font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(value == nil ? Color.secondary : (tint ?? .primary)).textSelection(.enabled)
            HStack(spacing: 4) {
                ModeTag(kind: kind, compact: true)
                if partial { Label("Partiel", systemImage: "exclamationmark.triangle.fill").font(.caption2.weight(.medium)).foregroundStyle(Theme.warning) }
            }
            if value == nil, let reason { Text(reason).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
        .frame(minWidth: 150, alignment: .leading).padding(10)
        .background(kind.color.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(kind.color.opacity(0.35)))
        .accessibilityElement(children: .combine)
    }
}

/// A button whose colour and title carry the mode it acts in.
struct ModeButton: View {
    let title: String
    let kind: ModeKind
    var systemImage: String?
    var prominent = false
    var role: ButtonRole?
    let action: () -> Void
    var body: some View {
        let label = "\(title) · \(kind.short)"
        Group {
            if prominent {
                Button(role: role, action: action) { if let systemImage { Label(label, systemImage: systemImage) } else { Text(label) } }.buttonStyle(.borderedProminent)
            } else {
                Button(role: role, action: action) { if let systemImage { Label(label, systemImage: systemImage) } else { Text(label) } }.buttonStyle(.bordered)
            }
        }.tint(kind.color)
    }
}

enum AgentText {
    /// The historical state text of the server, in French when known, verbatim otherwise.
    static func phase(_ s: String) -> String {
        switch s {
        case "CREATED": "Créé"
        case "RESEARCH", "RESEARCHING": "En recherche"
        case "BACKTESTING": "Backtest en cours"
        case "AWAITING_APPROVAL": "En attente d’approbation de la stratégie"
        case "PAPER_TRADING", "PAPER": "Actif sur papier"
        case "LIVE": "Actif en réel"
        case "RUNNING": "En marche"
        case "PAUSED": "En pause"
        case "STOPPING": "Arrêt en cours (fermeture des positions)"
        case "STOPPED": "Arrêté"
        default: s
        }
    }
    static func lifecycle(_ s: AgentLifecycle) -> String {
        switch s { case .active: "Actif"; case .paused: "En pause"; case .stopped: "Arrêté"; case .unknown: "État inconnu" }
    }
    static func kind(_ k: AgentKind) -> String {
        switch k { case .spot: "Comptant (coffre)"; case .perp: "Perpétuels"; case .stream: "Règle en flux"; case .supervisor: "Superviseur de risque"; case .unknown: "Type inconnu" }
    }
    static func family(_ f: String?) -> String {
        switch f { case "market_making": "Tenue de marché"; case nil: "—"; default: f!.replacingOccurrences(of: "_", with: " ") }
    }
    static func returnState(_ s: VaultReturnState) -> String {
        switch s {
        case .requested: "Demandé, pas encore signé"
        case .signed: "Signé, non diffusé"
        case .broadcast: "Diffusé, non confirmé"
        case .confirmed: "Confirmé par la chaîne"
        case .failed: "Échoué"
        case .notSent: "Signé, NON diffusé (diffusion désactivée sur ce serveur)"
        case .unknown: "État inconnu"
        }
    }
    static func ms(_ v: Int?) -> Date? { v.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) } }
    static func seconds(_ v: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(v)) }
    static func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }
    static func number(_ v: Double?, fraction: Int = 2) -> String? { v.map { $0.formatted(.number.precision(.fractionLength(0...fraction))) } }
    static func usd(_ v: Double?) -> String? { v.map { $0.formatted(.currency(code: "USD").precision(.fractionLength(2))) } }
    /// A ratio served as a fraction (0.12) shown as a percentage.
    static func ratio(_ v: Double?) -> String? { v.map { ($0 * 100).formatted(.number.precision(.fractionLength(2))) + " %" } }
    /// Parses a typed decimal ("1 000,5" or "1000.5"). Nil when it is not a finite number.
    static func decimal(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "\u{202F}", with: "").replacingOccurrences(of: " ", with: "")
        guard t.range(of: #"^\d+(\.\d+)?$"#, options: .regularExpression) != nil, let d = Double(t), d.isFinite else { return nil }
        return d
    }
    /// The same typed decimal as canonical text for exact comparison by the Core.
    static func decimalText(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "\u{202F}", with: "").replacingOccurrences(of: " ", with: "") }
    static func https(_ s: String?) -> URL? { guard let s, let u = URL(string: s), u.scheme == "https" else { return nil }; return u }
}

/// Server JSON shown as it is: keys and values, nothing interpreted, nothing dropped.
enum JSONFlat {
    static func text(_ v: JSONValue) -> String {
        switch v {
        case .null: "—"
        case .bool(let b): b ? "oui" : "non"
        case .int(let i): String(i)
        case .double(let d): d.formatted(.number.precision(.significantDigits(1...8)))
        case .string(let s): s.isEmpty ? "(vide)" : s
        case .array(let a): a.isEmpty ? "(aucun)" : a.allSatisfy({ $0.objectValue == nil && $0.arrayValue == nil }) ? a.map(text).joined(separator: ", ") : v.displayText
        case .object: v.displayText
        }
    }
    /// Flattens an object to `path → text` rows, in key order, down to `depth` levels.
    static func rows(_ v: JSONValue?, prefix: String = "", depth: Int = 2) -> [(key: String, value: String)] {
        guard let v, !v.isNull else { return [] }
        guard let o = v.objectValue else { return [(prefix.isEmpty ? "valeur" : prefix, text(v))] }
        var out: [(String, String)] = []
        for k in o.keys.sorted() {
            let path = prefix.isEmpty ? k : "\(prefix).\(k)", child = o[k]!
            if depth > 1, child.objectValue != nil { out += rows(child, prefix: path, depth: depth - 1) } else { out.append((path, text(child))) }
        }
        return out
    }
}

/// A block of verbatim server data, as label/value lines.
struct JSONFacts: View {
    let value: JSONValue?
    var depth = 2
    var empty = "Aucune donnée."
    var body: some View {
        let rows = JSONFlat.rows(value, depth: depth)
        if rows.isEmpty { Text(empty).foregroundStyle(.secondary).font(.callout) }
        else {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(r.key).font(.callout).foregroundStyle(.secondary).frame(width: 230, alignment: .leading)
                        Text(r.value).font(Theme.monoSmall).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// A list of JSON objects (positions, orders of a simulated account…) as one small block each.
struct JSONList: View {
    let items: [JSONValue]
    var limit = 50
    var empty = "Aucun élément."
    var body: some View {
        if items.isEmpty { Text(empty).foregroundStyle(.secondary).font(.callout) }
        else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.prefix(limit).enumerated()), id: \.offset) { _, it in
                    JSONFacts(value: it, depth: 1).padding(8).frame(maxWidth: .infinity, alignment: .leading).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                }
                if items.count > limit { Text("\(items.count - limit) autres éléments non affichés.").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}

/// A server lock: its state and the server's own reason. A closed path is shown closed, never hidden.
struct LockRow: View {
    let name: String
    let open: Bool
    let reason: String?
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: open ? "lock.open.fill" : "lock.fill").foregroundStyle(open ? Theme.positive : Theme.warning).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) { Text(name).font(Theme.monoSmall); Text(open ? "ouvert sur le serveur" : "FERMÉ sur le serveur").font(.caption.weight(.semibold)).foregroundStyle(open ? Theme.positive : Theme.warning) }
                if let reason, !reason.isEmpty { Text(reason).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) }
            }
            Spacer(minLength: 0)
        }.accessibilityElement(children: .combine)
    }
}

/// A checkbox the owner must tick before an approval button enables.
struct AckToggle: View {
    @Binding var isOn: Bool
    let text: String
    var body: some View {
        Toggle(isOn: $isOn) { Text(text).fixedSize(horizontal: false, vertical: true) }.toggleStyle(.checkbox)
    }
}

/// Title + scrolling body + pinned footer: the shape of every sheet of this section.
struct SheetScaffold<Content: View, Footer: View>: View {
    let title: String
    var width: CGFloat = 760
    var height: CGFloat = 780
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.title2.weight(.semibold)).padding(20)
            Divider()
            ScrollView { VStack(alignment: .leading, spacing: 14) { content }.padding(20).frame(maxWidth: .infinity, alignment: .leading) }
            Divider()
            VStack(alignment: .leading, spacing: 8) { footer }.padding(16)
        }
        .frame(width: width, height: height)
    }
}
