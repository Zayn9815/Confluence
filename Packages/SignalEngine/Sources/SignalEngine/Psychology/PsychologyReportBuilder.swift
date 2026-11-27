import Foundation

public struct TraderPsychologyInsight: Codable, Sendable, Equatable, Hashable, Identifiable {
    public enum Severity: String, Codable, Sendable, Equatable, Hashable {
        case positive
        case neutral
        case caution
    }

    public let id: String
    public let title: String
    public let detail: String
    public let severity: Severity

    public init(id: String, title: String, detail: String, severity: Severity) {
        self.id = id
        self.title = title
        self.detail = detail
        self.severity = severity
    }
}

public struct TraderPsychologyCoachReport: Codable, Sendable, Equatable, Hashable {
    public let disciplineScorePercent: Double
    public let activeProfileKey: String
    public let enabledCoreCount: Int
    public let filterHoppingDetected: Bool
    public let filterHopSwitchCount: Int
    public let conflictingOrderFlowTrades: Int
    public let conflictingOrderFlowAvgR: Double?
    public let alignedOrderFlowAvgR: Double?
    public let insights: [TraderPsychologyInsight]

    public init(
        disciplineScorePercent: Double,
        activeProfileKey: String,
        enabledCoreCount: Int,
        filterHoppingDetected: Bool,
        filterHopSwitchCount: Int,
        conflictingOrderFlowTrades: Int,
        conflictingOrderFlowAvgR: Double?,
        alignedOrderFlowAvgR: Double?,
        insights: [TraderPsychologyInsight]
    ) {
        self.disciplineScorePercent = disciplineScorePercent
        self.activeProfileKey = activeProfileKey
        self.enabledCoreCount = enabledCoreCount
        self.filterHoppingDetected = filterHoppingDetected
        self.filterHopSwitchCount = filterHopSwitchCount
        self.conflictingOrderFlowTrades = conflictingOrderFlowTrades
        self.conflictingOrderFlowAvgR = conflictingOrderFlowAvgR
        self.alignedOrderFlowAvgR = alignedOrderFlowAvgR
        self.insights = insights
    }
}

