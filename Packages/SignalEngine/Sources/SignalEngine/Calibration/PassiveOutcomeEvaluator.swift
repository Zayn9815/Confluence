import Foundation

public enum SignalOutcomeStatus: String, Codable, Sendable, Equatable {
    case pending
    case hitTP2
    case hitTP1
    case hitSL
    case expired
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
        dataProvider: String? = nil
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
    }

    public var isWin: Bool {
        status == .hitTP1 || status == .hitTP2
    }

    public var isResolved: Bool {
        status == .hitTP1 || status == .hitTP2 || status == .hitSL
    }
}

public struct StrategyAccuracyStat: Codable, Sendable, Equatable, Identifiable {
    public var id: String { strategyId }
    public let strategyId: String
    public let totalResolved: Int
    public let wins: Int
    public let winRate: Double
    public let expectancyR: Double

    public init(strategyId: String, totalResolved: Int, wins: Int, winRate: Double, expectancyR: Double) {
        self.strategyId = strategyId
        self.totalResolved = totalResolved
        self.wins = wins
        self.winRate = winRate
        self.expectancyR = expectancyR
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
        worstRegimes: [String]
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
    public let winRate: Double
    public let expectancyR: Double
    public let brierScore: Double
    public let trapAccuracy: Double?
    public let macroCatalystHitRate: Double?
    public let strategyRankings: [StrategyAccuracyStat]
    public let marketBreakdown: [MarketClass: Double]

    public init(
        totalSignals: Int,
        resolvedSignals: Int,
        tp1Hits: Int,
        tp2Hits: Int,
        slHits: Int,
        winRate: Double,
        expectancyR: Double,
        brierScore: Double,
        trapAccuracy: Double?,
        macroCatalystHitRate: Double?,
        strategyRankings: [StrategyAccuracyStat],
        marketBreakdown: [MarketClass: Double]
    ) {
        self.totalSignals = totalSignals
        self.resolvedSignals = resolvedSignals
        self.tp1Hits = tp1Hits
        self.tp2Hits = tp2Hits
        self.slHits = slHits
        self.winRate = winRate
        self.expectancyR = expectancyR
        self.brierScore = brierScore
        self.trapAccuracy = trapAccuracy
        self.macroCatalystHitRate = macroCatalystHitRate
        self.strategyRankings = strategyRankings
        self.marketBreakdown = marketBreakdown
    }
}

public enum PassiveOutcomeEvaluator {
    /// Passively checks a historical signal strictly against SUBSEQUENT closed candles
    /// (conservative tie-breaker: if SL and TP both fall inside the same bar, counts SL first).
    /// Applies realistic round-trip fee + slippage costs in basis points.
    public static func evaluate(
        signal: TradeSignal,
        subsequentClosedCandles: [Candle],
        roundTripCostBps: Double? = nil,
        maxLookforwardBars: Int = 48
    ) -> SignalOutcomeRecord {
        let prob = min(0.99, max(0.01, signal.confidencePercent / 100.0))
        let strategyIds = signal.alignedStrategies.map(\.id)
        let hasMacro = signal.postNewsCatalystBadge != nil

        func makeRecord(
            status: SignalOutcomeStatus,
            netReturnPercent: Double,
            rMultiple: Double,
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
                dataProvider: signal.dataProvider
            )
        }

        guard let lv = signal.levels, signal.direction == .long || signal.direction == .short else {
            return makeRecord(status: .expired, netReturnPercent: 0, rMultiple: 0, resolvedAt: nil)
        }

        let costPct = (roundTripCostBps ?? signal.marketClass.defaultRoundTripCostBps) / 100.0
        let futureBars = subsequentClosedCandles
            .filter { $0.isClosed && $0.openTimeEpochSeconds >= signal.barCloseEpochSeconds }
            .sorted { $0.openTimeEpochSeconds < $1.openTimeEpochSeconds }
            .prefix(maxLookforwardBars)

        var hitTP1 = false
        var tp1Time: TimeInterval?

