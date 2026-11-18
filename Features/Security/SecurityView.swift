// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/Security/SecurityView.swift
// Description: Security dashboard: signer state and key identifier, halt state and the one-way emergency halt, the limits in force on the signer (read from it, never editable here), what was spent today against them, RPC state, passkeys and sessions, and the hash-chained audit journal with the server's integrity verdict. No private key or recovery phrase is ever displayed: this app has no route to them.
import SwiftUI
import SPWalletCore

struct SecurityView: View {
    let model: AppModel
    @State private var journal: AuditJournal?
    @State private var journalError: String?
    @State private var confirmHalt = false
    @State private var confirmRevoke = false
    @State private var message: String?
    @State private var working = false
    @State private var auditFilter = ""
    @State private var newLabel = "Mac"

    var body: some View {
        Page("Sécurité", subtitle: "Le signataire isolé est l’autorité cryptographique. Ce Mac ne détient aucune clé du portefeuille.") {
            if let m = message { Banner(.info, m) }
            if let src = model.security {
                let s = src.value
                if src.fromCache { Banner(.warning, "État tel que synchronisé le \(Fmt.date(src.fetchedAt)) ; il peut avoir changé.") }
                HStack(alignment: .top, spacing: 16) { signerCard(s); haltCard(s) }
                limitsCard(s)
                rpcCard
                HStack(alignment: .top, spacing: 16) { devicesCard(s); sessionsCard(s) }
            } else {
                EmptyState(symbol: "lock.shield", title: "État de sécurité non synchronisé")
            }
            auditCard
            Card("Récupération") {
                Text("La phrase de récupération n’est jamais affichée, exportée ni transmise par une application. Elle ne peut être produite que par un opérateur, sur la machine du signataire, dans un terminal interactif (procédure du signataire). Aucune route de l’API n’y donne accès.").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { await model.refreshSecurity(); await model.refreshHealth(); await loadJournal() }
        .confirmationDialog("Engager l’arrêt d’urgence ?", isPresented: $confirmHalt, titleVisibility: .visible) {
            Button("Engager l’arrêt d’urgence", role: .destructive) { Task { await halt() } }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Le signataire refusera immédiatement tout transfert, échange, pont, dépôt, retrait, ordre qui ouvre ou augmente une position, et toute nouvelle autorisation. Les réductions de risque (annulations, ordres en réduction seule) et les retours de coffre vers vous restent possibles.\n\nL’arrêt NE PEUT PAS être levé depuis cette app ni depuis le site : seul un opérateur sur la machine du signataire peut le lever (commande « signer unhalt »).")
        }
        .confirmationDialog("Révoquer toutes les sessions ?", isPresented: $confirmRevoke, titleVisibility: .visible) {
            Button("Révoquer toutes les sessions", role: .destructive) { Task { do { try await model.revokeAllSessions() } catch { message = model.describe(error) } } }
            Button("Annuler", role: .cancel) {}
        } message: { Text("Toutes les sessions ouvertes (ce Mac, le site, les autres appareils) sont fermées. Les mandats et autorisations déjà accordés au signataire ne sont pas révoqués par cette action.") }
    }

    private func signerCard(_ s: SecurityOverview) -> some View {
        Card("Signataire isolé") {
            if s.signer.reachable {
                Label("Joignable", systemImage: "checkmark.shield.fill").foregroundStyle(Theme.positive)
                Field(label: "Identifiant de clé", value: s.signer.keyId ?? "—", mono: true)
                Field(label: "Journal du signataire", value: "\(s.signer.journalLength.map(String.init) ?? "—") entrées")
                if let h = s.signer.journalHead { Field(label: "Tête du journal", value: h, mono: true) }
                Field(label: "Version de la politique", value: s.signer.policy?["version"]?.intValue.map(String.init) ?? "—")
            } else {
                Label("Injoignable", systemImage: "xmark.shield.fill").foregroundStyle(Theme.negative)
                Text("Rien ne peut être signé tant que le signataire est injoignable. Les soldes restent lus par l’API.").foregroundStyle(.secondary)
            }
            Field(label: "Origine attendue", value: s.origin ?? "—")
            if s.broadcast == false { Banner(.warning, "Ce serveur signe mais ne diffuse PAS les transactions (mode test).") }
        }
    }

    private func haltCard(_ s: SecurityOverview) -> some View {
        Card("Arrêt d’urgence") {
            switch s.signer.halted {
            case true?: Banner(.danger, "ACTIF. Le signataire refuse tout ce qui déplace des fonds ou ajoute du risque. Levée : opérateur sur la machine du signataire uniquement.")
            case false?: Label("Inactif", systemImage: "checkmark.circle").foregroundStyle(Theme.positive)
            case nil: Label("État inconnu (signataire injoignable)", systemImage: "questionmark.circle").foregroundStyle(Theme.warning)
            }
            Text("À utiliser en cas de doute sur la sécurité du portefeuille, d’un appareil ou du serveur. Action à sens unique depuis l’app.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button(role: .destructive) { confirmHalt = true } label: { Label("Arrêt d’urgence…", systemImage: "hand.raised.fill") }
                .controlSize(.large).disabled(!model.canOperate || s.signer.halted == true || working)
        }
    }

    private func limitsCard(_ s: SecurityOverview) -> some View {
        Card("Limites du signataire", trailing: AnyView(ProvenanceTag(p: .verified, text: "Lues sur le signataire"))) {
            if let pol = s.signer.policy, let perTx = pol["perTx"]?.objectValue {
                let daily = pol["daily"]?.objectValue ?? [:], spent = s.signer.spentToday ?? [:]
                // show the assets held or already used today first; the full table has hundreds of rows
                let held = Set((model.portfolio?.value.balances ?? []).filter(\.isNonZero).map { "\($0.network):\($0.symbol)" })
                let keys = perTx.keys.filter { held.contains($0) || spent[$0] != nil }.sorted()
                Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 5) {
                    GridRow { Text("Actif").bold(); Text("Par opération").bold(); Text("Par jour (UTC)").bold(); Text("Dépensé aujourd’hui").bold() }
                    ForEach(keys, id: \.self) { k in
                        GridRow {
                            Text(label(k))
                            Text(units(perTx[k]?.stringValue, k)).monospacedDigit()
                            Text(units(daily[k]?.stringValue, k)).monospacedDigit()
                            Text(units(spent[k] ?? "0", k)).monospacedDigit().foregroundStyle(spent[k] == nil ? .secondary : .primary)
                        }
                    }
                }.font(.callout)
                if keys.isEmpty { Text("Aucun actif détenu n’a de limite à afficher.").foregroundStyle(.secondary) }
                Text("\(perTx.count) limites au total (affichées : actifs détenus ou utilisés aujourd’hui). Fenêtre d’approbation maximale : \(pol["maxApprovalTtlSec"]?.intValue.map { "\($0) s" } ?? "—"). Liste de destinations autorisées : \((pol["allowlist"]?.arrayValue?.isEmpty ?? true) ? "aucune restriction" : "\(pol["allowlist"]!.arrayValue!.count) adresse(s)").")
                    .font(.caption).foregroundStyle(.secondary)
                if let fees = pol["maxFee"]?.objectValue {
                    DisclosureGroup("Plafonds de frais par réseau (\(fees.count))") {
                        Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 3) {
                            ForEach(fees.keys.sorted(), id: \.self) { n in
                                GridRow { Text(model.network(n)?.name ?? n)
                                    Text(feeUnits(fees[n]?.stringValue, n)).monospacedDigit() }
                            }
                        }.font(.callout).padding(.top, 4)
                    }
                }
                Text("Ces limites sont appliquées par le signataire lui-même et ne peuvent être modifiées que dans son fichier de politique, sur sa machine. Cette app ne peut ni les relever ni les contourner.").font(.caption).foregroundStyle(.secondary)
            } else { Text("Politique non lue (signataire injoignable).").foregroundStyle(.secondary) }
        }
    }
    private func decimals(_ key: String) -> (Int, String)? {
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init); guard parts.count == 2, let n = model.network(parts[0]) else { return nil }
        return n.assets.first { $0.symbol == parts[1] }.map { ($0.decimals, $0.symbol) }
    }
    private func label(_ key: String) -> String { let p = key.split(separator: ":", maxSplits: 1).map(String.init); return p.count == 2 ? "\(p[1]) · \(model.network(p[0])?.name ?? p[0])" : key }
    private func units(_ v: String?, _ key: String) -> String {
        guard let v else { return "—" }
        guard let (d, sym) = decimals(key), let u = try? BaseUnits(v) else { return "\(v) (unités de base)" }
        return "\(Fmt.amount(u.formatted(decimals: d), maxFraction: 8)) \(sym)"
    }
    private func feeUnits(_ v: String?, _ net: String) -> String {
        guard let v, let n = model.network(net), let u = try? BaseUnits(v) else { return v ?? "—" }
        return "\(Fmt.amount(u.formatted(decimals: n.native.decimals), maxFraction: 9)) \(n.native.symbol)"
    }

