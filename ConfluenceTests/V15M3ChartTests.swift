import Foundation
import XCTest
@testable import Confluence
import SignalEngine

final class V15M3ChartTests: XCTestCase {
    func testLiveChartThrottleEnforcesOneHzLimit() {
        var throttle = LiveChartThrottle(minimumIntervalSeconds: 1.0)
        XCTAssertTrue(throttle.shouldEmit(at: 100.0))
        XCTAssertFalse(throttle.shouldEmit(at: 100.2))
        XCTAssertFalse(throttle.shouldEmit(at: 100.99))
        XCTAssertTrue(throttle.shouldEmit(at: 101.0))
        XCTAssertFalse(throttle.shouldEmit(at: 101.5))
        XCTAssertTrue(throttle.shouldEmit(at: 102.1))
    }

    func testChartPagingPolicyTriggersNearLeftEdgeAndStopsAtCap() {
        XCTAssertTrue(ChartPagingPolicy.shouldRequestOlderPage(
            visibleFromLogical: 25,
            currentBarCount: 500,
            isLoadingInitial: false,
            isLoadingOlder: false,
            hasReachedHistoryEnd: false
        ))
        // Far from left edge -> do not page
        XCTAssertFalse(ChartPagingPolicy.shouldRequestOlderPage(
            visibleFromLogical: 180,
            currentBarCount: 500,
            isLoadingInitial: false,
            isLoadingOlder: false,
            hasReachedHistoryEnd: false
        ))
        // Already at 5,000 cap -> do not page
        XCTAssertFalse(ChartPagingPolicy.shouldRequestOlderPage(
            visibleFromLogical: 5,
            currentBarCount: 5_000,
            isLoadingInitial: false,
            isLoadingOlder: false,
            hasReachedHistoryEnd: false
        ))
        // Currently loading -> do not double-fetch
        XCTAssertFalse(ChartPagingPolicy.shouldRequestOlderPage(
            visibleFromLogical: 5,
            currentBarCount: 500,
            isLoadingInitial: false,
            isLoadingOlder: true,
            hasReachedHistoryEnd: false
        ))
    }

    @MainActor
    func testChartSessionControllerLiveUpdateAndOlderMergePreserveFitToken() {
        let base: TimeInterval = 1_760_000_400
        let step: TimeInterval = 3_600
        let initial = (10..<30).map { i in
            Candle(
                openTimeEpochSeconds: base + Double(i) * step,
                closeTimeEpochSeconds: base + Double(i + 1) * step,
                open: 59_000, high: 59_500, low: 58_800, close: 59_200,
                volume: 100, isClosed: true
            )
        }

        let ctrl = ChartSessionController(
            symbol: "BTC/USDT",
            marketClass: .crypto,
            timeframe: .h1,
            initialCandles: initial
        )
        let initialFitToken = ctrl.fitRequestToken

        // Live tick updates forming candle WITHOUT bumping fitRequestToken
        let q = LivePriceQuote(
            symbol: "BTC/USDT",
            price: 59_450,
            asOfEpochSeconds: base + 30 * step + 120,
            sourceLabel: "Binance Live",
            isStreaming: true
        )
        let forming = ctrl.ingestLiveQuote(q)
        XCTAssertNotNil(forming)
        XCTAssertEqual(forming?.isClosed, false)
        XCTAssertEqual(ctrl.fitRequestToken, initialFitToken)
        XCTAssertEqual(ctrl.formingCandle?.close, 59_450)

        // Merging older history appends bars WITHOUT bumping fitRequestToken
        let older = (0..<10).map { i in
            Candle(
                openTimeEpochSeconds: base + Double(i) * step,
                closeTimeEpochSeconds: base + Double(i + 1) * step,
                open: 58_000, high: 58_600, low: 57_800, close: 58_400,
                volume: 90, isClosed: true
            )
        }
        ctrl.beginOlderPageLoad()
        ctrl.finishOlderPageLoad(olderCandles: older, serverNowEpochSeconds: base + 31 * step)
        XCTAssertEqual(ctrl.closedCandles.count, 30)
        XCTAssertEqual(ctrl.fitRequestToken, initialFitToken)

        // Reset explicitly bumps fitRequestToken
        ctrl.requestResetView()
        XCTAssertEqual(ctrl.fitRequestToken, initialFitToken + 1)
    }

    func testChartEngineOptionDefaultsToCandleKitAndMigratesRemovedEngines() {
        XCTAssertEqual(ChartEngineOption.allCases, [.candleKit, .dgCharts, .swiftTradingView, .tradingViewWeb])
        XCTAssertEqual(ChartEngineOption.fromStoredRawValue("lightweightCharts"), .candleKit)
        XCTAssertEqual(ChartEngineOption.fromStoredRawValue("dgCharts"), .dgCharts)
        XCTAssertEqual(ChartEngineOption.fromStoredRawValue("unknown_engine"), .candleKit)
    }
}
