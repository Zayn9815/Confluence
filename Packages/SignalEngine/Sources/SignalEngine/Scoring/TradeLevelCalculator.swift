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
                && $0.bottom <= close + safeATR * 0.15
            }) {
                entryLow = min(close, max(fvg.bottom, close - safeATR * 0.6))
                entryHigh = min(max(fvg.top, close), close + safeATR * 0.15)
            } else {
                entryLow = close - safeATR * 0.25
                entryHigh = close + safeATR * 0.10
            }
        } else {
            if let fvg = ict.fvgs.last(where: {
                $0.direction == .short
                && $0.isUnmitigated
                && $0.bottom >= close * 0.995
                && $0.top >= close - safeATR * 0.15
            }) {
                entryLow = max(min(fvg.bottom, close), close - safeATR * 0.15)
                entryHigh = max(close, min(fvg.top, close + safeATR * 0.6))
            } else {
                entryLow = close - safeATR * 0.10
                entryHigh = close + safeATR * 0.25
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

        // Structure / ATR Mode (Default)
        let stopLoss: Double
        let atrBuffer = safeATR * 0.25
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
        let atrTP2Multiplier: Double = (timeframe == .m15) ? 8.0 : 10.0
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
}
