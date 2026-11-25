import Foundation

public struct Candle: Codable, Sendable, Equatable, Hashable {
    public let openTimeEpochSeconds: TimeInterval
    public let closeTimeEpochSeconds: TimeInterval
    public let open: Double
    public let high: Double
    public let low: Double
    public let close: Double
    /// Explicit nil when volume is unavailable (e.g., OTC FX/Gold). Never coerce missing volume to 0.
    public let volume: Double?
    public let isClosed: Bool

    public init(
        openTimeEpochSeconds: TimeInterval,
        closeTimeEpochSeconds: TimeInterval,
        open: Double,
        high: Double,
        low: Double,
        close: Double,
        volume: Double?,
        isClosed: Bool = true
    ) {
        self.openTimeEpochSeconds = openTimeEpochSeconds
        self.closeTimeEpochSeconds = closeTimeEpochSeconds
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.volume = volume
        self.isClosed = isClosed
    }

    public var isBullish: Bool { close >= open }
    public var isBearish: Bool { close < open }
    public var bodySize: Double { abs(close - open) }
    public var rangeSize: Double { max(high - low, 0.0) }
    public var upperWick: Double { max(high - max(open, close), 0.0) }
    public var lowerWick: Double { max(min(open, close) - low, 0.0) }
    public var midpoint: Double { (high + low) * 0.5 }
    public var openDate: Date { Date(timeIntervalSince1970: openTimeEpochSeconds) }
    public var closeDate: Date { Date(timeIntervalSince1970: closeTimeEpochSeconds) }
}

public enum HygieneRejectionReason: String, Codable, Sendable, Equatable {
    case insufficientBars
    case staleFeedDuringOpenSession
    case excessiveClockSkew
    case invalidPriceData
    case severeGapContinuity
}

public struct HygieneReport: Codable, Sendable, Equatable {
    public let originalCount: Int
    public let closedCount: Int
    public let droppedOpenBars: Int
    public let droppedMalformedBars: Int
    public let duplicateBarsRemoved: Int
    public let gapCount: Int
    public let clockSkewSeconds: TimeInterval
    public let isMarketClosed: Bool
    public let marketClosedReason: String?
    public let isStale: Bool
    public let rejectionReason: HygieneRejectionReason?
    public let lastClosedBarEpochSeconds: TimeInterval?

    public init(
        originalCount: Int,
        closedCount: Int,
        droppedOpenBars: Int,
        droppedMalformedBars: Int,
        duplicateBarsRemoved: Int,
        gapCount: Int,
        clockSkewSeconds: TimeInterval,
        isMarketClosed: Bool,
        marketClosedReason: String? = nil,
        isStale: Bool,
        rejectionReason: HygieneRejectionReason?,
        lastClosedBarEpochSeconds: TimeInterval?
    ) {
        self.originalCount = originalCount
        self.closedCount = closedCount
        self.droppedOpenBars = droppedOpenBars
        self.droppedMalformedBars = droppedMalformedBars
        self.duplicateBarsRemoved = duplicateBarsRemoved
        self.gapCount = gapCount
        self.clockSkewSeconds = clockSkewSeconds
        self.isMarketClosed = isMarketClosed
        self.marketClosedReason = marketClosedReason
        self.isStale = isStale
        self.rejectionReason = rejectionReason
        self.lastClosedBarEpochSeconds = lastClosedBarEpochSeconds
    }

    enum CodingKeys: String, CodingKey {
        case originalCount, closedCount, droppedOpenBars, droppedMalformedBars
        case duplicateBarsRemoved, gapCount, clockSkewSeconds, isMarketClosed
        case marketClosedReason, isStale, rejectionReason, lastClosedBarEpochSeconds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        originalCount = try c.decode(Int.self, forKey: .originalCount)
        closedCount = try c.decode(Int.self, forKey: .closedCount)
        droppedOpenBars = try c.decode(Int.self, forKey: .droppedOpenBars)
        droppedMalformedBars = try c.decode(Int.self, forKey: .droppedMalformedBars)
        duplicateBarsRemoved = try c.decode(Int.self, forKey: .duplicateBarsRemoved)
        gapCount = try c.decode(Int.self, forKey: .gapCount)
        clockSkewSeconds = try c.decode(TimeInterval.self, forKey: .clockSkewSeconds)
        isMarketClosed = try c.decode(Bool.self, forKey: .isMarketClosed)
        marketClosedReason = try c.decodeIfPresent(String.self, forKey: .marketClosedReason)
        isStale = try c.decode(Bool.self, forKey: .isStale)
        rejectionReason = try c.decodeIfPresent(HygieneRejectionReason.self, forKey: .rejectionReason)
        lastClosedBarEpochSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .lastClosedBarEpochSeconds)
    }

    public var isUsable: Bool {
        rejectionReason == nil && closedCount > 0
    }
}

public struct SanitizedCandleSeries: Codable, Sendable, Equatable {
    public let symbol: String
    public let marketClass: MarketClass
    public let timeframe: Timeframe
    public let providerName: String
    public let candles: [Candle]
    public let report: HygieneReport

    public init(
        symbol: String,
        marketClass: MarketClass,
        timeframe: Timeframe,
        providerName: String,
        candles: [Candle],
        report: HygieneReport
    ) {
        self.symbol = symbol
        self.marketClass = marketClass
        self.timeframe = timeframe
        self.providerName = providerName
        self.candles = candles
        self.report = report
    }
}
