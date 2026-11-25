import Foundation

public struct RegimeAssessment: Codable, Sendable, Equatable {
    public let regime: MarketRegime
    public let riskState: RiskState
    public let atrPercent: Double
    public let atrZScore: Double
    public let efficiencyRatio: Double
    public let rollingDrawdownPercent: Double
    public let summary: String

    public init(
        regime: MarketRegime,
        riskState: RiskState,
        atrPercent: Double,
        atrZScore: Double,
        efficiencyRatio: Double,
        rollingDrawdownPercent: Double,
        summary: String
    ) {
        self.regime = regime
        self.riskState = riskState
        self.atrPercent = atrPercent
        self.atrZScore = atrZScore
        self.efficiencyRatio = efficiencyRatio
        self.rollingDrawdownPercent = rollingDrawdownPercent
        self.summary = summary
    }
}

public enum MarketRegimeClassifier {
    /// Strictly causal regime classification computed solely from candles[0...endIndex].
    /// Hard code rule: on `.crisis`, ALWAYS sets `riskState = .reduce`.
    public static func classify(
        candles: [Candle],
        upTo endIndex: Int? = nil,
        marketClass: MarketClass = .crypto
    ) -> RegimeAssessment {
        let lastIdx = min(endIndex ?? (candles.count - 1), candles.count - 1)
        guard lastIdx >= 20 else {
            return RegimeAssessment(
                regime: .meanReverting,
                riskState: .safe,
                atrPercent: 0,
                atrZScore: 0,
                efficiencyRatio: 0,
                rollingDrawdownPercent: 0,
                summary: "Insufficient bar history for regime classification."
            )
        }

        // Compute causal True Range series up to lastIdx
        var trs: [Double] = []
        trs.reserveCapacity(lastIdx + 1)
        for i in 0...lastIdx {
            let c = candles[i]
            if i == 0 {
                trs.append(c.rangeSize)
            } else {
                let prevClose = candles[i - 1].close
                let tr = max(c.high - c.low, max(abs(c.high - prevClose), abs(c.low - prevClose)))
                trs.append(tr)
            }
        }

        // 14-bar ATR and strictly out-of-sample rolling baseline ATR stats (up to 60 prior bars)
        let atrWindow = 14
        var atrSeries: [Double] = []
        var runningSum = 0.0
        for i in 0...lastIdx {
            runningSum += trs[i]
            if i >= atrWindow {
                runningSum -= trs[i - atrWindow]
            }
            if i >= atrWindow - 1 {
                atrSeries.append(runningSum / Double(atrWindow))
            }
        }

        let currentATR = atrSeries.last ?? 0.0
        let lastClose = candles[lastIdx].close
        let atrPercent = lastClose > 0 ? (currentATR / lastClose) * 100.0 : 0.0

        // Out-of-sample baseline excludes currentATR so sudden volatility spikes aren't dampened
        let priorATRSlice = atrSeries.count > 1 ? Array(atrSeries.dropLast().suffix(60)) : atrSeries
        let meanATR = priorATRSlice.reduce(0, +) / Double(max(priorATRSlice.count, 1))
        let variance = priorATRSlice.reduce(0.0) { acc, val in
            let d = val - meanATR
            return acc + d * d
        } / Double(max(priorATRSlice.count, 1))
        let stdATR = sqrt(max(variance, 0.0))
        let rawZ = stdATR > 1e-12 ? (currentATR - meanATR) / stdATR : 0.0
        let atrZScore = rawZ.isFinite ? rawZ : 0.0

        // Kaufman Efficiency Ratio over 20 bars (0 = noisy mean-reverting, 1 = clean trend)
        let erLookback = min(20, lastIdx)
        let netMove = abs(candles[lastIdx].close - candles[lastIdx - erLookback].close)
        var pathLength = 0.0
        for i in (lastIdx - erLookback + 1)...lastIdx {
            pathLength += abs(candles[i].close - candles[i - 1].close)
        }
        let efficiencyRatio = pathLength > 1e-12 ? netMove / pathLength : 0.0

        // Shock / drawdown check over last 24 bars + single-bar shock (asset-class calibrated)
        let shockStart = max(0, lastIdx - 24)
        var peakHigh = candles[shockStart].high
        for i in shockStart...lastIdx {
            peakHigh = max(peakHigh, candles[i].high)
        }
        let drawdownPct = peakHigh > 0 ? ((peakHigh - lastClose) / peakHigh) * 100.0 : 0.0
        let lastBarTRMultiple = meanATR > 1e-12 ? trs[lastIdx] / meanATR : 1.0

        let crisisDrawdownThreshold: Double
        switch marketClass {
        case .forex: crisisDrawdownThreshold = 3.0
        case .metals, .indices: crisisDrawdownThreshold = 5.5
        case .stocks: crisisDrawdownThreshold = 8.0
        case .crypto: crisisDrawdownThreshold = 12.0
        }

        // Hard deterministic classification
        if atrZScore >= 3.0 || lastBarTRMultiple >= 4.2 || drawdownPct >= crisisDrawdownThreshold {
            return RegimeAssessment(
                regime: .crisis,
                riskState: .reduce,
                atrPercent: atrPercent,
                atrZScore: atrZScore,
                efficiencyRatio: efficiencyRatio,
                rollingDrawdownPercent: drawdownPct,
                summary: "Crisis volatility shock detected (ATR z=\(String(format: "%.2f", atrZScore)), bar=\(String(format: "%.1f", lastBarTRMultiple))x avg, DD=\(String(format: "%.1f", drawdownPct))%). Risk forced to REDUCE."
            )
        }

        if atrZScore >= 1.65 || lastBarTRMultiple >= 2.6 {
            return RegimeAssessment(
                regime: .highVol,
                riskState: .nearLimit,
                atrPercent: atrPercent,
                atrZScore: atrZScore,
                efficiencyRatio: efficiencyRatio,
                rollingDrawdownPercent: drawdownPct,
                summary: "Elevated volatility expansion (ATR z=\(String(format: "%.2f", atrZScore))). Tighten confluence and watch stops."
            )
        }

        if efficiencyRatio >= 0.34 {
            return RegimeAssessment(
                regime: .trending,
                riskState: .safe,
                atrPercent: atrPercent,
                atrZScore: atrZScore,
                efficiencyRatio: efficiencyRatio,
                rollingDrawdownPercent: drawdownPct,
                summary: "Directional trending regime (ER=\(String(format: "%.2f", efficiencyRatio)), ATR=\(String(format: "%.2f", atrPercent))%)."
            )
        }

        return RegimeAssessment(
            regime: .meanReverting,
            riskState: .safe,
            atrPercent: atrPercent,
            atrZScore: atrZScore,
            efficiencyRatio: efficiencyRatio,
            rollingDrawdownPercent: drawdownPct,
            summary: "Rotational mean-reverting range (ER=\(String(format: "%.2f", efficiencyRatio)), ATR=\(String(format: "%.2f", atrPercent))%)."
        )
    }
}
