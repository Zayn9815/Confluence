import Foundation

public struct CorrelationPairWarning: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String { "\(otherSymbol)|\(clusterName ?? "")" }
    public let otherSymbol: String
    public let correlation: Double?
    public let isLiveComputed: Bool
    public let clusterName: String?

    public init(otherSymbol: String, correlation: Double?, isLiveComputed: Bool, clusterName: String?) {
        self.otherSymbol = otherSymbol
        self.correlation = correlation
        self.isLiveComputed = isLiveComputed
        self.clusterName = clusterName
    }

    public var badgeText: String {
        if let rho = correlation, isLiveComputed {
            return "Correlated w/ \(otherSymbol) (ρ \(String(format: "%.2f", rho)))"
        }
        if let cluster = clusterName {
            return "Cluster \(cluster) w/ \(otherSymbol)"
        }
        return "Correlated w/ \(otherSymbol)"
    }
}

public struct ClusterExposure: Codable, Sendable, Equatable, Identifiable {
    public var id: String { clusterName }
    public let clusterName: String
    public let longCount: Int
    public let shortCount: Int
    public let symbols: [String]

    public init(clusterName: String, longCount: Int, shortCount: Int, symbols: [String]) {
        self.clusterName = clusterName
        self.longCount = longCount
        self.shortCount = shortCount
        self.symbols = symbols
    }

    public var totalCount: Int { longCount + shortCount }

    public var summaryBadge: String {
        if longCount > 0 && shortCount > 0 {
            return "\(clusterName): \(longCount)L / \(shortCount)S"
        } else if longCount > 0 {
            return "\(clusterName): \(longCount) LONG"
        } else {
            return "\(clusterName): \(shortCount) SHORT"
        }
    }
}

public struct NetExposureSummary: Codable, Sendable, Equatable {
    public let exposures: [ClusterExposure]
    public let concentratedClusters: [ClusterExposure]
    public let totalStrongSignals: Int

    public init(exposures: [ClusterExposure], concentratedClusters: [ClusterExposure], totalStrongSignals: Int) {
        self.exposures = exposures
        self.concentratedClusters = concentratedClusters
        self.totalStrongSignals = totalStrongSignals
    }

    public var hasConcentratedRisk: Bool { !concentratedClusters.isEmpty }
}

/// Pure-Swift rolling Pearson log-return correlation engine across aligned closed candle timestamps
/// plus static macro-cluster fallbacks (`Crypto-Beta`, `Equity-Risk`, `USD-Risk`, `JPY-Rates`).
public enum CorrelationAnalyzer {
    public static let defaultCorrelationThreshold: Double = 0.70
    public static let minimumAlignedReturnBars: Int = 20

    /// Static institutional macro-risk cluster mapping used as fallback when overlapping closed bars are unavailable.
    public static func staticCluster(for symbol: String) -> String? {
        switch symbol.uppercased() {
        case "BTC/USDT", "ETH/USDT", "SOL/USDT":
            return "Crypto-Beta"
        case "US500", "NAS100", "SPY", "QQQ", "AAPL", "NVDA", "MSFT":
            return "Equity-Risk"
        case "EUR/USD", "GBP/USD", "XAU/USD":
            return "USD-Inverse"
        case "USD/JPY":
            return "JPY-Rates"
        default:
            return nil
        }
    }

