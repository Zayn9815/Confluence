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
        enableTP2Target: Bool = true
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
        if mode == .fixedPercent {
            let spreadPad = min(safeATR * 0.12, close * 0.0005)
            entryLow = close - spreadPad
            entryHigh = close + spreadPad
        } else if direction == .long {
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

        // Fixed % Ratio Mode (exact SL%, TP1%, and optional TP2% around entryMid)
        if mode == .fixedPercent {
            let slFrac = max(0.05, fixedStopLossPercent) / 100.0
            let tp1Frac = max(0.10, fixedTP1Percent) / 100.0
            let tp2Frac = max(tp1Frac, fixedTP2Percent / 100.0)

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
            guard riskDistance > 1e-12 else { return nil }
            let reward1Dist = abs(tp1 - entryMid)
            let reward2Dist = abs(tp2 - entryMid)

            return TradeLevels(
                entryLow: orderedLow,
                entryHigh: orderedHigh,
                entryMid: entryMid,
                stopLoss: stopLoss,
                tp1: tp1,
                tp2: tp2,
                riskPercent: (riskDistance / entryMid) * 100.0,
                reward1Percent: (reward1Dist / entryMid) * 100.0,
                reward2Percent: (reward2Dist / entryMid) * 100.0,
                riskRewardRatio: reward1Dist / riskDistance,
                tp2RiskRewardRatio: reward2Dist / riskDistance,
                isTP2Enabled: enableTP2Target
            )
        }

        // Structure / ATR Mode (Default)
        let stopLoss: Double
        let atrBuffer = safeATR * 0.25
        if direction == .long {
            let recentSwingLow = ict.swings.reversed().first(where: { !$0.isHigh && $0.price < entryMid })?.price
            let recentOBLow = ict.orderBlocks.reversed().first(where: { $0.direction == .long && $0.bottom < entryMid })?.bottom
            let structuralAnchor = [recentSwingLow, recentOBLow, lastBar.low].compactMap { $0 }.max() ?? lastBar.low
            let rawSL = structuralAnchor - atrBuffer
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
        let minTargetDist = riskDistance * max(minimumRiskReward, 1.0)
        let tp1: Double
        let tp2: Double

        if direction == .long {
            let opposingHighs = ict.swings
                .filter { $0.isHigh && $0.price >= entryMid + riskDistance * 1.25 }
                .map(\.price)
                .sorted()
            let htfHighs = (htfICT?.swings ?? [])
                .filter { $0.isHigh && $0.price > entryMid + minTargetDist }
                .map(\.price)
                .sorted()

            tp1 = opposingHighs.first(where: { $0 >= entryMid + minTargetDist }) ?? (entryMid + minTargetDist)
            if enableTP2Target {
                let tp2Candidate = htfHighs.first(where: { $0 > tp1 + riskDistance * 0.5 })
                tp2 = tp2Candidate ?? (entryMid + riskDistance * max(minimumRiskReward * 1.65, 3.3))
            } else {
                tp2 = tp1
            }
        } else {
            let opposingLows = ict.swings
                .filter { !$0.isHigh && $0.price <= entryMid - riskDistance * 1.25 }
                .map(\.price)
                .sorted(by: >)
            let htfLows = (htfICT?.swings ?? [])
                .filter { !$0.isHigh && $0.price < entryMid - minTargetDist }
                .map(\.price)
                .sorted(by: >)

            tp1 = opposingLows.first(where: { $0 <= entryMid - minTargetDist }) ?? (entryMid - minTargetDist)
            if enableTP2Target {
                let tp2Candidate = htfLows.first(where: { $0 < tp1 - riskDistance * 0.5 })
                tp2 = tp2Candidate ?? (entryMid - riskDistance * max(minimumRiskReward * 1.65, 3.3))
            } else {
                tp2 = tp1
            }
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
            tp2RiskRewardRatio: rr2,
            isTP2Enabled: enableTP2Target
        )
    }
}
