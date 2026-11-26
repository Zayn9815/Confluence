import Foundation

/// Exact Wilson score binomial confidence interval (default 95%, z = 1.959964).
public struct WilsonInterval: Codable, Sendable, Equatable, Hashable {
    public let lower: Double
    public let upper: Double
    public let center: Double
    public let sampleSize: Int

    public init(lower: Double, upper: Double, center: Double, sampleSize: Int) {
        self.lower = lower
        self.upper = upper
        self.center = center
        self.sampleSize = sampleSize
    }

    public static func compute(
        wins: Int,
        total: Int,
        z: Double = 1.959963984540054
    ) -> WilsonInterval? {
        guard total > 0 else { return nil }
        let clampedWins = max(0, min(wins, total))
        let n = Double(total)
        let p = Double(clampedWins) / n
        let z2 = z * z
        let denom = 1.0 + z2 / n
        let center = (p + z2 / (2.0 * n)) / denom
        let varianceTerm = max(0.0, (p * (1.0 - p) + z2 / (4.0 * n)) / n)
        let margin = (z * sqrt(varianceTerm)) / denom
        return WilsonInterval(
            lower: max(0.0, center - margin),
            upper: min(1.0, center + margin),
            center: max(0.0, min(1.0, center)),
            sampleSize: total
        )
    }

    public var percentRangeLabel: String {
        let lo = Int((lower * 100.0).rounded())
        let hi = Int((upper * 100.0).rounded())
        return "\(lo)–\(hi)%"
    }

    public var formattedSummary: String {
        "(\(percentRangeLabel), n=\(sampleSize))"
    }
}

/// Pure-Swift walk-forward Platt Scaling calibrator mapping raw confluence scores (`0...100`)
/// to empirical win probabilities.
///
/// **Hard Invariants:**
/// - Inactive (`calibratedProbability` returns `nil`) until at least `minimumSamples` (100) resolved filled trades exist.
/// - Strictly monotonic (`slopeA >= 0.05`) so a higher raw confluence score never produces a lower calibrated probability.
/// - **Display-Only:** The `minimumConfidencePercent` gate ALWAYS evaluates the RAW confluence score; calibrated probability
///   is surfaced alongside the score for honesty and Brier-score calibration only.
public struct ConfidenceCalibrator: Codable, Sendable, Equatable {
    public static let minimumSamples: Int = 100

    public let isActive: Bool
    public let sampleCount: Int
    public let slopeA: Double
    public let interceptB: Double

    public init(isActive: Bool, sampleCount: Int, slopeA: Double, interceptB: Double) {
        self.isActive = isActive
        self.sampleCount = sampleCount
        self.slopeA = slopeA
        self.interceptB = interceptB
    }

    public static let inactive = ConfidenceCalibrator(
        isActive: false,
        sampleCount: 0,
        slopeA: 1.0,
        interceptB: 0.0
    )

    /// Fits L2-regularized Platt scaling `p(s) = sigmoid(a * x + b)` where `x = (score - 50) / 25`
    /// using deterministic Newton-Raphson updates with Platt target smoothing.
    public static func fit(
        records: [SignalOutcomeRecord],
        filter: CalibrationFilterConfig = .headlineFixed
    ) -> ConfidenceCalibrator {
        let eligible = records.filter {
            filter.matchesRecord($0) && filter.isCountedInWinRateDenominator($0.status)
        }
        let samples: [(score: Double, isWin: Bool)] = eligible.map { rec in
            let prob = rec.predictedProbability.isFinite ? min(1.0, max(0.0, rec.predictedProbability)) : 0.5
            return (score: prob * 100.0, isWin: filter.isCountedWin(rec.status))
        }
        return fitPlatt(samples: samples)
    }

    /// Fits walk-forward Platt scaling directly over resolved automatic `TrackedJournalTrade` entries
    /// (excluding `.pending`, `.live`, and `.expired`; strictly inactive until `N >= minimumSamples`).
    public static func fit(
        journalEntries: [TrackedJournalTrade]
    ) -> ConfidenceCalibrator {
        let eligible = journalEntries.filter { $0.status.isCountedWin || $0.status.isCountedLoss }
        let samples: [(score: Double, isWin: Bool)] = eligible.map { entry in
            let safeScore = entry.score.isFinite ? min(100.0, max(0.0, entry.score)) : 50.0
            return (score: safeScore, isWin: entry.status.isCountedWin)
        }
        return fitPlatt(samples: samples)
    }