    /// Computes rolling Pearson correlation (`-1.0...1.0`) of log returns strictly on exact aligned closed-bar open timestamps.
    public static func rollingPearsonCorrelation(
        seriesA: [Candle],
        seriesB: [Candle],
        maxLookbackBars: Int = 72
    ) -> Double? {
        let closedA = seriesA.filter(\.isClosed)
        let closedB = seriesB.filter(\.isClosed)
        guard closedA.count >= minimumAlignedReturnBars + 1,
              closedB.count >= minimumAlignedReturnBars + 1 else {
            return nil
        }

        let validA = closedA.filter { $0.openTimeEpochSeconds.isFinite && $0.close.isFinite && $0.close > 0 }
        let validB = closedB.filter { $0.openTimeEpochSeconds.isFinite && $0.close.isFinite && $0.close > 0 }
        let mapA = Dictionary(validA.map { (Int($0.openTimeEpochSeconds.rounded()), $0.close) }, uniquingKeysWith: { _, latest in latest })
        let mapB = Dictionary(validB.map { (Int($0.openTimeEpochSeconds.rounded()), $0.close) }, uniquingKeysWith: { _, latest in latest })

        let commonTimestamps = mapA.keys.filter { mapB[$0] != nil }.sorted()
        let recent = Array(commonTimestamps.suffix(maxLookbackBars + 1))
        guard recent.count >= minimumAlignedReturnBars + 1 else { return nil }

        var steps: [Int] = []
        steps.reserveCapacity(recent.count - 1)
        for i in 1..<recent.count {
            let dt = recent[i] - recent[i - 1]
            if dt > 0 { steps.append(dt) }
        }
        steps.sort()
        let medianStep = steps.isEmpty ? Int.max : steps[steps.count / 2]
        let maxAllowedGap = (medianStep <= Int.max / 3) ? (medianStep * 3) : Int.max

        var retA: [Double] = []
        var retB: [Double] = []
        retA.reserveCapacity(recent.count - 1)
        retB.reserveCapacity(recent.count - 1)

        for i in 1..<recent.count {
            let tPrev = recent[i - 1]
            let tCurr = recent[i]
            let dt = tCurr - tPrev
            guard dt > 0, dt <= maxAllowedGap else { continue }
            guard let a0 = mapA[tPrev], let a1 = mapA[tCurr], a0 > 0, a1 > 0,
                  let b0 = mapB[tPrev], let b1 = mapB[tCurr], b0 > 0, b1 > 0 else {
                continue
            }
            let la = log(a1 / a0)
            let lb = log(b1 / b0)
            guard la.isFinite, lb.isFinite else { continue }
            retA.append(la)
            retB.append(lb)
        }

        let n = retA.count
        guard n >= minimumAlignedReturnBars else { return nil }

        let meanA = retA.reduce(0, +) / Double(n)
        let meanB = retB.reduce(0, +) / Double(n)

        var cov = 0.0
        var varA = 0.0
        var varB = 0.0
        for i in 0..<n {
            let da = retA[i] - meanA
            let db = retB[i] - meanB
            cov += da * db
            varA += da * da
            varB += db * db
        }

        let denom = sqrt(varA * varB)
        guard denom.isFinite, denom > 1e-12 else { return nil }
        let rho = cov / denom
        guard rho.isFinite else { return nil }
        return max(-1.0, min(1.0, rho))
    }

