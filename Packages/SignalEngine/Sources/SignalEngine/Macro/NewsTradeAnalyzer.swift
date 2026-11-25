import Foundation

public enum NewsDirectionBias: String, Codable, Sendable, Equatable, Hashable {
    case bullish = "BULLISH"
    case bearish = "BEARISH"
    case neutral = "NEUTRAL"
    case twoWayWhipsaw = "TWO-WAY WHIPSAW"

    public var tradeDirection: TradeDirection {
        switch self {
        case .bullish: return .long
        case .bearish: return .short
        case .neutral, .twoWayWhipsaw: return .neutral
        }
    }
}

public enum NewsCatalystSeverity: String, Codable, Sendable, Equatable, Hashable {
    case high = "High Impact"
    case medium = "Medium Impact"
    case low = "Low Impact"
}

public struct NewsAssetImpactSummary: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String { symbol }
    public let symbol: String
    public let displayName: String
    public let direction: NewsDirectionBias
    public let rationale: String
    public let severity: NewsCatalystSeverity

    public init(
        symbol: String,
        displayName: String,
        direction: NewsDirectionBias,
        rationale: String,
        severity: NewsCatalystSeverity
    ) {
        self.symbol = symbol
        self.displayName = displayName
        self.direction = direction
        self.rationale = rationale
        self.severity = severity
    }
}

public struct NewsMarketSummary: Codable, Sendable, Equatable, Hashable {
    public let title: String
    public let source: String
    public let timestampEpochSeconds: TimeInterval
    public let url: String?
    public let severity: NewsCatalystSeverity
    public let headlineBias: NewsDirectionBias
    public let recap: String
    public let whyItMovesMarket: [String]
    public let assetImpacts: [NewsAssetImpactSummary]
    public let isPreReleasePending: Bool
    public let isWhipsawGuardActive: Bool

    public init(
        title: String,
        source: String,
        timestampEpochSeconds: TimeInterval,
        url: String?,
        severity: NewsCatalystSeverity,
        headlineBias: NewsDirectionBias,
        recap: String,
        whyItMovesMarket: [String],
        assetImpacts: [NewsAssetImpactSummary],
        isPreReleasePending: Bool,
        isWhipsawGuardActive: Bool
    ) {
        self.title = title
        self.source = source
        self.timestampEpochSeconds = timestampEpochSeconds
        self.url = url
        self.severity = severity
        self.headlineBias = headlineBias
        self.recap = recap
        self.whyItMovesMarket = whyItMovesMarket
        self.assetImpacts = assetImpacts
        self.isPreReleasePending = isPreReleasePending
        self.isWhipsawGuardActive = isWhipsawGuardActive
    }
}

public enum NewsTradeVerdict: String, Codable, Sendable, Equatable, Hashable {
    case actionableSetup = "ACTIONABLE NEWS + MATH SETUP"
    case waitNoTrade = "WAIT / NO TRADE"
}

public struct NewsTradeEvaluation: Codable, Sendable, Equatable, Hashable {
    public let symbol: String
    public let newsBias: NewsDirectionBias
    public let verdict: NewsTradeVerdict
    public let signal: TradeSignal?
    public let headlineSummary: String
    public let alignmentNotes: [String]
    public let requiredConfirmations: [String]

    public init(
        symbol: String,
        newsBias: NewsDirectionBias,
        verdict: NewsTradeVerdict,
        signal: TradeSignal?,
        headlineSummary: String,
        alignmentNotes: [String],
        requiredConfirmations: [String]
    ) {
        self.symbol = symbol
        self.newsBias = newsBias
        self.verdict = verdict
        self.signal = signal
        self.headlineSummary = headlineSummary
        self.alignmentNotes = alignmentNotes
        self.requiredConfirmations = requiredConfirmations
    }
}

