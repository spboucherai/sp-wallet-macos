// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/NFTs/NFTItemView.swift
// Description: The page of one NFT: its media (through the server's proxy only; images downsampled by ImageIO, MP4 / audio played by AVKit, everything else shown as a neutral "not displayable" tile), its identity as the chain gives it (network, standard, token id, full contract / mint, quantity), ownership, the creator's metadata as plain untrusted text, provenance stamps, on-chain history, this wallet's own transfers, the transfer verdict and the entry to the transfer flow, and the market READ section. Flags (indexer spam signal, unverified collection, stale ownership) are shown at the top, never hidden.
import SwiftUI
import AVKit
import CryptoKit
import SPWalletCore

@MainActor @Observable final class NFTItemModel {
    let model: AppModel
    let api: NFTAPI
    let key: String

    private(set) var asset: NFTAsset?
    private(set) var assetAt: Date?
    private(set) var fromCache = false
    private(set) var loading = false
    private(set) var missing = false
    var error: String?

    private(set) var verdict: NFTTransferVerdictAnswer?
    private(set) var verdictError: String?
    private(set) var events: [NFTEvent] = []
    private(set) var activity: NFTActivity?
    private(set) var activityLoading = false
    private(set) var activityError: String?
    private(set) var transfers: [NFTTransfer] = []
    private(set) var working = false
    var actionError: String?
    var actionNote: String?

    init(model: AppModel, key: String) { self.model = model; self.key = key; api = NFTAPI(model.client) }

