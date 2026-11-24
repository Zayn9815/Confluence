import Foundation
import XCTest
@testable import SignalEngine

final class BehavioralAndMacroTests: XCTestCase {
    private func makeBar(
        index: Int,
        open: Double,
        high: Double,
        low: Double,
        close: Double,
        volume: Double? = 1_000,
        step: TimeInterval = 3_600,
        baseEpoch: TimeInterval = 1_760_000_000
    ) -> Candle {
        let t = baseEpoch + Double(index) * step
        return Candle(
            openTimeEpochSeconds: t,
            closeTimeEpochSeconds: t + step,
            open: open,
            high: high,
            low: low,
            close: close,
            volume: volume,
            isClosed: true
        )
    }

    func testTrapLifecycleTriggerActiveReturnedInvalidOnCloseOnly() {
        var bars: [Candle] = []
        // Baseline trading just below 1000.0 round level
        for i in 0..<25 {
            bars.append(makeBar(index: i, open: 992, high: 996, low: 988, close: 993))
        }
        // Bar 25: Osler round-number sweep above 1000.0, closing back below 1000.0 -> Trigger Bull Trap
        bars.append(makeBar(index: 25, open: 995, high: 1008, low: 994, close: 996))
        let ict25 = CausalICTDetector.analyze(candles: bars)
        let traps25 = TrapLifecycleEngine.evaluate(symbol: "BTC/USDT", roundNumberStep: 1000.0, candles: bars, ict: ict25)
        let trapAt25 = traps25.first { $0.triggerBarIndex == 25 }
        XCTAssertNotNil(trapAt25)
        XCTAssertEqual(trapAt25?.direction, .bullTrap)
        XCTAssertEqual(trapAt25?.triggerKind, .oslerRoundNumberSweep)
        XCTAssertEqual(trapAt25?.state, .trigger)

        // Bar 26: Moves away below 1000 -> Transitions to Active
        bars.append(makeBar(index: 26, open: 996, high: 998, low: 989, close: 991))
        let traps26 = TrapLifecycleEngine.evaluate(symbol: "BTC/USDT", roundNumberStep: 1000.0, candles: bars, ict: CausalICTDetector.analyze(candles: bars))
        XCTAssertEqual(traps26.first { $0.triggerBarIndex == 25 }?.state, .active)

        // Bar 27: WICKS up to 1002 (touching 1000 level) but CLOSES at 997 (below 1000) -> MUST be Returned, NOT Invalid!
        bars.append(makeBar(index: 27, open: 991, high: 1002, low: 990, close: 997))
        let traps27 = TrapLifecycleEngine.evaluate(symbol: "BTC/USDT", roundNumberStep: 1000.0, candles: bars, ict: CausalICTDetector.analyze(candles: bars))
        XCTAssertEqual(traps27.first { $0.triggerBarIndex == 25 }?.state, .returned)

        // Bar 28: CLOSES strictly above 1000 (1004) -> NOW transitions to Invalid!
        bars.append(makeBar(index: 28, open: 997, high: 1006, low: 996, close: 1004))
        let traps28 = TrapLifecycleEngine.evaluate(symbol: "BTC/USDT", roundNumberStep: 1000.0, candles: bars, ict: CausalICTDetector.analyze(candles: bars))
        XCTAssertEqual(traps28.first { $0.triggerBarIndex == 25 }?.state, .invalid)
        XCTAssertEqual(traps28.first { $0.triggerBarIndex == 25 }?.invalidatedAtBarIndex, 28)
    }

    func testAttentionFOMOSpikeDetection() {
        var bars: [Candle] = []
        for i in 0..<24 {
            bars.append(makeBar(index: i, open: 100, high: 101, low: 99, close: 100.2, volume: 1_000))
        }
        // Parabolic spike with 4.5x RVOL extended >2 ATR above EMA-20 with large exhaustion upper wick
        bars.append(makeBar(index: 24, open: 100.5, high: 109.5, low: 100.2, close: 102.0, volume: 4_500))

        let ict = CausalICTDetector.analyze(candles: bars)
        let traps = TrapLifecycleEngine.evaluate(symbol: "SOL/USDT", roundNumberStep: 500.0, candles: bars, ict: ict)
        XCTAssertTrue(traps.contains { $0.triggerKind == .attentionFOMOSpike && $0.direction == .bullTrap })
    }