public enum NewsTradeAnalyzer {
    /// Produces a deterministic cross-asset market direction summary for an Economic Calendar event.
    public static func summarize(
        event: EconomicEvent,
        nowEpochSeconds: TimeInterval,
        whipsawWindowMinutes: Int = 5
    ) -> NewsMarketSummary {
        let severity: NewsCatalystSeverity
        switch event.importance {
        case .high: severity = .high
        case .medium: severity = .medium
        case .low: severity = .low
        }

        let canonical = event.canonicalIndicator ?? MacroPolarityTable.canonicalIndicator(for: event.name)
        let higherIsHawkish = canonical.map { MacroPolarityTable.isHigherHawkish(for: $0) } ?? true
        let surprise = MacroSurpriseEngine.evaluateSurprise(
            event: event,
            nowEpochSeconds: nowEpochSeconds,
            whipsawWindowMinutes: whipsawWindowMinutes
        )

        let secondsUntil = event.scheduledEpochSeconds - nowEpochSeconds
        let isPending = !event.isPublished && secondsUntil > -3_600
        let isPreReleaseBlackout = event.isExactClock && isPending && secondsUntil > 0 && secondsUntil <= 15 * 60
        let isWhipsaw = isPreReleaseBlackout || (surprise?.isInPostNewsWhipsawWindow ?? false)

        let headlineBias: NewsDirectionBias
        var whyBullets: [String] = []
        let recap: String

        if let res = surprise {
            switch res.currencyStance {
            case .hawkish:
                headlineBias = isWhipsaw ? .twoWayWhipsaw : .bullish
                recap = "\(event.currency) \(event.name) printed hawkish vs forecast (\(formatMacroNumber(event.actual, unit: event.unit)) vs \(formatMacroNumber(event.forecast, unit: event.unit)))."
                whyBullets.append("A hawkish \(event.currency) surprise lifts \(event.currency) rate expectations and yields.")
                if event.currency == "USD" {
                    whyBullets.append("Stronger USD & higher real yields typically pressure Gold (XAU/USD), Nasdaq 100, S&P 500, EUR/USD, GBP/USD, and Bitcoin while lifting USD/JPY.")
                } else {
                    whyBullets.append("Stronger \(event.currency) pushes \(event.currency)-base pairs higher and \(event.currency)-quote pairs lower.")
                }
            case .dovish:
                headlineBias = isWhipsaw ? .twoWayWhipsaw : .bearish
                recap = "\(event.currency) \(event.name) printed dovish vs forecast (\(formatMacroNumber(event.actual, unit: event.unit)) vs \(formatMacroNumber(event.forecast, unit: event.unit)))."
                whyBullets.append("A dovish \(event.currency) surprise softens \(event.currency) yield expectations and eases financial conditions.")
                if event.currency == "USD" {
                    whyBullets.append("Softer USD & lower yields typically support Gold (XAU/USD), Nasdaq 100, S&P 500, EUR/USD, GBP/USD, and Bitcoin while pressuring USD/JPY.")
                } else {
                    whyBullets.append("Softer \(event.currency) weighs on \(event.currency)-base pairs and lifts \(event.currency)-quote pairs.")
                }
            case .neutral:
                headlineBias = .neutral
                recap = "\(event.currency) \(event.name) printed broadly in-line with consensus (\(formatMacroNumber(event.actual, unit: event.unit)) vs \(formatMacroNumber(event.forecast, unit: event.unit)))."
                whyBullets.append("In-line prints rarely sustain one-way institutional repricing; watch for range liquidity sweeps.")
            case .mixedWhipsaw:
                headlineBias = .twoWayWhipsaw
                recap = "\(event.currency) \(event.name) delivered mixed macro signals with elevated two-way whipsaw risk."
                whyBullets.append("Conflicting components trigger stop runs on both sides before a clean closed-bar direction emerges.")
            }
            if isWhipsaw {
                whyBullets.append("Post-release 5m whipsaw guard is active — spreads and stop-hunts dominate initial candles.")
            }
        } else if !event.isPublished {
            headlineBias = (event.importance == .high) ? .twoWayWhipsaw : .neutral
            let forecastStr = formatMacroNumber(event.forecast, unit: event.unit)
            let prevStr = formatMacroNumber(event.previous, unit: event.unit)
            recap = "Upcoming \(event.currency) \(event.name) (Forecast: \(forecastStr), Previous: \(prevStr)). Actual is unpublished."
            whyBullets.append(
                higherIsHawkish
                    ? "An actual print ABOVE forecast is hawkish for \(event.currency) (bearish for risk assets & Gold if USD); BELOW forecast is dovish."
                    : "An actual print ABOVE forecast is dovish for \(event.currency) (higher joblessness/claims); BELOW forecast is hawkish."
            )
            whyBullets.append("Never front-run an unpublished print: wait for the official release and a closed post-news candle.")
        } else {
            headlineBias = .neutral
            recap = "\(event.currency) \(event.name) published without a consensus forecast comparison."
            whyBullets.append("Without a consensus benchmark, verify directional reaction strictly via closed-bar market structure.")
        }

        let targetSymbols = impactedSymbols(forCurrency: event.currency)
        let assetImpacts: [NewsAssetImpactSummary] = targetSymbols.map { symbol in
            let desc = WatchlistDefaults.descriptor(for: symbol)
            let display = desc?.displayName ?? symbol
            let bias: NewsDirectionBias
            let rationale: String
            if let res = surprise, let desc {
                let dir = MacroPolarityTable.impactDirection(for: desc, currency: event.currency, stance: res.currencyStance)
                if isWhipsaw {
                    bias = .twoWayWhipsaw
                    rationale = "Post-release whipsaw window active; directional lean after settlement is \(dir == .neutral ? "NEUTRAL" : dir.rawValue.uppercased())."
                } else {
                    bias = biasFrom(direction: dir)
                    rationale = rationaleForAsset(symbol: symbol, currency: event.currency, stance: res.currencyStance, direction: dir)
                }
            } else {
                bias = isPending && event.importance == .high ? .twoWayWhipsaw : .neutral
                rationale = isPending
                    ? "Pending \(event.currency) release — directional bias activates once Actual prints vs Forecast."
                    : "No decisive macro surprise — rely on closed-bar technical structure."
            }
            return NewsAssetImpactSummary(
                symbol: symbol,
                displayName: display,
                direction: bias,
                rationale: rationale,
                severity: severity
            )
        }

        return NewsMarketSummary(
            title: "\(event.countryCode) \(event.name)",
            source: event.source == .biquote ? "biquote.io Calendar" : "Forex Factory Schedule",
            timestampEpochSeconds: event.scheduledEpochSeconds,
            url: nil,
            severity: severity,
            headlineBias: headlineBias,
            recap: recap,
            whyItMovesMarket: whyBullets,
            assetImpacts: assetImpacts,
            isPreReleasePending: isPending,
            isWhipsawGuardActive: isWhipsaw
        )
    }

