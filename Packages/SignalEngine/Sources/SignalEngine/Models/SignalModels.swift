import Foundation

public struct TradeLevels: Codable, Sendable, Equatable, Hashable {
    public let entryLow: Double
    public let entryHigh: Double
    public let entryMid: Double
    public let stopLoss: Double
    public let tp1: Double
    public let tp2: Double
    public let riskPercent: Double
    public let reward1Percent: Double
    public let reward2Percent: Double
    public let riskRewardRatio: Double
    public let tp2RiskRewardRatio: Double
    public let isTP2Enabled: Bool

    public init(
        entryLow: Double,
        entryHigh: Double,
        entryMid: Double,
        stopLoss: Double,
        tp1: Double,
        tp2: Double,
        riskPercent: Double,
        reward1Percent: Double,
        reward2Percent: Double,
        riskRewardRatio: Double,
        tp2RiskRewardRatio: Double,
        isTP2Enabled: Bool = true
    ) {
        self.entryLow = entryLow
        self.entryHigh = entryHigh
        self.entryMid = entryMid
        self.stopLoss = stopLoss
        self.tp1 = tp1
        self.tp2 = tp2
        self.riskPercent = riskPercent
        self.reward1Percent = reward1Percent
        self.reward2Percent = reward2Percent
        self.riskRewardRatio = riskRewardRatio
        self.tp2RiskRewardRatio = tp2RiskRewardRatio
        self.isTP2Enabled = isTP2Enabled
    }

    enum CodingKeys: String, CodingKey {
        case entryLow, entryHigh, entryMid, stopLoss, tp1, tp2
        case riskPercent, reward1Percent, reward2Percent
        case riskRewardRatio, tp2RiskRewardRatio, isTP2Enabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entryLow = try c.decode(Double.self, forKey: .entryLow)
        entryHigh = try c.decode(Double.self, forKey: .entryHigh)
        entryMid = try c.decode(Double.self, forKey: .entryMid)
        stopLoss = try c.decode(Double.self, forKey: .stopLoss)
        tp1 = try c.decode(Double.self, forKey: .tp1)
        tp2 = try c.decode(Double.self, forKey: .tp2)
        riskPercent = try c.decode(Double.self, forKey: .riskPercent)
        reward1Percent = try c.decode(Double.self, forKey: .reward1Percent)
        reward2Percent = try c.decode(Double.self, forKey: .reward2Percent)
        riskRewardRatio = try c.decode(Double.self, forKey: .riskRewardRatio)
        tp2RiskRewardRatio = try c.decode(Double.self, forKey: .tp2RiskRewardRatio)
        isTP2Enabled = (try? c.decodeIfPresent(Bool.self, forKey: .isTP2Enabled)) ?? true
    }
}

public struct StrategyContribution: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let group: StrategyGroup
    public let direction: TradeDirection
    public let weight: Double
    public let historicalWinRate: Double
    public let detail: String

    public init(
        id: String,
        name: String,
        group: StrategyGroup,
        direction: TradeDirection,
        weight: Double,
        historicalWinRate: Double,
        detail: String
    ) {
        self.id = id
        self.name = name
        self.group = group
        self.direction = direction
        self.weight = weight
        self.historicalWinRate = historicalWinRate
        self.detail = detail
    }
}

public struct PriceZoneOverlay: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let label: String
    public let kind: ZoneKind
    public let direction: TradeDirection
    public let top: Double
    public let bottom: Double
    public let startBarIndex: Int

    public enum ZoneKind: String, Codable, Sendable, Equatable, Hashable {
        case fvg
        case orderBlock
        case liquidityLevel
    }

    public init(
        id: String,
        label: String,
        kind: ZoneKind,
        direction: TradeDirection,
        top: Double,
        bottom: Double,
        startBarIndex: Int
    ) {
        self.id = id
        self.label = label
        self.kind = kind
        self.direction = direction
        self.top = top
        self.bottom = bottom
        self.startBarIndex = startBarIndex
    }
}

