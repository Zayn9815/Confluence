import Foundation

public enum TradeLevelCalculator {
    /// Code owns ALL numeric levels: Entry Zone, Stop Loss (either Structure/ATR or Fixed % Ratio),
    /// TP1, optional TP2, % risk, % gain, and exact R:R.
    public static func calculate(
        direction: TradeDirection,
        candles: [Candle],
        ict: ICTAnalysis,
        htfICT: ICTAnalysis?,
        atr: Double,
        marketClass: MarketClass,
        minimumRiskReward: Double,
        mode: TradeLevelMode = .structureATR,
        fixedStopLossPercent: Double = 1.0,
        fixedTP1Percent: Double = 2.0,
        fixedTP2Percent: Double = 3.5,
        enableTP2Target: Bool = true,
        timeframe: Timeframe = .h1
    ) -> TradeLevels? {
        guard direction == .long || direction == .short,
              let lastBar = candles.last,
              lastBar.close.isFinite,
              lastBar.close > 0,
              lastBar.low.isFinite, lastBar.low > 0,
              lastBar.high.isFinite, lastBar.high >= lastBar.low
        else { return nil }

        let validATR = (atr.isFinite && atr > 0) ? atr : 0.0
        let safeATR = max(validATR, lastBar.close * 0.0005, Double.leastNormalMagnitude)
        let close = lastBar.close

        let entryZoneScale: Double
        switch timeframe {
        case .m15: entryZoneScale = 0.90
        case .m30: entryZoneScale = 0.95
        case .h1: entryZoneScale = 1.00
        case .h4: entryZoneScale = 1.08
        case .d1: entryZoneScale = 1.15
        }

        // Entry Zone anchored around current close or active FVG/OB edge
        let entryLow: Double
        let entryHigh: Double
        if mode == .fixedPercent {
            let spreadPad = min(safeATR * 0.12, close * 0.0005)
            entryLow = close - spreadPad
            entryHigh = close + spreadPad
        } else if direction == .long {
            if let fvg = ict.fvgs.last(where: {
                $0.direction == .long
                && $0.isUnmitigated
                && $0.top <= close * 1.005
                && $0.bottom <= close + safeATR * 0.15 * entryZoneScale
            }) {
                entryLow = min(close, max(fvg.bottom, close - safeATR * 0.6 * entryZoneScale))
                entryHigh = min(max(fvg.top, close), close + safeATR * 0.15 * entryZoneScale)
            } else {
                entryLow = close - safeATR * 0.25 * entryZoneScale
                entryHigh = close + safeATR * 0.10 * entryZoneScale
            }
        } else {
            if let fvg = ict.fvgs.last(where: {
                $0.direction == .short
                && $0.isUnmitigated
                && $0.bottom >= close * 0.995
                && $0.top >= close - safeATR * 0.15 * entryZoneScale
            }) {
                entryLow = max(min(fvg.bottom, close), close - safeATR * 0.15 * entryZoneScale)
                entryHigh = max(close, min(fvg.top, close + safeATR * 0.6 * entryZoneScale))
            } else {
                entryLow = close - safeATR * 0.10 * entryZoneScale
                entryHigh = close + safeATR * 0.25 * entryZoneScale
            }
        }
        let orderedLow = min(entryLow, entryHigh)
        let orderedHigh = max(entryLow, entryHigh)
        let entryMid = (orderedLow + orderedHigh) * 0.5
        guard entryMid.isFinite, entryMid > 0 else { return nil }
        let minStopDist = max(Double.leastNormalMagnitude, entryMid * 1e-12)

        // Fixed % Ratio Mode (exact SL%, TP1%, and optional TP2% around entryMid)
        if mode == .fixedPercent {
            let safeFixedSL = fixedStopLossPercent.isFinite ? fixedStopLossPercent : 1.0
            let safeFixedTP1 = fixedTP1Percent.isFinite ? fixedTP1Percent : 2.0
            let safeFixedTP2 = fixedTP2Percent.isFinite ? fixedTP2Percent : 3.5

            let slFrac = min(max(0.05, safeFixedSL), 95.0) / 100.0
            let tp1Frac = min(max(0.10, safeFixedTP1), 95.0) / 100.0
            let tp2Frac = min(max(tp1Frac, safeFixedTP2 / 100.0), 0.95)

            let stopLoss: Double
            let tp1: Double
            let tp2: Double
            if direction == .long {
                stopLoss = entryMid * (1.0 - slFrac)
                tp1 = entryMid * (1.0 + tp1Frac)
                tp2 = enableTP2Target ? entryMid * (1.0 + tp2Frac) : tp1
            } else {
                stopLoss = entryMid * (1.0 + slFrac)
                tp1 = entryMid * (1.0 - tp1Frac)
                tp2 = enableTP2Target ? entryMid * (1.0 - tp2Frac) : tp1
            }

            let riskDistance = abs(entryMid - stopLoss)
            guard riskDistance.isFinite, riskDistance > minStopDist else { return nil }
            let exactRR1 = tp1Frac / slFrac
            let exactRR2 = enableTP2Target ? (tp2Frac / slFrac) : exactRR1
            guard exactRR1.isFinite, exactRR2.isFinite else { return nil }

            return TradeLevels(
                entryLow: orderedLow,
                entryHigh: orderedHigh,
                entryMid: entryMid,
                stopLoss: stopLoss,
                tp1: tp1,
                tp2: tp2,
                riskPercent: slFrac * 100.0,
                reward1Percent: tp1Frac * 100.0,
                reward2Percent: (enableTP2Target ? tp2Frac : tp1Frac) * 100.0,
                riskRewardRatio: exactRR1,
                tp2RiskRewardRatio: exactRR2,
                isTP2Enabled: enableTP2Target
            )
        }

        // Structure / ATR Mode (Default) — exhaustive timeframe scaling
        let atrBufferMult: Double
        let atrTP2Multiplier: Double
        switch timeframe {
        case .m15:
            atrBufferMult = 0.22
            atrTP2Multiplier = 8.0
        case .m30:
            atrBufferMult = 0.25
            atrTP2Multiplier = 9.0
        case .h1:
            atrBufferMult = 0.28
            atrTP2Multiplier = 10.0
        case .h4:
            atrBufferMult = 0.32
            atrTP2Multiplier = 11.0
        case .d1:
            atrBufferMult = 0.35
            atrTP2Multiplier = 12.0
        }

        let stopLoss: Double
        let atrBuffer = safeATR * atrBufferMult
        if direction == .long {
            let recentSwingLow = ict.swings.reversed().first(where: { !$0.isHigh && $0.price.isFinite && $0.price < entryMid })?.price
            let recentOBLow = ict.orderBlocks.reversed().first(where: { $0.direction == .long && $0.bottom.isFinite && $0.bottom < entryMid })?.bottom
            let structuralAnchor = [recentSwingLow, recentOBLow, lastBar.low].compactMap { $0 }.max() ?? lastBar.low
            let rawSL = structuralAnchor - atrBuffer
            stopLoss = max(min(rawSL, entryMid - safeATR * 0.65), entryMid * 0.05)
        } else {
            let recentSwingHigh = ict.swings.reversed().first(where: { $0.isHigh && $0.price.isFinite && $0.price > entryMid })?.price
            let recentOBHigh = ict.orderBlocks.reversed().first(where: { $0.direction == .short && $0.top.isFinite && $0.top > entryMid })?.top
            let structuralAnchor = [recentSwingHigh, recentOBHigh, lastBar.high].compactMap { $0 }.min() ?? lastBar.high
            let rawSL = structuralAnchor + atrBuffer
            stopLoss = max(rawSL, entryMid + safeATR * 0.65)
        }

        let riskDistance = abs(entryMid - stopLoss)
        guard riskDistance.isFinite, riskDistance > minStopDist else { return nil }

        // Sane R:R & timeframe-scaled ATR ceilings prevent unrealistic distant HTF swing targets (e.g. 1:16.7 on 15m)
        let sanitizedMinRR = minimumRiskReward.isFinite ? minimumRiskReward : 2.0
        let minRR = max(min(sanitizedMinRR, 10.0), 1.0)
        let minTargetDist = riskDistance * minRR
        let maxTP1RR = min(max(minRR * 1.6, 3.5), 4.0)
        let maxTP2RR = min(max(minRR * 2.2, 4.5), 6.0)
        let maxTP1Dist = max(minTargetDist, min(riskDistance * max(maxTP1RR, minRR), safeATR * (atrTP2Multiplier * 0.7)))
        let maxTP2Dist = max(minTargetDist * 1.25, min(riskDistance * maxTP2RR, safeATR * atrTP2Multiplier))
        let defaultTP2Dist = min(maxTP2Dist, riskDistance * max(minRR * 1.65, 3.3))

        let tp1: Double
        let tp2: Double

        if direction == .long {
            let opposingHighs = ict.swings
                .filter { $0.isHigh && $0.price.isFinite && $0.price >= entryMid + riskDistance * 1.25 }
                .map(\.price)
                .sorted()
            let htfHighs = (htfICT?.swings ?? [])
                .filter { $0.isHigh && $0.price.isFinite && $0.price > entryMid + minTargetDist }
                .map(\.price)
                .sorted()

            let tp1Candidate = opposingHighs.first(where: { $0 >= entryMid + minTargetDist && $0 <= entryMid + maxTP1Dist })
            tp1 = tp1Candidate ?? (entryMid + minTargetDist)

            if enableTP2Target {
                let tp2Min = tp1 + riskDistance * 0.5
                let tp2Max = entryMid + maxTP2Dist
                let tp2Candidate = htfHighs.first(where: { $0 >= tp2Min && $0 <= tp2Max })
                    ?? opposingHighs.first(where: { $0 >= tp2Min && $0 <= tp2Max })
                let rawTP2 = tp2Candidate ?? max(tp2Min, entryMid + defaultTP2Dist)
                tp2 = min(rawTP2, max(tp2Min, tp2Max))
            } else {
                tp2 = tp1
            }
        } else {
            let opposingLows = ict.swings
                .filter { !$0.isHigh && $0.price.isFinite && $0.price <= entryMid - riskDistance * 1.25 }
                .map(\.price)
                .sorted(by: >)
            let htfLows = (htfICT?.swings ?? [])
                .filter { !$0.isHigh && $0.price.isFinite && $0.price < entryMid - minTargetDist }
                .map(\.price)
                .sorted(by: >)

            let tp1Candidate = opposingLows.first(where: { $0 <= entryMid - minTargetDist && $0 >= entryMid - maxTP1Dist })
            let shortFloor = entryMid * 0.05
            tp1 = max(tp1Candidate ?? (entryMid - minTargetDist), shortFloor)

            if enableTP2Target {
                let tp2Min = max(tp1 - riskDistance * 0.5, shortFloor)
                let tp2Max = max(entryMid - maxTP2Dist, shortFloor)
                let tp2Candidate = htfLows.first(where: { $0 <= tp2Min && $0 >= tp2Max })
                    ?? opposingLows.first(where: { $0 <= tp2Min && $0 >= tp2Max })
                let rawTP2 = tp2Candidate ?? min(tp2Min, entryMid - defaultTP2Dist)
                tp2 = max(shortFloor, min(tp1, max(rawTP2, min(tp2Min, tp2Max))))
            } else {
                tp2 = tp1
            }
        }

        let reward1Dist = abs(tp1 - entryMid)
        let reward2Dist = abs(tp2 - entryMid)
        guard reward1Dist.isFinite, reward2Dist.isFinite else { return nil }

        let riskPct = (riskDistance / entryMid) * 100.0
        let reward1Pct = (reward1Dist / entryMid) * 100.0
        let reward2Pct = (reward2Dist / entryMid) * 100.0
        let rr1 = reward1Dist / riskDistance
        let rr2 = reward2Dist / riskDistance
        guard riskPct.isFinite, reward1Pct.isFinite, reward2Pct.isFinite, rr1.isFinite, rr2.isFinite else { return nil }

        return TradeLevels(
            entryLow: orderedLow,
            entryHigh: orderedHigh,
            entryMid: entryMid,
            stopLoss: stopLoss,
            tp1: tp1,
            tp2: tp2,
            riskPercent: riskPct,
            reward1Percent: reward1Pct,
            reward2Percent: reward2Pct,
            riskRewardRatio: rr1,
            tp2RiskRewardRatio: rr2,
            isTP2Enabled: enableTP2Target
        )
    }

