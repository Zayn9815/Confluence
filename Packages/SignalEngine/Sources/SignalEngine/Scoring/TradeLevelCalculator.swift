import Foundation

public enum TradeLevelCalculator {
    /// Code owns ALL numeric levels: Entry Zone, Stop Loss (beyond invalidation swing/OB + ATR buffer),
    /// TP1 (opposing structure/liquidity), TP2 (next HTF liquidity), % risk, % gain, and exact R:R.
    public static func calculate(
        direction: TradeDirection,
        candles: [Candle],
        ict: ICTAnalysis,
        htfICT: ICTAnalysis?,
        atr: Double,
        marketClass: MarketClass,
        minimumRiskReward: Double
    ) -> TradeLevels? {
        guard direction == .long || direction == .short,
              let lastBar = candles.last,
              lastBar.close > 0
        else { return nil }

        let safeATR = max(atr, lastBar.close * 0.0005)
        let close = lastBar.close

        // Entry Zone anchored around current close or active FVG/OB edge
        let entryLow: Double
        let entryHigh: Double
        if direction == .long {
            if let fvg = ict.fvgs.last(where: { $0.direction == .long && $0.isUnmitigated && $0.top <= close * 1.005 }) {
                entryLow = max(fvg.bottom, close - safeATR * 0.6)
                entryHigh = min(max(fvg.top, close), close + safeATR * 0.15)
            } else {
                entryLow = close - safeATR * 0.25
                entryHigh = close + safeATR * 0.10
            }
        } else {
            if let fvg = ict.fvgs.last(where: { $0.direction == .short && $0.isUnmitigated && $0.bottom >= close * 0.995 }) {
                entryLow = max(min(fvg.bottom, close), close - safeATR * 0.15)
                entryHigh = min(fvg.top, close + safeATR * 0.6)
            } else {
                entryLow = close - safeATR * 0.10
                entryHigh = close + safeATR * 0.25
            }
        }
        let orderedLow = min(entryLow, entryHigh)
        let orderedHigh = max(entryLow, entryHigh)
        let entryMid = (orderedLow + orderedHigh) * 0.5

        // Stop Loss beyond structural invalidation swing/OB + 0.25 * ATR buffer
        let stopLoss: Double
        let atrBuffer = safeATR * 0.25
        if direction == .long {
            let recentSwingLow = ict.swings.reversed().first(where: { !$0.isHigh && $0.price < entryMid })?.price
            let recentOBLow = ict.orderBlocks.reversed().first(where: { $0.direction == .long && $0.bottom < entryMid })?.bottom
            let structuralAnchor = [recentSwingLow, recentOBLow, lastBar.low].compactMap { $0 }.max() ?? lastBar.low
            let rawSL = structuralAnchor - atrBuffer
            // Ensure SL is at least 0.5*ATR away so noise doesn't produce distorted R:R
            stopLoss = min(rawSL, entryMid - safeATR * 0.65)
        } else {
            let recentSwingHigh = ict.swings.reversed().first(where: { $0.isHigh && $0.price > entryMid })?.price
            let recentOBHigh = ict.orderBlocks.reversed().first(where: { $0.direction == .short && $0.top > entryMid })?.top
            let structuralAnchor = [recentSwingHigh, recentOBHigh, lastBar.high].compactMap { $0 }.min() ?? lastBar.high
            let rawSL = structuralAnchor + atrBuffer
            stopLoss = max(rawSL, entryMid + safeATR * 0.65)
        }

        let riskDistance = abs(entryMid - stopLoss)
        guard riskDistance > 1e-12 else { return nil }

        // TP1: opposing structure / swing liquidity if >= min R:R, else projected at minRR * risk
        let minTargetDist = riskDistance * max(minimumRiskReward, 1.5)
        let tp1: Double
        let tp2: Double

        if direction == .long {
            let opposingHighs = ict.swings
                .filter { $0.isHigh && $0.price >= entryMid + riskDistance * 1.4 }
                .map(\.price)
                .sorted()
            let htfHighs = (htfICT?.swings ?? [])
                .filter { $0.isHigh && $0.price > entryMid + minTargetDist }
                .map(\.price)
                .sorted()

            tp1 = opposingHighs.first(where: { $0 >= entryMid + minTargetDist }) ?? (entryMid + minTargetDist)
            let tp2Candidate = htfHighs.first(where: { $0 > tp1 + riskDistance * 0.5 })
            tp2 = tp2Candidate ?? (entryMid + riskDistance * max(minimumRiskReward * 1.65, 3.3))
        } else {
            let opposingLows = ict.swings
                .filter { !$0.isHigh && $0.price <= entryMid - riskDistance * 1.4 }
                .map(\.price)
                .sorted(by: >)
            let htfLows = (htfICT?.swings ?? [])
                .filter { !$0.isHigh && $0.price < entryMid - minTargetDist }
                .map(\.price)
                .sorted(by: >)

            tp1 = opposingLows.first(where: { $0 <= entryMid - minTargetDist }) ?? (entryMid - minTargetDist)
            let tp2Candidate = htfLows.first(where: { $0 < tp1 - riskDistance * 0.5 })
            tp2 = tp2Candidate ?? (entryMid - riskDistance * max(minimumRiskReward * 1.65, 3.3))
        }

        let reward1Dist = abs(tp1 - entryMid)
        let reward2Dist = abs(tp2 - entryMid)
        let riskPct = (riskDistance / entryMid) * 100.0
        let reward1Pct = (reward1Dist / entryMid) * 100.0
        let reward2Pct = (reward2Dist / entryMid) * 100.0
        let rr1 = reward1Dist / riskDistance
        let rr2 = reward2Dist / riskDistance

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
            tp2RiskRewardRatio: rr2
        )
    }
}
