import Foundation

public enum SignalLifecycleStatus: String, Codable, Sendable, Equatable {
    case pending = "PENDING"
    case filled = "FILLED"
    case notFilled = "NOT_FILLED"
    case invalidated = "INVALIDATED"
    case open = "OPEN"
    case resolved = "RESOLVED"
}

public enum SignalOutcomeStatus: String, Codable, Sendable, Equatable {
    case pending
    case open
    case hitTP2
    case hitTP1
    case hitSL
    case expired
    case notFilled
    case invalidated
}

public enum CalibrationWinDefinition: String, Codable, Sendable, CaseIterable, Identifiable {
    case tp1OrTp2 = "TP1 or TP2 = Win"
    case tp2Only = "TP2 Only = Win"

    public var id: String { rawValue }

    public var shortLabel: String {
        switch self {
        case .tp1OrTp2: return "TP1/TP2"
        case .tp2Only: return "TP2 Only"
        }
    }
}

public enum CalibrationCategoryScope: String, Codable, Sendable, CaseIterable, Identifiable {
    case strongOnly = "Strong Signals Only"
    case strongAndTraps = "Include Trap Alerts"
    case allEvaluated = "All Evaluated Setups"

    public var id: String { rawValue }

    public var shortLabel: String {
        switch self {
        case .strongOnly: return "Strong"
        case .strongAndTraps: return "Strong+Traps"
        case .allEvaluated: return "All"
        }
    }
}

public struct CalibrationFilterConfig: Codable, Sendable, Equatable {
    public var winDefinition: CalibrationWinDefinition
    public var categoryScope: CalibrationCategoryScope
    public var minimumConfidencePercent: Double
    public var minimumRiskReward: Double
    public var excludeLegacyImmediateFill: Bool

    public init(
        winDefinition: CalibrationWinDefinition = .tp1OrTp2,
        categoryScope: CalibrationCategoryScope = .strongOnly,
        minimumConfidencePercent: Double = 0.0,
        minimumRiskReward: Double = 0.0,
        excludeLegacyImmediateFill: Bool = false
    ) {
        self.winDefinition = winDefinition
        self.categoryScope = categoryScope
        self.minimumConfidencePercent = minimumConfidencePercent
        self.minimumRiskReward = minimumRiskReward
        self.excludeLegacyImmediateFill = excludeLegacyImmediateFill
    }

    enum CodingKeys: String, CodingKey {
        case winDefinition, categoryScope, minimumConfidencePercent, minimumRiskReward, excludeLegacyImmediateFill
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        winDefinition = (try? c.decodeIfPresent(CalibrationWinDefinition.self, forKey: .winDefinition)) ?? .tp1OrTp2
        categoryScope = (try? c.decodeIfPresent(CalibrationCategoryScope.self, forKey: .categoryScope)) ?? .strongOnly
        minimumConfidencePercent = (try? c.decodeIfPresent(Double.self, forKey: .minimumConfidencePercent)) ?? 0.0
        minimumRiskReward = (try? c.decodeIfPresent(Double.self, forKey: .minimumRiskReward)) ?? 0.0
        excludeLegacyImmediateFill = (try? c.decodeIfPresent(Bool.self, forKey: .excludeLegacyImmediateFill)) ?? false
    }

    /// Fixed un-cherry-pickable headline standard (v1.4): Strong Signals Only, TP1 or TP2 = Win,
    /// filled entries only, excluding pre-v1.4 `legacy-immediate-fill` records.
    public static let headlineFixed = CalibrationFilterConfig(
        winDefinition: .tp1OrTp2,
        categoryScope: .strongOnly,
        minimumConfidencePercent: 0.0,
        minimumRiskReward: 0.0,
        excludeLegacyImmediateFill: true
    )

    /// Default backwards-compatible config (counts Strong + Traps, TP1 or TP2 = Win, no conf/R:R floor).
    public static let legacyAll = CalibrationFilterConfig(
        winDefinition: .tp1OrTp2,
        categoryScope: .allEvaluated,
        minimumConfidencePercent: 0.0,
        minimumRiskReward: 0.0,
        excludeLegacyImmediateFill: false
    )

    public var summarySubtitle: String {
        var parts: [String] = [winDefinition.shortLabel, categoryScope.shortLabel]
        if excludeLegacyImmediateFill {
            parts.append("Filled v1.4+")
        }
        if minimumConfidencePercent > 0 {
            parts.append("≥\(Int(minimumConfidencePercent.rounded()))%")
        }
        if minimumRiskReward > 0 {
            parts.append("≥1:\(String(format: "%.1f", minimumRiskReward))")
        }
        return parts.joined(separator: " · ")
    }

    public func matchesCategory(_ category: SignalCategory) -> Bool {
        switch categoryScope {
        case .strongOnly: return category == .strongSignal
        case .strongAndTraps: return category == .strongSignal || category == .trapAlert
        case .allEvaluated: return true
        }
    }

    public func matchesRecordIgnoringLegacyFlag(_ record: SignalOutcomeRecord) -> Bool {
        guard matchesCategory(record.category) else { return false }
        let confPct = record.predictedProbability * 100.0
        if minimumConfidencePercent > 0 && confPct + 1e-6 < minimumConfidencePercent {
            return false
        }
        if minimumRiskReward > 0 {
            guard let rr = record.riskRewardRatio, rr + 1e-6 >= minimumRiskReward else {
                return false
            }
        }
        return true
    }

