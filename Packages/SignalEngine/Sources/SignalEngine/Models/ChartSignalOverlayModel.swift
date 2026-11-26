import Foundation

/// Engine-agnostic ICT structure event marker anchored to a candle UTC open timestamp
/// (so markers remain accurate across history pagination and across any chart library).
public struct StructureOverlayEvent: Codable, Sendable, Equatable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, Equatable, Hashable {
        case bos = "BOS"
        case choch = "CHoCH"
        case liquiditySweep = "SWEEP"
    }

    public let id: String
    public let kind: Kind
    public let direction: TradeDirection
    public let price: Double
    public let timestampEpochSeconds: TimeInterval
    public let label: String

    public init(
        id: String,
        kind: Kind,
        direction: TradeDirection,
        price: Double,
        timestampEpochSeconds: TimeInterval,
        label: String
    ) {
        self.id = id
        self.kind = kind
        self.direction = direction
        self.price = price
        self.timestampEpochSeconds = timestampEpochSeconds
        self.label = label
    }
}

/// Engine-agnostic behavioral trap overlay anchored to price and UTC timestamp.
public struct ChartTrapOverlay: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let direction: TrapDirection
    public let label: String
    public let price: Double
    public let extremePrice: Double
    public let timestampEpochSeconds: TimeInterval
    public let state: TrapLifecycleState

    public var isActionable: Bool {
        state == .trigger || state == .active || state == .returned
    }

    public init(
        id: String,
        direction: TrapDirection,
        label: String,
        price: Double,
        extremePrice: Double,
        timestampEpochSeconds: TimeInterval,
        state: TrapLifecycleState
    ) {
        self.id = id
        self.direction = direction
        self.label = label
        self.price = price
        self.extremePrice = extremePrice
        self.timestampEpochSeconds = timestampEpochSeconds
        self.state = state
    }

    public init(from trap: BehavioralTrap) {
        self.id = trap.id
        self.direction = trap.direction
        self.label = trap.direction.rawValue
        self.price = trap.level
        self.extremePrice = trap.extremePrice
        self.timestampEpochSeconds = trap.triggerEpochSeconds
        self.state = trap.state
    }
}

/// Clean, engine-agnostic overlay model fed by `SignalEngine` for all chart engines
/// (`LightweightChartsIOS`, `DGCharts`, `SwiftTradingView`, `CandleKit`, and native SwiftUI fallback HUD).
public struct ChartSignalOverlayModel: Codable, Sendable, Equatable, Hashable {
    public let symbol: String
    public let marketClass: MarketClass
    public let timeframe: Timeframe

    // Core trade setup levels
    public let direction: TradeDirection?
    public let entryPrice: Double?
    public let entryLow: Double?
    public let entryHigh: Double?
    public let entryTimestamp: TimeInterval?
    public let stopLoss: Double?
    public let takeProfit1: Double?
    public let takeProfit2: Double?
    public let isTP2Enabled: Bool
    public let riskRewardRatio: Double?
    public let tp2RiskRewardRatio: Double?
    public let breakevenPrice: Double?

    // Behavioral Trap price/zone & ICT structure events
    public let traps: [ChartTrapOverlay]
    public let structureEvents: [StructureOverlayEvent]
    public let zones: [PriceZoneOverlay]

    // Live reference
    public let livePrice: Double?

    public init(
        symbol: String,
        marketClass: MarketClass,
        timeframe: Timeframe,
        direction: TradeDirection? = nil,
        entryPrice: Double? = nil,
        entryLow: Double? = nil,
        entryHigh: Double? = nil,
        entryTimestamp: TimeInterval? = nil,
        stopLoss: Double? = nil,
        takeProfit1: Double? = nil,
        takeProfit2: Double? = nil,
        isTP2Enabled: Bool = false,
        riskRewardRatio: Double? = nil,
        tp2RiskRewardRatio: Double? = nil,
        breakevenPrice: Double? = nil,
        traps: [ChartTrapOverlay] = [],
        structureEvents: [StructureOverlayEvent] = [],
        zones: [PriceZoneOverlay] = [],
        livePrice: Double? = nil
    ) {
        self.symbol = symbol
        self.marketClass = marketClass
        self.timeframe = timeframe
        self.direction = direction
        self.entryPrice = Self.sanitizedPositive(entryPrice)
        self.entryLow = Self.sanitizedPositive(entryLow)
        self.entryHigh = Self.sanitizedPositive(entryHigh)
        self.entryTimestamp = Self.sanitizedTimestamp(entryTimestamp)
        self.stopLoss = Self.sanitizedPositive(stopLoss)
        self.takeProfit1 = Self.sanitizedPositive(takeProfit1)
        self.takeProfit2 = Self.sanitizedPositive(takeProfit2)
        self.isTP2Enabled = isTP2Enabled && Self.sanitizedPositive(takeProfit2) != nil
        self.riskRewardRatio = Self.sanitizedNonNegative(riskRewardRatio)
        self.tp2RiskRewardRatio = Self.sanitizedNonNegative(tp2RiskRewardRatio)
        self.breakevenPrice = Self.sanitizedPositive(breakevenPrice)
        self.traps = traps.filter { $0.price.isFinite && $0.price > 0 }
        self.structureEvents = structureEvents.filter { $0.price.isFinite && $0.price > 0 && $0.timestampEpochSeconds.isFinite && $0.timestampEpochSeconds > 0 }
        self.zones = zones.filter { $0.top.isFinite && $0.bottom.isFinite && $0.top > 0 && $0.bottom > 0 }
        self.livePrice = Self.sanitizedPositive(livePrice)
    }

