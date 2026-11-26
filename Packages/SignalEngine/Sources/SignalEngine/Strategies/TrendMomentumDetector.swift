import Foundation

public struct TrendMomentumSnapshot: Codable, Sendable, Equatable {
    public let ema20: Double?
    public let ema50: Double?
    public let ema200: Double?
    public let rsi14: Double?
    public let atr14: Double
    /// Explicit nil when OTC volume is unavailable ("RVOL = N/A").
    public let rvol: Double?
    public let htfTrendDirection: TradeDirection
    public let contributions: [StrategyContribution]

    public init(
        ema20: Double?,
        ema50: Double?,
        ema200: Double?,
        rsi14: Double?,
        atr14: Double,
        rvol: Double?,
        htfTrendDirection: TradeDirection,
        contributions: [StrategyContribution]
    ) {
        self.ema20 = ema20
        self.ema50 = ema50
        self.ema200 = ema200
        self.rsi14 = rsi14
        self.atr14 = atr14
        self.rvol = rvol
        self.htfTrendDirection = htfTrendDirection
        self.contributions = contributions
    }
}

public enum TrendMomentumDetector {
    /// Strictly causal EMA(20/50/200), RSI(14) + divergence, ATR squeeze breakout, and honest RVOL.
    public static func analyze(
        candles: [Candle],
        upTo endIndex: Int? = nil,
        weights: [String: Double] = [:],
        enabled: Set<StrategyID> = StrategyID.allSet
    ) -> TrendMomentumSnapshot {
        // NOTE: EMA/ATR/RVOL values are always computed (ATR anchors Stop loss / Targets and EMAs feed HTF bias);
        // only the scored momentum StrategyContributions are hard-gated per `StrategyID`.
        let lastIdx = min(endIndex ?? (candles.count - 1), candles.count - 1)
        guard lastIdx >= 20 else {
            return TrendMomentumSnapshot(
                ema20: nil, ema50: nil, ema200: nil, rsi14: nil,
                atr14: 0, rvol: nil, htfTrendDirection: .neutral, contributions: []
            )
        }

        let closes = (0...lastIdx).map { candles[$0].close }
        let ema20Series = computeEMA(values: closes, period: 20)
        let ema50Series = closes.count >= 50 ? computeEMA(values: closes, period: 50) : nil
        let ema200Series = closes.count >= 200 ? computeEMA(values: closes, period: 200) : nil
        let rsiSeries = computeRSI(closes: closes, period: 14)
        let atrSeries = computeATR(candles: Array(candles[0...lastIdx]), period: 14)

        let e20 = ema20Series.last
        let e50 = ema50Series?.last
        let e200 = ema200Series?.last
        let rsi = rsiSeries.last
        let atr = atrSeries.last ?? 0.0
        let lastBar = candles[lastIdx]

        // Compute honest RVOL (nil on OTC feeds without volume)
        let rvol = computeRVOL(candles: candles, lastIdx: lastIdx, lookback: 20)

        // Trend stack bias
        var trendDir: TradeDirection = .neutral
        if let v20 = e20, let v50 = e50 {
            if let v200 = e200 {
                if v20 > v50 && v50 > v200 { trendDir = .long }
                else if v20 < v50 && v50 < v200 { trendDir = .short }
            } else {
                if v20 > v50 && lastBar.close > v50 { trendDir = .long }
                else if v20 < v50 && lastBar.close < v50 { trendDir = .short }
            }
        } else if let v20 = e20 {
            trendDir = lastBar.close > v20 ? .long : .short
        }

        var contributions: [StrategyContribution] = []

        // 1. EMA Stack Pullback / Trend Continuation
        if enabled.contains(.momentumEmaPullback), let v20 = e20, let v50 = e50, atr > 0 {
            let bullishStack = (e200 == nil) ? (v20 > v50) : (v20 > v50 && v50 > e200!)
            let bearishStack = (e200 == nil) ? (v20 < v50) : (v20 < v50 && v50 < e200!)

            if bullishStack && lastBar.low <= v20 + atr * 0.35 && lastBar.close > v20 && lastBar.close > v50 {
                let id = "momentum_ema_pullback"
                contributions.append(
                    StrategyContribution(
                        id: id,
                        name: "EMA Stack Pullback",
                        group: .trendMomentum,
                        direction: .long,
                        weight: weights[id] ?? 1.05,
                        historicalWinRate: 0.58,
                        detail: "Bullish EMA(20/50\(e200 != nil ? "/200" : "")) alignment with pullback bounce off EMA-20."
                    )
                )
            } else if bearishStack && lastBar.high >= v20 - atr * 0.35 && lastBar.close < v20 && lastBar.close < v50 {
                let id = "momentum_ema_pullback"
                contributions.append(
                    StrategyContribution(
                        id: id,
                        name: "EMA Stack Pullback",
                        group: .trendMomentum,
                        direction: .short,
                        weight: weights[id] ?? 1.05,
                        historicalWinRate: 0.58,
                        detail: "Bearish EMA(20/50\(e200 != nil ? "/200" : "")) alignment with rejection at EMA-20."
                    )
                )
            }
        }

        // 2. Causal RSI(14) Divergence over recent 14-bar lookback (verifies genuine 3-bar local pivot)
        if enabled.contains(.momentumRsiDivergence), rsiSeries.count >= 16, let currentRSI = rsi, currentRSI.isFinite {
            let lookback = 12
            let windowStart = max(1, lastIdx - lookback)
            let windowEnd = lastIdx - 2
            var priorLowIdx: Int? = nil
            var priorHighIdx: Int? = nil

            if windowStart < windowEnd {
                for i in windowStart..<windowEnd {
                    let isLocalLow = candles[i].low <= candles[i - 1].low && candles[i].low <= candles[i + 1].low
                    let isLocalHigh = candles[i].high >= candles[i - 1].high && candles[i].high >= candles[i + 1].high
                    if isLocalLow {
                        if let best = priorLowIdx {
                            if candles[i].low < candles[best].low { priorLowIdx = i }
                        } else {
                            priorLowIdx = i
                        }
                    }
                    if isLocalHigh {
                        if let best = priorHighIdx {
                            if candles[i].high > candles[best].high { priorHighIdx = i }
                        } else {
                            priorHighIdx = i
                        }
                    }
                }
            }

            let rsiOffset = lastIdx - (rsiSeries.count - 1)
            if let lowIdx = priorLowIdx {
                let priorLowRSIIndex = lowIdx - rsiOffset
                if priorLowRSIIndex >= 0 && priorLowRSIIndex < rsiSeries.count {
                    let priorRSI = rsiSeries[priorLowRSIIndex]
                    // Regular bullish divergence: lower price low + higher RSI low in oversold/neutral zone
                    if priorRSI.isFinite && lastBar.low < candles[lowIdx].low && currentRSI > priorRSI + 3.5 && priorRSI < 40.0 {
                        let id = "momentum_rsi_divergence"
                        contributions.append(
                            StrategyContribution(
                                id: id,
                                name: "Bullish RSI Divergence",
                                group: .trendMomentum,
                                direction: .long,
                                weight: weights[id] ?? 1.0,
                                historicalWinRate: 0.56,
                                detail: "Lower price low with higher RSI(14) (\(String(format: "%.1f", priorRSI)) -> \(String(format: "%.1f", currentRSI)))."
                            )
                        )
                    }
                }
            }
            if let highIdx = priorHighIdx {
                let priorHighRSIIndex = highIdx - rsiOffset
                if priorHighRSIIndex >= 0 && priorHighRSIIndex < rsiSeries.count {
                    let priorRSI = rsiSeries[priorHighRSIIndex]
                    // Regular bearish divergence: higher price high + lower RSI high in overbought/neutral zone
                    if priorRSI.isFinite && lastBar.high > candles[highIdx].high && currentRSI < priorRSI - 3.5 && priorRSI > 60.0 {
                        let id = "momentum_rsi_divergence"
                        contributions.append(
                            StrategyContribution(
                                id: id,
                                name: "Bearish RSI Divergence",
                                group: .trendMomentum,
                                direction: .short,
                                weight: weights[id] ?? 1.0,
                                historicalWinRate: 0.56,
                                detail: "Higher price high with lower RSI(14) (\(String(format: "%.1f", priorRSI)) -> \(String(format: "%.1f", currentRSI)))."
                            )
                        )
                    }
                }
            }
        }

        // 3. ATR Squeeze Breakout (prior 10 bars compressed below 0.80 * 40-bar avg ATR, current bar expands & breaks range)
        if enabled.contains(.momentumAtrSqueeze), atrSeries.count >= 25 && lastIdx >= 12 {
            let recentBaseline = atrSeries.suffix(25).dropLast()
            let avgATR = recentBaseline.reduce(0, +) / Double(max(recentBaseline.count, 1))
            let prevATR = atrSeries[atrSeries.count - 2]
            if avgATR > 0 && prevATR < avgATR * 0.85 && lastBar.rangeSize > atr * 1.25 {
                let rangeHigh = candles[(lastIdx - 8)..<lastIdx].map(\.high).max() ?? lastBar.high
                let rangeLow = candles[(lastIdx - 8)..<lastIdx].map(\.low).min() ?? lastBar.low
                if lastBar.close > rangeHigh {
                    let id = "momentum_atr_squeeze"
                    contributions.append(
                        StrategyContribution(
                            id: id,
                            name: "ATR Squeeze Breakout",
                            group: .trendMomentum,
                            direction: .long,
                            weight: weights[id] ?? 1.0,
                            historicalWinRate: 0.56,
                            detail: "Volatility compression broke upward (\(String(format: "%.2f", lastBar.rangeSize / atr))x ATR bar)."
                        )
                    )
                } else if lastBar.close < rangeLow {
                    let id = "momentum_atr_squeeze"
                    contributions.append(
                        StrategyContribution(
                            id: id,
                            name: "ATR Squeeze Breakdown",
                            group: .trendMomentum,
                            direction: .short,
                            weight: weights[id] ?? 1.0,
                            historicalWinRate: 0.56,
                            detail: "Volatility compression broke downward (\(String(format: "%.2f", lastBar.rangeSize / atr))x ATR bar)."
                        )
                    )
                }
            }
        }

        // 4. RVOL Confirmation (ONLY when real volume exists; never emits on OTC nil volume)
        if enabled.contains(.momentumRvol), let rv = rvol, rv >= 1.5 {
            let dir: TradeDirection = lastBar.isBullish ? .long : .short
            let id = "momentum_rvol"
            contributions.append(
                StrategyContribution(
                    id: id,
                    name: "RVOL Confirmation",
                    group: .trendMomentum,
                    direction: dir,
                    weight: weights[id] ?? 0.90,
                    historicalWinRate: 0.55,
                    detail: "Relative volume expanded to \(String(format: "%.2f", rv))x 20-bar average."
                )
            )
        }

        return TrendMomentumSnapshot(
            ema20: e20,
            ema50: e50,
            ema200: e200,
            rsi14: rsi,
            atr14: atr,
            rvol: rvol,
            htfTrendDirection: trendDir,
            contributions: contributions
        )
    }

