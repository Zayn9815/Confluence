import Foundation

public enum PositioningAnalyzer {
    /// Analyzes OKX perpetual funding + UTC-aligned Open Interest (`1Dutc` / `1H` / `4H`)
    /// against price direction to detect Short Squeezes, Long Liquidations, and Retail Funding Crowding.
    public static func analyzeOKX(
        snapshot: OKXDerivativesSnapshot,
        candles: [Candle],
        upTo endIndex: Int? = nil
    ) -> PositioningAssessment {
        let lastIdx: Int
        if candles.isEmpty {
            lastIdx = -1
        } else {
            lastIdx = max(0, min(endIndex ?? (candles.count - 1), candles.count - 1))
        }
        let lookbackIdx = max(0, lastIdx - 6)
        let priceChangePct: Double
        if lastIdx > lookbackIdx && candles[lookbackIdx].close.isFinite && candles[lookbackIdx].close > 0 && candles[lastIdx].close.isFinite {
            priceChangePct = ((candles[lastIdx].close - candles[lookbackIdx].close) / candles[lookbackIdx].close) * 100.0
        } else {
            priceChangePct = 0.0
        }

        // Sort OI history ascending and filter causally to <= last candle close
        let cutoff = lastIdx >= 0 ? candles[lastIdx].closeTimeEpochSeconds : snapshot.fetchedAtEpochSeconds
        let causalOI = snapshot.openInterestHistory
            .filter { $0.timestampEpochSeconds <= cutoff && $0.openInterestUSD.isFinite && $0.openInterestUSD > 0 }
            .sorted { $0.timestampEpochSeconds < $1.timestampEpochSeconds }

        var oiChangePct: Double? = nil
        if causalOI.count >= 2 {
            let latest = causalOI.last!.openInterestUSD
            let earlier = causalOI[max(0, causalOI.count - 7)].openInterestUSD
            if earlier > 0 {
                let pct = ((latest - earlier) / earlier) * 100.0
                if pct.isFinite {
                    oiChangePct = pct
                }
            }
        }

        // Classify Price-vs-OI divergence
        let divergence: PriceOIDivergence
        if let oiPct = oiChangePct {
            if priceChangePct > 0.35 && oiPct < -1.0 {
                divergence = .shortSqueeze
            } else if priceChangePct > 0.35 && oiPct > 1.0 {
                divergence = .freshLongs
            } else if priceChangePct < -0.35 && oiPct > 1.0 {
                divergence = .freshShorts
            } else if priceChangePct < -0.35 && oiPct < -1.0 {
                divergence = .longLiquidation
            } else {
                divergence = .neutral
            }
        } else {
            divergence = .neutral
        }

        // Funding crowding percentile over causal history (strict anti-lookahead in historical evals)
        let causalFundingPoints = snapshot.fundingHistory
            .filter { $0.fundingTimeEpochSeconds <= cutoff }
            .sorted { $0.fundingTimeEpochSeconds < $1.fundingTimeEpochSeconds }
        let causalFunding = causalFundingPoints.compactMap { pt -> Double? in
            let rate = pt.realizedRate ?? pt.fundingRate
            return rate.isFinite ? rate : nil
        }
        let isHistoricalEval = (endIndex != nil && lastIdx < candles.count - 1) || cutoff < snapshot.fetchedAtEpochSeconds
        let rawCurrentFunding: Double
        if isHistoricalEval {
            if let latestCausal = causalFundingPoints.last {
                rawCurrentFunding = latestCausal.realizedRate ?? latestCausal.fundingRate
            } else {
                // Strictly prevent leaking future live funding rate into historical replay
                rawCurrentFunding = 0.0
            }
        } else {
            rawCurrentFunding = snapshot.currentFundingRate
        }
        let currentFunding = rawCurrentFunding.isFinite ? rawCurrentFunding : 0.0

        let fundingPercentile: Double?
        if causalFunding.count >= 10 {
            fundingPercentile = percentileRank(value: currentFunding, history: causalFunding)
        } else {
            fundingPercentile = nil
        }

        var badges: [String] = []
        var proDir: TradeDirection = .neutral
        var retailDir: TradeDirection = .neutral

        switch divergence {
        case .shortSqueeze:
            badges.append("Short Squeeze")
            proDir = .long
            retailDir = .short
        case .longLiquidation:
            badges.append("Long Liquidation Flush")
            proDir = .short
            retailDir = .long
        case .freshLongs:
            badges.append("Fresh Longs (OI ↑)")
            proDir = .long
            retailDir = .long
        case .freshShorts:
            badges.append("Fresh Shorts (OI ↑)")
            proDir = .short
            retailDir = .short
        case .neutral:
            break
        }

        // Overcrowded funding override (extreme positive funding = overcrowded retail longs -> contrarian risk)
        let extremePositiveFunding = currentFunding >= 0.0005 || (currentFunding > 0 && (fundingPercentile ?? 50.0) >= 90.0)
        let extremeNegativeFunding = currentFunding <= -0.0003 || (currentFunding < 0 && (fundingPercentile ?? 50.0) <= 10.0)

        if extremePositiveFunding {
            badges.append("Overcrowded Retail Longs")
            retailDir = .long
            if divergence != .freshLongs { proDir = .short }
        } else if extremeNegativeFunding {
            badges.append("Overcrowded Retail Shorts")
            retailDir = .short
            if divergence != .freshShorts { proDir = .long }
        }

        let fundingBps = currentFunding * 10_000.0
        let oiStr = oiChangePct.map { String(format: "%+.1f%% OI", $0) } ?? "OI N/A"
        let summary = "OKX \(snapshot.instId): Funding \(String(format: "%+.2f", fundingBps)) bps (\(fundingPercentile.map { "P\(Int($0.rounded()))" } ?? "live")), \(oiStr) -> \(divergence.label)."

        return PositioningAssessment(
            provenance: .okxFundingOI,
            proDirection: proDir,
            retailCrowdDirection: retailDir,
            priceOIDivergence: divergence,
            fundingRate: currentFunding,
            fundingPercentile: fundingPercentile,
            oiChangePercent: oiChangePct,
            summary: summary,
            badges: badges
        )
    }