    private var snapshotKey: String { "nft-item-" + SHA256.hash(data: Data(key.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined() }

    func load() async {
        if asset == nil, let s: Snapshot<NFTAsset> = await SnapshotStore.shared.load(snapshotKey), s.value.key == key {
            asset = s.value; assetAt = s.savedAt; fromCache = true
        }
        guard model.phase == .signedIn, !loading else { return }
        loading = true; defer { loading = false }
        do {
            let a = try await api.item(key: key)
            guard a.key == key else { throw APIError(status: 0, code: "nft_key_mismatch", message: "le serveur a répondu un autre actif que celui demandé") }
            asset = a; assetAt = Date(); fromCache = false; error = nil; missing = false
            await SnapshotStore.shared.save(a, as: snapshotKey)
        } catch let e as APIError where e.code == "nft_not_found" {
            missing = true; error = "Cet NFT n’est pas (ou plus) dans l’inventaire du serveur. Utilisez « Rechercher ou suivre » pour l’ouvrir par son identifiant."
        } catch {
            self.error = model.describe(error)
            if asset != nil { fromCache = true }
            return
        }
        guard !missing else { return }
        async let v: Void = loadVerdict()
        async let a: Void = loadActivity(reset: true)
        async let t: Void = loadTransfers()
        _ = await (v, a, t)
    }

    func loadVerdict() async {
        do { verdict = try await api.transferVerdict(key: key); verdictError = nil } catch { verdictError = model.describe(error) }
    }
    func loadTransfers() async { if let t = try? await api.transfers(key: key, limit: 20) { transfers = t } }

    /// `reset`: the first page of the stored events. `older`: ask the server to continue its chain scan. Otherwise: the next stored page.
    func loadActivity(reset: Bool = false, older: Bool = false) async {
        guard !activityLoading else { return }
        activityLoading = true; defer { activityLoading = false }
        do {
            let page = try await api.activity(key: key, cursor: reset || older ? nil : activity?.cursor, limit: 20, loadOlder: older)
            if reset || older { events = page.events } else { let known = Set(events.map(\.id)); events += page.events.filter { !known.contains($0.id) } }
            activity = page; activityError = nil
        } catch { activityError = model.describe(error) }
    }

    func refreshMetadata() async {
        guard model.canOperate, !working else { return }
        working = true; actionError = nil; actionNote = nil; defer { working = false }
        do {
            let a = try await api.refreshMetadata(key: key)
            guard a.key == key else { return }
            // the refresh answer carries no transfer verdict: read the item again so the page stays whole
            await NFTMediaStore.shared.forgetFailures()
            actionNote = "Métadonnées relues auprès de la source du créateur le \(Fmt.date(Date())). La propriété et l’identité restent celles de la chaîne."
            await load()
        } catch { actionError = model.describe(error) }
    }

    /// Stops tracking a hand-tracked asset. Returns true when the server removed it.
    func untrack() async -> Bool {
        guard model.canOperate, !working else { return false }
        working = true; actionError = nil; defer { working = false }
        do { return try await api.untrack(key: key).removed } catch { actionError = model.describe(error); return false }
    }
}

struct NFTItemPage: View {
    let model: AppModel
    let gallery: NFTGallery
    let key: String
    let open: (NFTRoute) -> Void
    let back: () -> Void
    @State private var item: NFTItemModel?
    @State private var sending = false

    var body: some View {
        Page(title, subtitle: subtitle) {
            NFTBackBar(title: "Galerie", back: back)
            if let item {
                if let e = item.error { Banner(item.asset == nil ? .danger : .warning, e) }
                if let a = item.asset {
                    if item.fromCache { Banner(.warning, "Lecture seule — fiche telle que lue le \(Fmt.date(item.assetAt)). Elle peut ne plus refléter la chaîne ; le transfert est désactivé.") }
                    NFTItemFlags(asset: a)
                    HStack(alignment: .top, spacing: 16) {
                        NFTItemMedia(model: model, gallery: gallery, asset: a).frame(width: 430)
                        NFTIdentityCard(model: model, gallery: gallery, asset: a, open: open)
                    }
                    NFTTransferCard(model: model, gallery: gallery, item: item, asset: a, send: { sending = true })
                    NFTMetadataCard(asset: a)
                    NFTOwnershipCard(asset: a)
                    NFTHistoryCard(model: model, item: item)
                    NFTMarketSection(model: model, gallery: gallery, asset: a, offline: item.fromCache || !model.canOperate)
                    NFTProvenanceCard(asset: a)
                    actions(item, a)
                } else if item.loading { HStack { ProgressView().controlSize(.small); Text("Lecture de l’actif et vérification de sa propriété sur la chaîne…").foregroundStyle(.secondary) } }
                else if let s = gallery.summary(key) {
                    Banner(.info, "La fiche complète de cet NFT n’a pas été synchronisée sur ce Mac. Voici ce que l’inventaire en dit.")
                    Card { Field(label: "Réseau", value: gallery.networkName(s.chain)); Field(label: "Standard", value: NFTText.standard(s.standard)); Field(label: "Identifiant", value: s.assetId, mono: true); Field(label: "Quantité", value: s.quantity) }
                } else if item.error == nil {
                    EmptyState(symbol: "icloud.slash", title: "Fiche indisponible hors connexion", detail: "Cet NFT n’a pas été ouvert sur ce Mac avant la perte de connexion : aucune donnée locale à afficher.")
                }
            } else { ProgressView() }
        }
        .task {
            if item == nil { item = NFTItemModel(model: model, key: key) }
            await item?.load()
        }
        .sheet(isPresented: $sending) {
            if let item, let a = item.asset {
                NFTTransferSheet(model: model, gallery: gallery, asset: a, verdict: item.verdict, close: { changed in
                    sending = false
                    if changed { Task { await item.load(); await gallery.load() } }
                })
            }
        }
    }

    private var title: String {
        if let a = item?.asset { return NFTClean.line(a.displayName, max: 100) ?? "NFT sans nom" }
        return NFTClean.line(gallery.summary(key)?.displayName, max: 100) ?? "NFT"
    }
    private var subtitle: String? {
        guard let a = item?.asset else { return nil }
        return "\(NFTClean.line(a.collection?.name) ?? "Sans collection") · \(gallery.networkName(a.chainId)) · nom et collection déclarés par le créateur, non vérifiés"
    }

    @ViewBuilder private func actions(_ item: NFTItemModel, _ a: NFTAsset) -> some View {
        Card("Actions de lecture") {
            if let e = item.actionError { Banner(.danger, e) }
            if let n = item.actionNote { Banner(.ok, n) }
            HStack {
                Button { Task { await item.load() } } label: { Label("Relire la fiche", systemImage: "arrow.clockwise") }.disabled(model.phase != .signedIn || item.loading)
                Button { Task { await item.refreshMetadata() } } label: { Label("Relire les métadonnées du créateur", systemImage: "doc.text.magnifyingglass") }
                    .disabled(!model.canOperate || item.working).help("Le serveur relit l’URI de métadonnées (une fois par minute au plus par actif).")
                if a.origin == "manual" {
                    Button("Ne plus suivre", role: .destructive) { Task { if await item.untrack() { await gallery.load(); back() } } }.disabled(!model.canOperate || item.working)
                        .help("Retire cet actif suivi à la main de l’inventaire du serveur. Rien n’est modifié sur la chaîne.")
                }
                if item.loading || item.working { ProgressView().controlSize(.small) }
                Spacer()
            }
        }
    }
}

// MARK: - Flags

private struct NFTItemFlags: View {
    let asset: NFTAsset
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let f = asset.indexerFlags, f.spam {
                Banner(.danger, "Signalé comme INDÉSIRABLE (spam) par \(NFTText.sourceName(f.by))\(f.classifications.isEmpty ? "" : " — classifications : \(f.classifications.joined(separator: ", "))"). C’est la déclaration de cet indexeur. N’ouvrez aucun lien de ses métadonnées et ne signez rien qu’il vous demanderait ailleurs.")
            } else if let f = asset.indexerFlags, !f.classifications.isEmpty {
                Banner(.warning, "Classifications rapportées par \(NFTText.sourceName(f.by)) : \(f.classifications.joined(separator: ", ")).")
            }
            if asset.ownership.state != "in_wallet" {
                Banner(asset.ownership.state == "unknown" ? .warning : .info, "\(NFTText.ownership(asset.ownership.state))\(asset.goneAt.map { " — constaté le \(Fmt.date($0))" } ?? "").")
            }
            if let c = asset.collection {
                switch c.verifiedOnChain {
                case .known(false): Banner(.warning, "Collection NON vérifiée sur la chaîne : l’appartenance à cette collection est une simple déclaration de l’actif. Une contrefaçon se présente ainsi.")
                case .unknown: Banner(.warning, "La vérification on-chain de la collection n’a pas pu être établie.")
                default: EmptyView()
                }
            }
            if asset.ownership.source.isStale { Banner(.warning, "La propriété n’a pas été relue récemment sur la chaîne (dernière lecture \(Fmt.relative(asset.ownership.source.fetchedAt))).") }
            if asset.origin == "lookup" { Banner(.info, "Actif ouvert par recherche explicite : il ne fait pas partie de l’inventaire de ce portefeuille.") }
        }
    }
}

