import Foundation

// MARK: - Crypto Order Flow Data Models (Contract-Multiplier Invariant)

public struct OrderBookLevel: Codable, Sendable, Equatable, Hashable {
    public let price: Double
    public let quantity: Double

    public init(price: Double, quantity: Double) {
        self.price = price
        self.quantity = quantity
    }
}

public struct OrderFlowTrade: Codable, Sendable, Equatable, Hashable {
    public let price: Double
    public let quantity: Double
    /// `true` when buyer was maker (i.e. aggressive market SELL); `false` when aggressive market BUY.
    public let isBuyerMaker: Bool
    public let timestampEpochSeconds: TimeInterval

    public init(
        price: Double,
        quantity: Double,
        isBuyerMaker: Bool,
        timestampEpochSeconds: TimeInterval
    ) {
        self.price = price
        self.quantity = quantity
        self.isBuyerMaker = isBuyerMaker
        self.timestampEpochSeconds = timestampEpochSeconds
    }

    public var isAggressiveBuy: Bool { !isBuyerMaker }
}

public struct OrderFlowLiquidation: Codable, Sendable, Equatable, Hashable {
    public let price: Double
    /// Size expressed in the same quantity units as `recentTrades` on the same venue
    /// (contract-multiplier invariant across BTC/ETH/meme swaps).
    public let sizeInSameUnits: Double
    /// `true` when a long position was forcibly liquidated (forced selling); `false` for short liquidation (forced buying).
    public let isLongLiquidation: Bool
    public let timestampEpochSeconds: TimeInterval

    public init(
        price: Double,
        sizeInSameUnits: Double,
        isLongLiquidation: Bool,
        timestampEpochSeconds: TimeInterval
    ) {
        self.price = price
        self.sizeInSameUnits = sizeInSameUnits
        self.isLongLiquidation = isLongLiquidation
        self.timestampEpochSeconds = timestampEpochSeconds
    }
}

public struct OrderFlowSnapshot: Codable, Sendable, Equatable, Hashable {
    public let timestampEpochSeconds: TimeInterval
    /// Exchange venue name (`"OKX"`, `"Bybit"`, `"Binance"`).
    public let venue: String
    public let isLiveWebSocket: Bool
    public let midPrice: Double
    public let bestBid: Double
    public let bestAsk: Double
    public let spreadBps: Double
    public let bids: [OrderBookLevel]
    public let asks: [OrderBookLevel]
    public let recentTrades: [OrderFlowTrade]
    public let recentLiquidations: [OrderFlowLiquidation]
    /// Price levels observed surviving >= 6 seconds across live WebSocket updates (anti-spoofing).
    public let confirmedWallPrices: [Double]

    public init(
        timestampEpochSeconds: TimeInterval,
        venue: String,
        isLiveWebSocket: Bool,
        midPrice: Double,
        bestBid: Double,
        bestAsk: Double,
        spreadBps: Double,
        bids: [OrderBookLevel],
        asks: [OrderBookLevel],
        recentTrades: [OrderFlowTrade] = [],
        recentLiquidations: [OrderFlowLiquidation] = [],
        confirmedWallPrices: [Double] = []
    ) {
        self.timestampEpochSeconds = timestampEpochSeconds
        self.venue = venue
        self.isLiveWebSocket = isLiveWebSocket
        self.midPrice = midPrice
        self.bestBid = bestBid
        self.bestAsk = bestAsk
        self.spreadBps = spreadBps
        self.bids = bids
        self.asks = asks
        self.recentTrades = recentTrades
        self.recentLiquidations = recentLiquidations
        self.confirmedWallPrices = confirmedWallPrices
    }
}

// MARK: - Order Flow Evaluation Output Models

public enum OrderFlowDivergence: String, Codable, Sendable, Equatable, Hashable {
    case bullish = "bullish_div"
    case bearish = "bearish_div"
    case none = "none"

    public var shortTag: String? {
        switch self {
        case .bullish: return "DIV+"
        case .bearish: return "DIV-"
        case .none: return nil
        }
    }
}

