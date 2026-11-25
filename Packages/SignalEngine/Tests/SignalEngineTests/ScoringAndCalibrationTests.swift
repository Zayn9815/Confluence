import Foundation
import XCTest
@testable import SignalEngine

final class ScoringAndCalibrationTests: XCTestCase {
    func testReflexJudgmentHardConfirmationRuleInCode() {
        let confirmed = ReflexJudgment(
            regime: "trending",
            direction: .long,
            setupQuality: 3,
            confidence: 0.86,
            riskState: .safe,
            agree: true,
            catalystBias: "bullish",
            invalidationCheck: "Invalidates on 1H close below 61,400 OB."
        )
        XCTAssertTrue(confirmed.isConfirmedByCodeRule(minimumConfidence: 0.80))

        // Fails if risk_state != safe even if agree == true & high confidence
        let unsafeRisk = ReflexJudgment(
            regime: "crisis",
            direction: .long,
            setupQuality: 3,
            confidence: 0.95,
            riskState: .reduce,
            agree: true,
            catalystBias: "bullish",
            invalidationCheck: "Volatility shock."
        )
        XCTAssertFalse(unsafeRisk.isConfirmedByCodeRule(minimumConfidence: 0.80))

        // Fails if setup_quality < 2
        let lowQuality = ReflexJudgment(
            regime: "trending",
            direction: .long,
            setupQuality: 1,
            confidence: 0.90,
            riskState: .safe,
            agree: true,
            catalystBias: "none",
            invalidationCheck: "Weak sweep."
        )
        XCTAssertFalse(lowQuality.isConfirmedByCodeRule(minimumConfidence: 0.80))
    }

    func testBrierScoreAndPassiveOutcomeEvaluation() {
        let base: TimeInterval = 1_760_000_000
        let levels = TradeLevels(
            entryLow: 99.8, entryHigh: 100.2, entryMid: 100.0,
            stopLoss: 98.0, tp1: 104.0, tp2: 107.0,
            riskPercent: 2.0, reward1Percent: 4.0, reward2Percent: 7.0,
            riskRewardRatio: 2.0, tp2RiskRewardRatio: 3.5
        )
        let psych = PsychologyReport(
            signalCategory: .strongSignal, proDirection: .long, retailCrowdDirection: .short,
            provenanceBadge: PositioningProvenance.okxFundingOI.rawValue,
            whatHappened: "Test", beginnerPsychology: "Test", proPsychology: "Test",
            behavioralBadges: [], evidence: []
        )
        let sig = TradeSignal(
            id: "sig-1", fingerprint: "fp-1", symbol: "BTC/USDT", displayName: "Bitcoin",
            marketClass: .crypto, timeframe: .h1, htfTimeframe: .h4,
            category: .strongSignal, direction: .long, tier: .highConviction,
            confidencePercent: 80.0, regime: .trending, riskState: .safe,
            killzone: .newYork, htfBias: .long,
            generatedAtEpochSeconds: base, barCloseEpochSeconds: base,
            levels: levels, alignedStrategies: [], rejectionReasons: [],
            psychologyReport: psych, dataProvider: "Fixture"
        )

        // Future bars hit TP1 then TP2 cleanly
        let winningBars = [
            Candle(openTimeEpochSeconds: base, closeTimeEpochSeconds: base + 3600, open: 100, high: 105, low: 99, close: 104.5, volume: 1000),
            Candle(openTimeEpochSeconds: base + 3600, closeTimeEpochSeconds: base + 7200, open: 104.5, high: 108, low: 104, close: 107.5, volume: 1200)
        ]
        let winOutcome = PassiveOutcomeEvaluator.evaluate(signal: sig, subsequentClosedCandles: winningBars, roundTripCostBps: 15.0)
        XCTAssertEqual(winOutcome.status, .hitTP2)
        XCTAssertTrue(winOutcome.isWin)
        XCTAssertLessThan(winOutcome.netReturnPercent, 7.0) // Fees deducted

        // Losing bar hits SL
        let losingBars = [
            Candle(openTimeEpochSeconds: base, closeTimeEpochSeconds: base + 3600, open: 100, high: 101, low: 97.5, close: 97.8, volume: 1000)
        ]
        let lossOutcome = PassiveOutcomeEvaluator.evaluate(signal: sig, subsequentClosedCandles: losingBars, roundTripCostBps: 15.0)
        XCTAssertEqual(lossOutcome.status, .hitSL)
        XCTAssertFalse(lossOutcome.isWin)

        // Verify exact Brier score: ((0.8 - 1)^2 + (0.8 - 0)^2) / 2 = (0.04 + 0.64) / 2 = 0.34
        let summary = PassiveOutcomeEvaluator.summarize(records: [winOutcome, lossOutcome])
        XCTAssertEqual(summary.resolvedSignals, 2)
        XCTAssertEqual(summary.winRate, 0.5, accuracy: 1e-9)
        XCTAssertEqual(summary.brierScore, 0.34, accuracy: 1e-6)
    }

    func testDeduplicationCooldown() {
        let now: TimeInterval = 1_760_000_000
        let fp = ConfluenceScorer.makeFingerprint(symbol: "ETH/USDT", timeframe: .h1, category: .strongSignal, direction: .long, barCloseEpochSeconds: now)
        let history = [(fingerprint: fp, symbol: "ETH/USDT", direction: TradeDirection.long, epochSeconds: now - 600)]

        XCTAssertTrue(ConfluenceScorer.shouldSuppressDuplicate(
            fingerprint: fp, symbol: "ETH/USDT", direction: .long,
            nowEpochSeconds: now, recentHistory: history, cooldownSeconds: 3_600
        ))
        XCTAssertFalse(ConfluenceScorer.shouldSuppressDuplicate(
            fingerprint: "different", symbol: "ETH/USDT", direction: .long,
            nowEpochSeconds: now + 4_000, recentHistory: history, cooldownSeconds: 3_600
        ))
    }

