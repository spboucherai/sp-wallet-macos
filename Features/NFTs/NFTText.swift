// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/NFTs/NFTText.swift
// Description: French wording of the NFT domain's server codes (standards, ownership states, transfer block reasons, warnings, source categories) and the small pure helpers the NFT screens share. A code this version does not know is shown verbatim: nothing is paraphrased into something milder, and a value that is not `known` is shown as what it is, never as a default.
import SwiftUI
import SPWalletCore

enum NFTText {
    /// The standard in reading form, followed by the server's own name for it.
    static func standard(_ s: NFTStandard) -> String {
        let label: String? = switch s.rawValue {
        case "erc721": "ERC-721"
        case "erc1155": "ERC-1155"
        case "evm-nonstandard": "Contrat EVM non standard"
        case "metaplex-token-metadata": "Metaplex Token Metadata"
        case "metaplex-pnft": "Metaplex pNFT (programmable)"
        case "metaplex-core": "Metaplex Core"
        case "metaplex-bubblegum": "Metaplex Bubblegum (NFT compressé)"
        case "spl-token-2022": "SPL Token-2022"
        case "spl-token": "SPL Token sans métadonnées Metaplex"
        case "ordinals-inscription": "Inscription Ordinals"
        case "unknown": "Standard non établi"
        default: nil
        }
        return label.map { "\($0)  (\(s.rawValue))" } ?? s.rawValue
    }
    static func standardShort(_ s: NFTStandard) -> String {
        switch s.rawValue {
        case "erc721": "ERC-721"
        case "erc1155": "ERC-1155"
        case "metaplex-token-metadata": "Token Metadata"
        case "metaplex-pnft": "pNFT"
        case "metaplex-core": "Core"
        case "metaplex-bubblegum": "Compressé"
        case "spl-token-2022": "Token-2022"
        case "spl-token": "SPL"
        default: s.rawValue
        }
    }

    static func ownership(_ state: String) -> String {
        switch state {
        case "in_wallet": "Détenu par ce portefeuille"
        case "not_in_wallet": "N’est plus détenu par ce portefeuille"
        case "escrow_or_delegated": "En séquestre ou délégué"
        case "burned": "Détruit (burn)"
        case "unknown": "Propriété non établie"
        default: state
        }
    }

    static func origin(_ o: String) -> String {
        switch o {
        case "discovered": "Découvert par un fournisseur d’inventaire"
        case "manual": "Suivi à la main (vérifié sur la chaîne à l’ajout)"
        case "lookup": "Ouvert par recherche explicite (hors inventaire)"
        default: o
        }
    }

    static func blockReason(_ code: String) -> String {
        switch code {
        case "not_in_wallet": "Cet NFT n’est pas détenu par ce portefeuille."
        case "burned": "Cet NFT a été détruit."
        case "frozen": "Le compte de cet NFT est gelé."
        case "pnft_locked": "NFT programmable verrouillé (staké ou verrouillé par un délégué)."
        case "pnft_listed": "NFT programmable mis en vente : un délégué de place de marché le détient."
        case "delegated": "Un délégué est approuvé sur cet NFT (possiblement mis en vente) : il faut le révoquer avant l’envoi."
        case "soulbound": "NFT non transférable par construction (soulbound)."
        case "escrow": "NFT en séquestre."
        case "unsupported_standard": "Aucun transfert n’est construit pour ce standard."
        case "ownership_unknown": "La propriété n’a pas pu être établie sur la chaîne."
        case "token2022_extension_unsupported": "Extension Token-2022 que ce portefeuille ne prend pas en compte (transfer hook, délégué permanent, frais de transfert…)."
        case "compressed_transfer_not_supported": "NFT compressé : ce portefeuille ne vérifie pas la preuve de Merkle, donc ne le transfère pas."
        case "ordinals_transfer_not_supported": "Inscription Bitcoin : ce portefeuille ne construit aucun transfert d’inscription."
        case "source_not_associated_account": "L’unité se trouve dans un compte de jetons qui n’est pas le compte associé du portefeuille."
        case "ownership_single_source": "Les points d’accès RPC ne concordent pas (ou un seul a répondu) sur la propriété : rien n’est préparé."
        case "network_disabled_by_policy": "La politique du signataire n’autorise pas les transferts de ce standard sur ce réseau."
        case "non_standard_contract": "Contrat qui ne déclare ni ERC-721 ni ERC-1155 : aucun transfert n’est construit."
        case "no_adapter": "Aucun adaptateur NFT n’existe pour ce réseau sur ce serveur."
        default: code
        }
    }