    public func matchesRecord(_ record: SignalOutcomeRecord) -> Bool {
        guard matchesRecordIgnoringLegacyFlag(record) else { return false }
        if excludeLegacyImmediateFill && record.effectiveIsLegacyImmediateFill {
            return false
        }
        return true
    }

    public func isCountedWin(_ status: SignalOutcomeStatus) -> Bool {
        switch winDefinition {
        case .tp1OrTp2: return status == .hitTP1 || status == .hitTP2
        case .tp2Only: return status == .hitTP2
        }
    }

    public func isCountedInWinRateDenominator(_ status: SignalOutcomeStatus) -> Bool {
        switch winDefinition {
        case .tp1OrTp2: return status == .hitTP1 || status == .hitTP2 || status == .hitSL
        case .tp2Only: return status == .hitTP2 || status == .hitSL // TP1 tracked separately as partial/breakeven
        }
    }
}

public struct SignalOutcomeRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String { signalId }
    public let signalId: String
    public let symbol: String
    public let marketClass: MarketClass
    public let category: SignalCategory
    public let direction: TradeDirection
    public let predictedProbability: Double
    public let status: SignalOutcomeStatus
    public let netReturnPercent: Double
    public let rMultiple: Double
    public let strategyIds: [String]
    public let hadMacroCatalyst: Bool
    public let resolvedAtEpochSeconds: TimeInterval?
    public let regime: MarketRegime?
    public let killzone: KillzoneSession?
    public let timeframe: Timeframe?
    public let dataProvider: String?
    public let riskRewardRatio: Double?
    public let entryBarCloseEpochSeconds: TimeInterval?
    public let lifecycleStatus: SignalLifecycleStatus?
    public let filledAtEpochSeconds: TimeInterval?
    public let fillWindowBars: Int?
    public let isLegacyImmediateFill: Bool?
    public let origin: SignalOrigin
    public let activeStrategyProfileKey: String
    public let enabledStrategyIDsCSV: String
    public let orderFlowStatus: String

    public init(
        signalId: String,
        symbol: String,
        marketClass: MarketClass,
        category: SignalCategory,
        direction: TradeDirection,
        predictedProbability: Double,
        status: SignalOutcomeStatus,
        netReturnPercent: Double,
        rMultiple: Double,
        strategyIds: [String],
        hadMacroCatalyst: Bool,
        resolvedAtEpochSeconds: TimeInterval?,
        regime: MarketRegime? = nil,
        killzone: KillzoneSession? = nil,
        timeframe: Timeframe? = nil,
        dataProvider: String? = nil,
        riskRewardRatio: Double? = nil,
        entryBarCloseEpochSeconds: TimeInterval? = nil,
        lifecycleStatus: SignalLifecycleStatus? = nil,
        filledAtEpochSeconds: TimeInterval? = nil,
        fillWindowBars: Int? = nil,
        isLegacyImmediateFill: Bool? = nil,
        origin: SignalOrigin = .scanner,
        activeStrategyProfileKey: String = "",
        enabledStrategyIDsCSV: String = "",
        orderFlowStatus: String = "off"
    ) {
        self.signalId = signalId
        self.symbol = symbol
        self.marketClass = marketClass
        self.category = category
        self.direction = direction
        self.predictedProbability = predictedProbability
        self.status = status
        self.netReturnPercent = netReturnPercent
        self.rMultiple = rMultiple
        self.strategyIds = strategyIds
        self.hadMacroCatalyst = hadMacroCatalyst
        self.resolvedAtEpochSeconds = resolvedAtEpochSeconds
        self.regime = regime
        self.killzone = killzone
        self.timeframe = timeframe
        self.dataProvider = dataProvider
        self.riskRewardRatio = riskRewardRatio
        self.entryBarCloseEpochSeconds = entryBarCloseEpochSeconds
        self.lifecycleStatus = lifecycleStatus
        self.filledAtEpochSeconds = filledAtEpochSeconds
        self.fillWindowBars = fillWindowBars
        self.isLegacyImmediateFill = isLegacyImmediateFill
        self.origin = origin
        self.activeStrategyProfileKey = activeStrategyProfileKey
        self.enabledStrategyIDsCSV = enabledStrategyIDsCSV
        self.orderFlowStatus = orderFlowStatus
    }

    enum CodingKeys: String, CodingKey {
        case signalId, symbol, marketClass, category, direction, predictedProbability
        case status, netReturnPercent, rMultiple, strategyIds, hadMacroCatalyst
        case resolvedAtEpochSeconds, regime, killzone, timeframe, dataProvider
        case riskRewardRatio, entryBarCloseEpochSeconds
        case lifecycleStatus, filledAtEpochSeconds, fillWindowBars, isLegacyImmediateFill
        case origin, activeStrategyProfileKey, enabledStrategyIDsCSV, orderFlowStatus
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        signalId = try c.decode(String.self, forKey: .signalId)
        symbol = try c.decode(String.self, forKey: .symbol)
        marketClass = try c.decode(MarketClass.self, forKey: .marketClass)
        category = try c.decode(SignalCategory.self, forKey: .category)
        direction = try c.decode(TradeDirection.self, forKey: .direction)
        predictedProbability = try c.decode(Double.self, forKey: .predictedProbability)
        status = try c.decode(SignalOutcomeStatus.self, forKey: .status)
        netReturnPercent = try c.decode(Double.self, forKey: .netReturnPercent)
        rMultiple = try c.decode(Double.self, forKey: .rMultiple)
        strategyIds = (try? c.decodeIfPresent([String].self, forKey: .strategyIds)) ?? []
        hadMacroCatalyst = (try? c.decodeIfPresent(Bool.self, forKey: .hadMacroCatalyst)) ?? false
        resolvedAtEpochSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .resolvedAtEpochSeconds)
        regime = try c.decodeIfPresent(MarketRegime.self, forKey: .regime)
        killzone = try c.decodeIfPresent(KillzoneSession.self, forKey: .killzone)
        timeframe = try c.decodeIfPresent(Timeframe.self, forKey: .timeframe)
        dataProvider = try c.decodeIfPresent(String.self, forKey: .dataProvider)
        riskRewardRatio = try c.decodeIfPresent(Double.self, forKey: .riskRewardRatio)
        entryBarCloseEpochSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .entryBarCloseEpochSeconds)
        lifecycleStatus = try c.decodeIfPresent(SignalLifecycleStatus.self, forKey: .lifecycleStatus)
        filledAtEpochSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .filledAtEpochSeconds)
        fillWindowBars = try c.decodeIfPresent(Int.self, forKey: .fillWindowBars)
        isLegacyImmediateFill = try c.decodeIfPresent(Bool.self, forKey: .isLegacyImmediateFill)
        origin = (try? c.decodeIfPresent(SignalOrigin.self, forKey: .origin)) ?? .scanner
        activeStrategyProfileKey = (try? c.decodeIfPresent(String.self, forKey: .activeStrategyProfileKey)) ?? ""
        enabledStrategyIDsCSV = (try? c.decodeIfPresent(String.self, forKey: .enabledStrategyIDsCSV)) ?? ""
        orderFlowStatus = (try? c.decodeIfPresent(String.self, forKey: .orderFlowStatus)) ?? "off"
    }

    /// Treats pre-upgrade records with empty `activeStrategyProfileKey` as `"legacy_baseline"`.
    public var effectiveStrategyProfileKey: String {
        ActiveStrategyProfile.normalizedKey(activeStrategyProfileKey)
    }

    public var isWin: Bool {
        status == .hitTP1 || status == .hitTP2
    }

    public var isResolved: Bool {
        status == .hitTP1 || status == .hitTP2 || status == .hitSL
    }

    public var isTerminal: Bool {
        switch status {
        case .hitTP1, .hitTP2, .hitSL, .expired, .notFilled, .invalidated:
            return true
        case .pending, .open:
            return false
        }
    }

    /// Pre-v1.4 records lacked `lifecycleStatus` & `isLegacyImmediateFill` and assumed immediate fill on bar close.
    public var effectiveIsLegacyImmediateFill: Bool {
        if let explicit = isLegacyImmediateFill {
            return explicit
        }
        return lifecycleStatus == nil
    }

    public var effectiveLifecycleStatus: SignalLifecycleStatus {
        if let explicit = lifecycleStatus {
            return explicit
        }
        switch status {
        case .pending: return .pending
        case .open: return .open
        case .notFilled: return .notFilled
        case .invalidated: return .invalidated
        case .hitTP1, .hitTP2, .hitSL, .expired: return .resolved
        }
    }
}

