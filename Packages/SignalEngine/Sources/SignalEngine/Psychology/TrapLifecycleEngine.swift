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
        let safeLifetimeHours = (lifetimeHours.isFinite && lifetimeHours > 0) ? lifetimeHours : 48.0
        let lifetimeSeconds = safeLifetimeHours * 3_600.0

        var traps: [BehavioralTrap] = []

        // Scan causally from bar 14 (prefix-invariant: traps only retire via close-through invalidation or expiry,
        // never retroactively vanishing when `lastIdx` advances beyond an arbitrary fixed lookback window).
        let scanStart = 14
        for i in scanStart...lastIdx {
            let bar = candles[i]
            guard bar.open.isFinite, bar.high.isFinite, bar.low.isFinite, bar.close.isFinite, bar.close > 0 else {
                continue
            }
            let atrIdx = max(0, i - 13)
            let rawATR = atrIdx < atrSeries.count ? atrSeries[atrIdx] : bar.rangeSize
            let atrFloor = max(bar.close * 0.0005, Double.leastNormalMagnitude)
            let atr = max(rawATR.isFinite ? rawATR : 0.0, atrFloor)
            let rvol = TrendMomentumDetector.computeRVOL(candles: candles, lastIdx: i, lookback: 20)
            let emaIdx = i - 19
            let ema20 = (emaIdx >= 0 && emaIdx < ema20Series.count) ? ema20Series[emaIdx] : nil

            // 1. Transition all existing traps on bar `i` (strictly close-through invalidation)
            for idx in traps.indices {
                let t = traps[idx]
                guard t.state != .invalid else { continue }
                guard i > t.triggerBarIndex else { continue }

                // Step trigger -> active on the bar after creation (never double-jump trigger -> active -> returned on the same bar)
                let wasAlreadyActive = (t.state == .active)
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
                    } else if wasAlreadyActive {
                        // Price retested an already-active trap level without closing through it -> Returned (disposition wall)
                        let touched: Bool
                        switch t.direction {
                        case .bullTrap:
                            touched = bar.high >= t.level
                        case .bearTrap:
                            touched = bar.low <= t.level
                        }
                        if touched {
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

            // 2. Detect new traps forming on bar `i` (skip flat zero-range bars to prevent division/EMA noise spikes)
            guard bar.rangeSize > 0 else { continue }
            let wickRatioUpper = bar.upperWick / bar.rangeSize
            let wickRatioLower = bar.lowerWick / bar.rangeSize

            // 2a. Post-News Whipsaw Trap (bar spans within 15m of a macro release and reverses sharply)
            let matchingMacro = recentNewsImpulses.first { imp in
                imp.clusterEpochSeconds <= bar.closeTimeEpochSeconds &&
                (bar.openTimeEpochSeconds - imp.clusterEpochSeconds) <= 900
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
            if detectOsler, roundNumberStep.isFinite, roundNumberStep > 0 {
                let nearestUpperRound = floor((bar.high - atr * 0.15) / roundNumberStep) * roundNumberStep
                if nearestUpperRound.isFinite && nearestUpperRound > 0 &&
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
                            detail: "Pierced psychological round level \(formatLevel(nearestUpperRound, symbol: symbol)) by \(String(format: "%.2f", (bar.high - nearestUpperRound) / atr))x ATR and closed back below."
                        )
                    )
                    continue
                }

                let nearestLowerRound = ceil((bar.low + atr * 0.15) / roundNumberStep) * roundNumberStep
                if nearestLowerRound.isFinite && nearestLowerRound > 0 &&
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
                            detail: "Swept stop cluster below psychological round level \(formatLevel(nearestLowerRound, symbol: symbol)) by \(String(format: "%.2f", (nearestLowerRound - bar.low) / atr))x ATR and reclaimed above."
                        )
                    )
                    continue
                }
            }

            // 2c. Confirmed ICT Swing Liquidity Sweep Trap
            if detectSwing, let sweep = ict.liquiditySweeps.first(where: { $0.sweepBarIndex == i }) {
                let pierceATR = sweep.pierceDepth / atr
                if pierceATR.isFinite && pierceATR >= 0.15 {
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
                            detail: "Swept prior swing liquidity at \(formatLevel(sweep.sweptLevel, symbol: symbol)) (\(String(format: "%.2f", pierceATR))x ATR) and closed back inside range."
                        )
                    )
                    continue
                }
            }

            // 2d. Barber & Odean Attention-Driven Retail FOMO Spike (RVOL > 3.0x or extreme parabolic extension + failure close)
            let isAttentionVolumeSpike = (rvol ?? 0.0) >= 3.0
            let isParabolicRange = bar.rangeSize >= atr * 2.4
            if detectFomo, (isAttentionVolumeSpike || isParabolicRange), let eq = ema20, eq.isFinite {
                let distFromEMA = (bar.high - eq) / atr
                let distBelowEMA = (eq - bar.low) / atr

                if distFromEMA.isFinite && distFromEMA >= 2.0 && wickRatioUpper >= 0.45 {
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
                } else if distBelowEMA.isFinite && distBelowEMA >= 2.0 && wickRatioLower >= 0.45 {
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

        // Preserve actionable traps before slicing to 6 (with remaining slots filled by latest invalidated traps)
        let actionable = traps.filter(\.isActionable)
        if actionable.count >= 6 {
            return Array(actionable.suffix(6))
        }
        let actionableIDs = Set(actionable.map(\.id))
        let inactiveTail = traps.filter { !actionableIDs.contains($0.id) }.suffix(6 - actionable.count)
        return (Array(inactiveTail) + actionable).sorted { $0.triggerBarIndex < $1.triggerBarIndex }
    }

    private static func formatLevel(_ value: Double, symbol: String) -> String {
        ChartPricePrecision.resolve(symbol: symbol, referencePrice: value).format(value)
    }
}
