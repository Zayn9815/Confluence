import Foundation

public enum WinRateOriginGroup: String, Codable, Sendable, CaseIterable, Identifiable {
    case strongSignals
    case trapsAndFiltered
    case newsSetups

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .strongSignals: return "Strong signals"
        case .trapsAndFiltered: return "Traps and filtered"
        case .newsSetups: return "News setups"
        }
    }
}

public struct TrapOutcomeSummaryItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let outcome: TrapRespectOutcome
    public let confidencePercent: Double

    public init(id: String, outcome: TrapRespectOutcome, confidencePercent: Double = 60.0) {
        self.id = id
        self.outcome = outcome
        self.confidencePercent = confidencePercent
    }
}

public struct OriginWinRateStat: Codable, Sendable, Equatable, Identifiable {
    public var id: String { group.rawValue }
    public let group: WinRateOriginGroup
    public let title: String
    public let wins: Int
    public let losses: Int
    public let totalResolved: Int
    public let winRate: Double
    public let winRateCI: WilsonInterval?
    public let positiveCountLabel: String
    public let negativeCountLabel: String

    public init(
        group: WinRateOriginGroup,
        title: String,
        wins: Int,
        losses: Int,
        totalResolved: Int,
        winRate: Double,
        winRateCI: WilsonInterval?,
        positiveCountLabel: String,
        negativeCountLabel: String
    ) {
        self.group = group
        self.title = title
        self.wins = wins
        self.losses = losses
        self.totalResolved = totalResolved
        self.winRate = winRate
        self.winRateCI = winRateCI
        self.positiveCountLabel = positiveCountLabel
        self.negativeCountLabel = negativeCountLabel
    }

    public var countsSummaryText: String {
        if totalResolved == 0 {
            return "No trades yet"
        }
        return "\(wins) \(positiveCountLabel) · \(losses) \(negativeCountLabel) (n=\(totalResolved))"
    }
}

public struct StrengthBucketStat: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let lowerBound: Double
    public let upperBound: Double?
    public let wins: Int
    public let losses: Int
    public let totalResolved: Int
    public let winRate: Double
    public let winRateCI: WilsonInterval?

    public init(
        id: String,
        label: String,
        lowerBound: Double,
        upperBound: Double?,
        wins: Int,
        losses: Int,
        totalResolved: Int,
        winRate: Double,
        winRateCI: WilsonInterval?
    ) {
        self.id = id
        self.label = label
        self.lowerBound = lowerBound
        self.upperBound = upperBound
        self.wins = wins
        self.losses = losses
        self.totalResolved = totalResolved
        self.winRate = winRate
        self.winRateCI = winRateCI
    }

    public var summaryText: String {
        if totalResolved == 0 {
            return "No trades yet"
        }
        let pct = Int((winRate * 100.0).rounded())
        if let ci = winRateCI {
            return "\(pct)% \(ci.formattedSummary)"
        }
        return "\(pct)% (n=\(totalResolved))"
    }
}

/// Breaks down win rates honestly by signal origin (Strong signals / Traps and filtered / News setups)
/// and by raw score strength bucket, with exact Wilson 95% CI and sample size `n`.
public enum WinRateBreakdown {
    private struct BucketDef {
        let id: String
        let label: String
        let lower: Double
        let upper: Double?
    }

    private static let strengthBuckets: [BucketDef] = [
        BucketDef(id: "50_59", label: "50–59", lower: 50.0, upper: 60.0),
        BucketDef(id: "60_69", label: "60–69", lower: 60.0, upper: 70.0),
        BucketDef(id: "70_79", label: "70–79", lower: 70.0, upper: 80.0),
        BucketDef(id: "80_plus", label: "80+", lower: 80.0, upper: nil)
    ]

