import Foundation

public struct SwingPivot: Codable, Sendable, Equatable, Hashable {
    public let index: Int
    /// First bar index where this pivot is causally known (index + wingLength).
    public let confirmedAtIndex: Int
    public let price: Double
    public let isHigh: Bool

    public init(index: Int, confirmedAtIndex: Int, price: Double, isHigh: Bool) {
        self.index = index
        self.confirmedAtIndex = confirmedAtIndex
        self.price = price
        self.isHigh = isHigh
    }
}

public struct FairValueGap: Codable, Sendable, Equatable, Hashable {
    public let direction: TradeDirection
    public let top: Double
    public let bottom: Double
    /// Bar index of the 3rd candle completing the gap (causally observable at this index).
    public let formedAtIndex: Int
    public let mitigatedAtIndex: Int?

    public init(direction: TradeDirection, top: Double, bottom: Double, formedAtIndex: Int, mitigatedAtIndex: Int?) {
        self.direction = direction
        self.top = top
        self.bottom = bottom
        self.formedAtIndex = formedAtIndex
        self.mitigatedAtIndex = mitigatedAtIndex
    }

    public var isUnmitigated: Bool { mitigatedAtIndex == nil }
    public var midpoint: Double { (top + bottom) * 0.5 }
}

public enum StructureBreakKind: String, Codable, Sendable, Equatable {
    case bos = "BOS"
    case mss = "MSS/CHoCH"
}

public struct StructureBreak: Codable, Sendable, Equatable, Hashable {
    public let kind: StructureBreakKind
    public let direction: TradeDirection
    public let brokenLevel: Double
    public let breakBarIndex: Int
    public let brokenSwingIndex: Int

    public init(
        kind: StructureBreakKind,
        direction: TradeDirection,
        brokenLevel: Double,
        breakBarIndex: Int,
        brokenSwingIndex: Int
    ) {
        self.kind = kind
        self.direction = direction
        self.brokenLevel = brokenLevel
        self.breakBarIndex = breakBarIndex
        self.brokenSwingIndex = brokenSwingIndex
    }
}

public struct OrderBlock: Codable, Sendable, Equatable, Hashable {
    public let direction: TradeDirection
    public let top: Double
    public let bottom: Double
    public let originBarIndex: Int
    /// Causally valid only starting from the BOS/MSS break candle index.
    public let validFromIndex: Int
    public let mitigatedAtIndex: Int?
    /// Nil when OTC volume is unavailable.
    public let relativeVolume: Double?

    public init(
        direction: TradeDirection,
        top: Double,
        bottom: Double,
        originBarIndex: Int,
        validFromIndex: Int,
        mitigatedAtIndex: Int?,
        relativeVolume: Double?
    ) {
        self.direction = direction
        self.top = top
        self.bottom = bottom
        self.originBarIndex = originBarIndex
        self.validFromIndex = validFromIndex
        self.mitigatedAtIndex = mitigatedAtIndex
        self.relativeVolume = relativeVolume
    }

    public var isUnmitigated: Bool { mitigatedAtIndex == nil }
}

public struct LiquiditySweep: Codable, Sendable, Equatable, Hashable {
    /// Trade direction AFTER the sweep (swept low -> long; swept high -> short).
    public let reversalDirection: TradeDirection
    public let sweptLevel: Double
    public let sweepBarIndex: Int
    public let extremePrice: Double
    public let pierceDepth: Double

    public init(
        reversalDirection: TradeDirection,
        sweptLevel: Double,
        sweepBarIndex: Int,
        extremePrice: Double,
        pierceDepth: Double
    ) {
        self.reversalDirection = reversalDirection
        self.sweptLevel = sweptLevel
        self.sweepBarIndex = sweepBarIndex
        self.extremePrice = extremePrice
        self.pierceDepth = pierceDepth
    }
}

public enum DealingRangeZone: String, Codable, Sendable, Equatable {
    case discount
    case equilibrium
    case premium
}

