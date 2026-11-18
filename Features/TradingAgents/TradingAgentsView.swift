// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/TradingAgents/TradingAgentsView.swift
// Description: Entry of the trading-agents section: the emergency stop always on top, then two tabs — the agents (list, engine runtime, server locks, one agent's detail) and the programmable trading API (keys, webhooks, usage). Nothing here starts, funds or authorizes anything by being displayed.
import SwiftUI
import SPWalletCore

struct TradingAgentsView: View {
    let model: AppModel
    enum Tab: String, CaseIterable { case agents = "Agents", api = "API de trading" }
    @State private var tab: Tab = .agents
    @State private var store: AgentsStore?
    @State private var selected: String?
    @State private var creating = false

    var body: some View {
        Page("Agents de trading", subtitle: "Des stratégies automatiques, toujours bornées. Recherche et papier sont des simulations ; le réel n’existe que sous un mandat que vous approuvez avec votre passkey et révoquez sans elle.") {
            if let store {
                KillSwitchBar(model: model, store: store)
                if !model.canOperate { Banner(.warning, model.isOffline ? "Portefeuille injoignable : lecture seule des dernières données, aucune opération possible." : "Session requise : aucune opération possible.") }
                Picker("Section", selection: $tab) { ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 360)
                switch tab {
                case .agents:
                    if let id = selected { AgentDetailView(model: model, store: store, id: id) { selected = nil } .id(id) }
                    else { AgentsListView(model: model, store: store, onOpen: { selected = $0 }, onCreate: { creating = true }) }
                case .api: TradingAPIView(model: model, locks: store.locks)
                }
            } else { ProgressView() }
        }
        .task {
            if store == nil { store = AgentsStore(model: model) }
            await store?.poll()
        }
        .sheet(isPresented: $creating) {
            if let store { AgentCreateSheet(model: model, store: store) { created in creating = false; if let created { selected = created }; Task { await store.refresh() } } }
        }
        .sheet(isPresented: Binding(get: { store?.release != nil }, set: { _ in })) {
            if let store, let a = store.release { KillSwitchReleaseSheet(store: store, approval: a) }
        }
    }
}

/// The global emergency stop of every agent, key and mandate. Engage: one click and a confirmation, never a passkey. Release: the passkey.
struct KillSwitchBar: View {
    let model: AppModel
    let store: AgentsStore
    @State private var confirming = false

    var body: some View {
        let k = store.killSwitch
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: k?.engaged == true ? "hand.raised.fill" : "hand.raised").font(.title2).foregroundStyle(k?.engaged == true ? Theme.negative : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    if let k {
                        Text(k.engaged ? "ARRÊT D’URGENCE ENGAGÉ" : "Arrêt d’urgence : non engagé").font(.headline).foregroundStyle(k.engaged ? Theme.negative : .primary)
                        if k.engaged {
                            Text("Aucun agent, aucune clé et aucun mandat ne peut ajouter de risque. Les annulations et les ordres strictement réducteurs passent encore.").font(.callout).fixedSize(horizontal: false, vertical: true)
                            Text("Engagé \(Fmt.date(k.at))\(k.by.map { " par \($0)" } ?? "")\(k.reason.map { " — \($0)" } ?? "")").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        } else {
                            Text("Un clic et une confirmation, sans passkey : plus aucun agent, clé ou mandat ne peut ajouter de risque. Le lever exige votre passkey.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        if k.readOnly { Text("Mode lecture seule actif\(k.readOnlyReason.map { " : \($0)" } ?? "") — seules les annulations passent.").font(.caption).foregroundStyle(Theme.warning) }
                    } else {
                        Text("Arrêt d’urgence : état inconnu").font(.headline)
                        Text(store.runtimeError ?? "L’état n’a pas encore été lu sur le serveur. Il n’est pas présumé levé.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if store.killBusy { ProgressView().controlSize(.small) }
                if k?.engaged == true {
                    Button { Task { await store.prepareRelease() } } label: { Label("Lever avec la passkey…", systemImage: "touchid") }.disabled(!model.canOperate || store.killBusy)
                } else {
                    // engaging is allowed even when the last state read is unknown: it only removes authority
                    Button(role: .destructive) { confirming = true } label: { Label("Arrêt d’urgence", systemImage: "hand.raised.fill").fontWeight(.semibold) }
                        .buttonStyle(.borderedProminent).tint(Theme.negative).controlSize(.large).disabled(model.phase != .signedIn || store.killBusy)
                        .help("Engage l’arrêt d’urgence global des agents. Aucune passkey n’est demandée.")
                }
            }
            if let e = store.killError, store.release == nil { Banner(.danger, e) }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background((k?.engaged == true ? Theme.negative : Color.secondary).opacity(k?.engaged == true ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: Theme.corner))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner).strokeBorder((k?.engaged == true ? Theme.negative : Theme.stroke).opacity(0.6)))
        .confirmationDialog("Engager l’arrêt d’urgence des agents ?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Engager l’arrêt d’urgence", role: .destructive) { Task { await store.engageKillSwitch() } }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Effet immédiat pour tous les agents, toutes les clés d’API et tous les mandats : plus aucun nouveau risque. Les positions ouvertes ne sont PAS fermées par ce bouton ; les annulations et les ordres réducteurs restent possibles. Lever l’arrêt exigera votre passkey.")
        }
    }
}