    public static func byOrigin(
        records: [SignalOutcomeRecord],
        trapOutcomes: [TrapOutcomeSummaryItem] = [],
        filter: CalibrationFilterConfig = .headlineFixed
    ) -> [OriginWinRateStat] {
        let eligibleByLegacy = records.filter { rec in
            if filter.excludeLegacyImmediateFill && rec.effectiveIsLegacyImmediateFill {
                return false
            }
            return true
        }

        // 1. Strong signals (scanner origin)
        let strongResolved = eligibleByLegacy.filter {
            $0.origin == .scanner &&
            $0.category == .strongSignal &&
            filter.isCountedInWinRateDenominator($0.status)
        }
        let strongWins = strongResolved.filter { filter.isCountedWin($0.status) }.count
        let strongLosses = strongResolved.count - strongWins
        let strongStat = OriginWinRateStat(
            group: .strongSignals,
            title: WinRateOriginGroup.strongSignals.title,
            wins: strongWins,
            losses: strongLosses,
            totalResolved: strongResolved.count,
            winRate: strongResolved.isEmpty ? 0.0 : Double(strongWins) / Double(strongResolved.count),
            winRateCI: WilsonInterval.compute(wins: strongWins, total: strongResolved.count),
            positiveCountLabel: "Wins",
            negativeCountLabel: "Losses"
        )

        // 2. Traps and filtered (scanner weak/trap signals with levels + level-less TrapEvaluationHelper outcomes)
        let trapAndWeakResolved = eligibleByLegacy.filter {
            $0.origin == .scanner &&
            ($0.category == .trapAlert || $0.category == .weakSignal) &&
            filter.isCountedInWinRateDenominator($0.status)
        }
        let existingIds = Set(trapAndWeakResolved.map(\.signalId))
        let levelWins = trapAndWeakResolved.filter { filter.isCountedWin($0.status) }.count
        let levelLosses = trapAndWeakResolved.count - levelWins

        let additionalTraps = trapOutcomes.filter { !existingIds.contains($0.id) && ($0.outcome == .respected || $0.outcome == .invalidated) }
        let trapWorked = additionalTraps.filter { $0.outcome == .respected }.count
        let trapFailed = additionalTraps.filter { $0.outcome == .invalidated }.count

        let combinedWorked = levelWins + trapWorked
        let combinedFailed = levelLosses + trapFailed
        let combinedTotal = combinedWorked + combinedFailed
        let trapsStat = OriginWinRateStat(
            group: .trapsAndFiltered,
            title: WinRateOriginGroup.trapsAndFiltered.title,
            wins: combinedWorked,
            losses: combinedFailed,
            totalResolved: combinedTotal,
            winRate: combinedTotal == 0 ? 0.0 : Double(combinedWorked) / Double(combinedTotal),
            winRateCI: WilsonInterval.compute(wins: combinedWorked, total: combinedTotal),
            positiveCountLabel: "Worked",
            negativeCountLabel: "Failed"
        )

        // 3. News setups
        let newsResolved = eligibleByLegacy.filter {
            $0.origin == .news &&
            filter.isCountedInWinRateDenominator($0.status)
        }
        let newsWins = newsResolved.filter { filter.isCountedWin($0.status) }.count
        let newsLosses = newsResolved.count - newsWins
        let newsStat = OriginWinRateStat(
            group: .newsSetups,
            title: WinRateOriginGroup.newsSetups.title,
            wins: newsWins,
            losses: newsLosses,
            totalResolved: newsResolved.count,
            winRate: newsResolved.isEmpty ? 0.0 : Double(newsWins) / Double(newsResolved.count),
            winRateCI: WilsonInterval.compute(wins: newsWins, total: newsResolved.count),
            positiveCountLabel: "Wins",
            negativeCountLabel: "Losses"
        )

        return [strongStat, trapsStat, newsStat]
    }

    public static func byStrengthBucket(
        records: [SignalOutcomeRecord],
        filter: CalibrationFilterConfig = .headlineFixed
    ) -> [StrengthBucketStat] {
        let resolved = records.filter { rec in
            filter.matchesRecord(rec) && filter.isCountedInWinRateDenominator(rec.status)
        }

        return strengthBuckets.map { bucket in
            let matching = resolved.filter { rec in
                let score = rec.predictedProbability * 100.0
                if let upper = bucket.upper {
                    return score >= bucket.lower && score < upper
                } else {
                    return score >= bucket.lower
                }
            }
            let wins = matching.filter { filter.isCountedWin($0.status) }.count
            let losses = matching.count - wins
            let total = matching.count
            return StrengthBucketStat(
                id: bucket.id,
                label: bucket.label,
                lowerBound: bucket.lower,
                upperBound: bucket.upper,
                wins: wins,
                losses: losses,
                totalResolved: total,
                winRate: total == 0 ? 0.0 : Double(wins) / Double(total),
                winRateCI: WilsonInterval.compute(wins: wins, total: total)
            )
        }
    }
}
