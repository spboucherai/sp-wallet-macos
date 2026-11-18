// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/NFTs/NFTMarketView.swift
// Description: Market READ data of one NFT and of one collection, and the collection page. One block PER SOURCE with its name and the date of its answer: nothing is merged, averaged or picked, contradictions between sources are named, and every figure is labelled as an observed marketplace statement — never as a value of this wallet's NFT (a collection floor is a statistic of the collection). The market read is started by the owner, since it sends the asset's identifier to the marketplace. No market write exists in the backend, so none is offered.
import SwiftUI
import SPWalletCore

/// One source's page of a paginated market list (the Core's page types have no public initializer; pages are accumulated here).
struct NFTMarketPage<Item: Sendable>: Identifiable {
    let status: NFTMarketSourceStatus
    var items: [Item]
    var cursor: String?
    var id: String { status.provider }
}

@MainActor @Observable final class NFTMarketModel {
    let model: AppModel
    let api: NFTAPI
    let key: String

    private(set) var answer: NFTMarketAnswer?
    private(set) var listings: [NFTMarketPage<NFTMarketListing>]?
    private(set) var offers: [NFTMarketPage<NFTMarketOffer>]?
    private(set) var events: [NFTMarketPage<NFTMarketEvent>]?
    private(set) var traits: NFTTraitAnswer?
    private(set) var busy = false
    var error: String?

    init(model: AppModel, key: String) { self.model = model; self.key = key; api = NFTAPI(model.client) }

    private func run(_ work: () async throws -> Void) async {
        guard !busy, model.canOperate else { return }
        busy = true; error = nil; defer { busy = false }
        do { try await work() } catch { self.error = model.describe(error) }
    }

    func load(refresh: Bool = false) async { await run { self.answer = try await self.api.market(key: self.key, refresh: refresh) } }

    func loadListings(more provider: String? = nil) async {
        await run {
            if let provider, let i = self.listings?.firstIndex(where: { $0.id == provider }), let cursor = self.listings?[i].cursor {
                let r = try await self.api.marketListings(key: self.key, provider: provider, cursor: cursor)
                if let s = r.sources.first(where: { $0.status.provider == provider }) { self.listings?[i].items += s.items; self.listings?[i].cursor = s.cursor }
                else { self.listings?[i].cursor = nil }
            } else {
                self.listings = try await self.api.marketListings(key: self.key).sources.map { NFTMarketPage(status: $0.status, items: $0.items, cursor: $0.cursor) }
            }
        }
    }
    func loadOffers(more provider: String? = nil) async {
        await run {
            if let provider, let i = self.offers?.firstIndex(where: { $0.id == provider }), let cursor = self.offers?[i].cursor {
                let r = try await self.api.marketOffers(key: self.key, provider: provider, cursor: cursor)
                if let s = r.sources.first(where: { $0.status.provider == provider }) { self.offers?[i].items += s.items; self.offers?[i].cursor = s.cursor }
                else { self.offers?[i].cursor = nil }
            } else {
                self.offers = try await self.api.marketOffers(key: self.key).sources.map { NFTMarketPage(status: $0.status, items: $0.items, cursor: $0.cursor) }
            }
        }
    }
    func loadEvents(more provider: String? = nil) async {
        await run {
            if let provider, let i = self.events?.firstIndex(where: { $0.id == provider }), let cursor = self.events?[i].cursor {
                let r = try await self.api.marketActivity(key: self.key, NFTMarketEventQuery(provider: provider, cursor: cursor, limit: 20))
                if let s = r.sources.first(where: { $0.status.provider == provider }) { self.events?[i].items += s.events; self.events?[i].cursor = s.cursor }
                else { self.events?[i].cursor = nil }
            } else {
                self.events = try await self.api.marketActivity(key: self.key, NFTMarketEventQuery(limit: 20)).sources.map { NFTMarketPage(status: $0.status, items: $0.events, cursor: $0.cursor) }
            }
        }
    }
    func loadTraits() async { await run { self.traits = try await self.api.traitFrequency(key: self.key) } }
}

