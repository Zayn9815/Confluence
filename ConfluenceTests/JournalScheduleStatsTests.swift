import Foundation
import XCTest
@testable import Confluence
import SignalEngine

final class JournalScheduleStatsTests: XCTestCase {
    // MARK: - Live Quote Freshness & Automatic Journal Tick Tracking Tests

    func testLiveQuoteFreshnessAndAutomaticJournalLiveTickTracking() {
        let now: TimeInterval = 1_776_175_200
        let liveQuote = LivePriceQuote(
            symbol: "BTC/USDT",
            price: 61_000,
            asOfEpochSeconds: now - 3,
            sourceLabel: "Binance Live",
            isStreaming: true
        )
        XCTAssertEqual(liveQuote.freshness(nowEpochSeconds: now), .live)

        // Stale >60s quote -> OFFLINE freshness
        let staleQuote = LivePriceQuote(
            symbol: "BTC/USDT",
            price: 61_000,
            asOfEpochSeconds: now - 90,
            sourceLabel: "Binance Live",
            isStreaming: true
        )
        XCTAssertEqual(staleQuote.freshness(nowEpochSeconds: now), .offline)

        // Entry 60k, SL 59k, Target 1 62k, live 61k -> +1.0R, +1.67%
        let entry = TrackedJournalTrade(
            id: "tj-live-1",
            symbol: "BTC/USDT",
            assetClass: .crypto,
            timeframe: .m30,
            direction: .long,
            section: .strongSignals,
            status: .live,
            score: 82.0,
            signalBarTimestamp: now - 600,
            entryZoneLow: 59_900,
            entryZoneHigh: 60_100,
            entryPrice: 60_000,
            fillPrice: 60_000,
            stopLoss: 59_000,
            target1: 62_000,
            target2: 63_500,
            isTP2Enabled: true,
            currentPrice: 60_000,
            createdAt: now - 600,
            filledAt: now - 300
        )
        let updated = SignalJournalEngine.evaluateLiveTick(
            entry: entry,
            livePrice: liveQuote.price,
            now: now
        )
        XCTAssertEqual(updated.status, .live)
        XCTAssertEqual(updated.liveRMultiple, 1.0, accuracy: 0.001)
        XCTAssertEqual(updated.livePnLPercent, (1_000.0 / 60_000.0) * 100.0, accuracy: 0.01)
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
        let trapOut = SignalOutcomeRecord(
            signalId: "sig-trap-1",
            symbol: "XAU/USD",
            marketClass: .metals,
            category: .trapAlert,
            direction: .long,
            predictedProbability: 0.74,
            status: .hitTP2,
            netReturnPercent: 2.5,
            rMultiple: 2.5,
            strategyIds: ["trap_bull_bear_sweep"],
            hadMacroCatalyst: false,
            resolvedAtEpochSeconds: 1_776_175_200,
            lifecycleStatus: .resolved,
            isLegacyImmediateFill: false,
            origin: .scanner
        )
        store.updateOutcome(strongOut)
        store.updateOutcome(weakOut)
        store.updateOutcome(trapOut)

        let coord = MarketScannerCoordinator(settings: settings, store: store)
        XCTAssertEqual(coord.originWinRates.count, 3)

        let strongCard = coord.originWinRates.first { $0.group == .strongSignals }
        let weakCard = coord.originWinRates.first { $0.group == .weakAndFiltered }
        let trapCard = coord.originWinRates.first { $0.group == .trapAlerts }

        XCTAssertEqual(strongCard?.wins, 1)
        XCTAssertEqual(strongCard?.losses, 0)
        XCTAssertEqual(weakCard?.losses, 1) // weakOut tracked even with Show Weak OFF
        XCTAssertEqual(trapCard?.wins, 1)

        // 3 automatic Journal sections always populated
        XCTAssertEqual(coord.journalSectionStats.map(\.section), [.strongSignals, .weakAndFiltered, .trapAlerts])

        // Bucket 60-69 is empty -> "No trades yet"
        let bucket60 = coord.strengthBuckets.first { $0.id == "60_69" }
        XCTAssertEqual(bucket60?.summaryText, "No trades yet")
    }
}