    /// Produces a deterministic cross-asset market direction summary for a Breaking News headline.
    public static func summarize(newsItem: BreakingNewsItem) -> NewsMarketSummary {
        let absPolarity = abs(newsItem.polarityScore)
        let severity: NewsCatalystSeverity
        if absPolarity >= 1.5 {
            severity = .high
        } else if absPolarity >= 0.8 || !newsItem.matchedKeywords.isEmpty {
            severity = .medium
        } else {
            severity = .low
        }

        let headlineBias: NewsDirectionBias
        switch newsItem.sentiment {
        case .bullish: headlineBias = .bullish
        case .bearish: headlineBias = .bearish
        case .volatileNeutral:
            headlineBias = newsItem.matchedKeywords.isEmpty ? .neutral : .twoWayWhipsaw
        }

        var whyBullets: [String] = []
        if !newsItem.matchedKeywords.isEmpty {
            whyBullets.append("Detected catalysts: \(newsItem.matchedKeywords.prefix(4).joined(separator: ", ")).")
        }
        switch headlineBias {
        case .bullish:
            whyBullets.append("Positive headline polarity (\(String(format: "%+.1f", newsItem.polarityScore))) supports risk appetite / buying flows on directly linked pairs.")
        case .bearish:
            whyBullets.append("Negative headline polarity (\(String(format: "%+.1f", newsItem.polarityScore))) introduces headline de-risking or selling pressure on exposed assets.")
        case .twoWayWhipsaw:
            whyBullets.append("Event-driven macro/geopolitical volatility often sweeps both highs and lows before establishing trend continuation.")
        case .neutral:
            whyBullets.append("Informational headline without strong directional polarity — technical structure governs trade selection.")
        }

        let rawSymbols = newsItem.affectedAssets.isEmpty ? ["BTC/USDT", "XAU/USD", "US500", "NAS100"] : newsItem.affectedAssets
        let assetImpacts: [NewsAssetImpactSummary] = rawSymbols.compactMap { sym in
            guard let desc = WatchlistDefaults.descriptor(for: sym) else { return nil }
            let pairBias = assetBiasForHeadline(newsItem: newsItem, asset: desc, baseBias: headlineBias)
            let rationale: String
            switch pairBias {
            case .bullish:
                rationale = "Headline tailwind favors LONG continuation if closed-bar structure & R:R confirm."
            case .bearish:
                rationale = "Headline headwind favors SHORT continuation if closed-bar structure & R:R confirm."
            case .twoWayWhipsaw:
                rationale = "Headline raises intraday volatility; wait for liquidity sweep + BOS/MSS confirmation."
            case .neutral:
                rationale = "Indirect or neutral headline exposure; trade only on independent multi-strategy confluence."
            }
            return NewsAssetImpactSummary(
                symbol: desc.symbol,
                displayName: desc.displayName,
                direction: pairBias,
                rationale: rationale,
                severity: severity
            )
        }

        let recap = newsItem.summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? newsItem.summary!
            : newsItem.title

        return NewsMarketSummary(
            title: newsItem.title,
            source: newsItem.source,
            timestampEpochSeconds: newsItem.publishedEpochSeconds,
            url: newsItem.url,
            severity: severity,
            headlineBias: headlineBias,
            recap: recap,
            whyItMovesMarket: whyBullets,
            assetImpacts: assetImpacts,
            isPreReleasePending: false,
            isWhipsawGuardActive: headlineBias == .twoWayWhipsaw
        )
    }