// MARK: - Media

private struct NFTItemMedia: View {
    let model: AppModel
    let gallery: NFTGallery
    let asset: NFTAsset
    @State private var selected = ""
    @State private var state: Shown = .loading
    @State private var player: AVPlayer?
    @State private var file: NFTPlayableFile?
    @State private var info: NFTMediaInfo?

    enum Shown { case loading, image(CGImage), playable(isAudio: Bool), message(symbol: String, title: String, detail: String) }

    private var media: NFTMedia? { asset.media.first { $0.id == selected } }
    private var api: NFTAPI? { gallery.mediaAPI }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.corner).fill(Color.secondary.opacity(0.10))
                switch state {
                case .loading: ProgressView()
                case .image(let image): Image(decorative: image, scale: 1).resizable().interpolation(.high).aspectRatio(contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: Theme.corner))
                case .playable(let isAudio):
                    if let player { VideoPlayer(player: player).clipShape(RoundedRectangle(cornerRadius: Theme.corner)).padding(isAudio ? 24 : 0) }
                case .message(let symbol, let title, let detail):
                    VStack(spacing: 8) {
                        Image(systemName: symbol).font(.system(size: 34)).foregroundStyle(.tertiary)
                        Text(title).font(.headline)
                        NFTPlain(detail).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).textSelection(.enabled)
                    }.padding(20)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            if asset.media.count > 1 {
                Picker("Média", selection: $selected) {
                    ForEach(asset.media) { m in NFTPlain("\(role(m.role)) — \(m.mime ?? m.declaredMime ?? m.kind)").tag(m.id) }
                }.labelsHidden()
            }
            if let m = media {
                VStack(alignment: .leading, spacing: 2) {
                    NFTPlain("Servi par le proxy du serveur — jamais chargé depuis l’URI du créateur. État : \(NFTText.mediaStatus(info?.status ?? m.status))\((info?.code ?? m.errorCode).map { " (\($0))" } ?? "").")
                    NFTPlain("Type établi par le serveur d’après les octets : \(info?.mime ?? m.mime ?? "non établi")\(m.declaredMime.map { " · type annoncé par le créateur : \($0)" } ?? "")\((info?.bytes.map(String.init) ?? m.bytes).map { " · \($0) octets" } ?? "")")
                    if (info?.mime ?? m.mime) == "image/gif" { Text("GIF : seule la première image est affichée.") }
                    NFTPlain("URI du créateur (texte, non ouverte) : \(NFTClean.line(m.sourceUri, max: 300) ?? "—")").lineLimit(2).textSelection(.enabled)
                }.font(.caption).foregroundStyle(.secondary)
            }
        }
        .task(id: "\(selected)|\(api == nil)") { await show() }
        .onAppear { if selected.isEmpty { selected = (asset.media.first { $0.role == "image" } ?? asset.media.first)?.id ?? "" } }
        .onDisappear { release() }
    }

    private func role(_ r: String) -> String { switch r { case "image": "Image"; case "animation": "Animation"; case "file": "Fichier"; default: r } }

    private func release() {
        player?.pause(); player = nil
        if let f = file { file = nil; Task { await NFTMediaStore.shared.discard(f) } }
    }

    private func show() async {
        release(); info = nil
        guard let m = media else { state = .message(symbol: "photo", title: "Aucun média déclaré", detail: "Les métadonnées de cet NFT ne nomment aucun fichier (\(NFTText.metadataStatus(asset.metadata.status)))."); return }
        state = .loading
        let limit = gallery.mediaLimit
        guard let api else {
            // offline: only the grid thumbnail already on this Mac can be shown
            if case .image(let image) = await NFTMediaStore.shared.thumbnail(id: m.id, pixels: NFTMediaStore.gridPixels, api: nil, maxBytes: limit) { state = .image(image) }
            else { state = .message(symbol: "icloud.slash", title: "Média indisponible hors connexion", detail: "Ce fichier n’avait pas été téléchargé sur ce Mac.") }
            return
        }
        do {
            let i = try await api.mediaInfo(id: m.id)
            if Task.isCancelled { return }
            info = i
            guard i.isAvailable, let mime = i.mime else {
                state = .message(symbol: "icloud.slash", title: "Média indisponible", detail: "Le proxy du serveur ne sert pas ce fichier : \(NFTText.mediaStatus(i.status))\(i.code.map { " (\($0))" } ?? "").")
                return
            }
            if mime == "image/svg+xml" || mime == "text/html" || i.kind == "html" {
                state = .message(symbol: "eye.slash", title: "Média non affichable", detail: "Type \(mime) : un document qui peut contenir du script. Cette app n’exécute ni ne rend jamais de HTML ou de SVG provenant d’un NFT, et le serveur ne le convertit pas en image.")
            } else if i.kind == "image" {
                switch await NFTMediaStore.shared.thumbnail(id: m.id, pixels: NFTMediaStore.detailPixels, api: api, maxBytes: limit) {
                case .image(let image): if !Task.isCancelled { state = .image(image) }
                case .notDisplayable(let why): state = .message(symbol: "eye.slash", title: "Média non affichable", detail: why)
                case .unavailable(let why): state = .message(symbol: "icloud.slash", title: "Média indisponible", detail: why)
                }
            } else if NFTMediaStore.playableTypes[mime] != nil {
                if let bytes = i.bytes, bytes > limit {
                    state = .message(symbol: "eye.slash", title: "Média non chargé", detail: "Fichier de \(bytes) octets, au-delà de la limite de téléchargement de cette app (\(limit) octets).")
                    return
                }
                let f = try await NFTMediaStore.shared.playable(id: m.id, api: api, maxBytes: limit)
                if Task.isCancelled { await NFTMediaStore.shared.discard(f); return }
                file = f; player = AVPlayer(url: f.url); state = .playable(isAudio: f.isAudio)
            } else {
                state = .message(symbol: "eye.slash", title: "Média non affichable", detail: "Type \(mime) (\(i.kind ?? "inconnu")) : macOS ne le lit pas nativement, et cette app ne confie aucun contenu de NFT à un moteur web.")
            }
        } catch is CancellationError {
        } catch { if !Task.isCancelled { state = .message(symbol: "icloud.slash", title: "Média indisponible", detail: NFTMediaStore.text(error)) } }
    }
}

