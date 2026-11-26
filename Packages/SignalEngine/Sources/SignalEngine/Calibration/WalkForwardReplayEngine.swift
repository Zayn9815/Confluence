import Foundation

public struct WalkForwardReplayReport: Codable, Sendable, Equatable {
    public let symbol: String
    public let timeframe: Timeframe
    public let barsEvaluated: Int
    public let strongSignalsEmitted: Int
    public let trapsDetected: Int
    public let strategyNetReturnPercent: Double
    public let buyAndHoldReturnPercent: Double
    public let maxDrawdownPercent: Double
    public let calibration: CalibrationSummary
    public let roundTripCostBps: Double

    public init(
        symbol: String,
        timeframe: Timeframe,
        barsEvaluated: Int,
        strongSignalsEmitted: Int,
        trapsDetected: Int,
        strategyNetReturnPercent: Double,
        buyAndHoldReturnPercent: Double,
        maxDrawdownPercent: Double,
        calibration: CalibrationSummary,
        roundTripCostBps: Double
    ) {
        self.symbol = symbol
        self.timeframe = timeframe
        self.barsEvaluated = barsEvaluated
        self.strongSignalsEmitted = strongSignalsEmitted
        self.trapsDetected = trapsDetected
        self.strategyNetReturnPercent = strategyNetReturnPercent
        self.buyAndHoldReturnPercent = buyAndHoldReturnPercent
        self.maxDrawdownPercent = maxDrawdownPercent
        self.calibration = calibration
        self.roundTripCostBps = roundTripCostBps
    }
}

public enum WalkForwardReplayEngine {
    /// Strictly causal bar-by-bar walk-forward simulator.
    /// At each step `t`, passes ONLY `candles[0...t]` to `SignalEngine.analyze(...)`,
    /// deducts round-trip fees + slippage, benchmarks against Buy-and-Hold, and computes Brier score.
    public static func run(
        asset: AssetDescriptor,
        entryCandles: [Candle],
        htfCandles: [Candle] = [],
        timeframe: Timeframe,
        htfTimeframe: Timeframe = .h4,
        config: EngineConfig = EngineConfig(),
        warmupBars: Int = 45,
        roundTripCostBps: Double? = nil
    ) -> WalkForwardReplayReport {
        let sorted = entryCandles.filter(\.isClosed).sorted { $0.openTimeEpochSeconds < $1.openTimeEpochSeconds }
        let costBps = roundTripCostBps ?? asset.marketClass.defaultRoundTripCostBps

        guard sorted.count > warmupBars + 5 else {
            return WalkForwardReplayReport(
                symbol: asset.symbol,
                timeframe: timeframe,
                barsEvaluated: 0,
                strongSignalsEmitted: 0,
                trapsDetected: 0,
                strategyNetReturnPercent: 0,
                buyAndHoldReturnPercent: 0,
                maxDrawdownPercent: 0,
                calibration: PassiveOutcomeEvaluator.summarize(records: []),
                roundTripCostBps: costBps
            )
        }

        let startPrice = sorted[warmupBars].close
        let endPrice = sorted.last!.close
        let buyAndHoldPct = startPrice > 0 ? ((endPrice - startPrice) / startPrice) * 100.0 : 0.0

        var outcomes: [SignalOutcomeRecord] = []
        var recentHistory: [(fingerprint: String, symbol: String, direction: TradeDirection, epochSeconds: TimeInterval)] = []
        var equity = 100.0
        var peakEquity = 100.0
        var maxDrawdown = 0.0
        var strongCount = 0
        var trapCount = 0

        for t in warmupBars..<(sorted.count - 1) {
            let prefix = Array(sorted[0...t])
            let nowEpoch = sorted[t].closeTimeEpochSeconds
            let causalHTF = htfCandles.filter { $0.isClosed && $0.closeTimeEpochSeconds <= nowEpoch }

            guard let signal = SignalEngine.evaluateSanitized(
                asset: asset,
                entryCandles: prefix,
                htfCandles: causalHTF,
                timeframe: timeframe,
                htfTimeframe: htfTimeframe,
                positioning: nil,
                calendarEvents: [],
                config: config,
                dataProvider: "WalkForwardFixture",
                isMarketClosed: false,
                nowEpochSeconds: nowEpoch,
                orderFlowSnapshot: nil,
                isLiveEvaluation: false
            ) else { continue }

            if signal.category == .trapAlert {
                trapCount += 1
            }

            guard signal.category == .strongSignal else { continue }
            if ConfluenceScorer.shouldSuppressDuplicate(
                fingerprint: signal.fingerprint,
                symbol: signal.symbol,
                direction: signal.direction,
                nowEpochSeconds: nowEpoch,
                recentHistory: recentHistory,
                cooldownSeconds: config.signalCooldownSeconds
            ) {
                continue
            }

            strongCount += 1
            recentHistory.append((signal.fingerprint, signal.symbol, signal.direction, nowEpoch))

            let futureSlice = Array(sorted[(t + 1)..<sorted.count])
            let outcome = PassiveOutcomeEvaluator.evaluate(
                signal: signal,
                subsequentClosedCandles: futureSlice,
                roundTripCostBps: costBps
            )
            outcomes.append(outcome)

            if outcome.isResolved {
                // Assume fixed 1% risk per trade for compounding equity curve
                let tradeEquityChangePct = outcome.rMultiple * 1.0
                equity *= (1.0 + tradeEquityChangePct / 100.0)
                peakEquity = max(peakEquity, equity)
                let dd = peakEquity > 0 ? ((peakEquity - equity) / peakEquity) * 100.0 : 0.0
                maxDrawdown = max(maxDrawdown, dd)
            }
        }

        let summary = PassiveOutcomeEvaluator.summarize(records: outcomes)

        return WalkForwardReplayReport(
            symbol: asset.symbol,
            timeframe: timeframe,
            barsEvaluated: sorted.count - warmupBars - 1,
            strongSignalsEmitted: strongCount,
            trapsDetected: trapCount,
            strategyNetReturnPercent: equity - 100.0,
            buyAndHoldReturnPercent: buyAndHoldPct,
            maxDrawdownPercent: maxDrawdown,
            calibration: summary,
            roundTripCostBps: costBps
        )
    }
}
