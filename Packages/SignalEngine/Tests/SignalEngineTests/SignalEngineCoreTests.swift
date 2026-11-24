import Foundation
import XCTest
@testable import SignalEngine

final class SignalEngineCoreTests: XCTestCase {
    private func makeBar(
        index: Int,
        open: Double,
        high: Double,
        low: Double,
        close: Double,
        volume: Double? = 1_000,
        step: TimeInterval = 3_600,
        baseEpoch: TimeInterval = 1_760_000_000,
        isClosed: Bool = true
    ) -> Candle {
        let openT = baseEpoch + Double(index) * step
        return Candle(
            openTimeEpochSeconds: openT,
            closeTimeEpochSeconds: openT + step,
            open: open,
            high: high,
            low: low,
            close: close,
            volume: volume,
            isClosed: isClosed
        )
    }

    func testClosedCandleAntiRepaintingAndOTCNilVolume() {
        let now: TimeInterval = 1_760_000_000 + 50 * 3_600
        var bars: [Candle] = []
        for i in 0..<50 {
            bars.append(makeBar(index: i, open: 2600, high: 2610, low: 2595, close: 2605, volume: 0))
        }
        // Append an open forming bar closing in the future
        bars.append(makeBar(index: 50, open: 2605, high: 2630, low: 2600, close: 2625, volume: 0, isClosed: false))
        bars.append(makeBar(index: 51, open: 2625, high: 2650, low: 2620, close: 2645, volume: 0, isClosed: true))

        let sanitized = CandleHygieneEngine.sanitize(
            rawCandles: bars,
            symbol: "XAU/USD",
            marketClass: .metals,
            timeframe: .h1,
            providerName: "Test",
            serverNowEpochSeconds: now
        )

        XCTAssertEqual(sanitized.report.droppedOpenBars, 2)
        XCTAssertEqual(sanitized.candles.count, 50)
        // OTC feed with zero reported volume MUST be nil (never fake 0)
        XCTAssertTrue(sanitized.candles.allSatisfy { $0.volume == nil })

        let mom = TrendMomentumDetector.analyze(candles: sanitized.candles)
        XCTAssertNil(mom.rvol)
    }

    func testClockSkewAndStaleFeedRejection() {
        let base: TimeInterval = 1_760_000_000
        let bars = (0..<45).map { i in
            makeBar(index: i, open: 60_000, high: 60_500, low: 59_500, close: 60_100, baseEpoch: base)
        }
        let serverNow = base + 45 * 3_600

        let skewed = CandleHygieneEngine.sanitize(
            rawCandles: bars,
            symbol: "BTC/USDT",
            marketClass: .crypto,
            timeframe: .h1,
            providerName: "Binance",
            serverNowEpochSeconds: serverNow,
            clockSkewSeconds: 250.0
        )
        XCTAssertEqual(skewed.report.rejectionReason, .excessiveClockSkew)
        XCTAssertFalse(skewed.report.isUsable)

        let stale = CandleHygieneEngine.sanitize(
            rawCandles: bars,
            symbol: "BTC/USDT",
            marketClass: .crypto,
            timeframe: .h1,
            providerName: "Binance",
            serverNowEpochSeconds: serverNow + 20_000.0
        )
        XCTAssertEqual(stale.report.rejectionReason, .staleFeedDuringOpenSession)
        XCTAssertTrue(stale.report.isStale)
    }

    func testCausal1HTo4HUTCResamplingDropsOpenBucket() {
        // Align to exact UTC 4H boundary (14400 * 122222 = 1759996800)
        let boundary: TimeInterval = 1_759_996_800
        var hourly: [Candle] = []
        for i in 0..<10 {
            let p = 100.0 + Double(i)
            hourly.append(makeBar(index: i, open: p, high: p + 2, low: p - 1, close: p + 1, volume: 100, step: 3_600, baseEpoch: boundary))
        }
        // Only 2 full 4H buckets (hours 0..3 and 4..7) are closed at boundary + 10h; bucket 8..11 is open!
        let serverNow = boundary + 10 * 3_600
        let h4 = CandleHygieneEngine.resample1HTo4H(hourlyCandles: hourly, serverNowEpochSeconds: serverNow)
        XCTAssertEqual(h4.count, 2)
        XCTAssertEqual(h4[0].open, 100.0)
        XCTAssertEqual(h4[0].high, 105.0)
        XCTAssertEqual(h4[0].low, 99.0)
        XCTAssertEqual(h4[0].close, 104.0)
        XCTAssertEqual(h4[0].volume, 400.0)
    }

