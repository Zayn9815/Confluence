import XCTest
@testable import SignalEngine

final class StrategyFilteringTests: XCTestCase {

    func testProvenWinnersPresetAndCategoryCoverage() {
        XCTAssertEqual(
            StrategyID.provenWinners,
            [.ictBos, .ictOrderBlock, .ictFvg, .ictPremiumEq, .trapOslerRoundNumber]
        )
        let categorized = StrategyCategory.allCases.flatMap(\.strategies)
        XCTAssertEqual(Set(categorized), Set(StrategyID.allCases))
        XCTAssertEqual(categorized.count, StrategyID.allCases.count, "Every StrategyID must belong to exactly one StrategyCategory")
    }

    func testCandlestickDetectorHardGateSkipsDisabledPatterns() {
        let base: TimeInterval = 1_760_000_000
        var candles: [Candle] = []
        for i in 0..<20 {
            let t = base + Double(i) * 3600
            candles.append(Candle(openTimeEpochSeconds: t, closeTimeEpochSeconds: t + 3600, open: 100, high: 101, low: 99, close: 100.2, volume: 1000, isClosed: true))
        }
        // Prior bearish bar + large bullish engulfing displacement bar
        let tPrev = base + 20 * 3600
        candles.append(Candle(openTimeEpochSeconds: tPrev, closeTimeEpochSeconds: tPrev + 3600, open: 100.5, high: 100.7, low: 99.8, close: 99.9, volume: 1000, isClosed: true))
        let tCur = base + 21 * 3600
        candles.append(Candle(openTimeEpochSeconds: tCur, closeTimeEpochSeconds: tCur + 3600, open: 99.8, high: 103.0, low: 99.7, close: 102.9, volume: 2000, isClosed: true))

        let allDetected = CandlestickPatternDetector.detect(candles: candles, enabled: StrategyID.allSet)
        XCTAssertTrue(allDetected.contains { $0.id == "candle_bullish_engulfing" })
        XCTAssertTrue(allDetected.contains { $0.id == "candle_displacement" })

        let onlyDisplacement = CandlestickPatternDetector.detect(candles: candles, enabled: [.candleDisplacement])
        XCTAssertEqual(onlyDisplacement.map(\.id), ["candle_displacement"])

        let noneDetected = CandlestickPatternDetector.detect(candles: candles, enabled: [.ictFvg])
        XCTAssertTrue(noneDetected.isEmpty)
    }

    func testTrapLifecycleEngineHardGateSkipsDisabledTraps() {
        let base: TimeInterval = 1_760_000_000
        var candles: [Candle] = []
        for i in 0..<20 {
            let t = base + Double(i) * 3600
            candles.append(Candle(openTimeEpochSeconds: t, closeTimeEpochSeconds: t + 3600, open: 99.2, high: 99.8, low: 98.8, close: 99.5, volume: 1000, isClosed: true))
        }
        // Osler round-number 100.00 bull trap sweep: open <= 100, high > 100, close < 100, large upper wick
        let tTrap = base + 20 * 3600
        candles.append(Candle(openTimeEpochSeconds: tTrap, closeTimeEpochSeconds: tTrap + 3600, open: 99.6, high: 101.2, low: 99.4, close: 99.5, volume: 1500, isClosed: true))

        let ict = CausalICTDetector.analyze(candles: candles, enabled: StrategyID.allSet)

        let withOsler = TrapLifecycleEngine.evaluate(
            symbol: "BTC/USDT",
            roundNumberStep: 10.0,
            candles: candles,
            ict: ict,
            enabled: [.trapOslerRoundNumber]
        )
        XCTAssertTrue(withOsler.contains { $0.triggerKind == .oslerRoundNumberSweep })

        let withoutOsler = TrapLifecycleEngine.evaluate(
            symbol: "BTC/USDT",
            roundNumberStep: 10.0,
            candles: candles,
            ict: ict,
            enabled: [.trapNewsWhipsaw, .ictBos]
        )
        XCTAssertTrue(withoutOsler.isEmpty)
    }

    func testScorerDynamicConfluenceMinimumAndStrictStrategyFiltering() {
        let base: TimeInterval = 1_760_000_000
        let asset = WatchlistDefaults.descriptor(for: "GBP/USD")!
        let bar = Candle(openTimeEpochSeconds: base - 3600, closeTimeEpochSeconds: base, open: 1.3090, high: 1.3105, low: 1.3088, close: 1.3100, volume: nil, isClosed: true)
        let fvgContrib = StrategyContribution(id: "ict_fvg", name: "Bullish FVG", group: .ictSmc, direction: .long, weight: 1.4, historicalWinRate: 0.65, detail: "FVG")
        let obContrib = StrategyContribution(id: "ict_order_block", name: "Bullish Order Block", group: .ictSmc, direction: .long, weight: 1.2, historicalWinRate: 0.60, detail: "OB")
        let ict = ICTAnalysis(
            swings: [], structureBreaks: [], fvgs: [], orderBlocks: [], liquiditySweeps: [],
            currentStructureBias: .long, equilibriumPrice: 1.3110, dealingRangeHigh: nil,
            dealingRangeLow: nil, dealingZone: nil, contributions: [fvgContrib, obContrib]
        )
        let mom = TrendMomentumSnapshot(ema20: 1.3095, ema50: 1.3090, ema200: 1.3070, rsi14: 58, atr14: 0.0012, rvol: nil, htfTrendDirection: .long, contributions: [])
        let regime = RegimeAssessment(
            regime: .trending, riskState: .safe, atrPercent: 0.35, atrZScore: 0.2,
            efficiencyRatio: 0.65, rollingDrawdownPercent: 0.4, summary: "Trending"
        )

        // Enable ONLY ictFvg while configured minimumAlignedStrategies is 3 -> effectiveMinConfluence == 1
        let cfg = EngineConfig(
            minimumConfidencePercent: 60.0,
            minimumRiskReward: 2.0,
            levelCalculationMode: .fixedPercent,
            fixedStopLossPercent: 0.5,
            fixedTP1Percent: 1.0,
            minimumAlignedStrategies: 3,
            enabledStrategies: [.ictFvg]
        )
        XCTAssertEqual(cfg.effectiveMinConfluence(configured: 3), 1)

        let signal = ConfluenceScorer.score(
            asset: asset, timeframe: .h1, htfTimeframe: .h4, candles: [bar], htfBias: .long,
            ict: ict, htfICT: nil, candlestickContributions: [], momentum: mom, regimeAssessment: regime,
            traps: [], positioning: nil, preNewsShield: nil, macroImpulse: nil,
            config: cfg, dataProvider: "Twelve Data", isMarketClosed: false, nowEpochSeconds: base
        )
        XCTAssertNotNil(signal)
        XCTAssertEqual(signal?.category, .strongSignal)
        XCTAssertEqual(signal?.alignedStrategies.map(\.id), ["ict_fvg"], "Disabled ict_order_block must not appear")
        XCTAssertEqual(signal?.matchedStrategyIDs, [.ictFvg])
    }
}