/// Release of the kill switch: the fields of the verified release intent, then the passkey.
struct KillSwitchReleaseSheet: View {
    let store: AgentsStore
    let approval: RiskSwitchReleaseApproval
    @State private var understood = false

    var body: some View {
        let i = approval.intent
        SheetScaffold(title: "Lever l’arrêt d’urgence", width: 680, height: 560) {
            Banner(.warning, "Lever l’arrêt redonne aux mandats en vigueur la possibilité d’ajouter du risque. Les agents arrêtés ou en pause ne repartent pas seuls.")
            ReviewLines(lines: [
                ReviewLine(label: "Opération", value: "Levée de l’arrêt d’urgence global (\(i.kind.rawValue))", style: .strong),
                ReviewLine(label: "Engagé le", value: Fmt.dateSeconds(AgentText.ms(i.engagedAt))),
                ReviewLine(label: "Engagé par", value: i.engagedBy ?? "—"),
                ReviewLine(label: "Raison enregistrée", value: i.reason ?? "—"),
                ReviewLine(label: "Intention préparée le", value: Fmt.dateSeconds(AgentText.ms(i.createdAt))),
                ReviewLine(label: "Nonce", value: i.nonce, style: .address),
            ])
            BindingProof(digest: approval.approval.digest, expiry: i.expiry)
            AckToggle(isOn: $understood, text: "Je comprends que les mandats encore en vigueur pourront de nouveau engager du risque dès la levée.")
        } footer: {
            if let e = store.killError { Banner(.danger, e) }
            HStack {
                Button("Annuler") { store.cancelRelease() }.disabled(store.releasing)
                Spacer()
                if store.releasing { ProgressView().controlSize(.small); Text("Passkey…").foregroundStyle(.secondary) }
                Button { Task { await store.approveRelease() } } label: { Label("Lever avec la passkey", systemImage: "touchid") }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(!understood || store.releasing)
            }
        }
        .interactiveDismissDisabled()
    }
}

struct AgentsListView: View {
    let model: AppModel
    let store: AgentsStore
    let onOpen: (String) -> Void
    let onCreate: () -> Void

