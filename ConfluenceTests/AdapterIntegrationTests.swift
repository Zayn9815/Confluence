import Foundation
import SwiftData
import XCTest
@testable import Confluence
import SignalEngine

final class AdapterIntegrationTests: XCTestCase {
    func testForexFactoryRejectsHTMLRequestDeniedPage() {
        let html = """
        <!DOCTYPE html><html><head><title>Request Denied</title></head>
        <body>You've exceeded the limit for Calendar Export requests.</body></html>
        """.data(using: .utf8)!

        XCTAssertThrowsError(
            try EconomicCalendarService.parseForexFactoryPayload(data: html, contentType: "text/html")
        )
        // Even if server mislabels Content-Type as application/json, leading byte != '[' must reject
        XCTAssertThrowsError(
            try EconomicCalendarService.parseForexFactoryPayload(data: html, contentType: "application/json")
        )
    }

    func testBiquoteCalendarPreservesNullActualAndNonExactTimeMode() throws {
        let json = """
        [
          {
            "id": "mql5:900001",
            "eventId": "mql5:840",
            "time": "2026-11-25T13:30:00Z",
            "countryCode": "US",
            "currency": "USD",
            "name": "CPI y/y",
            "importance": "high",
            "unit": "percent",
            "multiplier": null,
            "actual": null,
            "forecast": 2.7,
            "previous": 2.8,
            "revisedPrevious": 2.9,
            "timeMode": "exact"
          },
          {
            "id": "mql5:900002",
            "eventId": "mql5:841",
            "time": "2026-11-26T00:00:00Z",
            "countryCode": "US",
            "currency": "USD",
            "name": "Bank Holiday",
            "importance": "medium",
            "actual": null,
            "forecast": null,
            "previous": null,
            "timeMode": "tentative"
          }
        ]
        """.data(using: .utf8)!

        let events = try EconomicCalendarService.parseBiquoteCalendarJSON(data: json)
        XCTAssertEqual(events.count, 2)
        let cpi = events[0]
        XCTAssertNil(cpi.actual)
        XCTAssertEqual(cpi.forecast, 2.7)
        XCTAssertEqual(cpi.revisedPrevious, 2.9)
        XCTAssertEqual(cpi.canonicalIndicator, .cpi)
        XCTAssertTrue(cpi.isExactClock)

        let holiday = events[1]
        XCTAssertFalse(holiday.isExactClock)
    }

    func testYahooChartParserHandlesNullGapsAndOTCNilVolume() throws {
        let json = """
        {
          "chart": {
            "result": [
              {
                "timestamp": [1760000000, 1760003600, 1760007200],
                "indicators": {
                  "quote": [
                    {
                      "open": [2650.0, null, 2655.0],
                      "high": [2660.0, null, 2665.0],
                      "low": [2645.0, null, 2650.0],
                      "close": [2655.0, null, 2662.0],
                      "volume": [0, null, 0]
                    }
                  ]
                }
              }
            ]
          }
        }
        """.data(using: .utf8)!

        let bars = try TradFiOHLCVRouter.parseYahooChartJSON(
            data: json,
            timeframe: .h1,
            marketClass: .metals,
            serverNowEpochSeconds: 1_760_020_000
        )
        XCTAssertEqual(bars.count, 2)
        XCTAssertTrue(bars.allSatisfy { $0.volume == nil })
    }