public struct StrategyAccuracyStat: Codable, Sendable, Equatable, Identifiable {
    public var id: String { strategyId }
    public let strategyId: String
    public let totalResolved: Int
    public let wins: Int
    public let winRate: Double
    public let expectancyR: Double
    public let winRateCI: WilsonInterval?

    public init(
        strategyId: String,
        totalResolved: Int,
        wins: Int,
        winRate: Double,
        expectancyR: Double,
        winRateCI: WilsonInterval? = nil
    ) {
        self.strategyId = strategyId
        self.totalResolved = totalResolved
        self.wins = wins
        self.winRate = winRate
        self.expectancyR = expectancyR
        self.winRateCI = winRateCI ?? WilsonInterval.compute(wins: wins, total: totalResolved)
    }
}

public struct MarketAccuracyStat: Codable, Sendable, Equatable {
    public let resolvedCount: Int
    public let wins: Int
    public let winRate: Double
    public let winRateCI: WilsonInterval?

    public init(resolvedCount: Int, wins: Int, winRate: Double, winRateCI: WilsonInterval? = nil) {
        self.resolvedCount = resolvedCount
        self.wins = wins
        self.winRate = winRate
        self.winRateCI = winRateCI ?? WilsonInterval.compute(wins: wins, total: resolvedCount)
    }
}

public struct StrategyDiagnosticBreakdown: Codable, Sendable, Equatable, Identifiable {
    public var id: String { strategyId }
    public let strategyId: String
    public let displayName: String
    public let totalSetups: Int
    public let wins: Int
    public let losses: Int
    public let winRate: Double
    public let expectancyR: Double
    public let brierContribution: Double
    public let bestPairs: [String]
    public let worstPairs: [String]
    public let bestRegimes: [String]
    public let worstRegimes: [String]
    public let winRateCI: WilsonInterval?