    private static func fitPlatt(samples: [(score: Double, isWin: Bool)]) -> ConfidenceCalibrator {
        guard samples.count >= minimumSamples else {
            return ConfidenceCalibrator(
                isActive: false,
                sampleCount: samples.count,
                slopeA: 1.0,
                interceptB: 0.0
            )
        }

        let nPos = Double(samples.filter(\.isWin).count)
        let nNeg = Double(samples.count) - nPos
        // Platt target smoothing avoids infinite weights on linearly separable subsets
        let tPos = (nPos + 1.0) / (nPos + 2.0)
        let tNeg = 1.0 / (nNeg + 2.0)

        let xs: [Double] = samples.map { ($0.score - 50.0) / 25.0 }
        let ts: [Double] = samples.map { $0.isWin ? tPos : tNeg }

        var a = 1.0
        var b = 0.0
        let lambda = 1e-2

        for _ in 0..<60 {
            var gA = lambda * (a - 1.0)
            var gB = lambda * b
            var hAA = lambda
            var hBB = lambda
            var hAB = 0.0

            for idx in 0..<xs.count {
                let x = xs[idx]
                let t = ts[idx]
                let z = max(-30.0, min(30.0, a * x + b))
                let p = 1.0 / (1.0 + exp(-z))
                let diff = p - t
                let w = max(1e-6, p * (1.0 - p))

                gA += diff * x
                gB += diff
                hAA += w * x * x
                hBB += w
                hAB += w * x
            }

            let det = hAA * hBB - hAB * hAB
            guard det.isFinite, abs(det) > 1e-12 else { break }

            let stepA = (hBB * gA - hAB * gB) / det
            let stepB = (-hAB * gA + hAA * gB) / det

            let rawNextA = a - stepA
            let nextA = max(0.05, min(10.0, rawNextA))
            let rawNextB: Double
            if nextA != rawNextA {
                let dA = nextA - a
                rawNextB = b - (gB + hAB * dA) / max(hBB, 1e-12)
            } else {
                rawNextB = b - stepB
            }
            let nextB = max(-8.0, min(8.0, rawNextB))

            let delta = abs(nextA - a) + abs(nextB - b)
            a = nextA
            b = nextB
            if delta < 1e-7 { break }
        }

        return ConfidenceCalibrator(
            isActive: true,
            sampleCount: samples.count,
            slopeA: a,
            interceptB: b
        )
    }

    /// Slice-aware Platt calibrator prioritizing outcomes matching `activeProfileKey`,
    /// applying smooth Bayesian shrinkage toward the overall baseline whenever matching
    /// sample count `< 10` so switching to a fresh strategy combination never collapses calibration.
    public static func fit(
        records: [SignalOutcomeRecord],
        filter: CalibrationFilterConfig = .headlineFixed,
        activeProfileKey: String?
    ) -> ConfidenceCalibrator {
        let baseline = fit(records: records, filter: filter)
        guard let rawKey = activeProfileKey, !rawKey.isEmpty else {
            return baseline
        }
        let targetKey = ActiveStrategyProfile.normalizedKey(rawKey)
        let eligible = records.filter {
            filter.matchesRecord($0) && filter.isCountedInWinRateDenominator($0.status)
        }
        let matching = eligible.filter { $0.effectiveStrategyProfileKey == targetKey }
        guard !matching.isEmpty else {
            return baseline
        }

        // Full profile-specific Platt fit once matching slice reaches minimumSamples
        if matching.count >= minimumSamples {
            return fit(records: matching, filter: filter)
        }

        // Smooth Bayesian shrinkage toward baseline when profile slice is small (< 10 or < minimumSamples)
        guard baseline.isActive else {
            return baseline
        }
        let matchWins = matching.filter { filter.isCountedWin($0.status) }.count
        let matchEmpiricalRate = (Double(matchWins) + 1.0) / (Double(matching.count) + 2.0)
        let baseWins = eligible.filter { filter.isCountedWin($0.status) }.count
        let baseRate = (Double(baseWins) + 1.0) / (Double(eligible.count) + 2.0)

        let shrinkWeight = min(1.0, Double(matching.count) / 10.0) * 0.5
        let safeMatch = min(0.98, max(0.02, matchEmpiricalRate))
        let safeBase = min(0.98, max(0.02, baseRate))
        let logitDelta = log(safeMatch / (1.0 - safeMatch)) - log(safeBase / (1.0 - safeBase))
        let shrunkIntercept = max(-8.0, min(8.0, baseline.interceptB + shrinkWeight * logitDelta))

        return ConfidenceCalibrator(
            isActive: true,
            sampleCount: baseline.sampleCount,
            slopeA: baseline.slopeA,
            interceptB: shrunkIntercept
        )
    }

    /// Maps a raw confluence score (`0...100`) to a calibrated win probability (`0.01...0.99`),
    /// or `nil` if fewer than `minimumSamples` (100) resolved filled trades have been observed.
    public func calibratedProbability(forRawScore rawScorePercent: Double) -> Double? {
        guard isActive, rawScorePercent.isFinite else { return nil }
        let x = (rawScorePercent - 50.0) / 25.0
        let z = max(-30.0, min(30.0, slopeA * x + interceptB))
        let p = 1.0 / (1.0 + exp(-z))
        return max(0.01, min(0.99, p))
    }
}