public struct ChartOverlayData: Codable, Sendable, Equatable, Hashable {
    public let zones: [PriceZoneOverlay]
    public let traps: [BehavioralTrap]
    public let equilibriumPrice: Double?
    public let ema20: Double?
    public let ema50: Double?
    public let ema200: Double?

    public init(
        zones: [PriceZoneOverlay] = [],
        traps: [BehavioralTrap] = [],
        equilibriumPrice: Double? = nil,
        ema20: Double? = nil,
        ema50: Double? = nil,
        ema200: Double? = nil
    ) {
        self.zones = zones
        self.traps = traps
        self.equilibriumPrice = equilibriumPrice
        self.ema20 = ema20
        self.ema50 = ema50
        self.ema200 = ema200
    }
}

public struct ReflexJudgment: Codable, Sendable, Equatable, Hashable {
    public let regime: String
    public let direction: TradeDirection
    public let setupQuality: Int
    public let confidence: Double
    public let riskState: RiskState
    public let agree: Bool
    public let catalystBias: String
    public let invalidationCheck: String

    enum CodingKeys: String, CodingKey {
        case regime
        case direction
        case setupQuality = "setup_quality"
        case confidence
        case riskState = "risk_state"
        case agree
        case catalystBias = "catalyst_bias"
        case invalidationCheck = "invalidation_check"
    }

    public init(
        regime: String,
        direction: TradeDirection,
        setupQuality: Int,
        confidence: Double,
        riskState: RiskState,
        agree: Bool,
        catalystBias: String,
        invalidationCheck: String
    ) {
        self.regime = regime
        self.direction = direction
        self.setupQuality = setupQuality
        self.confidence = confidence
        self.riskState = riskState
        self.agree = agree
        self.catalystBias = catalystBias
        self.invalidationCheck = invalidationCheck
    }

    /// Hard confirmation rule enforced purely in deterministic Swift code.
    public func isConfirmedByCodeRule(minimumConfidence: Double = 0.80) -> Bool {
        agree && setupQuality >= 2 && confidence >= minimumConfidence && riskState == .safe
    }
}

public struct SignalStrengthBreakdown: Codable, Sendable, Equatable, Hashable {
    public let technicalScore: Double
    public let psychologyScore: Double
    public let newsMacroScore: Double
    public let regimeRiskAdjustment: Double
    public let finalConfidencePercent: Double
    public let strengthLabel: String
    public let notes: [String]

    public init(
        technicalScore: Double,
        psychologyScore: Double,
        newsMacroScore: Double,
        regimeRiskAdjustment: Double,
        finalConfidencePercent: Double,
        strengthLabel: String,
        notes: [String] = []
    ) {
        self.technicalScore = technicalScore
        self.psychologyScore = psychologyScore
        self.newsMacroScore = newsMacroScore
        self.regimeRiskAdjustment = regimeRiskAdjustment
        self.finalConfidencePercent = finalConfidencePercent
        self.strengthLabel = strengthLabel
        self.notes = notes
    }
}