    public init(
        strategyId: String,
        displayName: String,
        totalSetups: Int,
        wins: Int,
        losses: Int,
        winRate: Double,
        expectancyR: Double,
        brierContribution: Double,
        bestPairs: [String],
        worstPairs: [String],
        bestRegimes: [String],
        worstRegimes: [String],
        winRateCI: WilsonInterval? = nil
    ) {
        self.strategyId = strategyId
        self.displayName = displayName
        self.totalSetups = totalSetups
        self.wins = wins
        self.losses = losses
        self.winRate = winRate
        self.expectancyR = expectancyR
        self.brierContribution = brierContribution
        self.bestPairs = bestPairs
        self.worstPairs = worstPairs
        self.bestRegimes = bestRegimes
        self.worstRegimes = worstRegimes
        self.winRateCI = winRateCI ?? WilsonInterval.compute(wins: wins, total: totalSetups)
    }
}

public enum TrapRespectOutcome: String, Codable, Sendable, Equatable {
    case pending = "PENDING"
    case respected = "RESPECTED"
    case invalidated = "INVALIDATED"
}

public enum TrapEvaluationHelper {
    /// Checks subsequent closed candles after a trap formed to verify whether price respected
    /// the trap warning (moved >= 1.0x ATR in the institutional direction without closing through level)
    /// or invalidated it on a close through the trap level.
    public static func evaluateTrapRespect(
        trap: BehavioralTrap,
        subsequentClosedCandles: [Candle],
        atrReference: Double
    ) -> TrapRespectOutcome {
        let safeATR = max(atrReference, trap.level * 0.002)
        let future = subsequentClosedCandles
            .filter { $0.isClosed && $0.openTimeEpochSeconds >= trap.triggerEpochSeconds }
            .sorted { $0.openTimeEpochSeconds < $1.openTimeEpochSeconds }
            .prefix(24)

        for bar in future {
            switch trap.direction {
            case .bullTrap:
                if bar.close > trap.level { return .invalidated }
                if bar.low <= trap.level - safeATR { return .respected }
            case .bearTrap:
                if bar.close < trap.level { return .invalidated }
                if bar.high >= trap.level + safeATR { return .respected }
            }
        }
        return trap.state == .invalid ? .invalidated : .pending
    }
}

public struct CalibrationSummary: Codable, Sendable, Equatable {
    public let totalSignals: Int
    public let resolvedSignals: Int
    public let tp1Hits: Int
    public let tp2Hits: Int
    public let slHits: Int
    public let tp1PartialsExcluded: Int
    public let notFilledCount: Int
    public let invalidatedCount: Int
    public let openCount: Int
    public let pendingCount: Int
    public let legacyExcludedCount: Int
    public let winRate: Double
    public let winRateCI: WilsonInterval?
    public let expectancyR: Double
    public let brierScore: Double
    public let trapAccuracy: Double?
    public let macroCatalystHitRate: Double?
    public let strategyRankings: [StrategyAccuracyStat]
    public let marketBreakdown: [MarketClass: Double]
    public let marketStats: [MarketClass: MarketAccuracyStat]
    public let isCalibrationActive: Bool
    public let calibrationSampleCount: Int

    public init(
        totalSignals: Int,
        resolvedSignals: Int,
        tp1Hits: Int,
        tp2Hits: Int,
        slHits: Int,
        tp1PartialsExcluded: Int = 0,
        notFilledCount: Int = 0,
        invalidatedCount: Int = 0,
        openCount: Int = 0,
        pendingCount: Int = 0,
        legacyExcludedCount: Int = 0,
        winRate: Double,
        winRateCI: WilsonInterval? = nil,
        expectancyR: Double,
        brierScore: Double,
        trapAccuracy: Double?,
        macroCatalystHitRate: Double?,
        strategyRankings: [StrategyAccuracyStat],
        marketBreakdown: [MarketClass: Double],
        marketStats: [MarketClass: MarketAccuracyStat] = [:],
        isCalibrationActive: Bool = false,
        calibrationSampleCount: Int = 0
    ) {
        self.totalSignals = totalSignals
        self.resolvedSignals = resolvedSignals
        self.tp1Hits = tp1Hits
        self.tp2Hits = tp2Hits
        self.slHits = slHits
        self.tp1PartialsExcluded = tp1PartialsExcluded
        self.notFilledCount = notFilledCount
        self.invalidatedCount = invalidatedCount
        self.openCount = openCount
        self.pendingCount = pendingCount
        self.legacyExcludedCount = legacyExcludedCount
        self.winRate = winRate
        self.winRateCI = winRateCI
        self.expectancyR = expectancyR
        self.brierScore = brierScore
        self.trapAccuracy = trapAccuracy
        self.macroCatalystHitRate = macroCatalystHitRate
        self.strategyRankings = strategyRankings
        self.marketBreakdown = marketBreakdown
        self.marketStats = marketStats
        self.isCalibrationActive = isCalibrationActive
        self.calibrationSampleCount = calibrationSampleCount
    }