public enum OrderFlowAbsorptionState: String, Codable, Sendable, Equatable, Hashable {
    case bullishAbsorption = "bullish_absorption"
    case bearishAbsorption = "bearish_absorption"
    case none = "none"

    public var shortTag: String? {
        switch self {
        case .bullishAbsorption: return "ABSORB+"
        case .bearishAbsorption: return "ABSORB-"
        case .none: return nil
        }
    }
}

public enum OrderFlowAlignment: String, Codable, Sendable, Equatable, Hashable {
    case aligned = "aligned"
    case neutral = "neutral"
    case conflicting = "conflicting"
    case unavailable = "unavailable"
}

public struct OrderFlowWallInfo: Codable, Sendable, Equatable, Hashable {
    public let price: Double
    public let distanceBps: Double
    public let sizeMultipleOfMedian: Double
    /// `true` only on live WebSocket after persisting >= 6s; `false` ("Unconfirmed") on REST snapshots.
    public let isConfirmed: Bool

    public init(
        price: Double,
        distanceBps: Double,
        sizeMultipleOfMedian: Double,
        isConfirmed: Bool
    ) {
        self.price = price
        self.distanceBps = distanceBps
        self.sizeMultipleOfMedian = sizeMultipleOfMedian
        self.isConfirmed = isConfirmed
    }
}

public struct OrderFlowAssessment: Codable, Sendable, Equatable, Hashable {
    public let timestampEpochSeconds: TimeInterval
    public let venue: String
    public let isLiveWebSocket: Bool
    public let spreadBps: Double
    public let isLowLiquidity: Bool
    public let obiAdaptiveBand: Double
    public let obiWeighted: Double
    public let micropriceBias: Double
    public let cvdRatio: Double
    public let tradeSampleCount: Int
    public let divergence: OrderFlowDivergence
    public let absorptionState: OrderFlowAbsorptionState
    public let nearestBidWall: OrderFlowWallInfo?
    public let nearestAskWall: OrderFlowWallInfo?
    public let longLiquidationRatio: Double
    public let shortLiquidationRatio: Double
    public let liquidationExhaustionDirection: TradeDirection
    /// Composite normalized score in `[-1.0, +1.0]` (`+` bullish, `-` bearish).
    public let compositeScore: Double
    public let alignment: OrderFlowAlignment
    /// `true` when a Confirmed resting wall sits strictly between Entry and TP1 in the trade's path.
    public let confirmedWallBlocksTP1: Bool
    public let summary: String
    public let warningNote: String?
    public let unavailableReason: String?

    public init(
        timestampEpochSeconds: TimeInterval,
        venue: String,
        isLiveWebSocket: Bool,
        spreadBps: Double,
        isLowLiquidity: Bool,
        obiAdaptiveBand: Double,
        obiWeighted: Double,
        micropriceBias: Double,
        cvdRatio: Double,
        tradeSampleCount: Int,
        divergence: OrderFlowDivergence,
        absorptionState: OrderFlowAbsorptionState,
        nearestBidWall: OrderFlowWallInfo?,
        nearestAskWall: OrderFlowWallInfo?,
        longLiquidationRatio: Double,
        shortLiquidationRatio: Double,
        liquidationExhaustionDirection: TradeDirection,
        compositeScore: Double,
        alignment: OrderFlowAlignment,
        confirmedWallBlocksTP1: Bool,
        summary: String,
        warningNote: String?,
        unavailableReason: String? = nil
    ) {
        self.timestampEpochSeconds = timestampEpochSeconds
        self.venue = venue
        self.isLiveWebSocket = isLiveWebSocket
        self.spreadBps = spreadBps
        self.isLowLiquidity = isLowLiquidity
        self.obiAdaptiveBand = obiAdaptiveBand
        self.obiWeighted = obiWeighted
        self.micropriceBias = micropriceBias
        self.cvdRatio = cvdRatio
        self.tradeSampleCount = tradeSampleCount
        self.divergence = divergence
        self.absorptionState = absorptionState
        self.nearestBidWall = nearestBidWall
        self.nearestAskWall = nearestAskWall
        self.longLiquidationRatio = longLiquidationRatio
        self.shortLiquidationRatio = shortLiquidationRatio
        self.liquidationExhaustionDirection = liquidationExhaustionDirection
        self.compositeScore = compositeScore
        self.alignment = alignment
        self.confirmedWallBlocksTP1 = confirmedWallBlocksTP1
        self.summary = summary
        self.warningNote = warningNote
        self.unavailableReason = unavailableReason
    }