public struct TradeSignal: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let fingerprint: String
    public let symbol: String
    public let displayName: String
    public let marketClass: MarketClass
    public let timeframe: Timeframe
    public let htfTimeframe: Timeframe
    public let category: SignalCategory
    public let direction: TradeDirection
    public let trapDirection: TrapDirection?
    public let tier: SignalTier
    public let confidencePercent: Double
    public let regime: MarketRegime
    public let riskState: RiskState
    public let killzone: KillzoneSession
    public let htfBias: TradeDirection
    public let generatedAtEpochSeconds: TimeInterval
    public let barCloseEpochSeconds: TimeInterval
    public let levels: TradeLevels?
    public let alignedStrategies: [StrategyContribution]
    public let rejectionReasons: [String]
    public let psychologyReport: PsychologyReport
    public let preNewsBadge: String?
    public let postNewsCatalystBadge: String?
    public let overlays: ChartOverlayData
    public let recentCandles: [Candle]
    public let aiJudgment: ReflexJudgment?
    public let aiConfirmed: Bool
    public let dataProvider: String
    public let isMarketClosedSnapshot: Bool
    public let marketClosedReason: String?
    public let strengthBreakdown: SignalStrengthBreakdown?
    /// Display-only Platt-calibrated win probability (nil until >= 100 resolved filled trades).
    /// NEVER replaces `confidencePercent` in the `minimumConfidencePercent` gate.
    public let calibratedProbability: Double?
    public let calibrationSampleCount: Int?

    public init(
        id: String,
        fingerprint: String,
        symbol: String,
        displayName: String,
        marketClass: MarketClass,
        timeframe: Timeframe,
        htfTimeframe: Timeframe,
        category: SignalCategory,
        direction: TradeDirection,
        trapDirection: TrapDirection? = nil,
        tier: SignalTier,
        confidencePercent: Double,
        regime: MarketRegime,
        riskState: RiskState,
        killzone: KillzoneSession,
        htfBias: TradeDirection,
        generatedAtEpochSeconds: TimeInterval,
        barCloseEpochSeconds: TimeInterval,
        levels: TradeLevels?,
        alignedStrategies: [StrategyContribution],
        rejectionReasons: [String],
        psychologyReport: PsychologyReport,
        preNewsBadge: String? = nil,
        postNewsCatalystBadge: String? = nil,
        overlays: ChartOverlayData = ChartOverlayData(),
        recentCandles: [Candle] = [],
        aiJudgment: ReflexJudgment? = nil,
        aiConfirmed: Bool = false,
        dataProvider: String,
        isMarketClosedSnapshot: Bool = false,
        marketClosedReason: String? = nil,
        strengthBreakdown: SignalStrengthBreakdown? = nil,
        calibratedProbability: Double? = nil,
        calibrationSampleCount: Int? = nil
    ) {
        self.id = id
        self.fingerprint = fingerprint
        self.symbol = symbol
        self.displayName = displayName
        self.marketClass = marketClass
        self.timeframe = timeframe
        self.htfTimeframe = htfTimeframe
        self.category = category
        self.direction = direction
        self.trapDirection = trapDirection
        self.tier = tier
        self.confidencePercent = confidencePercent
        self.regime = regime
        self.riskState = riskState
        self.killzone = killzone
        self.htfBias = htfBias
        self.generatedAtEpochSeconds = generatedAtEpochSeconds
        self.barCloseEpochSeconds = barCloseEpochSeconds
        self.levels = levels
        self.alignedStrategies = alignedStrategies
        self.rejectionReasons = rejectionReasons
        self.psychologyReport = psychologyReport
        self.preNewsBadge = preNewsBadge
        self.postNewsCatalystBadge = postNewsCatalystBadge
        self.overlays = overlays
        self.recentCandles = recentCandles
        self.aiJudgment = aiJudgment
        self.aiConfirmed = aiConfirmed
        self.dataProvider = dataProvider
        self.isMarketClosedSnapshot = isMarketClosedSnapshot
        self.marketClosedReason = marketClosedReason
        self.strengthBreakdown = strengthBreakdown
        self.calibratedProbability = calibratedProbability
        self.calibrationSampleCount = calibrationSampleCount
    }

    enum CodingKeys: String, CodingKey {
        case id, fingerprint, symbol, displayName, marketClass, timeframe, htfTimeframe
        case category, direction, trapDirection, tier, confidencePercent, regime, riskState
        case killzone, htfBias, generatedAtEpochSeconds, barCloseEpochSeconds, levels
        case alignedStrategies, rejectionReasons, psychologyReport, preNewsBadge
        case postNewsCatalystBadge, overlays, recentCandles, aiJudgment, aiConfirmed
        case dataProvider, isMarketClosedSnapshot, marketClosedReason, strengthBreakdown
        case calibratedProbability, calibrationSampleCount
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        fingerprint = try c.decode(String.self, forKey: .fingerprint)
        symbol = try c.decode(String.self, forKey: .symbol)
        displayName = try c.decode(String.self, forKey: .displayName)
        marketClass = try c.decode(MarketClass.self, forKey: .marketClass)
        timeframe = try c.decode(Timeframe.self, forKey: .timeframe)
        htfTimeframe = try c.decode(Timeframe.self, forKey: .htfTimeframe)
        category = try c.decode(SignalCategory.self, forKey: .category)
        direction = try c.decode(TradeDirection.self, forKey: .direction)
        trapDirection = try c.decodeIfPresent(TrapDirection.self, forKey: .trapDirection)
        tier = try c.decode(SignalTier.self, forKey: .tier)
        confidencePercent = try c.decode(Double.self, forKey: .confidencePercent)
        regime = try c.decode(MarketRegime.self, forKey: .regime)
        riskState = try c.decode(RiskState.self, forKey: .riskState)
        killzone = try c.decode(KillzoneSession.self, forKey: .killzone)
        htfBias = try c.decode(TradeDirection.self, forKey: .htfBias)
        generatedAtEpochSeconds = try c.decode(TimeInterval.self, forKey: .generatedAtEpochSeconds)
        barCloseEpochSeconds = try c.decode(TimeInterval.self, forKey: .barCloseEpochSeconds)
        levels = try c.decodeIfPresent(TradeLevels.self, forKey: .levels)
        alignedStrategies = (try? c.decodeIfPresent([StrategyContribution].self, forKey: .alignedStrategies)) ?? []
        rejectionReasons = (try? c.decodeIfPresent([String].self, forKey: .rejectionReasons)) ?? []
        psychologyReport = try c.decode(PsychologyReport.self, forKey: .psychologyReport)
        preNewsBadge = try c.decodeIfPresent(String.self, forKey: .preNewsBadge)
        postNewsCatalystBadge = try c.decodeIfPresent(String.self, forKey: .postNewsCatalystBadge)
        overlays = (try? c.decodeIfPresent(ChartOverlayData.self, forKey: .overlays)) ?? ChartOverlayData()
        recentCandles = (try? c.decodeIfPresent([Candle].self, forKey: .recentCandles)) ?? []
        aiJudgment = try c.decodeIfPresent(ReflexJudgment.self, forKey: .aiJudgment)
        aiConfirmed = (try? c.decodeIfPresent(Bool.self, forKey: .aiConfirmed)) ?? false
        dataProvider = try c.decode(String.self, forKey: .dataProvider)
        isMarketClosedSnapshot = (try? c.decodeIfPresent(Bool.self, forKey: .isMarketClosedSnapshot)) ?? false
        marketClosedReason = try c.decodeIfPresent(String.self, forKey: .marketClosedReason)
        strengthBreakdown = try c.decodeIfPresent(SignalStrengthBreakdown.self, forKey: .strengthBreakdown)
        calibratedProbability = try c.decodeIfPresent(Double.self, forKey: .calibratedProbability)
        calibrationSampleCount = try c.decodeIfPresent(Int.self, forKey: .calibrationSampleCount)
    }

    public func withAIJudgment(_ judgment: ReflexJudgment, threshold: Double) -> TradeSignal {
        TradeSignal(
            id: id,
            fingerprint: fingerprint,
            symbol: symbol,
            displayName: displayName,
            marketClass: marketClass,
            timeframe: timeframe,
            htfTimeframe: htfTimeframe,
            category: category,
            direction: direction,
            trapDirection: trapDirection,
            tier: tier,
            confidencePercent: confidencePercent,
            regime: regime,
            riskState: riskState,
            killzone: killzone,
            htfBias: htfBias,
            generatedAtEpochSeconds: generatedAtEpochSeconds,
            barCloseEpochSeconds: barCloseEpochSeconds,
            levels: levels,
            alignedStrategies: alignedStrategies,
            rejectionReasons: rejectionReasons,
            psychologyReport: psychologyReport,
            preNewsBadge: preNewsBadge,
            postNewsCatalystBadge: postNewsCatalystBadge,
            overlays: overlays,
            recentCandles: recentCandles,
            aiJudgment: judgment,
            aiConfirmed: judgment.isConfirmedByCodeRule(minimumConfidence: threshold),
            dataProvider: dataProvider,
            isMarketClosedSnapshot: isMarketClosedSnapshot,
            marketClosedReason: marketClosedReason,
            strengthBreakdown: strengthBreakdown,
            calibratedProbability: calibratedProbability,
            calibrationSampleCount: calibrationSampleCount
        )
    }

    /// Attaches display-only calibrated probability without altering raw `confidencePercent`, `category`, or gating.
    public func withCalibratedProbability(_ probability: Double?, sampleCount: Int?) -> TradeSignal {
        TradeSignal(
            id: id,
            fingerprint: fingerprint,
            symbol: symbol,
            displayName: displayName,
            marketClass: marketClass,
            timeframe: timeframe,
            htfTimeframe: htfTimeframe,
            category: category,
            direction: direction,
            trapDirection: trapDirection,
            tier: tier,
            confidencePercent: confidencePercent,
            regime: regime,
            riskState: riskState,
            killzone: killzone,
            htfBias: htfBias,
            generatedAtEpochSeconds: generatedAtEpochSeconds,
            barCloseEpochSeconds: barCloseEpochSeconds,
            levels: levels,
            alignedStrategies: alignedStrategies,
            rejectionReasons: rejectionReasons,
            psychologyReport: psychologyReport,
            preNewsBadge: preNewsBadge,
            postNewsCatalystBadge: postNewsCatalystBadge,
            overlays: overlays,
            recentCandles: recentCandles,
            aiJudgment: aiJudgment,
            aiConfirmed: aiConfirmed,
            dataProvider: dataProvider,
            isMarketClosedSnapshot: isMarketClosedSnapshot,
            marketClosedReason: marketClosedReason,
            strengthBreakdown: strengthBreakdown,
            calibratedProbability: probability,
            calibrationSampleCount: sampleCount
        )
    }

    public func formattedCopyText(decimals: Int) -> String {
        let fmt = "%.\(decimals)f"
        let header: String
        if let trap = trapDirection, category == .trapAlert {
            header = "CONFLUENCE \(trap.rawValue) | \(symbol) (\(timeframe.displayLabel))"
        } else {
            header = "CONFLUENCE \(direction.rawValue.uppercased()) | \(symbol) (\(timeframe.displayLabel))"
        }
        var lines: [String] = [
            header,
            "Confidence: \(Int(confidencePercent.rounded()))% (\(tier.displayName)) | Regime: \(regime.badgeLabel) | \(killzone.displayName)"
        ]
        if let lv = levels {
            lines.append("Entry Zone: \(String(format: fmt, lv.entryLow)) - \(String(format: fmt, lv.entryHigh))")
            lines.append("Stop Loss: \(String(format: fmt, lv.stopLoss)) (-\(String(format: "%.2f", lv.riskPercent))%)")
            lines.append("TP1: \(String(format: fmt, lv.tp1)) (+\(String(format: "%.2f", lv.reward1Percent))%) | R:R 1:\(String(format: "%.2f", lv.riskRewardRatio))")
            if lv.isTP2Enabled {
                lines.append("TP2: \(String(format: fmt, lv.tp2)) (+\(String(format: "%.2f", lv.reward2Percent))%)")
            }
        }
        lines.append("Pro vs Retail: Pro \(psychologyReport.proDirection.rawValue.uppercased()) vs Retail \(psychologyReport.retailCrowdDirection.rawValue.uppercased()) (\(psychologyReport.provenanceBadge))")
        lines.append("Note: \(psychologyReport.whatHappened)")
        return lines.joined(separator: "\n")
    }
}