    func testWalkForwardReplayExecutesCausallyWithFeesAndBenchmark() {
        let btc = WatchlistDefaults.descriptor(for: "BTC/USDT")!
        let base: TimeInterval = 1_760_000_000
        var bars: [Candle] = []
        var price = 60_000.0
        for i in 0..<180 {
            let cycle = sin(Double(i) * 0.28) * 550.0
            let drift = Double(i) * 18.0
            let open = price
            let close = max(50_000.0, 60_000.0 + drift + cycle)
            let high = max(open, close) + 280.0
            let low = min(open, close) - 280.0
            let vol = 1_000.0 + Double((i % 7) * 250)
            bars.append(Candle(
                openTimeEpochSeconds: base + Double(i) * 3_600,
                closeTimeEpochSeconds: base + Double(i + 1) * 3_600,
                open: open, high: high, low: low, close: close, volume: vol, isClosed: true
            ))
            price = close
        }

        let report = WalkForwardReplayEngine.run(
            asset: btc,
            entryCandles: bars,
            timeframe: .h1,
            config: EngineConfig(minimumConfidencePercent: 60.0),
            warmupBars: 45,
            roundTripCostBps: 15.0
        )
        XCTAssertEqual(report.barsEvaluated, 180 - 45 - 1)
        XCTAssertEqual(report.roundTripCostBps, 15.0)
        XCTAssertGreaterThan(report.buyAndHoldReturnPercent, 0)
        XCTAssertGreaterThanOrEqual(report.calibration.brierScore, 0.0)
        XCTAssertLessThanOrEqual(report.calibration.brierScore, 1.0)
    }

    func testStrategyPerformanceBreakdownAndFailureModes() {
        let records: [SignalOutcomeRecord] = [
            SignalOutcomeRecord(
                signalId: "s1", symbol: "XAU/USD", marketClass: .metals, category: .strongSignal,
                direction: .long, predictedProbability: 0.80, status: .hitTP2,
                netReturnPercent: 3.0, rMultiple: 2.5, strategyIds: ["ict_sweep"],
                hadMacroCatalyst: false, resolvedAtEpochSeconds: 1_760_010_000,
                regime: .trending, killzone: .london, timeframe: .h1, dataProvider: "Twelve Data"
            ),
            SignalOutcomeRecord(
                signalId: "s2", symbol: "XAU/USD", marketClass: .metals, category: .strongSignal,
                direction: .long, predictedProbability: 0.80, status: .hitTP1,
                netReturnPercent: 2.0, rMultiple: 1.5, strategyIds: ["ict_sweep"],
                hadMacroCatalyst: false, resolvedAtEpochSeconds: 1_760_020_000,
                regime: .trending, killzone: .newYork, timeframe: .h1, dataProvider: "Twelve Data"
            ),
            SignalOutcomeRecord(
                signalId: "s3", symbol: "USD/JPY", marketClass: .forex, category: .strongSignal,
                direction: .short, predictedProbability: 0.70, status: .hitSL,
                netReturnPercent: -1.0, rMultiple: -1.0, strategyIds: ["ict_sweep"],
                hadMacroCatalyst: false, resolvedAtEpochSeconds: 1_760_030_000,
                regime: .highVol, killzone: .asia, timeframe: .h1, dataProvider: "biquote.io"
            )
        ]

        let breakdowns = PassiveOutcomeEvaluator.analyzeStrategyPerformance(records: records)
        XCTAssertEqual(breakdowns.count, 1)
        let ict = breakdowns[0]
        XCTAssertEqual(ict.strategyId, "ict_sweep")
        XCTAssertEqual(ict.wins, 2)
        XCTAssertEqual(ict.losses, 1)
        XCTAssertEqual(ict.winRate, 2.0 / 3.0, accuracy: 1e-6)
        XCTAssertTrue(ict.bestPairs.contains("XAU/USD"))
        XCTAssertTrue(ict.worstPairs.contains("USD/JPY"))
        XCTAssertTrue(ict.bestRegimes.contains(MarketRegime.trending.badgeLabel))
        XCTAssertTrue(ict.worstRegimes.contains(MarketRegime.highVol.badgeLabel))
    }

    func testTrapRespectEvaluation() {
        let base: TimeInterval = 1_760_000_000
        let bullTrap = BehavioralTrap(
            symbol: "BTC/USDT",
            direction: .bullTrap,
            triggerKind: .roundNumberCluster,
            state: .active,
            level: 70_000.0,
            triggerBarIndex: 10,
            triggerEpochSeconds: base,
            description: "Round-number sweep failed"
        )

        let respectedBars = [
            Candle(openTimeEpochSeconds: base, closeTimeEpochSeconds: base + 3600, open: 69_900, high: 69_980, low: 69_200, close: 69_300, volume: 500, isClosed: true)
        ]
        XCTAssertEqual(
            TrapEvaluationHelper.evaluateTrapRespect(trap: bullTrap, subsequentClosedCandles: respectedBars, atrReference: 400.0),
            .respected
        )

        let invalidatedBars = [
            Candle(openTimeEpochSeconds: base, closeTimeEpochSeconds: base + 3600, open: 69_950, high: 70_500, low: 69_900, close: 70_350, volume: 900, isClosed: true)
        ]
        XCTAssertEqual(
            TrapEvaluationHelper.evaluateTrapRespect(trap: bullTrap, subsequentClosedCandles: invalidatedBars, atrReference: 400.0),
            .invalidated
        )
    }
}
