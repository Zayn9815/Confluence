import Foundation
import XCTest
@testable import Confluence
import SignalEngine

final class V15M4WalletScheduleStatsTests: XCTestCase {
    // MARK: - JournalLiveRowTests

    func testLivePositionRowMetricsProgressBarAndOfflineFreshness() {
        let now: TimeInterval = 1_776_175_200
        let liveQuote = LivePriceQuote(
            symbol: "BTC/USDT",
            price: 61_000,
            asOfEpochSeconds: now - 3,
            sourceLabel: "Binance Live",
            isStreaming: true
        )
        // Entry 60k, SL 59k, Target 1 62k -> span = 3k; 61k is 2k above SL -> 2/3 progress, +1.0R
        let m = LivePositionRowMetrics.compute(
            direction: .long,
            entryPrice: 60_000,
            stopLoss: 59_000,
            target1: 62_000,
            liveQuote: liveQuote,
            fallbackPrice: 60_000,
            pnlUSD: 20.0,
            marginUSD: 200.0,
            nowEpochSeconds: now
        )
        XCTAssertEqual(m.rMultiple, 1.0, accuracy: 0.001)
        XCTAssertEqual(m.returnPercent, 10.0, accuracy: 0.01)
        XCTAssertEqual(m.pnlUSD ?? 0, 20.0, accuracy: 0.01)
        XCTAssertEqual(m.stopToTargetProgress, 2.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(m.entryMarkerFraction, 1.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(m.freshness, .live)

        // Stale >60s quote -> OFFLINE badge
        let staleQuote = LivePriceQuote(
            symbol: "BTC/USDT",
            price: 61_000,
            asOfEpochSeconds: now - 90,
            sourceLabel: "Binance Live",
            isStreaming: true
        )
        let mStale = LivePositionRowMetrics.compute(
            direction: .long,
            entryPrice: 60_000,
            stopLoss: 59_000,
            target1: 62_000,
            liveQuote: staleQuote,
            fallbackPrice: 60_000,
            nowEpochSeconds: now
        )
        XCTAssertEqual(mStale.freshness, .offline)
    }

    // MARK: - ScanOnOpenTests

    @MainActor
    func testScanOnOpenRespectsTwoMinuteGapAndScheduleCountdown() {
        let store = ConfluenceDataStore(inMemory: true)
        let settings = AppSettingsStore()
        settings.payload.scanOnOpenEnabled = true
        settings.payload.autoScanIntervalMinutes = 30
        let coord = MarketScannerCoordinator(settings: settings, store: store)

        let now: TimeInterval = 1_776_175_200
        // Last scan 60s ago -> MUST NOT trigger scan-on-open (< 2 min gap)
        coord.lastScanDate = Date(timeIntervalSince1970: now - 60)
        XCTAssertFalse(ScanSchedulePolicy.shouldScanOnOpen(
            enabled: coord.settings.payload.scanOnOpenEnabled,
            lastScanEpochSeconds: coord.lastScanDate?.timeIntervalSince1970,
            nowEpochSeconds: now
        ))

        // Last scan 180s ago -> eligible
        coord.lastScanDate = Date(timeIntervalSince1970: now - 180)
        XCTAssertTrue(ScanSchedulePolicy.shouldScanOnOpen(
            enabled: coord.settings.payload.scanOnOpenEnabled,
            lastScanEpochSeconds: coord.lastScanDate?.timeIntervalSince1970,
            nowEpochSeconds: now
        ))

        // Usage estimate reflects configured 30-min default
        let est = coord.scanUsageEstimate
        XCTAssertEqual(est.effectiveIntervalMinutes, 30)
        XCTAssertGreaterThan(est.scansPerDay, 0)
        XCTAssertGreaterThan(est.estimatedRequestsPerDay, 0)
    }

    // MARK: - WinRateBreakdownViewModelTests

    @MainActor
    func testCoordinatorComputesThreeOriginCardsAndTracksWeakAndNewsOutcomes() {
        let store = ConfluenceDataStore(inMemory: true)
        let settings = AppSettingsStore()
        // Even with Show Weak / Filtered OFF, weak outcomes still count in Traps & Filtered stats
        settings.payload.showWeakFilteredSignals = false

        let strongOut = SignalOutcomeRecord(
            signalId: "sig-strong-1",
            symbol: "BTC/USDT",
            marketClass: .crypto,
            category: .strongSignal,
            direction: .long,
            predictedProbability: 0.82,
            status: .hitTP1,
            netReturnPercent: 2.0,
            rMultiple: 2.0,
            strategyIds: ["ict_fvg"],
            hadMacroCatalyst: false,
            resolvedAtEpochSeconds: 1_776_175_000,
            lifecycleStatus: .resolved,
            isLegacyImmediateFill: false,
            origin: .scanner
        )
        let weakOut = SignalOutcomeRecord(
            signalId: "sig-weak-1",
            symbol: "ETH/USDT",
            marketClass: .crypto,
            category: .weakSignal,
            direction: .short,
            predictedProbability: 0.58,
            status: .hitSL,
            netReturnPercent: -1.0,
            rMultiple: -1.0,
            strategyIds: ["ict_fvg"],
            hadMacroCatalyst: false,
            resolvedAtEpochSeconds: 1_776_175_100,
            lifecycleStatus: .resolved,
            isLegacyImmediateFill: false,
            origin: .scanner
        )
        let newsOut = SignalOutcomeRecord(
            signalId: "sig-news-1",
            symbol: "XAU/USD",
            marketClass: .metals,
            category: .strongSignal,
            direction: .long,
            predictedProbability: 0.74,
            status: .hitTP2,
            netReturnPercent: 2.5,
            rMultiple: 2.5,
            strategyIds: ["macro_surprise_catalyst"],
            hadMacroCatalyst: true,
            resolvedAtEpochSeconds: 1_776_175_200,
            lifecycleStatus: .resolved,
            isLegacyImmediateFill: false,
            origin: .news
        )
        store.updateOutcome(strongOut)
        store.updateOutcome(weakOut)
        store.updateOutcome(newsOut)

        let coord = MarketScannerCoordinator(settings: settings, store: store)
        XCTAssertEqual(coord.originWinRates.count, 3)

        let strongCard = coord.originWinRates.first { $0.group == .strongSignals }
        let trapsCard = coord.originWinRates.first { $0.group == .trapsAndFiltered }
        let newsCard = coord.originWinRates.first { $0.group == .newsSetups }

        XCTAssertEqual(strongCard?.wins, 1)
        XCTAssertEqual(strongCard?.losses, 0)
        XCTAssertEqual(trapsCard?.losses, 1) // weakOut tracked even with Show Weak OFF
        XCTAssertEqual(trapsCard?.positiveCountLabel, "Worked")
        XCTAssertEqual(trapsCard?.negativeCountLabel, "Failed")
        XCTAssertEqual(newsCard?.wins, 1)

        // Bucket 60-69 is empty -> "No trades yet"
        let bucket60 = coord.strengthBuckets.first { $0.id == "60_69" }
        XCTAssertEqual(bucket60?.summaryText, "No trades yet")
    }
}