public enum TradeLevelMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case structureATR = "Structure / ATR (Default)"
    case fixedPercent = "Fixed % Ratio"

    public var id: String { rawValue }

    public var shortLabel: String {
        switch self {
        case .structureATR: return "Structure/ATR"
        case .fixedPercent: return "Fixed %"
        }
    }
}

public enum StrategySelectionMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case defaultAll = "Default (All Enabled)"
    case custom = "Custom (Select Strategies)"
    case randomSubset = "Random Subset"

    public var id: String { rawValue }

    public var shortLabel: String {
        switch self {
        case .defaultAll: return "All Enabled"
        case .custom: return "Custom"
        case .randomSubset: return "Random Subset"
        }
    }
}

public enum CustomStrategyMatchRule: String, Codable, Sendable, CaseIterable, Identifiable {
    case anyWithMinConfluence = "Any Selected + Min Confluence"
    case requireAllSelected = "Require All Selected"

    public var id: String { rawValue }
}

/// Canonical 12 selectable trading strategies/concepts mapped 1:1 to deterministic `StrategyContribution.id` outputs.
public enum StrategyConcept: String, Codable, Sendable, CaseIterable, Hashable, Identifiable {
    case ictFVG = "ict_fvg"
    case ictOrderBlock = "ict_order_block"
    case ictBosMss = "ict_bos_mss"
    case ictLiquiditySweep = "ict_liquidity_sweep"
    case ictPremiumDiscount = "ict_premium_discount"
    case candlestickPatterns = "candlestick_patterns"
    case emaPullback = "momentum_ema_pullback"
    case rsiDivergence = "momentum_rsi_divergence"
    case rvolConfirmation = "momentum_rvol"
    case positioningFlow = "positioning_flow"
    case behavioralTraps = "behavioral_traps"
    case macroCatalyst = "macro_surprise_catalyst"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ictFVG: return "ICT Fair Value Gap (FVG)"
        case .ictOrderBlock: return "ICT Order Block (OB)"
        case .ictBosMss: return "ICT BOS / MSS Structure"
        case .ictLiquiditySweep: return "ICT Liquidity Sweep"
        case .ictPremiumDiscount: return "Premium / Discount EQ"
        case .candlestickPatterns: return "Candlestick Patterns"
        case .emaPullback: return "EMA Stack Pullback"
        case .rsiDivergence: return "RSI Divergence"
        case .rvolConfirmation: return "RVOL / ATR Squeeze"
        case .positioningFlow: return "Positioning (OKX / COT)"
        case .behavioralTraps: return "Behavioral Traps"
        case .macroCatalyst: return "Macro Surprise Catalyst"
        }
    }

    public var group: StrategyGroup {
        switch self {
        case .ictFVG, .ictOrderBlock, .ictBosMss, .ictLiquiditySweep, .ictPremiumDiscount:
            return .ictSmc
        case .candlestickPatterns:
            return .candlestick
        case .emaPullback, .rsiDivergence, .rvolConfirmation:
            return .trendMomentum
        case .positioningFlow, .behavioralTraps:
            return .behavioralTrap
        case .macroCatalyst:
            return .macroCatalyst
        }
    }

    public func matches(contributionId: String) -> Bool {
        let lower = contributionId.lowercased()
        switch self {
        case .ictFVG: return lower == "ict_fvg"
        case .ictOrderBlock: return lower == "ict_order_block"
        case .ictBosMss: return lower == "ict_bos" || lower == "ict_mss"
        case .ictLiquiditySweep: return lower == "ict_liquidity_sweep"
        case .ictPremiumDiscount: return lower == "ict_discount_eq" || lower == "ict_premium_eq"
        case .candlestickPatterns: return lower.hasPrefix("candle_")
        case .emaPullback: return lower == "momentum_ema_pullback"
        case .rsiDivergence: return lower == "momentum_rsi_divergence"
        case .rvolConfirmation: return lower == "momentum_rvol" || lower == "momentum_atr_squeeze"
        case .positioningFlow: return lower.hasPrefix("positioning_")
        case .behavioralTraps: return lower.hasPrefix("trap_")
        case .macroCatalyst: return lower == "macro_surprise_catalyst"
        }
    }
}