public struct ICTAnalysis: Codable, Sendable, Equatable {
    public let swings: [SwingPivot]
    public let structureBreaks: [StructureBreak]
    public let fvgs: [FairValueGap]
    public let orderBlocks: [OrderBlock]
    public let liquiditySweeps: [LiquiditySweep]
    public let currentStructureBias: TradeDirection
    public let equilibriumPrice: Double?
    public let dealingRangeHigh: Double?
    public let dealingRangeLow: Double?
    public let dealingZone: DealingRangeZone?
    public let contributions: [StrategyContribution]

    public init(
        swings: [SwingPivot],
        structureBreaks: [StructureBreak],
        fvgs: [FairValueGap],
        orderBlocks: [OrderBlock],
        liquiditySweeps: [LiquiditySweep],
        currentStructureBias: TradeDirection,
        equilibriumPrice: Double?,
        dealingRangeHigh: Double?,
        dealingRangeLow: Double?,
        dealingZone: DealingRangeZone?,
        contributions: [StrategyContribution]
    ) {
        self.swings = swings
        self.structureBreaks = structureBreaks
        self.fvgs = fvgs
        self.orderBlocks = orderBlocks
        self.liquiditySweeps = liquiditySweeps
        self.currentStructureBias = currentStructureBias
        self.equilibriumPrice = equilibriumPrice
        self.dealingRangeHigh = dealingRangeHigh
        self.dealingRangeLow = dealingRangeLow
        self.dealingZone = dealingZone
        self.contributions = contributions
    }
}

