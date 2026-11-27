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
        guard lastIdx >= 20, candles[lastIdx].close.isFinite, candles[lastIdx].close > 0 else {
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
                trs.append(max(0.0, c.rangeSize.isFinite ? c.rangeSize : 0.0))
            } else {
                let prevClose = candles[i - 1].close
                let tr = max(c.high - c.low, max(abs(c.high - prevClose), abs(c.low - prevClose)))
                trs.append(max(0.0, tr.isFinite ? tr : 0.0))
            }
        }

        // 14-bar ATR computed directly per window (avoids floating-point cancellation drift)
        let atrWindow = 14
        var atrSeries: [Double] = []
        atrSeries.reserveCapacity(max(0, lastIdx - atrWindow + 2))
        for i in (atrWindow - 1)...lastIdx {
            var sliceSum = 0.0
            for j in (i - atrWindow + 1)...i {
                sliceSum += trs[j]
            }
            atrSeries.append(max(0.0, sliceSum / Double(atrWindow)))
        }

        let currentATR = atrSeries.last ?? 0.0
        let lastClose = candles[lastIdx].close
        let relEps = max(Double.leastNormalMagnitude, lastClose * 1e-12)
        let atrPercent = lastClose > 0 ? (currentATR / lastClose) * 100.0 : 0.0

        // Out-of-sample baseline excludes currentATR so sudden volatility spikes aren't dampened
        let priorATRSlice = atrSeries.count > 1 ? Array(atrSeries.dropLast().suffix(60)) : atrSeries
        let meanATR = priorATRSlice.reduce(0, +) / Double(max(priorATRSlice.count, 1))
        let variance = priorATRSlice.reduce(0.0) { acc, val in
            let d = val - meanATR
            return acc + d * d
        } / Double(max(priorATRSlice.count, 1))
        let stdATR = sqrt(max(variance, 0.0))
        let rawZ = stdATR > relEps ? (currentATR - meanATR) / stdATR : 0.0
        let atrZScore = rawZ.isFinite ? rawZ : 0.0

        // Kaufman Efficiency Ratio over 20 bars (0 = noisy mean-reverting, 1 = clean trend)
        let erLookback = min(20, lastIdx)
        let rawNetMove = abs(candles[lastIdx].close - candles[lastIdx - erLookback].close)
        let netMove = rawNetMove.isFinite ? rawNetMove : 0.0
        var pathLength = 0.0
        for i in (lastIdx - erLookback + 1)...lastIdx {
            let step = abs(candles[i].close - candles[i - 1].close)
            if step.isFinite {
                pathLength += step
            }
        }
        let efficiencyRatio = (pathLength.isFinite && pathLength > relEps) ? min(1.0, max(0.0, netMove / pathLength)) : 0.0

        // Shock / drawdown & squeeze run-up check over last 24 bars + single-bar shock (asset-class calibrated)
        let shockStart = max(0, lastIdx - 24)
        var peakHigh: Double? = nil
        var troughLow: Double? = nil
        for i in shockStart...lastIdx {
            let hi = candles[i].high
            let lo = candles[i].low
            if hi.isFinite && hi > 0 {
                peakHigh = peakHigh.map { max($0, hi) } ?? hi
            }
            if lo.isFinite && lo > 0 {
                troughLow = troughLow.map { min($0, lo) } ?? lo
            }
        }
        let downsideDDPct: Double = {
            guard let pk = peakHigh, pk > 0, lastClose.isFinite else { return 0.0 }
            let val = ((pk - lastClose) / pk) * 100.0
            return val.isFinite ? max(0.0, val) : 0.0
        }()
        let upsideRunUpPct: Double = {
            guard let tr = troughLow, tr > 0, lastClose.isFinite else { return 0.0 }
            let val = ((lastClose - tr) / tr) * 100.0
            return val.isFinite ? max(0.0, val) : 0.0
        }()
        let drawdownPct = max(downsideDDPct, upsideRunUpPct)
        let rawBarTRMult = meanATR > relEps ? trs[lastIdx] / meanATR : 1.0
        let lastBarTRMultiple = rawBarTRMult.isFinite ? rawBarTRMult : 1.0

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
                summary: "Crisis volatility shock detected (ATR z=\(String(format: "%.2f", atrZScore)), bar=\(String(format: "%.1f", lastBarTRMultiple))x avg, shock=\(String(format: "%.1f", drawdownPct))%). Risk forced to REDUCE."
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
