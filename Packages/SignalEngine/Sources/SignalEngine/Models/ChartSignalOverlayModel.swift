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

/// Compact Crypto-Only live Order Flow summary attached to `ChartSignalOverlayModel`
/// for rendering the non-blocking Bid/Ask Pressure Bar, venue badge, absorption/divergence tags,
/// and optional confirmed resting liquidity walls on all chart engines.
public struct ChartOrderFlowSummary: Codable, Sendable, Equatable, Hashable {
    public let obiWeighted: Double
    public let cvdRatio: Double
    public let divergenceTag: String?
    public let absorptionTag: String?
    public let alignment: String
    public let venue: String
    public let isLiveStream: Bool
    public let bidWallPrice: Double?
    public let bidWallConfirmed: Bool
    public let askWallPrice: Double?
    public let askWallConfirmed: Bool

    public init(
        obiWeighted: Double,
        cvdRatio: Double,
        divergenceTag: String? = nil,
        absorptionTag: String? = nil,
        alignment: String = "neutral",
        venue: String,
        isLiveStream: Bool,
        bidWallPrice: Double? = nil,
        bidWallConfirmed: Bool = false,
        askWallPrice: Double? = nil,
        askWallConfirmed: Bool = false
    ) {
        self.obiWeighted = obiWeighted.isFinite ? min(1.0, max(-1.0, obiWeighted)) : 0.0
        self.cvdRatio = cvdRatio.isFinite ? min(1.0, max(-1.0, cvdRatio)) : 0.0
        self.divergenceTag = divergenceTag
        self.absorptionTag = absorptionTag
        self.alignment = alignment
        self.venue = venue
        self.isLiveStream = isLiveStream
        self.bidWallPrice = (bidWallPrice != nil && bidWallPrice!.isFinite && bidWallPrice! > 0) ? bidWallPrice : nil
        self.bidWallConfirmed = bidWallConfirmed
        self.askWallPrice = (askWallPrice != nil && askWallPrice!.isFinite && askWallPrice! > 0) ? askWallPrice : nil
        self.askWallConfirmed = askWallConfirmed
    }

    /// Fraction in `[0.0, 1.0]` representing Bid share of the pressure bar (`0.5` = balanced).
    public var bidPressureFraction: Double {
        min(0.95, max(0.05, (obiWeighted + 1.0) * 0.5))
    }
}

/// Clean, engine-agnostic overlay model fed by `SignalEngine` for all chart engines
/// (`LightweightChartsIOS`, `DGCharts`, `SwiftTradingView`, `CandleKit`, `TradingViewWeb`, and native SwiftUI fallback HUD).
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

    // Optional Crypto-Only Order Flow summary (always nil on Forex/TradFi or when OFF)
    public let orderFlowSummary: ChartOrderFlowSummary?

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
        livePrice: Double? = nil,
        orderFlowSummary: ChartOrderFlowSummary? = nil
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
        self.orderFlowSummary = (marketClass == .crypto) ? orderFlowSummary : nil
    }

    enum CodingKeys: String, CodingKey {
        case symbol, marketClass, timeframe, direction
        case entryPrice, entryLow, entryHigh, entryTimestamp
        case stopLoss, takeProfit1, takeProfit2, isTP2Enabled
        case riskRewardRatio, tp2RiskRewardRatio, breakevenPrice
        case traps, structureEvents, zones, livePrice, orderFlowSummary
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let sym = try c.decode(String.self, forKey: .symbol)
        let mc = try c.decode(MarketClass.self, forKey: .marketClass)
        let tf = try c.decode(Timeframe.self, forKey: .timeframe)
        self.init(
            symbol: sym,
            marketClass: mc,
            timeframe: tf,
            direction: try c.decodeIfPresent(TradeDirection.self, forKey: .direction),
            entryPrice: try c.decodeIfPresent(Double.self, forKey: .entryPrice),
            entryLow: try c.decodeIfPresent(Double.self, forKey: .entryLow),
            entryHigh: try c.decodeIfPresent(Double.self, forKey: .entryHigh),
            entryTimestamp: try c.decodeIfPresent(TimeInterval.self, forKey: .entryTimestamp),
            stopLoss: try c.decodeIfPresent(Double.self, forKey: .stopLoss),
            takeProfit1: try c.decodeIfPresent(Double.self, forKey: .takeProfit1),
            takeProfit2: try c.decodeIfPresent(Double.self, forKey: .takeProfit2),
            isTP2Enabled: (try? c.decodeIfPresent(Bool.self, forKey: .isTP2Enabled)) ?? false,
            riskRewardRatio: try c.decodeIfPresent(Double.self, forKey: .riskRewardRatio),
            tp2RiskRewardRatio: try c.decodeIfPresent(Double.self, forKey: .tp2RiskRewardRatio),
            breakevenPrice: try c.decodeIfPresent(Double.self, forKey: .breakevenPrice),
            traps: (try? c.decodeIfPresent([ChartTrapOverlay].self, forKey: .traps)) ?? [],
            structureEvents: (try? c.decodeIfPresent([StructureOverlayEvent].self, forKey: .structureEvents)) ?? [],
            zones: (try? c.decodeIfPresent([PriceZoneOverlay].self, forKey: .zones)) ?? [],
            livePrice: try c.decodeIfPresent(Double.self, forKey: .livePrice),
            orderFlowSummary: try c.decodeIfPresent(ChartOrderFlowSummary.self, forKey: .orderFlowSummary)
        )
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
        entryPrice != nil || stopLoss != nil || takeProfit1 != nil || primaryTrap != nil || orderFlowSummary != nil
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
        livePrice: Double? = nil,
        orderFlowSummary: ChartOrderFlowSummary? = nil
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
            livePrice: livePrice,
            orderFlowSummary: orderFlowSummary
        )
    }

    /// Convenience factory directly from a `TradeSignal`.
    public static func from(
        signal: TradeSignal,
        overrideLevels: TradeLevels? = nil,
        breakevenPrice: Double? = nil,
        livePrice: Double? = nil,
        orderFlowSummary: ChartOrderFlowSummary? = nil
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
            livePrice: livePrice,
            orderFlowSummary: orderFlowSummary ?? signal.orderFlowSummary
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
