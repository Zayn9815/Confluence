import Foundation

public enum ConfluenceScorer {
    /// Deterministic signal fingerprint for cooldown deduplication.
    public static func makeFingerprint(
        symbol: String,
        timeframe: Timeframe,
        category: SignalCategory,
        direction: TradeDirection,
        barCloseEpochSeconds: TimeInterval
    ) -> String {
        let bucket = Int(barCloseEpochSeconds / timeframe.seconds)
        return "\(symbol)|\(timeframe.rawValue)|\(category.rawValue)|\(direction.rawValue)|\(bucket)"
    }

    public static func shouldSuppressDuplicate(
        fingerprint: String,
        symbol: String,
        direction: TradeDirection,
        nowEpochSeconds: TimeInterval,
        recentHistory: [(fingerprint: String, symbol: String, direction: TradeDirection, epochSeconds: TimeInterval)],
        cooldownSeconds: TimeInterval
    ) -> Bool {
        if recentHistory.contains(where: { $0.fingerprint == fingerprint }) {
            return true
        }
        return recentHistory.contains { item in
            item.symbol == symbol &&
            item.direction == direction &&
            abs(nowEpochSeconds - item.epochSeconds) < cooldownSeconds
        }
    }

    /// Evaluates full multi-strategy confluence, calibrated Confidence %, Trap warnings,
    /// and weak-setup rejection diagnostics strictly in deterministic Swift code.
    public static func score(
        asset: AssetDescriptor,
        timeframe: Timeframe,
        htfTimeframe: Timeframe,
        candles: [Candle],
        htfBias: TradeDirection,
        ict: ICTAnalysis,
        htfICT: ICTAnalysis?,
        candlestickContributions: [StrategyContribution],
        momentum: TrendMomentumSnapshot,
        regimeAssessment: RegimeAssessment,
        traps: [BehavioralTrap],
        positioning: PositioningAssessment?,
        preNewsShield: PreNewsShieldStatus?,
        macroImpulse: MacroClusterImpulse?,
        config: EngineConfig,
        dataProvider: String,
        isMarketClosed: Bool,
        nowEpochSeconds: TimeInterval
    ) -> TradeSignal? {
        guard let lastBar = candles.last else { return nil }
        let killzone = SessionCalendar.killzone(at: lastBar.closeTimeEpochSeconds)

        // Gather all enabled strategy contributions
        var allContributions: [StrategyContribution] = []
        if config.enabledStrategyGroups.contains(.ictSmc) {
            allContributions.append(contentsOf: ict.contributions)
        }
        if config.enabledStrategyGroups.contains(.candlestick) {
            allContributions.append(contentsOf: candlestickContributions)
        }
        if config.enabledStrategyGroups.contains(.trendMomentum) {
            allContributions.append(contentsOf: momentum.contributions)
        }

        // Behavioral Trap contributions
        let actionableTraps = traps.filter(\.isActionable)
        let freshTrap = actionableTraps.last(where: { candles.count - 1 - $0.triggerBarIndex <= 4 || $0.state == .returned })
        if config.enabledStrategyGroups.contains(.behavioralTrap), let trap = freshTrap {
            allContributions.append(
                StrategyContribution(
                    id: "trap_\(trap.triggerKind.rawValue.lowercased().replacingOccurrences(of: " ", with: "_"))",
                    name: "\(trap.direction.rawValue) (\(trap.state.rawValue.capitalized))",
                    group: .behavioralTrap,
                    direction: trap.direction.institutionalDirection,
                    weight: config.historicalReliabilityWeights["trap"] ?? 1.25,
                    historicalWinRate: 0.61,
                    detail: trap.detail
                )
            )
        }

        // Positioning contribution (OKX Funding/OI or CFTC COT)
        if config.enabledStrategyGroups.contains(.behavioralTrap),
           let pos = positioning,
           pos.proDirection != .neutral {
            allContributions.append(
                StrategyContribution(
                    id: "positioning_\(pos.provenance == .okxFundingOI ? "okx" : "cot")",
                    name: pos.provenance == .okxFundingOI ? "OKX Pro/OI Flow" : "CFTC COT Smart Money",
                    group: .behavioralTrap,
                    direction: pos.proDirection,
                    weight: 1.10,
                    historicalWinRate: 0.59,
                    detail: pos.summary
                )
            )
        }

        // Macro Surprise catalyst contribution
        var macroAlignedDir: TradeDirection = .neutral
        if config.enabledStrategyGroups.contains(.macroCatalyst), let imp = macroImpulse {
            macroAlignedDir = MacroPolarityTable.impactDirection(for: asset, currency: imp.currency, stance: imp.netStance)
            if macroAlignedDir != .neutral && !imp.isWhipsawCautionActive {
                allContributions.append(
                    StrategyContribution(
                        id: "macro_surprise_catalyst",
                        name: "Macro Surprise Catalyst",
                        group: .macroCatalyst,
                        direction: macroAlignedDir,
                        weight: 1.20,
                        historicalWinRate: 0.60,
                        detail: imp.headlineStrip
                    )
                )
            }
        }

        // Split long vs short independent strategy contributions
        let longContribs = deduplicateById(allContributions.filter { $0.direction == .long })
        let shortContribs = deduplicateById(allContributions.filter { $0.direction == .short })

        let longScore = longContribs.reduce(0.0) { $0 + $1.weight }
        let shortScore = shortContribs.reduce(0.0) { $0 + $1.weight }

        let dominantDirection: TradeDirection
        let aligned: [StrategyContribution]
        let opposing: [StrategyContribution]

        if longScore > shortScore && !longContribs.isEmpty {
            dominantDirection = .long
            aligned = longContribs
            opposing = shortContribs
        } else if shortScore > longScore && !shortContribs.isEmpty {
            dominantDirection = .short
            aligned = shortContribs
            opposing = longContribs
        } else if let trap = freshTrap {
            dominantDirection = trap.direction.institutionalDirection
            aligned = dominantDirection == .long ? longContribs : shortContribs
            opposing = dominantDirection == .long ? shortContribs : longContribs
        } else {
            dominantDirection = .neutral
            aligned = []
            opposing = []
        }

        // Calculate numeric levels purely in code
        let levels = TradeLevelCalculator.calculate(
            direction: dominantDirection,
            candles: candles,
            ict: ict,
            htfICT: htfICT,
            atr: momentum.atr14,
            marketClass: asset.marketClass,
            minimumRiskReward: config.minimumRiskReward
        )

        // Calibrated Confidence % (0 - 99%)
        let confidence = computeCalibratedConfidence(
            aligned: aligned,
            opposing: opposing,
            dominantDirection: dominantDirection,
            htfBias: htfBias,
            killzone: killzone,
            regime: regimeAssessment.regime,
            positioning: positioning,
            macroAlignedDir: macroAlignedDir,
            macroImpulse: macroImpulse,
            preNewsShield: preNewsShield,
            freshTrap: freshTrap
        )

        // Hard Gate Checks (all enforced in deterministic Swift code)
        var rejectionReasons: [String] = []
        let distinctGroups = Set(aligned.map(\.group))

        if dominantDirection == .neutral || aligned.count < config.minimumAlignedStrategies {
            rejectionReasons.append("Only \(aligned.count)/\(config.minimumAlignedStrategies) independent strategies aligned")
        }
        if distinctGroups.count < 2 && aligned.count >= config.minimumAlignedStrategies {
            rejectionReasons.append("Lacks multi-pillar independence (only \(distinctGroups.count) strategy group)")
        }
        if confidence < config.minimumConfidencePercent {
            rejectionReasons.append("Confidence \(Int(confidence.rounded()))% below \(Int(config.minimumConfidencePercent.rounded()))% gate")
        }
        if let lv = levels {
            if lv.riskRewardRatio < config.minimumRiskReward - 1e-6 {
                rejectionReasons.append("R:R 1:\(String(format: "%.2f", lv.riskRewardRatio)) below 1:\(String(format: "%.1f", config.minimumRiskReward)) floor")
            }
            let maxSL = config.maxStopLossPercent(for: asset.marketClass)
            if lv.riskPercent > maxSL {
                rejectionReasons.append("Stop-loss \(String(format: "%.2f", lv.riskPercent))% exceeds \(String(format: "%.1f", maxSL))% cap")
            }
        } else {
            rejectionReasons.append("Could not anchor structural invalidation levels")
        }
        if regimeAssessment.regime == .crisis && config.suppressAlertsInCrisisRegime {
            rejectionReasons.append("Crisis regime active (risk_state=reduce; alerts suppressed)")
        }
        if let shield = preNewsShield, shield.isBlackoutActive && config.pauseSignalsDuringPreNewsWindow {
            rejectionReasons.append("Pre-News Volatility Shield active (\(shield.badgeText))")
        }
        if let imp = macroImpulse, imp.isWhipsawCautionActive {
            rejectionReasons.append("Post-news 5m whipsaw / mixed-print caution active")
        }
        // Unresolved opposing behavioral trap blocks primary signal
        if let opposingTrap = actionableTraps.last(where: { $0.direction.institutionalDirection == dominantDirection.opposite }) {
            rejectionReasons.append("Opposing unresolved \(opposingTrap.direction.rawValue) active at \(String(format: "%.2f", opposingTrap.level))")
        }

        // Determine final SignalCategory & Tier
        let category: SignalCategory
        let tier: SignalTier
        let trapDir: TrapDirection?

        if rejectionReasons.isEmpty {
            category = .strongSignal
            trapDir = freshTrap?.direction
            if confidence >= 85.0 {
                tier = .aPlusInstitutional
            } else if confidence >= 75.0 {
                tier = .highConviction
            } else {
                tier = .aligned
            }
        } else if let trap = freshTrap,
                  (trap.state == .trigger || trap.state == .returned || trap.triggerKind == .postNewsWhipsawTrap) {
            category = .trapAlert
            tier = .trapWarning
            trapDir = trap.direction
        } else {
            category = .weakSignal
            tier = .weakFiltered
            trapDir = freshTrap?.direction
        }

        let psychReport = PsychologyReportBuilder.build(
            category: category,
            signalDirection: dominantDirection,
            ict: ict,
            traps: traps,
            positioning: positioning,
            macroImpulse: macroImpulse,
            rejectionReasons: rejectionReasons,
            rvol: momentum.rvol,
            regime: regimeAssessment.regime
        )

        // Chart overlay data (unmitigated FVGs, OBs, active traps, EQ, EMAs)
        var zones: [PriceZoneOverlay] = []
        for (idx, fvg) in ict.fvgs.filter(\.isUnmitigated).suffix(3).enumerated() {
            zones.append(PriceZoneOverlay(
                id: "fvg-\(fvg.formedAtIndex)-\(idx)",
                label: fvg.direction == .long ? "Bull FVG" : "Bear FVG",
                kind: .fvg,
                direction: fvg.direction,
                top: fvg.top,
                bottom: fvg.bottom,
                startBarIndex: fvg.formedAtIndex
            ))
        }
        for (idx, ob) in ict.orderBlocks.filter(\.isUnmitigated).suffix(2).enumerated() {
            zones.append(PriceZoneOverlay(
                id: "ob-\(ob.originBarIndex)-\(idx)",
                label: ob.direction == .long ? "Bull OB" : "Bear OB",
                kind: .orderBlock,
                direction: ob.direction,
                top: ob.top,
                bottom: ob.bottom,
                startBarIndex: ob.originBarIndex
            ))
        }

        let overlays = ChartOverlayData(
            zones: zones,
            traps: traps,
            equilibriumPrice: ict.equilibriumPrice,
            ema20: momentum.ema20,
            ema50: momentum.ema50,
            ema200: momentum.ema200
        )

        let fingerprint = makeFingerprint(
            symbol: asset.symbol,
            timeframe: timeframe,
            category: category,
            direction: dominantDirection,
            barCloseEpochSeconds: lastBar.closeTimeEpochSeconds
        )

        return TradeSignal(
            id: fingerprint,
            fingerprint: fingerprint,
            symbol: asset.symbol,
            displayName: asset.displayName,
            marketClass: asset.marketClass,
            timeframe: timeframe,
            htfTimeframe: htfTimeframe,
            category: category,
            direction: dominantDirection,
            trapDirection: trapDir,
            tier: tier,
            confidencePercent: confidence,
            regime: regimeAssessment.regime,
            riskState: regimeAssessment.riskState,
            killzone: killzone,
            htfBias: htfBias,
            generatedAtEpochSeconds: nowEpochSeconds,
            barCloseEpochSeconds: lastBar.closeTimeEpochSeconds,
            levels: levels,
            alignedStrategies: aligned,
            rejectionReasons: rejectionReasons,
            psychologyReport: psychReport,
            preNewsBadge: preNewsShield?.badgeText,
            postNewsCatalystBadge: macroImpulse?.headlineStrip,
            overlays: overlays,
            recentCandles: Array(candles.suffix(48)),
            aiJudgment: nil,
            aiConfirmed: false,
            dataProvider: dataProvider,
            isMarketClosedSnapshot: isMarketClosed
        )
    }