    static func warning(_ code: String) -> String {
        switch code {
        case "pnft_rule_set": "NFT programmable : un jeu de règles du créateur s’applique au transfert et peut le refuser."
        case "core_collection_permanent_delegate": "La collection Core porte un délégué permanent : son détenteur peut déplacer cet actif à tout moment."
        case "core_permanent_delegate": "Cet actif Core porte un délégué permanent : son détenteur peut le déplacer à tout moment."
        case "mutable_metadata": "Métadonnées modifiables : le créateur peut changer le nom, l’image et les attributs après l’envoi."
        case "contract_recipient": "La destination est un contrat, pas un portefeuille."
        case "creates_token_account": "La transaction crée le compte de jetons du destinataire : un loyer (rent) y est immobilisé, à vos frais."
        case "semi_fungible": "Jeton semi-fongible : plusieurs unités identiques existent."
        default: ErrorText.warning(code)
        }
    }

    static func metadataStatus(_ s: String) -> String {
        switch s {
        case "ok": "Lues"
        case "missing": "Absentes"
        case "no_uri": "Aucune URI de métadonnées sur la chaîne"
        case "blocked": "Bloquées par le serveur (adresse ou schéma refusé)"
        case "unreachable": "Hôte du créateur injoignable"
        case "malformed": "Document malformé"
        case "too_large": "Document trop volumineux"
        case "not_loaded": "Pas encore chargées"
        default: s
        }
    }

    static func mediaStatus(_ s: String) -> String {
        switch s {
        case "available": "disponible"
        case "not_fetched": "pas encore récupéré par le serveur"
        case "blocked", "media_blocked": "bloqué par le serveur"
        case "unreachable", "media_unreachable": "hôte injoignable"
        case "unsupported_type": "type non servi par le serveur"
        case "too_large": "fichier trop volumineux"
        case "not_found": "introuvable"
        default: s
        }
    }

    static func sourceName(_ id: String) -> String {
        switch id {
        case "solana-rpc": "RPC Solana"
        case "solana-das": "Indexeur Solana DAS"
        case "evm-rpc": "RPC EVM"
        case "evm-indexer": "Indexeur EVM"
        case "metadata-uri": "URI de métadonnées du créateur"
        case "magiceden": "Magic Eden"
        case "opensea": "OpenSea"
        case "alchemy": "Alchemy"
        case "spw": "SP Wallet (calcul)"
        case "spw-transfer": "Transaction de ce portefeuille"
        default: id
        }
    }

    static func category(_ c: String) -> String {
        switch c {
        case "onchain": "Lu sur la chaîne"
        case "creator_metadata": "Déclaré par le créateur (non vérifié)"
        case "indexed": "Rapporté par un indexeur"
        case "market": "Rapporté par une place de marché"
        case "computed": "Calculé par le serveur"
        default: c
        }
    }

    static func confidence(_ c: String) -> String {
        switch c {
        case "chain_verified": "vérifié sur tous les points d’accès"
        case "chain_single_source": "une seule source de chaîne"
        case "indexer_reported": "déclaration d’indexeur"
        case "creator_declared": "déclaration du créateur"
        case "market_reported": "déclaration de place de marché"
        case "computed": "calcul"
        default: c
        }
    }

    static func stamp(_ s: NFTSourceStamp) -> String {
        "\(category(s.category)) — \(sourceName(s.source)) (\(s.detail)), \(confidence(s.confidence)), \(Fmt.date(s.fetchedAt))\(s.isStale ? " — PÉRIMÉ" : "")"
    }

    static func inventory(_ s: String) -> String {
        switch s {
        case "supported": "Découverte complète"
        case "partial": "Découverte partielle"
        case "blocked_by_provider": "Aucune découverte : fournisseur non configuré"
        case "unsupported": "Non pris en charge"
        default: s
        }
    }

    static func inventoryReason(_ code: String) -> String {
        switch code {
        case "onchain_and_das": "lecture de chaîne + indexeur DAS"
        case "onchain_only": "lecture de chaîne seule (les NFT compressés ne sont pas listés)"
        case "no_keyless_discovery": "aucune découverte sans clé de fournisseur : seuls les NFT suivis à la main et les arrivées sur des contrats connus apparaissent"
        case "ordinals_need_ord_indexer": "les inscriptions exigent un indexeur ord"
        case "no_adapter": "aucun adaptateur pour ce réseau"
        default: code
        }
    }

    static func sectionStatus(_ s: String) -> String {
        switch s {
        case "ok": "synchronisé"
        case "blocked_by_provider": "bloqué : fournisseur absent"
        case "error": "erreur"
        case "not_configured": "non configuré"
        default: s
        }
    }

