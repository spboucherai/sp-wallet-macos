// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Components/Theme.swift
// Description      : The visual language of SP Wallet: calm surfaces, one
//                    accent, and semantic colours that mean the same thing
//                    everywhere (verified, estimate, warning, danger). No
//                    decorative animation: nothing moves to distract from a fee
//                    or a risk.
// Module           : Components
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

import SwiftUI

enum Theme {
    static let accent = Color("AccentColor")
    static let positive = Color(red: 0.07, green: 0.62, blue: 0.40)
    static let negative = Color(red: 0.86, green: 0.24, blue: 0.24)
    static let warning = Color(red: 0.90, green: 0.56, blue: 0.04)
    static let estimate = Color.secondary
    static let card = Color(nsColor: .controlBackgroundColor)
    static let stroke = Color(nsColor: .separatorColor)
    static let corner: CGFloat = 16
    static let mono = Font.system(.body, design: .monospaced)
    static let monoSmall = Font.system(.callout, design: .monospaced)

    /// The brand's deep indigo, as on the app icon: the hero surfaces of the app.
    static let ink = Color(red: 0.043, green: 0.067, blue: 0.188)
    static let indigo = Color(red: 0.106, green: 0.165, blue: 0.420)
    static let azure = Color(red: 0.227, green: 0.388, blue: 0.902)
    static let sky = Color(red: 0.498, green: 0.635, blue: 1.0)
    static let hero = LinearGradient(colors: [Color(red: 0.13, green: 0.21, blue: 0.56), indigo, ink], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let accentGradient = LinearGradient(colors: [sky, azure], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Categorical palette for allocations and series: distinct in hue AND lightness, readable in light and dark appearance.
    static let palette: [Color] = [
        Color(red: 0.25, green: 0.41, blue: 0.93), Color(red: 0.06, green: 0.64, blue: 0.60), Color(red: 0.95, green: 0.62, blue: 0.11),
        Color(red: 0.86, green: 0.31, blue: 0.47), Color(red: 0.55, green: 0.38, blue: 0.90), Color(red: 0.20, green: 0.66, blue: 0.89),
        Color(red: 0.47, green: 0.70, blue: 0.24), Color(red: 0.55, green: 0.59, blue: 0.67),
    ]
    static func series(_ i: Int) -> Color { palette[i % palette.count] }

    static func change(_ v: Double?) -> Color { guard let v else { return .secondary }; return v > 0 ? positive : v < 0 ? negative : .secondary }
    /// Hero figures: rounded, heavy, tabular digits.
    static func figure(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .rounded) }
}

/// The window's backdrop: the system background with a very light brand tint at the top, so cards read as raised surfaces.
struct Backdrop: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(colors: [Theme.azure.opacity(scheme == .dark ? 0.16 : 0.07), .clear], startPoint: .top, endPoint: .center)
        }.ignoresSafeArea()
    }
}

struct Card<Content: View>: View {
    var title: String?
    var trailing: AnyView?
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme
    init(_ title: String? = nil, trailing: AnyView? = nil, @ViewBuilder content: () -> Content) { self.title = title; self.trailing = trailing; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if title != nil || trailing != nil {
                HStack(alignment: .firstTextBaseline) {
                    if let title { Text(title).font(.system(.headline, design: .rounded).weight(.semibold)) }
                    Spacer()
                    if let trailing { trailing }
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card.opacity(scheme == .dark ? 0.72 : 1), in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).strokeBorder(Theme.stroke.opacity(scheme == .dark ? 0.55 : 0.35)))
        .shadow(color: .black.opacity(scheme == .dark ? 0.28 : 0.06), radius: 14, x: 0, y: 5)
    }
}

/// The dark, branded surface used for the most important figure of a screen (total value, an account's equity…).
struct HeroCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.white)
            .background {
                ZStack {
                    Theme.hero
                    // two soft light sources, as on the icon; static — nothing here moves
                    Circle().fill(Theme.sky.opacity(0.30)).frame(width: 380, height: 380).blur(radius: 90).offset(x: 330, y: -150)
                    Circle().fill(Theme.azure.opacity(0.35)).frame(width: 300, height: 300).blur(radius: 80).offset(x: -260, y: 170)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.12)))
            .shadow(color: Theme.indigo.opacity(0.35), radius: 22, x: 0, y: 10)
            .environment(\.colorScheme, .dark)
    }
}

/// A small labelled figure with an icon tile: the dashboard's secondary facts.
struct StatTile: View {
    let symbol: String; let label: String; let value: String
    var tint: Color = Theme.azure
    var detail: String?
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 38, height: 38).background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(value).font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                if let detail { Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 0)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke.opacity(0.35)))
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
        .accessibilityElement(children: .combine)
    }
}