    enum CodingKeys: String, CodingKey {
        case totalSignals, resolvedSignals, tp1Hits, tp2Hits, slHits, tp1PartialsExcluded
        case notFilledCount, invalidatedCount, openCount, pendingCount, legacyExcludedCount
        case winRate, winRateCI, expectancyR, brierScore, trapAccuracy, macroCatalystHitRate
        case strategyRankings, marketBreakdown, marketStats, isCalibrationActive, calibrationSampleCount
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalSignals = try c.decode(Int.self, forKey: .totalSignals)
        resolvedSignals = try c.decode(Int.self, forKey: .resolvedSignals)
        tp1Hits = try c.decode(Int.self, forKey: .tp1Hits)
        tp2Hits = try c.decode(Int.self, forKey: .tp2Hits)
        slHits = try c.decode(Int.self, forKey: .slHits)
        tp1PartialsExcluded = (try? c.decodeIfPresent(Int.self, forKey: .tp1PartialsExcluded)) ?? 0
        notFilledCount = (try? c.decodeIfPresent(Int.self, forKey: .notFilledCount)) ?? 0
        invalidatedCount = (try? c.decodeIfPresent(Int.self, forKey: .invalidatedCount)) ?? 0
        openCount = (try? c.decodeIfPresent(Int.self, forKey: .openCount)) ?? 0
        pendingCount = (try? c.decodeIfPresent(Int.self, forKey: .pendingCount)) ?? 0
        legacyExcludedCount = (try? c.decodeIfPresent(Int.self, forKey: .legacyExcludedCount)) ?? 0
        winRate = try c.decode(Double.self, forKey: .winRate)
        winRateCI = try c.decodeIfPresent(WilsonInterval.self, forKey: .winRateCI)
        expectancyR = try c.decode(Double.self, forKey: .expectancyR)
        brierScore = try c.decode(Double.self, forKey: .brierScore)
        trapAccuracy = try c.decodeIfPresent(Double.self, forKey: .trapAccuracy)
        macroCatalystHitRate = try c.decodeIfPresent(Double.self, forKey: .macroCatalystHitRate)
        strategyRankings = (try? c.decodeIfPresent([StrategyAccuracyStat].self, forKey: .strategyRankings)) ?? []
        marketBreakdown = (try? c.decodeIfPresent([MarketClass: Double].self, forKey: .marketBreakdown)) ?? [:]
        marketStats = (try? c.decodeIfPresent([MarketClass: MarketAccuracyStat].self, forKey: .marketStats)) ?? [:]
        isCalibrationActive = (try? c.decodeIfPresent(Bool.self, forKey: .isCalibrationActive)) ?? false
        calibrationSampleCount = (try? c.decodeIfPresent(Int.self, forKey: .calibrationSampleCount)) ?? resolvedSignals
    }
}

public enum PassiveOutcomeEvaluator {
    /// Default entry-zone fill expiration window by timeframe (v1.4).
    public static func defaultFillWindowBars(for timeframe: Timeframe) -> Int {
        switch timeframe {
        case .m15: return 16
        case .m30: return 12
        case .h1: return 12
        case .h4: return 6
        case .d1: return 3
        }
    }