    static func eventType(_ t: String) -> String {
        switch t {
        case "mint": "Création (mint)"
        case "transfer-in": "Transfert entrant"
        case "transfer-out": "Transfert sortant"
        case "transfer": "Transfert"
        case "sale": "Vente"
        case "list": "Mise en vente"
        case "delist": "Retrait de vente"
        case "offer": "Offre"
        case "cancel-offer": "Offre annulée"
        case "accept-offer": "Offre acceptée"
        case "burn": "Destruction (burn)"
        case "escrow": "Mise en séquestre"
        case "unknown": "Événement non interprété"
        default: t
        }
    }

    static func finality(_ f: String) -> String {
        switch f {
        case "finalized": "finalisé"
        case "confirmed": "confirmé, non finalisé"
        case "pending": "en attente"
        case "reorged": "réorganisé"
        default: f
        }
    }

    static func completeness(_ c: String) -> String {
        switch c {
        case "full": "Historique complet"
        case "partial": "Historique partiel"
        case "recent_window": "Fenêtre récente seulement"
        case "unavailable": "Historique indisponible"
        default: c
        }
    }

    static func marketState(_ s: NFTMarketSourceStatus) -> String {
        switch s.state {
        case "ok": s.stale ? "réponse en cache après un échec de la source" : "réponse obtenue"
        case "needs_key": "clé d’API absente du serveur\(s.unlockedBy.map { " (variable \($0))" } ?? "")"
        case "off": "source désactivée sur le serveur\(s.unlockedBy.map { " (variable \($0))" } ?? "")"
        case "not_covered": "réseau non couvert par cette source"
        case "error": "erreur de la source\(s.code.map { " (\($0))" } ?? "")"
        default: s.state
        }
    }

    static func known<T>(_ k: NFTKnown<T>, _ render: (T) -> String) -> String {
        switch k {
        case .known(let v): render(v)
        case .none: "Aucun"
        case .unknown(let reason): reason.map { "Non établi (\($0))" } ?? "Non établi"
        case .unsupported: "Sans objet pour ce standard"
        case .unrecognized(let s): "État non reconnu (\(s))"
        }
    }
    static func knownBool(_ k: NFTKnown<Bool>) -> String { known(k) { $0 ? "Oui" : "Non" } }

    static func money(_ m: NFTMoney) -> String {
        "\(m.display.map { Fmt.amount($0) } ?? "\(m.amount) unités de base") \(m.currency.symbol)\(m.precision == "source_decimal" ? " (décimal de la source)" : "")"
    }
    static func amount(_ a: NFTAmount) -> String { "\(a.display.map { Fmt.amount($0) } ?? "\(a.amount) unités de base") \(a.currency.symbol)" }

    /// A time the SOURCE gave as text: parsed when it is ISO 8601, otherwise shown as given.
    static func sourceTime(_ s: String?) -> String {
        guard let s, !s.isEmpty else { return "—" }
        return ISO8601.parse(s).map { Fmt.date($0) } ?? s
    }

    /// Only an https link without credentials is ever offered; it opens in the browser, outside the app.
    static func httpsURL(_ raw: String?) -> URL? {
        guard let u = NFTLinks.safe(raw), u.scheme?.lowercased() == "https" else { return nil }
        return u
    }

    /// Search text of one inventory row: what the owner can see of it.
    static func haystack(_ s: NFTSummary) -> String {
        [s.name, s.onchainName, s.collection?.name, s.assetId, s.tokenId, s.key].compactMap { $0 }.joined(separator: "\n").lowercased()
    }
}

/// An https link opened outside the app, with its host spelled out. Anything that is not https is rendered as inert text.
struct NFTExternalLinkView: View {
    let title: String
    let raw: String?
    var body: some View {
        if let url = NFTText.httpsURL(raw) {
            Link(destination: url) { Label("\(title) — \(url.host ?? "")", systemImage: "arrow.up.right.square") }
                .help("S’ouvre dans le navigateur, hors de SP Wallet.")
        } else if let raw, !raw.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(title) — lien non ouvrable (seuls les liens https sont proposés)").font(.caption).foregroundStyle(.secondary)
                Text(verbatim: raw).font(Theme.monoSmall).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(2)
            }
        }
    }
}

/// A small coloured capsule for a flag (spam, stale, not verified…).
struct NFTFlag: View {
    let text: String
    var color: Color = Theme.warning
    var symbol: String?
    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.caption2.weight(.semibold)).foregroundStyle(color)
        .padding(.horizontal, 6).padding(.vertical, 2).background(color.opacity(0.14), in: Capsule())
    }
}
