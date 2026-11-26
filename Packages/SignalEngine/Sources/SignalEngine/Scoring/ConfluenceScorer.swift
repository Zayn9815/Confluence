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
        let safeClose = barCloseEpochSeconds.isFinite ? barCloseEpochSeconds : 0.0
        let bucket = Int(floor(safeClose / max(timeframe.seconds, 1.0)))
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
        nowEpochSeconds: TimeInterval,
        newsCatalyst: NewsCatalystAssessment? = nil,
        marketClosedReason: String? = nil
    ) -> TradeSignal? {
        guard let lastBar = candles.last else { return nil }
        let killzone = SessionCalendar.killzone(at: lastBar.closeTimeEpochSeconds)

        // Hard per-strategy gate: disabled detectors contribute zero contributions, zero traps and 0 score.
        let enabled = config.enabledStrategies
        let traps = traps.filter { trap in
            StrategyID.forTrapKind(trap.triggerKind).map { enabled.contains($0) } ?? false
        }
        let positioning: PositioningAssessment? = positioning.flatMap { pos in
            enabled.contains(pos.provenance == .okxFundingOI ? .positioningOkx : .positioningCot) ? pos : nil
        }

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
        let trapsAllowed: Bool = {
            guard config.enabledStrategyGroups.contains(.behavioralTrap) else { return false }
            if config.strategySelectionMode == .custom && !config.selectedStrategyConcepts.isEmpty {
                return config.selectedStrategyConcepts.contains(.behavioralTraps)
            }
            return true
        }()
        let positioningAllowed: Bool = {
            guard config.enabledStrategyGroups.contains(.behavioralTrap) else { return false }
            if config.strategySelectionMode == .custom && !config.selectedStrategyConcepts.isEmpty {
                return config.selectedStrategyConcepts.contains(.positioningFlow)
            }
            return true
        }()
        let effectiveTraps = trapsAllowed ? traps : []
        let effectivePositioning = positioningAllowed ? positioning : nil
        let actionableTraps = effectiveTraps.filter(\.isActionable)
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
           let pos = effectivePositioning,
           pos.proDirection != .neutral {
            allContributions.append(
                StrategyContribution(
                    id: "positioning_\(pos.provenance == .okxFundingOI ? "okx" : "cot")",
                    name: pos.provenance == .okxFundingOI ? "OKX Pro/OI Flow" : "CFTC COT Smart Money",
                    group: .behavioralTrap,
                    direction: pos.proDirection,
                    weight: pos.provenance == .okxFundingOI ? 1.10 : 0.90,
                    historicalWinRate: 0.59,
                    detail: pos.summary
                )
            )
        }

        // Macro Surprise catalyst contribution
        var macroAlignedDir: TradeDirection = .neutral
        if config.enabledStrategyGroups.contains(.macroCatalyst), enabled.contains(.macroSurpriseCatalyst), let imp = macroImpulse {
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

        // Drop any contribution whose StrategyID is disabled (defense in depth; detectors already gate at source)
        allContributions = allContributions.filter { contrib in
            guard let sid = contrib.strategyID else { return true }
            return enabled.contains(sid)
        }

        // Apply Custom concept filtering deterministically
        let activeConcepts: Set<StrategyConcept>
        switch config.strategySelectionMode {
        case .defaultAll:
            activeConcepts = Set(StrategyConcept.allCases)
        case .custom:
            activeConcepts = config.selectedStrategyConcepts.isEmpty
                ? Set(StrategyConcept.allCases)
                : config.selectedStrategyConcepts
            allContributions = allContributions.filter { contrib in
                activeConcepts.contains { $0.matches(contributionId: contrib.id) }
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

        // Calculate numeric levels purely in code (with timeframe-aware R:R & ATR ceilings)
        let levels = TradeLevelCalculator.calculate(
            direction: dominantDirection,
            candles: candles,
            ict: ict,
            htfICT: htfICT,
            atr: momentum.atr14,
            marketClass: asset.marketClass,
            minimumRiskReward: config.minimumRiskReward,
            mode: config.levelCalculationMode,
            fixedStopLossPercent: config.fixedStopLossPercent,
            fixedTP1Percent: config.fixedTP1Percent,
            fixedTP2Percent: config.fixedTP2Percent,
            enableTP2Target: config.enableTP2Target,
            timeframe: timeframe
        )

        // Calibrated 4-Pillar Signal Strength & Logistic Confidence (capped <= 92%, closed-market <= 72%)
        let breakdown = computeStrengthBreakdown(
            aligned: aligned,
            opposing: opposing,
            dominantDirection: dominantDirection,
            htfBias: htfBias,
            killzone: killzone,
            regime: regimeAssessment.regime,
            positioning: effectivePositioning,
            macroAlignedDir: macroAlignedDir,
            macroImpulse: macroImpulse,
            newsCatalyst: newsCatalyst,
            preNewsShield: preNewsShield,
            freshTrap: freshTrap,
            isMarketClosed: isMarketClosed
        )
        let confidence = breakdown.finalConfidencePercent

        // Hard Gate Checks (all enforced in deterministic Swift code)
        var rejectionReasons: [String] = []
        let distinctGroups = Set(aligned.map(\.group))
        let isCustomMode = (config.strategySelectionMode == .custom)
        let requiredAlignedCount: Int = isCustomMode
            ? max(1, min(config.minimumAlignedStrategies, activeConcepts.count))
            : config.effectiveMinConfluence(configured: max(3, config.minimumAlignedStrategies))
        let enabledGroupCount = Set(enabled.map(\.group)).count

        if config.strategySelectionMode == .custom && config.customStrategyMatchRule == .requireAllSelected {
            let missingConcepts = activeConcepts.filter { concept in
                !aligned.contains { concept.matches(contributionId: $0.id) }
            }
            if dominantDirection == .neutral || !missingConcepts.isEmpty {
                let names = missingConcepts.map(\.displayName).sorted().prefix(2).joined(separator: ", ")
                rejectionReasons.append("Missing required custom strategies (\(missingConcepts.count) unmatched: \(names))")
            }
        } else {
            if dominantDirection == .neutral || aligned.count < requiredAlignedCount {
                rejectionReasons.append("Only \(aligned.count)/\(requiredAlignedCount) independent strategies aligned")
            }
            let selectedGroupCount = Set(activeConcepts.map(\.group)).count
            let requireTwoGroups = isCustomMode
                ? (requiredAlignedCount >= 2 && selectedGroupCount >= 2)
                : (requiredAlignedCount >= 2 && enabledGroupCount >= 2)
            if requireTwoGroups && distinctGroups.count < 2 && aligned.count >= requiredAlignedCount {
                rejectionReasons.append("Lacks multi-pillar independence (only \(distinctGroups.count) strategy group)")
            }
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
            let priceFmt = ChartPricePrecision.resolve(symbol: asset.symbol, marketClass: asset.marketClass, referencePrice: opposingTrap.level)
            rejectionReasons.append("Opposing unresolved \(opposingTrap.direction.rawValue) active at \(priceFmt.format(opposingTrap.level))")
        }

        // Determine final SignalCategory & Tier
        let category: SignalCategory
        let tier: SignalTier
        let trapDir: TrapDirection?

        if rejectionReasons.isEmpty {
            category = .strongSignal
            trapDir = freshTrap?.direction
            if confidence >= 80.0 {
                tier = .aPlusInstitutional
            } else if confidence >= 73.0 {
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

        let finalDirection: TradeDirection
        let finalLevels: TradeLevels?
        let finalAligned: [StrategyContribution]
        let finalBreakdown: SignalStrengthBreakdown
        let finalConfidence: Double
        if category == .trapAlert, let td = trapDir, td.institutionalDirection != dominantDirection {
            finalDirection = td.institutionalDirection
            finalAligned = opposing
            finalLevels = TradeLevelCalculator.calculate(
                direction: finalDirection,
                candles: candles,
                ict: ict,
                htfICT: htfICT,
                atr: momentum.atr14,
                marketClass: asset.marketClass,
                minimumRiskReward: config.minimumRiskReward,
                mode: config.levelCalculationMode,
                fixedStopLossPercent: config.fixedStopLossPercent,
                fixedTP1Percent: config.fixedTP1Percent,
                fixedTP2Percent: config.fixedTP2Percent,
                enableTP2Target: config.enableTP2Target,
                timeframe: timeframe
            )
            finalBreakdown = computeStrengthBreakdown(
                aligned: opposing,
                opposing: aligned,
                dominantDirection: finalDirection,
                htfBias: htfBias,
                killzone: killzone,
                regime: regimeAssessment.regime,
                positioning: effectivePositioning,
                macroAlignedDir: macroAlignedDir,
                macroImpulse: macroImpulse,
                newsCatalyst: newsCatalyst,
                preNewsShield: preNewsShield,
                freshTrap: freshTrap,
                isMarketClosed: isMarketClosed
            )
            finalConfidence = finalBreakdown.finalConfidencePercent
        } else {
            finalDirection = dominantDirection
            finalLevels = levels
            finalAligned = aligned
            finalBreakdown = breakdown
            finalConfidence = confidence
        }

        let psychReport = PsychologyReportBuilder.build(
            category: category,
            signalDirection: finalDirection,
            ict: ict,
            traps: effectiveTraps,
            positioning: effectivePositioning,
            macroImpulse: macroImpulse,
            rejectionReasons: rejectionReasons,
            rvol: momentum.rvol,
            regime: regimeAssessment.regime,
            newsCatalyst: newsCatalyst,
            asset: asset
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

        var structureEvents: [StructureOverlayEvent] = []
        for (idx, brk) in ict.structureBreaks.suffix(4).enumerated() {
            guard brk.breakBarIndex >= 0, brk.breakBarIndex < candles.count else { continue }
            let bar = candles[brk.breakBarIndex]
            let kind: StructureOverlayEvent.Kind = (brk.kind == .bos) ? .bos : .choch
            let dirTag = (brk.direction == .long) ? "Bull" : "Bear"
            structureEvents.append(StructureOverlayEvent(
                id: "struct-\(kind.rawValue)-\(brk.breakBarIndex)-\(idx)",
                kind: kind,
                direction: brk.direction,
                price: brk.brokenLevel,
                timestampEpochSeconds: bar.openTimeEpochSeconds,
                label: "\(dirTag) \(kind.rawValue)"
            ))
        }
        for (idx, sweep) in ict.liquiditySweeps.suffix(3).enumerated() {
            guard sweep.sweepBarIndex >= 0, sweep.sweepBarIndex < candles.count else { continue }
            let bar = candles[sweep.sweepBarIndex]
            let dirTag = (sweep.reversalDirection == .long) ? "SSL" : "BSL"
            structureEvents.append(StructureOverlayEvent(
                id: "sweep-\(sweep.sweepBarIndex)-\(idx)",
                kind: .liquiditySweep,
                direction: sweep.reversalDirection,
                price: sweep.sweptLevel,
                timestampEpochSeconds: bar.openTimeEpochSeconds,
                label: "\(dirTag) Sweep"
            ))
        }
        structureEvents.sort { $0.timestampEpochSeconds < $1.timestampEpochSeconds }

        let overlays = ChartOverlayData(
            zones: zones,
            traps: effectiveTraps,
            structureEvents: structureEvents,
            equilibriumPrice: ict.equilibriumPrice,
            ema20: momentum.ema20,
            ema50: momentum.ema50,
            ema200: momentum.ema200
        )

        let fingerprint = makeFingerprint(
            symbol: asset.symbol,
            timeframe: timeframe,
            category: category,
            direction: finalDirection,
            barCloseEpochSeconds: lastBar.closeTimeEpochSeconds
        )

        let combinedCatalystBadge = macroImpulse?.headlineStrip ?? newsCatalyst?.headlineBadge

        return TradeSignal(
            id: fingerprint,
            fingerprint: fingerprint,
            symbol: asset.symbol,
            displayName: asset.displayName,
            marketClass: asset.marketClass,
            timeframe: timeframe,
            htfTimeframe: htfTimeframe,
            category: category,
            direction: finalDirection,
            trapDirection: trapDir,
            tier: tier,
            confidencePercent: finalConfidence,
            regime: regimeAssessment.regime,
            riskState: regimeAssessment.riskState,
            killzone: killzone,
            htfBias: htfBias,
            generatedAtEpochSeconds: nowEpochSeconds,
            barCloseEpochSeconds: lastBar.closeTimeEpochSeconds,
            levels: finalLevels,
            alignedStrategies: finalAligned,
            rejectionReasons: rejectionReasons,
            psychologyReport: psychReport,
            preNewsBadge: preNewsShield?.badgeText,
            postNewsCatalystBadge: combinedCatalystBadge,
            overlays: overlays,
            recentCandles: Array(candles.suffix(48)),
            aiJudgment: nil,
            aiConfirmed: false,
            dataProvider: dataProvider,
            isMarketClosedSnapshot: isMarketClosed,
            marketClosedReason: marketClosedReason,
            strengthBreakdown: finalBreakdown,
            matchedStrategyIDs: StrategyID.resolveMatched(
                alignedStrategies: finalAligned,
                category: category,
                trapDirection: trapDir,
                traps: effectiveTraps
            )
        )
    }

    private static func computeStrengthBreakdown(
        aligned: [StrategyContribution],
        opposing: [StrategyContribution],
        dominantDirection: TradeDirection,
        htfBias: TradeDirection,
        killzone: KillzoneSession,
        regime: MarketRegime,
        positioning: PositioningAssessment?,
        macroAlignedDir: TradeDirection,
        macroImpulse: MacroClusterImpulse?,
        newsCatalyst: NewsCatalystAssessment?,
        preNewsShield: PreNewsShieldStatus?,
        freshTrap: BehavioralTrap?,
        isMarketClosed: Bool
    ) -> SignalStrengthBreakdown {
        guard dominantDirection != .neutral, !aligned.isEmpty else {
            return SignalStrengthBreakdown(
                technicalScore: 0,
                psychologyScore: 0,
                newsMacroScore: 0,
                regimeRiskAdjustment: 0,
                finalConfidencePercent: 25.0,
                strengthLabel: "Weak",
                notes: ["No directional multi-strategy consensus"]
            )
        }

        var notes: [String] = []

        // Pillar 1: Technical Math (ICT/SMC + Candlesticks + Trend/Momentum + HTF + Killzone)
        let weightedSum = aligned.reduce(0.0) { $0 + ($1.weight * $1.historicalWinRate) }
        let opposingPenalty = opposing.reduce(0.0) { $0 + ($1.weight * 4.5) }
        let distinctGroups = Set(aligned.map(\.group)).count

        var techScore = min(28.0, weightedSum * 11.5)
        techScore += Double(max(0, distinctGroups - 1)) * 4.0
        techScore -= opposingPenalty
        if htfBias == dominantDirection {
            techScore += 7.0
            notes.append("HTF trend aligned (+7)")
        } else if htfBias == dominantDirection.opposite {
            techScore -= 9.0
            notes.append("Counter-HTF structure (-9)")
        }
        if killzone.isPrimeLiquidity {
            techScore += 3.0
            notes.append("\(killzone.displayName) liquidity (+3)")
        }

        // Pillar 2: Psychology & Positioning (Intraday Traps + OKX/CFTC positioning)
        var psychScore = 0.0
        if let trap = freshTrap {
            if trap.direction.institutionalDirection == dominantDirection {
                psychScore += 5.0
                notes.append("\(trap.direction.rawValue) aligned (+5)")
            } else {
                psychScore -= 10.0
                notes.append("Opposing \(trap.direction.rawValue) (-10)")
            }
        }
        if let pos = positioning, pos.proDirection != .neutral {
            if pos.provenance == .okxFundingOI {
                if pos.proDirection == dominantDirection {
                    psychScore += 5.0
                    if pos.retailCrowdDirection == dominantDirection.opposite {
                        psychScore += 3.0
                    }
                    notes.append("OKX Funding/OI flow aligned")
                } else if pos.proDirection == dominantDirection.opposite {
                    psychScore -= 6.0
                    notes.append("OKX Funding/OI opposing (-6)")
                }
            } else {
                // Weekly CFTC COT informs macro backdrop without overpowering intraday structure
                if pos.proDirection == dominantDirection {
                    psychScore += 4.0
                    if pos.retailCrowdDirection == dominantDirection.opposite {
                        psychScore += 2.0
                    }
                    notes.append("Weekly COT macro aligned")
                } else if pos.proDirection == dominantDirection.opposite {
                    psychScore -= 4.0
                    notes.append("Counter-trend vs Weekly COT (-4)")
                }
            }
        }
        psychScore = max(-14.0, min(14.0, psychScore))

        // Pillar 3: News & Macro Calendar Impact (Macro ±8 pts capped; Breaking News ±4 pts capped)
        var newsMacroScore = 0.0
        if let imp = macroImpulse {
            if imp.isWhipsawCautionActive {
                newsMacroScore -= 10.0
                notes.append("Post-news whipsaw caution (-10)")
            } else if macroAlignedDir == dominantDirection {
                newsMacroScore += 8.0
                notes.append("Macro release aligned (+8)")
            } else if macroAlignedDir == dominantDirection.opposite {
                newsMacroScore -= 8.0
                notes.append("Macro release opposing (-8)")
            }
        }
        if let catalyst = newsCatalyst {
            let cappedWeight = min(4.0, abs(catalyst.netScore) * 2.0)
            if catalyst.direction == dominantDirection {
                newsMacroScore += cappedWeight
                notes.append("\(catalyst.headlineBadge) (+\(String(format: "%.1f", cappedWeight)))")
            } else if catalyst.direction == dominantDirection.opposite {
                newsMacroScore -= cappedWeight
                notes.append("\(catalyst.headlineBadge) opposes (-\(String(format: "%.1f", cappedWeight)))")
            } else if catalyst.isHighVolatilityNeutral {
                newsMacroScore -= 2.0
                notes.append("Volatile headline watch (-2)")
            }
        }
        if let shield = preNewsShield, shield.isBlackoutActive {
            newsMacroScore -= 12.0
            notes.append("Pre-news blackout (-12)")
        }

        // Pillar 4: Regime & Market Session Risk Adjustment
        var regimeAdj = 0.0
        switch regime {
        case .trending:
            regimeAdj += (htfBias == dominantDirection) ? 4.0 : -3.0
        case .meanReverting:
            regimeAdj += (freshTrap != nil) ? 3.0 : -1.0
        case .highVol:
            regimeAdj -= 4.0
            notes.append("High-vol expansion (-4)")
        case .crisis:
            regimeAdj -= 18.0
            notes.append("Crisis regime (-18)")
        }
        if isMarketClosed {
            regimeAdj -= 12.0
            notes.append("Market closed penalty (-12, capped ≤72%)")
        }

        // Smooth calibrated logistic probability mapping (prevents overconfident 85-95% saturation)
        let totalRaw = techScore + psychScore + newsMacroScore + regimeAdj
        let logistic = 1.0 / (1.0 + exp(-0.042 * (totalRaw - 10.0)))
        var calibrated = 15.0 + 77.0 * logistic
        if isMarketClosed {
            calibrated = min(calibrated, 72.0)
        }
        calibrated = min(92.0, max(15.0, calibrated))

        let strengthLabel: String
        if calibrated >= 80.0 {
            strengthLabel = "Institutional A+"
        } else if calibrated >= 73.0 {
            strengthLabel = "Strong"
        } else if calibrated >= 65.0 {
            strengthLabel = "Moderate"
        } else {
            strengthLabel = "Weak"
        }

        return SignalStrengthBreakdown(
            technicalScore: techScore,
            psychologyScore: psychScore,
            newsMacroScore: newsMacroScore,
            regimeRiskAdjustment: regimeAdj,
            finalConfidencePercent: calibrated,
            strengthLabel: strengthLabel,
            notes: notes
        )
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