    /// Most recent actionable behavioral trap (if any).
    public var primaryTrap: ChartTrapOverlay? {
        traps.last(where: \.isActionable)
    }

    public var trapPrice: Double? { primaryTrap?.price }
    public var trapLabel: String? { primaryTrap?.label }
    public var trapTimestamp: TimeInterval? { primaryTrap?.timestampEpochSeconds }

    /// Live R:R ratio recomputed safely from Entry, Stop Loss, and Take Profit 1 (returns nil on zero stop distance).
    public var computedLiveRiskReward: Double? {
        if let rr = riskRewardRatio, rr.isFinite, rr > 0 {
            return rr
        }
        guard let entry = entryPrice, let sl = stopLoss, let tp1 = takeProfit1 else { return nil }
        let risk = abs(entry - sl)
        let minRisk = max(Double.leastNormalMagnitude, entry * 1e-12)
        guard risk.isFinite, risk > minRisk else { return nil }
        let reward = abs(tp1 - entry)
        let ratio = reward / risk
        return ratio.isFinite ? ratio : nil
    }

    public var hasAnyOverlayLevels: Bool {
        entryPrice != nil || stopLoss != nil || takeProfit1 != nil || primaryTrap != nil
    }

    /// Builds a `ChartSignalOverlayModel` from raw signal/chart components.
    public static func build(
        symbol: String,
        marketClass: MarketClass,
        timeframe: Timeframe,
        direction: TradeDirection?,
        levels: TradeLevels?,
        overlays: ChartOverlayData,
        entryTimestamp: TimeInterval? = nil,
        breakevenPrice: Double? = nil,
        livePrice: Double? = nil
    ) -> ChartSignalOverlayModel {
        let trapOverlays = overlays.traps
            .filter(\.isActionable)
            .map(ChartTrapOverlay.init(from:))

        let resolvedDirection: TradeDirection? = {
            if let dir = direction, dir != .neutral { return dir }
            if let lv = levels {
                return lv.tp1 >= lv.entryMid ? .long : .short
            }
            return nil
        }()

        return ChartSignalOverlayModel(
            symbol: symbol,
            marketClass: marketClass,
            timeframe: timeframe,
            direction: resolvedDirection,
            entryPrice: levels?.entryMid,
            entryLow: levels?.entryLow,
            entryHigh: levels?.entryHigh,
            entryTimestamp: entryTimestamp,
            stopLoss: levels?.stopLoss,
            takeProfit1: levels?.tp1,
            takeProfit2: levels?.isTP2Enabled == true ? levels?.tp2 : nil,
            isTP2Enabled: levels?.isTP2Enabled ?? false,
            riskRewardRatio: levels?.riskRewardRatio,
            tp2RiskRewardRatio: levels?.tp2RiskRewardRatio,
            breakevenPrice: breakevenPrice,
            traps: trapOverlays,
            structureEvents: overlays.structureEvents,
            zones: overlays.zones,
            livePrice: livePrice
        )
    }

    /// Convenience factory directly from a `TradeSignal`.
    public static func from(
        signal: TradeSignal,
        overrideLevels: TradeLevels? = nil,
        breakevenPrice: Double? = nil,
        livePrice: Double? = nil
    ) -> ChartSignalOverlayModel {
        build(
            symbol: signal.symbol,
            marketClass: signal.marketClass,
            timeframe: signal.timeframe,
            direction: signal.direction,
            levels: overrideLevels ?? signal.levels,
            overlays: signal.overlays,
            entryTimestamp: signal.recentCandles.last?.openTimeEpochSeconds ?? signal.barCloseEpochSeconds,
            breakevenPrice: breakevenPrice,
            livePrice: livePrice
        )
    }

    private static func sanitizedPositive(_ value: Double?) -> Double? {
        guard let v = value, v.isFinite, v > 0 else { return nil }
        return v
    }

    private static func sanitizedNonNegative(_ value: Double?) -> Double? {
        guard let v = value, v.isFinite, v >= 0 else { return nil }
        return v
    }

    private static func sanitizedTimestamp(_ value: TimeInterval?) -> TimeInterval? {
        guard let v = value, v.isFinite, v > 0 else { return nil }
        return v
    }
}