// MARK: - Identity

private struct NFTIdentityCard: View {
    let model: AppModel
    let gallery: NFTGallery
    let asset: NFTAsset
    let open: (NFTRoute) -> Void

    var body: some View {
        let a = asset
        Card("Identité sur la chaîne", trailing: AnyView(ProvenanceTag(p: a.ownership.source.isChainVerified ? .verified : .stale, text: a.ownership.source.isChainVerified ? "Propriété vérifiée sur la chaîne" : NFTText.confidence(a.ownership.source.confidence)))) {
            Field(label: "Réseau", value: "\(gallery.networkName(a.chainId))  (\(a.chainId))")
            Field(label: "Standard", value: NFTText.standard(a.standard), emphasis: true)
            if let t = a.tokenId { Field(label: "Identifiant du jeton", value: t, mono: true) }
            if let c = a.contractAddress { Field(label: "Contrat", value: c, mono: true) }
            if let m = a.mintAddress { Field(label: a.standard == .metaplexCore ? "Adresse de l’actif" : "Mint", value: m, mono: true) }
            if a.contractAddress == nil, a.mintAddress == nil { Field(label: "Identifiant de l’actif", value: a.assetId, mono: true) }
            Field(label: a.standard == .erc1155 ? "Quantité détenue (ERC-1155)" : "Quantité détenue", value: Fmt.amount(a.quantity), emphasis: a.standard == .erc1155 || a.quantity != "1")
            Field(label: "Offre totale", value: NFTText.known(a.supply) { Fmt.amount($0) })
            if let c = a.collection {
                Field(label: "Collection", value: "\(NFTClean.line(c.name) ?? "sans nom déclaré") — vérifiée sur la chaîne : \(NFTText.knownBool(c.verifiedOnChain))")
                Field(label: "Identifiant de collection", value: c.id, mono: true)
                HStack { Spacer().frame(width: 182); Button("Page de la collection") { open(.collection(c.key)) }.buttonStyle(.link) }
            } else { Field(label: "Collection", value: "Aucune") }
            if let p = a.tokenProgram { Field(label: "Programme de jetons", value: p, mono: true) }
            if !a.extensions.isEmpty { Field(label: "Extensions / plugins", value: a.extensions.joined(separator: ", ")) }
            Field(label: "Redevance du créateur", value: NFTText.known(a.royaltyBps) { "\($0) points de base (\(Double($0) / 100) %)" })
            Field(label: "Jeu de règles (pNFT)", value: NFTText.known(a.ruleSet) { $0 }, mono: a.ruleSet.isKnown)
            Field(label: "Autorité de mise à jour", value: NFTText.known(a.updateAuthority) { $0 }, mono: a.updateAuthority.isKnown)
            if case .known(let creators) = a.creators, !creators.isEmpty {
                Field(label: "Créateurs", value: creators.map { "\($0.address) — \($0.verified ? "vérifié" : "NON vérifié"), part \($0.share) %" }.joined(separator: "\n"), mono: true)
            }
            Field(label: "Entrée dans l’inventaire", value: NFTText.origin(a.origin))
            Field(label: "Vu pour la première fois", value: Fmt.date(a.firstSeen))
            Field(label: "Propriété relue le", value: Fmt.date(a.verifiedAt))
            HStack(spacing: 14) {
                NFTExternalLinkView(title: "Explorateur de blocs", raw: a.explorerUrl)
                Button("Copier l’adresse") { copyToPasteboard(a.assetAddress) }.buttonStyle(.link)
            }
        }
    }
}