    /// Passively evaluates a historical signal strictly against SUBSEQUENT closed candles using
    /// the v1.4 causal fill lifecycle:
    /// 1. Signal starts `.pending` until a subsequent closed bar intersects `[entryLow, entryHigh]`.
    /// 2. Before fill: if a bar closes beyond SL OR touches TP1 without filling, signal is `.invalidated`.
    ///    If `fillWindowBars` pass without touching entry zone, signal expires as `.notFilled`.
    /// 3. **Fill-Bar Rule (Pessimistic):** On the fill bar itself, check SL ONLY (TP checks start on the NEXT bar).
    /// 4. **Same-Bar Rule (Pessimistic):** On any subsequent bar after fill, if both SL and TP are touched
    ///    within the same bar, resolve pessimistically as SL first (unless TP1 was already hit on a prior bar).
    /// 5. Deducts realistic round-trip fee + slippage costs in basis points.
    public static func evaluate(
        signal: TradeSignal,
        subsequentClosedCandles: [Candle],
        roundTripCostBps: Double? = nil,
        maxLookforwardBars: Int = 48,
        fillWindowBars: Int? = nil
    ) -> SignalOutcomeRecord {
        let prob = min(0.99, max(0.01, signal.confidencePercent / 100.0))
        let strategyIds = signal.alignedStrategies.map(\.id)
        let hasMacro = signal.postNewsCatalystBadge != nil
        let effectiveFillWindow = fillWindowBars ?? defaultFillWindowBars(for: signal.timeframe)

        func makeRecord(
            status: SignalOutcomeStatus,
            lifecycle: SignalLifecycleStatus,
            netReturnPercent: Double,
            rMultiple: Double,
            filledAt: TimeInterval?,
            resolvedAt: TimeInterval?
        ) -> SignalOutcomeRecord {
            SignalOutcomeRecord(
                signalId: signal.id,
                symbol: signal.symbol,
                marketClass: signal.marketClass,
                category: signal.category,
                direction: signal.direction,
                predictedProbability: prob,
                status: status,
                netReturnPercent: netReturnPercent,
                rMultiple: rMultiple,
                strategyIds: strategyIds,
                hadMacroCatalyst: hasMacro,
                resolvedAtEpochSeconds: resolvedAt,
                regime: signal.regime,
                killzone: signal.killzone,
                timeframe: signal.timeframe,
                dataProvider: signal.dataProvider,
                riskRewardRatio: signal.levels?.riskRewardRatio,
                entryBarCloseEpochSeconds: signal.barCloseEpochSeconds,
                lifecycleStatus: lifecycle,
                filledAtEpochSeconds: filledAt,
                fillWindowBars: effectiveFillWindow,
                isLegacyImmediateFill: false,
                origin: signal.origin,
                activeStrategyProfileKey: signal.activeStrategyProfileKey,
                enabledStrategyIDsCSV: signal.matchedStrategyIDs.map(\.rawValue).sorted().joined(separator: ","),
                orderFlowStatus: signal.orderFlowStatus
            )
        }

        guard let lv = signal.levels, signal.direction == .long || signal.direction == .short else {
            return makeRecord(
                status: .expired,
                lifecycle: .resolved,
                netReturnPercent: 0,
                rMultiple: 0,
                filledAt: nil,
                resolvedAt: nil
            )
        }

        let costPct = (roundTripCostBps ?? signal.marketClass.defaultRoundTripCostBps) / 100.0
        let costR = costPct / max(lv.riskPercent, 0.01)
        let futureBars = Array(
            subsequentClosedCandles
                .filter { $0.isClosed && $0.openTimeEpochSeconds >= signal.barCloseEpochSeconds }
                .sorted { $0.openTimeEpochSeconds < $1.openTimeEpochSeconds }
                .prefix(maxLookforwardBars)
        )

        var isFilled = false
        var filledAt: TimeInterval? = nil
        var barsWithoutFill = 0
        var hitTP1 = false
        var tp1Time: TimeInterval? = nil

        for bar in futureBars {
            if !isFilled {
                let touchedEntry = (bar.low <= lv.entryHigh && bar.high >= lv.entryLow)
                if touchedEntry {
                    isFilled = true
                    filledAt = bar.closeTimeEpochSeconds

                    // Fill-Bar Rule: check SL ONLY on the fill bar (pessimistic). TP checks start on the NEXT bar.
                    let slHitOnFillBar = (signal.direction == .long)
                        ? (bar.low <= lv.stopLoss)
                        : (bar.high >= lv.stopLoss)
                    if slHitOnFillBar {
                        let netPct = -(lv.riskPercent + costPct)
                        return makeRecord(
                            status: .hitSL,
                            lifecycle: .resolved,
                            netReturnPercent: netPct,
                            rMultiple: -1.0 - costR,
                            filledAt: filledAt,
                            resolvedAt: bar.closeTimeEpochSeconds
                        )
                    }
                    continue
                }

                // Pre-fill invalidation: bar closes beyond SL OR reaches TP1 without ever touching entry zone
                let closedBeyondSL = (signal.direction == .long)
                    ? (bar.close <= lv.stopLoss)
                    : (bar.close >= lv.stopLoss)
                let reachedTP1BeforeFill = (signal.direction == .long)
                    ? (bar.high >= lv.tp1)
                    : (bar.low <= lv.tp1)

                if closedBeyondSL || reachedTP1BeforeFill {
                    return makeRecord(
                        status: .invalidated,
                        lifecycle: .invalidated,
                        netReturnPercent: 0,
                        rMultiple: 0,
                        filledAt: nil,
                        resolvedAt: bar.closeTimeEpochSeconds
                    )
                }

                barsWithoutFill += 1
                if barsWithoutFill >= effectiveFillWindow {
                    return makeRecord(
                        status: .notFilled,
                        lifecycle: .notFilled,
                        netReturnPercent: 0,
                        rMultiple: 0,
                        filledAt: nil,
                        resolvedAt: bar.closeTimeEpochSeconds
                    )
                }
                continue
            }

            // Strictly post-fill bars: pessimistic same-bar SL-first resolution
            if signal.direction == .long {
                if bar.low <= lv.stopLoss {
                    if hitTP1 {
                        let netPct = lv.reward1Percent - costPct
                        return makeRecord(
                            status: .hitTP1,
                            lifecycle: .resolved,
                            netReturnPercent: netPct,
                            rMultiple: lv.riskRewardRatio - costR,
                            filledAt: filledAt,
                            resolvedAt: tp1Time
                        )
                    }
                    let netPct = -(lv.riskPercent + costPct)
                    return makeRecord(
                        status: .hitSL,
                        lifecycle: .resolved,
                        netReturnPercent: netPct,
                        rMultiple: -1.0 - costR,
                        filledAt: filledAt,
                        resolvedAt: bar.closeTimeEpochSeconds
                    )
                }
                if lv.isTP2Enabled && bar.high >= lv.tp2 {
                    let netPct = lv.reward2Percent - costPct
                    return makeRecord(
                        status: .hitTP2,
                        lifecycle: .resolved,
                        netReturnPercent: netPct,
                        rMultiple: lv.tp2RiskRewardRatio - costR,
                        filledAt: filledAt,
                        resolvedAt: bar.closeTimeEpochSeconds
                    )
                }
                if !hitTP1 && bar.high >= lv.tp1 {
                    if !lv.isTP2Enabled {
                        let netPct = lv.reward1Percent - costPct
                        return makeRecord(
                            status: .hitTP1,
                            lifecycle: .resolved,
                            netReturnPercent: netPct,
                            rMultiple: lv.riskRewardRatio - costR,
                            filledAt: filledAt,
                            resolvedAt: bar.closeTimeEpochSeconds
                        )
                    }
                    hitTP1 = true
                    tp1Time = bar.closeTimeEpochSeconds
                }
            } else {
                if bar.high >= lv.stopLoss {
                    if hitTP1 {
                        let netPct = lv.reward1Percent - costPct
                        return makeRecord(
                            status: .hitTP1,
                            lifecycle: .resolved,
                            netReturnPercent: netPct,
                            rMultiple: lv.riskRewardRatio - costR,
                            filledAt: filledAt,
                            resolvedAt: tp1Time
                        )
                    }
                    let netPct = -(lv.riskPercent + costPct)
                    return makeRecord(
                        status: .hitSL,
                        lifecycle: .resolved,
                        netReturnPercent: netPct,
                        rMultiple: -1.0 - costR,
                        filledAt: filledAt,
                        resolvedAt: bar.closeTimeEpochSeconds
                    )
                }
                if lv.isTP2Enabled && bar.low <= lv.tp2 {
                    let netPct = lv.reward2Percent - costPct
                    return makeRecord(
                        status: .hitTP2,
                        lifecycle: .resolved,
                        netReturnPercent: netPct,
                        rMultiple: lv.tp2RiskRewardRatio - costR,
                        filledAt: filledAt,
                        resolvedAt: bar.closeTimeEpochSeconds
                    )
                }
                if !hitTP1 && bar.low <= lv.tp1 {
                    if !lv.isTP2Enabled {
                        let netPct = lv.reward1Percent - costPct
                        return makeRecord(
                            status: .hitTP1,
                            lifecycle: .resolved,
                            netReturnPercent: netPct,
                            rMultiple: lv.riskRewardRatio - costR,
                            filledAt: filledAt,
                            resolvedAt: bar.closeTimeEpochSeconds
                        )
                    }
                    hitTP1 = true
                    tp1Time = bar.closeTimeEpochSeconds
                }
            }
        }

        if isFilled {
            if futureBars.count >= maxLookforwardBars {
                if hitTP1 {
                    let netPct = lv.reward1Percent - costPct
                    return makeRecord(
                        status: .hitTP1,
                        lifecycle: .resolved,
                        netReturnPercent: netPct,
                        rMultiple: lv.riskRewardRatio - costR,
                        filledAt: filledAt,
                        resolvedAt: tp1Time
                    )
                }
                return makeRecord(
                    status: .expired,
                    lifecycle: .resolved,
                    netReturnPercent: 0,
                    rMultiple: 0,
                    filledAt: filledAt,
                    resolvedAt: futureBars.last?.closeTimeEpochSeconds
                )
            }
            return makeRecord(
                status: .open,
                lifecycle: .open,
                netReturnPercent: 0,
                rMultiple: 0,
                filledAt: filledAt,
                resolvedAt: nil
            )
        }

        return makeRecord(
            status: .pending,
            lifecycle: .pending,
            netReturnPercent: 0,
            rMultiple: 0,
            filledAt: nil,
            resolvedAt: nil
        )
    }

