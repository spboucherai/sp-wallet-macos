// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/Alerts/AlertsListTab.swift
// Description: The list of the server's alerts: severity, type (the catalogue's French title), time, read state and the alert's own sentence; filters by severity, catalogue group, subject and unread; read marks; the live state of the stream; and a detail pane with every fact the server attached to the alert.
import SwiftUI
import SPWalletCore

struct AlertsListTab: View {
    let model: AppModel
    @Bindable var center: AlertsCenter
    @State private var selection: Set<WalletAlert.ID> = []
    @State private var notifyLevel = AlertsNotifyLevel.stored
    @State private var notifyDetails = AlertsNotifyLevel.showDetails
    @State private var confirmAllRead = false

    var body: some View {
        let rows = center.shown
        VStack(spacing: 0) {
            filters
            if let e = center.error { Banner(.danger, e).padding(.horizontal, 24).padding(.bottom, 8) }
            if center.fromCache, let d = center.loadedAt { Banner(.warning, "Liste lue le \(Fmt.date(d)) — elle n’a pas pu être rafraîchie. Des alertes plus récentes peuvent manquer.").padding(.horizontal, 24).padding(.bottom, 8) }
            Table(rows, selection: $selection) {
                TableColumn("") { a in Circle().fill(a.isRead ? Color.clear : Theme.accent).frame(width: 8, height: 8).accessibilityLabel(a.isRead ? "Lue" : "Non lue") }.width(14)
                TableColumn("Gravité") { a in Label(AlertsText.severity(a.severity), systemImage: AlertsText.symbol(a.severity)).foregroundStyle(AlertsText.color(a.severity)).font(.callout) }.width(min: 110, ideal: 130)
                TableColumn("Type") { a in Text(AlertsText.sentence(a).title).fontWeight(a.isRead ? .regular : .semibold).lineLimit(1) }.width(min: 170, ideal: 230)
                TableColumn("Fait rapporté") { a in
                    let body = AlertsText.sentence(a).body
                    Text(body.isEmpty ? "—" : body).lineLimit(1).foregroundStyle(a.isRead ? .secondary : .primary).help(body)
                }.width(min: 220, ideal: 420)
                TableColumn("Groupe") { a in Text(AlertsText.group(a.group)).foregroundStyle(.secondary) }.width(min: 80, ideal: 100)
                TableColumn("Date") { a in Text(Fmt.date(a.ts)).monospacedDigit().foregroundStyle(.secondary) }.width(min: 130, ideal: 150)
                TableColumn("×") { a in Text(a.count > 1 ? "\(a.count)" : "").monospacedDigit().help("Occurrences regroupées dans cette alerte") }.width(30)
            }
            .contextMenu(forSelectionType: WalletAlert.ID.self) { ids in
                Button("Marquer comme lue\(ids.count > 1 ? "s" : "")") { Task { await center.markRead(Array(ids)) } }.disabled(!model.canOperate || ids.isEmpty)
            }
            .overlay {
                if center.loading && rows.isEmpty { ProgressView() }
                else if rows.isEmpty {
                    EmptyState(symbol: "bell.slash", title: center.loadedAt == nil ? "Alertes non lues depuis le serveur" : "Aucune alerte ne correspond",
                               detail: center.theme != nil ? "Le filtre par sujet s’applique aux \(center.items.count) alertes déjà chargées. Chargez-en davantage ou retirez-le." : nil)
                }
            }
            footer(rows: rows)
            if selection.count == 1, let id = selection.first, let a = center.items.first(where: { $0.id == id }) {
                Divider()
                AlertsDetailPane(model: model, center: center, alert: a).frame(maxHeight: 290)
            }
        }
        .confirmationDialog("Marquer toutes les alertes comme lues ?", isPresented: $confirmAllRead) {
            Button("Tout marquer comme lu") { Task { await center.markAllRead() } }
            Button("Annuler", role: .cancel) {}
        } message: { Text("Cela concerne toutes les alertes du serveur, y compris celles qui ne sont pas affichées (\(center.counters?.unread ?? 0) non lues, dont \(center.counters?.critical ?? 0) critiques).") }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Picker("Gravité", selection: $center.severity) {
                    Text("Toutes gravités").tag(AlertSeverity?.none)
                    ForEach([AlertSeverity.critical, .warning, .info], id: \.self) { Text(AlertsText.severity($0)).tag(AlertSeverity?.some($0)) }
                }.frame(width: 170)
                Picker("Groupe", selection: $center.group) {
                    Text("Tous groupes").tag(AlertGroup?.none)
                    ForEach(AlertGroup.allCases, id: \.self) { Text(AlertsText.group($0)).tag(AlertGroup?.some($0)) }
                }.frame(width: 150)
                Picker("Sujet", selection: $center.theme) {
                    Text("Tous sujets").tag(AlertsTheme?.none)
                    ForEach(AlertsTheme.allCases) { Text($0.label).tag(AlertsTheme?.some($0)) }
                }.frame(width: 210).help("Classement plus fin que les groupes du catalogue, appliqué aux alertes chargées. « Solde insuffisant » et « Frais élevés » n’ont pas de type propre sur le serveur : ils sont reconnus dans le motif d’un échec ou d’un refus.")
                Toggle("Non lues seulement", isOn: $center.unreadOnly).toggleStyle(.checkbox)
                Spacer()
                AlertsLiveBadge(state: center.live)
                Button { Task { await center.reload() } } label: { Image(systemName: "arrow.clockwise") }.help("Relire la liste").disabled(center.loading)
            }.labelsHidden()
            HStack(spacing: 10) {
                Text("Notifications macOS des nouvelles alertes :").font(.callout).foregroundStyle(.secondary)
                Picker("Seuil", selection: $notifyLevel) { ForEach(AlertsNotifyLevel.allCases) { Text($0.label).tag($0) } }.labelsHidden().frame(width: 250)
                    .onChange(of: notifyLevel) { AlertsNotifyLevel.stored = notifyLevel }
                Toggle("Montants et motifs dans le texte", isOn: $notifyDetails).toggleStyle(.checkbox)
                    .onChange(of: notifyDetails) { AlertsNotifyLevel.showDetails = notifyDetails }
                    .help("Désactivé : la notification ne contient que des noms, réseaux et compteurs (formulation « écran verrouillé » du serveur).")
                if !Notifier.enabled { Label("Notifications désactivées dans Réglages de l’app", systemImage: "bell.slash").font(.caption).foregroundStyle(Theme.warning) }
                Spacer()
            }
            if let t = center.theme, t.derivedFromReason {
                Text("« \(t.label) » n’est pas un type d’alerte du serveur : les lignes affichées sont des échecs ou refus dont le motif renvoyé par le serveur contient ces termes.").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.horizontal, 24).padding(.vertical, 10)
    }

    private func footer(rows: [WalletAlert]) -> some View {
        HStack(spacing: 12) {
            Text("\(rows.count) affichées\(center.theme != nil ? " sur \(center.items.count) chargées" : "")").font(.callout).foregroundStyle(.secondary)
            if let d = center.loadedAt { ProvenanceTag(p: center.fromCache ? .stale : .verified, text: center.fromCache ? "Lue le \(Fmt.date(d))" : "Lue sur le serveur \(Fmt.relative(d))") }
            if !center.reachedEnd && !center.fromCache {
                Button(center.loadingMore ? "Chargement…" : "Charger des alertes plus anciennes") { Task { await center.loadMore() } }.disabled(center.loadingMore)
            } else if center.loadedAt != nil && !center.fromCache { Text("Fin de l’historique pour ces filtres.").font(.callout).foregroundStyle(.secondary) }
            Spacer()
            if center.marking { ProgressView().controlSize(.small) }
            Button("Marquer la sélection comme lue") { Task { await center.markRead(Array(selection)) } }
                .disabled(!model.canOperate || center.marking || !selection.contains { id in center.items.first { $0.id == id }?.isRead == false })
            Button("Tout marquer comme lu…") { confirmAllRead = true }.disabled(!model.canOperate || center.marking || (center.counters?.unread ?? 0) == 0)
        }.padding(.horizontal, 24).padding(.vertical, 8)
    }
}

