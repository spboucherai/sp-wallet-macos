// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Features/Settings/SettingsView.swift
// Description      : Settings: display currency and privacy (stored server-side
//                    with the wallet's other settings), the app's local lock,
//                    notifications, the address book, local data and sign-out.
// Module           : Features
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
import SPWalletCore

struct SettingsView: View {
    let model: AppModel
    @State private var lockOn = UserDefaults.standard.bool(forKey: AppLock.enabledKey)
    @State private var lockDelay = UserDefaults.standard.double(forKey: AppLock.delayKey) > 0 ? UserDefaults.standard.double(forKey: AppLock.delayKey) : 60
    @State private var notifications = Notifier.enabled
    @State private var confirmErase = false
    @State private var abNetwork = ""
    @State private var abAddress = ""
    @State private var abLabel = ""
    @State private var abError: String?

    var body: some View {
        Page("Réglages") {
            Card("Affichage") {
                Picker("Devise d’affichage", selection: Binding(get: { model.settings.currency }, set: { v in var s = model.settings; s.currency = v; Task { await model.update(settings: s) } })) {
                    ForEach(FiatCurrency.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(width: 260)
                Toggle("Masquer les soldes à l’écran", isOn: Binding(get: { model.settings.hideBalances }, set: { v in var s = model.settings; s.hideBalances = v; Task { await model.update(settings: s) } }))
                Toggle("Afficher les prix et valeurs estimées (CoinGecko, source secondaire en secours)", isOn: Binding(get: { model.settings.prices }, set: { v in var s = model.settings; s.prices = v; Task { await model.update(settings: s) } }))
                Text("Ces réglages sont partagés avec le site (enregistrés par le serveur). Désactiver les prix : le serveur n’interroge plus aucune source de prix.").font(.caption).foregroundStyle(.secondary)
            }.disabled(!model.canOperate)
            Card("Verrouillage de l’app") {
                Toggle("Verrouiller SP Wallet (\(AppLock.biometryName))", isOn: Binding(get: { lockOn }, set: { v in Task { if await model.lock.setEnabled(v) { lockOn = v } } })).disabled(!AppLock.available)
                Picker("Verrouiller après une absence de", selection: $lockDelay) { Text("immédiatement").tag(1.0); Text("1 minute").tag(60.0); Text("5 minutes").tag(300.0); Text("15 minutes").tag(900.0) }
                    .frame(width: 380).disabled(!lockOn).onChange(of: lockDelay) { UserDefaults.standard.set(lockDelay, forKey: AppLock.delayKey) }
                Text("Le verrou masque les écrans de ce Mac. Il n’autorise aucune opération : chaque opération exige une signature de votre passkey liée à son intention exacte, vérifiée par le signataire.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Card("Notifications") {
                Toggle("Notifications macOS (transactions finalisées ou échouées, alertes)", isOn: $notifications).onChange(of: notifications) { UserDefaults.standard.set(notifications, forKey: "notificationsEnabled"); if notifications { Task { _ = await Notifier.requestPermission() } } }
                Text("Aucune notification n’annonce un succès avant la finalisation par la chaîne.").font(.caption).foregroundStyle(.secondary)
            }
            Card("Carnet d’adresses") {
                ForEach(model.addressBook) { e in
                    HStack {
                        Text(e.label).frame(width: 160, alignment: .leading)
                        Text(model.network(e.network)?.name ?? e.network).foregroundStyle(.secondary).frame(width: 120, alignment: .leading)
                        Text(e.address).font(Theme.monoSmall).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                        Spacer()
                        Button { Task { try? await model.wallet.deleteAddress(id: e.id); await model.refreshAddressBook() } } label: { Image(systemName: "trash") }.buttonStyle(.borderless).disabled(!model.canOperate)
                    }
                }
                if model.addressBook.isEmpty { Text("Aucune adresse enregistrée.").foregroundStyle(.secondary) }
                Divider()
                HStack {
                    NetworkPicker(networks: model.networks?.value ?? [], selection: $abNetwork).labelsHidden().frame(width: 150)
                    TextField("Adresse", text: $abAddress).font(Theme.monoSmall)
                    TextField("Nom", text: $abLabel).frame(width: 140)
                    Button("Ajouter") { Task { await addAddress() } }.disabled(!model.canOperate || abAddress.isEmpty || abLabel.isEmpty || abNetwork.isEmpty)
                }
                if let e = abError { Text(e).foregroundStyle(Theme.negative).font(.callout) }
            }
            Card("Données locales et session") {
                Text("Ce Mac conserve, dans le conteneur protégé de l’app, les dernières données lues (soldes, adresses publiques, historique, NFT) pour la consultation hors connexion, et le jeton de session dans le trousseau. Aucune clé privée ni phrase de récupération n’y figure.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Se déconnecter") { Task { await model.signOut(eraseLocalData: false) } }.disabled(model.phase != .signedIn)
                    Button("Se déconnecter et effacer les données locales…", role: .destructive) { confirmErase = true }
                }
            }
            Card("À propos") {
                Field(label: "Version", value: "\(AppEnvironment.version) (\(AppEnvironment.build))" + (AppEnvironment.isDevelopment ? " — variante de développement" : ""))
                Field(label: "Portefeuille", value: model.configuration.originHeader)
                Field(label: "Clé du portefeuille", value: model.accounts?.value.keyId ?? "—", mono: true)
                Text("Application native Swift / SwiftUI. Aucune vue web. Le signataire isolé du cluster MacLustr signe ; cette app affiche, prépare et transmet vos autorisations.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { if abNetwork.isEmpty { abNetwork = model.networks?.value.first?.id ?? "" } }
        .confirmationDialog("Effacer les données locales ?", isPresented: $confirmErase) {
            Button("Se déconnecter et effacer", role: .destructive) { Task { await model.signOut(eraseLocalData: true) } }
        } message: { Text("Les données de consultation hors connexion de ce Mac sont supprimées. Rien n’est modifié côté portefeuille.") }
    }

    private func addAddress() async {
        abError = nil
        if let n = model.network(abNetwork), case .invalid(let r) = AddressValidator.check(abAddress, network: n) { abError = SendFlow.text(r); return }
        do { _ = try await model.wallet.saveAddress(network: abNetwork, address: abAddress.trimmingCharacters(in: .whitespacesAndNewlines), label: abLabel); abAddress = ""; abLabel = ""; await model.refreshAddressBook() }
        catch { abError = model.describe(error) }
    }
}
