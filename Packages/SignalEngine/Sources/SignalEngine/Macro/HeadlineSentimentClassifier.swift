import Foundation

public enum HeadlineSentimentClassifier {
    private static let bullishTerms: [(String, Double)] = [
        ("etf approved", 2.0), ("etf approval", 2.0), ("spot etf", 1.2),
        ("rate cut", 1.8), ("dovish", 1.6), ("cooler inflation", 1.6), ("cpi cools", 1.6),
        ("earnings beat", 1.5), ("beats estimates", 1.5), ("record inflows", 1.6),
        ("institutional buying", 1.5), ("treasury buyback", 1.2), ("stimulus", 1.3),
        ("upgrade", 1.0), ("surge", 0.9), ("rally", 0.9), ("breakout", 0.8),
        ("partnership", 0.7), ("adoption", 0.8)
    ]

    private static let bearishTerms: [(String, Double)] = [
        ("exchange hack", -2.2), ("exploit", -2.0), ("drained", -1.9), ("insolvency", -2.2),
        ("bankruptcy", -2.2), ("sec lawsuit", -1.8), ("indictment", -1.8), ("etf rejected", -2.0),
        ("rate hike", -1.8), ("hawkish", -1.6), ("hotter inflation", -1.6), ("cpi surges", -1.6),
        ("earnings miss", -1.5), ("misses estimates", -1.5), ("outflows", -1.3),
        ("liquidation cascade", -1.5), ("downgrade", -1.1), ("ban", -1.4), ("sanction", -1.2),
        ("plunge", -1.0), ("crash", -1.3), ("sell-off", -1.0), ("tariff", -1.0)
    ]

    private static let volatileTerms: [String] = [
        "emergency meeting", "fomc", "cpi", "nfp", "powell", "war", "geopolitical", "flash", "halt", "volatility"
    ]

    private static let assetMatchers: [(symbol: String, keywords: [String])] = [
        ("BTC/USDT", ["bitcoin", "btc"]),
        ("ETH/USDT", ["ethereum", "eth ", "ether "]),
        ("SOL/USDT", ["solana", " sol "]),
        ("XAU/USD", ["gold", "xau", "bullion"]),
        ("EUR/USD", ["euro", "ecb", "eur/usd", "eurusd"]),
        ("GBP/USD", ["pound", "sterling", "boe", "gbp/usd", "gbpusd"]),
        ("USD/JPY", ["yen", "boj", "usd/jpy", "usdjpy"]),
        ("US500", ["s&p 500", "s&p500", "sp500", "wall street", "fed ", "fomc", "cpi", "nfp", "powell"]),
        ("NAS100", ["nasdaq", "tech stocks", "ndx"]),
        ("AAPL", ["apple", "aapl"]),
        ("NVDA", ["nvidia", "nvda"]),
        ("MSFT", ["microsoft", "msft"])
    ]

    /// Deterministic on-device financial polarity classifier + asset tagger (zero ML bloat).
    public static func classify(
        id: String,
        title: String,
        summary: String? = nil,
        source: String,
        url: String? = nil,
        publishedEpochSeconds: TimeInterval
    ) -> BreakingNewsItem {
        let combined = " \(title.lowercased()) \(summary?.lowercased() ?? "") "
        var score = 0.0
        var matched: [String] = []

        for (term, weight) in bullishTerms where combined.contains(term) {
            score += weight
            matched.append(term)
        }
        for (term, weight) in bearishTerms where combined.contains(term) {
            score += weight
            matched.append(term)
        }

        let hasVolatile = volatileTerms.contains { combined.contains($0) }
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
            if matcher.keywords.contains(where: { combined.contains($0) }) {
                affected.append(matcher.symbol)
            }
        }
        if affected.isEmpty && (combined.contains("crypto") || combined.contains("digital asset")) {
            affected.append("BTC/USDT")
        }
        if affected.isEmpty && (combined.contains("dollar") || combined.contains("treasury") || combined.contains("inflation")) {
            affected.append(contentsOf: ["XAU/USD", "EUR/USD", "US500"])
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
}
