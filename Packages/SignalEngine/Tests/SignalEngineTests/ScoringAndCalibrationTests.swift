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
                regime: .highVol, killzone: .offSession, timeframe: .h1, dataProvider: "biquote.io"
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
            id: "trap-test-1",
            symbol: "BTC/USDT",
            direction: .bullTrap,
            triggerKind: .oslerRoundNumberSweep,
            level: 70_000.0,
            extremePrice: 70_250.0,
            triggerBarIndex: 10,
            triggerEpochSeconds: base,
            state: .active,
            expiresAtEpochSeconds: base + 86_400,
            pierceATRMultiple: 0.65,
            detail: "Round-number sweep failed"
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

    func testChartPricePrecisionRules() {
        let gbp = ChartPricePrecision.resolve(symbol: "GBP/USD", marketClass: .forex, referencePrice: 1.31002)
        XCTAssertEqual(gbp.precision, 5)
        XCTAssertEqual(gbp.minMove, 0.00001, accuracy: 1e-9)
        XCTAssertEqual(gbp.format(1.31002), "1.31002")

        let jpy = ChartPricePrecision.resolve(symbol: "USD/JPY", marketClass: .forex, referencePrice: 159.178)
        XCTAssertEqual(jpy.precision, 3)
        XCTAssertEqual(jpy.minMove, 0.001, accuracy: 1e-9)
        XCTAssertEqual(jpy.format(159.178), "159.178")

        let sub100 = ChartPricePrecision.resolve(symbol: "SOL/USDT", marketClass: .crypto, referencePrice: 42.1234)
        XCTAssertEqual(sub100.precision, 4)
        XCTAssertEqual(sub100.minMove, 0.0001, accuracy: 1e-9)

        let gold = ChartPricePrecision.resolve(symbol: "XAU/USD", marketClass: .metals, referencePrice: 2650.55)
        XCTAssertEqual(gold.precision, 2)
        XCTAssertEqual(gold.minMove, 0.01, accuracy: 1e-9)
    }

    func testFixedPercentLevelsAndTP2DisabledEvaluation() {
        let base: TimeInterval = 1_760_000_000
        let bar = Candle(
            openTimeEpochSeconds: base - 3600,
            closeTimeEpochSeconds: base,
            open: 100.0, high: 100.5, low: 99.5, close: 100.0, volume: 1000, isClosed: true
        )
        let emptyICT = ICTAnalysis(
            swings: [], structureBreaks: [], fvgs: [], orderBlocks: [], liquiditySweeps: [],
            currentStructureBias: .long, equilibriumPrice: nil, dealingRangeHigh: nil,
            dealingRangeLow: nil, dealingZone: nil, contributions: []
        )

        let lv = TradeLevelCalculator.calculate(
            direction: .long,
            candles: [bar],
            ict: emptyICT,
            htfICT: nil,
            atr: 0.5,
            marketClass: .crypto,
            minimumRiskReward: 2.0,
            mode: .fixedPercent,
            fixedStopLossPercent: 1.0,
            fixedTP1Percent: 2.0,
            fixedTP2Percent: 4.0,
            enableTP2Target: false
        )
        XCTAssertNotNil(lv)
        guard let levels = lv else { return }
        XCTAssertEqual(levels.riskPercent, 1.0, accuracy: 1e-6)
        XCTAssertEqual(levels.reward1Percent, 2.0, accuracy: 1e-6)
        XCTAssertEqual(levels.riskRewardRatio, 2.0, accuracy: 1e-6)
        XCTAssertFalse(levels.isTP2Enabled)
        XCTAssertEqual(levels.tp1, levels.tp2, accuracy: 1e-9)

        let psych = PsychologyReport(
            signalCategory: .strongSignal, proDirection: .long, retailCrowdDirection: .short,
            provenanceBadge: "Test", whatHappened: "Test", beginnerPsychology: "B", proPsychology: "P",
            behavioralBadges: [], evidence: []
        )
        let sig = TradeSignal(
            id: "fixed-tp1-only", fingerprint: "fixed-tp1-only", symbol: "BTC/USDT", displayName: "Bitcoin",
            marketClass: .crypto, timeframe: .h1, htfTimeframe: .h4,
            category: .strongSignal, direction: .long, tier: .highConviction,
            confidencePercent: 82.0, regime: .trending, riskState: .safe,
            killzone: .newYork, htfBias: .long,
            generatedAtEpochSeconds: base, barCloseEpochSeconds: base,
            levels: levels, alignedStrategies: [], rejectionReasons: [],
            psychologyReport: psych, dataProvider: "Fixture"
        )
        // Bar 1 hits TP1 (102.0), Bar 2 drops to SL (99.0) — with TP2 disabled, must resolve immediately as TP1 on Bar 1
        let future = [
            Candle(openTimeEpochSeconds: base, closeTimeEpochSeconds: base + 3600, open: 100.0, high: 102.5, low: 99.8, close: 102.2, volume: 1000, isClosed: true),
            Candle(openTimeEpochSeconds: base + 3600, closeTimeEpochSeconds: base + 7200, open: 102.2, high: 102.3, low: 98.5, close: 98.8, volume: 1000, isClosed: true)
        ]
        let out = PassiveOutcomeEvaluator.evaluate(signal: sig, subsequentClosedCandles: future, roundTripCostBps: 10.0)
        XCTAssertEqual(out.status, .hitTP1)
        XCTAssertEqual(out.resolvedAtEpochSeconds, base + 3600)
    }

    func testCalibrationFilterRulesTP2OnlyCategoryAndThresholds() {
        let records: [SignalOutcomeRecord] = [
            // Strong TP2 Win (85% conf, 2.2 R:R)
            SignalOutcomeRecord(
                signalId: "r1", symbol: "GBP/USD", marketClass: .forex, category: .strongSignal,
                direction: .long, predictedProbability: 0.85, status: .hitTP2,
                netReturnPercent: 3.0, rMultiple: 3.0, strategyIds: ["ict_fvg"],
                hadMacroCatalyst: false, resolvedAtEpochSeconds: 1_760_010_000,
                regime: .trending, killzone: .london, timeframe: .h1, dataProvider: "Twelve Data",
                riskRewardRatio: 2.2
            ),
            // Strong TP1 Partial (82% conf, 2.0 R:R)
            SignalOutcomeRecord(
                signalId: "r2", symbol: "GBP/USD", marketClass: .forex, category: .strongSignal,
                direction: .long, predictedProbability: 0.82, status: .hitTP1,
                netReturnPercent: 1.5, rMultiple: 1.5, strategyIds: ["ict_fvg"],
                hadMacroCatalyst: false, resolvedAtEpochSeconds: 1_760_020_000,
                regime: .trending, killzone: .london, timeframe: .h1, dataProvider: "Twelve Data",
                riskRewardRatio: 2.0
            ),
            // Strong SL Loss (72% conf, 1.6 R:R)
            SignalOutcomeRecord(
                signalId: "r3", symbol: "EUR/USD", marketClass: .forex, category: .strongSignal,
                direction: .short, predictedProbability: 0.72, status: .hitSL,
                netReturnPercent: -1.0, rMultiple: -1.0, strategyIds: ["ict_fvg"],
                hadMacroCatalyst: false, resolvedAtEpochSeconds: 1_760_030_000,
                regime: .highVol, killzone: .newYork, timeframe: .h1, dataProvider: "biquote.io",
                riskRewardRatio: 1.6
            ),
            // Trap Alert SL Loss (88% conf, 2.5 R:R)
            SignalOutcomeRecord(
                signalId: "r4", symbol: "BTC/USDT", marketClass: .crypto, category: .trapAlert,
                direction: .short, predictedProbability: 0.88, status: .hitSL,
                netReturnPercent: -1.0, rMultiple: -1.0, strategyIds: ["trap_osler"],
                hadMacroCatalyst: false, resolvedAtEpochSeconds: 1_760_040_000,
                regime: .highVol, killzone: .newYork, timeframe: .h1, dataProvider: "Binance Vision",
                riskRewardRatio: 2.5
            )
        ]

        // 1. TP2 Only = Win, Strong Only -> TP1 excluded as breakeven partial: 1 TP2 / (1 TP2 + 1 SL) = 50%
        let tp2OnlyFilter = CalibrationFilterConfig(winDefinition: .tp2Only, categoryScope: .strongOnly)
        let tp2Summary = PassiveOutcomeEvaluator.summarize(records: records, filter: tp2OnlyFilter)
        XCTAssertEqual(tp2Summary.tp2Hits, 1)
        XCTAssertEqual(tp2Summary.slHits, 1)
        XCTAssertEqual(tp2Summary.tp1PartialsExcluded, 1)
        XCTAssertEqual(tp2Summary.resolvedSignals, 2)
        XCTAssertEqual(tp2Summary.winRate, 0.5, accuracy: 1e-6)

        // 2. Min confidence >= 80% + Min R:R >= 2.0, TP1 or TP2 = Win, Strong Only -> r1 & r2 both win = 100%
        let strictFilter = CalibrationFilterConfig(
            winDefinition: .tp1OrTp2,
            categoryScope: .strongOnly,
            minimumConfidencePercent: 80.0,
            minimumRiskReward: 2.0
        )
        let strictSummary = PassiveOutcomeEvaluator.summarize(records: records, filter: strictFilter)
        XCTAssertEqual(strictSummary.resolvedSignals, 2)
        XCTAssertEqual(strictSummary.winRate, 1.0, accuracy: 1e-6)
    }

    func testCustomSingleStrategySelectionAndConfidenceGate() {
        let base: TimeInterval = 1_760_000_000
        let asset = WatchlistDefaults.descriptor(for: "GBP/USD")!
        let bar = Candle(openTimeEpochSeconds: base - 3600, closeTimeEpochSeconds: base, open: 1.3090, high: 1.3105, low: 1.3088, close: 1.3100, volume: nil, isClosed: true)
        let fvgContrib = StrategyContribution(id: "ict_fvg", name: "Bullish FVG", group: .ictSmc, direction: .long, weight: 1.4, historicalWinRate: 0.65, detail: "FVG")
        let ict = ICTAnalysis(
            swings: [], structureBreaks: [], fvgs: [], orderBlocks: [], liquiditySweeps: [],
            currentStructureBias: .long, equilibriumPrice: 1.3110, dealingRangeHigh: nil,
            dealingRangeLow: nil, dealingZone: nil, contributions: [fvgContrib]
        )
        let mom = TrendMomentumSnapshot(ema20: 1.3095, ema50: 1.3090, ema200: 1.3070, rsi14: 58, atr14: 0.0012, rvol: nil, htfTrendDirection: .long, contributions: [])
        let regime = RegimeAssessment(
            regime: .trending, riskState: .safe, atrPercent: 0.35, atrZScore: 0.2,
            efficiencyRatio: 0.65, rollingDrawdownPercent: 0.4, summary: "Trending"
        )

        // Custom mode with 1 selected strategy (`ictFVG`) + Fixed % SL/TP + 60% confidence gate -> fires as Strong Signal
        var cfg = EngineConfig(
            minimumConfidencePercent: 60.0,
            minimumRiskReward: 2.0,
            levelCalculationMode: .fixedPercent,
            fixedStopLossPercent: 0.5,
            fixedTP1Percent: 1.0,
            minimumAlignedStrategies: 3,
            strategySelectionMode: .custom,
            selectedStrategyConcepts: [.ictFVG],
            customStrategyMatchRule: .requireAllSelected
        )
        let strongSig = ConfluenceScorer.score(
            asset: asset, timeframe: .h1, htfTimeframe: .h4, candles: [bar], htfBias: .long,
            ict: ict, htfICT: nil, candlestickContributions: [], momentum: mom, regimeAssessment: regime,
            traps: [], positioning: nil, preNewsShield: nil, macroImpulse: nil,
            config: cfg, dataProvider: "Twelve Data", isMarketClosed: false, nowEpochSeconds: base
        )
        XCTAssertEqual(strongSig?.category, .strongSignal)

        // Raising Confidence % floor to 90% must demote the exact same setup to .weakSignal
        cfg.minimumConfidencePercent = 90.0
        let weakSig = ConfluenceScorer.score(
            asset: asset, timeframe: .h1, htfTimeframe: .h4, candles: [bar], htfBias: .long,
            ict: ict, htfICT: nil, candlestickContributions: [], momentum: mom, regimeAssessment: regime,
            traps: [], positioning: nil, preNewsShield: nil, macroImpulse: nil,
            config: cfg, dataProvider: "Twelve Data", isMarketClosed: false, nowEpochSeconds: base
        )
        XCTAssertEqual(weakSig?.category, .weakSignal)
    }
}