public enum CausalICTDetector {
    /// Strictly causal ICT/SMC analysis evaluated exclusively over `candles[0...endIndex]`.
    /// Zero future leakage: pivots at `p` are only confirmed at `p + swingWing`, FVGs at bar `t`,
    /// BOS/MSS on closed break bar `t`, and Order Blocks from `validFromIndex = breakBarIndex`.
    public static func analyze(
        candles: [Candle],
        upTo endIndex: Int? = nil,
        swingWing: Int = 3,
        weights: [String: Double] = [:]
    ) -> ICTAnalysis {
        let lastIdx = min(endIndex ?? (candles.count - 1), candles.count - 1)
        guard lastIdx >= max(swingWing * 2 + 2, 10) else {
            return ICTAnalysis(
                swings: [],
                structureBreaks: [],
                fvgs: [],
                orderBlocks: [],
                liquiditySweeps: [],
                currentStructureBias: .neutral,
                equilibriumPrice: nil,
                dealingRangeHigh: nil,
                dealingRangeLow: nil,
                dealingZone: nil,
                contributions: []
            )
        }

        // 1. Causal Swing Highs & Lows (confirmed strictly at p + swingWing <= lastIdx)
        var swings: [SwingPivot] = []
        let maxPivotIdx = lastIdx - swingWing
        if maxPivotIdx >= swingWing {
            for p in swingWing...maxPivotIdx {
                let candidateHigh = candles[p].high
                let candidateLow = candles[p].low
                var isHigh = true
                var isLow = true
                for k in (p - swingWing)...(p + swingWing) where k != p {
                    if candles[k].high >= candidateHigh { isHigh = false }
                    if candles[k].low <= candidateLow { isLow = false }
                    if !isHigh && !isLow { break }
                }
                let confirmedAt = p + swingWing
                if isHigh {
                    swings.append(SwingPivot(index: p, confirmedAtIndex: confirmedAt, price: candidateHigh, isHigh: true))
                }
                if isLow {
                    swings.append(SwingPivot(index: p, confirmedAtIndex: confirmedAt, price: candidateLow, isHigh: false))
                }
            }
        }

        // 2. Causal Fair Value Gaps (3-bar pattern completed at bar i)
        var fvgs: [FairValueGap] = []
        for i in 2...lastIdx {
            let c0 = candles[i - 2]
            let c1 = candles[i - 1]
            let c2 = candles[i]
            if c0.high < c2.low && c1.isBullish {
                let top = c2.low
                let bottom = c0.high
                var mitigated: Int? = nil
                if i + 1 <= lastIdx {
                    for j in (i + 1)...lastIdx {
                        if candles[j].low <= top {
                            mitigated = j
                            break
                        }
                    }
                }
                fvgs.append(FairValueGap(direction: .long, top: top, bottom: bottom, formedAtIndex: i, mitigatedAtIndex: mitigated))
            } else if c0.low > c2.high && c1.isBearish {
                let top = c0.low
                let bottom = c2.high
                var mitigated: Int? = nil
                if i + 1 <= lastIdx {
                    for j in (i + 1)...lastIdx {
                        if candles[j].high >= bottom {
                            mitigated = j
                            break
                        }
                    }
                }
                fvgs.append(FairValueGap(direction: .short, top: top, bottom: bottom, formedAtIndex: i, mitigatedAtIndex: mitigated))
            }
        }

        // 3. Causal BOS / MSS, Order Blocks, and Liquidity Sweeps (step bar-by-bar using ONLY already-confirmed swings)
        var structureBreaks: [StructureBreak] = []
        var orderBlocks: [OrderBlock] = []
        var sweeps: [LiquiditySweep] = []
        var trendBias: TradeDirection = .neutral
        var activeHigh: SwingPivot?
        var activeLow: SwingPivot?
        var brokenSwingIndices = Set<Int>()
        var swingCursor = 0

        for i in 0...lastIdx {
            while swingCursor < swings.count && swings[swingCursor].confirmedAtIndex <= i {
                let piv = swings[swingCursor]
                if piv.isHigh { activeHigh = piv } else { activeLow = piv }
                swingCursor += 1
            }

            let bar = candles[i]

            // Check Liquidity Sweep of active swing high (wick above, close below)
            if let sh = activeHigh, sh.confirmedAtIndex < i {
                if bar.high > sh.price && bar.close < sh.price {
                    sweeps.append(
                        LiquiditySweep(
                            reversalDirection: .short,
                            sweptLevel: sh.price,
                            sweepBarIndex: i,
                            extremePrice: bar.high,
                            pierceDepth: bar.high - sh.price
                        )
                    )
                }
                // Check closed-candle bullish BOS / MSS
                if bar.close > sh.price && !brokenSwingIndices.contains(sh.index) {
                    brokenSwingIndices.insert(sh.index)
                    let kind: StructureBreakKind = (trendBias == .short) ? .mss : .bos
                    structureBreaks.append(
                        StructureBreak(kind: kind, direction: .long, brokenLevel: sh.price, breakBarIndex: i, brokenSwingIndex: sh.index)
                    )
                    trendBias = .long

                    // Locate causal bullish Order Block: last bearish candle between sh.index and i-1
                    if let ob = findOrderBlock(candles: candles, direction: .long, searchStart: max(sh.index, i - 10), breakIndex: i, endIndex: lastIdx) {
                        orderBlocks.append(ob)
                    }
                }
            }

            // Check Liquidity Sweep of active swing low (wick below, close above)
            if let sl = activeLow, sl.confirmedAtIndex < i {
                if bar.low < sl.price && bar.close > sl.price {
                    sweeps.append(
                        LiquiditySweep(
                            reversalDirection: .long,
                            sweptLevel: sl.price,
                            sweepBarIndex: i,
                            extremePrice: bar.low,
                            pierceDepth: sl.price - bar.low
                        )
                    )
                }
                // Check closed-candle bearish BOS / MSS
                if bar.close < sl.price && !brokenSwingIndices.contains(sl.index) {
                    brokenSwingIndices.insert(sl.index)
                    let kind: StructureBreakKind = (trendBias == .long) ? .mss : .bos
                    structureBreaks.append(
                        StructureBreak(kind: kind, direction: .short, brokenLevel: sl.price, breakBarIndex: i, brokenSwingIndex: sl.index)
                    )
                    trendBias = .short

                    if let ob = findOrderBlock(candles: candles, direction: .short, searchStart: max(sl.index, i - 10), breakIndex: i, endIndex: lastIdx) {
                        orderBlocks.append(ob)
                    }
                }
            }
        }

        // 4. Premium / Discount 50% Equilibrium from latest confirmed swing high & low
        let latestHigh = swings.last(where: { $0.isHigh })
        let latestLow = swings.last(where: { !$0.isHigh })
        var eqPrice: Double? = nil
        var drHigh: Double? = nil
        var drLow: Double? = nil
        var dealingZone: DealingRangeZone? = nil

        if let h = latestHigh?.price, let l = latestLow?.price, h > l {
            drHigh = h
            drLow = l
            let eq = (h + l) * 0.5
            eqPrice = eq
            let lastClose = candles[lastIdx].close
            let band = (h - l) * 0.04
            if lastClose < eq - band {
                dealingZone = .discount
            } else if lastClose > eq + band {
                dealingZone = .premium
            } else {
                dealingZone = .equilibrium
            }
        }

        // 5. Build causal StrategyContributions for the current closed bar `lastIdx`
        var contributions: [StrategyContribution] = []
        let lastBar = candles[lastIdx]

        // Recent BOS / MSS within last 6 bars
        if let recentBreak = structureBreaks.last, lastIdx - recentBreak.breakBarIndex <= 6 {
            let id = recentBreak.kind == .mss ? "ict_mss" : "ict_bos"
            contributions.append(
                StrategyContribution(
                    id: id,
                    name: "ICT \(recentBreak.kind.rawValue)",
                    group: .ictSmc,
                    direction: recentBreak.direction,
                    weight: weights[id] ?? (recentBreak.kind == .mss ? 1.20 : 1.05),
                    historicalWinRate: 0.58,
                    detail: "\(recentBreak.kind.rawValue) \(recentBreak.direction.rawValue.uppercased()) closed past swing level \(String(format: "%.4f", recentBreak.brokenLevel))."
                )
            )
        }

        // Recent Liquidity Sweep within last 3 bars
        if let recentSweep = sweeps.last, lastIdx - recentSweep.sweepBarIndex <= 3 {
            let id = "ict_liquidity_sweep"
            contributions.append(
                StrategyContribution(
                    id: id,
                    name: "Liquidity Sweep",
                    group: .ictSmc,
                    direction: recentSweep.reversalDirection,
                    weight: weights[id] ?? 1.25,
                    historicalWinRate: 0.61,
                    detail: "Swept liquidity at \(String(format: "%.4f", recentSweep.sweptLevel)) and reclaimed inside range."
                )
            )
        }

        // Active unmitigated FVG or fresh FVG retest within 12 bars
        let recentUnmitigatedFVG = fvgs.reversed().first { fvg in
            let age = lastIdx - fvg.formedAtIndex
            guard age >= 0 && age <= 18 else { return false }
            if fvg.isUnmitigated { return true }
            if let mit = fvg.mitigatedAtIndex, lastIdx - mit <= 2 {
                // Just mitigated and rejecting in FVG direction
                return (fvg.direction == .long && lastBar.close >= fvg.bottom) ||
                       (fvg.direction == .short && lastBar.close <= fvg.top)
            }
            return false
        }
        if let fvg = recentUnmitigatedFVG {
            let id = "ict_fvg"
            contributions.append(
                StrategyContribution(
                    id: id,
                    name: fvg.direction == .long ? "Bullish FVG" : "Bearish FVG",
                    group: .ictSmc,
                    direction: fvg.direction,
                    weight: weights[id] ?? 1.0,
                    historicalWinRate: 0.57,
                    detail: "Active \(fvg.direction.rawValue) Fair Value Gap [\(String(format: "%.4f", fvg.bottom)) - \(String(format: "%.4f", fvg.top))]."
                )
            )
        }

        // Unmitigated or freshly tapped Order Block
        let recentOB = orderBlocks.reversed().first { ob in
            guard lastIdx - ob.validFromIndex <= 25 else { return false }
            let nearZone: Bool
            if ob.direction == .long {
                nearZone = lastBar.low <= ob.top * 1.004 && lastBar.close >= ob.bottom
            } else {
                nearZone = lastBar.high >= ob.bottom * 0.996 && lastBar.close <= ob.top
            }
            return ob.isUnmitigated || nearZone
        }
        if let ob = recentOB {
            let id = "ict_order_block"
            contributions.append(
                StrategyContribution(
                    id: id,
                    name: ob.direction == .long ? "Bullish Order Block" : "Bearish Order Block",
                    group: .ictSmc,
                    direction: ob.direction,
                    weight: weights[id] ?? 1.10,
                    historicalWinRate: 0.59,
                    detail: "Institutional \(ob.direction.rawValue) OB [\(String(format: "%.4f", ob.bottom)) - \(String(format: "%.4f", ob.top))]."
                )
            )
        }

        // Premium / Discount Equilibrium alignment with structure bias
        if let zone = dealingZone, let eq = eqPrice {
            if zone == .discount {
                let id = "ict_discount_eq"
                contributions.append(
                    StrategyContribution(
                        id: id,
                        name: "Discount (<50% EQ)",
                        group: .ictSmc,
                        direction: .long,
                        weight: weights[id] ?? 0.85,
                        historicalWinRate: 0.55,
                        detail: "Price trading in discount below 50% equilibrium (\(String(format: "%.4f", eq)))."
                    )
                )
            } else if zone == .premium {
                let id = "ict_premium_eq"
                contributions.append(
                    StrategyContribution(
                        id: id,
                        name: "Premium (>50% EQ)",
                        group: .ictSmc,
                        direction: .short,
                        weight: weights[id] ?? 0.85,
                        historicalWinRate: 0.55,
                        detail: "Price trading in premium above 50% equilibrium (\(String(format: "%.4f", eq)))."
                    )
                )
            }
        }

        return ICTAnalysis(
            swings: swings,
            structureBreaks: structureBreaks,
            fvgs: fvgs,
            orderBlocks: orderBlocks,
            liquiditySweeps: sweeps,
            currentStructureBias: trendBias,
            equilibriumPrice: eqPrice,
            dealingRangeHigh: drHigh,
            dealingRangeLow: drLow,
            dealingZone: dealingZone,
            contributions: contributions
        )
    }