public enum PsychologyReportBuilder {
    /// Synthesizes a strictly rule-triggered `PsychologyReport` from concrete structural, trap,
    /// positioning, crypto order flow, and macro evidence — zero generic filler text, and never
    /// lectures about strategies disabled in `activeProfile` or absent Order Flow on non-crypto markets.
    public static func build(
        category: SignalCategory,
        signalDirection: TradeDirection,
        ict: ICTAnalysis,
        traps: [BehavioralTrap],
        positioning: PositioningAssessment?,
        macroImpulse: MacroClusterImpulse?,
        rejectionReasons: [String],
        rvol: Double?,
        regime: MarketRegime,
        newsCatalyst: NewsCatalystAssessment? = nil,
        asset: AssetDescriptor? = nil,
        activeProfile: ActiveStrategyProfile? = nil,
        orderFlow: OrderFlowAssessment? = nil
    ) -> PsychologyReport {
        var evidence: [BehavioralEvidence] = []
        var badges: [String] = []

        let isCryptoAsset = (asset?.marketClass == .crypto)
        let activeOrderFlow: OrderFlowAssessment? = {
            guard isCryptoAsset, let of = orderFlow, of.alignment != .unavailable else { return nil }
            return of
        }()

        // 1. Active Behavioral Traps
        let actionableTraps = traps.filter(\.isActionable)
        let latestTrap = actionableTraps.last

        if let trap = latestTrap {
            badges.append(trap.triggerKind.rawValue)
            if trap.state == .returned {
                badges.append("Disposition Wall")
            }
            evidence.append(
                BehavioralEvidence(
                    badge: trap.triggerKind.rawValue,
                    fact: trap.detail,
                    proBias: trap.direction.institutionalDirection,
                    retailBias: trap.direction.trappedRetailDirection
                )
            )
        }

        // 2. Positioning evidence (OKX or CFTC COT)
        if let pos = positioning {
            badges.append(contentsOf: pos.badges)
            evidence.append(
                BehavioralEvidence(
                    badge: pos.provenance.rawValue,
                    fact: pos.summary,
                    proBias: pos.proDirection,
                    retailBias: pos.retailCrowdDirection
                )
            )
        }

        // 2b. Live Crypto Order Flow & Institutional Absorption evidence (Crypto Only when ON & fresh)
        if let of = activeOrderFlow {
            if of.absorptionState.shortTag != nil {
                badges.append(of.absorptionState == .bullishAbsorption ? "Bullish Absorption" : "Bearish Absorption")
            }
            if of.divergence == .bullish {
                badges.append("Bullish CVD Div")
            } else if of.divergence == .bearish {
                badges.append("Bearish CVD Div")
            }
            if of.confirmedWallBlocksTP1 {
                badges.append("Wall Blocks TP1")
            } else if of.alignment == .conflicting {
                badges.append("Order Flow Conflict")
            } else if of.alignment == .aligned {
                badges.append("Order Flow Aligned")
            }
            let retailAggressor: TradeDirection = of.cvdRatio >= 0.20 ? .long : (of.cvdRatio <= -0.20 ? .short : .neutral)
            evidence.append(
                BehavioralEvidence(
                    badge: "\(of.venue) Order Flow",
                    fact: of.warningNote ?? of.summary,
                    proBias: of.directionalBias,
                    retailBias: of.absorptionState.isDetected ? retailAggressor : .neutral
                )
            )
        }

        // 3. Macro Surprise & Breaking News catalyst evidence
        if let macro = macroImpulse {
            let macroPro: TradeDirection
            if let asset {
                macroPro = MacroPolarityTable.impactDirection(for: asset, currency: macro.currency, stance: macro.netStance)
            } else {
                macroPro = macro.impacts.first?.direction ?? .neutral
            }
            if macro.isWhipsawCautionActive {
                badges.append("News Whipsaw Risk")
            } else if macroPro != .neutral && macroPro == signalDirection {
                badges.append("Macro Catalyst Aligned")
            } else if macroPro != .neutral && signalDirection != .neutral && macroPro != signalDirection {
                badges.append("Macro Catalyst Opposes")
            }
            evidence.append(
                BehavioralEvidence(
                    badge: "Macro Release",
                    fact: macro.headlineStrip,
                    proBias: macroPro,
                    retailBias: macro.isWhipsawCautionActive ? macroPro.opposite : .neutral
                )
            )
        }
        if let news = newsCatalyst {
            badges.append(news.headlineBadge)
            evidence.append(
                BehavioralEvidence(
                    badge: "Breaking News",
                    fact: news.summary,
                    proBias: news.direction,
                    retailBias: .neutral
                )
            )
        }

        // 4. Provenance badge (exact data source honesty)
        let provenance: PositioningProvenance
        if let pos = positioning {
            provenance = pos.provenance
        } else if macroImpulse != nil {
            provenance = .macroSurpriseStructure
        } else {
            provenance = .structureVolumeWickProxy
        }

        // 5. Separate Intraday Pro Flow (`proDir`) from Weekly Macro COT (`macroDir`)
        let macroDir: TradeDirection?
        let macroLabel: String?
        let macroAligns: Bool?
        if let pos = positioning, pos.proDirection != .neutral {
            macroDir = pos.proDirection
            macroLabel = (pos.provenance == .cftcCOT) ? "Weekly COT Macro" : "OKX Derivatives Flow"
            if signalDirection != .neutral {
                macroAligns = (pos.proDirection == signalDirection)
            } else {
                macroAligns = nil
            }
        } else {
            macroDir = nil
            macroLabel = nil
            macroAligns = nil
        }

        var proDir: TradeDirection = .neutral
        if let trap = latestTrap {
            proDir = trap.direction.institutionalDirection
        } else if let of = activeOrderFlow, of.absorptionState.isDetected {
            proDir = of.absorptionState == .bullishAbsorption ? .long : .short
        } else if signalDirection != .neutral {
            proDir = signalDirection
        } else if let pos = positioning, pos.provenance == .okxFundingOI, pos.proDirection != .neutral {
            proDir = pos.proDirection
        } else if ict.currentStructureBias != .neutral {
            proDir = ict.currentStructureBias
        } else if let pos = positioning {
            proDir = pos.proDirection
        }

        var retailDir: TradeDirection = .neutral
        if let trap = latestTrap {
            retailDir = trap.direction.trappedRetailDirection
        } else if let pos = positioning, pos.retailCrowdDirection != .neutral {
            retailDir = pos.retailCrowdDirection
        } else if let of = activeOrderFlow, of.absorptionState.isDetected {
            retailDir = of.absorptionState == .bullishAbsorption ? .short : .long
        } else if let sweep = ict.liquiditySweeps.last {
            retailDir = sweep.reversalDirection.opposite
        } else if let dz = ict.dealingZone {
            retailDir = (dz == .premium) ? .long : (dz == .discount ? .short : .neutral)
        }

        if macroAligns == false && macroLabel != nil {
            badges.append(positioning?.provenance == .cftcCOT ? "Counter-Trend vs Macro COT" : "Counter-Trend vs OKX Flow")
        }

        // 6. Compose concrete 3-part narrative grounded purely in triggered & enabled facts
        let whatHappened: String
        let beginnerPsych: String
        let proPsych: String
        let minActiveCount = activeProfile.map { max(1, min(3, $0.enabledCoreCount)) } ?? 3

        switch category {
        case .trapAlert:
            if let trap = latestTrap {
                whatHappened = "\(trap.direction.rawValue) [\(trap.state.rawValue.uppercased())]: \(trap.detail)"
                switch trap.triggerKind {
                case .oslerRoundNumberSweep, .liquiditySwingSweep:
                    beginnerPsych = "Retail stop orders clustered at \(formatPrice(trap.level)) were triggered on the pierce (\(String(format: "%.2f", trap.pierceATRMultiple))x ATR), while breakout chasers entered \(trap.direction.trappedRetailDirection.rawValue.uppercased()) right into institutional supply/demand."
                    proPsych = "Smart money absorbed the clustered stop liquidity beyond \(formatPrice(trap.level)) and closed back inside range, leaning \(trap.direction.institutionalDirection.rawValue.uppercased()) while underwater breakout traders create a disposition breakeven wall."
                case .attentionFOMOSpike:
                    let volNote = rvol.map { String(format: "%.1fx RVOL", $0) } ?? "parabolic range expansion"
                    beginnerPsych = "Attention-driven retail FOMO (\(volNote)) chased extended price far from EMA-20 equilibrium, entering late into exhaustion."
                    proPsych = "Institutions faded the overcrowded attention spike into retail market orders, positioning \(trap.direction.institutionalDirection.rawValue.uppercased()) for mean reversion."
                case .postNewsWhipsawTrap:
                    beginnerPsych = "Beginners chased the initial post-release knee-jerk candle without waiting for a closed structure bar, getting caught in wide spreads and whipsaw."
                    proPsych = "Desks swept resting stops on the initial macro spike and faded the emotional imbalance back through the pre-news open."
                }
            } else {
                whatHappened = positioning?.summary ?? "Behavioral trap condition triggered by positioning divergence."
                beginnerPsych = "Retail positioning is heavily skewed \(retailDir.rawValue.uppercased()) against structural rejection."
                proPsych = "Institutional flow favors \(proDir.rawValue.uppercased()) liquidity absorption."
            }

        case .strongSignal:
            var facts: [String] = []
            if let brk = ict.structureBreaks.last {
                facts.append("\(brk.kind.rawValue) \(brk.direction.rawValue.uppercased()) at \(formatPrice(brk.brokenLevel))")
            }
            if let trap = latestTrap, trap.direction.institutionalDirection == signalDirection {
                facts.append("\(trap.direction.rawValue) (\(trap.triggerKind.rawValue))")
            }
            if let of = activeOrderFlow {
                facts.append(of.summary)
            }
            if let pos = positioning {
                facts.append(pos.summary)
            }
            if let macro = macroImpulse {
                facts.append(macro.headlineStrip)
            }
            if let news = newsCatalyst, news.matchingHeadlinesCount > 0 {
                facts.append(news.summary)
            }
            whatHappened = facts.isEmpty
                ? "Closed-bar active strategy confluence aligned \(signalDirection.rawValue.uppercased()) in \(regime.badgeLabel) regime."
                : facts.joined(separator: " · ")

            if let of = activeOrderFlow, of.absorptionState.isDetected {
                let aggDir = of.absorptionState == .bullishAbsorption ? "SELL" : "BUY"
                beginnerPsych = "Aggressive market \(aggDir) orders hammered the tape (\(String(format: "CVD %+.0f%%", of.cvdRatio * 100))) without breaking price through, trapping impatient breakout chasers."
            } else if retailDir != .neutral && retailDir != signalDirection {
                beginnerPsych = "Retail crowd is leaning \(retailDir.rawValue.uppercased()) (chasing swept stops or opposing liquidity), supplying counterparty liquidity for the \(signalDirection.rawValue.uppercased()) move."
            } else if let dz = ict.dealingZone {
                beginnerPsych = "Beginners typically hesitate in \(dz.rawValue) after a pullback or wait until price is already extended away from value."
            } else {
                beginnerPsych = "Retail participants react to impulsive ticks instead of waiting for closed-bar confirmation from your enabled strategy rules."
            }

            if let of = activeOrderFlow, let warn = of.warningNote {
                proPsych = "Closed structure supports \(signalDirection.rawValue.uppercased()), but live crypto tape flags caution: \(warn). Manage risk conservatively."
            } else if let pos = positioning, let mDir = macroDir, let aligns = macroAligns {
                if aligns {
                    proPsych = "Intraday institutional flow AND \(macroLabel ?? pos.provenance.rawValue) align \(signalDirection.rawValue.uppercased()) with defined invalidation and \(signalDirection == .long ? "demand" : "supply") backing."
                } else {
                    proPsych = "Intraday institutional flow confirms \(signalDirection.rawValue.uppercased()) on closed structure; note \(macroLabel ?? pos.provenance.rawValue) sits \(mDir.rawValue.uppercased()) (counter-trend — respect disciplined targets)."
                }
            } else {
                proPsych = "Institutional execution confirmed \(signalDirection.rawValue.uppercased()) on closed bars with asymmetric R:R beyond invalidation liquidity."
            }

        case .weakSignal:
            let reasonsText = rejectionReasons.isEmpty
                ? "Insufficient alignment among your enabled strategies."
                : rejectionReasons.joined(separator: "; ")
            whatHappened = "Filtered setup (\(signalDirection.rawValue.uppercased())): \(reasonsText)"
            beginnerPsych = "Beginners force entries on partial setups without waiting for \(minActiveCount)+ enabled confirmations, R:R floor, or clean regime/news clearance."
            proPsych = "Institutional desks stand aside when edge is diluted (\(reasonsText)) and preserve capital for clean asymmetric setups."
        }

        var seenBadges = Set<String>()
        let uniqueBadges = badges.filter { seenBadges.insert($0).inserted }

        return PsychologyReport(
            signalCategory: category,
            proDirection: proDir,
            retailCrowdDirection: retailDir,
            provenanceBadge: provenance.rawValue,
            whatHappened: whatHappened,
            beginnerPsychology: beginnerPsych,
            proPsychology: proPsych,
            behavioralBadges: uniqueBadges,
            evidence: evidence,
            macroPositioningDirection: macroDir,
            macroPositioningLabel: macroLabel,
            macroAlignsWithSetup: macroAligns
        )
    }