    func testOKXShortSqueezeDetectionWith1DutcAlignment() {
        let base: TimeInterval = 1_760_000_000
        // Rising price candles
        let bars = (0..<12).map { i in
            let p = 60_000.0 + Double(i) * 400.0
            return makeBar(index: i, open: p, high: p + 300, low: p - 100, close: p + 250, baseEpoch: base)
        }
        // Falling Open Interest -> Price Up + OI Down = Short Squeeze
        let oiPoints = (0..<10).map { i in
            OKXOpenInterestPoint(
                timestampEpochSeconds: base + Double(i) * 3_600,
                openInterestContracts: 50_000 - Double(i) * 800,
                openInterestCoin: 500 - Double(i) * 8,
                openInterestUSD: 3_000_000_000 - Double(i) * 55_000_000,
                period: "1Dutc"
            )
        }
        let fundingHistory = (0..<15).map { i in
            OKXFundingPoint(fundingTimeEpochSeconds: base - Double(15 - i) * 28_800, fundingRate: 0.0001, realizedRate: 0.0001)
        }
        let snap = OKXDerivativesSnapshot(
            instId: "BTC-USDT-SWAP",
            currentFundingRate: -0.0004,
            nextFundingTimeEpochSeconds: base + 28_800,
            liveOpenInterestUSD: 2_500_000_000,
            fundingHistory: fundingHistory,
            openInterestHistory: oiPoints,
            fetchedAtEpochSeconds: base + 12 * 3_600
        )

        let pos = PositioningAnalyzer.analyzeOKX(snapshot: snap, candles: bars)
        XCTAssertEqual(pos.priceOIDivergence, .shortSqueeze)
        XCTAssertEqual(pos.proDirection, .long)
        XCTAssertEqual(pos.retailCrowdDirection, .short)
        XCTAssertTrue(pos.badges.contains("Short Squeeze"))
    }

    func testCFTCCOTFridayPublicationLookaheadGuard() {
        let tuesdayReport: TimeInterval = 1_760_000_000
        let fridayRelease: TimeInterval = tuesdayReport + 3 * 86_400 + 20.5 * 3_600
        let record = CFTCCOTRecord(
            contractCode: "088691",
            marketName: "GOLD - COMEX",
            dataset: .disaggregatedFuturesOnly,
            reportDateEpochSeconds: tuesdayReport,
            publishedAtEpochSeconds: fridayRelease,
            openInterest: 500_000,
            institutionalLong: 240_000,
            institutionalShort: 60_000,
            nonReportableLong: 20_000,
            nonReportableShort: 55_000
        )

        // Before Friday 20:30 UTC release -> MUST NOT leak future COT report
        let beforeRelease = PositioningAnalyzer.analyzeCFTCCOT(records: [record], asOfEpochSeconds: tuesdayReport + 86_400)
        XCTAssertNil(beforeRelease)

        // After Friday release -> cleanly observable
        let afterRelease = PositioningAnalyzer.analyzeCFTCCOT(records: [record], asOfEpochSeconds: fridayRelease + 60)
        XCTAssertNotNil(afterRelease)
        XCTAssertEqual(afterRelease?.provenance, .cftcCOT)
        XCTAssertEqual(afterRelease?.proDirection, .long)
    }

