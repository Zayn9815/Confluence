import Foundation

public struct NewsCatalystAssessment: Codable, Sendable, Equatable, Hashable {
    public let direction: TradeDirection
    public let netScore: Double
    public let matchingHeadlinesCount: Int
    public let isHighVolatilityNeutral: Bool
    public let headlineBadge: String
    public let summary: String
    public let topHeadline: String?

    public init(
        direction: TradeDirection,
        netScore: Double,
        matchingHeadlinesCount: Int,
        isHighVolatilityNeutral: Bool,
        headlineBadge: String,
        summary: String,
        topHeadline: String?
    ) {
        self.direction = direction
        self.netScore = netScore
        self.matchingHeadlinesCount = matchingHeadlinesCount
        self.isHighVolatilityNeutral = isHighVolatilityNeutral
        self.headlineBadge = headlineBadge
        self.summary = summary
        self.topHeadline = topHeadline
    }
}

public enum HeadlineSentimentClassifier {
    private static let bullishTerms: [(String, Double)] = [
        ("etf approved", 2.0), ("etf approval", 2.0), ("spot etf", 1.2),
        ("rate cut", 1.8), ("rate cuts", 1.8), ("dovish", 1.6), ("cooler inflation", 1.6), ("cpi cools", 1.6),
        ("earnings beat", 1.5), ("beats estimates", 1.5), ("record inflows", 1.6),
        ("institutional buying", 1.5), ("treasury buyback", 1.2), ("stimulus", 1.3),
        ("upgrade", 1.0), ("upgrades", 1.0), ("surge", 0.9), ("surges", 0.9),
        ("rally", 0.9), ("rallies", 0.9), ("breakout", 0.8),
        ("partnership", 0.7), ("adoption", 0.8)
    ]

    private static let bearishTerms: [(String, Double)] = [
        ("exchange hack", -2.2), ("hack", -1.6), ("exploit", -2.0), ("drained", -1.9), ("insolvency", -2.2),
        ("bankruptcy", -2.2), ("sec lawsuit", -1.8), ("indictment", -1.8), ("etf rejected", -2.0),
        ("rate hike", -1.8), ("rate hikes", -1.8), ("hawkish", -1.6), ("hotter inflation", -1.6), ("cpi surges", -1.6),
        ("earnings miss", -1.5), ("misses estimates", -1.5), ("outflows", -1.3),
        ("liquidation cascade", -1.5), ("downgrade", -1.1), ("downgrades", -1.1),
        ("ban", -1.4), ("banned", -1.4), ("sanction", -1.2), ("sanctions", -1.2),
        ("plunge", -1.0), ("plunges", -1.0), ("crash", -1.3), ("crashes", -1.3),
        ("sell-off", -1.0), ("selloff", -1.0), ("tariff", -1.0), ("tariffs", -1.0)
    ]

    private static let volatileTerms: [String] = [
        "emergency meeting", "fomc", "cpi", "nfp", "powell", "war", "geopolitical", "flash", "halt", "volatility"
    ]

    private static let assetMatchers: [(symbol: String, keywords: [String])] = [
        ("BTC/USDT", ["bitcoin", "btc"]),
        ("ETH/USDT", ["ethereum", "eth", "ether"]),
        ("SOL/USDT", ["solana", "sol"]),
        ("XAU/USD", ["gold", "xau", "bullion"]),
        ("EUR/USD", ["euro", "ecb", "eur/usd", "eurusd"]),
        ("GBP/USD", ["pound", "sterling", "boe", "gbp/usd", "gbpusd"]),
        ("USD/JPY", ["yen", "boj", "usd/jpy", "usdjpy"]),
        ("US500", ["s&p 500", "s&p500", "sp500", "wall street", "fed", "fomc", "cpi", "nfp", "powell"]),
        ("NAS100", ["nasdaq", "tech stocks", "ndx", "nas100", "qqq"]),
        ("AAPL", ["apple", "aapl"]),
        ("NVDA", ["nvidia", "nvda"]),
        ("MSFT", ["microsoft", "msft"])
    ]

    /// Normalizes text to space-padded tokens so word-boundary matching prevents false hits like "ban" inside "central bank".
    public static func normalizedTokenString(_ text: String) -> String {
        var out = String()
        out.reserveCapacity(text.count + 2)
        out.append(" ")
        var lastWasSpace = true
        for scalar in text.lowercased().unicodeScalars {
            let isKeep = CharacterSet.alphanumerics.contains(scalar)
                || scalar == "&"
                || scalar == "/"
                || scalar == "-"
            if isKeep {
                out.unicodeScalars.append(scalar)
                lastWasSpace = false
            } else if !lastWasSpace {
                out.append(" ")
                lastWasSpace = true
            }
        }
        if !lastWasSpace {
            out.append(" ")
        }
        return out
    }

    private static func containsWholeTerm(_ normalizedPadded: String, term: String) -> Bool {
        normalizedPadded.contains(" \(term) ")
    }

