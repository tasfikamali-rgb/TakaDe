import Foundation
import Observation
import TakaDeCore

/// Today's exchange rates, downloaded by this phone straight from a free public source
/// each time TakaDe opens, and kept on the phone for when there's no internet (ADR 28).
///
/// Nothing goes through TakaDe's own server. The request is a plain download of one public
/// file: it carries no names, amounts, account or device ID, and no cookies.
@MainActor
@Observable
final class ExchangeRateStore {
    private(set) var rates: ExchangeRates?
    /// When this phone last got fresh rates.
    private(set) var fetchedAt: Date?
    /// The last try to get fresh rates failed (offline, or the source was down).
    private(set) var lastRefreshFailed = false

    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private let cacheURL: URL?

    /// fawazahmed0/exchange-api: free, no key, CC0, updated daily. The project asks apps
    /// to fall back to its Cloudflare mirror when jsDelivr fails.
    nonisolated static let sources = [
        URL(string: "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/bdt.min.json")!,
        URL(string: "https://latest.currency-api.pages.dev/v1/currencies/bdt.min.json")!,
    ]

    private struct Cached: Codable {
        let rates: ExchangeRates
        let fetchedAt: Date
    }

    nonisolated private static var cacheFolder: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("ExchangeRates", isDirectory: true)
    }

    /// For "Delete all my data". The rates aren't personal, but nothing should be left behind.
    nonisolated static func removeCache() {
        if let folder = cacheFolder { try? FileManager.default.removeItem(at: folder) }
    }

    init() {
        cacheURL = Self.cacheFolder?.appendingPathComponent("bdt.json")
        if let cacheURL, let data = try? Data(contentsOf: cacheURL),
           let cached = try? JSONDecoder().decode(Cached.self, from: data) {
            rates = cached.rates
            fetchedAt = cached.fetchedAt
        }
    }

    /// Gets fresh rates. Called on every open; skipped if it ran under a minute ago, so
    /// launch and becoming active don't download twice.
    func refresh() async {
        guard !refreshing else { return }
        if let fetchedAt, Date().timeIntervalSince(fetchedAt) < 60 { return }
        refreshing = true
        defer { refreshing = false }

        if let fresh = await Self.download() {
            rates = fresh
            fetchedAt = Date()
            lastRefreshFailed = false
            save()
        } else {
            lastRefreshFailed = true
        }
    }

    private func save() {
        guard let cacheURL, let rates, let fetchedAt,
              let data = try? JSONEncoder().encode(Cached(rates: rates, fetchedAt: fetchedAt)) else { return }
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
    }

    /// Tries each source in turn. Nil when none answered with a valid table.
    nonisolated private static func download() async -> ExchangeRates? {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        for url in sources {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            guard let reply = try? await session.data(for: request),
                  (reply.1 as? HTTPURLResponse)?.statusCode == 200,
                  let rates = try? ExchangeRates.parse(reply.0, base: "BDT")
            else { continue }
            return rates
        }
        return nil
    }
}
