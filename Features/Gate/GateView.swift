// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/Gate/GateView.swift
// Description: Sign-in screen on the brand's hero surface: passkey only (Touch ID / iCloud Keychain / nearby device through the system sheet). No password exists. Also offers the read-only offline consultation of the last synchronized data.
import SwiftUI
import SPWalletCore

struct GateView: View {
    let model: AppModel
    #if SPW_DEV
    @State private var devToken = UserDefaults.standard.string(forKey: "spwDevSetupToken") ?? ""
    #endif

    var body: some View {
        ZStack {
            Theme.hero.ignoresSafeArea()
            Circle().fill(Theme.sky.opacity(0.28)).frame(width: 620, height: 620).blur(radius: 140).offset(x: 360, y: -260)
            Circle().fill(Theme.azure.opacity(0.36)).frame(width: 520, height: 520).blur(radius: 130).offset(x: -380, y: 280)
            VStack(spacing: 22) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 104, height: 104).shadow(color: .black.opacity(0.35), radius: 18, y: 8)
                VStack(spacing: 4) {
                    Text("SP Wallet").font(.system(size: 40, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text("Portefeuille multichaîne · signature isolée MacLustr").foregroundStyle(.white.opacity(0.72))
                }
                panel.frame(width: 440)
                HStack(spacing: 18) {
                    Label("Aucune clé privée sur ce Mac", systemImage: "lock.shield")
                    Label("Chaque opération liée à sa passkey", systemImage: "person.badge.key")
                    Label(model.configuration.origin.host ?? "", systemImage: "network")
                }.font(.caption).foregroundStyle(.white.opacity(0.65))
            }.padding(40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // the whole screen sits on the dark hero surface: secondary texts and the glass panel must use the dark appearance
        .environment(\.colorScheme, .dark)
    }

    private var panel: some View {
        VStack(spacing: 14) {
            if model.phase == .setupRequired {
                #if SPW_DEV
                Text("Pile de développement vierge : enrôlez la passkey logicielle avec le jeton de configuration de la pile.").multilineTextAlignment(.center)
                TextField("Jeton de configuration", text: $devToken).textFieldStyle(.roundedBorder)
                Button("Configurer la pile de test") { Task { await model.devSetup(token: devToken.trimmingCharacters(in: .whitespacesAndNewlines)) } }.controlSize(.large).disabled(devToken.isEmpty || model.busy)
                #else
                Banner(.warning, "Ce portefeuille n’a pas encore de propriétaire. La configuration initiale exige le jeton à usage unique émis sur la machine du signataire et se fait depuis le site, pas depuis cette app.")
                Button("Réessayer") { Task { await model.retryConnection() } }
                #endif
            } else {
                Button { Task { await model.signIn() } } label: {
                    Label("Se connecter avec une passkey", systemImage: "touchid").font(.system(.title3, design: .rounded).weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 6)
                }.controlSize(.extraLarge).buttonStyle(.borderedProminent).tint(Theme.azure).keyboardShortcut(.defaultAction).disabled(model.busy)
                Text("Touch ID, trousseau iCloud ou appareil à proximité.\nAucun mot de passe n’existe pour ce portefeuille.").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            if model.busy { ProgressView().controlSize(.small) }
            if let m = model.gateMessage { Banner(model.isOffline ? .warning : .danger, m) }
            if model.isOffline { Button("Réessayer la connexion") { Task { await model.retryConnection() } } }
            if model.hasSnapshots, model.phase != .setupRequired {
                Divider()
                Button("Consulter les dernières données (hors connexion)") { Task { await model.browseOffline() } }.buttonStyle(.link)
                Text("Lecture seule : soldes, adresses et historique synchronisés le \(Fmt.date(model.portfolio?.fetchedAt)).").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding(26)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.18)))
        .shadow(color: .black.opacity(0.35), radius: 30, y: 14)
    }
}
