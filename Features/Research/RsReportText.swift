// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/Research/RsReportText.swift
// Description: Native rendering of untrusted text and data that come back from a research job: the AI agent's markdown-like files as plain structured text (headings, lists, code blocks — no web view, no image, no link followed, no markup interpreted beyond layout) and the laboratory's JSON report as an indented key / value outline. The text is shown verbatim.
import SwiftUI
import SPWalletCore

/// A document split into simple blocks by line prefixes only. Inline markup is left as typed: nothing is hidden and no link becomes clickable.
struct RsPlainDocument {
    enum Block: Identifiable {
        case heading(Int, String, level: Int)
        case paragraph(Int, String)
        case bullet(Int, String, indent: Int)
        case code(Int, String)
        case rule(Int)
        var id: Int { switch self { case .heading(let i, _, _), .paragraph(let i, _), .bullet(let i, _, _), .code(let i, _), .rule(let i): i } }
    }
    let blocks: [Block]
    let truncated: Bool

    static let maxCharacters = 200_000

    init(_ raw: String) {
        let text = raw.count > Self.maxCharacters ? String(raw.prefix(Self.maxCharacters)) : raw
        truncated = raw.count > Self.maxCharacters
        var out: [Block] = [], paragraph: [String] = [], code: [String]? = nil, n = 0
        func flush() { if !paragraph.isEmpty { out.append(.paragraph(n, paragraph.joined(separator: " "))); n += 1; paragraph = [] } }
        for line in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if let c = code { out.append(.code(n, c.joined(separator: "\n"))); n += 1; code = nil } else { flush(); code = [] }
                continue
            }
            if code != nil { code?.append(String(line)); continue }
            if trimmed.isEmpty { flush(); continue }
            let hashes = trimmed.prefix { $0 == "#" }.count
            if (1...6).contains(hashes), trimmed.dropFirst(hashes).hasPrefix(" ") {
                flush(); out.append(.heading(n, trimmed.dropFirst(hashes).trimmingCharacters(in: .whitespaces), level: hashes)); n += 1; continue
            }
            if trimmed.count >= 3, trimmed.allSatisfy({ $0 == "-" || $0 == "*" || $0 == "_" }), Set(trimmed).count == 1 { flush(); out.append(.rule(n)); n += 1; continue }
            let indent = line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) } / 2
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                flush(); out.append(.bullet(n, "• " + trimmed.dropFirst(2), indent: indent)); n += 1; continue
            }
            if let m = trimmed.prefixMatch(of: #/\d{1,3}[.)] /#) {
                flush(); out.append(.bullet(n, String(m.0) + trimmed[m.range.upperBound...], indent: indent)); n += 1; continue
            }
            if trimmed.hasPrefix("|") { flush(); out.append(.code(n, String(line))); n += 1; continue } // table rows: kept aligned, monospaced
            paragraph.append(trimmed)
        }
        if let c = code { out.append(.code(n, c.joined(separator: "\n"))); n += 1 }
        flush()
        blocks = out
    }
}

struct RsPlainDocumentView: View {
    let document: RsPlainDocument
    init(_ text: String) { document = RsPlainDocument(text) }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 7) {
            ForEach(document.blocks) { block in
                switch block {
                case .heading(_, let t, let level): Text(verbatim: t).font(level <= 1 ? .title3.weight(.semibold) : level == 2 ? .headline : .subheadline.weight(.semibold)).padding(.top, 4)
                case .paragraph(_, let t): Text(verbatim: t).fixedSize(horizontal: false, vertical: true)
                case .bullet(_, let t, let indent): Text(verbatim: t).padding(.leading, CGFloat(min(indent, 6)) * 12 + 4).fixedSize(horizontal: false, vertical: true)
                case .code(_, let t):
                    Text(verbatim: t).font(Theme.monoSmall).fixedSize(horizontal: false, vertical: true).padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                case .rule: Divider()
                }
            }
            if document.truncated { Text("Texte tronqué à \(RsPlainDocument.maxCharacters.formatted()) caractères pour l’affichage.").font(.caption).foregroundStyle(Theme.warning) }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Server JSON as an outline: keys and scalar values, nested objects indented. Long arrays are summarised, never silently cut.
struct RsJSONOutline: View {
    struct Line: Identifiable { let id: Int; let depth: Int; let key: String; let value: String? }
    let lines: [Line]
    let clipped: Bool
    static let maxLines = 400

    init(_ value: JSONValue) {
        var out: [Line] = [], clippedFlag = false
        func walk(_ v: JSONValue, key: String, depth: Int) {
            guard out.count < Self.maxLines else { clippedFlag = true; return }
            switch v {
            case .object(let o):
                if !key.isEmpty { out.append(Line(id: out.count, depth: depth, key: key, value: o.isEmpty ? "{}" : nil)) }
                for k in o.keys.sorted() { if let child = o[k] { walk(child, key: k, depth: key.isEmpty ? depth : depth + 1) } }
            case .array(let a):
                let scalars = a.allSatisfy { if case .object = $0 { return false }; if case .array = $0 { return false }; return true }
                if scalars && a.count <= 12 { out.append(Line(id: out.count, depth: depth, key: key, value: a.isEmpty ? "[]" : a.map(\.displayText).joined(separator: ", "))) }
                else if a.count > 24 { out.append(Line(id: out.count, depth: depth, key: key, value: "\(a.count) éléments (non détaillés ici)")) }
                else {
                    out.append(Line(id: out.count, depth: depth, key: key, value: nil))
                    for (i, child) in a.enumerated() { walk(child, key: "[\(i)]", depth: depth + 1) }
                }
            default: out.append(Line(id: out.count, depth: depth, key: key, value: v.displayText))
            }
        }
        walk(value, key: "", depth: 0)
        lines = out; clipped = clippedFlag
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(lines) { l in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: l.key).font(Theme.monoSmall).foregroundStyle(.secondary)
                    if let v = l.value { Text(verbatim: v).font(Theme.monoSmall).fixedSize(horizontal: false, vertical: true) }
                    Spacer(minLength: 0)
                }.padding(.leading, CGFloat(min(l.depth, 8)) * 14)
            }
            if clipped { Text("Affichage limité aux \(Self.maxLines) premières lignes de ce bloc.").font(.caption).foregroundStyle(Theme.warning) }
        }.textSelection(.enabled)
    }
}

/// The header every result block carries: what kind of thing it is, and who produced it.
struct RsBlockHeader: View {
    let title: String
    let provenance: ResearchProvenance
    var body: some View {
        let (p, text) = RsJobText.provenance(provenance)
        HStack { Text(title).font(.headline); Spacer(); ProvenanceTag(p: p, text: text) }
    }
}