    var body: some View {
        Card("Agents", trailing: AnyView(HStack(spacing: 10) {
            if store.agentsFromCache { ProvenanceTag(p: .stale, text: "Données du \(Fmt.date(store.agentsAt))") }
            if store.loading { ProgressView().controlSize(.small) }
            Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }.help("Relire sur le serveur").disabled(model.phase != .signedIn)
            Button { onCreate() } label: { Label("Nouvel agent…", systemImage: "plus") }.disabled(!model.canOperate)
        })) {
            if let e = store.agentsError { Banner(.danger, "Liste indisponible : \(e)") }
            if let agents = store.agents {
                if agents.isEmpty { EmptyState(symbol: "cpu", title: "Aucun agent", detail: "Un agent se crée en recherche ou en simulation, avec toutes ses limites. Rien ne peut être négocié en réel tant que vous n’avez pas approuvé un mandat avec votre passkey.") }
                else { VStack(spacing: 8) { ForEach(agents) { a in AgentRow(agent: a, lease: store.runtime?.leases.first { $0.agentId == a.id }) { onOpen(a.id) } } } }
            } else if store.agentsError == nil { ProgressView() }
            HStack(spacing: 8) { ForEach([AgentMode.research, .paper, .live], id: \.self) { ModeTag(kind: ModeKind($0)) }; ModeTag(kind: ModeKind(.live, liveNetwork: "testnet")) }
            Text("La couleur et l’étiquette du mode accompagnent chaque agent, chaque chiffre et chaque bouton. Les chiffres de modes différents ne sont jamais additionnés.").font(.caption).foregroundStyle(.secondary)
        }
        RuntimeCard(store: store)
        LocksCard(store: store)
    }
}

/// One agent in the list: the mode band on the leading edge, then name, state, strategy family, markets, network or venue.
struct AgentRow: View {
    let agent: Agent
    let lease: AgentRuntimeStatus.Lease?
    let open: () -> Void

    var body: some View {
        let kind = ModeKind(agent: agent)
        Button(action: open) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(agent.name).font(.headline).lineLimit(1)
                        ModeTag(kind: kind)
                        if agent.tradesRealMoney { Label("Argent réel engagé", systemImage: "exclamationmark.triangle.fill").font(.caption.weight(.semibold)).foregroundStyle(kind.color) }
                    }
                    Text("\(AgentText.phase(agent.state)) · \(AgentText.kind(agent.resolvedKind))\(agent.family.map { " · \(AgentText.family($0))" } ?? "")\(agent.template.map { " · modèle \($0)" } ?? "")").font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    Text("Marchés : \(agent.universe.isEmpty ? "—" : agent.universe.joined(separator: ", ")) · \(agent.resolvedKind == .spot ? "Réseau" : "Plateforme") : \(agent.networkName ?? agent.network) · pas \(agent.interval)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if let r = agent.stopReason, !r.isEmpty { Text("Motif d’arrêt : \(r)").font(.caption).foregroundStyle(Theme.warning).lineLimit(2) }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(Fmt.amount(agent.capitalUsdc, maxFraction: 2)) USDC").monospacedDigit().fontWeight(.medium)
                    Text(agent.hasVault ? "capital prévu (coffre)" : "capital \(kind.mode == .live ? "de référence" : "simulé")").font(.caption).foregroundStyle(.secondary)
                    if let lease { Text(lease.active ? "Travailleur actif · \(Fmt.relative(lease.heartbeatAt))" : "Bail expiré").font(.caption2).foregroundStyle(lease.active ? Color.secondary : Theme.warning) }
                }
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8).padding(.trailing, 10).modeFramed(kind)
            .background(kind.color.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(agent.name), mode \(kind.title), \(AgentText.phase(agent.state))")
    }
}

