import Foundation
import SwiftData
import XCTest
@testable import Confluence
import SignalEngine

final class SwiftDataMigrationV16ToV20Tests: XCTestCase {

    // MARK: - Helpers

    private func makeSampleSignal(
        fingerprint: String,
        symbol: String,
        marketClass: MarketClass,
        epochSeconds: TimeInterval
    ) -> TradeSignal {
        let psych = PsychologyReport(
            signalCategory: .strongSignal,
            proDirection: .long,
            retailCrowdDirection: .short,
            provenanceBadge: PositioningProvenance.cftcCOT.rawValue,
            whatHappened: "Migration fixture signal",
            beginnerPsychology: "Beginner note",
            proPsychology: "Pro note",
            behavioralBadges: [],
            evidence: []
        )
        return TradeSignal(
            id: fingerprint,
            fingerprint: fingerprint,
            symbol: symbol,
            displayName: symbol,
            marketClass: marketClass,
            timeframe: .h1,
            htfTimeframe: .h4,
            category: .strongSignal,
            direction: .long,
            tier: .highConviction,
            confidencePercent: 84.0,
            regime: .trending,
            riskState: .safe,
            killzone: .newYork,
            htfBias: .long,
            generatedAtEpochSeconds: epochSeconds,
            barCloseEpochSeconds: epochSeconds,
            levels: nil,
            alignedStrategies: [],
            rejectionReasons: [],
            psychologyReport: psych,
            dataProvider: "Fixture"
        )
    }

    private func makeSampleOutcome(
        signalId: String,
        symbol: String,
        marketClass: MarketClass,
        status: SignalOutcomeStatus,
        rMultiple: Double,
        resolvedAt: TimeInterval
    ) -> SignalOutcomeRecord {
        SignalOutcomeRecord(
            signalId: signalId,
            symbol: symbol,
            marketClass: marketClass,
            category: .strongSignal,
            direction: .long,
            predictedProbability: 0.82,
            status: status,
            netReturnPercent: rMultiple > 0 ? 1.8 : -0.9,
            rMultiple: rMultiple,
            strategyIds: ["ict_bos", "ict_fvg"],
            hadMacroCatalyst: false,
            resolvedAtEpochSeconds: resolvedAt,
            lifecycleStatus: .resolved,
            filledAtEpochSeconds: resolvedAt - 1_800,
            fillWindowBars: 12,
            isLegacyImmediateFill: false
        )
    }

    // MARK: - 1. On-Disk v1.5 (12-Table) -> v2.0 (9-Table) Staged Migration + outcomeJSON Backfill