    func testCFTCSocrataStringEncodedNumbersAndFridayReleaseDate() throws {
        let json = """
        [
          {
            "cftc_contract_market_code": "088691",
            "market_and_exchange_names": "GOLD - COMEX",
            "report_date_as_yyyy_mm_dd": "2026-11-17T00:00:00.000",
            "open_interest_all": "512400",
            "m_money_positions_long_all": "210000",
            "m_money_positions_short_all": "48000",
            "nonrept_positions_long_all": "31000",
            "nonrept_positions_short_all": "49000"
          }
        ]
        """.data(using: .utf8)!

        let records = try CFTCCOTAdapter.parseSocrataJSON(data: json, dataset: .disaggregatedFuturesOnly)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].institutionalNet, 162_000)
        XCTAssertEqual(records[0].nonReportableNet, -18_000)
        XCTAssertGreaterThan(records[0].publishedAtEpochSeconds, records[0].reportDateEpochSeconds + 3 * 86_400)
    }

    func testBundledCAFAlertSoundsPresentAtAppRoot() {
        let expected = [
            "terminal_chime",
            "sonar_pulse",
            "vault_lock",
            "trap_warning",
            "news_release_ping"
        ]
        for name in expected {
            let url = Bundle.main.url(forResource: name, withExtension: "caf")
            XCTAssertNotNil(url, "Missing root-bundled \(name).caf in Confluence.app")
        }
    }

    @MainActor
    func testSwiftDataPersistenceAndDeduplicationRoundTrip() {
        let store = ConfluenceDataStore(inMemory: true)
        let psych = PsychologyReport(
            signalCategory: .strongSignal, proDirection: .long, retailCrowdDirection: .short,
            provenanceBadge: PositioningProvenance.okxFundingOI.rawValue,
            whatHappened: "Sweep reclaimed", beginnerPsychology: "Stopped out", proPsychology: "Absorbed",
            behavioralBadges: ["Osler Round-Number Sweep"], evidence: []
        )
        let sig = TradeSignal(
            id: "fp-test-1", fingerprint: "fp-test-1", symbol: "BTC/USDT", displayName: "Bitcoin",
            marketClass: .crypto, timeframe: .h1, htfTimeframe: .h4,
            category: .strongSignal, direction: .long, tier: .aPlusInstitutional,
            confidencePercent: 87.0, regime: .trending, riskState: .safe,
            killzone: .london, htfBias: .long,
            generatedAtEpochSeconds: 1_760_000_000, barCloseEpochSeconds: 1_760_000_000,
            levels: nil, alignedStrategies: [], rejectionReasons: [],
            psychologyReport: psych, dataProvider: "Binance Vision"
        )
        store.upsertSignal(sig)
        let fetched = store.fetchSignals()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.fingerprint, "fp-test-1")
    }

    @MainActor
    func testSwiftDataV1ToV1_1AdditiveMigrationPreservesExistingSignals() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("confluence_mig_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("confluence_test.store")

        // 1. Create a v1.0-only container (PersistedSignalRecord only) and insert a signal
        do {
            let v1Schema = Schema([PersistedSignalRecord.self])
            let v1Config = ModelConfiguration(schema: v1Schema, url: storeURL)
            let v1Container = try ModelContainer(for: v1Schema, configurations: [v1Config])
            let ctx = ModelContext(v1Container)
            let psych = PsychologyReport(
                signalCategory: .strongSignal, proDirection: .long, retailCrowdDirection: .short,
                provenanceBadge: PositioningProvenance.cftcCOT.rawValue,
                whatHappened: "Pre-migration signal", beginnerPsychology: "B", proPsychology: "P",
                behavioralBadges: [], evidence: []
            )
            let sig = TradeSignal(
                id: "fp-v1-legacy", fingerprint: "fp-v1-legacy", symbol: "XAU/USD", displayName: "Gold",
                marketClass: .metals, timeframe: .h1, htfTimeframe: .h4,
                category: .strongSignal, direction: .long, tier: .highConviction,
                confidencePercent: 82.0, regime: .trending, riskState: .safe,
                killzone: .london, htfBias: .long,
                generatedAtEpochSeconds: 1_760_000_000, barCloseEpochSeconds: 1_760_000_000,
                levels: nil, alignedStrategies: [], rejectionReasons: [],
                psychologyReport: psych, dataProvider: "biquote.io"
            )
            let data = try JSONEncoder().encode(sig)
            ctx.insert(PersistedSignalRecord(
                fingerprint: sig.fingerprint,
                symbol: sig.symbol,
                directionRaw: sig.direction.rawValue,
                categoryRaw: sig.category.rawValue,
                createdAt: Date(timeIntervalSince1970: sig.generatedAtEpochSeconds),
                signalJSON: data
            ))
            try ctx.save()
        }

        // 2. Re-open the exact same on-disk store with v1.1 5-model ConfluenceDataStore
        let upgradedStore = ConfluenceDataStore(inMemory: false, customStoreURL: storeURL)
        XCTAssertFalse(upgradedStore.didQuarantineCorruptStore)
        let migratedSignals = upgradedStore.fetchSignals()
        XCTAssertEqual(migratedSignals.count, 1)
        XCTAssertEqual(migratedSignals.first?.fingerprint, "fp-v1-legacy")

        // 3. Verify new v1.1 tables work seamlessly on the upgraded store
        let saved = upgradedStore.saveNotification(NotificationItemSnapshot(
            id: "notif-mig-1",
            type: .strongSignal,
            title: "LONG XAU/USD",
            subtitle: "Migrated store test",
            symbol: "XAU/USD",
            marketClass: .metals,
            signalFingerprint: "fp-v1-legacy"
        ))
        XCTAssertTrue(saved)
        XCTAssertEqual(upgradedStore.unreadNotificationCount(), 1)
    }

    @MainActor
    func testNotificationInboxCapDedupAndDeepLinkParsing() {
        let store = ConfluenceDataStore(inMemory: true)
        let base = Date()

        // Insert 260 items -> must cap strictly at 250
        for i in 0..<260 {
            let inserted = store.saveNotification(NotificationItemSnapshot(
                id: "n-\(i)",
                createdAt: base.addingTimeInterval(Double(i)),
                type: .strongSignal,
                title: "Signal \(i)",
                subtitle: "Sub \(i)",
                symbol: "BTC/USDT",
                marketClass: .crypto,
                signalFingerprint: "fp-\(i)"
            ))
            XCTAssertTrue(inserted)
        }

        // Duplicate ID must be rejected
        XCTAssertFalse(store.saveNotification(NotificationItemSnapshot(
            id: "n-259",
            type: .strongSignal,
            title: "Dup",
            subtitle: "Dup"
        )))

        XCTAssertEqual(store.fetchNotifications(limit: 300).count, ConfluenceDataStore.maxStoredNotifications)
        XCTAssertEqual(store.unreadNotificationCount(), ConfluenceDataStore.maxStoredNotifications)

        store.markAllNotificationsRead()
        XCTAssertEqual(store.unreadNotificationCount(), 0)

        // Verify pure deep-link parser
        let link = NotificationCenterRouter.parseDeepLink(from: [
            NotificationUserInfoKey.signalFingerprint: "fp-259",
            NotificationUserInfoKey.category: SignalCategory.trapAlert.rawValue,
            NotificationUserInfoKey.market: MarketClass.crypto.rawValue,
            NotificationUserInfoKey.symbol: "BTC/USDT"
        ])
        XCTAssertEqual(link, .signal(fingerprint: "fp-259", category: .trapAlert, market: .crypto, symbol: "BTC/USDT"))
    }

    func testTwelveDataTimeSeriesQuotaAndErrorHandling() throws {
        // 1. Valid UTC time series with closed-candle guard & OTC nil volume
        let seriesJSON = """
        {
          "status": "ok",
          "values": [
            {"datetime": "2026-11-24 10:00:00", "open": "2650.0", "high": "2660.0", "low": "2648.0", "close": "2658.0"},
            {"datetime": "2026-11-24 11:00:00", "open": "2658.0", "high": "2665.0", "low": "2655.0", "close": "2662.0"}
          ]
        }
        """.data(using: .utf8)!
        // 2026-11-24 11:30:00 UTC -> 10:00 bar is closed (11:00), 11:00 bar is still open (closes 12:00)
        let serverNow = ISO8601DateFormatter().date(from: "2026-11-24T11:30:00Z")!.timeIntervalSince1970
        let bars = try TwelveDataAdapter.parseTimeSeriesJSON(
            data: seriesJSON,
            querySymbol: "XAU/USD",
            timeframe: .h1,
            marketClass: .metals,
            serverNowEpochSeconds: serverNow
        )
        XCTAssertEqual(bars.count, 2)
        XCTAssertTrue(bars[0].isClosed)
        XCTAssertFalse(bars[1].isClosed)
        XCTAssertNil(bars[0].volume)

        // 2. HTTP-200 JSON 403 Grow/Pro plan restriction
        let restrictedJSON = """
        {"code": 403, "message": "SPX is available exclusively with Grow or Pro plan", "status": "error"}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try TwelveDataAdapter.parseTimeSeriesJSON(
            data: restrictedJSON, querySymbol: "SPX", timeframe: .h1, marketClass: .indices, serverNowEpochSeconds: serverNow
        )) { err in
            guard case TwelveDataError.planRestrictedSymbol = err else {
                XCTFail("Expected planRestrictedSymbol, got \(err)")
                return
            }
        }

        // 3. /api_usage quota response
        let usageJSON = """
        {"current_usage": 3, "plan_limit": 8, "daily_usage": 42, "plan_daily_limit": 800, "plan_category": "Basic"}
        """.data(using: .utf8)!
        let quota = try TwelveDataAdapter.parseQuotaUsageJSON(data: usageJSON)
        XCTAssertEqual(quota.currentMinuteUsage, 3)
        XCTAssertEqual(quota.planMinuteLimit, 8)
        XCTAssertEqual(quota.remainingDailyCredits, 758)
    }

    @MainActor
    func testSecretRedactorAndDiagnosticLogRingBuffer() {
        let leaky = "GET /time_series?apikey=1234567890abcdef1234567890abcdef x-goog-api-key: AIzaSyDummySecretKeyValue1234567890"
        let clean = SecretRedactor.redact(leaky)
        XCTAssertFalse(clean.contains("1234567890abcdef1234567890abcdef"))
        XCTAssertFalse(clean.contains("AIzaSyDummySecretKeyValue1234567890"))
        XCTAssertTrue(clean.contains("[REDACTED]"))

        let store = ConfluenceDataStore(inMemory: true)
        let logger = DiagnosticLogStore(store: store)
        logger.log(.error, category: .feed, message: leaky)
        XCTAssertEqual(logger.entries.count, 1)
        XCTAssertFalse(logger.entries[0].message.contains("AIzaSyDummy"))

        let report = logger.buildAntigravityMarkdownReport(
            appVersion: "1.1.0",
            appBuild: "2",
            twelveDataQuota: nil,
            twelveDataLocalDailyUsed: 12,
            feedHealth: [],
            calibration: PassiveOutcomeEvaluator.summarize(records: []),
            strategyBreakdowns: [],
            tradeLedger: [],
            trapLogs: []
        )
        XCTAssertTrue(report.contains("# Confluence Antigravity Diagnostic Report"))
        XCTAssertFalse(report.contains("AIzaSyDummy"))
    }
}