    /// Fuses a selected news item's directional bias with live/closed-candle deterministic `SignalEngine.analyze(...)`
    /// to emit either an Actionable News+Math `TradeSignal` OR an explicit `WAIT / NO TRADE` safety verdict.
    public static func evaluateTrade(
        summary: NewsMarketSummary,
        asset: AssetDescriptor,
        rawEntryCandles: [Candle],
        rawHTFCandles: [Candle],
        timeframe: Timeframe,
        htfTimeframe: Timeframe = .h4,
        okxDerivatives: OKXDerivativesSnapshot? = nil,
        cftcCOTRecords: [CFTCCOTRecord] = [],
        calendarEvents: [EconomicEvent] = [],
        breakingNews: [BreakingNewsItem] = [],
        fearGreed: FearGreedSnapshot? = nil,
        config: EngineConfig = EngineConfig(),
        dataProvider: String,
        serverNowEpochSeconds: TimeInterval
    ) -> NewsTradeEvaluation {
        let assetImpact = summary.assetImpacts.first { $0.symbol.caseInsensitiveCompare(asset.symbol) == .orderedSame }
        let newsBias = assetImpact?.direction ?? summary.headlineBias

        let analysis = SignalEngine.analyze(
            asset: asset,
            rawEntryCandles: rawEntryCandles,
            rawHTFCandles: rawHTFCandles,
            timeframe: timeframe,
            htfTimeframe: htfTimeframe,
            okxDerivatives: okxDerivatives,
            cftcCOTRecords: cftcCOTRecords,
            calendarEvents: calendarEvents,
            breakingNews: breakingNews,
            fearGreed: fearGreed,
            config: config,
            dataProvider: dataProvider,
            serverNowEpochSeconds: serverNowEpochSeconds
        )

        var notes: [String] = []
        var confirmNeeded: [String] = []

        if summary.isPreReleasePending {
            confirmNeeded.append("Wait for the official Actual print to publish before entering.")
        }
        if summary.isWhipsawGuardActive || newsBias == .twoWayWhipsaw {
            confirmNeeded.append("Wait out the initial volatility/whipsaw window and confirm a closed-bar BOS/MSS.")
        }
        if analysis.regimeAssessment.regime == .crisis {
            confirmNeeded.append("Crisis volatility regime active (risk_state=reduce) — stand aside until ATR normalizes.")
        }

        guard let signal = analysis.signal else {
            let reason = analysis.hygieneReport.rejectionReason?.rawValue ?? "insufficient closed candles"
            confirmNeeded.append("Wait for clean closed-candle feed (\(reason)).")
            return NewsTradeEvaluation(
                symbol: asset.symbol,
                newsBias: newsBias,
                verdict: .waitNoTrade,
                signal: nil,
                headlineSummary: "Unable to build a closed-bar setup on \(asset.symbol) (\(reason)).",
                alignmentNotes: notes,
                requiredConfirmations: confirmNeeded
            )
        }

        notes.append("Technical engine direction: \(signal.direction.rawValue.uppercased()) (\(Int(signal.confidencePercent.rounded()))% · \(signal.alignedStrategies.count) aligned).")
        if let lv = signal.levels {
            notes.append("Calculated R:R 1:\(String(format: "%.2f", lv.riskRewardRatio)) with \(String(format: "%.2f", lv.riskPercent))% stop distance.")
        }
        if signal.isMarketClosedSnapshot {
            confirmNeeded.append("\(asset.symbol) market is currently closed — re-verify at session open before acting.")
        }

        let newsDir = newsBias.tradeDirection
        let newsOpposesMath = (newsDir != .neutral && signal.direction != .neutral && newsDir != signal.direction)

        if newsOpposesMath {
            notes.append("Conflict: News bias leans \(newsBias.rawValue), while closed-bar structure favors \(signal.direction.rawValue.uppercased()).")
            confirmNeeded.append("Wait for a closed-bar \(newsDir == .long ? "Bullish" : "Bearish") MSS/BOS or Liquidity Sweep aligning chart structure with the news catalyst.")
        } else if newsDir != .neutral && newsDir == signal.direction {
            notes.append("Alignment confirmed: Both news catalyst (\(newsBias.rawValue)) and chart math agree \(signal.direction.rawValue.uppercased()).")
        }

        if !signal.rejectionReasons.isEmpty {
            confirmNeeded.append(contentsOf: signal.rejectionReasons)
        }

        let isActionable = (signal.category == .strongSignal)
            && !summary.isPreReleasePending
            && !summary.isWhipsawGuardActive
            && !newsOpposesMath
            && !signal.isMarketClosedSnapshot
            && analysis.regimeAssessment.regime != .crisis

        let verdict: NewsTradeVerdict = isActionable ? .actionableSetup : .waitNoTrade
        let headlineSummary: String
        if isActionable {
            headlineSummary = "\(asset.symbol) \(signal.direction.rawValue.uppercased()) passes full News + Math confluence (\(Int(signal.confidencePercent.rounded()))% · \(signal.strengthBreakdown?.strengthLabel ?? signal.tier.displayName))."
        } else if newsOpposesMath {
            headlineSummary = "WAIT / NO TRADE on \(asset.symbol): News leans \(newsBias.rawValue) but closed-bar math opposes (\(signal.direction.rawValue.uppercased()))."
        } else if summary.isPreReleasePending {
            headlineSummary = "WAIT / NO TRADE on \(asset.symbol): Catalyst is not yet published."
        } else {
            headlineSummary = "WAIT / NO TRADE on \(asset.symbol): Closed-bar technical & risk gates are not yet fully confirmed."
        }

        return NewsTradeEvaluation(
            symbol: asset.symbol,
            newsBias: newsBias,
            verdict: verdict,
            signal: signal,
            headlineSummary: headlineSummary,
            alignmentNotes: notes,
            requiredConfirmations: Array(NSOrderedSet(array: confirmNeeded)).compactMap { $0 as? String }
        )
    }

