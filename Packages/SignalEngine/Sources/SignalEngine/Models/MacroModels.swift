import Foundation

public enum MacroImportance: String, Codable, Sendable, Comparable, CaseIterable {
    case low
    case medium
    case high

    private var rank: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }

    public static func < (lhs: MacroImportance, rhs: MacroImportance) -> Bool {
        lhs.rank < rhs.rank
    }
}

public enum CalendarTimeMode: String, Codable, Sendable, Equatable {
    case exact
    case date
    case notime
    case tentative
}

public enum CalendarSource: String, Codable, Sendable, Equatable {
    case biquote
    case forexFactory
}

public enum CanonicalMacroIndicator: String, Codable, Sendable, CaseIterable {
    case cpi
    case coreCpi
    case pce
    case corePce
    case nfp
    case unemploymentRate
    case centralBankRate
    case gdp
    case retailSales
    case ismPmi
    case ppi
    case averageHourlyEarnings
    case initialJoblessClaims
}

public struct EconomicEvent: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String { semanticKey }
    /// Stable semantic fingerprint surviving upstream ID churn: country|canonicalOrName|dayBucket
    public let semanticKey: String
    public let source: CalendarSource
    public let upstreamEventId: String?
    public let countryCode: String
    public let currency: String
    public let name: String
    public let canonicalIndicator: CanonicalMacroIndicator?
    public let importance: MacroImportance
    public let timeMode: CalendarTimeMode
    public let scheduledEpochSeconds: TimeInterval
    public let unit: String?
    public let multiplier: String?
    /// Strictly nil until officially published — NEVER coerce nil to 0.
    public let actual: Double?
    public let forecast: Double?
    public let previous: Double?
    public let revisedPrevious: Double?
    /// True for biquote.io (publishes actuals); false for Forex Factory schedule-only fallback.
    public let supportsActualRelease: Bool

    public init(
        semanticKey: String,
        source: CalendarSource,
        upstreamEventId: String? = nil,
        countryCode: String,
        currency: String,
        name: String,
        canonicalIndicator: CanonicalMacroIndicator? = nil,
        importance: MacroImportance,
        timeMode: CalendarTimeMode,
        scheduledEpochSeconds: TimeInterval,
        unit: String? = nil,
        multiplier: String? = nil,
        actual: Double? = nil,
        forecast: Double? = nil,
        previous: Double? = nil,
        revisedPrevious: Double? = nil,
        supportsActualRelease: Bool = true
    ) {
        self.semanticKey = semanticKey
        self.source = source
        self.upstreamEventId = upstreamEventId
        self.countryCode = countryCode
        self.currency = currency.uppercased()
        self.name = name
        self.canonicalIndicator = canonicalIndicator
        self.importance = importance
        self.timeMode = timeMode
        self.scheduledEpochSeconds = scheduledEpochSeconds
        self.unit = unit
        self.multiplier = multiplier
        self.actual = actual
        self.forecast = forecast
        self.previous = previous
        self.revisedPrevious = revisedPrevious
        self.supportsActualRelease = supportsActualRelease
    }

    public var isExactClock: Bool { timeMode == .exact }
    public var isPublished: Bool { actual != nil }
    public var hasRevision: Bool {
        guard let rev = revisedPrevious, let prev = previous else { return revisedPrevious != nil }
        return abs(rev - prev) > 1e-9
    }
    public var scheduledDate: Date { Date(timeIntervalSince1970: scheduledEpochSeconds) }
}

public enum MacroStance: String, Codable, Sendable, Equatable {
    case hawkish
    case dovish
    case neutral
    case mixedWhipsaw
}

public struct AssetMacroImpact: Codable, Sendable, Equatable, Hashable {
    public let assetLabel: String
    public let direction: TradeDirection

    public init(assetLabel: String, direction: TradeDirection) {
        self.assetLabel = assetLabel
        self.direction = direction
    }
}