    /// Computes per-strategy win/loss/expectancy/Brier contribution plus Wilson 95% CI and best/worst pairs & regimes.
    public static func analyzeStrategyPerformance(
        records: [SignalOutcomeRecord],
        filter: CalibrationFilterConfig = .legacyAll
    ) -> [StrategyDiagnosticBreakdown] {
        let eligible = records.filter { filter.matchesRecord($0) && filter.isCountedInWinRateDenominator($0.status) }
        var grouped: [String: [SignalOutcomeRecord]] = [:]
        for rec in eligible {
            for sid in Set(rec.strategyIds) {
                grouped[sid, default: []].append(rec)
            }
        }

        return grouped.map { sid, items in
            let wins = items.filter { filter.isCountedWin($0.status) }.count
            let losses = items.count - wins
            let winRate = Double(wins) / Double(max(items.count, 1))
            let expR = items.reduce(0.0) { $0 + $1.rMultiple } / Double(max(items.count, 1))
            let brier = items.reduce(0.0) { acc, rec in
                let y = filter.isCountedWin(rec.status) ? 1.0 : 0.0
                let d = rec.predictedProbability - y
                return acc + d * d
            } / Double(max(items.count, 1))

            let byPair = Dictionary(grouping: items, by: \.symbol).map { sym, list in
                (sym, list.reduce(0.0) { $0 + $1.rMultiple } / Double(max(list.count, 1)))
            }
            let bestPairs = byPair.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.prefix(3).map(\.0)
            let worstPairs = byPair.filter { $0.1 <= 0 }.sorted { $0.1 < $1.1 }.prefix(3).map(\.0)

            let byRegime = Dictionary(grouping: items, by: { $0.regime?.badgeLabel ?? "UNKNOWN" }).map { reg, list in
                (reg, list.reduce(0.0) { $0 + $1.rMultiple } / Double(max(list.count, 1)))
            }
            let bestRegimes = byRegime.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.prefix(2).map(\.0)
            let worstRegimes = byRegime.filter { $0.1 <= 0 }.sorted { $0.1 < $1.1 }.prefix(2).map(\.0)

            let prettyName = StrategyID.displayName(forRawKey: sid)

            return StrategyDiagnosticBreakdown(
                strategyId: sid,
                displayName: prettyName,
                totalSetups: items.count,
                wins: wins,
                losses: losses,
                winRate: winRate,
                expectancyR: expR,
                brierContribution: brier,
                bestPairs: bestPairs,
                worstPairs: worstPairs,
                bestRegimes: bestRegimes,
                worstRegimes: worstRegimes,
                winRateCI: WilsonInterval.compute(wins: wins, total: items.count)
            )
        }.sorted { $0.expectancyR > $1.expectancyR }
    }

