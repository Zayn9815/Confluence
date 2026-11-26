import Foundation

public enum TrapLifecycleEngine {
    /// Strictly causal 4-stage Behavioral Trap state machine (`trigger` -> `active` -> `returned` -> `invalid`),
    /// inspired by BigTradeTrap's close-only invalidation + Osler Stop-Clustering + Barber-Odean Attention FOMO +
    /// Kahneman-Tversky Disposition Effect breakeven walls.
    public static func evaluate(
        symbol: String,
        roundNumberStep: Double,
        candles: [Candle],
        ict: ICTAnalysis,
        recentNewsImpulses: [MacroClusterImpulse] = [],
        upTo endIndex: Int? = nil,
        lifetimeHours: Double = 48.0,
        enabled: Set<StrategyID> = StrategyID.allSet
    ) -> [BehavioralTrap] {
        // Hard gate: zero computation when every trap toggle is off; each detector below is gated individually.
        let detectNews = enabled.contains(.trapNewsWhipsaw)
        let detectOsler = enabled.contains(.trapOslerRoundNumber)
        let detectSwing = enabled.contains(.trapLiquiditySwingSweep)
        let detectFomo = enabled.contains(.trapAttentionFomo)
        guard detectNews || detectOsler || detectSwing || detectFomo else { return [] }
        let lastIdx = min(endIndex ?? (candles.count - 1), candles.count - 1)
        guard lastIdx >= 15 else { return [] }

        let atrSeries = TrendMomentumDetector.computeATR(candles: Array(candles[0...lastIdx]), period: 14)
        let ema20Series = TrendMomentumDetector.computeEMA(values: candles[0...lastIdx].map(\.close), period: 20)
        let lifetimeSeconds = lifetimeHours * 3_600.0

        var traps: [BehavioralTrap] = []

        // Scan causally bar-by-bar so every trap transitions strictly on subsequent closed bars
        let scanStart = max(14, lastIdx - 60)
        for i in scanStart...lastIdx {
            let bar = candles[i]
            let atrIdx = max(0, i - 13)
            let atr = atrIdx < atrSeries.count ? max(atrSeries[atrIdx], 1e-12) : max(bar.rangeSize, 1e-12)
            let rvol = TrendMomentumDetector.computeRVOL(candles: candles, lastIdx: i, lookback: 20)
            let emaIdx = i - 19
            let ema20 = (emaIdx >= 0 && emaIdx < ema20Series.count) ? ema20Series[emaIdx] : nil

            // 1. Transition all existing traps on bar `i` (strictly close-through invalidation)
            for idx in traps.indices {
                let t = traps[idx]
                guard t.state != .invalid else { continue }
                guard i > t.triggerBarIndex else { continue }

                // Step trigger -> active on the bar after creation
                var nextState = (t.state == .trigger) ? TrapLifecycleState.active : t.state
                var returnedIdx = t.returnedAtBarIndex
                var invalidIdx = t.invalidatedAtBarIndex

                if bar.closeTimeEpochSeconds > t.expiresAtEpochSeconds {
                    nextState = .invalid
                    invalidIdx = i
                } else {
                    // Invalidate ONLY when a candle CLOSES strictly through the trap level (BigTradeTrap rule)
                    let closedThrough: Bool
                    switch t.direction {
                    case .bullTrap:
                        closedThrough = bar.close > t.level
                    case .bearTrap:
                        closedThrough = bar.close < t.level
                    }

                    if closedThrough {
                        nextState = .invalid
                        invalidIdx = i
                    } else {
                        // Price retested the trap level without closing through it -> Returned (disposition wall)
                        let touched: Bool
                        switch t.direction {
                        case .bullTrap:
                            touched = bar.high >= t.level
                        case .bearTrap:
                            touched = bar.low <= t.level
                        }
                        if touched && nextState == .active {
                            nextState = .returned
                            returnedIdx = i
                        }
                    }
                }

                traps[idx] = BehavioralTrap(
                    id: t.id,
                    symbol: t.symbol,
                    direction: t.direction,
                    triggerKind: t.triggerKind,
                    level: t.level,
                    extremePrice: t.extremePrice,
                    triggerBarIndex: t.triggerBarIndex,
                    triggerEpochSeconds: t.triggerEpochSeconds,
                    state: nextState,
                    returnedAtBarIndex: returnedIdx,
                    invalidatedAtBarIndex: invalidIdx,
                    expiresAtEpochSeconds: t.expiresAtEpochSeconds,
                    pierceATRMultiple: t.pierceATRMultiple,
                    rvolMultiple: t.rvolMultiple,
                    detail: t.detail
                )
            }

            // 2. Detect new traps forming on bar `i`
            let wickRatioUpper = bar.rangeSize > 0 ? bar.upperWick / bar.rangeSize : 0
            let wickRatioLower = bar.rangeSize > 0 ? bar.lowerWick / bar.rangeSize : 0

            // 2a. Post-News Whipsaw Trap (bar spans within 15m of a macro release and reverses sharply)
            let matchingMacro = recentNewsImpulses.first { imp in
                abs(bar.openTimeEpochSeconds - imp.clusterEpochSeconds) <= 900 ||
                (imp.clusterEpochSeconds >= bar.openTimeEpochSeconds && imp.clusterEpochSeconds <= bar.closeTimeEpochSeconds)
            }
            if detectNews, let macro = matchingMacro, bar.rangeSize >= atr * 1.4 {
                if wickRatioUpper >= 0.45 && bar.close < bar.open {
                    let level = bar.open + bar.rangeSize * 0.25
                    traps.append(
                        BehavioralTrap(
                            id: "\(symbol)-news-bulltrap-\(i)",
                            symbol: symbol,
                            direction: .bullTrap,
                            triggerKind: .postNewsWhipsawTrap,
                            level: level,
                            extremePrice: bar.high,
                            triggerBarIndex: i,
                            triggerEpochSeconds: bar.closeTimeEpochSeconds,
                            state: .trigger,
                            expiresAtEpochSeconds: bar.closeTimeEpochSeconds + lifetimeSeconds,
                            pierceATRMultiple: (bar.high - level) / atr,
                            rvolMultiple: rvol,
                            detail: "Post-news spike during \(macro.headlineStrip) reversed below open, trapping breakout buyers."
                        )
                    )
                    continue
                } else if wickRatioLower >= 0.45 && bar.close > bar.open {
                    let level = bar.open - bar.rangeSize * 0.25
                    traps.append(
                        BehavioralTrap(
                            id: "\(symbol)-news-beartrap-\(i)",
                            symbol: symbol,
                            direction: .bearTrap,
                            triggerKind: .postNewsWhipsawTrap,
                            level: level,
                            extremePrice: bar.low,
                            triggerBarIndex: i,
                            triggerEpochSeconds: bar.closeTimeEpochSeconds,
                            state: .trigger,
                            expiresAtEpochSeconds: bar.closeTimeEpochSeconds + lifetimeSeconds,
                            pierceATRMultiple: (level - bar.low) / atr,
                            rvolMultiple: rvol,
                            detail: "Post-news flush during \(macro.headlineStrip) reclaimed above open, trapping panic sellers."
                        )
                    )
                    continue
                }
            }

            // 2b. Osler Psychological Round-Number Stop-Cluster Sweep
            if detectOsler, roundNumberStep > 0 {
                let nearestUpperRound = floor(bar.high / roundNumberStep) * roundNumberStep
                if nearestUpperRound > 0 &&
                    bar.high > nearestUpperRound &&
                    bar.close < nearestUpperRound &&
                    bar.open <= nearestUpperRound &&
                    (bar.high - nearestUpperRound) >= atr * 0.15 &&
                    wickRatioUpper >= 0.42 {
                    traps.append(
                        BehavioralTrap(
                            id: "\(symbol)-osler-bulltrap-\(i)",
                            symbol: symbol,
                            direction: .bullTrap,
                            triggerKind: .oslerRoundNumberSweep,
                            level: nearestUpperRound,
                            extremePrice: bar.high,
                            triggerBarIndex: i,
                            triggerEpochSeconds: bar.closeTimeEpochSeconds,
                            state: .trigger,
                            expiresAtEpochSeconds: bar.closeTimeEpochSeconds + lifetimeSeconds,
                            pierceATRMultiple: (bar.high - nearestUpperRound) / atr,
                            rvolMultiple: rvol,
                            detail: "Pierced psychological round level \(formatLevel(nearestUpperRound)) by \(String(format: "%.2f", (bar.high - nearestUpperRound) / atr))x ATR and closed back below."
                        )
                    )
                    continue
                }

                let nearestLowerRound = ceil(bar.low / roundNumberStep) * roundNumberStep
                if nearestLowerRound > 0 &&
                    bar.low < nearestLowerRound &&
                    bar.close > nearestLowerRound &&
                    bar.open >= nearestLowerRound &&
                    (nearestLowerRound - bar.low) >= atr * 0.15 &&
                    wickRatioLower >= 0.42 {
                    traps.append(
                        BehavioralTrap(
                            id: "\(symbol)-osler-beartrap-\(i)",
                            symbol: symbol,
                            direction: .bearTrap,
                            triggerKind: .oslerRoundNumberSweep,
                            level: nearestLowerRound,
                            extremePrice: bar.low,
                            triggerBarIndex: i,
                            triggerEpochSeconds: bar.closeTimeEpochSeconds,
                            state: .trigger,
                            expiresAtEpochSeconds: bar.closeTimeEpochSeconds + lifetimeSeconds,
                            pierceATRMultiple: (nearestLowerRound - bar.low) / atr,
                            rvolMultiple: rvol,
                            detail: "Swept stop cluster below psychological round level \(formatLevel(nearestLowerRound)) by \(String(format: "%.2f", (nearestLowerRound - bar.low) / atr))x ATR and reclaimed above."
                        )
                    )
                    continue
                }
            }

            // 2c. Confirmed ICT Swing Liquidity Sweep Trap
            if detectSwing, let sweep = ict.liquiditySweeps.first(where: { $0.sweepBarIndex == i }) {
                let pierceATR = sweep.pierceDepth / atr
                if pierceATR >= 0.15 {
                    let trapDir: TrapDirection = (sweep.reversalDirection == .short) ? .bullTrap : .bearTrap
                    traps.append(
                        BehavioralTrap(
                            id: "\(symbol)-swing-trap-\(i)",
                            symbol: symbol,
                            direction: trapDir,
                            triggerKind: .liquiditySwingSweep,
                            level: sweep.sweptLevel,
                            extremePrice: sweep.extremePrice,
                            triggerBarIndex: i,
                            triggerEpochSeconds: bar.closeTimeEpochSeconds,
                            state: .trigger,
                            expiresAtEpochSeconds: bar.closeTimeEpochSeconds + lifetimeSeconds,
                            pierceATRMultiple: pierceATR,
                            rvolMultiple: rvol,
                            detail: "Swept prior swing liquidity at \(formatLevel(sweep.sweptLevel)) (\(String(format: "%.2f", pierceATR))x ATR) and closed back inside range."
                        )
                    )
                    continue
                }
            }

            // 2d. Barber & Odean Attention-Driven Retail FOMO Spike (RVOL > 3.0x or extreme parabolic extension + failure close)
            let isAttentionVolumeSpike = (rvol ?? 0.0) >= 3.0
            let isParabolicRange = bar.rangeSize >= atr * 2.4
            if detectFomo, (isAttentionVolumeSpike || isParabolicRange), let eq = ema20 {
                let distFromEMA = (bar.high - eq) / atr
                let distBelowEMA = (eq - bar.low) / atr

                if distFromEMA >= 2.0 && wickRatioUpper >= 0.45 {
                    let trapLevel = max(bar.open, bar.close) + bar.upperWick * 0.25
                    traps.append(
                        BehavioralTrap(
                            id: "\(symbol)-fomo-bulltrap-\(i)",
                            symbol: symbol,
                            direction: .bullTrap,
                            triggerKind: .attentionFOMOSpike,
                            level: trapLevel,
                            extremePrice: bar.high,
                            triggerBarIndex: i,
                            triggerEpochSeconds: bar.closeTimeEpochSeconds,
                            state: .trigger,
                            expiresAtEpochSeconds: bar.closeTimeEpochSeconds + lifetimeSeconds,
                            pierceATRMultiple: (bar.high - trapLevel) / atr,
                            rvolMultiple: rvol,
                            detail: "Attention spike (\(rvol.map { String(format: "%.1fx RVOL", $0) } ?? String(format: "%.1fx ATR", bar.rangeSize / atr))) extended \(String(format: "%.1f", distFromEMA))x ATR above EMA-20 with exhaustion upper wick."
                        )
                    )
                } else if distBelowEMA >= 2.0 && wickRatioLower >= 0.45 {
                    let trapLevel = min(bar.open, bar.close) - bar.lowerWick * 0.25
                    traps.append(
                        BehavioralTrap(
                            id: "\(symbol)-fomo-beartrap-\(i)",
                            symbol: symbol,
                            direction: .bearTrap,
                            triggerKind: .attentionFOMOSpike,
                            level: trapLevel,
                            extremePrice: bar.low,
                            triggerBarIndex: i,
                            triggerEpochSeconds: bar.closeTimeEpochSeconds,
                            state: .trigger,
                            expiresAtEpochSeconds: bar.closeTimeEpochSeconds + lifetimeSeconds,
                            pierceATRMultiple: (trapLevel - bar.low) / atr,
                            rvolMultiple: rvol,
                            detail: "Capitulation spike (\(rvol.map { String(format: "%.1fx RVOL", $0) } ?? String(format: "%.1fx ATR", bar.rangeSize / atr))) stretched \(String(format: "%.1f", distBelowEMA))x ATR below EMA-20 with absorption lower wick."
                        )
                    )
                }
            }
        }

        // Keep most recent 6 traps (including any freshly invalidated ones for diagnostics)
        return Array(traps.suffix(6))
    }

    private static func formatLevel(_ value: Double) -> String {
        if value >= 100 { return String(format: "%.2f", value) }
        if value >= 10 { return String(format: "%.3f", value) }
        return String(format: "%.5f", value)
    }
}