/// The agent engine as the server reports it: workers, loops with their last pass, leases, queue.
struct RuntimeCard: View {
    let store: AgentsStore
    var body: some View {
        Card("Moteur des agents (état du serveur)") {
            if let r = store.runtime {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Field(label: "Travailleurs", value: "\(r.workers.inProcess ? "dans le processus de l’API" : "processus séparé")\(r.workers.mode.map { " · réglage : \($0)" } ?? "")")
                        Field(label: "File de tâches", value: "\(r.queue.queued) en attente · \(r.queue.running) en cours · \(r.queue.dead24h) abandonnée(s) en 24 h")
                        if let ms = r.queue.oldestQueuedMs { Field(label: "Plus ancienne en attente", value: "\(Int(ms / 1000)) s") }
                        Field(label: "Baux", value: r.leases.isEmpty ? "aucun agent tenu par un travailleur" : "\(r.leases.filter(\.active).count) actif(s) sur \(r.leases.count)")
                    }
                }
                if r.queue.dead24h > 0 { Banner(.warning, "\(r.queue.dead24h) tâche(s) abandonnée(s) après épuisement des tentatives dans les dernières 24 h.") }
                if !r.loops.isEmpty {
                    Divider()
                    Text("Boucles").font(.caption).foregroundStyle(.secondary)
                    ForEach(r.loops, id: \.name) { l in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: l.lastError == nil ? "checkmark.circle" : "exclamationmark.triangle.fill").foregroundStyle(l.lastError == nil ? Theme.positive : Theme.warning)
                            Text(l.name).font(Theme.monoSmall).frame(width: 220, alignment: .leading)
                            Text("dernière passe réussie : \(Fmt.relative(l.lastOkAt))\(l.runs.map { " · \($0) passes" } ?? "")\(l.failures.map { $0 > 0 ? " · \($0) échec(s)" : "" } ?? "")").font(.callout).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        }
                        if let e = l.lastError { Text("Dernière erreur (\(Fmt.relative(l.lastErrorAt))) : \(e)").font(.caption).foregroundStyle(Theme.warning).textSelection(.enabled) }
                    }
                }
                if !r.leases.isEmpty {
                    Divider()
                    Text("Baux des travailleurs").font(.caption).foregroundStyle(.secondary)
                    ForEach(r.leases, id: \.agentId) { l in
                        HStack(spacing: 10) {
                            Image(systemName: l.active ? "circle.fill" : "circle").font(.caption2).foregroundStyle(l.active ? Theme.positive : Theme.warning)
                            Text(store.agents?.first { $0.id == l.agentId }?.name ?? Fmt.short(l.agentId)).frame(width: 220, alignment: .leading).lineLimit(1)
                            Text("\(l.owner) · battement \(Fmt.relative(l.heartbeatAt)) · \(l.active ? "expire \(Fmt.relative(l.expiresAt))" : "EXPIRÉ")").font(.callout).foregroundStyle(.secondary).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                }
            } else if let e = store.runtimeError { Banner(.danger, "État du moteur indisponible : \(e)") }
            else { ProgressView() }
        }
    }
}

/// The server locks that gate real execution. A closed lock means the corresponding live controls do not exist in this app.
struct LocksCard: View {
    let store: AgentsStore
    static let relevant = ["deriv_live_mainnet", "deriv_mandate_mainnet", "deriv_mm_mainnet", "deriv_mm_testnet", "trading_api_execution", "broadcast", "workers"]
    var body: some View {
        Card("Verrous du serveur") {
            if let locks = store.locks {
                let shown = locks.filter { Self.relevant.contains($0.id) }, rest = locks.filter { !Self.relevant.contains($0.id) }
                ForEach(shown.isEmpty ? locks : shown) { l in LockRow(name: l.id, open: l.on, reason: l.why) }
                if !shown.isEmpty, !rest.isEmpty { DisclosureGroup("Autres capacités du serveur (\(rest.count))") { VStack(alignment: .leading, spacing: 6) { ForEach(rest) { l in LockRow(name: l.id, open: l.on, reason: l.why) } }.padding(.top, 6) } }
                Text("Ces réglages appartiennent au serveur. Quand un verrou est fermé, les commandes réelles correspondantes sont absentes de cette app ; seul l’état et sa raison sont affichés.").font(.caption).foregroundStyle(.secondary)
            } else if let e = store.locksError { Banner(.warning, "État des verrous indisponible : \(e) Les commandes réelles restent soumises au refus du serveur.") }
            else { ProgressView() }
        }
    }
}