    // MARK: - Private Helpers

    private static func impactedSymbols(forCurrency currency: String) -> [String] {
        switch currency.uppercased() {
        case "USD":
            return ["XAU/USD", "EUR/USD", "GBP/USD", "USD/JPY", "US500", "NAS100", "BTC/USDT"]
        case "EUR":
            return ["EUR/USD", "XAU/USD"]
        case "GBP":
            return ["GBP/USD", "EUR/USD"]
        case "JPY":
            return ["USD/JPY", "NAS100"]
        default:
            return ["XAU/USD", "EUR/USD", "US500", "BTC/USDT"]
        }
    }

    private static func biasFrom(direction: TradeDirection) -> NewsDirectionBias {
        switch direction {
        case .long: return .bullish
        case .short: return .bearish
        case .neutral: return .neutral
        }
    }

    private static func rationaleForAsset(
        symbol: String,
        currency: String,
        stance: MacroStance,
        direction: TradeDirection
    ) -> String {
        guard direction != .neutral else {
            return "Limited direct directional transmission from this \(currency) release."
        }
        let stanceText = (stance == .hawkish) ? "Hawkish \(currency)" : "Dovish \(currency)"
        let move = (direction == .long) ? "upside" : "downside"
        return "\(stanceText) surprise historically transmits \(move) pressure onto \(symbol)."
    }

    private static func assetBiasForHeadline(
        newsItem: BreakingNewsItem,
        asset: AssetDescriptor,
        baseBias: NewsDirectionBias
    ) -> NewsDirectionBias {
        // Handle USD/JPY inverse rate sensitivity when headline is strictly Fed/USD hawkish/dovish
        let norm = HeadlineSentimentClassifier.normalizedTokenString("\(newsItem.title) \(newsItem.summary ?? "")")
        let isFedRateNews = norm.contains(" rate hike ") || norm.contains(" hawkish ") || norm.contains(" rate cut ") || norm.contains(" dovish ")
        if asset.symbol == "USD/JPY" && isFedRateNews {
            if baseBias == .bearish { return .bullish } // Hawkish Fed = bearish risk assets, bullish USD/JPY
            if baseBias == .bullish { return .bearish } // Dovish Fed = bullish risk assets, bearish USD/JPY
        }
        return baseBias
    }

    private static func formatMacroNumber(_ value: Double?, unit: String?) -> String {
        guard let v = value, v.isFinite else { return "—" }
        let formatted = abs(v) >= 100 ? String(format: "%.1f", v) : String(format: "%.2f", v)
        if let u = unit, !u.isEmpty {
            return "\(formatted)\(u)"
        }
        return formatted
    }
}