    /// Analyzes weekly CFTC Commitments of Traders records causally (only using reports whose
    /// Friday 20:30 UTC publication timestamp <= `asOfEpochSeconds`).
    public static func analyzeCFTCCOT(
        records: [CFTCCOTRecord],
        asOfEpochSeconds: TimeInterval
    ) -> PositioningAssessment? {
        let causal = records
            .filter { $0.publishedAtEpochSeconds <= asOfEpochSeconds }
            .sorted { $0.reportDateEpochSeconds < $1.reportDateEpochSeconds }
        guard let latest = causal.last else { return nil }

        let window = Array(causal.suffix(52))
        let instValues = window.map(\.institutionalNetPercentOI).filter(\.isFinite)
        let retailValues = window.map(\.nonReportableNetPercentOI).filter(\.isFinite)

        let instPct = percentileRank(value: latest.institutionalNetPercentOI, history: instValues)
        let retailPct = percentileRank(value: latest.nonReportableNetPercentOI, history: retailValues)

        let hasEnoughHistory = window.count >= 4
        let proDir: TradeDirection
        if hasEnoughHistory {
            if instPct >= 62.0 || (latest.institutionalNet > 0 && instPct >= 52.0) {
                proDir = .long
            } else if instPct <= 38.0 || (latest.institutionalNet < 0 && instPct <= 48.0) {
                proDir = .short
            } else {
                proDir = .neutral
            }
        } else {
            if latest.institutionalNet > 0 {
                proDir = .long
            } else if latest.institutionalNet < 0 {
                proDir = .short
            } else {
                proDir = .neutral
            }
        }

        let retailDir: TradeDirection
        if retailPct >= 62.0 {
            retailDir = .long
        } else if retailPct <= 38.0 {
            retailDir = .short
        } else {
            retailDir = .neutral
        }

        var badges: [String] = []
        if proDir != .neutral && retailDir != .neutral && proDir != retailDir {
            badges.append("COT Institutional Divergence")
        }
        if instPct >= 80.0 {
            badges.append("Managed Money Net Long Extreme")
        } else if instPct <= 20.0 {
            badges.append("Managed Money Net Short Extreme")
        }

        let summary = "CFTC COT (\(latest.contractCode)): Institutional Net \(String(format: "%+.1f%%", latest.institutionalNetPercentOI)) OI (52w P\(Int(instPct.rounded()))) vs Non-Reportables \(String(format: "%+.1f%%", latest.nonReportableNetPercentOI)) OI (P\(Int(retailPct.rounded())))."

        return PositioningAssessment(
            provenance: .cftcCOT,
            proDirection: proDir,
            retailCrowdDirection: retailDir,
            priceOIDivergence: .neutral,
            cotInstitutionalPercentile: instPct,
            cotRetailPercentile: retailPct,
            summary: summary,
            badges: badges
        )
    }

    private static func percentileRank(value: Double, history: [Double]) -> Double {
        guard value.isFinite, !history.isEmpty else { return 50.0 }
        let below = history.filter { $0 < value }.count
        let equal = history.filter { $0 == value }.count
        return ((Double(below) + 0.5 * Double(equal)) / Double(history.count)) * 100.0
    }
}
