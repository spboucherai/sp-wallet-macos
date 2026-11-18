// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/NFTs/NFTMedia.swift
// Description: The only door through which NFT media enters the app. Bytes come exclusively from the backend's media proxy (an opaque id, never a URL); images are decoded with ImageIO into downsampled bitmaps under strict type, dimension and pixel limits (decompression bombs are refused before any pixel is decoded); HTML, SVG and 3D models are never rendered. Thumbnails live in a memory cache bounded by cost, and the small grid thumbnails are re-encoded by this app and kept beside the offline snapshots so the last inventory stays viewable without a connection.
import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
import SPWalletCore

/// What a media tile can show. Never the raw bytes: either a bitmap this app decoded, or the reason there is none.
enum NFTThumbnail: Sendable {
    case image(CGImage)
    /// The file exists but this app will not render it (active content, unsupported type, refused by the decoder).
    case notDisplayable(String)
    /// The file could not be obtained (proxy refusal, host unreachable, offline).
    case unavailable(String)
}

enum NFTImageDecoder {
    /// Hard limits on what is handed to the decoder. A 36-megapixel image is at most ~144 MB transiently while it is downsampled.
    static let maxPixels = 36_000_000
    static let maxDimension = 16_384
    /// Container types ImageIO may open for NFT media: exactly the raster types the proxy serves. SVG is not among them.
    static let allowedTypes: Set<String> = ["public.png", "public.jpeg", "com.compuserve.gif", "org.webmproject.webp", "public.avif"]

    enum Failure: Error { case notAnImage, typeNotAllowed(String), tooLarge(width: Int, height: Int), undecodable }

    /// Reads the header first (type, pixel size), refuses anything outside the limits, then asks ImageIO for a thumbnail of at most `maxPixelSize` on its long side. The full-size bitmap is never kept.
    static func downsample(_ data: Data, maxPixelSize: Int) -> Result<CGImage, Failure> {
        let lazy = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, lazy), CGImageSourceGetCount(source) > 0 else { return .failure(.notAnImage) }
        guard let type = CGImageSourceGetType(source) as String? else { return .failure(.notAnImage) }
        guard allowedTypes.contains(type) else { return .failure(.typeNotAllowed(type)) }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, lazy) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, width > 0, height > 0 else { return .failure(.undecodable) }
        guard width <= maxDimension, height <= maxDimension, width.multipliedReportingOverflow(by: height).overflow == false, width * height <= maxPixels
        else { return .failure(.tooLarge(width: width, height: height)) }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(16, maxPixelSize), kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return .failure(.undecodable) }
        return .success(image)
    }

    /// PNG bytes of a bitmap this app produced (what is written to the offline thumbnail cache — never the creator's file).
    static func png(_ image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? out as Data : nil
    }

    static func text(_ f: Failure) -> String {
        switch f {
        case .notAnImage: "Média non affichable : ces octets ne sont pas une image reconnue."
        case .typeNotAllowed(let t): "Média non affichable : type d’image non accepté (\(t))."
        case .tooLarge(let w, let h): "Média non affichable : image de \(w) × \(h) pixels, au-delà de la limite de sécurité de cette app."
        case .undecodable: "Média non affichable : l’image n’a pas pu être décodée."
        }
    }
}

/// One decode at a time: a downsample can transiently need over a hundred megabytes, so decodes are never run in parallel.
private actor NFTDecodeQueue {
    func downsample(_ data: Data, maxPixelSize: Int) -> Result<CGImage, NFTImageDecoder.Failure> { NFTImageDecoder.downsample(data, maxPixelSize: maxPixelSize) }
}

/// A media file this app can hand to AVFoundation, written to a private temporary file.
struct NFTPlayableFile: Sendable, Equatable {
    let url: URL
    let mime: String
    var isAudio: Bool { mime.hasPrefix("audio/") }
}