    func testStrictPrefixInvarianceZeroLookaheadInICTDetector() {
        // Build a 70-bar oscillating + breakout series
        var bars: [Candle] = []
        for i in 0..<70 {
            let wave = sin(Double(i) * 0.45) * 10.0 + Double(i) * 0.25
            let o = 100.0 + wave
            let c = o + ((i % 3 == 0) ? 2.8 : -1.2)
            let h = max(o, c) + 1.4
            let l = min(o, c) - 1.4
            bars.append(makeBar(index: i, open: o, high: h, low: l, close: c, volume: 1_000 + Double(i * 15)))
        }

        // Prefix-invariance: evaluating upTo t on full array vs sliced prefix[0...t] MUST match identically
        for t in [25, 35, 48, 60] {
            let sliced = Array(bars[0...t])
            let fullUpToT = CausalICTDetector.analyze(candles: bars, upTo: t)
            let prefixOnly = CausalICTDetector.analyze(candles: sliced)

            XCTAssertEqual(fullUpToT.swings, prefixOnly.swings, "Swing lookahead detected at bar \(t)")
            XCTAssertEqual(fullUpToT.structureBreaks, prefixOnly.structureBreaks, "BOS/MSS lookahead detected at bar \(t)")
            XCTAssertEqual(fullUpToT.fvgs, prefixOnly.fvgs, "FVG lookahead detected at bar \(t)")
            XCTAssertEqual(fullUpToT.orderBlocks, prefixOnly.orderBlocks, "OB lookahead detected at bar \(t)")
            XCTAssertEqual(fullUpToT.liquiditySweeps, prefixOnly.liquiditySweeps, "Sweep lookahead detected at bar \(t)")
            XCTAssertEqual(fullUpToT.currentStructureBias, prefixOnly.currentStructureBias)

            // Verify no pivot has confirmedAtIndex > t
            XCTAssertTrue(prefixOnly.swings.allSatisfy { $0.confirmedAtIndex <= t })
            XCTAssertTrue(prefixOnly.fvgs.allSatisfy { $0.formedAtIndex <= t })
            XCTAssertTrue(prefixOnly.orderBlocks.allSatisfy { $0.validFromIndex <= t })
        }
    }

    func testCrisisRegimeForcesReduceRiskState() {
        var bars: [Candle] = []
        for i in 0..<45 {
            bars.append(makeBar(index: i, open: 100, high: 100.8, low: 99.4, close: 100.2))
        }
        // Inject massive flash-crash crisis candle (>14% drop and huge ATR shock)
        bars.append(makeBar(index: 45, open: 100.2, high: 100.5, low: 82.0, close: 84.0))

        let assessment = MarketRegimeClassifier.classify(candles: bars)
        XCTAssertEqual(assessment.regime, .crisis)
        XCTAssertEqual(assessment.riskState, .reduce)
    }

    func testCandlestickPatternsEngulfingAndHammer() {
        var bars = (0..<16).map { i in
            makeBar(index: i, open: 100, high: 101, low: 99, close: 100.1)
        }
        // Prior bearish bar + strong bullish engulfing bar
        bars.append(makeBar(index: 16, open: 100.5, high: 100.8, low: 99.2, close: 99.4))
        bars.append(makeBar(index: 17, open: 99.2, high: 102.2, low: 99.0, close: 101.8))

        let engulfing = CandlestickPatternDetector.detect(candles: bars)
        XCTAssertTrue(engulfing.contains { $0.id == "candle_bullish_engulfing" && $0.direction == .long })

        // Append clean hammer rejection bar
        bars.append(makeBar(index: 18, open: 101.0, high: 101.2, low: 98.0, close: 101.1))
        let hammer = CandlestickPatternDetector.detect(candles: bars)
        XCTAssertTrue(hammer.contains { $0.id == "candle_hammer_pinbar" && $0.direction == .long })
    }
}