struct AlertsLiveBadge: View {
    let state: AlertsCenter.Live
    var body: some View {
        let (text, color, symbol): (String, Color, String) = {
            switch state {
            case .idle: ("Veille arrêtée", .secondary, "pause.circle")
            case .paused: ("En pause (app inactive, hors ligne ou session absente)", .secondary, "pause.circle")
            case .connecting: ("Connexion au flux…", Theme.warning, "dot.radiowaves.left.and.right")
            case .streaming(let since): ("En direct depuis \(since.formatted(date: .omitted, time: .shortened))", Theme.positive, "dot.radiowaves.left.and.right")
            case .reconnecting(let at, _): ("Reconnexion à \(at.formatted(date: .omitted, time: .standard))", Theme.warning, "arrow.triangle.2.circlepath")
            case .polling: ("Relevé des compteurs chaque minute", .secondary, "clock")
            }
        }()
        Label(text, systemImage: symbol).font(.caption).foregroundStyle(color)
            .help({ if case .reconnecting(_, let reason) = state { return reason }; return "Le flux en direct transporte les compteurs d’alertes ; la liste est relue à chaque changement." }())
    }
}

struct AlertsDetailPane: View {
    let model: AppModel
    let center: AlertsCenter
    let alert: WalletAlert

    var body: some View {
        let a = alert, t = AlertsText.sentence(a)
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: AlertsText.symbol(a.severity)).foregroundStyle(AlertsText.color(a.severity)).font(.title2)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.title).font(.headline)
                        Text("\(AlertsText.severity(a.severity)) · \(AlertsText.group(a.group)) · \(Fmt.dateSeconds(a.ts))").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if a.isRead { Text("Lue le \(Fmt.date(a.readAt))").font(.caption).foregroundStyle(.secondary) }
                    else { Button("Marquer comme lue") { Task { await center.markRead([a.id]) } }.disabled(!model.canOperate || center.marking) }
                }
                if !t.body.isEmpty { Text(t.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                if AlertCatalog.definition(a.kind) == nil {
                    Banner(.info, "Ce type d’alerte n’est pas connu de cette version de l’app : il est affiché tel que le serveur l’a envoyé, sans interprétation.")
                }
                if let def = AlertCatalog.definition(a.kind), def.severity != a.severity {
                    Text("Gravité par défaut de ce type : \(AlertsText.severity(def.severity)). Cette alerte porte la sienne.").font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                Text("Faits joints par le serveur").font(.caption).foregroundStyle(.secondary)
                ForEach(a.params.keys.sorted(), id: \.self) { k in
                    if let v = a.params[k] { Field(label: AlertsText.param(k), value: AlertsText.value(v), mono: ["to", "from", "ip", "clientId"].contains(k)) }
                }
                Field(label: "Code du type", value: a.kind.rawValue, mono: true)
                Field(label: "Identifiant", value: String(a.id), mono: true)
                if let s = a.subject, s.type != "none" { Field(label: "Concerne", value: AlertsText.subject(s), mono: s.id != nil) }
                Field(label: "Écran concerné", value: AlertsText.destination(a.path))
                let themes = AlertsTheme.of(a)
                if !themes.isEmpty { Field(label: "Sujets", value: AlertsTheme.allCases.filter(themes.contains).map(\.label).joined(separator: ", ")) }
                Field(label: "Notification serveur", value: AlertsText.delivery(a.delivery))
                if let p = a.channels?.push { Field(label: "Push web", value: "\(p.sent) remis au service, \(p.failed) en échec, \(p.removed) appareils retirés") }
                if let w = a.channels?.webhook { Field(label: "Webhook", value: w.ok ? "Accepté par le destinataire (HTTP \(w.status))" : (w.status == 0 ? "Aucune réponse du destinataire" : "Refusé par le destinataire (HTTP \(w.status))")) }
            }.padding(16)
        }
    }
}
