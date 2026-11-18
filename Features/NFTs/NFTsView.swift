// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/NFTs/NFTsView.swift
// Description: Entry of the NFT feature: the gallery of the wallet's NFTs (virtualized grid, filters by network / collection / status, search, sort, grouping), the honest account of where the inventory comes from (which provider, when, what is not discovered), the synchronisation the server offers, and the navigation to an item, a collection, the explicit lookup / manual tracking and the signer's NFT controls. Remote names are plain text, media only ever comes through the server's proxy, and there is no market write anywhere: the backend has none.
import SwiftUI
import SPWalletCore

enum NFTRoute: Hashable {
    case item(String)
    case collection(String)
    case controls
}

/// Plain text, never Markdown, never a localisation key: the only way server-provided text is put on screen.
func NFTPlain(_ s: String) -> Text { Text(verbatim: s) }

struct NFTsView: View {
    let model: AppModel
    @State private var gallery: NFTGallery?
    @State private var path: [NFTRoute] = []

    var body: some View {
        Group {
            if let gallery {
                switch path.last {
                case nil: NFTGalleryPage(model: model, gallery: gallery, open: { path.append($0) })
                case .item(let key): NFTItemPage(model: model, gallery: gallery, key: key, open: { path.append($0) }, back: back).id(key)
                case .collection(let key): NFTCollectionPage(model: model, gallery: gallery, key: key, open: { path.append($0) }, back: back).id(key)
                case .controls: NFTControlsPage(model: model, gallery: gallery, back: back)
                }
            } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .task {
            if gallery == nil { gallery = NFTGallery(model: model) }
            await gallery?.load()
        }
        .onDisappear { gallery?.stop() }
    }
    private func back() { if !path.isEmpty { path.removeLast() } }
}

/// The "‹ back" row every sub-page starts with.
struct NFTBackBar: View {
    let title: String
    let back: () -> Void
    var body: some View {
        Button(action: back) { Label(title, systemImage: "chevron.left") }.buttonStyle(.link)
    }
}

// MARK: - Gallery

private struct NFTGalleryPage: View {
    let model: AppModel
    @Bindable var gallery: NFTGallery
    let open: (NFTRoute) -> Void
    @State private var showLookup = false
    @State private var showSources = false

    private let columns = [GridItem(.adaptive(minimum: 172, maximum: 240), spacing: 14, alignment: .top)]

