// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Components/NetworkPicker.swift
// Description: Pickers for a network and for an asset of that network, fed by the backend's registry (never a hard-coded list): adding a network server-side adds it here.
import SwiftUI
import SPWalletCore

struct NetworkPicker: View {
    let networks: [SPWalletCore.Network]
    @Binding var selection: String
    var label = "Réseau"
    var body: some View {
        Picker(label, selection: $selection) {
            ForEach(networks) { n in
                Text(n.name + (n.health?.ok == false ? "  ⚠︎ RPC" : "")).tag(n.id)
            }
        }
    }
}

struct AssetPicker: View {
    let network: SPWalletCore.Network?
    @Binding var selection: String
    var balances: [Balance] = []
    var label = "Actif"
    var body: some View {
        Picker(label, selection: $selection) {
            ForEach(network?.assets ?? []) { a in
                let b = balances.first { $0.network == network?.id && $0.asset == a.id }
                Text("\(a.symbol) — \(a.name)" + (b?.display.map { "  (\(Fmt.amount($0, maxFraction: 6)))" } ?? "")).tag(a.id)
            }
        }
    }
}