        for bar in futureBars {
            if signal.direction == .long {
                // Conservative: SL checked before TP within the same bar
                if bar.low <= lv.stopLoss {
                    if hitTP1 {
                        let netPct = lv.reward1Percent - costPct
                        return makeRecord(status: .hitTP1, netReturnPercent: netPct, rMultiple: lv.riskRewardRatio - (costPct / max(lv.riskPercent, 0.01)), resolvedAt: tp1Time)
                    }
                    let netPct = -(lv.riskPercent + costPct)
                    return makeRecord(status: .hitSL, netReturnPercent: netPct, rMultiple: -1.0 - (costPct / max(lv.riskPercent, 0.01)), resolvedAt: bar.closeTimeEpochSeconds)
                }
                if bar.high >= lv.tp2 {
                    let netPct = lv.reward2Percent - costPct
                    return makeRecord(status: .hitTP2, netReturnPercent: netPct, rMultiple: lv.tp2RiskRewardRatio - (costPct / max(lv.riskPercent, 0.01)), resolvedAt: bar.closeTimeEpochSeconds)
                }
                if !hitTP1 && bar.high >= lv.tp1 {
                    hitTP1 = true
                    tp1Time = bar.closeTimeEpochSeconds
                }
            } else {
                if bar.high >= lv.stopLoss {
                    if hitTP1 {
                        let netPct = lv.reward1Percent - costPct
                        return makeRecord(status: .hitTP1, netReturnPercent: netPct, rMultiple: lv.riskRewardRatio - (costPct / max(lv.riskPercent, 0.01)), resolvedAt: tp1Time)
                    }
                    let netPct = -(lv.riskPercent + costPct)
                    return makeRecord(status: .hitSL, netReturnPercent: netPct, rMultiple: -1.0 - (costPct / max(lv.riskPercent, 0.01)), resolvedAt: bar.closeTimeEpochSeconds)
                }
                if bar.low <= lv.tp2 {
                    let netPct = lv.reward2Percent - costPct
                    return makeRecord(status: .hitTP2, netReturnPercent: netPct, rMultiple: lv.tp2RiskRewardRatio - (costPct / max(lv.riskPercent, 0.01)), resolvedAt: bar.closeTimeEpochSeconds)
                }
                if !hitTP1 && bar.low <= lv.tp1 {
                    hitTP1 = true
                    tp1Time = bar.closeTimeEpochSeconds
                }
            }
        }

        if hitTP1 {
            let netPct = lv.reward1Percent - costPct
            return makeRecord(status: .hitTP1, netReturnPercent: netPct, rMultiple: lv.riskRewardRatio - (costPct / max(lv.riskPercent, 0.01)), resolvedAt: tp1Time)
        }

        return makeRecord(
            status: futureBars.count >= maxLookforwardBars ? .expired : .pending,
            netReturnPercent: 0,
            rMultiple: 0,
            resolvedAt: nil
        )
    }