public struct MacroSurpriseResult: Codable, Sendable, Equatable {
    public let event: EconomicEvent
    public let surpriseDelta: Double
    public let surprisePercent: Double
    public let currencyStance: MacroStance
    public let impacts: [AssetMacroImpact]
    public let summaryLine: String
    public let isInPostNewsWhipsawWindow: Bool

    public init(
        event: EconomicEvent,
        surpriseDelta: Double,
        surprisePercent: Double,
        currencyStance: MacroStance,
        impacts: [AssetMacroImpact],
        summaryLine: String,
        isInPostNewsWhipsawWindow: Bool
    ) {
        self.event = event
        self.surpriseDelta = surpriseDelta
        self.surprisePercent = surprisePercent
        self.currencyStance = currencyStance
        self.impacts = impacts
        self.summaryLine = summaryLine
        self.isInPostNewsWhipsawWindow = isInPostNewsWhipsawWindow
    }
}

public struct MacroClusterImpulse: Codable, Sendable, Equatable {
    public let currency: String
    public let clusterEpochSeconds: TimeInterval
    public let results: [MacroSurpriseResult]
    public let netStance: MacroStance
    public let impacts: [AssetMacroImpact]
    public let headlineStrip: String
    public let isWhipsawCautionActive: Bool

    public init(
        currency: String,
        clusterEpochSeconds: TimeInterval,
        results: [MacroSurpriseResult],
        netStance: MacroStance,
        impacts: [AssetMacroImpact],
        headlineStrip: String,
        isWhipsawCautionActive: Bool
    ) {
        self.currency = currency
        self.clusterEpochSeconds = clusterEpochSeconds
        self.results = results
        self.netStance = netStance
        self.impacts = impacts
        self.headlineStrip = headlineStrip
        self.isWhipsawCautionActive = isWhipsawCautionActive
    }
}

public struct PreNewsShieldStatus: Codable, Sendable, Equatable {
    public let event: EconomicEvent
    public let minutesUntilRelease: Int
    public let isBlackoutActive: Bool
    public let badgeText: String

    public init(event: EconomicEvent, minutesUntilRelease: Int, isBlackoutActive: Bool, badgeText: String) {
        self.event = event
        self.minutesUntilRelease = minutesUntilRelease
        self.isBlackoutActive = isBlackoutActive
        self.badgeText = badgeText
    }
}

public enum NewsSentiment: String, Codable, Sendable, Equatable {
    case bullish = "Bullish"
    case bearish = "Bearish"
    case volatileNeutral = "Volatile"
}

public struct BreakingNewsItem: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let summary: String?
    public let source: String
    public let url: String?
    public let publishedEpochSeconds: TimeInterval
    public let affectedAssets: [String]
    public let sentiment: NewsSentiment
    public let polarityScore: Double
    public let matchedKeywords: [String]
    public let aiImpactNote: String?

    public init(
        id: String,
        title: String,
        summary: String? = nil,
        source: String,
        url: String? = nil,
        publishedEpochSeconds: TimeInterval,
        affectedAssets: [String],
        sentiment: NewsSentiment,
        polarityScore: Double,
        matchedKeywords: [String],
        aiImpactNote: String? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.source = source
        self.url = url
        self.publishedEpochSeconds = publishedEpochSeconds
        self.affectedAssets = affectedAssets
        self.sentiment = sentiment
        self.polarityScore = polarityScore
        self.matchedKeywords = matchedKeywords
        self.aiImpactNote = aiImpactNote
    }
}

public struct FearGreedSnapshot: Codable, Sendable, Equatable {
    public let value: Int
    public let classification: String
    public let updatedEpochSeconds: TimeInterval
    public let source: String

    public init(value: Int, classification: String, updatedEpochSeconds: TimeInterval, source: String) {
        self.value = value
        self.classification = classification
        self.updatedEpochSeconds = updatedEpochSeconds
        self.source = source
    }
}
