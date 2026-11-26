import XCTest
import Foundation
@testable import Confluence
import SignalEngine

final class StrategyToggleAndPopoverTests: XCTestCase {

    func testFreshInstallDefaultsToProvenWinners() throws {
        let emptyJSON = Data("{}".utf8)
        let decoded = try JSONDecoder().decode(PersistedSettingsPayload.self, from: emptyJSON)
        XCTAssertEqual(decoded.enabledStrategies, StrategyID.provenWinners)
    }

    func testLegacyCustomConceptsMigrateOnceToIndividualStrategyIDs() throws {
        let legacyJSON = Data("""
        {
          "strategySelectionMode": "Custom",
          "selectedStrategyConcepts": ["ict_fvg", "ict_order_block", "macro_surprise_catalyst"]
        }
        """.utf8)
        let decoded = try JSONDecoder().decode(PersistedSettingsPayload.self, from: legacyJSON)
        XCTAssertEqual(decoded.enabledStrategies, [.ictFvg, .ictOrderBlock, .macroSurpriseCatalyst])
    }

    func testLegacyStrategyGroupsMigrateOnceToIndividualStrategyIDs() throws {
        let legacyJSON = Data("""
        {
          "strategySelectionMode": "All Enabled",
          "enabledStrategyGroups": ["macroCatalyst"]
        }
        """.utf8)
        let decoded = try JSONDecoder().decode(PersistedSettingsPayload.self, from: legacyJSON)
        XCTAssertEqual(decoded.enabledStrategies, [.macroSurpriseCatalyst])
    }

    func testEnabledStrategiesPersistsAndIgnoresUnknownIDs() throws {
        let json = Data("""
        {
          "enabledStrategies": ["ict_bos", "trap_osler_round-number_sweep", "future_removed_strategy"]
        }
        """.utf8)
        let decoded = try JSONDecoder().decode(PersistedSettingsPayload.self, from: json)
        XCTAssertEqual(decoded.enabledStrategies, [.ictBos, .trapOslerRoundNumber])
    }

    @MainActor
    func testZeroStrategyScanGuardAbortsImmediately() async {
        let settings = AppSettingsStore()
        let previous = settings.payload.enabledStrategies
        defer { settings.payload.enabledStrategies = previous }

        settings.payload.enabledStrategies = []
        let dataStore = ConfluenceDataStore(inMemory: true)
        let coordinator = MarketScannerCoordinator(settings: settings, store: dataStore)
        await coordinator.scanAllMarkets(isBackground: false)
        XCTAssertEqual(coordinator.scanBlockedMessage, MarketScannerCoordinator.noStrategiesEnabledMessage)
        XCTAssertEqual(coordinator.lastScanError, MarketScannerCoordinator.noStrategiesEnabledMessage)
        XCTAssertFalse(coordinator.isScanning)
    }
}
