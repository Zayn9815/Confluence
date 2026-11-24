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
        tp2RiskRewardRatio: Double
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
        isMarketClosedSnapshot: Bool = false
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
            isMarketClosedSnapshot: isMarketClosedSnapshot
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
            lines.append("TP2: \(String(format: fmt, lv.tp2)) (+\(String(format: "%.2f", lv.reward2Percent))%)")
        }
        lines.append("Pro vs Retail: Pro \(psychologyReport.proDirection.rawValue.uppercased()) vs Retail \(psychologyReport.retailCrowdDirection.rawValue.uppercased()) (\(psychologyReport.provenanceBadge))")
        lines.append("Note: \(psychologyReport.whatHappened)")
        return lines.joined(separator: "\n")
    }
}

public struct EngineConfig: Codable, Sendable, Equatable {
    public var htfTimeframe: Timeframe
    public var entryTimeframe: Timeframe
    public var minimumConfidencePercent: Double
    public var minimumRiskReward: Double
    public var maxStopLossPercentCryptoStocks: Double
    public var maxStopLossPercentFXMetalsIndices: Double
    public var minimumAlignedStrategies: Int
    public var enabledStrategyGroups: Set<StrategyGroup>
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
        minimumAlignedStrategies: Int = 3,
        enabledStrategyGroups: Set<StrategyGroup> = Set(StrategyGroup.allCases),
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
        self.minimumAlignedStrategies = minimumAlignedStrategies
        self.enabledStrategyGroups = enabledStrategyGroups
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
