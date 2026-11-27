import Foundation
import XCTest
@testable import SignalEngine

final class V16AuditCoverageTests: XCTestCase {
    func testWithAIJudgmentEnforcesCodeOwnedRiskRegimeAndCategoryGates() {
        let base: TimeInterval = 1_760_000_000
        let psych = PsychologyReport(
            signalCategory: .strongSignal,
            proDirection: .long,
            retailCrowdDirection: .short,
            provenanceBadge: "Test",
            whatHappened: "Structure aligned.",
            beginnerPsychology: "Clean trend.",
            proPsychology: "Institutional demand held.",
            behavioralBadges: [],
            evidence: []
        )
        let validJudgment = ReflexJudgment(
            regime: "trending",
            direction: .long,
            setupQuality: 3,
            confidence: 0.90,
            riskState: .safe,
            agree: true,
            catalystBias: "bullish",
            invalidationCheck: "Invalidates on close below OB."
        )

        let crisisSignal = TradeSignal(
            id: "sig-crisis",
            fingerprint: "sig-crisis",
            symbol: "BTC/USDT",
            displayName: "Bitcoin",
            marketClass: .crypto,
            timeframe: .h1,
            htfTimeframe: .h4,
            category: .strongSignal,
            direction: .long,
            tier: .highConviction,
            confidencePercent: 78.0,
            regime: .crisis,
            riskState: .safe,
            killzone: .newYork,
            htfBias: .long,
            generatedAtEpochSeconds: base,
            barCloseEpochSeconds: base,
            levels: nil,
            alignedStrategies: [],
            rejectionReasons: [],
            psychologyReport: psych,
            dataProvider: "Binance"
        )
        XCTAssertFalse(crisisSignal.withAIJudgment(validJudgment, threshold: 0.80).aiConfirmed)

        let weakSignal = TradeSignal(
            id: "sig-weak",
            fingerprint: "sig-weak",
            symbol: "BTC/USDT",
            displayName: "Bitcoin",
            marketClass: .crypto,
            timeframe: .h1,
            htfTimeframe: .h4,
            category: .weakSignal,
            direction: .long,
            tier: .weakFiltered,
            confidencePercent: 60.0,
            regime: .trending,
            riskState: .safe,
            killzone: .newYork,
            htfBias: .long,
            generatedAtEpochSeconds: base,
            barCloseEpochSeconds: base,
            levels: nil,
            alignedStrategies: [],
            rejectionReasons: ["Low confluence"],
            psychologyReport: psych,
            dataProvider: "Binance"
        )
        XCTAssertFalse(weakSignal.withAIJudgment(validJudgment, threshold: 0.80).aiConfirmed)

        let safeStrong = TradeSignal(
            id: "sig-safe",
            fingerprint: "sig-safe",
            symbol: "BTC/USDT",
            displayName: "Bitcoin",
            marketClass: .crypto,
            timeframe: .h1,
            htfTimeframe: .h4,
            category: .strongSignal,
            direction: .long,
            tier: .highConviction,
            confidencePercent: 80.0,
            regime: .trending,
            riskState: .safe,
            killzone: .newYork,
            htfBias: .long,
            generatedAtEpochSeconds: base,
            barCloseEpochSeconds: base,
            levels: nil,
            alignedStrategies: [],
            rejectionReasons: [],
            psychologyReport: psych,
            dataProvider: "Binance"
        )
        XCTAssertTrue(safeStrong.withAIJudgment(validJudgment, threshold: 0.80).aiConfirmed)
    }

    func testReflexJudgmentSchemaRejectsInvalidEnumsAndOversizedInvalidation() {
        let badRegime = ReflexJudgment(
            regime: "moon_mode",
            direction: .long,
            setupQuality: 3,
            confidence: 0.85,
            riskState: .safe,
            agree: true,
            catalystBias: "bullish",
            invalidationCheck: "Below swing low."
        )
        XCTAssertFalse(badRegime.isSchemaValid())

        let badCatalyst = ReflexJudgment(
            regime: "trending",
            direction: .long,
            setupQuality: 3,
            confidence: 0.85,
            riskState: .safe,
            agree: true,
            catalystBias: "mega_bull",
            invalidationCheck: "Below swing low."
        )
        XCTAssertFalse(badCatalyst.isSchemaValid())

        let hugeCheck = ReflexJudgment(
            regime: "trending",
            direction: .long,
            setupQuality: 3,
            confidence: 0.85,
            riskState: .safe,
            agree: true,
            catalystBias: "neutral",
            invalidationCheck: String(repeating: "x", count: 221)
        )
        XCTAssertFalse(hugeCheck.isSchemaValid())
    }

    func testCausalDuplicateSuppressionIgnoresFutureTimestamps() {
        let now: TimeInterval = 1_760_000_000
        let futureHistory: [(fingerprint: String, symbol: String, direction: TradeDirection, epochSeconds: TimeInterval)] = [
            (fingerprint: "other", symbol: "BTC/USDT", direction: .long, epochSeconds: now + 600)
        ]
        XCTAssertFalse(
            ConfluenceScorer.shouldSuppressDuplicate(
                fingerprint: "new-fp",
                symbol: "BTC/USDT",
                direction: .long,
                nowEpochSeconds: now,
                recentHistory: futureHistory,
                cooldownSeconds: 3_600
            )
        )
    }