actor NFTMediaStore {
    static let shared = NFTMediaStore()

    /// Long side, in pixels, of a grid thumbnail (kept on disk for offline reading) and of the item page's image (memory only).
    static let gridPixels = 360
    static let detailPixels = 1800
    /// Types AVFoundation plays natively among those the proxy serves. WebM and Ogg are not, and are said so.
    static let playableTypes: [String: String] = ["video/mp4": "mp4", "audio/mp4": "m4a", "audio/mpeg": "mp3", "audio/wav": "wav"]
    /// Local ceiling on one media download, whatever the server's own limit is.
    static let maxDownloadBytes = 64 * 1024 * 1024

    private final class Box { let image: CGImage; init(_ image: CGImage) { self.image = image } }
    private let memory: NSCache<NSString, Box> = {
        let c = NSCache<NSString, Box>(); c.totalCostLimit = 160 * 1024 * 1024; c.countLimit = 600
        return c
    }()
    private var failures: [String: NFTThumbnail] = [:]
    private var inflight: [String: Task<NFTThumbnail, Never>] = [:]
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let decoder = NFTDecodeQueue()
    private let thumbDirectory = AppEnvironment.supportDirectory.appendingPathComponent("snapshots", isDirectory: true).appendingPathComponent("nft-thumbs", isDirectory: true)
    private let playDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("spw-nft-media", isDirectory: true)
    private var pruned = false

    private init() { try? FileManager.default.removeItem(at: playDirectory) }

    static func limit(_ serverMax: Int?) -> Int { min(serverMax ?? 25 * 1024 * 1024, maxDownloadBytes) }

    /// The thumbnail of one proxy media id. `api == nil` means offline: only what is already in memory or on disk is answered.
    func thumbnail(id: String, pixels: Int, api: NFTAPI?, maxBytes: Int) async -> NFTThumbnail {
        guard id.range(of: "^m[0-9a-f]{40}$", options: .regularExpression) != nil else { return .unavailable("Identifiant de média invalide.") }
        let key = "\(id)-\(pixels)"
        if let box = memory.object(forKey: key as NSString) { return .image(box.image) }
        if let failed = failures[key] { return failed }
        if let task = inflight[key] { return await task.value }
        let persist = pixels == Self.gridPixels
        let file = thumbDirectory.appendingPathComponent("\(key).png")
        let directory = thumbDirectory, decoder = decoder
        let task = Task<NFTThumbnail, Never> {
            if persist, let cached = try? Data(contentsOf: file), case .success(let image) = await decoder.downsample(cached, maxPixelSize: pixels) { return .image(image) }
            guard let api else { return .unavailable("Hors connexion : cette miniature n’avait pas été téléchargée.") }
            await self.acquire()
            let content: NFTMediaContent
            do { content = try await api.media(id: id, maxBytes: maxBytes) } catch { self.release(); return .unavailable(Self.text(error)) }
            self.release()
            guard content.kind == "image" else { return .notDisplayable("Média non affichable ici : type \(content.mime).") }
            guard !content.isActiveContent else { return .notDisplayable("Média non affichable : document SVG (peut contenir du script ; le serveur ne le convertit pas en image).") }
            switch await decoder.downsample(content.data, maxPixelSize: pixels) {
            case .failure(let f): return .notDisplayable(NFTImageDecoder.text(f))
            case .success(let image):
                if persist, let png = NFTImageDecoder.png(image) {
                    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try? png.write(to: file, options: [.atomic, .completeFileProtection])
                }
                return .image(image)
            }
        }
        inflight[key] = task
        let result = await task.value
        inflight[key] = nil
        switch result {
        case .image(let image): memory.setObject(Box(image), forKey: key as NSString, cost: image.bytesPerRow * image.height)
        case .notDisplayable: remember(result, for: key)
        case .unavailable: if api != nil { remember(result, for: key) }
        }
        if persist, !pruned { pruned = true; prune() }
        return result
    }

    /// Download a playable file (types of `playableTypes` only) to a private temporary file for AVFoundation.
    func playable(id: String, api: NFTAPI, maxBytes: Int) async throws -> NFTPlayableFile {
        let content = try await api.media(id: id, maxBytes: maxBytes)
        guard let ext = Self.playableTypes[content.mime] else { throw APIError(status: 0, code: "media_not_playable", message: content.mime) }
        try FileManager.default.createDirectory(at: playDirectory, withIntermediateDirectories: true)
        let url = playDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
        try content.data.write(to: url, options: [.atomic])
        return NFTPlayableFile(url: url, mime: content.mime)
    }

    func discard(_ file: NFTPlayableFile) { try? FileManager.default.removeItem(at: file.url) }

    /// A manual refresh gives every refused or failed media another chance.
    func forgetFailures() { failures.removeAll() }

    private func remember(_ t: NFTThumbnail, for key: String) {
        if failures.count >= 2_000 { failures.removeAll() }
        failures[key] = t
    }

    // at most four proxy downloads at once (the route allows 240 a minute)
    private func acquire() async {
        if running < 4 { running += 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    private func release() {
        if waiters.isEmpty { running -= 1 } else { waiters.removeFirst().resume() }
    }

    /// Keeps the offline thumbnail folder bounded: beyond 3 000 files the oldest are removed.
    private func prune() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: thumbDirectory, includingPropertiesForKeys: [.contentModificationDateKey]), files.count > 3_000 else { return }
        let dated = files.map { ($0, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }.sorted { $0.1 < $1.1 }
        for (url, _) in dated.prefix(files.count - 3_000) { try? fm.removeItem(at: url) }
    }

    /// French reason of a proxy refusal. The server's codes are kept: a refusal is information, not noise.
    static func text(_ error: Error) -> String {
        guard let e = error as? APIError else { return "Média indisponible : \(error.localizedDescription)" }
        let detail = e.data?["code"]?.stringValue.map { " (\($0))" } ?? ""
        switch e.code {
        case "offline": return "Média indisponible : portefeuille injoignable."
        case "media_blocked": return e.status == 413 ? "Média refusé par le serveur : fichier trop volumineux\(detail)." : "Média bloqué par le serveur\(detail)."
        case "media_unreachable": return "Média indisponible : l’hôte du créateur ne répond pas\(detail)."
        case "not_found": return "Média introuvable sur le serveur."
        case "media_too_large": return "Média refusé par cette app : fichier au-delà de la limite locale."
        case "media_unexpected_type": return "Média refusé : le serveur a répondu un type hors de sa liste autorisée."
        case "media_not_playable": return "Média non lisible nativement (type \(e.message))."
        case "rate_limited": return "Trop de requêtes de médias ; réessayez dans un instant."
        default: return "Média indisponible : \(e.message.isEmpty ? e.code : e.message) [\(e.code)]"
        }
    }
}
