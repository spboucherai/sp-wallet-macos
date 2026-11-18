// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/Receive/ReceiveView.swift
// Description: Receiving: the wallet's public address on each network (given by the signer), as selectable text and as a QR code generated locally (Core Image). Available offline, with the date the addresses were last confirmed.
import SwiftUI
import CoreImage.CIFilterBuiltins
import SPWalletCore

struct ReceiveView: View {
    let model: AppModel
    @State private var network = ""
    @State private var copied = false

    var body: some View {
        Page("Recevoir", subtitle: "Adresses publiques de ce portefeuille. Elles peuvent être partagées sans risque ; elles ne permettent pas de dépenser.") {
            if let src = model.accounts, !src.value.accounts.isEmpty {
                let accounts = src.value.accounts
                let acc = accounts.first { $0.network == network } ?? accounts[0]
                let net = model.network(acc.network)
                if src.fromCache || !src.value.signerReachable {
                    Banner(.warning, "Adresses telles que confirmées par le signataire le \(Fmt.date(src.value.addressesAsOf ?? src.fetchedAt)). Elles ne changent pas pour une même clé (\(src.value.keyId)).")
                }
                Card {
                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Réseau", selection: Binding(get: { acc.network }, set: { network = $0; copied = false })) {
                                ForEach(accounts) { a in Text(a.name).tag(a.network) }
                            }.frame(maxWidth: 340)
                            Text("Adresse \(acc.name)").font(.headline)
                            Text(acc.address).font(.system(.title3, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            Text(Fmt.chunked(acc.address)).font(Theme.monoSmall).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            HStack {
                                Button { copyToPasteboard(acc.address); copied = true } label: { Label(copied ? "Copiée" : "Copier l’adresse", systemImage: copied ? "checkmark" : "doc.on.doc") }
                                if let u = URL(string: acc.explorer), u.scheme == "https" { Link("Voir dans l’explorateur", destination: u) }
                            }
                            Banner(.warning, "N’envoyez à cette adresse que des actifs du réseau \(acc.name). Un actif envoyé depuis un autre réseau peut être perdu.")
                            if let net {
                                Text("Actifs suivis sur ce réseau : " + net.assets.map(\.symbol).joined(separator: ", ")).font(.callout).foregroundStyle(.secondary)
                                if let act = net.activation { Text("Ce réseau exige un minimum de \(act) \(net.native.symbol) pour que le compte existe.").font(.callout).foregroundStyle(.secondary) }
                                if net.memo != nil { Text("Aucun mémo ni étiquette n’est requis pour créditer ce portefeuille.").font(.callout).foregroundStyle(.secondary) }
                                Text("Un dépôt apparaît dans Activité après \(net.minConf) confirmation(s).").font(.callout).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        VStack(spacing: 6) {
                            if let img = QR.image(qrText(acc, net)) {
                                Image(nsImage: img).interpolation(.none).resizable().frame(width: 220, height: 220).padding(10).background(.white, in: RoundedRectangle(cornerRadius: 10))
                                    .accessibilityLabel("Code QR de l’adresse \(acc.name)")
                            }
                            Text("Généré sur ce Mac").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Card("Toutes les adresses") {
                    ForEach(accounts) { a in
                        HStack {
                            Text(a.name).frame(width: 150, alignment: .leading)
                            Text(a.address).font(Theme.monoSmall).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button { copyToPasteboard(a.address) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.borderless).help("Copier")
                        }
                        if a.id != accounts.last?.id { Divider() }
                    }
                }
            } else {
                EmptyState(symbol: "arrow.down.left", title: "Adresses indisponibles", detail: "Les adresses viennent du signataire. Aucune n’a encore été synchronisée sur ce Mac.")
            }
        }
    }
    /// The network's standard payment URI when it has one, else the bare address.
    private func qrText(_ a: Account, _ n: SPWalletCore.Network?) -> String {
        if let n, let uri = try? PaymentURI.make(address: a.address, network: n) { return uri }
        return a.address
    }
}

enum QR {
    static func image(_ text: String) -> NSImage? {
        let f = CIFilter.qrCodeGenerator(); f.message = Data(text.utf8); f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let rep = NSCIImageRep(ciImage: out); let img = NSImage(size: rep.size); img.addRepresentation(rep); return img
    }
}