/// A prominent action with an icon above its label (dashboard shortcuts). An action, never a status.
struct QuickAction: View {
    let symbol: String; let title: String; var onDark = false
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
                    .frame(width: 46, height: 46)
                    .background(onDark ? AnyShapeStyle(.white.opacity(hover ? 0.26 : 0.16)) : AnyShapeStyle(Theme.azure.opacity(hover ? 0.22 : 0.13)), in: Circle())
                Text(title).font(.caption.weight(.medium))
            }
            .foregroundStyle(onDark ? .white : Theme.azure).frame(minWidth: 70)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hover = $0 }
    }
}

/// A label + value row for review sheets and detail panes. The value is selectable text: an address can always be copied and compared.
struct Field: View {
    let label: String
    let value: String
    var mono = false
    var emphasis = false
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).foregroundStyle(.secondary).frame(width: 170, alignment: .leading)
            Text(value).font(mono ? Theme.monoSmall : .body).fontWeight(emphasis ? .semibold : .regular).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// How much a figure can be trusted — shown next to it, never hidden in a tooltip only.
enum Provenance { case verified, estimate, stale, unavailable, simulated, ai
    var label: String {
        switch self { case .verified: "Lu sur la chaîne"; case .estimate: "Estimation"; case .stale: "Périmé"; case .unavailable: "Indisponible"; case .simulated: "Simulation"; case .ai: "Analyse IA" }
    }
    var color: Color { switch self { case .verified: Theme.positive; case .estimate, .simulated, .ai: .secondary; case .stale: Theme.warning; case .unavailable: Theme.negative } }
    var symbol: String { switch self { case .verified: "checkmark.seal"; case .estimate: "tilde"; case .stale: "clock.badge.exclamationmark"; case .unavailable: "xmark.octagon"; case .simulated: "testtube.2"; case .ai: "sparkles" } }
}
struct ProvenanceTag: View {
    let p: Provenance; var text: String?
    var body: some View {
        Label(text ?? p.label, systemImage: p.symbol).font(.caption.weight(.medium)).foregroundStyle(p.color).lineLimit(1)
            .padding(.horizontal, 9).padding(.vertical, 4).background(p.color.opacity(0.12), in: Capsule())
    }
}

struct Banner: View {
    enum Kind { case info, warning, danger, ok
        var color: Color { switch self { case .info: .blue; case .warning: Theme.warning; case .danger: Theme.negative; case .ok: Theme.positive } }
        var symbol: String { switch self { case .info: "info.circle.fill"; case .warning: "exclamationmark.triangle.fill"; case .danger: "exclamationmark.octagon.fill"; case .ok: "checkmark.circle.fill" } }
    }
    let kind: Kind; let text: String
    init(_ kind: Kind, _ text: String) { self.kind = kind; self.text = text }
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: kind.symbol).foregroundStyle(kind.color)
            Text(text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10).background(kind.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(kind.color.opacity(0.30)))
    }
}

/// A screen's scaffold: title, optional subtitle, scrollable content with the standard margins.
struct Page<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content
    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) { self.title = title; self.subtitle = subtitle; self.content = content() }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 30, weight: .bold, design: .rounded))
                    if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                }
                content
            }
            .padding(.horizontal, 28).padding(.vertical, 22).frame(maxWidth: 1180, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Backdrop())
    }
}

struct EmptyState: View {
    let symbol: String; let title: String; var detail: String?
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 28, weight: .medium)).foregroundStyle(Theme.azure.opacity(0.75))
                .frame(width: 68, height: 68).background(Theme.azure.opacity(0.10), in: Circle())
            Text(title).font(.system(.headline, design: .rounded))
            if let detail { Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 460) }
        }.frame(maxWidth: .infinity).padding(40)
    }
}

/// A coloured disc with the asset's symbol initials: the app ships no third-party logo and never treats a logo as proof of identity.
struct AssetBadge: View {
    let symbol: String; var size: CGFloat = 32
    var body: some View {
        let hue = Double(abs(symbol.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }) % 360) / 360
        Text(String(symbol.prefix(symbol.count > 4 ? 3 : 4))).font(.system(size: size * 0.31, weight: .heavy, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
            .foregroundStyle(.white).frame(width: size, height: size)
            .background(LinearGradient(colors: [Color(hue: hue, saturation: 0.52, brightness: 0.82), Color(hue: hue, saturation: 0.70, brightness: 0.52)], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.18)))
            .shadow(color: Color(hue: hue, saturation: 0.6, brightness: 0.5).opacity(0.28), radius: 4, x: 0, y: 2)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Destructive or irreversible actions are never the default button and always spelled out.
    func copyable(_ text: String) -> some View {
        contextMenu { Button("Copier") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) } }
    }
}
func copyToPasteboard(_ s: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string) }