    /// Computes Brier score (`mean((p - y)^2)`), win-rate + Wilson 95% CI, expectancy, trap accuracy,
    /// macro hit rate, lifecycle counts, legacy exclusion counts, and per-strategy/per-market stats.
    public static func summarize(
        records: [SignalOutcomeRecord],
        filter: CalibrationFilterConfig = .legacyAll
    ) -> CalibrationSummary {
        let legacyExcludedCount: Int
        if filter.excludeLegacyImmediateFill {
            legacyExcludedCount = records.filter {
                filter.matchesRecordIgnoringLegacyFlag($0) && $0.effectiveIsLegacyImmediateFill && $0.isResolved
            }.count
        } else {
            legacyExcludedCount = 0
        }

        let scoped = records.filter { filter.matchesRecord($0) }
        let notFilledCount = scoped.filter { $0.status == .notFilled }.count
        let invalidatedCount = scoped.filter { $0.status == .invalidated }.count
        let openCount = scoped.filter { $0.status == .open }.count
        let pendingCount = scoped.filter { $0.status == .pending }.count

        let allResolved = scoped.filter(\.isResolved)
        let counted = allResolved.filter { filter.isCountedInWinRateDenominator($0.status) }

        let tp1 = allResolved.filter { $0.status == .hitTP1 }.count
        let tp2 = allResolved.filter { $0.status == .hitTP2 }.count
        let sl = allResolved.filter { $0.status == .hitSL }.count
        let tp1PartialsExcluded = (filter.winDefinition == .tp2Only) ? tp1 : 0
        let wins = counted.filter { filter.isCountedWin($0.status) }.count

        let winRate = counted.isEmpty ? 0.0 : Double(wins) / Double(counted.count)
        let winRateCI = WilsonInterval.compute(wins: wins, total: counted.count)
        let expectancyR = counted.isEmpty ? 0.0 : counted.reduce(0.0) { $0 + $1.rMultiple } / Double(counted.count)

        let brier: Double
        if counted.isEmpty {
            brier = 0.0
        } else {
            let sumSq = counted.reduce(0.0) { acc, rec in
                let y = filter.isCountedWin(rec.status) ? 1.0 : 0.0
                let diff = rec.predictedProbability - y
                return acc + diff * diff
            }
            brier = sumSq / Double(counted.count)
        }

        let trapResolved = records.filter {
            $0.category == .trapAlert &&
            (!filter.excludeLegacyImmediateFill || !$0.effectiveIsLegacyImmediateFill) &&
            filter.isCountedInWinRateDenominator($0.status)
        }
        let trapAcc: Double? = trapResolved.isEmpty ? nil : Double(trapResolved.filter { filter.isCountedWin($0.status) }.count) / Double(trapResolved.count)

        let macroResolved = counted.filter(\.hadMacroCatalyst)
        let macroHit: Double? = macroResolved.isEmpty ? nil : Double(macroResolved.filter { filter.isCountedWin($0.status) }.count) / Double(macroResolved.count)

        // Per-strategy rankings with Wilson 95% CI
        var stratMap: [String: (wins: Int, total: Int, rSum: Double)] = [:]
        for rec in counted {
            for sid in Set(rec.strategyIds) {
                var entry = stratMap[sid] ?? (0, 0, 0.0)
                entry.total += 1
                if filter.isCountedWin(rec.status) { entry.wins += 1 }
                entry.rSum += rec.rMultiple
                stratMap[sid] = entry
            }
        }
        let rankings = stratMap.map { key, val in
            StrategyAccuracyStat(
                strategyId: key,
                totalResolved: val.total,
                wins: val.wins,
                winRate: Double(val.wins) / Double(max(val.total, 1)),
                expectancyR: val.rSum / Double(max(val.total, 1)),
                winRateCI: WilsonInterval.compute(wins: val.wins, total: val.total)
            )
        }.sorted { $0.expectancyR > $1.expectancyR }

        var marketBreakdown: [MarketClass: Double] = [:]
        var marketStats: [MarketClass: MarketAccuracyStat] = [:]
        for mc in MarketClass.allCases {
            let slice = counted.filter { $0.marketClass == mc }
            if !slice.isEmpty {
                let mWins = slice.filter { filter.isCountedWin($0.status) }.count
                let rate = Double(mWins) / Double(slice.count)
                marketBreakdown[mc] = rate
                marketStats[mc] = MarketAccuracyStat(
                    resolvedCount: slice.count,
                    wins: mWins,
                    winRate: rate,
                    winRateCI: WilsonInterval.compute(wins: mWins, total: slice.count)
                )
            }
        }

        return CalibrationSummary(
            totalSignals: scoped.count,
            resolvedSignals: counted.count,
            tp1Hits: tp1,
            tp2Hits: tp2,
            slHits: sl,
            tp1PartialsExcluded: tp1PartialsExcluded,
            notFilledCount: notFilledCount,
            invalidatedCount: invalidatedCount,
            openCount: openCount,
            pendingCount: pendingCount,
            legacyExcludedCount: legacyExcludedCount,
            winRate: winRate,
            winRateCI: winRateCI,
            expectancyR: expectancyR,
            brierScore: brier,
            trapAccuracy: trapAcc,
            macroCatalystHitRate: macroHit,
            strategyRankings: rankings,
            marketBreakdown: marketBreakdown,
            marketStats: marketStats,
            isCalibrationActive: counted.count >= ConfidenceCalibrator.minimumSamples,
            calibrationSampleCount: counted.count
        )
    }
}