    /// Computes correlation badges for every active Strong signal against other currently active Strong signals.
    public static func analyzeActiveSignals(
        signals: [TradeSignal],
        candlesBySymbol: [String: [Candle]],
        threshold: Double = defaultCorrelationThreshold
    ) -> [String: [CorrelationPairWarning]] {
        let strong = signals.filter { $0.category == .strongSignal && ($0.direction == .long || $0.direction == .short) }
        var result: [String: [CorrelationPairWarning]] = [:]

        for i in 0..<strong.count {
            let a = strong[i]
            var warnings: [CorrelationPairWarning] = []
            for j in 0..<strong.count where i != j {
                let b = strong[j]
                guard a.symbol != b.symbol else { continue }

                let seriesA = candlesBySymbol[a.symbol] ?? a.recentCandles
                let seriesB = candlesBySymbol[b.symbol] ?? b.recentCandles
                if let rho = rollingPearsonCorrelation(seriesA: seriesA, seriesB: seriesB) {
                    // Warn if positively correlated in same direction OR negatively correlated in opposite direction (same underlying bet)
                    let sameDirectionHighPos = (a.direction == b.direction && rho >= threshold)
                    let oppDirectionHighNeg = (a.direction == b.direction.opposite && rho <= -threshold)
                    if sameDirectionHighPos || oppDirectionHighNeg {
                        warnings.append(CorrelationPairWarning(
                            otherSymbol: b.symbol,
                            correlation: rho,
                            isLiveComputed: true,
                            clusterName: staticCluster(for: a.symbol)
                        ))
                    }
                } else if let cA = staticCluster(for: a.symbol),
                          let cB = staticCluster(for: b.symbol),
                          cA == cB,
                          a.direction == b.direction {
                    warnings.append(CorrelationPairWarning(
                        otherSymbol: b.symbol,
                        correlation: nil,
                        isLiveComputed: false,
                        clusterName: cA
                    ))
                }
            }
            if !warnings.isEmpty {
                // Deduplicate by otherSymbol keeping strongest |rho|
                var bestBySym: [String: CorrelationPairWarning] = [:]
                for w in warnings {
                    if let prev = bestBySym[w.otherSymbol] {
                        if abs(w.correlation ?? 0) > abs(prev.correlation ?? 0) {
                            bestBySym[w.otherSymbol] = w
                        }
                    } else {
                        bestBySym[w.otherSymbol] = w
                    }
                }
                result[a.fingerprint] = bestBySym.values.sorted { abs($0.correlation ?? 0) > abs($1.correlation ?? 0) }
            }
        }
        return result
    }

    /// Aggregates active Strong signals by risk cluster so the user immediately sees overlapping macro exposure.
    public static func netExposureSummary(signals: [TradeSignal]) -> NetExposureSummary {
        let strong = signals.filter { $0.category == .strongSignal && ($0.direction == .long || $0.direction == .short) }
        var buckets: [String: (longs: Int, shorts: Int, syms: [String])] = [:]

        for sig in strong {
            let cluster = staticCluster(for: sig.symbol) ?? sig.marketClass.displayName
            var entry = buckets[cluster] ?? (0, 0, [])
            if !entry.syms.contains(sig.symbol) {
                if sig.direction == .long { entry.longs += 1 } else { entry.shorts += 1 }
                entry.syms.append(sig.symbol)
                buckets[cluster] = entry
            }
        }

        let exposures = buckets.map { name, data in
            ClusterExposure(clusterName: name, longCount: data.longs, shortCount: data.shorts, symbols: data.syms.sorted())
        }.sorted { $0.totalCount > $1.totalCount }

        let concentrated = exposures.filter { $0.longCount >= 2 || $0.shortCount >= 2 }
        return NetExposureSummary(exposures: exposures, concentratedClusters: concentrated, totalStrongSignals: strong.count)
    }

    /// Optional portfolio discipline filter: keeps only the highest raw-score Strong signal per correlated cluster/direction.
    public static func filterOnePerCorrelatedCluster(
        signals: [TradeSignal],
        candlesBySymbol: [String: [Candle]],
        threshold: Double = defaultCorrelationThreshold
    ) -> [TradeSignal] {
        let strong = signals.filter { $0.category == .strongSignal }.sorted { $0.confidencePercent > $1.confidencePercent }
        let nonStrong = signals.filter { $0.category != .strongSignal }

        var kept: [TradeSignal] = []
        for candidate in strong {
            let isRedundant = kept.contains { existing in
                let sA = candlesBySymbol[candidate.symbol] ?? candidate.recentCandles
                let sB = candlesBySymbol[existing.symbol] ?? existing.recentCandles
                if let rho = rollingPearsonCorrelation(seriesA: sA, seriesB: sB) {
                    if candidate.direction == existing.direction && rho >= threshold { return true }
                    if candidate.direction == existing.direction.opposite && rho <= -threshold { return true }
                    return false
                }
                if let cA = staticCluster(for: candidate.symbol),
                   let cB = staticCluster(for: existing.symbol),
                   cA == cB,
                   candidate.direction == existing.direction {
                    return true
                }
                return false
            }
            if !isRedundant {
                kept.append(candidate)
            }
        }
        return kept + nonStrong
    }
}