    /// Synthesizes deterministic ATR-anchored Entry Zone / SL / TP1 / TP2 for any actionable `BehavioralTrap`
    /// so Trap Alerts always have concrete auditable trade levels for automatic Journal tracking.
    public static func synthesizeTrapLevels(
        trap: BehavioralTrap,
        candles: [Candle],
        atr: Double,
        marketClass: MarketClass,
        timeframe: Timeframe
    ) -> TradeLevels? {
        guard trap.level.isFinite, trap.level > 0,
              trap.extremePrice.isFinite, trap.extremePrice > 0
        else { return nil }

        let direction = trap.direction.institutionalDirection
        guard direction == .long || direction == .short else { return nil }

        let refClose: Double = {
            if let last = candles.last, last.close.isFinite, last.close > 0 {
                return last.close
            }
            return trap.level
        }()

        let validATR = (atr.isFinite && atr > 0) ? atr : (candles.last?.rangeSize ?? (refClose * 0.002))
        let safeATR = max(validATR, refClose * 0.0005, Double.leastNormalMagnitude)

        let atrBufferMult: Double
        let atrTP2Multiplier: Double
        switch timeframe {
        case .m15:
            atrBufferMult = 0.22
            atrTP2Multiplier = 8.0
        case .m30:
            atrBufferMult = 0.25
            atrTP2Multiplier = 9.0
        case .h1:
            atrBufferMult = 0.28
            atrTP2Multiplier = 10.0
        case .h4:
            atrBufferMult = 0.32
            atrTP2Multiplier = 11.0
        case .d1:
            atrBufferMult = 0.35
            atrTP2Multiplier = 12.0
        }

        let atrBuffer = safeATR * atrBufferMult
        let clampedTrapRef = min(refClose + safeATR * 0.45, max(refClose - safeATR * 0.45, trap.level))
        let entryLow: Double
        let entryHigh: Double
        if direction == .long {
            entryLow = min(refClose, clampedTrapRef) - safeATR * 0.15
            entryHigh = max(refClose, clampedTrapRef) + safeATR * 0.10
        } else {
            entryLow = min(refClose, clampedTrapRef) - safeATR * 0.10
            entryHigh = max(refClose, clampedTrapRef) + safeATR * 0.15
        }
        let orderedLow = max(min(entryLow, entryHigh), refClose * 0.05)
        let orderedHigh = max(entryLow, entryHigh)
        let entryMid = (orderedLow + orderedHigh) * 0.5
        guard entryMid.isFinite, entryMid > 0 else { return nil }
        let minStopDist = max(Double.leastNormalMagnitude, entryMid * 1e-12)

        let maxSLFraction = max(0.005, marketClass.defaultMaxStopLossPercent / 100.0)
        let stopLoss: Double
        if direction == .long {
            let rawSL = min(trap.extremePrice - atrBuffer, entryMid - safeATR * 0.65)
            let floorSL = max(entryMid * (1.0 - maxSLFraction), entryMid * 0.05)
            stopLoss = min(entryMid - safeATR * 0.35, max(rawSL, floorSL))
        } else {
            let rawSL = max(trap.extremePrice + atrBuffer, entryMid + safeATR * 0.65)
            let capSL = entryMid * (1.0 + maxSLFraction)
            stopLoss = max(entryMid + safeATR * 0.35, min(rawSL, capSL))
        }

        let riskDistance = abs(entryMid - stopLoss)
        guard riskDistance.isFinite, riskDistance > minStopDist else { return nil }

        let tp1Dist = min(max(riskDistance * 2.0, safeATR * 1.2), safeATR * (atrTP2Multiplier * 0.7))
        let tp2Dist = min(max(tp1Dist + riskDistance * 1.0, riskDistance * 3.2), safeATR * atrTP2Multiplier)

        let tp1: Double
        let tp2: Double
        if direction == .long {
            tp1 = entryMid + tp1Dist
            tp2 = entryMid + max(tp2Dist, tp1Dist + riskDistance * 0.5)
        } else {
            let floor = entryMid * 0.05
            tp1 = max(floor, entryMid - tp1Dist)
            tp2 = max(floor, min(tp1, entryMid - max(tp2Dist, tp1Dist + riskDistance * 0.5)))
        }

        let reward1Dist = abs(tp1 - entryMid)
        let reward2Dist = abs(tp2 - entryMid)
        let riskPct = (riskDistance / entryMid) * 100.0
        let reward1Pct = (reward1Dist / entryMid) * 100.0
        let reward2Pct = (reward2Dist / entryMid) * 100.0
        let rr1 = reward1Dist / riskDistance
        let rr2 = reward2Dist / riskDistance
        guard riskPct.isFinite, reward1Pct.isFinite, reward2Pct.isFinite, rr1.isFinite, rr2.isFinite else { return nil }

        return TradeLevels(
            entryLow: orderedLow,
            entryHigh: orderedHigh,
            entryMid: entryMid,
            stopLoss: stopLoss,
            tp1: tp1,
            tp2: tp2,
            riskPercent: riskPct,
            reward1Percent: reward1Pct,
            reward2Percent: reward2Pct,
            riskRewardRatio: rr1,
            tp2RiskRewardRatio: rr2,
            isTP2Enabled: true
        )
    }
}
