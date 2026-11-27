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

    public init(
        direction: TradeDirection,
        top: Double,
        bottom: Double,
        originBarIndex: Int,
        validFromIndex: Int,
        mitigatedAtIndex: Int?
    ) {
        self.direction = direction
        self.top = top
        self.bottom = bottom
        self.originBarIndex = originBarIndex
        self.validFromIndex = validFromIndex
        self.mitigatedAtIndex = mitigatedAtIndex
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
        weights: [String: Double] = [:],
        enabled: Set<StrategyID> = StrategyID.allSet
    ) -> ICTAnalysis {
        // NOTE: structural primitives (swings, FVG/OB zones, sweeps, EQ) are always computed because
        // Stop loss / Target anchoring, trap detection and chart overlays depend on them. Only the
        // scored StrategyContributions below are hard-gated per `StrategyID`.
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
        var brokenHighSwingIndices = Set<Int>()
        var brokenLowSwingIndices = Set<Int>()
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
                if bar.close > sh.price && !brokenHighSwingIndices.contains(sh.index) {
                    brokenHighSwingIndices.insert(sh.index)
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
                if bar.close < sl.price && !brokenLowSwingIndices.contains(sl.index) {
                    brokenLowSwingIndices.insert(sl.index)
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
        let priceFmt = ChartPricePrecision.resolve(symbol: "", referencePrice: lastBar.close)

        // Causal 14-bar ATR computed strictly over 0...lastIdx (preserves exact prefix invariance)
        let atrLookback = min(14, lastIdx + 1)
        var trSum = 0.0
        for idx in (lastIdx - atrLookback + 1)...lastIdx {
            let c = candles[idx]
            if idx == 0 {
                trSum += c.rangeSize
            } else {
                let pc = candles[idx - 1].close
                trSum += max(c.high - c.low, max(abs(c.high - pc), abs(c.low - pc)))
            }
        }
        let causalATR = max(trSum / Double(max(atrLookback, 1)), lastBar.close * 0.0005)
        let proximityLimit = causalATR * 1.25

        // Recent BOS / MSS within last 6 bars
        let freshStructureBreak: StructureBreak?
        if let recentBreak = structureBreaks.last, lastIdx - recentBreak.breakBarIndex <= 6 {
            freshStructureBreak = recentBreak
            let id = recentBreak.kind == .mss ? "ict_mss" : "ict_bos"
            if enabled.contains(recentBreak.kind == .mss ? .ictMss : .ictBos) {
            contributions.append(
                StrategyContribution(
                    id: id,
                    name: "ICT \(recentBreak.kind.rawValue)",
                    group: .ictSmc,
                    direction: recentBreak.direction,
                    weight: weights[id] ?? ConfluenceScorer.defaultBaseWeight(for: recentBreak.kind == .mss ? .ictMss : .ictBos),
                    historicalWinRate: 0.58,
                    detail: "\(recentBreak.kind.rawValue) \(recentBreak.direction.rawValue.uppercased()) closed past swing level \(priceFmt.format(recentBreak.brokenLevel))."
                )
            )
            }
        } else {
            freshStructureBreak = nil
        }

        // Recent Liquidity Sweep within last 3 bars
        let freshSweep: LiquiditySweep?
        if let recentSweep = sweeps.last, lastIdx - recentSweep.sweepBarIndex <= 3 {
            freshSweep = recentSweep
            let id = "ict_liquidity_sweep"
            if enabled.contains(.ictLiquiditySweep) {
            contributions.append(
                StrategyContribution(
                    id: id,
                    name: "Liquidity Sweep",
                    group: .ictSmc,
                    direction: recentSweep.reversalDirection,
                    weight: weights[id] ?? ConfluenceScorer.defaultBaseWeight(for: .ictLiquiditySweep),
                    historicalWinRate: 0.61,
                    detail: "Swept liquidity at \(priceFmt.format(recentSweep.sweptLevel)) and reclaimed inside range."
                )
            )
            }
        } else {
            freshSweep = nil
        }

        // Active FVG: must be freshly formed (age <= 4) OR actively retested / proximate within 1.25 * ATR
        let recentActiveFVG: FairValueGap? = !enabled.contains(.ictFvg) ? nil : fvgs.reversed().first(where: { fvg in
            let age = lastIdx - fvg.formedAtIndex
            guard age >= 0 && age <= 18 else { return false }
            let distanceToZone: Double
            if lastBar.close > fvg.top {
                distanceToZone = lastBar.close - fvg.top
            } else if lastBar.close < fvg.bottom {
                distanceToZone = fvg.bottom - lastBar.close
            } else {
                distanceToZone = 0.0
            }
            if fvg.isUnmitigated {
                let isFresh = age <= 4
                let isNear = distanceToZone <= proximityLimit
                return isFresh || isNear
            }
            if let mit = fvg.mitigatedAtIndex, lastIdx - mit <= 2 {
                // Just mitigated and rejecting in FVG direction
                return (fvg.direction == .long && lastBar.close >= fvg.bottom && distanceToZone <= proximityLimit) ||
                       (fvg.direction == .short && lastBar.close <= fvg.top && distanceToZone <= proximityLimit)
            }
            return false
        })
        if let fvg = recentActiveFVG {
            let id = "ict_fvg"
            contributions.append(
                StrategyContribution(
                    id: id,
                    name: fvg.direction == .long ? "Bullish FVG" : "Bearish FVG",
                    group: .ictSmc,
                    direction: fvg.direction,
                    weight: weights[id] ?? ConfluenceScorer.defaultBaseWeight(for: .ictFvg),
                    historicalWinRate: 0.57,
                    detail: "Active \(fvg.direction.rawValue) Fair Value Gap [\(priceFmt.format(fvg.bottom)) - \(priceFmt.format(fvg.top))]."
                )
            )
        }

        // Order Block: must be freshly validated (age <= 4) OR actively tapped / within 1.25 * ATR
        let recentOB: OrderBlock? = !enabled.contains(.ictOrderBlock) ? nil : orderBlocks.reversed().first(where: { ob in
            let age = lastIdx - ob.validFromIndex
            guard age >= 0 && age <= 25 else { return false }
            let distanceToZone: Double
            if lastBar.close > ob.top {
                distanceToZone = lastBar.close - ob.top
            } else if lastBar.close < ob.bottom {
                distanceToZone = ob.bottom - lastBar.close
            } else {
                distanceToZone = 0.0
            }
            guard ob.isUnmitigated else { return false }
            let nearZone: Bool
            if ob.direction == .long {
                nearZone = lastBar.close >= ob.bottom &&
                    (lastBar.low <= ob.top + causalATR * 0.25 || distanceToZone <= proximityLimit)
            } else {
                nearZone = lastBar.close <= ob.top &&
                    (lastBar.high >= ob.bottom - causalATR * 0.25 || distanceToZone <= proximityLimit)
            }
            return age <= 4 || nearZone
        })
        if let ob = recentOB {
            let id = "ict_order_block"
            contributions.append(
                StrategyContribution(
                    id: id,
                    name: ob.direction == .long ? "Bullish Order Block" : "Bearish Order Block",
                    group: .ictSmc,
                    direction: ob.direction,
                    weight: weights[id] ?? ConfluenceScorer.defaultBaseWeight(for: .ictOrderBlock),
                    historicalWinRate: 0.59,
                    detail: "Institutional \(ob.direction.rawValue) OB [\(priceFmt.format(ob.bottom)) - \(priceFmt.format(ob.top))]."
                )
            )
        }

        // Premium / Discount Equilibrium — avoid emitting standalone EQ against an opposing fresh BOS/MSS without a sweep
        if let zone = dealingZone, let eq = eqPrice {
            if zone == .discount {
                let opposesFreshBreak = (freshStructureBreak?.direction == .short) && (freshSweep?.reversalDirection != .long)
                if !opposesFreshBreak && enabled.contains(.ictDiscountEq) {
                    let id = "ict_discount_eq"
                    contributions.append(
                        StrategyContribution(
                            id: id,
                            name: "Discount (<50% EQ)",
                            group: .ictSmc,
                            direction: .long,
                            weight: weights[id] ?? ConfluenceScorer.defaultBaseWeight(for: .ictDiscountEq),
                            historicalWinRate: 0.55,
                            detail: "Price trading in discount below 50% equilibrium (\(priceFmt.format(eq)))."
                        )
                    )
                }
            } else if zone == .premium {
                let opposesFreshBreak = (freshStructureBreak?.direction == .long) && (freshSweep?.reversalDirection != .short)
                if !opposesFreshBreak && enabled.contains(.ictPremiumEq) {
                    let id = "ict_premium_eq"
                    contributions.append(
                        StrategyContribution(
                            id: id,
                            name: "Premium (>50% EQ)",
                            group: .ictSmc,
                            direction: .short,
                            weight: weights[id] ?? ConfluenceScorer.defaultBaseWeight(for: .ictPremiumEq),
                            historicalWinRate: 0.55,
                            detail: "Price trading in premium above 50% equilibrium (\(priceFmt.format(eq)))."
                        )
                    )
                }
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

        return OrderBlock(
            direction: direction,
            top: obBar.high,
            bottom: obBar.low,
            originBarIndex: origin,
            validFromIndex: breakIndex,
            mitigatedAtIndex: mitigated
        )
    }
}
