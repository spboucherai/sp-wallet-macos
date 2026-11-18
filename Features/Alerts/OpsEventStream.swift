// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/Alerts/OpsEventStream.swift
// Description: The streaming loader of the wallet's two Server-Sent-Events routes (alert counters, research-job log). It runs the request the Core built (session cookie, no cookie jar), refuses redirects, and feeds the Core's incremental parser. It owns no reconnection policy: callers decide when to reconnect and stop the stream by cancelling their task.
import Foundation
import SPWalletCore

/// A session cookie must never follow a redirect to another host.
private final class OpsNoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? { nil }
}

enum OpsEventStream {
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil; c.httpShouldSetCookies = false; c.urlCache = nil
        c.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        // the server ends every stream by itself after ten minutes; a silent research job sends nothing in between
        c.timeoutIntervalForRequest = 660; c.timeoutIntervalForResource = 720
        c.waitsForConnectivity = false
        return URLSession(configuration: c, delegate: OpsNoRedirect(), delegateQueue: nil)
    }()

    /// The events of one connection. Finishes when the server closes the stream; throws an `APIError` when the connection fails or is refused.
    static func events(_ request: URLRequest) -> AsyncThrowingStream<ServerSentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw APIError.offline("réponse sans en-tête HTTP") }
                    guard http.statusCode == 200 else { throw refusal(http.statusCode) }
                    var parser = ServerSentEventParser(); var chunk = Data()
                    for try await byte in bytes {
                        chunk.append(byte)
                        guard byte == 0x0a else { continue }
                        for e in parser.feed(chunk) { continuation.yield(e) }
                        chunk.removeAll(keepingCapacity: true)
                    }
                    continuation.finish()
                } catch is CancellationError { continuation.finish() }
                catch let e as URLError where e.code == .cancelled { continuation.finish() }
                catch let e as URLError { continuation.finish(throwing: APIError.offline(e.localizedDescription)) }
                catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The same events, for as long as `keep` stays true (checked every second on the main actor): used to drop a stream when the app goes to the background.
    static func events(_ request: URLRequest, while keep: @escaping @MainActor @Sendable () -> Bool) -> AsyncThrowingStream<ServerSentEvent, Error> {
        AsyncThrowingStream { continuation in
            let reader = Task {
                do { for try await e in events(request) { continuation.yield(e) }; continuation.finish() } catch { continuation.finish(throwing: error) }
            }
            let watchdog = Task { @MainActor in
                while !Task.isCancelled {
                    if !keep() { reader.cancel(); continuation.finish(); return }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            continuation.onTermination = { _ in reader.cancel(); watchdog.cancel() }
        }
    }

    private static func refusal(_ status: Int) -> APIError {
        switch status {
        case 401: APIError(status: 401, code: "unauthenticated", message: "")
        case 429: APIError(status: 429, code: "too_many_streams", message: "Trop de flux en direct ouverts à la fois sur ce portefeuille. Fermez-en un (autre appareil, autre fenêtre) ou patientez.")
        case 404: APIError(status: 404, code: "not_found", message: "Flux introuvable sur le serveur.")
        case 300..<400: APIError(status: status, code: "redirect_refused", message: "Le serveur a répondu par une redirection : refusée, la session n’est jamais envoyée ailleurs.")
        default: APIError(status: status, code: "stream_failed", message: "Le flux en direct a été refusé par le serveur (HTTP \(status)).")
        }
    }
}

/// Exponential backoff with jitter for the reconnection of a stream: 2 s, 4 s, 8 s… capped at one minute.
struct OpsBackoff {
    private(set) var attempt = 0
    mutating func reset() { attempt = 0 }
    mutating func next() -> Duration {
        attempt = min(attempt + 1, 6)
        let base = min(60.0, pow(2.0, Double(attempt)))
        return .milliseconds(Int((base + Double.random(in: 0...1)) * 1000))
    }
}