private struct NFTOwnershipCard: View {
    let asset: NFTAsset
    var body: some View {
        let o = asset.ownership
        Card("Propriété") {
            Field(label: "État", value: NFTText.ownership(o.state), emphasis: true)
            Field(label: "Détenteur selon la chaîne", value: NFTText.known(o.owner) { $0 }, mono: o.owner.isKnown)
            if let w = asset.ownerAddress { Field(label: "Adresse de ce portefeuille", value: w, mono: true) }
            Field(label: "Compte de jetons", value: NFTText.known(o.tokenAccount) { $0 }, mono: o.tokenAccount.isKnown)
            Field(label: "Gelé", value: NFTText.knownBool(o.frozen))
            Field(label: "Délégué", value: NFTText.known(o.delegate) { $0 }, mono: o.delegate.isKnown)
            Field(label: "État du token record", value: NFTText.known(o.tokenRecordState) { $0 })
            NFTPlain(NFTText.stamp(o.source)).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Creator metadata (untrusted, plain text)

private struct NFTMetadataCard: View {
    let asset: NFTAsset
    @State private var showRaw = false

    private var onchainName: String {
        let parts = [NFTClean.line(asset.metadata.onchainName), NFTClean.line(asset.metadata.onchainSymbol).map { "(\($0))" }].compactMap { $0 }
        return parts.isEmpty ? "—" : parts.joined(separator: " ")
    }

    var body: some View {
        let m = asset.metadata
        Card("Métadonnées déclarées par le créateur", trailing: AnyView(NFTFlag(text: "Non vérifié — texte brut", color: .secondary))) {
            Text("Tout ce qui suit est du contenu distant non fiable, affiché comme simple texte : aucun lien n’y est suivi, aucun balisage n’y est interprété.").font(.caption).foregroundStyle(.secondary)
            Field(label: "État de lecture", value: NFTText.metadataStatus(m.status) + (m.errorCode.map { " (\($0))" } ?? ""))
            Field(label: "Nom (créateur)", value: NFTClean.line(m.name, max: 300) ?? "—")
            Field(label: "Nom sur la chaîne", value: onchainName)
            if let d = NFTClean.text(m.description, max: 4_000) { Field(label: "Description", value: d) }
            Field(label: "Modifiables", value: NFTText.knownBool(m.mutable))
            if let u = m.externalUrl, !u.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Lien du créateur").foregroundStyle(.secondary).frame(width: 170, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        NFTExternalLinkView(title: "Ouvrir dans le navigateur", raw: u)
                        Text("Lien choisi par le créateur de l’NFT : SP Wallet ne le cautionne pas. Ne connectez ce portefeuille à aucun site.").font(.caption).foregroundStyle(Theme.warning)
                    }
                }
            }
            if let u = m.sourceUri { Field(label: "URI des métadonnées", value: NFTClean.line(u, max: 400) ?? "—", mono: true) }
            if let h = m.contentHash { Field(label: "SHA-256 du document", value: h, mono: true) }
            if let s = m.source { NFTPlain(NFTText.stamp(s)).font(.caption).foregroundStyle(.secondary) }
            if !m.attributes.isEmpty {
                Divider()
                Text("Attributs (\(m.attributes.count))").font(.subheadline.weight(.medium))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8, alignment: .top)], alignment: .leading, spacing: 8) {
                    ForEach(Array(m.attributes.prefix(200).enumerated()), id: \.offset) { _, t in
                        VStack(alignment: .leading, spacing: 2) {
                            NFTPlain(NFTClean.line(t.traitType, max: 80) ?? "(sans type)").font(.caption).foregroundStyle(.secondary)
                            NFTPlain(NFTClean.line(t.valueText, max: 160) ?? "—").textSelection(.enabled)
                            if let d = t.displayType { NFTPlain("affichage : \(NFTClean.line(d, max: 40) ?? "")\(t.maxValue.map { " · max \($0)" } ?? "")").font(.caption2).foregroundStyle(.secondary) }
                            if t.malformed { NFTFlag(text: "Entrée malformée") }
                        }
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                if m.attributes.count > 200 { Text("\(m.attributes.count - 200) attribut(s) supplémentaire(s) non affiché(s).").font(.caption).foregroundStyle(.secondary) }
                if let s = m.traitStatistics, !s.computed { NFTPlain("Aucune rareté n’est calculée par le serveur (\(s.reason)). Voir « Fréquence des traits » dans les données de marché.").font(.caption).foregroundStyle(.secondary) }
            }
            if let raw = m.raw {
                DisclosureGroup("Document JSON tel que lu par le serveur (texte inerte)", isExpanded: $showRaw) {
                    ScrollView { NFTPlain(NFTClean.text(raw.displayText, max: 20_000) ?? "").font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 260)
                }.font(.callout)
            }
        }
    }
}