    func testEconomicCalendarNullActualAndNonExactTimeModeGuards() {
        let now: TimeInterval = 1_760_000_000
        let gold = WatchlistDefaults.descriptor(for: "XAU/USD")!

        // Unpublished event with actual == nil MUST NEVER be coerced to 0
        let pendingCPI = EconomicEvent(
            semanticKey: "US|cpi|2026-11-24",
            source: .biquote,
            countryCode: "US",
            currency: "USD",
            name: "CPI y/y",
            canonicalIndicator: .cpi,
            importance: .high,
            timeMode: .exact,
            scheduledEpochSeconds: now + 600,
            actual: nil,
            forecast: 2.8,
            previous: 2.9,
            supportsActualRelease: true
        )
        XCTAssertNil(MacroSurpriseEngine.evaluateSurprise(event: pendingCPI, nowEpochSeconds: now))

        // Tentative / non-exact event MUST suppress countdown timer & notifications
        let tentativeEvent = EconomicEvent(
            semanticKey: "US|gdp|2026-11-24",
            source: .biquote,
            countryCode: "US",
            currency: "USD",
            name: "GDP QoQ",
            canonicalIndicator: .gdp,
            importance: .high,
            timeMode: .tentative,
            scheduledEpochSeconds: now + 600,
            actual: nil,
            forecast: 2.1,
            supportsActualRelease: true
        )
        XCTAssertNil(MacroSurpriseEngine.preNewsShield(for: gold, events: [tentativeEvent], nowEpochSeconds: now))
        XCTAssertTrue(MacroSurpriseEngine.planPreNewsNotificationSlots(events: [tentativeEvent], nowEpochSeconds: now, leadTimesMinutes: [15, 5]).isEmpty)

        // Hotter US CPI (3.2% vs 2.8% forecast) -> Hawkish USD -> USD ↑, XAU/USD ↓, BTC/USDT ↓
        let hotCPI = EconomicEvent(
            semanticKey: "US|cpi|2026-11-24",
            source: .biquote,
            countryCode: "US",
            currency: "USD",
            name: "CPI y/y",
            canonicalIndicator: .cpi,
            importance: .high,
            timeMode: .exact,
            scheduledEpochSeconds: now - 600,
            actual: 3.2,
            forecast: 2.8,
            previous: 2.9,
            revisedPrevious: 3.0,
            supportsActualRelease: true
        )
        let surprise = MacroSurpriseEngine.evaluateSurprise(event: hotCPI, nowEpochSeconds: now)
        XCTAssertEqual(surprise?.currencyStance, .hawkish)
        XCTAssertTrue(hotCPI.hasRevision)
        XCTAssertEqual(MacroPolarityTable.impactDirection(for: gold, currency: "USD", stance: .hawkish), .short)

        // Higher Unemployment Rate (4.5% vs 4.1% forecast) -> Dovish USD -> XAU/USD ↑
        let highUnemp = EconomicEvent(
            semanticKey: "US|unemp|2026-11-24",
            source: .biquote,
            countryCode: "US",
            currency: "USD",
            name: "Unemployment Rate",
            canonicalIndicator: .unemploymentRate,
            importance: .high,
            timeMode: .exact,
            scheduledEpochSeconds: now - 600,
            actual: 4.5,
            forecast: 4.1,
            supportsActualRelease: true
        )
        let unempRes = MacroSurpriseEngine.evaluateSurprise(event: highUnemp, nowEpochSeconds: now)
        XCTAssertEqual(unempRes?.currencyStance, .dovish)
        XCTAssertEqual(MacroPolarityTable.impactDirection(for: gold, currency: "USD", stance: .dovish), .long)
    }

    func testSimultaneousReleasesClusterMixedWhipsawAnd64NotificationQueueCap() {
        let now: TimeInterval = 1_760_000_000
        // Simultaneous NFP beat (hawkish) + Unemployment surge (dovish) at exact same minute -> Mixed Whipsaw
        let nfp = EconomicEvent(
            semanticKey: "US|nfp|1", source: .biquote, countryCode: "US", currency: "USD",
            name: "Nonfarm Payrolls", canonicalIndicator: .nfp, importance: .high, timeMode: .exact,
            scheduledEpochSeconds: now - 400, actual: 260, forecast: 170, supportsActualRelease: true
        )
        let unemp = EconomicEvent(
            semanticKey: "US|unemp|1", source: .biquote, countryCode: "US", currency: "USD",
            name: "Unemployment Rate", canonicalIndicator: .unemploymentRate, importance: .high, timeMode: .exact,
            scheduledEpochSeconds: now - 400, actual: 4.6, forecast: 4.1, supportsActualRelease: true
        )
        let clusters = MacroSurpriseEngine.buildClusters(events: [nfp, unemp], nowEpochSeconds: now)
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters.first?.netStance, .mixedWhipsaw)
        XCTAssertEqual(clusters.first?.isWhipsawCautionActive, true)

        // Feed 50 upcoming exact high-impact events with 2 lead times -> MUST cap strictly at <= 40 slots (safely under iOS 64 limit)
        let manyEvents = (1...50).map { i in
            EconomicEvent(
                semanticKey: "US|ev|\(i)", source: .biquote, countryCode: "US", currency: "USD",
                name: "Event \(i)", importance: .high, timeMode: .exact,
                scheduledEpochSeconds: now + Double(i) * 3_600
            )
        }
        let slots = MacroSurpriseEngine.planPreNewsNotificationSlots(
            events: manyEvents,
            nowEpochSeconds: now,
            leadTimesMinutes: [15, 5],
            maxSlots: 40
        )
        XCTAssertLessThanOrEqual(slots.count, 40)
        XCTAssertEqual(slots.count, 40)
    }

    func testHeadlineSentimentLexicon() {
        let bullish = HeadlineSentimentClassifier.classify(
            id: "1",
            title: "SEC grants Spot Bitcoin ETF Approval sparking record inflows",
            source: "TestWire",
            publishedEpochSeconds: 1_760_000_000
        )
        XCTAssertEqual(bullish.sentiment, .bullish)
        XCTAssertTrue(bullish.affectedAssets.contains("BTC/USDT"))

        let bearish = HeadlineSentimentClassifier.classify(
            id: "2",
            title: "Major crypto exchange hack triggers liquidation cascade",
            source: "TestWire",
            publishedEpochSeconds: 1_760_000_000
        )
        XCTAssertEqual(bearish.sentiment, .bearish)
    }
}