    @MainActor
    func testOnDiskV15TwelveTableStoreUpgradesCleanlyToV20WithOutcomeBackfill() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("confluence_v15_to_v20_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("confluence_v15.store")

        let base: TimeInterval = 1_760_500_000
        let embeddedSignal = makeSampleSignal(
            fingerprint: "fp-v15-embedded",
            symbol: "XAU/USD",
            marketClass: .metals,
            epochSeconds: base
        )
        let embeddedOutcome = makeSampleOutcome(
            signalId: "fp-v15-embedded",
            symbol: "XAU/USD",
            marketClass: .metals,
            status: .hitTP2,
            rMultiple: 3.1,
            resolvedAt: base + 7_200
        )
        let decoupledOutcome = makeSampleOutcome(
            signalId: "fp-v15-decoupled",
            symbol: "BTC/USDT",
            marketClass: .crypto,
            status: .hitTP1,
            rMultiple: 2.0,
            resolvedAt: base + 3_600
        )

        let signalData = try JSONEncoder().encode(embeddedSignal)
        let embeddedOutcomeData = try JSONEncoder().encode(embeddedOutcome)
        let decoupledOutcomeData = try JSONEncoder().encode(decoupledOutcome)

        // 1. Seed a real on-disk v1.5 (12-table) store with embedded outcomeJSON + DemoWallet* + JournalEntry
        do {
            let v15Schema = Schema(versionedSchema: ConfluenceSchemaV15.self)
            let v15Config = ModelConfiguration(schema: v15Schema, url: storeURL)
            let v15Container = try ModelContainer(for: v15Schema, configurations: [v15Config])
            let ctx = ModelContext(v15Container)

            ctx.insert(ConfluenceSchemaV16.PersistedSignalRecord(
                fingerprint: embeddedSignal.fingerprint,
                symbol: embeddedSignal.symbol,
                directionRaw: embeddedSignal.direction.rawValue,
                categoryRaw: embeddedSignal.category.rawValue,
                createdAt: Date(timeIntervalSince1970: base),
                signalJSON: signalData,
                outcomeJSON: embeddedOutcomeData,
                activeStrategyProfileKey: "ict_bos+ict_fvg",
                enabledStrategyIDsCSV: "ict_bos,ict_fvg",
                orderFlowStatus: "off"
            ))
            ctx.insert(PersistedOutcomeRecord(
                signalId: decoupledOutcome.signalId,
                outcomeJSON: decoupledOutcomeData,
                resolvedAt: Date(timeIntervalSince1970: base + 3_600)
            ))
            ctx.insert(ConfluenceSchemaV16.JournalEntry(
                id: "legacy-j-v15",
                symbol: "EUR/USD",
                marketRaw: MarketClass.forex.rawValue,
                timeframeRaw: Timeframe.h1.rawValue,
                directionRaw: TradeDirection.long.rawValue,
                plannedEntry: 1.0950,
                stopLoss: 1.0900,
                tp1: 1.1050
            ))
            ctx.insert(ConfluenceSchemaV16.DemoWalletRecord(
                id: "primary",
                startingBalanceUSD: 1_000,
                cashBalanceUSD: 1_180
            ))
            ctx.insert(ConfluenceSchemaV16.DemoPositionRecord(
                id: "demo-pos-1",
                symbol: "BTC/USDT",
                statusRaw: "open",
                positionJSON: Data("{}".utf8),
                createdAt: Date(timeIntervalSince1970: base)
            ))
            ctx.insert(ConfluenceSchemaV16.DemoWalletTransactionRecord(
                id: "demo-tx-1",
                timestamp: Date(timeIntervalSince1970: base),
                kindRaw: "deposit",
                amountUSD: 1_000,
                balanceAfterUSD: 1_000,
                note: "Initial paper funding"
            ))
            try ctx.save()
        }

        // 2. Open with v2.0 ConfluenceDataStore -> zero quarantine, zero data loss, embedded outcomeJSON backfilled!
        let v20Store = ConfluenceDataStore(inMemory: false, customStoreURL: storeURL)
        XCTAssertFalse(v20Store.didQuarantineCorruptStore, "v1.5 -> v2.0 migration must NEVER quarantine store")

        let signals = v20Store.fetchSignals()
        XCTAssertEqual(signals.count, 1)
        XCTAssertEqual(signals.first?.fingerprint, "fp-v15-embedded")

        let outcomes = v20Store.fetchOutcomeRecords()
        XCTAssertEqual(outcomes.count, 2, "Both decoupled and backfilled outcomeJSON records must survive v2.0 migration")
        let outcomeById = Dictionary(uniqueKeysWithValues: outcomes.map { ($0.signalId, $0) })
        XCTAssertEqual(outcomeById["fp-v15-embedded"]?.status, .hitTP2)
        XCTAssertEqual(outcomeById["fp-v15-embedded"]?.rMultiple ?? 0, 3.1, accuracy: 1e-6)
        XCTAssertEqual(outcomeById["fp-v15-decoupled"]?.status, .hitTP1)

        // 3. Delete signal card and reopen -> backfilled outcome must persist permanently in PersistedOutcomeRecord
        v20Store.deleteSignal(fingerprint: "fp-v15-embedded")
        let reopened = ConfluenceDataStore(inMemory: false, customStoreURL: storeURL)
        XCTAssertFalse(reopened.didQuarantineCorruptStore)
        XCTAssertTrue(reopened.fetchSignals().isEmpty)
        XCTAssertEqual(reopened.fetchOutcomeRecords().count, 2)
    }

    // MARK: - 2. On-Disk v1.6 (13-Table) -> v2.0 (9-Table) Staged Migration + TrackedJournalTrade Preservation

