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
            let v1Schema = Schema([ConfluenceSchemaV16.PersistedSignalRecord.self])
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
            ctx.insert(ConfluenceSchemaV16.PersistedSignalRecord(
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

    @MainActor
    func testSwiftDataV1_1ToV1_2AdditiveMigrationPreservesDataAndAddsReplayCache() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("confluence_v12_mig_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("confluence_v11.store")

        // 1. Seed a v1.1 5-model container
        do {
            let v11Schema = Schema([
                ConfluenceSchemaV16.PersistedSignalRecord.self,
                StoredNotificationItem.self,
                DiagnosticLogEntry.self,
                TrapLogEntry.self,
                TradeLedgerEntry.self
            ])
            let v11Config = ModelConfiguration(schema: v11Schema, url: storeURL)
            let v11Container = try ModelContainer(for: v11Schema, configurations: [v11Config])
            let ctx = ModelContext(v11Container)
            ctx.insert(StoredNotificationItem(
                id: "v11-notif",
                createdAt: Date(),
                typeRaw: NotificationItemType.strongSignal.rawValue,
                title: "Pre-v1.2 Alert",
                subtitle: "Preserved"
            ))
            try ctx.save()
        }

        // 2. Open with v1.2 6-model ConfluenceDataStore (including TradeReplayCandleCache)
        let upgraded = ConfluenceDataStore(inMemory: false, customStoreURL: storeURL)
        XCTAssertFalse(upgraded.didQuarantineCorruptStore)
        XCTAssertEqual(upgraded.fetchNotifications().count, 1)

        // 3. Verify TradeReplayCandleCache round-trip
        let base: TimeInterval = 1_760_000_000
        let sampleBars = [
            Candle(openTimeEpochSeconds: base, closeTimeEpochSeconds: base + 900, open: 1.31000, high: 1.31050, low: 1.30950, close: 1.31002, volume: nil, isClosed: true),
            Candle(openTimeEpochSeconds: base + 900, closeTimeEpochSeconds: base + 1800, open: 1.31002, high: 1.31120, low: 1.30990, close: 1.31110, volume: nil, isClosed: true)
        ]
        upgraded.saveReplayCandles(fingerprint: "fp-replay-1", symbol: "GBP/USD", timeframe: .m15, providerName: "Twelve Data", candles: sampleBars)
        let fetched = upgraded.fetchReplayCandles(fingerprint: "fp-replay-1")
        XCTAssertEqual(fetched?.candles.count, 2)
        XCTAssertEqual(fetched?.providerName, "Twelve Data")
    }

    @MainActor
    func testAppSettingsBackwardsCompatibleDecodeAndThemeToggle() throws {
        // Legacy v1.1/v1.3 payload with old ThemePreset + removed Random Subset mode
        let legacyJSON = """
        {
          "appearanceMode": "Dark Mode",
          "themePreset": "AMOLED Vault",
          "strategySelectionMode": "Random Subset",
          "minimumConfidencePercent": 78.0,
          "minimumRiskReward": 2.5
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PersistedSettingsPayload.self, from: legacyJSON)
        XCTAssertEqual(decoded.appearanceMode, .dark)
        XCTAssertTrue(decoded.usePureBlackAMOLED, "Legacy AMOLED Vault must migrate to usePureBlackAMOLED = true")
        XCTAssertEqual(decoded.enabledStrategies, StrategyID.allSet, "Legacy Random Subset must migrate safely to StrategyID.allSet")
        XCTAssertFalse(decoded.showWeakFilteredSignals, "Weak / Filtered signals must default OFF")
        XCTAssertFalse(decoded.showAdvancedSettings, "Show Advanced Settings must default OFF")
        XCTAssertEqual(decoded.minimumConfidencePercent, 78.0)
        XCTAssertEqual(decoded.levelCalculationMode, .structureATR)
        XCTAssertEqual(decoded.calibrationWinDefinition, .tp1OrTp2)

        // Legacy Porcelain Desk without explicit appearanceMode -> Light Mode + AMOLED false
        let legacyPorcelainJSON = """
        {
          "themePreset": "Porcelain Desk"
        }
        """.data(using: .utf8)!
        let decodedPorcelain = try JSONDecoder().decode(PersistedSettingsPayload.self, from: legacyPorcelainJSON)
        XCTAssertEqual(decodedPorcelain.appearanceMode, .light)
        XCTAssertFalse(decodedPorcelain.usePureBlackAMOLED)

        let settings = AppSettingsStore()
        let originalPayload = settings.payload
        defer { settings.payload = originalPayload }
        settings.payload = decoded
        // Toggle Dark (AMOLED) -> Light -> Dark (preserves usePureBlackAMOLED = true!)
        settings.toggleDarkLightMode(currentlyDark: true)
        XCTAssertEqual(settings.payload.appearanceMode, .light)
        XCTAssertTrue(settings.payload.usePureBlackAMOLED)

        settings.toggleDarkLightMode(currentlyDark: false)
        XCTAssertEqual(settings.payload.appearanceMode, .dark)
        XCTAssertTrue(settings.payload.usePureBlackAMOLED)
    }

    @MainActor
    func testStrategyTradeMappingAndReplayMarkerSnapping() {
        let base: TimeInterval = 1_760_000_000
        let entryBar = Candle(openTimeEpochSeconds: base - 900, closeTimeEpochSeconds: base, open: 1.30980, high: 1.31020, low: 1.30950, close: 1.31002, volume: nil, isClosed: true)
        let fillBar = Candle(openTimeEpochSeconds: base, closeTimeEpochSeconds: base + 900, open: 1.31002, high: 1.31040, low: 1.30990, close: 1.31030, volume: nil, isClosed: true)
        let exitBar = Candle(openTimeEpochSeconds: base + 900, closeTimeEpochSeconds: base + 1800, open: 1.31030, high: 1.31250, low: 1.31020, close: 1.31220, volume: nil, isClosed: true)
        let levels = TradeLevels(
            entryLow: 1.30990, entryHigh: 1.31014, entryMid: 1.31002,
            stopLoss: 1.30920, tp1: 1.31166, tp2: 1.31240,
            riskPercent: 0.06, reward1Percent: 0.13, reward2Percent: 0.18,
            riskRewardRatio: 2.0, tp2RiskRewardRatio: 2.9, isTP2Enabled: true
        )
        let psych = PsychologyReport(
            signalCategory: .strongSignal, proDirection: .long, retailCrowdDirection: .short,
            provenanceBadge: "CFTC COT", whatHappened: "Sweep", beginnerPsychology: "B", proPsychology: "P",
            behavioralBadges: [], evidence: []
        )
        let contrib = StrategyContribution(id: "ict_liquidity_sweep", name: "Liquidity Sweep", group: .ictSmc, direction: .long, weight: 1.3, historicalWinRate: 0.65, detail: "Sweep")
        let sig = TradeSignal(
            id: "fp-gbp-replay", fingerprint: "fp-gbp-replay", symbol: "GBP/USD", displayName: "British Pound / US Dollar",
            marketClass: .forex, timeframe: .m15, htfTimeframe: .h4,
            category: .strongSignal, direction: .long, tier: .highConviction,
            confidencePercent: 84.0, regime: .trending, riskState: .safe,
            killzone: .london, htfBias: .long,
            generatedAtEpochSeconds: base, barCloseEpochSeconds: base,
            levels: levels, alignedStrategies: [contrib], rejectionReasons: [],
            psychologyReport: psych, recentCandles: [entryBar], dataProvider: "Twelve Data"
        )

        let store = ConfluenceDataStore(inMemory: true)
        store.upsertSignal(sig)
        let outcome = PassiveOutcomeEvaluator.evaluate(signal: sig, subsequentClosedCandles: [fillBar, exitBar], roundTripCostBps: 2.0)
        XCTAssertEqual(outcome.status, .hitTP2)
        store.updateOutcome(outcome)

        let coordinator = MarketScannerCoordinator(settings: AppSettingsStore(), store: store)
        let trades = coordinator.trades(forStrategyId: "ict_liquidity_sweep")
        XCTAssertEqual(trades.count, 1)
        let trade = trades[0]
        XCTAssertEqual(trade.status, .tp2Win)

        let markerResult = TradeReplayMarkerBuilder.buildMarkers(for: trade, candles: [entryBar, fillBar, exitBar])
        XCTAssertTrue(markerResult.hasEntryBar)
        XCTAssertTrue(markerResult.hasExitBar)
        XCTAssertEqual(markerResult.markers.count, 2)
        XCTAssertEqual(markerResult.markers[0].text, "ENTRY LONG")
        XCTAssertTrue(markerResult.markers[1].text.hasPrefix("T2 WIN"))
    }

    // MARK: - v1.3 Additive Migration, Permanent Signal Deletion & Native Crash Log Tests

    @MainActor
    func testSwiftDataV1_2ToV1_3AdditiveMigrationAndOutcomeBackfill() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("confluence_v13_mig_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("confluence_v12.store")

        let base: TimeInterval = 1_760_000_000
        let sampleOutcome = SignalOutcomeRecord(
            signalId: "fp-legacy-v12",
            symbol: "NAS100",
            marketClass: .indices,
            category: .strongSignal,
            direction: .short,
            predictedProbability: 0.74,
            status: .hitTP1,
            netReturnPercent: 0.85,
            rMultiple: 2.1,
            strategyIds: ["ict_bos", "momentum_ema_pullback"],
            hadMacroCatalyst: false,
            resolvedAtEpochSeconds: base + 3600
        )
        let outcomeData = try JSONEncoder().encode(sampleOutcome)

        // 1. Seed a v1.2 6-model container with a legacy PersistedSignalRecord carrying outcomeJSON
        do {
            let v12Schema = Schema([
                ConfluenceSchemaV16.PersistedSignalRecord.self,
                StoredNotificationItem.self,
                DiagnosticLogEntry.self,
                TrapLogEntry.self,
                TradeLedgerEntry.self,
                TradeReplayCandleCache.self
            ])
            let v12Config = ModelConfiguration(schema: v12Schema, url: storeURL)
            let v12Container = try ModelContainer(for: v12Schema, configurations: [v12Config])
            let ctx = ModelContext(v12Container)
            ctx.insert(ConfluenceSchemaV16.PersistedSignalRecord(
                fingerprint: "fp-legacy-v12",
                symbol: "NAS100",
                directionRaw: "short",
                categoryRaw: SignalCategory.strongSignal.rawValue,
                createdAt: Date(timeIntervalSince1970: base),
                signalJSON: Data("{}".utf8),
                outcomeJSON: outcomeData
            ))
            try ctx.save()
        }

        // 2. Open with v1.3 8-model ConfluenceDataStore -> must migrate cleanly & backfill PersistedOutcomeRecord
        let upgraded = ConfluenceDataStore(inMemory: false, customStoreURL: storeURL)
        XCTAssertFalse(upgraded.didQuarantineCorruptStore)
        XCTAssertEqual(upgraded.fetchOutcomeRecords().count, 1)
        XCTAssertEqual(upgraded.fetchOutcomeRecords().first?.signalId, "fp-legacy-v12")

        // 3. Delete the legacy signal card -> Calibration outcome must STILL survive in PersistedOutcomeRecord!
        upgraded.deleteSignal(fingerprint: "fp-legacy-v12")
        let reopened = ConfluenceDataStore(inMemory: false, customStoreURL: storeURL)
        XCTAssertEqual(reopened.fetchOutcomeRecords().count, 1)
        XCTAssertEqual(reopened.fetchOutcomeRecords().first?.status, .hitTP1)
    }

    @MainActor
    func testPermanentSignalDeletionPreservesCalibrationStatsAcrossReopen() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("confluence_v13_del_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("confluence_del.store")

        let store = ConfluenceDataStore(inMemory: false, customStoreURL: storeURL)
        let base: TimeInterval = 1_760_000_000
        let psych = PsychologyReport(
            signalCategory: .strongSignal, proDirection: .long, retailCrowdDirection: .short,
            provenanceBadge: "Structure", whatHappened: "Setup", beginnerPsychology: "B", proPsychology: "P",
            behavioralBadges: [], evidence: []
        )
        let levels = TradeLevels(
            entryLow: 100, entryHigh: 101, entryMid: 100.5, stopLoss: 99, tp1: 103.5, tp2: 105.5,
            riskPercent: 1.5, reward1Percent: 3.0, reward2Percent: 5.0,
            riskRewardRatio: 2.0, tp2RiskRewardRatio: 3.3, isTP2Enabled: true
        )

        func makeSig(fp: String, cat: SignalCategory) -> TradeSignal {
            TradeSignal(
                id: fp, fingerprint: fp, symbol: "BTC/USDT", displayName: "Bitcoin",
                marketClass: .crypto, timeframe: .h1, htfTimeframe: .h4,
                category: cat, direction: .long, tier: .highConviction,
                confidencePercent: 76.0, regime: .trending, riskState: .safe,
                killzone: .newYork, htfBias: .long,
                generatedAtEpochSeconds: base, barCloseEpochSeconds: base,
                levels: levels, alignedStrategies: [], rejectionReasons: [],
                psychologyReport: psych, dataProvider: "Binance Vision"
            )
        }

        let s1 = makeSig(fp: "fp-strong-1", cat: .strongSignal)
        let s2 = makeSig(fp: "fp-trap-1", cat: .trapAlert)
        let s3 = makeSig(fp: "fp-weak-1", cat: .weakSignal)
        store.upsertSignal(s1)
        store.upsertSignal(s2)
        store.upsertSignal(s3)

        let out1 = SignalOutcomeRecord(
            signalId: "fp-strong-1", symbol: "BTC/USDT", marketClass: .crypto,
            category: .strongSignal, direction: .long, predictedProbability: 0.76,
            status: .hitTP2, netReturnPercent: 4.8, rMultiple: 3.2, strategyIds: ["ict_bos"],
            hadMacroCatalyst: false, resolvedAtEpochSeconds: base + 7200
        )
        store.updateOutcome(out1)

        let coord = MarketScannerCoordinator(settings: AppSettingsStore(), store: store)
        XCTAssertEqual(coord.signals.count, 3)

        // Single delete
        coord.deleteSignal(fingerprint: "fp-weak-1")
        XCTAssertEqual(coord.signals.count, 2)

        // Category delete (Traps)
        coord.deleteSignals(in: .trapAlert)
        XCTAssertEqual(coord.signals.count, 1)

        // Delete all remaining cards
        coord.deleteAllSignals()
        XCTAssertTrue(coord.signals.isEmpty)

        // Reopen from disk: deleted cards stay gone, Calibration Stats & Trade Ledger stay 100% preserved!
        let reopened = ConfluenceDataStore(inMemory: false, customStoreURL: storeURL)
        XCTAssertTrue(reopened.fetchSignals().isEmpty)
        XCTAssertEqual(reopened.fetchOutcomeRecords().count, 1)
        XCTAssertEqual(reopened.fetchOutcomeRecords().first?.status, .hitTP2)
        XCTAssertEqual(reopened.fetchTradeLedger().count, 2)
    }

    @MainActor
    func testCrashLogStoreMetricKitParsingBreadcrumbImportAndSecretScrubbing() throws {
        let store = ConfluenceDataStore(inMemory: true)
        let crashStore = CrashLogStore(store: store)
        let diagStore = DiagnosticLogStore(store: store)

        // 1. Parse MetricKit JSON containing both crashDiagnostics and hangDiagnostics
        let sampleMetricKitJSON = """
        {
          "timeStampBegin": "2026-11-24T10:00:00Z",
          "timeStampEnd": "2026-11-25T10:00:00Z",
          "crashDiagnostics": [
            {
              "version": "1.3.0",
              "diagnosticMetaData": {
                "appVersion": "1.3.0",
                "appBuildVersion": "4",
                "signal": 11,
                "exceptionType": 1,
                "terminationReason": "Namespace SIGNAL, Code 11 Segmentation fault: 11 apikey=SUPERSECRET123"
              },
              "callStackTree": {
                "callStacks": [
                  {
                    "threadAttributed": true,
                    "callStackRootFrames": [
                      {
                        "binaryName": "Confluence",
                        "address": 4294967296,
                        "offsetIntoBinaryTextSegment": 1024,
                        "subFrames": []
                      }
                    ]
                  }
                ]
              }
            }
          ],
          "hangDiagnostics": [
            {
              "version": "1.3.0",
              "diagnosticMetaData": {
                "appVersion": "1.3.0",
                "appBuildVersion": "4",
                "hangDuration": "2.4s"
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let parsedCount = crashStore.ingestMetricKitJSON(sampleMetricKitJSON)
        XCTAssertEqual(parsedCount, 2)
        XCTAssertEqual(crashStore.entries.count, 2)
        let crashEntry = crashStore.entries.first { $0.source == .metricKitCrash }
        XCTAssertNotNil(crashEntry)
        XCTAssertFalse(crashEntry?.summary.contains("SUPERSECRET123") ?? true, "API secrets must be redacted in crash logs")
        XCTAssertTrue(crashEntry?.summary.contains("[REDACTED]") ?? false)

        // 2. Simulate pending uncaught exception + POSIX signal breadcrumbs in temp directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("confluence_crash_bc_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let excFile = tempDir.appendingPathComponent(CrashLogStore.exceptionBreadcrumbFilename)
        try """
        EXCEPTION_NAME:NSRangeException
        REASON:Index out of bounds x-goog-api-key: AIzaSyTestFakeKey12345678901234567890
        STACK:
        0 Confluence 0x1000 main
        """.write(to: excFile, atomically: true, encoding: .utf8)

        let posixFile = tempDir.appendingPathComponent(CrashLogStore.posixBreadcrumbFilename)
        try "POSIX_SIGNAL:SIGSEGV\n".write(to: posixFile, atomically: true, encoding: .utf8)

        let imported = crashStore.importPendingCrashBreadcrumbs(from: tempDir)
        XCTAssertEqual(imported, 2)
        XCTAssertEqual(crashStore.entries.count, 4)
        XCTAssertFalse(FileManager.default.fileExists(atPath: excFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: posixFile.path))

        // Verify secret redaction on imported exception breadcrumb & Error Log filtering
        let excLog = crashStore.entries.first { $0.source == .uncaughtException }
        XCTAssertNotNil(excLog)
        XCTAssertFalse(excLog?.summary.contains("AIzaSyTestFakeKey") ?? true)

        diagStore.log(.info, category: .engine, message: "Routine info")
        diagStore.log(.warn, category: .feed, message: "Rate limit warning")
        diagStore.log(.error, category: .feed, message: "Feed error with apikey=SECRET_KEY_999")
        XCTAssertEqual(diagStore.errorOnlyCount, 1)
        XCTAssertEqual(diagStore.errorAndCriticalEntries.count, 2)
        XCTAssertFalse(diagStore.errorOnlyEntries.first?.message.contains("SECRET_KEY_999") ?? true)

        let md = diagStore.buildAntigravityMarkdownReport(
            appVersion: "1.3.0",
            appBuild: "4",
            twelveDataQuota: nil,
            twelveDataLocalDailyUsed: 0,
            feedHealth: [],
            calibration: PassiveOutcomeEvaluator.summarize(records: []),
            strategyBreakdowns: [],
            tradeLedger: [],
            trapLogs: [],
            crashLogs: crashStore.entries
        )
        XCTAssertTrue(md.contains("## Crash & Hang Logs (4)"))
        XCTAssertTrue(md.contains("## Error & Warning Logs (2)"))
        XCTAssertFalse(md.contains("SECRET_KEY_999"))
        XCTAssertFalse(md.contains("AIzaSyTestFakeKey"))
    }

    // MARK: - v1.4 Phase 1: Zero Info.plist Secrets & Legacy Headline Exclusion Tests

    func testBuiltInfoPlistContainsNoSecretKeys() {
        let info = Bundle.main.infoDictionary ?? [:]
        XCTAssertNil(info["ConfluenceDefaultTwelveDataKey"], "Built Info.plist must never embed Twelve Data API keys")

        for (key, value) in info {
            guard let str = value as? String else { continue }
            XCTAssertFalse(str.hasPrefix("AIza"), "Info.plist key \(key) contains Gemini-like API key")
            XCTAssertFalse(str.hasPrefix("sk-"), "Info.plist key \(key) contains secret-like token")
            let isHex32Plus = str.count >= 32 && str.allSatisfy { $0.isHexDigit }
            XCTAssertFalse(isHex32Plus, "Info.plist key \(key) contains a 32+ char hex key-like string")
        }
    }

    @MainActor
    func testLegacyPreV14OutcomeTaggedAndExcludedFromHeadlineWinRate() throws {
        let store = ConfluenceDataStore(inMemory: true)
        let legacyJSON = """
        {
          "signalId": "fp-pre-v14",
          "symbol": "GBP/USD",
          "marketClass": "forex",
          "category": "STRONG_SIGNAL",
          "direction": "long",
          "predictedProbability": 0.82,
          "status": "hitTP2",
          "netReturnPercent": 2.4,
          "rMultiple": 3.0,
          "strategyIds": ["ict_fvg"],
          "hadMacroCatalyst": false,
          "resolvedAtEpochSeconds": 1760010000
        }
        """.data(using: .utf8)!
        let legacyOutcome = try JSONDecoder().decode(SignalOutcomeRecord.self, from: legacyJSON)
        XCTAssertTrue(legacyOutcome.effectiveIsLegacyImmediateFill)
        store.updateOutcome(legacyOutcome)

        let v14Outcome = SignalOutcomeRecord(
            signalId: "fp-v14-filled",
            symbol: "GBP/USD",
            marketClass: .forex,
            category: .strongSignal,
            direction: .short,
            predictedProbability: 0.78,
            status: .hitSL,
            netReturnPercent: -1.0,
            rMultiple: -1.0,
            strategyIds: ["ict_fvg"],
            hadMacroCatalyst: false,
            resolvedAtEpochSeconds: 1_760_020_000,
            lifecycleStatus: .resolved,
            filledAtEpochSeconds: 1_760_015_000,
            fillWindowBars: 12,
            isLegacyImmediateFill: false
        )
        store.updateOutcome(v14Outcome)

        let coordinator = MarketScannerCoordinator(settings: AppSettingsStore(), store: store)
        XCTAssertEqual(coordinator.headlineCalibrationSummary.resolvedSignals, 1)
        XCTAssertEqual(coordinator.headlineCalibrationSummary.legacyExcludedCount, 1)
        XCTAssertEqual(coordinator.headlineCalibrationSummary.winRate, 0.0, accuracy: 1e-9)
        XCTAssertFalse(coordinator.confidenceCalibrator.isActive)
    }

    // MARK: - v1.4 Phase 3a: On-Disk SwiftData v1.3 -> v1.4 Migration, Backup/CSV & Broker Offset Tests

    @MainActor
    func testSwiftDataV1_3ToV1_4AdditiveMigrationAndJournalRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("confluence_v14_mig_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("confluence_v14.store")

        let base: TimeInterval = 1_760_050_000
        let sampleOutcome = SignalOutcomeRecord(
            signalId: "fp-v13-existing",
            symbol: "XAU/USD",
            marketClass: .metals,
            category: .strongSignal,
            direction: .long,
            predictedProbability: 0.78,
            status: .hitTP2,
            netReturnPercent: 1.9,
            rMultiple: 2.5,
            strategyIds: ["ict_fvg", "ict_sweep"],
            hadMacroCatalyst: false,
            resolvedAtEpochSeconds: base + 3600,
            lifecycleStatus: .resolved,
            filledAtEpochSeconds: base + 1800,
            fillWindowBars: 12,
            isLegacyImmediateFill: false
        )
        let outcomeData = try JSONEncoder().encode(sampleOutcome)

        // 1. Seed an on-disk v1.3 8-table SwiftData store (without JournalEntry)
        do {
            let v13Schema = Schema([
                ConfluenceSchemaV16.PersistedSignalRecord.self,
                StoredNotificationItem.self,
                DiagnosticLogEntry.self,
                TrapLogEntry.self,
                TradeLedgerEntry.self,
                TradeReplayCandleCache.self,
                PersistedOutcomeRecord.self,
                CrashLogEntry.self
            ])
            let v13Config = ModelConfiguration(schema: v13Schema, url: storeURL)
            let v13Container = try ModelContainer(for: v13Schema, configurations: [v13Config])
            let ctx = ModelContext(v13Container)
            ctx.insert(PersistedOutcomeRecord(
                signalId: sampleOutcome.signalId,
                outcomeJSON: outcomeData,
                resolvedAt: Date(timeIntervalSince1970: base + 3600)
            ))
            try ctx.save()
        }

        // 2. Open with v1.4 9-table ConfluenceDataStore -> zero quarantine, v1.3 outcome preserved
        let v14Store = ConfluenceDataStore(inMemory: false, customStoreURL: storeURL)
        XCTAssertFalse(v14Store.didQuarantineCorruptStore)
        XCTAssertEqual(v14Store.fetchOutcomeRecords().count, 1)
        XCTAssertEqual(v14Store.fetchOutcomeRecords().first?.signalId, "fp-v13-existing")

        // 3. Upsert an automatic TrackedJournalTrade & verify persistence across disk reopen
        let entry = TrackedJournalTrade(
            id: "journal-1",
            symbol: "XAU/USD",
            assetClass: .metals,
            timeframe: .h1,
            direction: .long,
            section: .strongSignals,
            status: .winTP1,
            score: 82.0,
            signalBarTimestamp: base,
            entryZoneLow: 2649.5,
            entryZoneHigh: 2650.5,
            entryPrice: 2650.0,
            fillPrice: 2650.5,
            stopLoss: 2640.0,
            target1: 2670.0,
            target2: 2685.0,
            isTP2Enabled: true,
            currentPrice: 2671.5,
            livePnLPercent: 0.79,
            liveRMultiple: 2.0,
            realizedR: 2.0,
            isWinLocked: true,
            createdAt: base + 1800,
            filledAt: base + 1800,
            tp1HitAt: base + 5400,
            closedAt: base + 5400,
            matchedStrategyIDs: ["ict_fvg", "ict_sweep"]
        )
        v14Store.upsertTrackedJournalEntry(entry)

        let reopened = ConfluenceDataStore(inMemory: false, customStoreURL: storeURL)
        XCTAssertFalse(reopened.didQuarantineCorruptStore)
        let fetched = reopened.loadTrackedJournalEntries()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.symbol, "XAU/USD")
        XCTAssertEqual(fetched.first?.status, .winTP1)
        XCTAssertEqual(fetched.first?.matchedStrategyIDs, ["ict_fvg", "ict_sweep"])
        XCTAssertEqual(fetched.first?.id, "journal-1")
    }

    @MainActor
    func testBackupArchiveMergeReplaceZeroSecretsAndCSVEscaping() throws {
        let store = ConfluenceDataStore(inMemory: true)
        let settings = AppSettingsStore()
        settings.payload.minimumConfidencePercent = 77.0
        settings.payload.use24HourTime = true

        // Put a secret-like string and RFC-4180 special chars in filterReason to verify SecretRedactor + CSV escaping
        let baseNow: TimeInterval = 1_760_050_000
        let j1 = TrackedJournalTrade(
            id: "j-secret-test",
            symbol: "EUR/USD",
            assetClass: .forex,
            timeframe: .h1,
            direction: .long,
            section: .weakAndFiltered,
            status: .winTP1,
            score: 64.0,
            signalBarTimestamp: baseNow,
            entryZoneLow: 1.0998,
            entryZoneHigh: 1.1002,
            entryPrice: 1.1000,
            fillPrice: 1.1000,
            stopLoss: 1.0950,
            target1: 1.1100,
            target2: 1.1150,
            currentPrice: 1.1100,
            livePnLPercent: 0.91,
            liveRMultiple: 2.0,
            realizedR: 2.0,
            isWinLocked: true,
            createdAt: baseNow,
            filledAt: baseNow,
            closedAt: baseNow + 3600,
            filterReason: "Quoted \"entry\", London, NY, apikey=SECRET_TD_KEY_12345 and AIzaSyFakeGeminiKey0123456789012345\nSecond line"
        )
        store.upsertTrackedJournalEntry(j1)

        // 1. Export JSON archive and verify zero secrets
        let archive = BackupArchiveService.buildArchive(settings: settings.payload, store: store, appVersion: "1.4.0")
        let archiveData = try BackupArchiveService.encodeRedactedArchiveData(archive)
        let archiveText = String(data: archiveData, encoding: .utf8) ?? ""
        XCTAssertFalse(archiveText.contains("SECRET_TD_KEY_12345"))
        XCTAssertFalse(archiveText.contains("AIzaSyFakeGeminiKey"))
        XCTAssertTrue(archiveText.contains("[REDACTED]"))

        // 2. Reject unsupported future schemaVersion
        let badSchemaJSON = archiveText.replacingOccurrences(
            of: "\"schemaVersion\" : \(ConfluenceBackupArchive.currentSchemaVersion)",
            with: "\"schemaVersion\" : 99"
        )
        XCTAssertThrowsError(try BackupArchiveService.decodeAndValidateArchive(from: Data(badSchemaJSON.utf8)))

        // 3. Merge vs Replace restore
        let targetStore = ConfluenceDataStore(inMemory: true)
        let targetSettings = AppSettingsStore()
        targetStore.upsertTrackedJournalEntry(TrackedJournalTrade(
            id: "j-existing-local",
            symbol: "BTC/USDT",
            assetClass: .crypto,
            timeframe: .h4,
            direction: .short,
            section: .strongSignals,
            status: .live,
            score: 80.0,
            signalBarTimestamp: baseNow,
            entryZoneLow: 94_900,
            entryZoneHigh: 95_100,
            entryPrice: 95_000,
            fillPrice: 95_000,
            stopLoss: 96_000,
            target1: 92_000,
            target2: 90_000,
            currentPrice: 95_000,
            createdAt: baseNow,
            filledAt: baseNow
        ))

        let mergeSummary = try BackupArchiveService.restoreArchive(
            from: archiveData, mode: .merge, settingsStore: targetSettings, dataStore: targetStore
        )
        XCTAssertEqual(mergeSummary.journalImported, 1)
        XCTAssertEqual(targetStore.loadTrackedJournalEntries().count, 2, "Merge mode must keep pre-existing local entries")
        XCTAssertEqual(targetSettings.payload.minimumConfidencePercent, 77.0, accuracy: 1e-6)

        let replaceSummary = try BackupArchiveService.restoreArchive(
            from: archiveData, mode: .replace, settingsStore: targetSettings, dataStore: targetStore
        )
        XCTAssertEqual(replaceSummary.journalImported, 1)
        XCTAssertEqual(targetStore.loadTrackedJournalEntries().count, 1, "Replace mode must clear pre-existing local entries")
        XCTAssertEqual(targetStore.loadTrackedJournalEntries().first?.id, "j-secret-test")

        // 4. RFC-4180 CSV escaping & redaction
        let csv = BackupArchiveService.buildTrackedJournalCSV(entries: [j1])
        XCTAssertFalse(csv.contains("SECRET_TD_KEY_12345"))
        XCTAssertFalse(csv.contains("AIzaSyFakeGeminiKey"))
        XCTAssertTrue(csv.contains("\"\"entry\"\""), "RFC-4180 must double inner quotes")
        XCTAssertTrue(csv.contains("London, NY"), "RFC-4180 must preserve fields containing commas inside quotes")
    }

    @MainActor
    func testBrokerPriceOffsetDisplayOnlyAndStaleCheck() throws {
        let settings = AppSettingsStore()
        let originalPayload = settings.payload
        defer { settings.payload = originalPayload }
        let baseNow: TimeInterval = 1_760_100_000
        let staleOffset = BrokerPriceOffset(offset: 12.5, calibratedAtEpochSeconds: baseNow - 90_000)
        XCTAssertTrue(staleOffset.isStale(nowEpochSeconds: baseNow))

        let freshOffset = BrokerPriceOffset(offset: 12.5, calibratedAtEpochSeconds: baseNow - 3_600)
        XCTAssertFalse(freshOffset.isStale(nowEpochSeconds: baseNow))

        settings.setBrokerOffset(12.5, for: "XAU/USD")
        let psych = PsychologyReport(
            signalCategory: .strongSignal, proDirection: .long, retailCrowdDirection: .short,
            provenanceBadge: "Structure", whatHappened: "Setup", beginnerPsychology: "B", proPsychology: "P",
            behavioralBadges: [], evidence: []
        )
        let rawLevels = TradeLevels(
            entryLow: 2648.0, entryHigh: 2652.0, entryMid: 2650.0, stopLoss: 2640.0, tp1: 2670.0, tp2: 2685.0,
            riskPercent: 0.38, reward1Percent: 0.75, reward2Percent: 1.32,
            riskRewardRatio: 2.0, tp2RiskRewardRatio: 3.5, isTP2Enabled: true
        )
        let sig = TradeSignal(
            id: "fp-gold-offset", fingerprint: "fp-gold-offset", symbol: "XAU/USD", displayName: "Gold",
            marketClass: .metals, timeframe: .h1, htfTimeframe: .h4,
            category: .strongSignal, direction: .long, tier: .highConviction,
            confidencePercent: 80.0, regime: .trending, riskState: .safe,
            killzone: .london, htfBias: .long,
            generatedAtEpochSeconds: baseNow, barCloseEpochSeconds: baseNow,
            levels: rawLevels, alignedStrategies: [], rejectionReasons: [],
            psychologyReport: psych, dataProvider: "Yahoo"
        )

        // Toggle OFF -> exact raw levels
        settings.payload.showBrokerAdjustedLevels = false
        let rawDisplayed = try XCTUnwrap(settings.displayLevels(for: sig))
        XCTAssertEqual(rawDisplayed.entryMid, 2650.0, accuracy: 1e-9)
        XCTAssertEqual(rawDisplayed.stopLoss, 2640.0, accuracy: 1e-9)

        // Toggle ON -> shifted display levels while raw signal.levels stays untouched
        settings.payload.showBrokerAdjustedLevels = true
        let shifted = try XCTUnwrap(settings.displayLevels(for: sig))
        XCTAssertEqual(shifted.entryLow, 2660.5, accuracy: 1e-9)
        XCTAssertEqual(shifted.entryMid, 2662.5, accuracy: 1e-9)
        XCTAssertEqual(shifted.stopLoss, 2652.5, accuracy: 1e-9)
        XCTAssertEqual(shifted.tp1, 2682.5, accuracy: 1e-9)
        XCTAssertEqual(shifted.tp2, 2697.5, accuracy: 1e-9)
        XCTAssertEqual(sig.levels?.entryMid ?? 0, 2650.0, accuracy: 1e-9, "Raw signal levels must never be mutated by display offset")
    }
}