    /// Computes per-strategy win/loss/expectancy/Brier contribution plus best/worst pairs and regimes.
    public static func analyzeStrategyPerformance(records: [SignalOutcomeRecord]) -> [StrategyDiagnosticBreakdown] {
        let resolved = records.filter(\.isResolved)
        var grouped: [String: [SignalOutcomeRecord]] = [:]
        for rec in resolved {
            for sid in Set(rec.strategyIds) {
                grouped[sid, default: []].append(rec)
            }
        }

        return grouped.map { sid, items in
            let wins = items.filter(\.isWin).count
            let losses = items.count - wins
            let winRate = Double(wins) / Double(max(items.count, 1))
            let expR = items.reduce(0.0) { $0 + $1.rMultiple } / Double(max(items.count, 1))
            let brier = items.reduce(0.0) { acc, rec in
                let y = rec.isWin ? 1.0 : 0.0
                let d = rec.predictedProbability - y
                return acc + d * d
            } / Double(max(items.count, 1))

            // Best & worst pairs by net R
            let byPair = Dictionary(grouping: items, by: \.symbol).map { sym, list in
                (sym, list.reduce(0.0) { $0 + $1.rMultiple } / Double(max(list.count, 1)))
            }
            let bestPairs = byPair.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.prefix(3).map(\.0)
            let worstPairs = byPair.filter { $0.1 <= 0 }.sorted { $0.1 < $1.1 }.prefix(3).map(\.0)

            // Best & worst regimes by net R
            let byRegime = Dictionary(grouping: items, by: { $0.regime?.badgeLabel ?? "UNKNOWN" }).map { reg, list in
                (reg, list.reduce(0.0) { $0 + $1.rMultiple } / Double(max(list.count, 1)))
            }
            let bestRegimes = byRegime.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.prefix(2).map(\.0)
            let worstRegimes = byRegime.filter { $0.1 <= 0 }.sorted { $0.1 < $1.1 }.prefix(2).map(\.0)

            let prettyName = sid
                .replacingOccurrences(of: "_", with: " ")
                .capitalized

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
                worstRegimes: worstRegimes
            )
        }.sorted { $0.expectancyR > $1.expectancyR }
    }

    /// Computes Brier score (`mean((p - y)^2)`), win-rate, expectancy, trap accuracy, macro hit rate, and per-strategy stats.
    public static func summarize(records: [SignalOutcomeRecord]) -> CalibrationSummary {
        let resolved = records.filter(\.isResolved)
        let tp1 = resolved.filter { $0.status == .hitTP1 }.count
        let tp2 = resolved.filter { $0.status == .hitTP2 }.count
        let sl = resolved.filter { $0.status == .hitSL }.count
        let wins = tp1 + tp2

        let winRate = resolved.isEmpty ? 0.0 : Double(wins) / Double(resolved.count)
        let expectancyR = resolved.isEmpty ? 0.0 : resolved.reduce(0.0) { $0 + $1.rMultiple } / Double(resolved.count)

        let brier: Double
        if resolved.isEmpty {
            brier = 0.0
        } else {
            let sumSq = resolved.reduce(0.0) { acc, rec in
                let y = rec.isWin ? 1.0 : 0.0
                let diff = rec.predictedProbability - y
                return acc + diff * diff
            }
            brier = sumSq / Double(resolved.count)
        }

        let trapResolved = resolved.filter { $0.category == .trapAlert }
        let trapAcc: Double? = trapResolved.isEmpty ? nil : Double(trapResolved.filter(\.isWin).count) / Double(trapResolved.count)

        let macroResolved = resolved.filter(\.hadMacroCatalyst)
        let macroHit: Double? = macroResolved.isEmpty ? nil : Double(macroResolved.filter(\.isWin).count) / Double(macroResolved.count)

        // Per-strategy rankings
        var stratMap: [String: (wins: Int, total: Int, rSum: Double)] = [:]
        for rec in resolved {
            for sid in rec.strategyIds {
                var entry = stratMap[sid] ?? (0, 0, 0.0)
                entry.total += 1
                if rec.isWin { entry.wins += 1 }
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
                expectancyR: val.rSum / Double(max(val.total, 1))
            )
        }.sorted { $0.expectancyR > $1.expectancyR }

        var marketBreakdown: [MarketClass: Double] = [:]
        for mc in MarketClass.allCases {
            let slice = resolved.filter { $0.marketClass == mc }
            if !slice.isEmpty {
                marketBreakdown[mc] = Double(slice.filter(\.isWin).count) / Double(slice.count)
            }
        }

        return CalibrationSummary(
            totalSignals: records.count,
            resolvedSignals: resolved.count,
            tp1Hits: tp1,
            tp2Hits: tp2,
            slHits: sl,
            winRate: winRate,
            expectancyR: expectancyR,
            brierScore: brier,
            trapAccuracy: trapAcc,
            macroCatalystHitRate: macroHit,
            strategyRankings: rankings,
            marketBreakdown: marketBreakdown
        )
    }
}