    @MainActor
    func testOnDiskV16ThirteenTableStoreUpgradesCleanlyToV20PreservingTrackedJournal() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("confluence_v16_to_v20_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("confluence_v16.store")

        let base: TimeInterval = 1_760_600_000
        let sig = makeSampleSignal(
            fingerprint: "fp-v16-live",
            symbol: "BTC/USDT",
            marketClass: .crypto,
            epochSeconds: base
        )
        let embeddedOutcome = makeSampleOutcome(
            signalId: "fp-v16-live",
            symbol: "BTC/USDT",
            marketClass: .crypto,
            status: .hitTP1,
            rMultiple: 2.4,
            resolvedAt: base + 5_400
        )
        let tracked = TrackedJournalTrade(
            id: "BTC/USDT|30m|strong_signals|\(Int(base))",
            symbol: "BTC/USDT",
            assetClass: .crypto,
            timeframe: .m30,
            direction: .long,
            section: .strongSignals,
            status: .winTrackingTP2,
            score: 86.0,
            signalBarTimestamp: base,
            entryZoneLow: 60_000,
            entryZoneHigh: 60_200,
            entryPrice: 60_100,
            fillPrice: 60_100,
            stopLoss: 59_100,
            target1: 62_100,
            target2: 63_600,
            isTP2Enabled: true,
            currentPrice: 62_450,
            livePnLPercent: 3.91,
            liveRMultiple: 2.35,
            realizedR: 2.0,
            isWinLocked: true,
            activeStrategyProfileKey: "ict_bos+ict_fvg",
            orderFlowStatus: "aligned",
            createdAt: base,
            filledAt: base + 600,
            tp1HitAt: base + 2_400,
            matchedStrategyIDs: ["ict_bos", "ict_fvg"]
        )

        let signalData = try JSONEncoder().encode(sig)
        let embeddedOutcomeData = try JSONEncoder().encode(embeddedOutcome)

        // 1. Seed a real on-disk v1.6 (13-table) store with all surviving + retired models populated
        do {
            let v16Schema = Schema(versionedSchema: ConfluenceSchemaV16.self)
            let v16Config = ModelConfiguration(schema: v16Schema, url: storeURL)
            let v16Container = try ModelContainer(for: v16Schema, configurations: [v16Config])
            let ctx = ModelContext(v16Container)

            ctx.insert(ConfluenceSchemaV16.PersistedSignalRecord(
                fingerprint: sig.fingerprint,
                symbol: sig.symbol,
                directionRaw: sig.direction.rawValue,
                categoryRaw: sig.category.rawValue,
                createdAt: Date(timeIntervalSince1970: base),
                signalJSON: signalData,
                outcomeJSON: embeddedOutcomeData,
                activeStrategyProfileKey: "ict_bos+ict_fvg",
                enabledStrategyIDsCSV: "ict_bos,ict_fvg",
                orderFlowStatus: "aligned"
            ))
            ctx.insert(TrackedSignalJournalEntry(from: tracked))
            ctx.insert(ConfluenceSchemaV16.JournalEntry(
                id: "legacy-j-v16",
                symbol: "NAS100",
                marketRaw: MarketClass.indices.rawValue,
                timeframeRaw: Timeframe.h1.rawValue,
                directionRaw: TradeDirection.short.rawValue,
                plannedEntry: 20_500,
                stopLoss: 20_620,
                tp1: 20_260
            ))
            ctx.insert(ConfluenceSchemaV16.DemoWalletRecord(id: "primary", cashBalanceUSD: 940))
            ctx.insert(ConfluenceSchemaV16.DemoPositionRecord(
                id: "demo-pos-v16",
                symbol: "ETH/USDT",
                statusRaw: "closed",
                positionJSON: Data("{}".utf8),
                createdAt: Date(timeIntervalSince1970: base)
            ))
            ctx.insert(ConfluenceSchemaV16.DemoWalletTransactionRecord(
                id: "demo-tx-v16",
                timestamp: Date(timeIntervalSince1970: base),
                kindRaw: "fee",
                amountUSD: -2.5,
                balanceAfterUSD: 940,
                note: "Paper fee"
            ))
            try ctx.save()
        }

        // 2. Open with v2.0 ConfluenceDataStore -> zero quarantine, signals + backfilled outcomes + tracked journal preserved
        let v20Store = ConfluenceDataStore(inMemory: false, customStoreURL: storeURL)
        XCTAssertFalse(v20Store.didQuarantineCorruptStore, "v1.6 -> v2.0 migration must NEVER quarantine store")

        XCTAssertEqual(v20Store.fetchSignals().first?.fingerprint, "fp-v16-live")
        XCTAssertEqual(v20Store.fetchOutcomeRecords().first?.signalId, "fp-v16-live")
        XCTAssertEqual(v20Store.fetchOutcomeRecords().first?.status, .hitTP1)

        let loadedJournal = v20Store.loadTrackedJournalEntries()
        XCTAssertEqual(loadedJournal.count, 1)
        XCTAssertEqual(loadedJournal.first?.id, tracked.id)
        XCTAssertEqual(loadedJournal.first?.status, .winTrackingTP2)
        XCTAssertEqual(loadedJournal.first?.isWinLocked, true)
        XCTAssertEqual(loadedJournal.first?.timeframe, .m30)

        // 3. Reopen v2.0 store a second time -> idempotent zero-quarantine startup
        let reopened = ConfluenceDataStore(inMemory: false, customStoreURL: storeURL)
        XCTAssertFalse(reopened.didQuarantineCorruptStore)
        XCTAssertEqual(reopened.loadTrackedJournalEntries().count, 1)
        XCTAssertEqual(reopened.fetchOutcomeRecords().count, 1)
    }

    // MARK: - 3. BackupArchiveService v1 / v2 / v3 Compatibility Round-Trip