    public var directionalBias: TradeDirection {
        guard alignment != .unavailable, !isLowLiquidity else { return .neutral }
        if compositeScore >= 0.18 { return .long }
        if compositeScore <= -0.18 { return .short }
        return .neutral
    }

    public var isStrongConflict: Bool {
        alignment == .conflicting && (
            confirmedWallBlocksTP1 ||
            divergence != .none ||
            absorptionState != .none ||
            abs(compositeScore) >= 0.40
        )
    }

    public var chartSummary: ChartOrderFlowSummary? {
        guard alignment != .unavailable else { return nil }
        return ChartOrderFlowSummary(
            obiWeighted: obiWeighted,
            cvdRatio: cvdRatio,
            divergenceTag: divergence.shortTag,
            absorptionTag: absorptionState.shortTag,
            alignment: alignment.rawValue,
            venue: venue,
            isLiveStream: isLiveWebSocket,
            bidWallPrice: nearestBidWall?.price,
            bidWallConfirmed: nearestBidWall?.isConfirmed ?? false,
            askWallPrice: nearestAskWall?.price,
            askWallConfirmed: nearestAskWall?.isConfirmed ?? false
        )
    }

    public static func unavailable(reason: String, nowEpochSeconds: TimeInterval = 0) -> OrderFlowAssessment {
        OrderFlowAssessment(
            timestampEpochSeconds: nowEpochSeconds,
            venue: "",
            isLiveWebSocket: false,
            spreadBps: 0,
            isLowLiquidity: false,
            obiAdaptiveBand: 0,
            obiWeighted: 0,
            micropriceBias: 0,
            cvdRatio: 0,
            tradeSampleCount: 0,
            divergence: .none,
            absorptionState: .none,
            nearestBidWall: nil,
            nearestAskWall: nil,
            longLiquidationRatio: 0,
            shortLiquidationRatio: 0,
            liquidationExhaustionDirection: .neutral,
            compositeScore: 0,
            alignment: .unavailable,
            confirmedWallBlocksTP1: false,
            summary: reason,
            warningNote: nil,
            unavailableReason: reason
        )
    }
}

// MARK: - Pure-Swift Contract-Multiplier-Invariant Order Flow & Absorption Analyzer

public enum OrderFlowAnalyzer {
    public static let maxSnapshotAgeSeconds: TimeInterval = 20.0
    public static let maxHealthySpreadBps: Double = 60.0
    public static let minTradesForCVDAndAbsorption: Int = 20
    public static let wallMedianMultipleThreshold: Double = 3.0

    /// Timeframe-aware base weight for Order Flow inside `ConfluenceScorer`.
    /// Stronger on execution timeframes (`15m`, `1H`), smoothly tapered on swing timeframes (`4H`, `1D`).
    public static func timeframeBaseWeight(for timeframe: Timeframe) -> Double {
        switch timeframe {
        case .m15: return 1.25
        case .h1: return 1.00
        case .h4: return 0.65
        case .d1: return 0.40
        }
    }