    var body: some View {
        Page("NFT", subtitle: "Inventaire découvert par les fournisseurs configurés sur le serveur, vérifié sur la chaîne à l’ouverture de chaque fiche.") {
            banners
            toolbar
            NFTSourcesCard(model: model, gallery: gallery, expanded: $showSources)
            if gallery.items.isEmpty { emptyInventory }
            else if gallery.sections.isEmpty {
                EmptyState(symbol: "line.3.horizontal.decrease.circle", title: "Aucun NFT ne correspond aux filtres",
                           detail: gallery.hiddenSpam > 0 ? "\(gallery.hiddenSpam) élément(s) signalé(s) comme indésirables par un indexeur sont masqués par le filtre actuel." : nil)
            } else {
                counts
                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    ForEach(gallery.sections) { section in
                        SwiftUI.Section {
                            ForEach(section.items) { item in tile(item) }
                        } header: {
                            NFTSectionHeader(section: section, open: open)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showLookup) { NFTLookupSheet(model: model, gallery: gallery, open: { showLookup = false; open($0) }, close: { showLookup = false }) }
    }

    private func tile(_ item: NFTSummary) -> some View {
        Button { open(.item(item.key)) } label: { NFTTile(item: item, gallery: gallery) }.buttonStyle(.plain)
    }

    @ViewBuilder private var banners: some View {
        if gallery.fromCache, let d = gallery.fetchedAt {
            Banner(.warning, "Lecture seule — inventaire tel que synchronisé par cette app le \(Fmt.date(d)). Il peut ne plus refléter la chaîne. Seules les miniatures déjà téléchargées sont affichées ; les transferts sont désactivés.")
        } else if !model.canOperate {
            Banner(.warning, "Session ou portefeuille indisponible : lecture seule, aucune synchronisation ni transfert possible.")
        }
        if let e = gallery.error { Banner(.danger, e) }
        if !gallery.complete { Banner(.warning, "Inventaire incomplet : la lecture s’est arrêtée à \(gallery.items.count) éléments sur \(gallery.total) annoncés par le serveur.") }
    }

    @ViewBuilder private var emptyInventory: some View {
        if gallery.loading || !gallery.loadedOnce { HStack { ProgressView().controlSize(.small); Text("Lecture de l’inventaire…").foregroundStyle(.secondary) } }
        else {
            EmptyState(symbol: "square.grid.2x2", title: "Aucun NFT dans l’inventaire",
                       detail: "Aucun NFT n’a été découvert pour les adresses de ce portefeuille. Sur les réseaux EVM, la découverte dépend du fournisseur configuré sur le serveur : sans lui, un NFT entre dans l’inventaire en le suivant à la main (bouton « Rechercher ou suivre »). Voir « Sources de l’inventaire » ci-dessus.")
        }
    }

    private var counts: some View {
        HStack {
            NFTPlain("\(gallery.visibleCount) affiché(s) sur \(gallery.items.count)").font(.callout).foregroundStyle(.secondary)
            if gallery.hiddenSpam > 0 {
                Button { gallery.spam = .show } label: { NFTPlain("\(gallery.hiddenSpam) signalé(s) comme indésirables masqué(s) — afficher") }.buttonStyle(.link).font(.callout)
            }
            Spacer()
            Text("Aucune valeur n’est attribuée aux NFT : ce portefeuille ne sait pas en établir une de façon fiable.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var toolbar: some View {
        Card {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Rechercher", text: $gallery.search, prompt: Text("Nom, collection, contrat, mint ou identifiant")).textFieldStyle(.plain)
                if !gallery.search.isEmpty { Button { gallery.search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary) }
                Divider().frame(height: 18)
                if gallery.loading { ProgressView().controlSize(.small) }
                Button { Task { await gallery.refresh() } } label: { Label("Relire", systemImage: "arrow.clockwise") }
                    .disabled(!gallery.canFetch || gallery.loading).help("Relit l’inventaire tel que le serveur le stocke maintenant. Ne lance pas de découverte : voir « Synchroniser ».")
                Button { showLookup = true } label: { Label("Rechercher ou suivre…", systemImage: "plus.magnifyingglass") }.disabled(!model.canOperate)
                Button { open(.controls) } label: { Label("Contrôles du signataire", systemImage: "lock.shield") }
            }
            Divider()
            HStack(spacing: 12) {
                Picker("Réseau", selection: $gallery.chain) {
                    Text("Tous les réseaux").tag("")
                    ForEach(gallery.chainsPresent, id: \.self) { NFTPlain(gallery.networkName($0)).tag($0) }
                }
                Picker("Collection", selection: $gallery.collection) {
                    Text("Toutes les collections").tag("")
                    ForEach(gallery.collectionsPresent, id: \.key) { c in NFTPlain("\(c.name) (\(c.count))").tag(c.key) }
                }
                Picker("État", selection: $gallery.status) { ForEach(NFTGallery.Status.allCases) { Text($0.label).tag($0) } }
                Picker("Indésirables", selection: $gallery.spam) { ForEach(NFTGallery.Spam.allCases) { Text($0.label).tag($0) } }
            }.labelsHidden()
            HStack(spacing: 12) {
                Picker("Tri", selection: $gallery.sort) { ForEach(NFTGallery.Sort.allCases) { Text($0.label).tag($0) } }.frame(maxWidth: 220)
                Picker("Regroupement", selection: $gallery.grouping) { ForEach(NFTGallery.Grouping.allCases) { Text($0.label).tag($0) } }.frame(maxWidth: 220)
                if !gallery.collection.isEmpty { Button("Page de la collection") { open(.collection(gallery.collection)) } }
                Spacer()
            }.labelsHidden()
        }
    }
}

private struct NFTSectionHeader: View {
    let section: NFTGallerySection
    let open: (NFTRoute) -> Void
    var body: some View {
        if !section.title.isEmpty {
            HStack(spacing: 10) {
                NFTPlain(section.title).font(.headline)
                NFTPlain(String(section.items.count)).font(.callout).foregroundStyle(.secondary).monospacedDigit()
                if let key = section.collectionKey { Button("Page de la collection") { open(.collection(key)) }.buttonStyle(.link).font(.callout) }
                Spacer()
            }.padding(.top, 8)
        }
    }
}

/// One NFT of the grid. Its flags are on the tile itself: an indexer's spam signal, an item that left the wallet, a stale ownership.
struct NFTTile: View {
    let item: NFTSummary
    let gallery: NFTGallery

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            NFTThumbView(mediaId: item.image?.id, kind: item.image?.kind, pixels: NFTMediaStore.gridPixels, api: gallery.mediaAPI, maxBytes: gallery.mediaLimit)
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 3) {
                        if let s = item.spam { NFTFlag(text: "Indésirable selon \(NFTText.sourceName(s.by))", color: Theme.negative, symbol: "exclamationmark.triangle.fill") }
                        if !item.inWallet { NFTFlag(text: NFTText.ownership(item.state), color: Theme.warning) }
                    }.padding(6)
                }
                .overlay(alignment: .bottomTrailing) {
                    if item.quantity != "1" { NFTPlain("× \(Fmt.amount(item.quantity))").font(.caption.weight(.semibold)).monospacedDigit().padding(.horizontal, 6).padding(.vertical, 2).background(.thinMaterial, in: Capsule()).padding(6) }
                }
            NFTPlain(NFTClean.line(item.displayName, max: 80) ?? "Sans nom — \(Fmt.short(item.tokenId ?? item.assetId))").font(.callout.weight(.medium)).lineLimit(1)
                .foregroundStyle(item.displayName == nil ? .secondary : .primary)
            NFTPlain(NFTClean.line(item.collection?.name, max: 80) ?? "Sans collection").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: 4) {
                NFTPlain(gallery.networkName(item.chain)).lineLimit(1)
                Text("·")
                NFTPlain(NFTText.standardShort(item.standard)).lineLimit(1)
                if item.stale { Image(systemName: "clock.badge.exclamationmark").foregroundStyle(Theme.warning).help("La propriété n’a pas été relue récemment sur la chaîne.") }
                if item.origin == "manual" { Image(systemName: "pin").help("Suivi à la main") }
            }.font(.caption2).foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.corner))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner).strokeBorder(item.spam != nil ? Theme.negative.opacity(0.6) : Theme.stroke.opacity(0.6)))
        .contentShape(RoundedRectangle(cornerRadius: Theme.corner))
        .accessibilityElement(children: .combine)
    }
}