private struct NFTProvenanceCard: View {
    let asset: NFTAsset
    var body: some View {
        Card("Provenance des données") {
            Text("Chaque valeur de cette fiche vient d’une seule de ces sources ; elles ne sont jamais fusionnées.").font(.caption).foregroundStyle(.secondary)
            ForEach(Array(asset.sources.enumerated()), id: \.offset) { _, s in
                VStack(alignment: .leading, spacing: 1) {
                    NFTPlain(NFTText.stamp(s)).font(.callout)
                    if !s.covers.isEmpty { NFTPlain("couvre : \(s.covers.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary) }
                }
            }
            if let b = asset.blockRef { NFTPlain("Référence de bloc : \([b.number.map { "n° \($0)" }, b.slot.map { "slot \($0)" }, b.commitment, b.hash].compactMap { $0 }.joined(separator: " · "))").font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
        }
    }
}

// MARK: - History

private struct NFTHistoryCard: View {
    let model: AppModel
    let item: NFTItemModel

    var body: some View {
        Card("Historique sur la chaîne", trailing: item.activityLoading ? AnyView(ProgressView().controlSize(.small)) : nil) {
            if let e = item.activityError { Banner(.warning, e) }
            if let a = item.activity {
                NFTPlain("\(NFTText.completeness(a.completeness))\(a.note.map { " — \($0)" } ?? "")\(a.scannedAt.map { " · lu le \(Fmt.date($0))" } ?? "")").font(.caption).foregroundStyle(a.completeness == "full" ? Color.secondary : Theme.warning)
                if let code = a.error { Banner(.warning, "La relecture de l’historique a échoué (\(code)) : les événements ci-dessous sont ceux déjà stockés.") }
            }
            if item.events.isEmpty, item.activity != nil { Text("Aucun événement connu pour cet actif.").foregroundStyle(.secondary) }
            ForEach(item.events) { e in
                NFTEventRow(event: e)
                Divider()
            }
            HStack {
                if item.activity?.cursor != nil { Button("Événements suivants") { Task { await item.loadActivity() } }.disabled(item.activityLoading || model.phase != .signedIn) }
                if item.activity?.canLoadOlder == true { Button("Remonter plus loin dans la chaîne") { Task { await item.loadActivity(older: true) } }.disabled(item.activityLoading || !model.canOperate) }
                Spacer()
            }
            if !item.transfers.isEmpty {
                Text("Transferts préparés depuis ce portefeuille").font(.subheadline.weight(.medium)).padding(.top, 4)
                ForEach(item.transfers) { t in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            StatusPill(raw: t.state == .unknown ? "unknown" : t.state.rawValue)
                            NFTPlain("\(Fmt.date(t.proposal.createdAt)) · quantité \(t.proposal.amount)").font(.callout)
                            Spacer()
                            if let ex = NFTText.httpsURL(t.proposal.explorer) { Link("Explorateur", destination: ex).font(.callout) }
                        }
                        if let to = t.proposal.to { NFTPlain("vers \(to)").font(Theme.monoSmall).textSelection(.enabled) }
                        if let tx = t.proposal.txid { NFTPlain("transaction \(tx)").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled) }
                        if let err = t.proposal.error { NFTPlain(err).font(.caption).foregroundStyle(Theme.negative) }
                    }
                }
            }
        }
    }
}