    /// Evaluates a live Crypto `OrderFlowSnapshot` using strictly dimensionless / contract-multiplier-invariant ratios.
    ///
    /// **Hard Anti-Repainting & Crypto-Only Guards:**
    /// - Returns `.unavailable` immediately when `isOrderFlowEnabled == false`, `marketClass != .crypto`,
    ///   `isLiveEvaluation == false` (historical backtest/replay), `snapshot == nil`, or snapshot age `> 20s`.
    public static func evaluate(
        snapshot: OrderFlowSnapshot?,
        marketClass: MarketClass,
        isOrderFlowEnabled: Bool,
        isLiveEvaluation: Bool,
        candidateDirection: TradeDirection = .neutral,
        entryPrice: Double? = nil,
        takeProfit1: Double? = nil,
        nowEpochSeconds: TimeInterval
    ) -> OrderFlowAssessment {
        guard isOrderFlowEnabled else {
            return .unavailable(reason: "Order Flow disabled", nowEpochSeconds: nowEpochSeconds)
        }
        guard marketClass == .crypto else {
            return .unavailable(reason: "Crypto-only module skipped on \(marketClass.displayName)", nowEpochSeconds: nowEpochSeconds)
        }
        guard isLiveEvaluation else {
            return .unavailable(reason: "Order Flow excluded from historical replay (anti-repainting)", nowEpochSeconds: nowEpochSeconds)
        }
        guard let snap = snapshot else {
            return .unavailable(reason: "No live crypto order flow snapshot available", nowEpochSeconds: nowEpochSeconds)
        }

        // Reject stale snapshots (> 20 seconds old) or invalid timestamps
        guard snap.timestampEpochSeconds.isFinite, nowEpochSeconds.isFinite else {
            return .unavailable(reason: "Invalid order flow timestamp", nowEpochSeconds: nowEpochSeconds)
        }
        let ageSeconds = nowEpochSeconds - snap.timestampEpochSeconds
        if ageSeconds > maxSnapshotAgeSeconds || ageSeconds < -30.0 {
            return .unavailable(reason: "Order flow snapshot stale (\(Int(max(0, ageSeconds)))s old)", nowEpochSeconds: nowEpochSeconds)
        }

        // Validate book integrity (finite positive bid/ask, non-crossed)
        let validBids = snap.bids
            .filter { $0.price.isFinite && $0.price > 0 && $0.quantity.isFinite && $0.quantity > 0 }
            .sorted { $0.price > $1.price }
        let validAsks = snap.asks
            .filter { $0.price.isFinite && $0.price > 0 && $0.quantity.isFinite && $0.quantity > 0 }
            .sorted { $0.price < $1.price }

        guard let topBid = validBids.first, let topAsk = validAsks.first else {
            return lowLiquidityAssessment(snap: snap, spreadBps: snap.spreadBps, reason: "Order book empty")
        }

        let bestBid = (snap.bestBid.isFinite && snap.bestBid > 0) ? min(snap.bestBid, topBid.price) : topBid.price
        let bestAsk = (snap.bestAsk.isFinite && snap.bestAsk > 0) ? max(snap.bestAsk, topAsk.price) : topAsk.price
        guard bestAsk > bestBid else {
            return lowLiquidityAssessment(snap: snap, spreadBps: 999.0, reason: "Crossed order book")
        }

        let mid = (snap.midPrice.isFinite && snap.midPrice > 0) ? snap.midPrice : ((bestBid + bestAsk) * 0.5)
        guard mid.isFinite, mid > 0 else {
            return lowLiquidityAssessment(snap: snap, spreadBps: 999.0, reason: "Invalid mid price")
        }

        let computedSpreadBps = ((bestAsk - bestBid) / mid) * 10_000.0
        let spreadBps = computedSpreadBps.isFinite ? max(0.0, computedSpreadBps) : 999.0

        if spreadBps > maxHealthySpreadBps {
            return lowLiquidityAssessment(
                snap: snap,
                spreadBps: spreadBps,
                reason: "Low liquidity spread (\(String(format: "%.1f", spreadBps)) bps > 60 bps)"
            )
        }

        // 1. Adaptive Distance-Weighted Order Book Imbalance (OBI) + Microprice Bias
        let bandBps = max(25.0, spreadBps * 2.5)
        var bandBidQty = 0.0
        var bandAskQty = 0.0
        var weightedBidQty = 0.0
        var weightedAskQty = 0.0

        for level in validBids {
            let distBps = max(0.0, ((bestBid - level.price) / bestBid) * 10_000.0)
            if distBps <= bandBps {
                bandBidQty += level.quantity
            }
            let weight = exp(-distBps / bandBps)
            weightedBidQty += level.quantity * weight
        }
        for level in validAsks {
            let distBps = max(0.0, ((level.price - bestAsk) / bestAsk) * 10_000.0)
            if distBps <= bandBps {
                bandAskQty += level.quantity
            }
            let weight = exp(-distBps / bandBps)
            weightedAskQty += level.quantity * weight
        }

        let obiAdaptiveBand: Double = (bandBidQty + bandAskQty) > 0
            ? clamp((bandBidQty - bandAskQty) / (bandBidQty + bandAskQty), -1.0, 1.0)
            : 0.0
        let obiWeighted: Double = (weightedBidQty + weightedAskQty) > 0
            ? clamp((weightedBidQty - weightedAskQty) / (weightedBidQty + weightedAskQty), -1.0, 1.0)
            : 0.0

        // Microprice bias normalized to [-1, +1]
        let topSum = topBid.quantity + topAsk.quantity
        let micropriceBias: Double
        if topSum > 0 {
            let microprice = (bestAsk * topBid.quantity + bestBid * topAsk.quantity) / topSum
            let halfSpread = max((bestAsk - bestBid) * 0.5, mid * 1e-6)
            micropriceBias = clamp((microprice - mid) / halfSpread, -1.0, 1.0)
        } else {
            micropriceBias = 0.0
        }

        // 2. Anti-Spoofing Resting Liquidity Walls (>= 3.0x median level size)
        let nearestBidWall = detectNearestWall(
            levels: validBids,
            referencePrice: bestBid,
            isBidSide: true,
            isLiveWebSocket: snap.isLiveWebSocket,
            confirmedPrices: snap.confirmedWallPrices
        )
        let nearestAskWall = detectNearestWall(
            levels: validAsks,
            referencePrice: bestAsk,
            isBidSide: false,
            isLiveWebSocket: snap.isLiveWebSocket,
            confirmedPrices: snap.confirmedWallPrices
        )

        // 3. Window-Guarded CVD & Price Divergence
        let validTrades = snap.recentTrades
            .filter { $0.price.isFinite && $0.price > 0 && $0.quantity.isFinite && $0.quantity > 0 && $0.timestampEpochSeconds.isFinite }
            .sorted { $0.timestampEpochSeconds < $1.timestampEpochSeconds }

        var buyVol = 0.0
        var sellVol = 0.0
        for trade in validTrades {
            if trade.isAggressiveBuy {
                buyVol += trade.quantity
            } else {
                sellVol += trade.quantity
            }
        }
        let totalTradeVol = buyVol + sellVol
        let cvdRatio: Double = totalTradeVol > 0
            ? clamp((buyVol - sellVol) / totalTradeVol, -1.0, 1.0)
            : 0.0

        let minMeaningfulMoveBps = max(5.0, spreadBps * 1.2)
        var divergence: OrderFlowDivergence = .none
        var absorptionState: OrderFlowAbsorptionState = .none

        if validTrades.count >= minTradesForCVDAndAbsorption, totalTradeVol > 0 {
            let halfIdx = validTrades.count / 2
            let firstHalf = validTrades[0..<halfIdx]
            let secondHalf = validTrades[halfIdx..<validTrades.count]

            let firstAvgPrice = firstHalf.reduce(0.0) { $0 + $1.price } / Double(max(1, firstHalf.count))
            let secondAvgPrice = secondHalf.reduce(0.0) { $0 + $1.price } / Double(max(1, secondHalf.count))
            let priceMoveBps = firstAvgPrice > 0 ? ((secondAvgPrice - firstAvgPrice) / firstAvgPrice) * 10_000.0 : 0.0

            let firstDelta = firstHalf.reduce(0.0) { $0 + ($1.isAggressiveBuy ? $1.quantity : -$1.quantity) }
            let firstVol = firstHalf.reduce(0.0) { $0 + $1.quantity }
            let secondDelta = secondHalf.reduce(0.0) { $0 + ($1.isAggressiveBuy ? $1.quantity : -$1.quantity) }
            let secondVol = secondHalf.reduce(0.0) { $0 + $1.quantity }

            let firstRatio = firstVol > 0 ? (firstDelta / firstVol) : 0.0
            let secondRatio = secondVol > 0 ? (secondDelta / secondVol) : 0.0
            let deltaShift = secondRatio - firstRatio

            // Window-guarded CVD divergence (requires meaningful price movement AND opposing CVD slope)
            if priceMoveBps <= -minMeaningfulMoveBps && (deltaShift >= 0.20 || (secondRatio >= 0.15 && cvdRatio > 0.05)) {
                divergence = .bullish
            } else if priceMoveBps >= minMeaningfulMoveBps && (deltaShift <= -0.20 || (secondRatio <= -0.15 && cvdRatio < -0.05)) {
                divergence = .bearish
            }

            // 4. Institutional Passive Absorption Detector
            // Heavy one-sided aggressive flow (|cvdRatio| >= 0.35, >= 20 trades) fails to push price through
            let firstPrice = validTrades.first?.price ?? mid
            let lastPrice = validTrades.last?.price ?? mid
            let netMoveBps = firstPrice > 0 ? ((lastPrice - firstPrice) / firstPrice) * 10_000.0 : 0.0
            let nearConfirmedBidWall = (nearestBidWall?.isConfirmed == true && (nearestBidWall?.distanceBps ?? 999) <= max(35.0, bandBps))
            let nearConfirmedAskWall = (nearestAskWall?.isConfirmed == true && (nearestAskWall?.distanceBps ?? 999) <= max(35.0, bandBps))

            let flatToleranceBps = max(4.0, spreadBps * 1.1)
            if cvdRatio <= -0.35 && (netMoveBps >= -flatToleranceBps || (nearConfirmedBidWall && netMoveBps >= -flatToleranceBps * 2.0)) {
                absorptionState = .bullishAbsorption
            } else if cvdRatio >= 0.35 && (netMoveBps <= flatToleranceBps || (nearConfirmedAskWall && netMoveBps <= flatToleranceBps * 2.0)) {
                absorptionState = .bearishAbsorption
            }
        }

        // 5. Relative Liquidation Exhaustion Spikes (dimensionless ratio to rolling trade volume in same units)
        let validLiqs = snap.recentLiquidations.filter {
            $0.price.isFinite && $0.price > 0 && $0.sizeInSameUnits.isFinite && $0.sizeInSameUnits > 0
        }
        let longLiqSize = validLiqs.filter(\.isLongLiquidation).reduce(0.0) { $0 + $1.sizeInSameUnits }
        let shortLiqSize = validLiqs.filter { !$0.isLongLiquidation }.reduce(0.0) { $0 + $1.sizeInSameUnits }
        let liqDenominator = max(totalTradeVol, (weightedBidQty + weightedAskQty) * 0.25, Double.leastNormalMagnitude)
        let longLiqRatio = min(5.0, longLiqSize / liqDenominator)
        let shortLiqRatio = min(5.0, shortLiqSize / liqDenominator)

        let liqExhaustionDir: TradeDirection
        var liqScore = 0.0
        if longLiqRatio >= 0.15 && longLiqRatio > shortLiqRatio * 1.5 {
            // Forced long flush -> selling exhaustion (contrarian bullish absorption context)
            liqExhaustionDir = .long
            liqScore = min(0.30, longLiqRatio * 0.45)
        } else if shortLiqRatio >= 0.15 && shortLiqRatio > longLiqRatio * 1.5 {
            // Forced short squeeze exhaustion -> buying exhaustion (contrarian bearish fade risk)
            liqExhaustionDir = .short
            liqScore = -min(0.30, shortLiqRatio * 0.45)
        } else {
            liqExhaustionDir = .neutral
        }

        // 6. Composite OrderFlowScore in [-1.0, +1.0]
        var rawComposite = (obiWeighted * 0.42) + (micropriceBias * 0.08)

        // CVD contributes directly when sample size is sufficient; damped on small sample
        let cvdSampleScale = min(1.0, Double(validTrades.count) / Double(minTradesForCVDAndAbsorption))
        if absorptionState == .bullishAbsorption {
            // Passive buyers absorbing aggressive selling -> flips bearish CVD into bullish signal
            rawComposite += 0.35
        } else if absorptionState == .bearishAbsorption {
            // Passive sellers absorbing aggressive buying -> flips bullish CVD into bearish signal
            rawComposite -= 0.35
        } else {
            rawComposite += cvdRatio * 0.30 * cvdSampleScale
        }

        switch divergence {
        case .bullish: rawComposite += 0.22
        case .bearish: rawComposite -= 0.22
        case .none: break
        }

        // Resting walls: confirmed WS walls carry full weight; unconfirmed REST/flash walls weighted conservatively (0.35x)
        if let bw = nearestBidWall, bw.distanceBps <= max(45.0, bandBps * 1.5) {
            let mult = bw.isConfirmed ? 1.0 : 0.35
            rawComposite += 0.14 * mult
        }
        if let aw = nearestAskWall, aw.distanceBps <= max(45.0, bandBps * 1.5) {
            let mult = aw.isConfirmed ? 1.0 : 0.35
            rawComposite -= 0.14 * mult
        }

        rawComposite += liqScore
        let compositeScore = clamp(rawComposite.isFinite ? rawComposite : 0.0, -1.0, 1.0)

        // 7. Confirmed Wall Blocking Entry -> TP1 Check
        var wallBlocksTP1 = false
        if let entry = entryPrice, let tp1 = takeProfit1, entry.isFinite, tp1.isFinite {
            if candidateDirection == .long,
               let aw = nearestAskWall,
               aw.isConfirmed,
               aw.price > entry,
               aw.price < tp1 {
                wallBlocksTP1 = true
            } else if candidateDirection == .short,
                      let bw = nearestBidWall,
                      bw.isConfirmed,
                      bw.price < entry,
                      bw.price > tp1 {
                wallBlocksTP1 = true
            }
        }

        // 8. Candidate Alignment & Warning Note
        let alignment: OrderFlowAlignment
        var warningNote: String? = nil

        switch candidateDirection {
        case .long:
            let opposingEvent = (divergence == .bearish || absorptionState == .bearishAbsorption || wallBlocksTP1)
            if opposingEvent || compositeScore <= -0.22 {
                alignment = .conflicting
                if wallBlocksTP1, let aw = nearestAskWall {
                    warningNote = "Confirmed Ask Wall blocks TP1 near \(ChartPricePrecision.resolve(symbol: "", referencePrice: aw.price).format(aw.price))"
                } else if absorptionState == .bearishAbsorption {
                    warningNote = "Bearish institutional absorption detected against Long setup"
                } else if divergence == .bearish {
                    warningNote = "Bearish CVD divergence conflicts with Long setup"
                } else {
                    warningNote = "Crypto Order Flow leans bearish (\(String(format: "%+.2f", compositeScore))) against Long"
                }
            } else if compositeScore >= 0.18 || absorptionState == .bullishAbsorption || divergence == .bullish {
                alignment = .aligned
            } else {
                alignment = .neutral
            }
        case .short:
            let opposingEvent = (divergence == .bullish || absorptionState == .bullishAbsorption || wallBlocksTP1)
            if opposingEvent || compositeScore >= 0.22 {
                alignment = .conflicting
                if wallBlocksTP1, let bw = nearestBidWall {
                    warningNote = "Confirmed Bid Wall blocks TP1 near \(ChartPricePrecision.resolve(symbol: "", referencePrice: bw.price).format(bw.price))"
                } else if absorptionState == .bullishAbsorption {
                    warningNote = "Bullish institutional absorption detected against Short setup"
                } else if divergence == .bullish {
                    warningNote = "Bullish CVD divergence conflicts with Short setup"
                } else {
                    warningNote = "Crypto Order Flow leans bullish (\(String(format: "%+.2f", compositeScore))) against Short"
                }
            } else if compositeScore <= -0.18 || absorptionState == .bearishAbsorption || divergence == .bearish {
                alignment = .aligned
            } else {
                alignment = .neutral
            }
        case .neutral:
            alignment = .neutral
        }

        var parts: [String] = [
            "\(snap.venue)\(snap.isLiveWebSocket ? " Live" : " REST")",
            String(format: "OBI %+.0f%%", obiWeighted * 100.0),
            String(format: "CVD %+.0f%%", cvdRatio * 100.0)
        ]
        if let absTag = absorptionState.shortTag { parts.append(absTag) }
        if let divTag = divergence.shortTag { parts.append(divTag) }
        if wallBlocksTP1 { parts.append("Wall Blocks TP1") }

        return OrderFlowAssessment(
            timestampEpochSeconds: snap.timestampEpochSeconds,
            venue: snap.venue,
            isLiveWebSocket: snap.isLiveWebSocket,
            spreadBps: spreadBps,
            isLowLiquidity: false,
            obiAdaptiveBand: obiAdaptiveBand,
            obiWeighted: obiWeighted,
            micropriceBias: micropriceBias,
            cvdRatio: cvdRatio,
            tradeSampleCount: validTrades.count,
            divergence: divergence,
            absorptionState: absorptionState,
            nearestBidWall: nearestBidWall,
            nearestAskWall: nearestAskWall,
            longLiquidationRatio: longLiqRatio,
            shortLiquidationRatio: shortLiqRatio,
            liquidationExhaustionDirection: liqExhaustionDir,
            compositeScore: compositeScore,
            alignment: alignment,
            confirmedWallBlocksTP1: wallBlocksTP1,
            summary: parts.joined(separator: " · "),
            warningNote: warningNote,
            unavailableReason: nil
        )
    }