    func testSignalJournalEngineFillBarSLOnlyAndNoRepeatReEvaluation() {
        let bar0: TimeInterval = 1_760_000_000
        let tf: Timeframe = .h1
        let step = tf.seconds

        let entry = TrackedJournalTrade(
            id: "j-fill-bar-test",
            symbol: "BTC/USDT",
            assetClass: .crypto,
            timeframe: tf,
            direction: .long,
            section: .strongSignals,
            status: .pending,
            score: 82.0,
            signalBarTimestamp: bar0,
            entryZoneLow: 99.5,
            entryZoneHigh: 100.5,
            entryPrice: 100.0,
            fillPrice: nil,
            stopLoss: 98.0,
            target1: 104.0,
            target2: 108.0,
            isTP2Enabled: true,
            currentPrice: 101.0,
            livePnLPercent: 0.0,
            liveRMultiple: 0.0,
            realizedR: nil,
            isWinLocked: false,
            createdAt: bar0 + step,
            filledAt: nil,
            tp1HitAt: nil,
            closedAt: nil,
            lastEvaluatedAt: bar0 + step
        )

        // Bar 1 dips into entry (100.0) and rallies above TP1 (105.0) on the SAME fill bar:
        // Fill-Bar SL-Only rule MUST NOT award TP1 on the fill bar, and repeat reconcile MUST NOT re-evaluate Bar 1.
        let fillBar = Candle(
            openTimeEpochSeconds: bar0 + step,
            closeTimeEpochSeconds: bar0 + step * 2,
            open: 101.0,
            high: 105.0,
            low: 99.8,
            close: 104.5,
            volume: 100.0,
            isClosed: true
        )

        let afterFirst = SignalJournalEngine.reconcile(
            entry: entry,
            againstClosedCandles: [fillBar],
            now: bar0 + step * 2 + 10
        )
        XCTAssertEqual(afterFirst.status, .live)
        XCTAssertFalse(afterFirst.isWinLocked)

        // Repeat reconcile against the exact same closed bar must stay .live (strict > on lastEvaluatedAt)
        let afterRepeat = SignalJournalEngine.reconcile(
            entry: afterFirst,
            againstClosedCandles: [fillBar],
            now: bar0 + step * 2 + 20
        )
        XCTAssertEqual(afterRepeat.status, .live)
        XCTAssertFalse(afterRepeat.isWinLocked)
    }

    func testLiveCandleAggregatorConfirmsLegitimateGapOnThirdTick() {
        let base: TimeInterval = 1_760_004_000 // Exact UTC 1H boundary (488_890 * 3_600)
        let seed = Candle(
            openTimeEpochSeconds: base - 3_600,
            closeTimeEpochSeconds: base,
            open: 100.0,
            high: 101.0,
            low: 99.0,
            close: 100.0,
            volume: 50.0,
            isClosed: true
        )
        var agg = LiveCandleAggregator(timeframe: .h1, seed: seed, marketClass: .forex) // 2% guard

        // Isolated spike (5% gap) rejected on ticks 1 and 2
        if case .rejected = agg.ingest(LiveTick(price: 105.0, epochSeconds: base + 10)) {
            // expected
        } else {
            XCTFail("Expected 1st gap tick to be rejected")
        }
        if case .rejected = agg.ingest(LiveTick(price: 105.1, epochSeconds: base + 20)) {
            // expected
        } else {
            XCTFail("Expected 2nd gap tick to be rejected")
        }
        // 3rd consecutive clustered tick confirms legitimate gap
        if case .formingUpdated(let bar) = agg.ingest(LiveTick(price: 105.05, epochSeconds: base + 30)) {
            XCTAssertEqual(bar.close, 105.05, accuracy: 1e-6)
        } else {
            XCTFail("Expected 3rd clustered gap tick to confirm and resume live forming updates")
        }
    }

    func testResample15MTo30MPreservesNilVolumeWhenConstituentMissingVolume() {
        let base: TimeInterval = 1_760_000_400 // Exact UTC 30m boundary (977_778 * 1_800)
        let b1 = Candle(
            openTimeEpochSeconds: base,
            closeTimeEpochSeconds: base + 900,
            open: 100, high: 102, low: 99, close: 101,
            volume: 50,
            isClosed: true
        )
        let b2 = Candle(
            openTimeEpochSeconds: base + 900,
            closeTimeEpochSeconds: base + 1_800,
            open: 101, high: 103, low: 100, close: 102,
            volume: nil,
            isClosed: true
        )
        let resampled = CandleHygieneEngine.resample15MTo30M(
            m15Candles: [b1, b2],
            serverNowEpochSeconds: base + 2_000
        )
        XCTAssertEqual(resampled.count, 1)
        XCTAssertNil(resampled.first?.volume)
    }
}