    /// Deterministic on-device financial polarity classifier + asset tagger (zero ML bloat).
    public static func classify(
        id: String,
        title: String,
        summary: String? = nil,
        source: String,
        url: String? = nil,
        publishedEpochSeconds: TimeInterval
    ) -> BreakingNewsItem {
        let normalized = normalizedTokenString("\(title) \(summary ?? "")")
        var score = 0.0
        var matched: [String] = []

        for (term, weight) in bullishTerms where containsWholeTerm(normalized, term: term) {
            score += weight
            matched.append(term)
        }
        for (term, weight) in bearishTerms where containsWholeTerm(normalized, term: term) {
            score += weight
            matched.append(term)
        }

        let hasVolatile = volatileTerms.contains { containsWholeTerm(normalized, term: $0) }
        if hasVolatile && matched.isEmpty {
            matched.append("macro-volatility")
        }

        let sentiment: NewsSentiment
        if score >= 0.8 {
            sentiment = .bullish
        } else if score <= -0.8 {
            sentiment = .bearish
        } else {
            sentiment = .volatileNeutral
        }

        var affected: [String] = []
        for matcher in assetMatchers {
            if matcher.keywords.contains(where: { containsWholeTerm(normalized, term: $0) }) {
                affected.append(matcher.symbol)
            }
        }
        if affected.isEmpty && (containsWholeTerm(normalized, term: "crypto") || containsWholeTerm(normalized, term: "digital asset")) {
            affected.append("BTC/USDT")
        }
        if affected.isEmpty && (
            containsWholeTerm(normalized, term: "dollar")
            || containsWholeTerm(normalized, term: "treasury")
            || containsWholeTerm(normalized, term: "inflation")
            || containsWholeTerm(normalized, term: "central bank")
            || containsWholeTerm(normalized, term: "federal reserve")
        ) {
            affected.append(contentsOf: ["XAU/USD", "EUR/USD", "US500", "NAS100"])
        }

        return BreakingNewsItem(
            id: id,
            title: title,
            summary: summary,
            source: source,
            url: url,
            publishedEpochSeconds: publishedEpochSeconds,
            affectedAssets: affected,
            sentiment: sentiment,
            polarityScore: score,
            matchedKeywords: matched
        )
    }

    /// Aggregates recent breaking news (`<= 6h` old matching the asset) + optional crypto Fear & Greed
    /// into a disciplined, bounded `NewsCatalystAssessment` for direct SignalEngine fusion.
    public static func analyzeNewsCatalyst(
        for asset: AssetDescriptor,
        breakingNews: [BreakingNewsItem],
        fearGreed: FearGreedSnapshot?,
        nowEpochSeconds: TimeInterval,
        maxAgeSeconds: TimeInterval = 6 * 3_600
    ) -> NewsCatalystAssessment? {
        let relevant = breakingNews.filter { item in
            let age = nowEpochSeconds - item.publishedEpochSeconds
            guard age >= -300 && age <= maxAgeSeconds else { return false }
            return item.affectedAssets.contains { $0.caseInsensitiveCompare(asset.symbol) == .orderedSame }
        }

        var weightedScore = 0.0
        var hasVolatileOnly = false
        for item in relevant {
            let ageHours = max(0.0, (nowEpochSeconds - item.publishedEpochSeconds) / 3_600.0)
            let recencyWeight = max(0.35, 1.0 - (ageHours / 6.0) * 0.65)
            weightedScore += item.polarityScore * recencyWeight
            if item.sentiment == .volatileNeutral && !item.matchedKeywords.isEmpty {
                hasVolatileOnly = true
            }
        }

        // Optional contrarian sentiment nudge for Crypto extremes only
        var fearGreedNote: String? = nil
        if asset.marketClass == .crypto, let fg = fearGreed {
            if fg.value <= 20 {
                weightedScore += 0.35
                fearGreedNote = "Fear & Greed \(fg.value) (\(fg.classification))"
            } else if fg.value >= 80 {
                weightedScore -= 0.35
                fearGreedNote = "Fear & Greed \(fg.value) (\(fg.classification))"
            }
        }

        guard !relevant.isEmpty || fearGreedNote != nil else { return nil }

        let clampedScore = max(-2.0, min(2.0, weightedScore))
        let direction: TradeDirection
        let badge: String
        if clampedScore >= 0.6 {
            direction = .long
            badge = "News Bullish (\(relevant.count))"
        } else if clampedScore <= -0.6 {
            direction = .short
            badge = "News Bearish (\(relevant.count))"
        } else {
            direction = .neutral
            badge = hasVolatileOnly ? "News Volatility Alert" : "News Neutral"
        }

        let topHeadline = relevant.max(by: { abs($0.polarityScore) < abs($1.polarityScore) })?.title
        var parts: [String] = []
        if !relevant.isEmpty {
            parts.append("\(relevant.count) recent \(asset.symbol) headline\(relevant.count == 1 ? "" : "s") (\(direction == .neutral ? "mixed/volatile" : direction.rawValue.uppercased()))")
        }
        if let fgNote = fearGreedNote {
            parts.append(fgNote)
        }

        return NewsCatalystAssessment(
            direction: direction,
            netScore: clampedScore,
            matchingHeadlinesCount: relevant.count,
            isHighVolatilityNeutral: direction == .neutral && hasVolatileOnly,
            headlineBadge: badge,
            summary: parts.joined(separator: " · "),
            topHeadline: topHeadline
        )
    }
}