    // MARK: - Private Helpers

    private static func lowLiquidityAssessment(
        snap: OrderFlowSnapshot,
        spreadBps: Double,
        reason: String
    ) -> OrderFlowAssessment {
        OrderFlowAssessment(
            timestampEpochSeconds: snap.timestampEpochSeconds,
            venue: snap.venue,
            isLiveWebSocket: snap.isLiveWebSocket,
            spreadBps: spreadBps.isFinite ? spreadBps : 999.0,
            isLowLiquidity: true,
            obiAdaptiveBand: 0,
            obiWeighted: 0,
            micropriceBias: 0,
            cvdRatio: 0,
            tradeSampleCount: snap.recentTrades.count,
            divergence: .none,
            absorptionState: .none,
            nearestBidWall: nil,
            nearestAskWall: nil,
            longLiquidationRatio: 0,
            shortLiquidationRatio: 0,
            liquidationExhaustionDirection: .neutral,
            compositeScore: 0,
            alignment: .unavailable,
            confirmedWallBlocksTP1: false,
            summary: reason,
            warningNote: nil,
            unavailableReason: reason
        )
    }

    private static func detectNearestWall(
        levels: [OrderBookLevel],
        referencePrice: Double,
        isBidSide: Bool,
        isLiveWebSocket: Bool,
        confirmedPrices: [Double]
    ) -> OrderFlowWallInfo? {
        guard levels.count >= 3, referencePrice > 0 else { return nil }
        let sortedSizes = levels.map(\.quantity).sorted()
        let midIdx = sortedSizes.count / 2
        let median: Double
        if sortedSizes.count % 2 == 0 {
            median = (sortedSizes[midIdx - 1] + sortedSizes[midIdx]) * 0.5
        } else {
            median = sortedSizes[midIdx]
        }
        guard median.isFinite, median > 0 else { return nil }

        let threshold = median * wallMedianMultipleThreshold
        for level in levels {
            guard level.quantity >= threshold else { continue }
            let distBps: Double
            if isBidSide {
                distBps = max(0.0, ((referencePrice - level.price) / referencePrice) * 10_000.0)
            } else {
                distBps = max(0.0, ((level.price - referencePrice) / referencePrice) * 10_000.0)
            }
            let tol = max(level.price * 0.0005, 1e-8)
            let isConfirmed = isLiveWebSocket && confirmedPrices.contains { abs($0 - level.price) <= tol }
            return OrderFlowWallInfo(
                price: level.price,
                distanceBps: distBps,
                sizeMultipleOfMedian: level.quantity / median,
                isConfirmed: isConfirmed
            )
        }
        return nil
    }

    private static func clamp(_ value: Double, _ lo: Double, _ hi: Double) -> Double {
        guard value.isFinite else { return 0.0 }
        return min(hi, max(lo, value))
    }
}