    private static func computeCalibratedConfidence(
        aligned: [StrategyContribution],
        opposing: [StrategyContribution],
        dominantDirection: TradeDirection,
        htfBias: TradeDirection,
        killzone: KillzoneSession,
        regime: MarketRegime,
        positioning: PositioningAssessment?,
        macroAlignedDir: TradeDirection,
        macroImpulse: MacroClusterImpulse?,
        preNewsShield: PreNewsShieldStatus?,
        freshTrap: BehavioralTrap?
    ) -> Double {
        guard dominantDirection != .neutral, !aligned.isEmpty else { return 25.0 }

        // (a) Count & independence of aligned strategies
        let weightedSum = aligned.reduce(0.0) { $0 + ($1.weight * $1.historicalWinRate) }
        let opposingPenalty = opposing.reduce(0.0) { $0 + ($1.weight * 4.5) }
        let distinctGroups = Set(aligned.map(\.group)).count

        var score = 38.0
        score += min(32.0, weightedSum * 12.5)
        score += Double(max(0, distinctGroups - 1)) * 5.0
        score -= opposingPenalty

        // (c) Regime fit
        switch regime {
        case .trending:
            score += (htfBias == dominantDirection) ? 6.0 : -3.0
        case .meanReverting:
            score += (freshTrap != nil) ? 5.0 : -1.0
        case .highVol:
            score -= 4.0
        case .crisis:
            score -= 18.0
        }

        // (d) HTF bias + Killzone alignment
        if htfBias == dominantDirection {
            score += 7.0
        } else if htfBias == dominantDirection.opposite {
            score -= 9.0
        }
        if killzone.isPrimeLiquidity {
            score += 4.0
        }

        // (e) Pro-vs-Crowd behavioral alignment
        if let pos = positioning {
            if pos.proDirection == dominantDirection {
                score += 6.0
                if pos.retailCrowdDirection == dominantDirection.opposite {
                    score += 4.0 // Classic smart-money vs retail divergence
                }
            } else if pos.proDirection == dominantDirection.opposite {
                score -= 7.0
            }
        }
        if let trap = freshTrap {
            if trap.direction.institutionalDirection == dominantDirection {
                score += 5.0
            } else {
                score -= 10.0
            }
        }

        // (f) Macro catalyst alignment / conflict penalty
        if let imp = macroImpulse {
            if imp.isWhipsawCautionActive {
                score -= 12.0
            } else if macroAlignedDir == dominantDirection {
                score += 6.0
            } else if macroAlignedDir == dominantDirection.opposite {
                score -= 10.0
            }
        }
        if let shield = preNewsShield, shield.isBlackoutActive {
            score -= 14.0
        }

        return min(99.0, max(5.0, score))
    }

    private static func deduplicateById(_ items: [StrategyContribution]) -> [StrategyContribution] {
        var seen = Set<String>()
        var out: [StrategyContribution] = []
        for item in items where !seen.contains(item.id) {
            seen.insert(item.id)
            out.append(item)
        }
        return out
    }
}
