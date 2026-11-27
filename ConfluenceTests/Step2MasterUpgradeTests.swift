import XCTest
import Foundation
@testable import Confluence
import SignalEngine

final class Step2MasterUpgradeTests: XCTestCase {

    // MARK: - ChartEngineOption Resilient Decoding

    func testChartEngineOptionDecodesTradingViewWebAndFallsBackOnUnknown() throws {
        let validJSON = Data("\"tradingViewWeb\"".utf8)
        let decoded = try JSONDecoder().decode(ChartEngineOption.self, from: validJSON)
        XCTAssertEqual(decoded, .tradingViewWeb)

        let legacyJSON = Data("\"lightweightCharts\"".utf8)
        let legacyMigrated = try JSONDecoder().decode(ChartEngineOption.self, from: legacyJSON)
        XCTAssertEqual(legacyMigrated, .candleKit)

        let unknownJSON = Data("\"removed_future_engine_v9\"".utf8)
        let fallback = try JSONDecoder().decode(ChartEngineOption.self, from: unknownJSON)
        XCTAssertEqual(fallback, .candleKit)
    }

    // MARK: - CryptoOrderFlowVenueSymbols & Hard Non-Crypto Gate

    func testCryptoOrderFlowVenueSymbolsNormalizesMajorsAnd1000MultiplierMemes() {
        let btc = CryptoOrderFlowVenueSymbols.resolve(symbol: "BTC/USDT")
        XCTAssertEqual(btc.base, "BTC")
        XCTAssertEqual(btc.okxSwapInstId, "BTC-USDT-SWAP")
        XCTAssertEqual(btc.bybitLinearSymbol, "BTCUSDT")
        XCTAssertEqual(btc.binanceFuturesSymbol, "BTCUSDT")

        let pepe = CryptoOrderFlowVenueSymbols.resolve(symbol: "PEPE/USDT")
        XCTAssertEqual(pepe.base, "PEPE")
        XCTAssertEqual(pepe.okxSwapInstId, "PEPE-USDT-SWAP")
        XCTAssertEqual(pepe.bybitLinearSymbol, "1000PEPEUSDT")
        XCTAssertEqual(pepe.binanceFuturesSymbol, "1000PEPEUSDT")
        XCTAssertEqual(pepe.bybitSpotSymbol, "PEPEUSDT")
    }

    func testCryptoOrderFlowAdapterEnforcesHardNonCryptoGateWithZeroNetworkCalls() async {
        struct FailingHTTP: HTTPTransport {
            func send(_ request: URLRequest, maxRetries: Int) async throws -> HTTPResponseData {
                XCTFail("Network request must NEVER be issued for non-crypto markets")
                throw URLError(.cancelled)
            }

            func estimatedClockSkewSeconds() async -> TimeInterval {
                0
            }
        }

        let adapter = CryptoOrderFlowAdapter(http: FailingHTTP())
        let forexSnap = await adapter.fetchSnapshot(symbol: "EUR/USD", assetClass: .forex)
        let metalSnap = await adapter.fetchSnapshot(symbol: "XAU/USD", assetClass: .metals)
        let stockSnap = await adapter.fetchSnapshot(symbol: "AAPL", assetClass: .stocks)
        let indexSnap = await adapter.fetchSnapshot(symbol: "US500", assetClass: .indices)

        XCTAssertNil(forexSnap)
        XCTAssertNil(metalSnap)
        XCTAssertNil(stockSnap)
        XCTAssertNil(indexSnap)
    }

    // MARK: - TradingView Sync URL Layout Path Preservation

    @MainActor
    func testTradingViewSyncURLPreservesCustomLayoutPath() {
        let existing = URL(string: "https://www.tradingview.com/chart/AbCdEf12/?symbol=OANDA%3AEURUSD&interval=60")!
        let synced = TradingViewWebSessionManager.buildSyncURL(
            symbol: "BTC/USDT",
            timeframe: .h4,
            existingURL: existing,
            isDark: true
        )
        XCTAssertEqual(synced.host, "www.tradingview.com")
        XCTAssertEqual(synced.path, "/chart/AbCdEf12")
        XCTAssertTrue(synced.absoluteString.contains("BINANCE"))
        XCTAssertTrue(synced.absoluteString.contains("BTCUSDT"))
        XCTAssertTrue(synced.absoluteString.contains("interval=240"))
        XCTAssertTrue(synced.absoluteString.contains("theme=dark"))
    }

    // MARK: - SideStore Dynamic Bundle ID Backup Acceptance & tvLastChartURL Round-Trip

    func testBackupArchiveAcceptsSideStoreSuffixedBundleIDAndPreservesTVChartURL() throws {
        let payload = PersistedSettingsPayload()
        let archive = ConfluenceBackupArchive(
            schemaVersion: ConfluenceBackupArchive.currentSchemaVersion,
            appBundleId: "com.bilal.confluence.ABC123TEAM",
            appVersion: "1.5.0",
            settings: payload,
            signals: [],
            outcomes: [],
            tradeLedger: [],
            trackedJournalEntries: [],
            tvLastChartURL: "https://www.tradingview.com/chart/MyLayout1/?symbol=BINANCE:BTCUSDT&interval=60"
        )
        let encoded = try JSONEncoder().encode(archive)
        let decoded = try BackupArchiveService.decodeAndValidateArchive(from: encoded)
        XCTAssertEqual(decoded.appBundleId, "com.bilal.confluence.ABC123TEAM")
        XCTAssertEqual(
            decoded.tvLastChartURL,
            "https://www.tradingview.com/chart/MyLayout1/?symbol=BINANCE:BTCUSDT&interval=60"
        )
    }

    // MARK: - PersistedSettingsPayload Backwards Compatibility & Core Floor

    func testPersistedSettingsPayloadDecodesMissingOrderFlowAndDesktopWebFlagsSafely() throws {
        // Minimal legacy JSON omitting new Step 2+ fields must decode with safe defaults
        let legacyJSON = Data("{}".utf8)
        let decoded = try JSONDecoder().decode(PersistedSettingsPayload.self, from: legacyJSON)
        XCTAssertFalse(decoded.isOrderFlowEnabled)
        XCTAssertFalse(decoded.tradingViewPreferDesktop)
        XCTAssertEqual(decoded.chartEngine, .candleKit)
    }

    @MainActor
    func testAppSettingsCoreFloorBlocksDisablingLastCoreStrategy() {
        let store = AppSettingsStore()
        let original = store.payload
        defer { store.payload = original }

        store.payload.enabledStrategies = [.ictBos]
        let accepted = store.setStrategyEnforcingCoreFloor(.ictBos, enabled: false)
        XCTAssertFalse(accepted)
        XCTAssertTrue(store.payload.enabledStrategies.contains(.ictBos))

        let enabledAnother = store.setStrategyEnforcingCoreFloor(.momentumEmaPullback, enabled: true)
        XCTAssertTrue(enabledAnother)
        let disabledFirst = store.setStrategyEnforcingCoreFloor(.ictBos, enabled: false)
        XCTAssertTrue(disabledFirst)
        XCTAssertEqual(store.payload.enabledStrategies, [.momentumEmaPullback])
    }
}