    /// Timeframe-aware healthy daily signal cadence threshold (used for overtrading / cadence coaching).
    public static func healthyDailyCadenceLimit(for timeframe: Timeframe) -> Int {
        switch timeframe {
        case .m15: return 12
        case .m30: return 8
        case .h1: return 6
        case .h4: return 3
        case .d1: return 2
        }
    }

    /// Adaptive trader-level behavioral audit driven strictly by the user's active `ActiveStrategyProfile`,
    /// historical outcome stream, and automatic `TrackedJournalTrade` entries.
    ///
    /// - **Rule-Consistent Discipline:** Scores adherence strictly against currently enabled strategies.
    /// - **Filter-Hopping Detection:** Detects repeated switches of non-empty `activeStrategyProfileKey`
    ///   immediately following losing trades (explicitly ignoring the one-time upgrade transition from
    ///   `"legacy_baseline"` to a real profile key).
    /// - **Order Flow Conflict Coaching (Crypto Only, when ON):** Flags crypto trades taken against
    ///   strong opposing Order Flow (`orderFlowStatus == "conflicting"`) and quantifies their R:R impact.
    /// - **Timeframe Cadence Audit:** Evaluates rolling 24h trade frequency against `entryTimeframe` thresholds (`.m30` tuned between `.m15` and `.h1`).
    /// - **Confluence Breadth Insight:** Surfaces calm guidance when narrowed down to 1 core strategy.
    public static func buildBehavioralAudit(
        outcomes: [SignalOutcomeRecord],
        journalEntries: [TrackedJournalTrade] = [],
        activeProfile: ActiveStrategyProfile,
        marketClass: MarketClass? = nil,
        entryTimeframe: Timeframe = .h1
    ) -> TraderPsychologyCoachReport {
        var insights: [TraderPsychologyInsight] = []

        // 1. Filter-Hopping Detection (chronological resolved records)
        struct ChronologicalTrade {
            let timestamp: TimeInterval
            let profileKey: String
            let isLoss: Bool
            let isCrypto: Bool
            let orderFlowStatus: String
            let rMultiple: Double
        }

        var timeline: [ChronologicalTrade] = []
        var seenTradeKeys: Set<String> = []
        for rec in outcomes where rec.isResolved {
            seenTradeKeys.insert(rec.signalId)
            if let tf = rec.timeframe, let barClose = rec.entryBarCloseEpochSeconds {
                let barOpen = Int((barClose - tf.seconds).rounded())
                seenTradeKeys.insert("\(rec.symbol)|\(tf.rawValue)|\(barOpen)")
            }
            timeline.append(ChronologicalTrade(
                timestamp: rec.resolvedAtEpochSeconds ?? rec.entryBarCloseEpochSeconds ?? 0,
                profileKey: ActiveStrategyProfile.normalizedKey(rec.activeStrategyProfileKey),
                isLoss: rec.status == .hitSL,
                isCrypto: rec.marketClass == .crypto,
                orderFlowStatus: rec.orderFlowStatus,
                rMultiple: rec.rMultiple
            ))
        }
        for entry in journalEntries where entry.status.isCountedWin || entry.status.isCountedLoss {
            let barKey = "\(entry.symbol)|\(entry.timeframe.rawValue)|\(Int(entry.signalBarTimestamp.rounded()))"
            guard !seenTradeKeys.contains(entry.id), !seenTradeKeys.contains(barKey) else { continue }
            seenTradeKeys.insert(entry.id)
            seenTradeKeys.insert(barKey)
            timeline.append(ChronologicalTrade(
                timestamp: entry.closedAt ?? entry.tp1HitAt ?? entry.createdAt,
                profileKey: entry.effectiveStrategyProfileKey,
                isLoss: entry.status.isCountedLoss,
                isCrypto: entry.assetClass == .crypto,
                orderFlowStatus: entry.orderFlowStatus,
                rMultiple: entry.effectiveRMultiple
            ))
        }
        timeline.sort { $0.timestamp < $1.timestamp }

        var postLossSwitches = 0
        if timeline.count >= 2 {
            for idx in 1..<timeline.count {
                let prev = timeline[idx - 1]
                let curr = timeline[idx]
                // Explicitly ignore the one-time migration transition from "legacy_baseline" to a real profile key
                guard prev.profileKey != ActiveStrategyProfile.legacyBaselineKey,
                      curr.profileKey != ActiveStrategyProfile.legacyBaselineKey
                else { continue }
                if prev.isLoss && curr.profileKey != prev.profileKey {
                    postLossSwitches += 1
                }
            }
        }
        let filterHoppingDetected = postLossSwitches >= 2
        if filterHoppingDetected {
            insights.append(TraderPsychologyInsight(
                id: "filter_hopping",
                title: "Strategy Filter-Hopping Detected",
                detail: "You switched active strategy combinations immediately after \(postLossSwitches) losing trades. Let a strategy profile accumulate at least 15–20 resolved setups before judging edge.",
                severity: .caution
            ))
        } else if timeline.count >= 5 {
            insights.append(TraderPsychologyInsight(
                id: "profile_consistency",
                title: "Consistent Rule Execution",
                detail: "You are sticking cleanly to your chosen strategy profile without reactive post-loss rule switching.",
                severity: .positive
            ))
        }

        // 2. Order Flow Conflict Coaching (Crypto Only, when Order Flow is ON — never lecture on Forex/TradFi)
        let cryptoTrades = timeline.filter(\.isCrypto)
        let conflictingOF = cryptoTrades.filter { $0.orderFlowStatus == OrderFlowAlignment.conflicting.rawValue }
        let alignedOF = cryptoTrades.filter { $0.orderFlowStatus == OrderFlowAlignment.aligned.rawValue }

        let conflictingAvgR: Double? = conflictingOF.isEmpty
            ? nil
            : conflictingOF.reduce(0.0) { $0 + $1.rMultiple } / Double(conflictingOF.count)
        let alignedAvgR: Double? = alignedOF.isEmpty
            ? nil
            : alignedOF.reduce(0.0) { $0 + $1.rMultiple } / Double(alignedOF.count)

        let shouldCoachOrderFlow = activeProfile.isOrderFlowEnabled && (marketClass == nil || marketClass == .crypto)
        if shouldCoachOrderFlow && !conflictingOF.isEmpty {
            let confStr = conflictingAvgR.map { String(format: "%+.2fR", $0) } ?? "N/A"
            let alignNote = alignedAvgR.map { " vs \(String(format: "%+.2fR", $0)) when aligned" } ?? ""
            insights.append(TraderPsychologyInsight(
                id: "orderflow_conflict_coaching",
                title: "Crypto Entries Against Order Flow",
                detail: "\(conflictingOF.count) tracked crypto setup(s) were taken against conflicting live Order Flow (avg \(confStr)\(alignNote)). Waiting for passive absorption or wall clearance can protect R:R.",
                severity: .caution
            ))
        } else if shouldCoachOrderFlow && alignedOF.count >= 3, let avg = alignedAvgR {
            insights.append(TraderPsychologyInsight(
                id: "orderflow_aligned_edge",
                title: "Crypto Order Flow Alignment",
                detail: "\(alignedOF.count) crypto setup(s) aligned with live Order Flow averaged \(String(format: "%+.2fR", avg)).",
                severity: avg >= 0 ? .positive : .neutral
            ))
        }

        // 3. Timeframe-Aware Cadence Check (tuned for 15m / 30m / 1H / 4H / 1D)
        let cadenceLimit = healthyDailyCadenceLimit(for: entryTimeframe)
        if let latestTs = timeline.last?.timestamp, latestTs > 0 {
            let recent24hCount = timeline.filter { latestTs - $0.timestamp <= 86_400 }.count
            if recent24hCount > cadenceLimit {
                insights.append(TraderPsychologyInsight(
                    id: "cadence_overtrading",
                    title: "Elevated \(entryTimeframe.displayLabel) Setup Cadence",
                    detail: "\(recent24hCount) resolved setups in 24h exceeds the typical \(entryTimeframe.displayLabel) cadence ceiling (\(cadenceLimit)/day). Prioritize A+ killzone alignment over volume.",
                    severity: .caution
                ))
            }
        }

        // 4. Confluence Breadth Insight (calm feedback strictly on currently enabled core strategies)
        let coreCount = activeProfile.enabledCoreCount
        if coreCount == 1 {
            insights.append(TraderPsychologyInsight(
                id: "breadth_single_core",
                title: "Single-Strategy Mode (Higher Noise Risk)",
                detail: "Only 1 core price-action strategy is enabled. Single-module setups fire more often but carry higher whipsaw noise — consider pairing at least 2 independent modules.",
                severity: .caution
            ))
        } else if coreCount >= 4 {
            insights.append(TraderPsychologyInsight(
                id: "breadth_multi_module",
                title: "High-Confluence Selectivity",
                detail: "\(coreCount) core modules are active, filtering out low-conviction noise in favor of multi-factor alignment.",
                severity: .positive
            ))
        } else if coreCount >= 2 {
            insights.append(TraderPsychologyInsight(
                id: "breadth_balanced",
                title: "Focused Strategy Profile",
                detail: "\(coreCount) core modules active — balanced selectivity aligned with your current rules.",
                severity: .neutral
            ))
        }

        // 5. Rule-Consistent Discipline Score (0...100) evaluated strictly against active rules
        var discipline = 90.0
        if filterHoppingDetected {
            discipline -= min(30.0, Double(postLossSwitches) * 9.0)
        }
        if shouldCoachOrderFlow && !conflictingOF.isEmpty {
            let ratio = Double(conflictingOF.count) / Double(max(1, cryptoTrades.count))
            discipline -= min(25.0, ratio * 35.0)
        }
        if coreCount == 1 {
            discipline -= 6.0
        } else if coreCount >= 3 && !filterHoppingDetected {
            discipline += 5.0
        }
        let clampedDiscipline = min(100.0, max(10.0, discipline))

        return TraderPsychologyCoachReport(
            disciplineScorePercent: clampedDiscipline,
            activeProfileKey: activeProfile.profileKey,
            enabledCoreCount: coreCount,
            filterHoppingDetected: filterHoppingDetected,
            filterHopSwitchCount: postLossSwitches,
            conflictingOrderFlowTrades: conflictingOF.count,
            conflictingOrderFlowAvgR: conflictingAvgR,
            alignedOrderFlowAvgR: alignedAvgR,
            insights: insights
        )
    }

    private static func formatPrice(_ value: Double) -> String {
        ChartPricePrecision.resolve(symbol: "", referencePrice: value).format(value)
    }
}