    public static func computeEMA(values: [Double], period: Int) -> [Double] {
        guard values.count >= period, period > 0 else { return [] }
        let k = 2.0 / Double(period + 1)
        let sma = values.prefix(period).reduce(0, +) / Double(period)
        var out: [Double] = [sma]
        out.reserveCapacity(values.count - period + 1)
        var prev = sma
        for i in period..<values.count {
            let next = values[i] * k + prev * (1.0 - k)
            out.append(next)
            prev = next
        }
        return out
    }

    public static func computeRSI(closes: [Double], period: Int = 14) -> [Double] {
        guard closes.count > period else { return [] }
        var avgGain = 0.0
        var avgLoss = 0.0
        for i in 1...period {
            let diff = closes[i] - closes[i - 1]
            if diff >= 0 { avgGain += diff } else { avgLoss += -diff }
        }
        avgGain /= Double(period)
        avgLoss /= Double(period)

        var out: [Double] = []
        let firstRS: Double
        if avgGain == 0 && avgLoss == 0 {
            firstRS = 50.0
        } else if avgLoss == 0 {
            firstRS = 100.0
        } else {
            firstRS = 100.0 - (100.0 / (1.0 + avgGain / avgLoss))
        }
        out.append(firstRS)

        for i in (period + 1)..<closes.count {
            let diff = closes[i] - closes[i - 1]
            let gain = max(diff, 0.0)
            let loss = max(-diff, 0.0)
            avgGain = (avgGain * Double(period - 1) + gain) / Double(period)
            avgLoss = (avgLoss * Double(period - 1) + loss) / Double(period)
            let rsi: Double
            if avgGain == 0 && avgLoss == 0 {
                rsi = 50.0
            } else if avgLoss == 0 {
                rsi = 100.0
            } else {
                rsi = 100.0 - (100.0 / (1.0 + avgGain / avgLoss))
            }
            out.append(rsi)
        }
        return out
    }

