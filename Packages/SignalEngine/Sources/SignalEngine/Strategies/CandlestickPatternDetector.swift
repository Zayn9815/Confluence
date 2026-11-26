import Foundation

public enum CandlestickPatternDetector {
    /// Strictly causal candlestick price-action detector evaluated on `candles[0...endIndex]`.
    public static func detect(
        candles: [Candle],
        upTo endIndex: Int? = nil,
        weights: [String: Double] = [:],
        enabled: Set<StrategyID> = StrategyID.allSet
    ) -> [StrategyContribution] {
        // Hard gate: zero computation when every candlestick toggle is off.
        guard !enabled.isDisjoint(with: StrategyCategory.candlestickPatterns.strategies) else { return [] }
        let lastIdx = min(endIndex ?? (candles.count - 1), candles.count - 1)
        guard lastIdx >= 14 else { return [] }

        let current = candles[lastIdx]
        let prev = candles[lastIdx - 1]
        let prev2 = candles[lastIdx - 2]

        // 14-bar causal ATR for scale-invariant pattern validation
        var atrSum = 0.0
        for i in (lastIdx - 13)...lastIdx {
            let c = candles[i]
            let pc = candles[i - 1].close
            atrSum += max(c.high - c.low, max(abs(c.high - pc), abs(c.low - pc)))
        }
        let atr = max(atrSum / 14.0, 1e-12)

        var results: [StrategyContribution] = []

        // 1. Bullish / Bearish Engulfing
        if enabled.contains(.candleBullishEngulfing),
            current.isBullish && prev.isBearish &&
            current.bodySize > prev.bodySize * 1.05 &&
            current.close >= prev.open &&
            current.open <= prev.close &&
            current.bodySize >= atr * 0.45 {
            let id = "candle_bullish_engulfing"
            results.append(
                StrategyContribution(
                    id: id,
                    name: "Bullish Engulfing",
                    group: .candlestick,
                    direction: .long,
                    weight: weights[id] ?? 1.05,
                    historicalWinRate: 0.57,
                    detail: "Closed bullish body engulfed prior bearish candle (\(String(format: "%.2f", current.bodySize / atr))x ATR)."
                )
            )
        } else if enabled.contains(.candleBearishEngulfing),
                    current.isBearish && prev.isBullish &&
                    current.bodySize > prev.bodySize * 1.05 &&
                    current.close <= prev.open &&
                    current.open >= prev.close &&
                    current.bodySize >= atr * 0.45 {
            let id = "candle_bearish_engulfing"
            results.append(
                StrategyContribution(
                    id: id,
                    name: "Bearish Engulfing",
                    group: .candlestick,
                    direction: .short,
                    weight: weights[id] ?? 1.05,
                    historicalWinRate: 0.57,
                    detail: "Closed bearish body engulfed prior bullish candle (\(String(format: "%.2f", current.bodySize / atr))x ATR)."
                )
            )
        }

        // 2. Pin Bar / Hammer / Shooting Star Rejection Wick
        if enabled.contains(.candleHammerPinbar) || enabled.contains(.candleShootingStar), current.rangeSize >= atr * 0.65 {
            let lowerWickRatio = current.lowerWick / current.rangeSize
            let upperWickRatio = current.upperWick / current.rangeSize
            let bodyRatio = current.bodySize / current.rangeSize

            if enabled.contains(.candleHammerPinbar), lowerWickRatio >= 0.55 && upperWickRatio <= 0.22 && bodyRatio <= 0.35 {
                let id = "candle_hammer_pinbar"
                results.append(
                    StrategyContribution(
                        id: id,
                        name: "Hammer / Pin Rejection",
                        group: .candlestick,
                        direction: .long,
                        weight: weights[id] ?? 1.10,
                        historicalWinRate: 0.58,
                        detail: "Strong lower rejection wick (\(Int((lowerWickRatio * 100).rounded()))% of bar range) signaling demand absorption."
                    )
                )
            } else if enabled.contains(.candleShootingStar), upperWickRatio >= 0.55 && lowerWickRatio <= 0.22 && bodyRatio <= 0.35 {
                let id = "candle_shooting_star"
                results.append(
                    StrategyContribution(
                        id: id,
                        name: "Shooting Star Rejection",
                        group: .candlestick,
                        direction: .short,
                        weight: weights[id] ?? 1.10,
                        historicalWinRate: 0.58,
                        detail: "Strong upper rejection wick (\(Int((upperWickRatio * 100).rounded()))% of bar range) signaling supply absorption."
                    )
                )
            }
        }

        // 3. Strong Displacement / Marubozu
        if enabled.contains(.candleDisplacement), current.rangeSize >= atr * 1.25 && current.bodySize / max(current.rangeSize, 1e-12) >= 0.72 {
            let dir: TradeDirection = current.isBullish ? .long : .short
            let id = "candle_displacement"
            results.append(
                StrategyContribution(
                    id: id,
                    name: dir == .long ? "Bullish Displacement" : "Bearish Displacement",
                    group: .candlestick,
                    direction: dir,
                    weight: weights[id] ?? 1.0,
                    historicalWinRate: 0.56,
                    detail: "Institutional displacement bar (\(String(format: "%.2f", current.rangeSize / atr))x ATR, \(Int((current.bodySize / current.rangeSize * 100).rounded()))% body)."
                )
            )
        }

        // 4. Inside Bar Breakout (prev inside prev2, current breaks and closes outside prev2)
        let prevInsidePrev2 = prev.high <= prev2.high && prev.low >= prev2.low
        if enabled.contains(.candleInsideBreakout), prevInsidePrev2 {
            if current.close > prev2.high {
                let id = "candle_inside_breakout"
                results.append(
                    StrategyContribution(
                        id: id,
                        name: "Inside Bar Breakout",
                        group: .candlestick,
                        direction: .long,
                        weight: weights[id] ?? 0.95,
                        historicalWinRate: 0.55,
                        detail: "Closed above mother-bar high after compression inside bar."
                    )
                )
            } else if current.close < prev2.low {
                let id = "candle_inside_breakout"
                results.append(
                    StrategyContribution(
                        id: id,
                        name: "Inside Bar Breakdown",
                        group: .candlestick,
                        direction: .short,
                        weight: weights[id] ?? 0.95,
                        historicalWinRate: 0.55,
                        detail: "Closed below mother-bar low after compression inside bar."
                    )
                )
            }
        }

        return results
    }
}