public struct EngineConfig: Codable, Sendable, Equatable {
    public var htfTimeframe: Timeframe
    public var entryTimeframe: Timeframe
    public var minimumConfidencePercent: Double
    public var minimumRiskReward: Double
    public var maxStopLossPercentCryptoStocks: Double
    public var maxStopLossPercentFXMetalsIndices: Double
    public var levelCalculationMode: TradeLevelMode
    public var fixedStopLossPercent: Double
    public var fixedTP1Percent: Double
    public var fixedTP2Percent: Double
    public var enableTP2Target: Bool
    public var minimumAlignedStrategies: Int
    public var enabledStrategyGroups: Set<StrategyGroup>
    public var strategySelectionMode: StrategySelectionMode
    public var selectedStrategyConcepts: Set<StrategyConcept>
    public var customStrategyMatchRule: CustomStrategyMatchRule
    public var pauseSignalsDuringPreNewsWindow: Bool
    public var preNewsBlackoutMinutesBefore: Int
    public var postNewsWhipsawMinutesAfter: Int
    public var suppressAlertsInCrisisRegime: Bool
    public var aiConfirmationThreshold: Double
    public var signalCooldownSeconds: TimeInterval
    public var historicalReliabilityWeights: [String: Double]

    public init(
        htfTimeframe: Timeframe = .h4,
        entryTimeframe: Timeframe = .h1,
        minimumConfidencePercent: Double = 70.0,
        minimumRiskReward: Double = 2.0,
        maxStopLossPercentCryptoStocks: Double = 3.0,
        maxStopLossPercentFXMetalsIndices: Double = 1.5,
        levelCalculationMode: TradeLevelMode = .structureATR,
        fixedStopLossPercent: Double = 1.0,
        fixedTP1Percent: Double = 2.0,
        fixedTP2Percent: Double = 3.5,
        enableTP2Target: Bool = true,
        minimumAlignedStrategies: Int = 3,
        enabledStrategyGroups: Set<StrategyGroup> = Set(StrategyGroup.allCases),
        strategySelectionMode: StrategySelectionMode = .defaultAll,
        selectedStrategyConcepts: Set<StrategyConcept> = Set(StrategyConcept.allCases),
        customStrategyMatchRule: CustomStrategyMatchRule = .anyWithMinConfluence,
        pauseSignalsDuringPreNewsWindow: Bool = true,
        preNewsBlackoutMinutesBefore: Int = 15,
        postNewsWhipsawMinutesAfter: Int = 5,
        suppressAlertsInCrisisRegime: Bool = true,
        aiConfirmationThreshold: Double = 0.80,
        signalCooldownSeconds: TimeInterval = 3_600,
        historicalReliabilityWeights: [String: Double] = [:]
    ) {
        self.htfTimeframe = htfTimeframe
        self.entryTimeframe = entryTimeframe
        self.minimumConfidencePercent = minimumConfidencePercent
        self.minimumRiskReward = minimumRiskReward
        self.maxStopLossPercentCryptoStocks = maxStopLossPercentCryptoStocks
        self.maxStopLossPercentFXMetalsIndices = maxStopLossPercentFXMetalsIndices
        self.levelCalculationMode = levelCalculationMode
        self.fixedStopLossPercent = fixedStopLossPercent
        self.fixedTP1Percent = fixedTP1Percent
        self.fixedTP2Percent = fixedTP2Percent
        self.enableTP2Target = enableTP2Target
        self.minimumAlignedStrategies = minimumAlignedStrategies
        self.enabledStrategyGroups = enabledStrategyGroups
        self.strategySelectionMode = strategySelectionMode
        self.selectedStrategyConcepts = selectedStrategyConcepts
        self.customStrategyMatchRule = customStrategyMatchRule
        self.pauseSignalsDuringPreNewsWindow = pauseSignalsDuringPreNewsWindow
        self.preNewsBlackoutMinutesBefore = preNewsBlackoutMinutesBefore
        self.postNewsWhipsawMinutesAfter = postNewsWhipsawMinutesAfter
        self.suppressAlertsInCrisisRegime = suppressAlertsInCrisisRegime
        self.aiConfirmationThreshold = aiConfirmationThreshold
        self.signalCooldownSeconds = signalCooldownSeconds
        self.historicalReliabilityWeights = historicalReliabilityWeights
    }

    public func maxStopLossPercent(for marketClass: MarketClass) -> Double {
        switch marketClass {
        case .crypto, .stocks:
            return maxStopLossPercentCryptoStocks
        case .forex, .metals, .indices:
            return maxStopLossPercentFXMetalsIndices
        }
    }
}