    public static func computeATR(candles: [Candle], period: Int = 14) -> [Double] {
        guard candles.count >= period else { return [] }
        var trs: [Double] = []
        trs.reserveCapacity(candles.count)
        for i in 0..<candles.count {
            if i == 0 {
                trs.append(candles[0].rangeSize)
            } else {
                let c = candles[i]
                let pc = candles[i - 1].close
                trs.append(max(c.high - c.low, max(abs(c.high - pc), abs(c.low - pc))))
            }
        }
        var sum = trs.prefix(period).reduce(0, +)
        var out: [Double] = [sum / Double(period)]
        for i in period..<trs.count {
            sum += trs[i] - trs[i - period]
            out.append(sum / Double(period))
        }
        return out
    }

    public static func computeRVOL(candles: [Candle], lastIdx: Int, lookback: Int = 20) -> Double? {
        guard lastIdx >= 5, let currentVol = candles[lastIdx].volume, currentVol > 0 else { return nil }
        let start = max(0, lastIdx - lookback)
        let prior = candles[start..<lastIdx].compactMap(\.volume).filter { $0 > 0 }
        guard prior.count >= 5 else { return nil }
        let avg = prior.reduce(0, +) / Double(prior.count)
        return avg > 0 ? currentVol / avg : nil
    }
}
