// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/Portfolio/PortfolioView.swift
// Description: Multi-chain view: one block per network of the backend's registry with its identifier, native coin, the wallet's address, balances, RPC state and what the backend can really do on it. Nothing is assumed: a capability is listed only when the registry or the server says so.
import SwiftUI
import SPWalletCore

struct PortfolioView: View {
    let model: AppModel
    @Bindable var nav: Navigator
    @State private var onlyHeld = true
    @State private var caps: NetworkCapabilities?

    var body: some View {
        Page("Portefeuille", subtitle: "\(model.networks?.value.count ?? 0) réseaux pris en charge par le backend") {
            Toggle("Afficher seulement les réseaux où un actif est détenu", isOn: $onlyHeld)
            if let nets = model.networks?.value {
                let p = model.portfolio?.value
                let shown = nets.filter { n in !onlyHeld || (p?.balances.contains { $0.network == n.id && $0.isNonZero } ?? false) }
                if shown.isEmpty { EmptyState(symbol: "tray", title: "Aucun actif détenu", detail: "Décochez le filtre pour voir tous les réseaux et leurs adresses.") }
                ForEach(shown) { n in NetworkCard(model: model, nav: nav, net: n, caps: caps) }
            } else {
                EmptyState(symbol: "network.slash", title: "Registre des réseaux non synchronisé")
            }
        }
        .task { if caps == nil, model.canOperate { caps = await NetworkCapabilities.load(model) } }
    }
}

/// What the server reports it can execute per network (swap execution, bridge routes, agents). Read once; absent = unknown, not "no".
struct NetworkCapabilities: Sendable {
    var swap: Set<String> = []
    var bridge: Set<String> = []
    var xswap: Set<String> = []
    var loaded: Set<String> = []

    static func load(_ model: AppModel) async -> NetworkCapabilities {
        var c = NetworkCapabilities()
        func nets(_ path: String, keys: [String]) async -> Set<String>? {
            guard let j: JSONValue = try? await model.client.get(path) else { return nil }
            var out = Set<String>()
            for k in keys { for v in j[k]?.arrayValue ?? [] { if let s = v.stringValue { out.insert(s) } else if let s = v["network"]?.stringValue ?? v["id"]?.stringValue { out.insert(s) } } }
            return out
        }
        if let j: JSONValue = try? await model.client.get("/swap/execution") {
            c.swap = Set((j["networks"]?.arrayValue ?? []).compactMap(\.stringValue))
            if j["solana"]?["enabled"]?.boolValue == true { c.swap.insert("solana") }
            c.loaded.insert("swap")
        }
        if let s = await nets("/bridge/execution", keys: ["networks"]) { c.bridge = s; c.loaded.insert("bridge") }
        if let s = await nets("/xswap/execution", keys: ["assets"]) { c.xswap = s; c.loaded.insert("xswap") }
        return c
    }
}

private struct NetworkCard: View {
    let model: AppModel
    @Bindable var nav: Navigator
    let net: SPWalletCore.Network
    let caps: NetworkCapabilities?

    var body: some View {
        let p = model.portfolio?.value
        let balances = p?.balances.filter { $0.network == net.id } ?? []
        let held = balances.filter { $0.isNonZero || !$0.isAvailable }
        Card {
            HStack(alignment: .firstTextBaseline) {
                Text(net.name).font(.title3.weight(.semibold))
                Text("\(net.id) · \(net.family) · \(net.chainRef)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                rpc
            }
            if let addr = model.address(on: net.id) {
                HStack {
                    Text("Adresse").foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
                    Text(addr).font(Theme.monoSmall).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                    Button { copyToPasteboard(addr) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.borderless).help("Copier l’adresse")
                }
            }
            HStack { Text("Actif natif").foregroundStyle(.secondary).frame(width: 130, alignment: .leading); Text("\(net.native.symbol) — \(net.native.name), \(net.native.decimals) décimales") }
            HStack(alignment: .top) { Text("Capacités").foregroundStyle(.secondary).frame(width: 130, alignment: .leading); Text(capabilityText).fixedSize(horizontal: false, vertical: true) }
            HStack { Text("Finalité").foregroundStyle(.secondary).frame(width: 130, alignment: .leading); Text("\(net.minConf) confirmation(s) requises" + (net.activation.map { " · minimum de compte \($0) \(net.native.symbol)" } ?? "") + (net.memo.map { " · mémo \($0)" } ?? "")) }
            if !held.isEmpty, let p {
                Divider()
                ForEach(held) { b in
                    AssetRow(balance: b, portfolio: p, currency: model.currency, hide: model.settings.hideBalances, cached: model.portfolio?.fromCache ?? false)
                        .contentShape(Rectangle()).onTapGesture { nav.open(asset: b.id) }
                }
            }
            HStack {
                Text("\(net.tokens.count) jeton(s) suivi(s) : " + net.tokens.prefix(12).map(\.symbol).joined(separator: ", ") + (net.tokens.count > 12 ? "…" : "")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Button("Envoyer") { nav.send(network: net.id, asset: "native") }.disabled(!model.canOperate)
            }
        }
    }

    @ViewBuilder private var rpc: some View {
        if let h = net.health {
            if h.ok == true { Label(h.identityVerified == false ? "RPC joignable, identité non vérifiée" : "RPC joignable", systemImage: "circle.fill").foregroundStyle(Theme.positive).font(.caption) }
            else if h.ok == false { Label(h.readable == false ? "RPC en échec (chaîne illisible)" : "RPC dégradé", systemImage: "circle.fill").foregroundStyle(Theme.negative).font(.caption).lineLimit(1) }
            else { Label("RPC : état inconnu", systemImage: "circle").foregroundStyle(.secondary).font(.caption) }
        } else { Label("RPC : non mesuré", systemImage: "circle").foregroundStyle(.secondary).font(.caption) }
    }

    private var capabilityText: String {
        var c = ["soldes", "réception", "envoi (\(net.native.symbol)\(net.tokens.isEmpty ? "" : " et jetons"))"]
        if let caps {
            if caps.swap.contains(net.id) { c.append("échange (exécution)") }
            if caps.bridge.contains(net.id) { c.append("pont USDC (CCTP)") }
            if caps.xswap.contains(net.id) { c.append("échange natif inter-chaînes") }
            if caps.loaded.count < 3 { c.append("autres capacités non lues") }
        } else { c.append("échanges et ponts : voir leurs sections") }
        return c.joined(separator: " · ")
    }
}