    @MainActor
    func testBackupArchiveV1V2V3DecodeAndRestoreCompatibility() throws {
        XCTAssertEqual(ConfluenceBackupArchive.currentSchemaVersion, 3)

        // 1. Legacy v1 JSON (with obsolete journalEntries & demoWallet, missing trackedJournalEntries & tvLastChartURL)
        let v1JSON = """
        {
          "schemaVersion": 1,
          "exportedAtISO8601": "2026-04-01T00:00:00Z",
          "appBundleId": "com.bilal.confluence",
          "appVersion": "1.4.0",
          "settings": {},
          "signals": [],
          "outcomes": [],
          "tradeLedger": [],
          "journalEntries": [
            { "id": "legacy-manual-1", "symbol": "EUR/USD", "notes": "old entry" }
          ],
          "demoWallet": { "cashBalanceUSD": 1000 }
        }
        """
        let decodedV1 = try BackupArchiveService.decodeAndValidateArchive(from: Data(v1JSON.utf8))
        XCTAssertEqual(decodedV1.schemaVersion, 1)
        XCTAssertTrue(decodedV1.trackedJournalEntries.isEmpty)
        XCTAssertNil(decodedV1.tvLastChartURL)

        // 2. Legacy v2 JSON (with journalEntries + trackedJournalEntries + tvLastChartURL)
        let now: TimeInterval = 1_760_700_000
        let sampleTrade = TrackedJournalTrade(
            id: "v2-tracked-1",
            symbol: "SOL/USDT",
            assetClass: .crypto,
            timeframe: .h1,
            direction: .long,
            section: .strongSignals,
            status: .winTP2,
            score: 88.0,
            signalBarTimestamp: now,
            entryZoneLow: 150.0,
            entryZoneHigh: 151.0,
            entryPrice: 150.5,
            fillPrice: 150.5,
            stopLoss: 147.5,
            target1: 156.5,
            target2: 160.0,
            currentPrice: 160.0,
            livePnLPercent: 6.31,
            liveRMultiple: 3.16,
            realizedR: 3.16,
            isWinLocked: true,
            createdAt: now,
            filledAt: now,
            closedAt: now + 3_600
        )
        let tradeJSON = String(data: try JSONEncoder().encode([sampleTrade]), encoding: .utf8) ?? "[]"
        let v2JSON = """
        {
          "schemaVersion": 2,
          "exportedAtISO8601": "2026-05-01T00:00:00Z",
          "appBundleId": "com.bilal.confluence",
          "appVersion": "1.5.5",
          "settings": {},
          "signals": [],
          "outcomes": [],
          "tradeLedger": [],
          "journalEntries": [],
          "trackedJournalEntries": \(tradeJSON),
          "tvLastChartURL": "https://www.tradingview.com/chart/V2Layout/?symbol=BINANCE:SOLUSDT&interval=60"
        }
        """
        let decodedV2 = try BackupArchiveService.decodeAndValidateArchive(from: Data(v2JSON.utf8))
        XCTAssertEqual(decodedV2.schemaVersion, 2)
        XCTAssertEqual(decodedV2.trackedJournalEntries.count, 1)
        XCTAssertEqual(decodedV2.trackedJournalEntries.first?.id, "v2-tracked-1")
        XCTAssertEqual(
            decodedV2.tvLastChartURL,
            "https://www.tradingview.com/chart/V2Layout/?symbol=BINANCE:SOLUSDT&interval=60"
        )

        // 3. v3 build -> encode -> restore round-trip on v2.0 ConfluenceDataStore
        let sourceStore = ConfluenceDataStore(inMemory: true)
        let sourceSettings = AppSettingsStore()
        sourceStore.upsertTrackedJournalEntry(sampleTrade)
        let v3Archive = BackupArchiveService.buildArchive(
            settings: sourceSettings.payload,
            store: sourceStore,
            appVersion: "1.6.0"
        )
        XCTAssertEqual(v3Archive.schemaVersion, 3)
        let v3Data = try BackupArchiveService.encodeRedactedArchiveData(v3Archive)

        let targetStore = ConfluenceDataStore(inMemory: true)
        let targetSettings = AppSettingsStore()
        let summary = try BackupArchiveService.restoreArchive(
            from: v3Data,
            mode: .replace,
            settingsStore: targetSettings,
            dataStore: targetStore
        )
        XCTAssertEqual(summary.schemaVersion, 3)
        XCTAssertEqual(summary.journalImported, 1)
        XCTAssertEqual(targetStore.loadTrackedJournalEntries().first?.id, "v2-tracked-1")

        // 4. Reject future schemaVersion (> 3)
        let v4JSON = v1JSON.replacingOccurrences(of: "\"schemaVersion\": 1", with: "\"schemaVersion\": 4")
        XCTAssertThrowsError(try BackupArchiveService.decodeAndValidateArchive(from: Data(v4JSON.utf8)))
    }
}