/// A square media tile: the downsampled bitmap, or a neutral placeholder that says why there is none.
struct NFTThumbView: View {
    let mediaId: String?
    let kind: String?
    let pixels: Int
    let api: NFTAPI?
    let maxBytes: Int
    @State private var thumbnail: NFTThumbnail?

    /// Kinds that are never downloaded for a tile: they are not images.
    private var nonImage: String? {
        switch kind {
        case "video": "Vidéo — ouvrir la fiche"
        case "audio": "Audio — ouvrir la fiche"
        case "html": "Média non affichable (document HTML)"
        case "model": "Média non affichable (modèle 3D)"
        default: nil
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.10))
            if mediaId == nil { placeholder("photo", "Aucun média déclaré") }
            else if let nonImage { placeholder(kind == "video" ? "film" : kind == "audio" ? "waveform" : "eye.slash", nonImage) }
            else {
                switch thumbnail {
                case .image(let image): Image(decorative: image, scale: 1).resizable().interpolation(.medium).aspectRatio(contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 8))
                case .notDisplayable(let why): placeholder("eye.slash", "Média non affichable").help(why)
                case .unavailable(let why): placeholder("icloud.slash", "Média indisponible").help(why)
                case nil: ProgressView().controlSize(.small)
                }
            }
        }
        .task(id: "\(mediaId ?? "")|\(api == nil)") {
            guard let mediaId, nonImage == nil else { return }
            let t = await NFTMediaStore.shared.thumbnail(id: mediaId, pixels: pixels, api: api, maxBytes: maxBytes)
            if !Task.isCancelled { thumbnail = t }
        }
    }
    private func placeholder(_ symbol: String, _ text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.tertiary)
            Text(text).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(8)
    }
}

// MARK: - Where the inventory comes from

private struct NFTSourcesCard: View {
    let model: AppModel
    let gallery: NFTGallery
    @Binding var expanded: Bool

