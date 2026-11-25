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
        // Bar 0 fills entry zone cleanly (TP checks begin next bar per v1.4 fill-bar rule).
        // Bar 1 hits TP1 (102.0), Bar 2 drops to SL (99.0) — with TP2 disabled, must resolve immediately as TP1 on Bar 1.
        let future = [
            Candle(openTimeEpochSeconds: base, closeTimeEpochSeconds: base + 3600, open: 100.0, high: 100.8, low: 99.8, close: 100.4, volume: 1000, isClosed: true),
            Candle(openTimeEpochSeconds: base + 3600, closeTimeEpochSeconds: base + 7200, open: 100.4, high: 102.5, low: 100.2, close: 102.2, volume: 1000, isClosed: true),
            Candle(openTimeEpochSeconds: base + 7200, closeTimeEpochSeconds: base + 10800, open: 102.2, high: 102.3, low: 98.5, close: 98.8, volume: 1000, isClosed: true)
        ]
        let out = PassiveOutcomeEvaluator.evaluate(signal: sig, subsequentClosedCandles: future, roundTripCostBps: 10.0)
        XCTAssertEqual(out.status, .hitTP1)
        XCTAssertEqual(out.resolvedAtEpochSeconds, base + 7200)
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

    // MARK: - v1.3 Quantitative Math, Psychology & News Fusion Tests

    func testTP2RRAndATRCeilingCapsUnrealisticStructuralOutlier() {
        let base: TimeInterval = 1_760_000_000
        let bar = Candle(
            openTimeEpochSeconds: base - 900,
            closeTimeEpochSeconds: base,
            open: 25910, high: 25940, low: 25880, close: 25900,
            volume: 1000, isClosed: true
        )
        let ict = ICTAnalysis(
            swings: [
                SwingPivot(index: 5, confirmedAtIndex: 8, price: 25945, isHigh: true),
                SwingPivot(index: 12, confirmedAtIndex: 15, price: 25760, isHigh: false)
            ],
            structureBreaks: [], fvgs: [], orderBlocks: [], liquiditySweeps: [],
            currentStructureBias: .short, equilibriumPrice: nil,
            dealingRangeHigh: nil, dealingRangeLow: nil, dealingZone: nil, contributions: []
        )
        // Distant HTF swing low ~20R away (the exact bug that produced TP2 1:16.7 on NAS100 15m)
        let htfICT = ICTAnalysis(
            swings: [SwingPivot(index: 3, confirmedAtIndex: 6, price: 24500, isHigh: false)],
            structureBreaks: [], fvgs: [], orderBlocks: [], liquiditySweeps: [],
            currentStructureBias: .short, equilibriumPrice: nil,
            dealingRangeHigh: nil, dealingRangeLow: nil, dealingZone: nil, contributions: []
        )

        let lv = TradeLevelCalculator.calculate(
            direction: .short,
            candles: [bar],
            ict: ict,
            htfICT: htfICT,
            atr: 45.0,
            marketClass: .indices,
            minimumRiskReward: 2.0,
            mode: .structureATR,
            enableTP2Target: true,
            timeframe: .m15
        )
        XCTAssertNotNil(lv)
        if let lv {
            XCTAssertGreaterThanOrEqual(lv.riskRewardRatio, 2.0 - 1e-6)
            XCTAssertLessThanOrEqual(lv.riskRewardRatio, 4.0 + 1e-6)
            XCTAssertLessThanOrEqual(lv.tp2RiskRewardRatio, 6.0 + 1e-6, "TP2 must never explode to 1:16.7 on 15m")
            XCTAssertLessThan(lv.tp2, lv.tp1)
        }
    }

    func testCalibratedConfidenceClosedMarketPenaltyAndBreakdown() {
        let base: TimeInterval = 1_760_000_000
        let asset = WatchlistDefaults.descriptor(for: "NAS100")!
        let bar = Candle(openTimeEpochSeconds: base - 900, closeTimeEpochSeconds: base, open: 25920, high: 25940, low: 25880, close: 25890, volume: 500, isClosed: true)
        let ict = ICTAnalysis(
            swings: [], structureBreaks: [], fvgs: [], orderBlocks: [], liquiditySweeps: [],
            currentStructureBias: .short, equilibriumPrice: 25950, dealingRangeHigh: 26000,
            dealingRangeLow: 25800, dealingZone: .premium,
            contributions: [
                StrategyContribution(id: "ict_bos", name: "ICT BOS", group: .ictSmc, direction: .short, weight: 1.1, historicalWinRate: 0.58, detail: "BOS"),
                StrategyContribution(id: "ict_fvg", name: "Bearish FVG", group: .ictSmc, direction: .short, weight: 1.0, historicalWinRate: 0.57, detail: "FVG")
            ]
        )
        let mom = TrendMomentumSnapshot(
            ema20: 25920, ema50: 25950, ema200: 26010, rsi14: 44, atr14: 42, rvol: 1.6,
            htfTrendDirection: .short,
            contributions: [
                StrategyContribution(id: "momentum_ema_pullback", name: "EMA Pullback", group: .trendMomentum, direction: .short, weight: 1.05, historicalWinRate: 0.58, detail: "EMA")
            ]
        )
        let regime = RegimeAssessment(
            regime: .trending, riskState: .safe, atrPercent: 0.25, atrZScore: 0.1,
            efficiencyRatio: 0.55, rollingDrawdownPercent: 0.6, summary: "Trending"
        )
        let openSig = ConfluenceScorer.score(
            asset: asset, timeframe: .m15, htfTimeframe: .h4, candles: [bar], htfBias: .short,
            ict: ict, htfICT: nil, candlestickContributions: [], momentum: mom, regimeAssessment: regime,
            traps: [], positioning: nil, preNewsShield: nil, macroImpulse: nil,
            config: EngineConfig(), dataProvider: "biquote.io", isMarketClosed: false, nowEpochSeconds: base
        )
        let closedSig = ConfluenceScorer.score(
            asset: asset, timeframe: .m15, htfTimeframe: .h4, candles: [bar], htfBias: .short,
            ict: ict, htfICT: nil, candlestickContributions: [], momentum: mom, regimeAssessment: regime,
            traps: [], positioning: nil, preNewsShield: nil, macroImpulse: nil,
            config: EngineConfig(), dataProvider: "biquote.io", isMarketClosed: true, nowEpochSeconds: base
        )

        XCTAssertNotNil(openSig?.strengthBreakdown)
        XCTAssertNotNil(closedSig?.strengthBreakdown)
        XCTAssertLessThanOrEqual(openSig?.confidencePercent ?? 100, 92.0)
        XCTAssertLessThanOrEqual(closedSig?.confidencePercent ?? 100, 72.0, "Closed-market snapshots must be capped <= 72%")
        XCTAssertGreaterThan(openSig?.confidencePercent ?? 0, closedSig?.confidencePercent ?? 100)
    }

    func testPsychologyReportSeparatesIntradayProFlowFromCounterTrendWeeklyCOT() {
        let ict = ICTAnalysis(
            swings: [], structureBreaks: [], fvgs: [], orderBlocks: [], liquiditySweeps: [],
            currentStructureBias: .short, equilibriumPrice: 25950, dealingRangeHigh: 26000,
            dealingRangeLow: 25800, dealingZone: .premium, contributions: []
        )
        let cotPositioning = PositioningAssessment(
            provenance: .cftcCOT,
            proDirection: .long,
            retailCrowdDirection: .long,
            priceOIDivergence: .neutral,
            cotInstitutionalPercentile: 78.0,
            cotRetailPercentile: 62.0,
            summary: "CFTC COT Smart Money Net Long (78th pct)",
            badges: ["CFTC COT Smart Money Long"]
        )

        let report = PsychologyReportBuilder.build(
            category: .strongSignal,
            signalDirection: .short,
            ict: ict,
            traps: [],
            positioning: cotPositioning,
            macroImpulse: nil,
            rejectionReasons: [],
            rvol: nil,
            regime: .meanReverting
        )

        XCTAssertEqual(report.proDirection, .short, "Intraday Pro Flow must reflect SHORT setup, not opposing weekly COT")
        XCTAssertEqual(report.macroPositioningDirection, .long)
        XCTAssertEqual(report.macroPositioningLabel, "Weekly COT Macro")
        XCTAssertEqual(report.macroAlignsWithSetup, false)
        XCTAssertTrue(report.proPsychology.contains("counter-trend"))
        XCTAssertFalse(report.proPsychology.contains("Smart money aligned LONG"))
    }

    func testFlatMarketRSIReturnsNeutral50AndNAS100SessionHours() {
        let flatCloses = Array(repeating: 100.0, count: 30)
        let rsi = TrendMomentumDetector.computeRSI(closes: flatCloses, period: 14)
        XCTAssertFalse(rsi.isEmpty)
        XCTAssertEqual(rsi.last ?? -1.0, 50.0, accuracy: 1e-6, "Flat series RSI must be neutral 50.0, never 100.0")

        // Tuesday 03:00 UTC (Asian session): NAS100 23/5 futures/CFD is OPEN, while SPY US cash ETF is CLOSED
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 11
        comps.day = 24 // Tuesday
        comps.hour = 3
        comps.minute = 0
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let tuesdayAsianUTC = cal.date(from: comps)!.timeIntervalSince1970

        let nas100 = WatchlistDefaults.descriptor(for: "NAS100")!
        let spy = WatchlistDefaults.descriptor(for: "SPY")!
        XCTAssertTrue(SessionCalendar.isMarketOpen(asset: nas100, at: tuesdayAsianUTC))
        XCTAssertFalse(SessionCalendar.isMarketOpen(asset: spy, at: tuesdayAsianUTC))
    }

    func testHeadlineWordBoundaryAndNewsTradeAnalyzerSafety() {
        let now: TimeInterval = 1_760_000_000
        // "Central Bank" must NEVER match bearish keyword "ban"!
        let bankItem = HeadlineSentimentClassifier.classify(
            id: "bank-1",
            title: "Central Bank holds steady as banking sector reports stable reserves",
            source: "TestWire",
            publishedEpochSeconds: now - 600
        )
        XCTAssertFalse(bankItem.matchedKeywords.contains("ban"))
        XCTAssertNotEqual(bankItem.sentiment, .bearish)

        // Unpublished high-impact USD CPI event must produce WAIT / NO TRADE verdict
        let pendingCPI = EconomicEvent(
            semanticKey: "US|cpi|2026-11-24",
            source: .biquote,
            countryCode: "US",
            currency: "USD",
            name: "US CPI YoY",
            canonicalIndicator: .cpi,
            importance: .high,
            timeMode: .exact,
            scheduledEpochSeconds: now + 1800,
            unit: "%",
            actual: nil,
            forecast: 2.8,
            previous: 2.9,
            supportsActualRelease: true
        )
        let summary = NewsTradeAnalyzer.summarize(event: pendingCPI, nowEpochSeconds: now)
        XCTAssertTrue(summary.isPreReleasePending)
        XCTAssertTrue(summary.assetImpacts.contains { $0.symbol == "NAS100" })
        XCTAssertTrue(summary.assetImpacts.contains { $0.symbol == "XAU/USD" })

        let gold = WatchlistDefaults.descriptor(for: "XAU/USD")!
        let eval = NewsTradeAnalyzer.evaluateTrade(
            summary: summary,
            asset: gold,
            rawEntryCandles: [],
            rawHTFCandles: [],
            timeframe: .h1,
            dataProvider: "Test",
            serverNowEpochSeconds: now
        )
        XCTAssertEqual(eval.verdict, .waitNoTrade)
        XCTAssertFalse(eval.requiredConfirmations.isEmpty)
    }

    // MARK: - v1.4 Phase 1 (Workstream A): DST, Holidays, Fill Lifecycle, Calibration & Wilson CI Tests

    private func utcEpoch(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> TimeInterval {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = hour
        c.minute = minute
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal.date(from: c)!.timeIntervalSince1970
    }

    private func nyEpoch(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> TimeInterval {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = hour
        c.minute = minute
        return MarketHolidayCalendar.newYorkCalendar.date(from: c)!.timeIntervalSince1970
    }

    func testDSTKillzonesWinterSummerAndMismatchWeeks() {
        // Winter (Jan 15, 2026 — UK GMT=UTC+0, US EST=UTC-5)
        XCTAssertEqual(SessionCalendar.killzone(at: utcEpoch(2026, 1, 15, 6)), .asian)
        XCTAssertEqual(SessionCalendar.killzone(at: utcEpoch(2026, 1, 15, 7)), .london)
        XCTAssertEqual(SessionCalendar.killzone(at: utcEpoch(2026, 1, 15, 12)), .newYork)
        XCTAssertEqual(SessionCalendar.killzone(at: utcEpoch(2026, 1, 15, 15)), .londonClose)

        // Summer (Jul 15, 2026 — UK BST=UTC+1, US EDT=UTC-4)
        XCTAssertEqual(SessionCalendar.killzone(at: utcEpoch(2026, 7, 15, 5)), .asian)
        XCTAssertEqual(SessionCalendar.killzone(at: utcEpoch(2026, 7, 15, 6)), .london, "06:00 UTC is 07:00 BST -> London killzone")
        XCTAssertEqual(SessionCalendar.killzone(at: utcEpoch(2026, 7, 15, 11)), .newYork)
        XCTAssertEqual(SessionCalendar.killzone(at: utcEpoch(2026, 7, 15, 14)), .londonClose)

        // US/UK DST Mismatch Week (Mar 18, 2026 — US EDT=UTC-4, UK GMT=UTC+0)
        XCTAssertEqual(SessionCalendar.killzone(at: utcEpoch(2026, 3, 18, 6)), .asian)
        XCTAssertEqual(SessionCalendar.killzone(at: utcEpoch(2026, 3, 18, 7)), .london)
        XCTAssertEqual(SessionCalendar.killzone(at: utcEpoch(2026, 3, 18, 11)), .newYork)
        XCTAssertEqual(SessionCalendar.killzone(at: utcEpoch(2026, 3, 18, 14)), .londonClose)
    }

    func testNYSE2026And2027GoldenHolidayCalendarAndAssetRules() {
        // Golden NYSE 2026 full holidays (published calendar)
        let full2026: [(Int, Int)] = [
            (1, 1), (1, 19), (2, 16), (4, 3), (5, 25),
            (6, 19), (7, 3), (9, 7), (11, 26), (12, 25)
        ]
        for (m, d) in full2026 {
            let entry = MarketHolidayCalendar.nyseHoliday(year: 2026, month: m, day: d)
            XCTAssertEqual(entry?.kind, .fullClose, "Expected NYSE 2026 full close on 2026-\(m)-\(d)")
        }
        // Golden NYSE 2026 early closes (13:00 ET)
        let early2026: [(Int, Int)] = [(11, 27), (12, 24)]
        for (m, d) in early2026 {
            let entry = MarketHolidayCalendar.nyseHoliday(year: 2026, month: m, day: d)
            XCTAssertEqual(entry?.kind, .earlyClose1300ET, "Expected NYSE 2026 early close on 2026-\(m)-\(d)")
        }

        // Golden NYSE 2027 full holidays (published calendar)
        let full2027: [(Int, Int)] = [
            (1, 1), (1, 18), (2, 15), (3, 26), (5, 31),
            (6, 18), (7, 5), (9, 6), (11, 25), (12, 24)
        ]
        for (m, d) in full2027 {
            let entry = MarketHolidayCalendar.nyseHoliday(year: 2027, month: m, day: d)
            XCTAssertEqual(entry?.kind, .fullClose, "Expected NYSE 2027 full close on 2027-\(m)-\(d)")
        }
        // Golden NYSE 2027 early close (Black Friday; Dec 24 2027 is full close because Dec 25 is Sat)
        XCTAssertEqual(MarketHolidayCalendar.nyseHoliday(year: 2027, month: 11, day: 26)?.kind, .earlyClose1300ET)
        XCTAssertEqual(MarketHolidayCalendar.nyseHoliday(year: 2027, month: 12, day: 24)?.kind, .fullClose)
        // Non-weekend Jul 3 early close check (Mon Jul 3, 2028)
        XCTAssertEqual(MarketHolidayCalendar.nyseHoliday(year: 2028, month: 7, day: 3)?.kind, .earlyClose1300ET)

        // Asset-specific checks: Index CFDs (US500, NAS100) and Metals (XAU/USD) treat Good Friday & US early closes as closed/limited
        let nas100 = WatchlistDefaults.descriptor(for: "NAS100")!
        let us500 = WatchlistDefaults.descriptor(for: "US500")!
        let gold = WatchlistDefaults.descriptor(for: "XAU/USD")!
        let eurusd = WatchlistDefaults.descriptor(for: "EUR/USD")!
        let btc = WatchlistDefaults.descriptor(for: "BTC/USDT")!
        let spy = WatchlistDefaults.descriptor(for: "SPY")!

        // Good Friday 2026 (Apr 3, 11:00 ET) -> US500, NAS100, XAU/USD, SPY all closed; BTC open
        let goodFriday2026 = nyEpoch(2026, 4, 3, 11, 0)
        for asset in [nas100, us500, gold, spy] {
            let st = SessionCalendar.sessionStatus(asset: asset, at: goodFriday2026)
            XCTAssertFalse(st.isOpen, "\(asset.symbol) must be closed on Good Friday 2026")
            XCTAssertTrue(st.closedReason?.contains("Good Friday") == true)
        }
        XCTAssertTrue(SessionCalendar.isMarketOpen(asset: btc, at: goodFriday2026))

        // Black Friday 2026 (Nov 27): open at 11:00 ET, closed/limited at 13:30 ET for Index CFDs, Metals & SPY
        let blackFridayMorning = nyEpoch(2026, 11, 27, 11, 0)
        let blackFridayAfternoon = nyEpoch(2026, 11, 27, 13, 30)
        for asset in [nas100, us500, gold, spy] {
            XCTAssertTrue(SessionCalendar.isMarketOpen(asset: asset, at: blackFridayMorning), "\(asset.symbol) open before 13:00 ET")
            let afternoon = SessionCalendar.sessionStatus(asset: asset, at: blackFridayAfternoon)
            XCTAssertFalse(afternoon.isOpen, "\(asset.symbol) must be closed/limited after 13:00 ET on Black Friday")
            XCTAssertTrue(afternoon.closedReason?.contains("13:00 ET") == true)
        }

        // Christmas Day 2026 (Dec 25, 11:00 ET): FX, Metals, Indices, Stocks closed; Crypto open
        let xmas2026 = nyEpoch(2026, 12, 25, 11, 0)
        XCTAssertFalse(SessionCalendar.isMarketOpen(asset: eurusd, at: xmas2026))
        XCTAssertFalse(SessionCalendar.isMarketOpen(asset: gold, at: xmas2026))
        XCTAssertTrue(SessionCalendar.isMarketOpen(asset: btc, at: xmas2026))
    }

    func testSignalLifecycleFillWindowInvalidationFillBarSLOnlyAndPessimisticSameBar() {
        let base: TimeInterval = 1_760_000_000
        let levels = TradeLevels(
            entryLow: 99.8, entryHigh: 100.2, entryMid: 100.0,
            stopLoss: 98.0, tp1: 104.0, tp2: 107.0,
            riskPercent: 2.0, reward1Percent: 4.0, reward2Percent: 7.0,
            riskRewardRatio: 2.0, tp2RiskRewardRatio: 3.5, isTP2Enabled: true
        )
        let psych = PsychologyReport(
            signalCategory: .strongSignal, proDirection: .long, retailCrowdDirection: .short,
            provenanceBadge: "Test", whatHappened: "Test", beginnerPsychology: "B", proPsychology: "P",
            behavioralBadges: [], evidence: []
        )
        let sig = TradeSignal(
            id: "sig-life", fingerprint: "sig-life", symbol: "BTC/USDT", displayName: "Bitcoin",
            marketClass: .crypto, timeframe: .h1, htfTimeframe: .h4,
            category: .strongSignal, direction: .long, tier: .highConviction,
            confidencePercent: 80.0, regime: .trending, riskState: .safe,
            killzone: .newYork, htfBias: .long,
            generatedAtEpochSeconds: base, barCloseEpochSeconds: base,
            levels: levels, alignedStrategies: [], rejectionReasons: [],
            psychologyReport: psych, dataProvider: "Fixture"
        )

        // 1. Pending -> Filled -> Open
        let missBar = Candle(openTimeEpochSeconds: base, closeTimeEpochSeconds: base + 3600, open: 101.0, high: 102.0, low: 100.8, close: 101.5, volume: 100)
        let pendingOut = PassiveOutcomeEvaluator.evaluate(signal: sig, subsequentClosedCandles: [missBar], fillWindowBars: 4)
        XCTAssertEqual(pendingOut.status, .pending)
        XCTAssertEqual(pendingOut.lifecycleStatus, .pending)
        XCTAssertNil(pendingOut.filledAtEpochSeconds)

        let fillBar = Candle(openTimeEpochSeconds: base + 3600, closeTimeEpochSeconds: base + 7200, open: 101.5, high: 101.8, low: 100.0, close: 100.8, volume: 100)
        let openOut = PassiveOutcomeEvaluator.evaluate(signal: sig, subsequentClosedCandles: [missBar, fillBar], fillWindowBars: 4)
        XCTAssertEqual(openOut.status, .open)
        XCTAssertEqual(openOut.lifecycleStatus, .open)
        XCTAssertEqual(openOut.filledAtEpochSeconds, base + 7200)

        // 2. Fill-Bar Rule (Amendment #4): On fill bar, check SL ONLY. TP1/TP2 on the fill bar MUST NOT trigger a win!
        let fillAndSpikeTP2Bar = Candle(openTimeEpochSeconds: base, closeTimeEpochSeconds: base + 3600, open: 100.0, high: 108.5, low: 99.9, close: 107.8, volume: 200)
        let fillBarNoWin = PassiveOutcomeEvaluator.evaluate(signal: sig, subsequentClosedCandles: [fillAndSpikeTP2Bar])
        XCTAssertEqual(fillBarNoWin.status, .open, "TP checks must NOT fire on the fill bar itself")

        // If fill bar touches entry AND SL -> immediate pessimistic SL hit
        let fillAndHitSLBar = Candle(openTimeEpochSeconds: base, closeTimeEpochSeconds: base + 3600, open: 100.0, high: 108.5, low: 97.5, close: 106.0, volume: 200)
        let fillBarSL = PassiveOutcomeEvaluator.evaluate(signal: sig, subsequentClosedCandles: [fillAndHitSLBar])
        XCTAssertEqual(fillBarSL.status, .hitSL, "SL must be checked on the fill bar itself")

        // 3. Post-fill same-bar conflict (hits BOTH SL and TP2) -> pessimistic SL-first
        let cleanFill = Candle(openTimeEpochSeconds: base, closeTimeEpochSeconds: base + 3600, open: 100.0, high: 101.0, low: 99.9, close: 100.5, volume: 100)
        let sameBarConflict = Candle(openTimeEpochSeconds: base + 3600, closeTimeEpochSeconds: base + 7200, open: 100.5, high: 108.0, low: 97.5, close: 107.5, volume: 300)
        let conflictOut = PassiveOutcomeEvaluator.evaluate(signal: sig, subsequentClosedCandles: [cleanFill, sameBarConflict])
        XCTAssertEqual(conflictOut.status, .hitSL, "Same-bar SL + TP conflict must resolve pessimistically as SL")

        // 4. Fill window expiry -> .notFilled (excluded from win rate)
        let threeMisses = (0..<3).map { i in
            Candle(openTimeEpochSeconds: base + Double(i) * 3600, closeTimeEpochSeconds: base + Double(i + 1) * 3600, open: 101.0, high: 102.0, low: 100.8, close: 101.5, volume: 100)
        }
        let notFilledOut = PassiveOutcomeEvaluator.evaluate(signal: sig, subsequentClosedCandles: threeMisses, fillWindowBars: 3)
        XCTAssertEqual(notFilledOut.status, .notFilled)
        XCTAssertEqual(notFilledOut.lifecycleStatus, .notFilled)

        // 5. Pre-fill invalidation: price hits TP1 without ever touching entry zone -> .invalidated
        let runawayTP1 = Candle(openTimeEpochSeconds: base, closeTimeEpochSeconds: base + 3600, open: 101.5, high: 104.5, low: 101.2, close: 104.2, volume: 100)
        let invOut = PassiveOutcomeEvaluator.evaluate(signal: sig, subsequentClosedCandles: [runawayTP1])
        XCTAssertEqual(invOut.status, .invalidated)
        XCTAssertEqual(invOut.lifecycleStatus, .invalidated)

        // Verify notFilled & invalidated are excluded from headline Win Rate denominator
        let summary = PassiveOutcomeEvaluator.summarize(records: [notFilledOut, invOut, fillBarSL], filter: .headlineFixed)
        XCTAssertEqual(summary.resolvedSignals, 1)
        XCTAssertEqual(summary.notFilledCount, 1)
        XCTAssertEqual(summary.invalidatedCount, 1)
        XCTAssertEqual(summary.winRate, 0.0, accuracy: 1e-9)
    }

    func testWilsonIntervalConfidenceCalibratorAndHeadlineLegacyExclusion() throws {
        // 1. Wilson 95% CI exact bounds
        XCTAssertNil(WilsonInterval.compute(wins: 0, total: 0))
        let ci = WilsonInterval.compute(wins: 58, total: 100)
        XCTAssertNotNil(ci)
        XCTAssertEqual(ci?.lower ?? 0, 0.482, accuracy: 0.005)
        XCTAssertEqual(ci?.upper ?? 0, 0.672, accuracy: 0.005)

        // 2. ConfidenceCalibrator: inactive at N = 99, active at N = 120, monotonic & improves Brier on overconfident fixture
        func makeSyntheticRecord(idx: Int, rawScore: Double, isWin: Bool) -> SignalOutcomeRecord {
            SignalOutcomeRecord(
                signalId: "cal-\(idx)",
                symbol: "BTC/USDT",
                marketClass: .crypto,
                category: .strongSignal,
                direction: .long,
                predictedProbability: rawScore / 100.0,
                status: isWin ? .hitTP1 : .hitSL,
                netReturnPercent: isWin ? 2.0 : -1.0,
                rMultiple: isWin ? 2.0 : -1.0,
                strategyIds: ["ict_fvg"],
                hadMacroCatalyst: false,
                resolvedAtEpochSeconds: 1_760_000_000 + Double(idx) * 3600,
                lifecycleStatus: .resolved,
                filledAtEpochSeconds: 1_760_000_000 + Double(idx) * 3600 - 1800,
                fillWindowBars: 12,
                isLegacyImmediateFill: false
            )
        }

        // Deterministic overconfident dataset: raw scores 70..90, actual win rate ~45% at 70 and ~65% at 90
        var records: [SignalOutcomeRecord] = []
        for i in 0..<120 {
            let highBucket = (i % 2 == 0)
            let score = highBucket ? 88.0 : 72.0
            let mod = i % 20
            let isWin = highBucket ? (mod < 12) : (mod < 8) // 60% vs 40%, while raw predicts 88% vs 72%
            records.append(makeSyntheticRecord(idx: i, rawScore: score, isWin: isWin))
        }

        let underThreshold = ConfidenceCalibrator.fit(records: Array(records.prefix(99)), filter: .headlineFixed)
        XCTAssertFalse(underThreshold.isActive)
        XCTAssertNil(underThreshold.calibratedProbability(forRawScore: 85.0))

        let fitted = ConfidenceCalibrator.fit(records: records, filter: .headlineFixed)
        XCTAssertTrue(fitted.isActive)
        XCTAssertEqual(fitted.sampleCount, 120)
        let pHigh = fitted.calibratedProbability(forRawScore: 88.0)!
        let pLow = fitted.calibratedProbability(forRawScore: 72.0)!
        XCTAssertGreaterThan(pHigh, pLow, "Calibrated probabilities must stay strictly monotonic")

        let rawBrier = records.reduce(0.0) { acc, r in
            let y = r.isWin ? 1.0 : 0.0
            let d = r.predictedProbability - y
            return acc + d * d
        } / Double(records.count)
        let calBrier = records.reduce(0.0) { acc, r in
            let y = r.isWin ? 1.0 : 0.0
            let p = fitted.calibratedProbability(forRawScore: r.predictedProbability * 100.0)!
            let d = p - y
            return acc + d * d
        } / Double(records.count)
        XCTAssertLessThan(calBrier, rawBrier, "Platt scaling must improve Brier score on overconfident raw scores")

        // 3. Pre-v1.4 legacy JSON decodes as legacy-immediate-fill and is excluded from headlineFixed
        let legacyJSON = """
        {
          "signalId": "legacy-pre-14",
          "symbol": "XAU/USD",
          "marketClass": "metals",
          "category": "STRONG_SIGNAL",
          "direction": "long",
          "predictedProbability": 0.80,
          "status": "hitTP2",
          "netReturnPercent": 3.5,
          "rMultiple": 3.0,
          "strategyIds": ["ict_bos"],
          "hadMacroCatalyst": false,
          "resolvedAtEpochSeconds": 1760010000
        }
        """.data(using: .utf8)!
        let legacyRec = try JSONDecoder().decode(SignalOutcomeRecord.self, from: legacyJSON)
        XCTAssertTrue(legacyRec.effectiveIsLegacyImmediateFill)

        let summaryWithLegacy = PassiveOutcomeEvaluator.summarize(records: [legacyRec, records[0]], filter: .headlineFixed)
        XCTAssertEqual(summaryWithLegacy.legacyExcludedCount, 1)
        XCTAssertEqual(summaryWithLegacy.resolvedSignals, 1, "Headline win rate must exclude pre-v1.4 legacy-immediate-fill record")
    }
}