private struct NFTEventRow: View {
    let event: NFTEvent
    var body: some View {
        let e = event
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(NFTText.eventType(e.type)).fontWeight(.medium)
                NFTFlag(text: NFTText.finality(e.finality), color: e.isFinal ? Theme.positive : Theme.warning)
                if e.quantity != "1" { NFTPlain("× \(e.quantity)").monospacedDigit() }
                Spacer()
                NFTPlain(NFTText.sourceTime(e.at)).font(.callout).foregroundStyle(.secondary)
            }
            if let f = e.from { NFTPlain("de   \(f)").font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
            if let t = e.to { NFTPlain("vers \(t)").font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
            NFTPlain("tx \(e.tx)").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
            if let p = e.price { NFTPlain("Prix lié par une source de marché (déclaration, pas une lecture de chaîne) : \(NFTText.amount(p))").font(.caption).foregroundStyle(.secondary) }
            if let m = e.market { NFTPlain("Marché : \(NFTText.sourceName(m.provider))\(m.venue.map { " · \($0)" } ?? "")\(m.washTrade.map { " · vente fictive selon la source : \(NFTText.knownBool($0))" } ?? "")").font(.caption).foregroundStyle(.secondary) }
            NFTPlain("\(NFTText.sourceName(e.source.source)) — \(NFTText.confidence(e.source.confidence))\(e.interpretation.map { " · interprété par \($0.by)" } ?? "")\(e.marketProgram.map { " · programme \($0.name)" } ?? "")").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Transfer verdict

private struct NFTTransferCard: View {
    let model: AppModel
    let gallery: NFTGallery
    let item: NFTItemModel
    let asset: NFTAsset
    let send: () -> Void

    private var chainCap: NFTChainCapability? { gallery.capabilities?.chain(asset.chainId) }
    private var blockedBy: [String] { item.verdict?.blockedBy ?? asset.transfer?.blockedBy ?? asset.capabilities.transferBlockedBy }
    private var warnings: [String] { item.verdict?.warnings ?? asset.transfer?.warnings ?? asset.capabilities.transferWarnings ?? [] }
    private var transferable: Bool { item.verdict?.transferable ?? asset.transfer?.transferable ?? false }

    /// Why the button is disabled, in order. Empty = the transfer can be prepared (the server and the signer still decide).
    private var obstacles: [String] {
        var out: [String] = []
        if item.fromCache || !model.canOperate { out.append("Hors connexion ou session indisponible : aucun transfert ne peut être préparé.") }
        if asset.standard.transferStandard == nil { out.append("Aucun transfert n’est construit pour le standard \(NFTText.standard(asset.standard)).") }
        if let c = chainCap, !c.canPrepareTransfer(of: asset.standard) { out.append("Le serveur ne prépare pas de transfert de ce standard sur \(c.name)\(c.transferReason.map { " (\(NFTText.blockReason($0)))" } ?? "").") }
        out += blockedBy.map(NFTText.blockReason)
        if let s = item.verdict?.signer {
            if !s.reachable { out.append("Le signataire isolé est injoignable.") }
            if s.halted == true { out.append("L’arrêt d’urgence du signataire est actif.") }
            if s.supportsNft == false { out.append("La version du signataire ne prend pas en charge les transferts de NFT.") }
            if let n = s.signedToday, let m = s.maxPerDay, n >= m { out.append("Plafond quotidien du signataire atteint : \(n) transfert(s) de NFT signé(s) aujourd’hui sur \(m).") }
        } else if item.verdict == nil, !item.fromCache { out.append(item.verdictError ?? "Le verdict de transfert du serveur n’a pas encore été lu.") }
        return out
    }

    private func policy(_ s: NFTTransferVerdictAnswer.Signer) -> String {
        let parts: [String?] = [
            s.signedToday.flatMap { n in s.maxPerDay.map { "\(n) / \($0) transfert(s) signé(s) aujourd’hui" } },
            s.allowlistOnly.map { $0 ? "destinations limitées à la liste autorisée" : "toute destination valide (liste non imposée)" },
            asset.standard == .erc1155 ? s.maxErc1155Quantity.map { "au plus \($0) unité(s) ERC-1155 par transfert" } : nil,
        ]
        let known = parts.compactMap { $0 }
        return known.isEmpty ? "non lue" : known.joined(separator: " · ")
    }

    var body: some View {
        Card("Transfert", trailing: AnyView(NFTFlag(text: transferable && obstacles.isEmpty ? "Préparable" : "Non disponible", color: transferable && obstacles.isEmpty ? Theme.positive : .secondary))) {
            if let v = item.verdict {
                if let r = v.route { Field(label: "Appel utilisé", value: r, mono: true) }
                Field(label: "Politique NFT du signataire", value: policy(v.signer))
                if v.broadcast == false { Banner(.warning, "SERVEUR DE TEST — il signe mais ne diffuse pas : un transfert approuvé se terminera « signé, NON diffusé ». Rien ne quittera le portefeuille.") }
            }
            ForEach(warnings, id: \.self) { w in Banner(.warning, NFTText.warning(w)) }
            ForEach(obstacles, id: \.self) { o in
                HStack(alignment: .firstTextBaseline, spacing: 6) { Image(systemName: "nosign").foregroundStyle(.secondary); NFTPlain(o).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            HStack {
                Text("Ce verdict est un affichage, pas une autorisation : à la préparation, le serveur relit la chaîne sur chaque point d’accès et simule le transfert ; le signataire applique ensuite sa propre politique.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button { send() } label: { Label("Envoyer cet NFT…", systemImage: "paperplane") }.buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(!transferable || !obstacles.isEmpty)
            }
        }
    }
}
