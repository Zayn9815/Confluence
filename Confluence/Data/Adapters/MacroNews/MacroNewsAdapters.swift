import Foundation
import SignalEngine

/// Primary Economic Calendar adapter (`biquote.io/api/calendar`) + disk-cached Forex Factory fallback
/// (`nfs.faireconomy.media/ff_calendar_thisweek.json` with >= 60m cooldown, 24h offline fallback,
/// and strict HTML "Request Denied" rejection).
public actor EconomicCalendarService {
    private let http: any HTTPTransport
    private let ffCacheURL: URL
    private var lastFFFetchDate: Date?
    private var cachedFFEvents: [EconomicEvent] = []

    public init(http: any HTTPTransport, cacheDirectory: URL? = nil) {
        self.http = http
        let dir = cacheDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.ffCacheURL = dir.appendingPathComponent("confluence_ff_calendar_cache.json")
        if let disk = Self.loadFFCache(from: self.ffCacheURL) {
            self.lastFFFetchDate = disk.fetchedAt
            self.cachedFFEvents = disk.events
        }
    }

    public func fetchCalendarEvents(
        countries: [String] = ["US", "EU", "GB", "JP"],
        minimumImportance: MacroImportance = .medium
    ) async -> (events: [EconomicEvent], sourceLabel: String) {
        do {
            let primary = try await fetchBiquoteCalendar(countries: countries, minimumImportance: minimumImportance)
            if !primary.isEmpty {
                return (primary, "biquote.io")
            }
        } catch {
            // Fall through cleanly to disk-cached Forex Factory schedule
        }

        let fallback = await fetchForexFactoryWithStrictCooldown()
        let filtered = fallback.filter { $0.importance >= minimumImportance }
        return (filtered, "Forex Factory (Schedule Fallback)")
    }

    public func fetchBiquoteCalendar(
        countries: [String],
        minimumImportance: MacroImportance
    ) async throws -> [EconomicEvent] {
        var comps = URLComponents(string: "https://biquote.io/api/calendar")!
        comps.queryItems = [
            URLQueryItem(name: "countries", value: countries.joined(separator: ",")),
            URLQueryItem(name: "importance", value: minimumImportance.rawValue),
            URLQueryItem(name: "limit", value: "200")
        ]
        guard let url = comps.url else { throw NetworkAdapterError.invalidURL("biquote calendar") }
        let res = try await http.send(URLRequest(url: url), maxRetries: 1)
        return try Self.parseBiquoteCalendarJSON(data: res.data)
    }

    public static func parseBiquoteCalendarJSON(data: Data) throws -> [EconomicEvent] {
        struct Row: Decodable {
            let id: String?
            let eventId: String?
            let time: String
            let countryCode: String
            let currency: String
            let name: String
            let importance: String
            let unit: String?
            let multiplier: String?
            let actual: Double?
            let forecast: Double?
            let previous: Double?
            let revisedPrevious: Double?
            let timeMode: String?
        }

        let rows = try JSONDecoder().decode([Row].self, from: data)
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoStd = ISO8601DateFormatter()
        let dayFmt = DateFormatter()
        dayFmt.locale = Locale(identifier: "en_US_POSIX")
        dayFmt.timeZone = TimeZone(secondsFromGMT: 0)
        dayFmt.dateFormat = "yyyy-MM-dd"

        var dedup: [String: EconomicEvent] = [:]
        for r in rows {
            guard let date = isoFrac.date(from: r.time) ?? isoStd.date(from: r.time) else { continue }
            let imp = MacroImportance(rawValue: r.importance.lowercased()) ?? .low
            let mode = CalendarTimeMode(rawValue: (r.timeMode ?? "exact").lowercased()) ?? .tentative
            let canonical = MacroPolarityTable.canonicalIndicator(for: r.name)
            let dayStr = dayFmt.string(from: date)
            let nameSlug = (canonical?.rawValue ?? r.name.lowercased().replacingOccurrences(of: " ", with: "_"))
            let semanticKey = "\(r.countryCode.uppercased())|\(nameSlug)|\(dayStr)"

            let ev = EconomicEvent(
                semanticKey: semanticKey,
                source: .biquote,
                upstreamEventId: r.eventId ?? r.id,
                countryCode: r.countryCode.uppercased(),
                currency: r.currency.uppercased(),
                name: r.name,
                canonicalIndicator: canonical,
                importance: imp,
                timeMode: mode,
                scheduledEpochSeconds: date.timeIntervalSince1970,
                unit: r.unit,
                multiplier: r.multiplier,
                actual: r.actual,                   // Strictly nil if unpublished; NEVER 0
                forecast: r.forecast,
                previous: r.previous,
                revisedPrevious: r.revisedPrevious,
                supportsActualRelease: true
            )
            dedup[semanticKey] = ev
        }
        return dedup.values.sorted { $0.scheduledEpochSeconds < $1.scheduledEpochSeconds }
    }

    public func fetchForexFactoryWithStrictCooldown() async -> [EconomicEvent] {
        let now = Date()
        // Enforce strict >= 60-minute refresh cooldown to never trip FF's "Request Denied" HTML block
        if let last = lastFFFetchDate, now.timeIntervalSince(last) < 3_600.0, !cachedFFEvents.isEmpty {
            return cachedFFEvents
        }

        do {
            let url = URL(string: "https://nfs.faireconomy.media/ff_calendar_thisweek.json")!
            let res = try await http.send(URLRequest(url: url), maxRetries: 0)
            let parsed = try Self.parseForexFactoryPayload(data: res.data, contentType: res.headers["content-type"])
            self.cachedFFEvents = parsed
            self.lastFFFetchDate = now
            Self.saveFFCache(FFDiskCache(fetchedAt: now, events: parsed), to: ffCacheURL)
            return parsed
        } catch {
            // 24-hour offline disk cache fallback
            if let last = lastFFFetchDate, now.timeIntervalSince(last) <= 86_400.0 {
                return cachedFFEvents
            }
            return []
        }
    }

    /// Validates both Content-Type and leading `[` byte so HTTP 200 HTML "Request Denied" pages
    /// are safely rejected instead of corrupting the calendar cache.
    public static func parseForexFactoryPayload(data: Data, contentType: String?) throws -> [EconomicEvent] {
        if let ct = contentType?.lowercased(), ct.contains("text/html") {
            throw NetworkAdapterError.htmlRateLimitPage("nfs.faireconomy.media")
        }
        guard let trimmedFirst = String(data: data.prefix(64), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              trimmedFirst.hasPrefix("[")
        else {
            throw NetworkAdapterError.htmlRateLimitPage("nfs.faireconomy.media")
        }

        struct FFRow: Decodable {
            let title: String
            let country: String
            let date: String
            let impact: String
            let forecast: String?
            let previous: String?
        }
        let rows = try JSONDecoder().decode([FFRow].self, from: data)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        let dayFmt = DateFormatter()
        dayFmt.locale = Locale(identifier: "en_US_POSIX")
        dayFmt.timeZone = TimeZone(secondsFromGMT: 0)
        dayFmt.dateFormat = "yyyy-MM-dd"

        var out: [EconomicEvent] = []
        for r in rows {
            guard let date = iso.date(from: r.date) else { continue }
            let imp: MacroImportance
            switch r.impact.lowercased() {
            case "high": imp = .high
            case "medium": imp = .medium
            default: imp = .low
            }
            let ccy = r.country.uppercased()
            let countryCode: String
            switch ccy {
            case "USD": countryCode = "US"
            case "EUR": countryCode = "EU"
            case "GBP": countryCode = "GB"
            case "JPY": countryCode = "JP"
            default: countryCode = String(ccy.prefix(2))
            }
            let canonical = MacroPolarityTable.canonicalIndicator(for: r.title)
            let slug = canonical?.rawValue ?? r.title.lowercased().replacingOccurrences(of: " ", with: "_")
            let key = "\(countryCode)|\(slug)|\(dayFmt.string(from: date))"

            out.append(EconomicEvent(
                semanticKey: key,
                source: .forexFactory,
                countryCode: countryCode,
                currency: ccy,
                name: r.title,
                canonicalIndicator: canonical,
                importance: imp,
                timeMode: .exact,
                scheduledEpochSeconds: date.timeIntervalSince1970,
                actual: nil, // Forex Factory weekly export carries NO actual column
                forecast: parseNumericString(r.forecast),
                previous: parseNumericString(r.previous),
                supportsActualRelease: false
            ))
        }
        return out.sorted { $0.scheduledEpochSeconds < $1.scheduledEpochSeconds }
    }

    private static func parseNumericString(_ raw: String?) -> Double? {
        guard let raw else { return nil }
        let cleaned = raw.replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: "K", with: "")
            .replacingOccurrences(of: "M", with: "")
            .replacingOccurrences(of: "B", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Double(cleaned)
    }

    private struct FFDiskCache: Codable {
        let fetchedAt: Date
        let events: [EconomicEvent]
    }

    private static func loadFFCache(from url: URL) -> FFDiskCache? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(FFDiskCache.self, from: data)
    }

    private static func saveFFCache(_ cache: FFDiskCache, to url: URL) {
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

/// Breaking News & Sentiment Radar aggregating `cryptocurrency.cv` (`/api/breaking`, `/api/news`, `/api/fear-greed`
/// with `alternative.me` fallback), `biquote.io/api/news/market` (filtering Hacker News noise),
/// optional Finnhub `/api/v1/news`, and native `XMLParser` financial RSS fallback.
public actor BreakingNewsService {
    private let http: any HTTPTransport

    public init(http: any HTTPTransport) {
        self.http = http
    }

    public func fetchNewsAndSentiment(finnhubAPIKey: String?) async -> (items: [BreakingNewsItem], fearGreed: FearGreedSnapshot?) {
        async let cryptoNewsTask = fetchCryptoCVNews()
        async let macroNewsTask = fetchBiquoteMarketNews()
        async let rssNewsTask = fetchFinancialRSS()
        async let finnhubTask = fetchFinnhubNews(apiKey: finnhubAPIKey)
        async let fgTask = fetchFearGreed()

        let combined = await (cryptoNewsTask + macroNewsTask + rssNewsTask + finnhubTask)
        let fg = await fgTask

        // Deduplicate by normalized title prefix and sort newest-first
        var seen = Set<String>()
        var unique: [BreakingNewsItem] = []
        for item in combined.sorted(by: { $0.publishedEpochSeconds > $1.publishedEpochSeconds }) {
            let norm = String(item.title.lowercased().filter { $0.isLetter || $0.isNumber }.prefix(48))
            if !seen.contains(norm) {
                seen.insert(norm)
                unique.append(item)
            }
        }
        return (Array(unique.prefix(60)), fg)
    }

    private func fetchCryptoCVNews() async -> [BreakingNewsItem] {
        var results: [BreakingNewsItem] = []
        for endpoint in ["https://cryptocurrency.cv/api/breaking", "https://cryptocurrency.cv/api/news?limit=15"] {
            guard let url = URL(string: endpoint),
                  let res = try? await http.send(URLRequest(url: url), maxRetries: 1)
            else { continue }
            results.append(contentsOf: Self.parseCryptoCVArticles(data: res.data))
        }
        return results
    }

    public static func parseCryptoCVArticles(data: Data) -> [BreakingNewsItem] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let rawList: [[String: Any]]
        if let arr = obj as? [[String: Any]] {
            rawList = arr
        } else if let dict = obj as? [String: Any],
                  let arr = (dict["articles"] ?? dict["news"] ?? dict["data"]) as? [[String: Any]] {
            rawList = arr
        } else {
            return []
        }

        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoStd = ISO8601DateFormatter()

        return rawList.compactMap { row in
            guard let title = row["title"] as? String, !title.isEmpty else { return nil }
            let link = (row["link"] ?? row["url"]) as? String
            let source = (row["source"] ?? row["publisher"]) as? String ?? "cryptocurrency.cv"
            let desc = (row["description"] ?? row["summary"]) as? String
            let pubStr = (row["pubDate"] ?? row["publishedAt"] ?? row["published_at"]) as? String
            let epoch = pubStr.flatMap { isoFrac.date(from: $0) ?? isoStd.date(from: $0) }?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
            let id = "cv-\(abs(title.hashValue))"
            return HeadlineSentimentClassifier.classify(
                id: id, title: title, summary: desc, source: source, url: link, publishedEpochSeconds: epoch
            )
        }
    }

    private func fetchBiquoteMarketNews() async -> [BreakingNewsItem] {
        guard let url = URL(string: "https://biquote.io/api/news/market?language=en&country=US&maxResults=25"),
              let res = try? await http.send(URLRequest(url: url), maxRetries: 1)
        else { return [] }

        struct BQArticle: Decodable {
            let title: String
            let description: String?
            let url: String?
            let publisher: String?
            let publishedDate: String?
        }
        guard let rows = try? JSONDecoder().decode([BQArticle].self, from: res.data) else { return [] }
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoStd = ISO8601DateFormatter()

        return rows.compactMap { row in
            // Filter out generic Hacker News stories interleaved by biquote's market news endpoint
            if let pub = row.publisher, pub.caseInsensitiveCompare("Hacker News") == .orderedSame {
                return nil
            }
            let epoch = row.publishedDate.flatMap { isoFrac.date(from: $0) ?? isoStd.date(from: $0) }?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
            return HeadlineSentimentClassifier.classify(
                id: "bq-\(abs(row.title.hashValue))",
                title: row.title,
                summary: row.description,
                source: row.publisher ?? "biquote Market",
                url: row.url,
                publishedEpochSeconds: epoch
            )
        }
    }

    private func fetchFinnhubNews(apiKey: String?) async -> [BreakingNewsItem] {
        guard let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty,
              let url = URL(string: "https://finnhub.io/api/v1/news?category=general&token=\(key)"),
              let res = try? await http.send(URLRequest(url: url), maxRetries: 1)
        else { return [] }

        struct FHItem: Decodable {
            let id: Int
            let headline: String
            let summary: String?
            let source: String?
            let url: String?
            let datetime: TimeInterval
        }
        guard let rows = try? JSONDecoder().decode([FHItem].self, from: res.data) else { return [] }
        return rows.prefix(20).map { row in
            HeadlineSentimentClassifier.classify(
                id: "fh-\(row.id)",
                title: row.headline,
                summary: row.summary,
                source: row.source ?? "Finnhub",
                url: row.url,
                publishedEpochSeconds: row.datetime
            )
        }
    }

    private func fetchFinancialRSS() async -> [BreakingNewsItem] {
        let feeds: [(name: String, url: String)] = [
            ("FXStreet", "https://www.fxstreet.com/rss/news"),
            ("CoinDesk", "https://www.coindesk.com/arc/outboundfeeds/rss/")
        ]
        var collected: [BreakingNewsItem] = []
        for feed in feeds {
            guard let url = URL(string: feed.url),
                  let res = try? await http.send(URLRequest(url: url), maxRetries: 0)
            else { continue }
            let parser = SimpleRSSParser(sourceName: feed.name)
            collected.append(contentsOf: parser.parse(data: res.data).prefix(10))
        }
        return collected
    }

    private func fetchFearGreed() async -> FearGreedSnapshot? {
        // Primary: verified cryptocurrency.cv route `/api/fear-greed`
        if let url = URL(string: "https://cryptocurrency.cv/api/fear-greed"),
           let res = try? await http.send(URLRequest(url: url), maxRetries: 1),
           let root = try? JSONSerialization.jsonObject(with: res.data) as? [String: Any],
           let current = root["current"] as? [String: Any],
           let val = current["value"] as? Int {
            let label = (current["valueClassification"] as? String) ?? classifyFG(val)
            let ts = (current["timestamp"] as? Double) ?? Date().timeIntervalSince1970
            return FearGreedSnapshot(value: val, classification: label, updatedEpochSeconds: ts, source: "cryptocurrency.cv")
        }

        // Keyless fallback: Alternative.me public Fear & Greed API
        if let url = URL(string: "https://api.alternative.me/fng/?limit=1"),
           let res = try? await http.send(URLRequest(url: url), maxRetries: 1) {
            struct AltResp: Decodable {
                struct Item: Decodable {
                    let value: String
                    let value_classification: String
                    let timestamp: String
                }
                let data: [Item]
            }
            if let decoded = try? JSONDecoder().decode(AltResp.self, from: res.data),
               let first = decoded.data.first,
               let val = Int(first.value) {
                return FearGreedSnapshot(
                    value: val,
                    classification: first.value_classification,
                    updatedEpochSeconds: Double(first.timestamp) ?? Date().timeIntervalSince1970,
                    source: "Alternative.me"
                )
            }
        }
        return nil
    }

    private func classifyFG(_ v: Int) -> String {
        if v <= 20 { return "Extreme Fear" }
        if v <= 40 { return "Fear" }
        if v <= 60 { return "Neutral" }
        if v <= 80 { return "Greed" }
        return "Extreme Greed"
    }
}

private final class SimpleRSSParser: NSObject, XMLParserDelegate {
    private let sourceName: String
    private var items: [BreakingNewsItem] = []
    private var inItem = false
    private var currentElement = ""
    private var currentTitle = ""
    private var currentLink = ""
    private var currentDesc = ""
    private var currentPubDate = ""

    init(sourceName: String) {
        self.sourceName = sourceName
    }

    func parse(data: Data) -> [BreakingNewsItem] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName.lowercased()
        if currentElement == "item" {
            inItem = true
            currentTitle = ""
            currentLink = ""
            currentDesc = ""
            currentPubDate = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inItem else { return }
        switch currentElement {
        case "title": currentTitle += string
        case "link": currentLink += string
        case "description": currentDesc += string
        case "pubdate": currentPubDate += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName.lowercased() == "item" {
            inItem = false
            let title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return }
            let epoch = parseRSSDate(currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines)) ?? Date().timeIntervalSince1970
            items.append(
                HeadlineSentimentClassifier.classify(
                    id: "rss-\(sourceName)-\(abs(title.hashValue))",
                    title: title,
                    summary: currentDesc.trimmingCharacters(in: .whitespacesAndNewlines),
                    source: sourceName,
                    url: currentLink.trimmingCharacters(in: .whitespacesAndNewlines),
                    publishedEpochSeconds: epoch
                )
            )
        }
    }

    private func parseRSSDate(_ raw: String) -> TimeInterval? {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return df.date(from: raw)?.timeIntervalSince1970
    }
}