/// The line that says who answered and when — shown with every block of market figures.
struct NFTMarketSourceHeader: View {
    let status: NFTMarketSourceStatus
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                NFTPlain(status.name).font(.subheadline.weight(.semibold))
                NFTFlag(text: status.isOK ? (status.stale ? "Périmé" : "Réponse du \(Fmt.date(status.fetchedAt))") : "Sans donnée", color: status.isOK ? (status.stale ? Theme.warning : Theme.positive) : .secondary)
                NFTPlain(NFTText.marketState(status)).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            if status.stale, let c = status.code { NFTPlain("Dernier échec de la source : \(c). Les chiffres datent du \(Fmt.date(status.fetchedAt)).").font(.caption).foregroundStyle(Theme.warning) }
            if let a = status.attribution {
                HStack(spacing: 6) { NFTPlain(a.text).font(.caption2).foregroundStyle(.secondary); if let u = NFTText.httpsURL(a.url) { Link(u.host ?? "source", destination: u).font(.caption2) } }
            }
        }
    }
}

struct NFTMarketSection: View {
    let model: AppModel
    let gallery: NFTGallery
    let asset: NFTAsset
    let offline: Bool
    @State private var market: NFTMarketModel?

    var body: some View {
        Card("Données de marché observées", trailing: AnyView(NFTFlag(text: "Déclarations de places de marché — pas une évaluation", color: .secondary))) {
            Text("Ces chiffres sont ce que des places de marché déclarent, avec leur source et leur date. Ils ne sont ni vérifiés sur la chaîne ni une valeur de votre NFT, et ne sont jamais ajoutés au total du portefeuille. Un prix plancher est une statistique de la collection entière.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let s = asset.marketSources, !s.isEmpty {
                NFTPlain("Sources du serveur : " + s.map { "\($0.name) — \($0.state == "on" ? "active" : $0.state == "needs_key" ? "clé absente\($0.unlockedBy.map { " (\($0))" } ?? "")" : "désactivée")" }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }
            if let m = market {
                if let e = m.error { Banner(.danger, e) }
                if let a = m.answer { content(m, a) }
                else if offline { Text("Indisponible hors connexion : aucune donnée de marché n’est conservée sur ce Mac.").foregroundStyle(.secondary) }
                else {
                    HStack {
                        Text("La lecture transmet l’identifiant de cet NFT (contrat et jeton, ou mint) aux places de marché actives — jamais l’adresse du portefeuille.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        if m.busy { ProgressView().controlSize(.small) }
                        Button("Lire les données de marché") { Task { await m.load() } }.disabled(m.busy)
                    }
                }
                if let stored = asset.market, m.answer == nil { storedSnapshot(stored) }
            }
        }
        .task { if market == nil { market = NFTMarketModel(model: model, key: asset.key) } }
    }

    @ViewBuilder private func storedSnapshot(_ s: NFTMarketSnapshot) -> some View {
        Divider()
        Text("Instantané enregistré avec la fiche").font(.subheadline.weight(.medium))
        NFTPlain(NFTText.stamp(s.source)).font(.caption).foregroundStyle(s.source.isStale ? Theme.warning : Color.secondary)
        Field(label: "En vente (déclaré)", value: NFTText.knownBool(s.listed))
        Field(label: "Prix demandé", value: NFTText.known(s.listingPrice, NFTText.amount))
        Field(label: "Meilleure offre", value: NFTText.known(s.bestOffer, NFTText.amount))
        Field(label: "Dernière vente", value: NFTText.known(s.lastSale) { "\(NFTText.amount($0)) — \(NFTText.sourceTime($0.at))" })
        Field(label: "Plancher de la collection", value: NFTText.known(s.collectionFloor, NFTText.amount) + " — statistique de la collection, pas la valeur de cet NFT")
    }

    @ViewBuilder private func content(_ m: NFTMarketModel, _ a: NFTMarketAnswer) -> some View {
        HStack {
            NFTPlain("Réponse du serveur : \(Fmt.date(a.asOf))").font(.caption).foregroundStyle(.secondary)
            Spacer()
            if m.busy { ProgressView().controlSize(.small) }
            Button("Relire sans le cache") { Task { await m.load(refresh: true) } }.controlSize(.small).disabled(m.busy || offline)
        }
        ForEach(a.contradictions, id: \.self) { c in
            Banner(.warning, "Les sources se contredisent sur « \(c.field) » (\(c.providers.map(NFTText.sourceName).joined(separator: ", "))) : \(c.note). Aucune n’est retenue à la place de l’autre.")
        }
        ForEach(Array(a.sources.enumerated()), id: \.offset) { _, s in
            Divider()
            NFTMarketSourceHeader(status: s.status)
            if s.status.isOK { itemRow(s) }
        }
        if let v = a.value { NFTPlain("Valeur de cet NFT : indisponible (\(v.reason)). Ce portefeuille n’en établit aucune à partir d’un plancher ou d’une cotation isolée.").font(.callout).foregroundStyle(.secondary) }

        Divider()
        HStack {
            Button("Annonces de vente") { Task { await m.loadListings() } }
            Button("Offres d’achat") { Task { await m.loadOffers() } }
            Button("Activité de marché") { Task { await m.loadEvents() } }
            Button("Fréquence des traits") { Task { await m.loadTraits() } }
            Spacer()
        }.disabled(m.busy || offline)
        if let pages = m.listings { orders(title: "Annonces de vente observées", pages: pages, more: { p in Task { await m.loadListings(more: p) } }) { l in
            "\(NFTText.money(l.price)) pour \(l.quantity) unité(s)\(l.venue.map { " · \($0)" } ?? "")\(l.seller.map { " · vendeur \($0)" } ?? "") · créée \(NFTText.sourceTime(l.createdAt)) · expire \(NFTText.sourceTime(l.expiresAt))"
        } }
        if let pages = m.offers { orders(title: "Offres d’achat observées", pages: pages, more: { p in Task { await m.loadOffers(more: p) } }) { o in
            "\(NFTText.money(o.price)) pour \(o.quantity) unité(s) · portée : \(o.scope == "item" ? "cet NFT" : o.scope == "collection" ? "toute la collection" : o.scope)\(o.venue.map { " · \($0)" } ?? "")\(o.bidder.map { " · offrant \($0)" } ?? "") · expire \(NFTText.sourceTime(o.expiresAt))"
        } }
        if let pages = m.events { orders(title: "Événements de marché rapportés (distincts de l’historique de chaîne)", pages: pages, more: { p in Task { await m.loadEvents(more: p) } }) { e in
            "\(NFTText.sourceTime(e.at)) — \(NFTText.eventType(e.type)) (« \(e.providerType) »)\(e.price.map { " · \(NFTText.money($0))" } ?? "") · quantité \(e.quantity)\(e.venue.map { " · \($0)" } ?? "")\(e.flags.map { " · vente fictive selon la source : \(NFTText.knownBool($0.washTrade))" } ?? "")\(e.tx.map { " · tx \($0)" } ?? "")"
        } }
        if let t = m.traits { traits(t) }

        Divider()
        if let ext = a.external {
            Text("Pages de cet NFT sur des places de marché").font(.subheadline.weight(.medium))
            ForEach(ext.links, id: \.self) { l in NFTExternalLinkView(title: l.name, raw: l.url) }
            Text("Ces sites sont hors du portefeuille. Y agir exigerait une connexion de portefeuille que SP Wallet n’offre pas (\(ext.notice.walletConnect ? "annoncée par le serveur, non construite dans cette app" : "aucune connexion de portefeuille")) ; aucune clé n’est jamais exportée.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        NFTPlain(a.anyActionAvailable
                 ? "Le serveur annonce une action de marché que cette version de l’app ne sait pas vérifier : elle n’est pas proposée."
                 : "Aucune action de marché n’existe dans ce portefeuille (achat, vente, mise en vente, offre, acceptation) — raison donnée par le serveur : \(Set(a.actions.compactMap(\.reason)).sorted().joined(separator: ", ")).")
            .font(.caption).foregroundStyle(.secondary)
    }

    @ViewBuilder private func itemRow(_ s: NFTItemMarket) -> some View {
        if let f = s.flags {
            if case .known(true) = f.suspicious { Banner(.danger, "\(s.status.name) signale cet NFT comme SUSPECT.") }
            if case .known(true) = f.disabled { Banner(.warning, "\(s.status.name) a désactivé cet NFT sur sa place de marché.") }
            if case .known(true) = f.nsfw { Banner(.info, "\(s.status.name) classe cet NFT comme contenu sensible.") }
        }
        Field(label: "En vente", value: NFTText.knownBool(s.listed))
        Field(label: "Prix demandé", value: NFTText.known(s.ask) { "\(NFTText.money($0.price)) pour \($0.quantity) unité(s)\($0.venue.map { " · \($0)" } ?? "")" })
        Field(label: "Meilleure offre", value: NFTText.known(s.bestOffer) { "\(NFTText.money($0.price)) — portée : \($0.scope)" })
        Field(label: "Dernière vente rapportée", value: NFTText.known(s.lastSale) { "\(NFTText.money($0.price)) — \(NFTText.sourceTime($0.at))" })
        Field(label: "Plancher de la collection", value: NFTText.known(s.collectionFloor, NFTText.money) + " — statistique de la collection, pas la valeur de cet NFT")
        if let c = s.collection { Field(label: "Collection selon la source", value: "\(NFTClean.line(c.name) ?? "sans nom") (\(c.slug))") }
        if let v = s.verification {
            Field(label: "Badge de la source", value: v.state == "verified" ? "Vérifiée selon \(v.by)\(v.providerValue.map { " (« \($0) »)" } ?? "") — déclaration de cette place de marché" : v.state == "not_verified" ? "Non vérifiée selon \(v.by)" : "Inconnu")
        }
        if let r = s.rarity, case .known(let rank) = r { Field(label: "Rang de rareté (source)", value: "\(rank.rank)\(rank.outOf.map { " sur \($0)" } ?? "") — méthode : \(rank.method)") }
        NFTExternalLinkView(title: "Page sur \(s.status.name)", raw: s.url)
    }

    @ViewBuilder private func orders<Item: Sendable>(title: String, pages: [NFTMarketPage<Item>], more: @escaping (String) -> Void, line: @escaping (Item) -> String) -> some View {
        Divider()
        Text(title).font(.subheadline.weight(.medium))
        ForEach(pages) { p in
            NFTMarketSourceHeader(status: p.status)
            if p.status.isOK, p.items.isEmpty { Text("Aucun élément rapporté par cette source.").font(.callout).foregroundStyle(.secondary) }
            ForEach(Array(p.items.enumerated()), id: \.offset) { _, item in
                NFTPlain(line(item)).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            if p.cursor != nil { Button("Suite de \(p.status.name)") { more(p.id) }.controlSize(.small).disabled(offline) }
        }
    }

    @ViewBuilder private func traits(_ t: NFTTraitAnswer) -> some View {
        Divider()
        Text("Fréquence des traits").font(.subheadline.weight(.medium))
        if !t.computed { NFTPlain("Non calculée : \(t.reason ?? "aucune source ne donne de décompte par collection avec un total déclaré"). Rien n’est estimé à partir d’un échantillon partiel.").font(.callout).foregroundStyle(.secondary) }
        if t.mutableMetadata == true { Text("Les métadonnées de cet NFT sont modifiables : ses traits peuvent changer.").font(.caption).foregroundStyle(Theme.warning) }
        ForEach(Array(t.sources.enumerated()), id: \.offset) { _, s in
            NFTPlain("\(s.name) — \(s.computed ? "sur \(s.total ?? "?") éléments déclarés, réponse du \(Fmt.date(s.fetchedAt))\(s.stale == true ? " (périmée)" : "")" : "non calculée (\(s.reason ?? "—"))")").font(.caption).foregroundStyle(.secondary)
            ForEach(Array(s.rows.enumerated()), id: \.offset) { _, r in
                Field(label: NFTClean.line(r.traitType, max: 60) ?? "—", value: "\(NFTClean.line(r.value, max: 120) ?? "—") — " + (r.frequency.map { "\($0.count) sur \($0.total) (\($0.percent) %)" } ?? "valeur absente du décompte de la source"))
            }
        }
    }
}

// MARK: - Collection page

struct NFTCollectionPage: View {
    let model: AppModel
    let gallery: NFTGallery
    let key: String
    let open: (NFTRoute) -> Void
    let back: () -> Void
    @State private var detail: NFTCollectionDetail?
    @State private var market: NFTCollectionMarketAnswer?
    @State private var loading = false
    @State private var marketBusy = false
    @State private var error: String?
    @State private var marketError: String?

    private let columns = [GridItem(.adaptive(minimum: 172, maximum: 240), spacing: 14, alignment: .top)]
    private var items: [NFTSummary] { gallery.items(inCollection: key) }
    private var declaredName: String? { NFTClean.line(detail?.metadata?.name ?? items.first?.collection?.name) }

    var body: some View {
        Page(declaredName ?? "Collection", subtitle: "Nom déclaré par le créateur, non vérifié. Les NFT listés sont ceux de l’inventaire de ce portefeuille.") {
            NFTBackBar(title: "Retour", back: back)
            if !model.canOperate { Banner(.warning, "Hors connexion ou session indisponible : seuls les NFT de l’inventaire synchronisé sont affichés.") }
            if let e = error { Banner(.danger, e) }
            if loading { HStack { ProgressView().controlSize(.small); Text("Lecture de la collection sur la chaîne…").foregroundStyle(.secondary) } }
            if let d = detail { chainCard(d) }
            marketCard
            Card("NFT de cette collection dans l’inventaire (\(items.count))") {
                if items.isEmpty { Text("Aucun.").foregroundStyle(.secondary) }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    ForEach(items) { item in Button { open(.item(item.key)) } label: { NFTTile(item: item, gallery: gallery) }.buttonStyle(.plain) }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard model.phase == .signedIn, !loading else { return }
        loading = true; defer { loading = false }
        do { detail = try await gallery.api.collection(key: key); error = nil } catch { self.error = model.describe(error) }
    }

    @ViewBuilder private func chainCard(_ d: NFTCollectionDetail) -> some View {
        Card("Ce que la chaîne dit de la collection") {
            HStack(alignment: .top, spacing: 16) {
                NFTThumbView(mediaId: d.metadata?.imageId, kind: nil, pixels: NFTMediaStore.gridPixels, api: gallery.mediaAPI, maxBytes: gallery.mediaLimit).frame(width: 120, height: 120)
                VStack(alignment: .leading, spacing: 9) {
                    if let e = d.error { Banner(.warning, "La collection n’a pas pu être lue sur la chaîne (\(e)).") }
                    if let i = d.info {
                        Field(label: "Réseau", value: "\(gallery.networkName(i.chain))  (\(i.chain))")
                        Field(label: "Standard", value: NFTText.standard(i.standard))
                        Field(label: "Identifiant", value: i.id, mono: true)
                        Field(label: "Nom sur la chaîne", value: NFTClean.line(i.onchainName) ?? "—")
                        Field(label: "Taille", value: NFTText.known(i.size) { Fmt.amount($0) })
                        Field(label: "Autorité de mise à jour", value: NFTText.known(i.updateAuthority) { $0 }, mono: i.updateAuthority.isKnown)
                        if !i.features.isEmpty { Field(label: "Caractéristiques", value: i.features.joined(separator: ", ")) }
                        if let u = i.uri { Field(label: "URI (texte, non ouverte)", value: NFTClean.line(u, max: 300) ?? "—", mono: true) }
                        NFTPlain(NFTText.stamp(i.source)).font(.caption).foregroundStyle(.secondary)
                    }
                    Field(label: "Détenus par ce portefeuille", value: String(d.held))
                    if let m = d.metadata {
                        Field(label: "Nom (créateur, non vérifié)", value: NFTClean.line(m.name, max: 200) ?? "—")
                        if let t = NFTClean.text(m.description, max: 2_000) { Field(label: "Description (créateur)", value: t) }
                        Field(label: "Métadonnées", value: NFTText.metadataStatus(m.status))
                    }
                }
            }
        }
    }

    private var marketCard: some View {
        Card("Données de marché observées de la collection", trailing: AnyView(NFTFlag(text: "Déclarations de places de marché — pas une évaluation", color: .secondary))) {
            if let e = marketError { Banner(.danger, e) }
            if let m = market {
                NFTPlain("Réponse du serveur : \(Fmt.date(m.asOf))").font(.caption).foregroundStyle(.secondary)
                if m.sources.isEmpty { Text("Aucune source de marché ne couvre cette collection.").foregroundStyle(.secondary) }
                ForEach(Array(m.sources.enumerated()), id: \.offset) { _, s in
                    Divider()
                    NFTMarketSourceHeader(status: s.status)
                    if s.status.isOK { collectionRow(s) }
                }
            } else {
                HStack {
                    Text("Plancher, volumes et nombre de détenteurs tels que rapportés par chaque place de marché, avec leur date. Statistiques de la collection entière — jamais la valeur des NFT détenus.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if marketBusy { ProgressView().controlSize(.small) }
                    Button("Lire les données de marché") {
                        marketBusy = true; marketError = nil
                        Task { defer { marketBusy = false }; do { market = try await gallery.api.marketCollection(key: key) } catch { marketError = model.describe(error) } }
                    }.disabled(marketBusy || !model.canOperate)
                }
            }
        }
    }

    @ViewBuilder private func collectionRow(_ s: NFTCollectionMarket) -> some View {
        Field(label: "Nom selon la source", value: "\(NFTClean.line(s.name) ?? "—")\(s.slug.map { " (\($0))" } ?? "")")
        if let v = s.verification { Field(label: "Badge de la source", value: v.state == "verified" ? "Vérifiée selon \(v.by) — déclaration de cette place de marché" : v.state == "not_verified" ? "Non vérifiée selon \(v.by)" : "Inconnu") }
        Field(label: "Prix plancher", value: NFTText.known(s.floor, NFTText.money) + " — annonce la moins chère de la collection")
        Field(label: "NFT en vente", value: NFTText.known(s.listedCount) { Fmt.amount($0) })
        Field(label: "Détenteurs", value: NFTText.known(s.owners) { Fmt.amount($0) })
        Field(label: "Offre totale", value: NFTText.known(s.totalSupply) { Fmt.amount($0) })
        ForEach(s.volumes, id: \.self) { v in
            Field(label: "Volume \(v.interval)", value: (v.volume.map(NFTText.money) ?? v.reported.map { "\($0.value) \($0.symbol) (tel que rapporté)" } ?? "—") + (v.sales.map { " · \($0) vente(s)" } ?? ""))
        }
        if let fees = s.fees, !fees.isEmpty {
            Field(label: "Frais rapportés", value: fees.map { "\($0.kind)\($0.bps.map { " \($0) pb" } ?? "")\($0.required == true ? " (obligatoire)" : "")" }.joined(separator: " · "))
        }
        if let d = s.definitions, !d.isEmpty { NFTPlain("Définitions de la source : " + d.keys.sorted().map { "\($0) = \(d[$0] ?? "")" }.joined(separator: " ; ")).font(.caption).foregroundStyle(.secondary) }
        NFTExternalLinkView(title: "Page sur \(s.status.name)", raw: s.url)
    }
}