    var body: some View {
        Card {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 12) {
                    if let caps = gallery.capabilities {
                        let listed = caps.chains.filter { $0.inventory != "unsupported" || !$0.sections.isEmpty }
                        ForEach(listed) { chain in row(chain) }
                        let others = caps.chains.count - listed.count
                        if others > 0 { Text("\(others) autre(s) réseau(x) du registre : aucun adaptateur NFT sur ce serveur.").font(.caption).foregroundStyle(.secondary) }
                        Divider()
                        Text("Fournisseurs du serveur").font(.subheadline.weight(.medium))
                        ForEach(caps.providers) { p in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: p.on ? "checkmark.circle.fill" : "minus.circle").foregroundStyle(p.on ? Theme.positive : .secondary)
                                NFTPlain(p.id).font(Theme.monoSmall)
                                NFTPlain(p.on ? "actif" : "inactif\(p.unlockedBy.map { " — s’active par la variable serveur \($0)" } ?? "")").foregroundStyle(.secondary)
                                Spacer()
                                NFTPlain("ce qui sort du serveur : \(p.sends)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if !caps.anyMarketWrite { Text("Aucune écriture de marché (mise en vente, achat, offre) n’existe dans le serveur : cette app n’en propose donc aucune.").font(.caption).foregroundStyle(.secondary) }
                    } else {
                        Text(gallery.loading ? "Lecture de la matrice de capacités…" : "Matrice de capacités indisponible.").foregroundStyle(.secondary)
                    }
                    if let e = gallery.syncError { Banner(.danger, e) }
                }.padding(.top, 8)
            } label: {
                HStack(spacing: 10) {
                    Text("Sources de l’inventaire").font(.headline)
                    NFTPlain(summaryLine).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    if !gallery.syncRunning.isEmpty {
                        ProgressView().controlSize(.small)
                        NFTPlain("Synchronisation en cours côté serveur : \(gallery.syncRunning.map(gallery.networkName).joined(separator: ", "))").font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Button { Task { await gallery.startSync(chain: nil) } } label: { Label("Synchroniser", systemImage: "arrow.triangle.2.circlepath") }
                        .disabled(!model.canOperate || gallery.syncStarting || !gallery.syncRunning.isEmpty)
                        .help("Demande au serveur d’interroger ses fournisseurs pour chaque réseau qui en a un (6 demandes par minute au plus). L’inventaire est relu quand le serveur a terminé.")
                }
            }
        }
    }

    private var summaryLine: String {
        guard let caps = gallery.capabilities else { return "" }
        let sources = Set(caps.chains.flatMap { $0.sections.filter { $0.status == "ok" }.compactMap(\.source) }).map(NFTText.sourceName).sorted()
        let last = gallery.lastSyncedAt.values.max() ?? caps.chains.flatMap { $0.sections.compactMap(\.syncedAt) }.max()
        return (sources.isEmpty ? "aucune source n’a encore répondu" : sources.joined(separator: ", ")) + (last.map { " · dernière synchronisation \(Fmt.relative($0))" } ?? "")
    }

    private func row(_ chain: NFTChainCapability) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                NFTPlain(chain.name).fontWeight(.medium)
                NFTFlag(text: NFTText.inventory(chain.inventory), color: chain.inventory == "supported" ? Theme.positive : chain.inventory == "partial" ? Theme.warning : .secondary)
                NFTPlain(NFTText.inventoryReason(chain.reason) + (chain.unlockedBy.map { " — variable serveur \($0)" } ?? "")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let d = gallery.lastSyncedAt[chain.network] { NFTPlain("synchronisé \(Fmt.relative(d))").font(.caption).foregroundStyle(.secondary) }
                if gallery.syncRunning.contains(chain.network) { ProgressView().controlSize(.mini) }
                else if chain.inventory == "supported" || chain.inventory == "partial" {
                    Button("Synchroniser") { Task { await gallery.startSync(chain: chain.network) } }.controlSize(.small).disabled(!model.canOperate || gallery.syncStarting)
                }
            }
            ForEach(chain.sections, id: \.section) { s in
                HStack(spacing: 6) {
                    Image(systemName: s.status == "ok" ? "checkmark" : "exclamationmark.triangle").foregroundStyle(s.status == "ok" ? Theme.positive : Theme.warning).font(.caption)
                    NFTPlain("\(s.section) — \(s.source.map(NFTText.sourceName) ?? "aucune source") : \(NFTText.sectionStatus(s.status))\(s.code.map { " (\($0))" } ?? "")\(s.unlockedBy.map { ", variable serveur \($0)" } ?? ""), \(s.count) élément(s)\(s.truncated ? ", liste TRONQUÉE par le serveur" : "")\(s.syncedAt.map { ", le \(Fmt.date($0))" } ?? "")")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.leading, 12)
            }
            HStack(spacing: 10) {
                NFTPlain("Transfert : \(chain.canPrepareTransfers ? "préparable pour \((chain.transferStandards ?? []).map(NFTText.standardShort).joined(separator: ", "))" : "non construit\(chain.transferReason.map { " — \(NFTText.blockReason($0))" } ?? "")")")
                NFTPlain("Lecture de marché : \(chain.marketRead ? "oui" : "non")")
            }.font(.caption).foregroundStyle(.secondary).padding(.leading, 12)
        }
    }
}