    private var rpcCard: some View {
        Card("État des RPC", trailing: AnyView(Text("relevé \(Fmt.relative(model.health?.fetchedAt))").font(.caption).foregroundStyle(.secondary))) {
            if let h = model.health?.value {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), alignment: .leading)], alignment: .leading, spacing: 5) {
                    ForEach(h.networks, id: \.self) { n in
                        Label(model.network(n.network ?? "")?.name ?? n.network ?? "?", systemImage: n.ok == true ? "circle.fill" : n.ok == false ? "xmark.circle.fill" : "circle")
                            .foregroundStyle(n.ok == true ? Theme.positive : n.ok == false ? Theme.negative : .secondary).font(.callout).help(n.readable == false ? "Chaîne illisible" : "")
                    }
                }
            } else { Text("Non lu.").foregroundStyle(.secondary) }
        }
    }

    private func devicesCard(_ s: SecurityOverview) -> some View {
        Card("Passkeys enrôlées") {
            ForEach(s.devices) { d in
                HStack {
                    Image(systemName: "person.badge.key")
                    VStack(alignment: .leading) {
                        Text(d.label).fontWeight(.medium)
                        Text("créée \(Fmt.date(d.createdAt)) · dernière utilisation \(Fmt.relative(d.lastUsedAt))" + (d.backedUp == true ? " · synchronisée" : "")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if d.enrolledOnSigner == true { ProvenanceTag(p: .verified, text: "Épinglée par le signataire") }
                    else if d.enrolledOnSigner == false { ProvenanceTag(p: .unavailable, text: "Inconnue du signataire") }
                }
            }
            Divider()
            HStack {
                TextField("Nom de la nouvelle passkey", text: $newLabel).frame(width: 200)
                Button("Ajouter une passkey sur ce Mac…") { Task { await addPasskey() } }.disabled(!model.canOperate || working || newLabel.isEmpty || AppEnvironment.isDevelopment)
            }
            Text("Deux demandes système : la création de la nouvelle passkey, puis une signature par une passkey DÉJÀ enrôlée — c’est cette signature que le signataire vérifie avant d’épingler la nouvelle clé.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sessionsCard(_ s: SecurityOverview) -> some View {
        Card("Sessions actives") {
            ForEach(Array(s.sessions.enumerated()), id: \.offset) { _, x in
                VStack(alignment: .leading) {
                    Text(x.ua.map { $0.count > 60 ? String($0.prefix(60)) + "…" : $0 } ?? "Client inconnu").lineLimit(1)
                    Text("\(x.ip ?? "?") · ouverte \(Fmt.date(x.createdAt)) · vue \(Fmt.relative(x.lastSeen))").font(.caption).foregroundStyle(.secondary)
                }
            }
            if s.sessions.isEmpty { Text("Aucune.").foregroundStyle(.secondary) }
            Text("Une session expire après 30 minutes d’inactivité et au plus 12 heures.").font(.caption).foregroundStyle(.secondary)
            Button("Révoquer toutes les sessions…", role: .destructive) { confirmRevoke = true }.disabled(!model.canOperate)
        }
    }

    private var auditCard: some View {
        Card("Journal d’audit", trailing: AnyView(TextField("Filtrer", text: $auditFilter).textFieldStyle(.roundedBorder).frame(width: 180))) {
            if let j = journal {
                if j.intact { Label("Chaîne de hachage intacte — \(j.total) événements vérifiés par le serveur", systemImage: "checkmark.seal").foregroundStyle(Theme.positive).font(.callout) }
                else { Banner(.danger, "CHAÎNE D’AUDIT ROMPUE à l’événement \(j.brokenAt.map(String.init) ?? "?") : le journal a pu être altéré.") }
                let q = auditFilter.lowercased()
                let ev = j.events.filter { q.isEmpty || $0.type.lowercased().contains(q) || $0.actor.lowercased().contains(q) || ($0.data?.displayText.lowercased().contains(q) ?? false) }
                ForEach(ev.prefix(150)) { e in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(Fmt.dateSeconds(e.ts)).monospacedDigit().foregroundStyle(.secondary).frame(width: 165, alignment: .leading)
                        Text(e.type).fontWeight(.medium).frame(width: 190, alignment: .leading)
                        Text(e.actor).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                        Text(e.data?.displayText ?? "").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                    }.font(.callout)
                }
            } else { Text(journalError ?? (model.canOperate ? "Lecture…" : "Indisponible hors connexion.")).foregroundStyle(.secondary) }
        }
    }

    private func loadJournal() async {
        guard model.canOperate else { return }
        do { journal = try await model.wallet.audit(limit: 300); journalError = nil } catch { journalError = model.describe(error) }
    }
    private func halt() async {
        working = true; defer { working = false }
        do { try await model.wallet.emergencyHalt(); message = "Arrêt d’urgence engagé. Le signataire refuse désormais toute opération qui déplace des fonds."; Notifier.post(title: "Arrêt d’urgence engagé", body: "Le signataire refuse toute opération jusqu’à la levée par un opérateur.")
            await model.refreshAll(); await loadJournal()
        } catch { message = "ÉCHEC de l’arrêt d’urgence : \(model.describe(error)). L’arrêt n’est PAS confirmé." }
    }
    private func addPasskey() async {
        working = true; defer { working = false }
        do { try await model.auth.addPasskey(label: newLabel, authenticator: model.authenticator); message = "Passkey « \(newLabel) » ajoutée et épinglée par le signataire."; await model.refreshSecurity() }
        catch PasskeyError.cancelled { message = nil }
        catch { message = model.describe(error) }
    }
}