    private static func findOrderBlock(
        candles: [Candle],
        direction: TradeDirection,
        searchStart: Int,
        breakIndex: Int,
        endIndex: Int
    ) -> OrderBlock? {
        guard breakIndex > 1, searchStart < breakIndex else { return nil }
        var originIdx: Int? = nil
        for idx in stride(from: breakIndex - 1, through: max(0, searchStart), by: -1) {
            if direction == .long && candles[idx].isBearish {
                originIdx = idx
                break
            }
            if direction == .short && candles[idx].isBullish {
                originIdx = idx
                break
            }
        }
        guard let origin = originIdx else { return nil }
        let obBar = candles[origin]

        // Check mitigation strictly AFTER breakIndex up to endIndex
        var mitigated: Int? = nil
        if breakIndex + 1 <= endIndex {
            for j in (breakIndex + 1)...endIndex {
                if direction == .long && candles[j].close < obBar.low {
                    mitigated = j
                    break
                }
                if direction == .short && candles[j].close > obBar.high {
                    mitigated = j
                    break
                }
            }
        }

        // Optional relative volume (nil if OTC volume unavailable)
        let rvol: Double?
        if let v = obBar.volume {
            let lookbackStart = max(0, origin - 20)
            let vols = candles[lookbackStart..<origin].compactMap(\.volume)
            if !vols.isEmpty {
                let avg = vols.reduce(0, +) / Double(vols.count)
                rvol = avg > 0 ? v / avg : nil
            } else {
                rvol = nil
            }
        } else {
            rvol = nil
        }

        return OrderBlock(
            direction: direction,
            top: obBar.high,
            bottom: obBar.low,
            originBarIndex: origin,
            validFromIndex: breakIndex,
            mitigatedAtIndex: mitigated,
            relativeVolume: rvol
        )
    }
}