// MARK: - Explicit lookup and manual tracking

/// The owner types a chain identifier: the server reads that asset on-chain (lookup, never part of the inventory) or tracks it (verified on-chain first). This is how an EVM NFT enters the inventory when no discovery provider is configured.
private struct NFTLookupSheet: View {
    let model: AppModel
    let gallery: NFTGallery
    let open: (NFTRoute) -> Void
    let close: () -> Void
    @State private var chain = ""
    @State private var address = ""
    @State private var tokenId = ""
    @State private var busy = false
    @State private var error: String?

    private var chains: [NFTChainCapability] { (gallery.capabilities?.chains ?? []).filter { $0.lookup || $0.manualAdd } }
    private var selected: NFTChainCapability? { chains.first { $0.network == chain } }
    private var isEVM: Bool { selected?.family == "evm" }
    private var trimmed: String { address.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var problem: String? {
        guard selected != nil else { return "Choisissez un réseau." }
        if trimmed.count < 26 || trimmed.count > 64 { return isEVM ? "Entrez l’adresse du contrat." : "Entrez l’adresse du mint ou de l’actif." }
        if isEVM, tokenId.trimmingCharacters(in: .whitespaces).isEmpty { return "Entrez l’identifiant du jeton (décimal ou 0x…)." }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rechercher ou suivre un NFT").font(.title2.weight(.semibold))
            Text("Le serveur lit cet actif sur la chaîne à partir de l’identifiant saisi. « Ouvrir » l’affiche sans l’ajouter à l’inventaire ; « Suivre » l’ajoute après vérification sur la chaîne (c’est ainsi qu’un NFT EVM entre dans l’inventaire sans fournisseur de découverte).")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if chains.isEmpty { Banner(.warning, "Aucun réseau ne permet la recherche explicite sur ce serveur (ou la matrice de capacités n’a pas pu être lue).") }
            Form {
                Picker("Réseau", selection: $chain) {
                    Text("Choisir…").tag("")
                    ForEach(chains) { NFTPlain($0.name).tag($0.network) }
                }
                TextField(isEVM ? "Contrat" : "Mint / actif", text: $address).font(Theme.monoSmall)
                if isEVM { TextField("Identifiant du jeton", text: $tokenId).font(Theme.monoSmall) }
            }.formStyle(.grouped).scrollDisabled(true)
            if let e = error { Banner(.danger, e) }
            HStack {
                if let p = problem, !address.isEmpty { Text(p).font(.callout).foregroundStyle(.secondary) }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button("Annuler", action: close)
                Button("Suivre dans l’inventaire") { run(track: true) }.disabled(problem != nil || busy || !model.canOperate || selected?.manualAdd != true)
                Button("Ouvrir") { run(track: false) }.buttonStyle(.borderedProminent).disabled(problem != nil || busy || !model.canOperate || selected?.lookup != true)
            }
        }
        .padding(20).frame(width: 620)
    }

    private func run(track: Bool) {
        let token = tokenId.trimmingCharacters(in: .whitespaces)
        let ref = NFTReference(chain: chain, address: trimmed, tokenId: isEVM && !token.isEmpty ? token : nil)
        busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                let asset = track ? try await gallery.api.track(ref) : try await gallery.api.lookup(ref)
                if track { await gallery.load() }
                open(.item(asset.key))
            } catch { self.error = model.describe(error) }
        }
    }
}
