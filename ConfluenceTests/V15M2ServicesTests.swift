import Foundation
import SwiftData
import XCTest
@testable import Confluence
import SignalEngine

final class V15M2ServicesTests: XCTestCase {
    // MARK: - YahooPricingProtobufDecoder Tests

    private func encodeVarint(_ value: UInt64) -> [UInt8] {
        var v = value
        var out: [UInt8] = []
        while v >= 0x80 {
            out.append(UInt8((v & 0x7F) | 0x80))
            v >>= 7
        }
        out.append(UInt8(v))
        return out
    }

    private func encodeZigZag(_ value: Int64) -> UInt64 {
        UInt64(bitPattern: (value << 1) ^ (value >> 63))
    }

    private func encodeFloat32(_ value: Float) -> [UInt8] {
        let bits = value.bitPattern
        return [
            UInt8(bits & 0xFF),
            UInt8((bits >> 8) & 0xFF),
            UInt8((bits >> 16) & 0xFF),
            UInt8((bits >> 24) & 0xFF)
        ]
    }

    func testYahooProtobufDecoderAndScaleGuards() {
        // Construct a real Yahoo PricingData protobuf wire frame:
        // field 1 (id: string), field 2 (price: float), field 3 (time: sint64 ms),
        // field 8 (changePercent: float), field 12 (marketHours: varint)
        var bytes: [UInt8] = []
        let symBytes = Array("EURUSD=X".utf8)
        bytes += encodeVarint((1 << 3) | 2)
        bytes += encodeVarint(UInt64(symBytes.count))
        bytes += symBytes

        bytes += encodeVarint((2 << 3) | 5)
        bytes += encodeFloat32(1.08425)

        let tsMs: Int64 = 1_760_050_000_000
        bytes += encodeVarint((3 << 3) | 0)
        bytes += encodeVarint(encodeZigZag(tsMs))

        bytes += encodeVarint((8 << 3) | 5)
        bytes += encodeFloat32(0.42)

        bytes += encodeVarint((12 << 3) | 0)
        bytes += encodeVarint(1)

        let b64 = Data(bytes).base64EncodedString()
        let decoded = YahooPricingProtobufDecoder.decodeBase64(b64)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.id, "EURUSD=X")
        XCTAssertEqual(decoded?.price ?? 0, 1.08425, accuracy: 0.0001)
        XCTAssertEqual(decoded?.timestampEpochSeconds ?? 0, 1_760_050_000, accuracy: 0.5)
        XCTAssertEqual(decoded?.changePercent ?? 0, 0.42, accuracy: 0.01)
        XCTAssertEqual(decoded?.marketHours, 1)

        // Bad-tick & scale guards:
        // FX >2% rejected, <=2% accepted
        XCTAssertTrue(YahooPricingProtobufDecoder.isAcceptableTick(marketClass: .forex, price: 1.09, referenceClose: 1.08))
        XCTAssertFalse(YahooPricingProtobufDecoder.isAcceptableTick(marketClass: .forex, price: 1.15, referenceClose: 1.08))
        // SPY (~550) vs US500 (~5500) scale mismatch rejected
        XCTAssertFalse(YahooPricingProtobufDecoder.isAcceptableTick(marketClass: .indices, price: 550.0, referenceClose: 5_500.0))
        // GC=F diverging >2% from spot XAU/USD rejected (triggers biquote fallback)
        XCTAssertFalse(YahooPricingProtobufDecoder.isAcceptableTick(marketClass: .metals, price: 2_690.0, referenceClose: 2_600.0))
        // Stocks allow up to 5%
        XCTAssertTrue(YahooPricingProtobufDecoder.isAcceptableTick(marketClass: .stocks, price: 208.0, referenceClose: 200.0))
        XCTAssertFalse(YahooPricingProtobufDecoder.isAcceptableTick(marketClass: .stocks, price: 220.0, referenceClose: 200.0))
    }

    func testBinanceKlineStreamParser() {
        let frame = #"{"stream":"btcusdt@kline_1m","data":{"e":"kline","E":1760050005000,"s":"BTCUSDT","k":{"s":"BTCUSDT","c":"61234.50","v":"12.34","x":false}}}"#
        let parsed = BinanceLiveStreamParser.parseKlineFrame(frame)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.binanceSymbol, "BTCUSDT")
        XCTAssertEqual(parsed?.price ?? 0, 61_234.50, accuracy: 0.01)
        XCTAssertEqual(parsed?.isCandleClosed, false)
    }

    // MARK: - LivePriceEngine 8-Symbol LRU Cap & Release Tests

    func testLivePriceEngineEightSymbolCapAndRelease() async {
        let engine = LivePriceEngine(onQuote: { _ in })
        await engine.updateModes(tradFi: .off, crypto: .off)

        let batch1 = ["BTC/USDT", "ETH/USDT", "SOL/USDT", "EUR/USD", "GBP/USD", "USD/JPY"]
        let active1 = await engine.acquire(owner: "owner_a", symbols: batch1)
        XCTAssertEqual(active1.count, 6)

        // Adding 4 more symbols via a newer owner must cap total at 8 (LRU drops oldest symbols)
        let batch2 = ["XAU/USD", "US500", "NAS100", "AAPL"]
        let active2 = await engine.acquire(owner: "owner_b", symbols: batch2)
        XCTAssertEqual(active2.count, 8)
        XCTAssertTrue(active2.contains("AAPL"))
        XCTAssertTrue(active2.contains("XAU/USD"))

        // Releasing owner_b restores owner_a's 6 symbols; releasing owner_a empties list
        let active3 = await engine.release(owner: "owner_b")
        XCTAssertEqual(active3.count, 6)
        let active4 = await engine.release(owner: "owner_a")
        XCTAssertTrue(active4.isEmpty)
    }

    // MARK: - On-Disk SwiftData v1.5 -> v1.6 Additive Migration Test (12 -> 13 tables)

    @MainActor
    func testSwiftDataV15ToV16AdditiveMigrationPreservesLegacyTablesAndPersistsTrackedJournal() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("confluence_v16_mig_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("confluence_v16.store")

        // 1. Seed a 12-table v1.5 on-disk store (including legacy Demo tables, without TrackedSignalJournalEntry)
        let now: TimeInterval = 1_776_175_200
        let sampleOutcome = SignalOutcomeRecord(
            signalId: "fp-v15-keep",
            symbol: "EUR/USD",
            marketClass: .forex,
            category: .strongSignal,
            direction: .long,
            predictedProbability: 0.76,
            status: .hitTP1,
            netReturnPercent: 0.9,
            rMultiple: 2.0,
            strategyIds: ["ict_bos"],
            hadMacroCatalyst: false,
            resolvedAtEpochSeconds: now
        )
        let outcomeData = try JSONEncoder().encode(sampleOutcome)

        do {
            let v15Schema = Schema([
                ConfluenceSchemaV16.PersistedSignalRecord.self,
                StoredNotificationItem.self,
                DiagnosticLogEntry.self,
                TrapLogEntry.self,
                TradeLedgerEntry.self,
                TradeReplayCandleCache.self,
                PersistedOutcomeRecord.self,
                CrashLogEntry.self,
                ConfluenceSchemaV16.JournalEntry.self,
                ConfluenceSchemaV16.DemoWalletRecord.self,
                ConfluenceSchemaV16.DemoPositionRecord.self,
                ConfluenceSchemaV16.DemoWalletTransactionRecord.self
            ])
            let v15Config = ModelConfiguration(schema: v15Schema, url: storeURL)
            let v15Container = try ModelContainer(for: v15Schema, configurations: [v15Config])
            let ctx = ModelContext(v15Container)
            ctx.insert(PersistedOutcomeRecord(
                signalId: sampleOutcome.signalId,
                outcomeJSON: outcomeData,
                resolvedAt: Date(timeIntervalSince1970: now)
            ))
            ctx.insert(ConfluenceSchemaV16.JournalEntry(
                id: "j-v15-keep",
                symbol: "EUR/USD",
                marketRaw: MarketClass.forex.rawValue,
                timeframeRaw: Timeframe.h1.rawValue,
                directionRaw: TradeDirection.long.rawValue,
                plannedEntry: 1.10,
                stopLoss: 1.095,
                tp1: 1.11
            ))
            ctx.insert(ConfluenceSchemaV16.DemoWalletRecord(id: "primary", cashBalanceUSD: 1_250))
            try ctx.save()
        }

        // 2. Reopen with v2.0 ConfluenceDataStore -> zero quarantine, decoupled outcomes preserved & legacy tables retired
        let store = ConfluenceDataStore(inMemory: false, customStoreURL: storeURL)
        XCTAssertFalse(store.didQuarantineCorruptStore)
        XCTAssertEqual(store.fetchOutcomeRecords().first?.signalId, "fp-v15-keep")

        // 3. Persist TrackedJournalTrade and verify round-trip across disk reopen
        let tracked = TrackedJournalTrade(
            id: "tj-disk-1",
            symbol: "BTC/USDT",
            assetClass: .crypto,
            timeframe: .m30,
            direction: .long,
            section: .strongSignals,
            status: .live,
            score: 84.0,
            signalBarTimestamp: now,
            entryZoneLow: 59_900,
            entryZoneHigh: 60_100,
            entryPrice: 60_000,
            fillPrice: 60_000,
            stopLoss: 59_000,
            target1: 62_000,
            target2: 63_500,
            isTP2Enabled: true,
            currentPrice: 60_500,
            livePnLPercent: 0.83,
            liveRMultiple: 0.50,
            createdAt: now,
            filledAt: now
        )
        store.upsertTrackedJournalEntry(tracked)

        let reopened = ConfluenceDataStore(inMemory: false, customStoreURL: storeURL)
        XCTAssertFalse(reopened.didQuarantineCorruptStore)
        let loaded = reopened.loadTrackedJournalEntries()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, "tj-disk-1")
        XCTAssertEqual(loaded.first?.timeframe, .m30)
        XCTAssertEqual(loaded.first?.section, .strongSignals)
    }

    // MARK: - Backup v3 Round-Trip + Legacy Archive Import + SecretRedactor Tests

    @MainActor
    func testBackupV2RoundTripLegacyV1ImportAndSecretRedactor() throws {
        // 1. SecretRedactor strips sk- and sk-or- keys cleanly
        let rawText = "deepseek=sk-1234567890abcdefghij openrouter=sk-or-v1-abcdef0123456789abcdef"
        let scrubbed = SecretRedactor.redact(rawText)
        XCTAssertFalse(scrubbed.contains("sk-1234567890"))
        XCTAssertFalse(scrubbed.contains("sk-or-v1-abcdef"))
        XCTAssertTrue(scrubbed.contains("[REDACTED_API_KEY]"))
        XCTAssertTrue(scrubbed.contains("[REDACTED_OPENROUTER_KEY]"))

        // 2. Backup v3 round-trip includes TrackedJournalTrade entries & CSV export
        let store = ConfluenceDataStore(inMemory: true)
        let settings = AppSettingsStore()
        let now: TimeInterval = 1_776_175_200
        let sampleTracked = TrackedJournalTrade(
            id: "tj-backup-1",
            symbol: "ETH/USDT",
            assetClass: .crypto,
            timeframe: .m30,
            direction: .short,
            section: .weakAndFiltered,
            status: .winTP1,
            score: 62.0,
            signalBarTimestamp: now,
            entryZoneLow: 3_000,
            entryZoneHigh: 3_010,
            entryPrice: 3_005,
            fillPrice: 3_005,
            stopLoss: 3_065,
            target1: 2_885,
            target2: 2_825,
            isTP2Enabled: true,
            currentPrice: 2_885,
            livePnLPercent: 3.99,
            liveRMultiple: 2.0,
            realizedR: 2.0,
            isWinLocked: true,
            createdAt: now,
            filledAt: now,
            tp1HitAt: now + 1_800,
            closedAt: now + 3_600,
            filterReason: "Score 62 < 70"
        )
        store.upsertTrackedJournalEntry(sampleTracked)

        let archive = BackupArchiveService.buildArchive(settings: settings.payload, store: store, appVersion: "1.6.0")
        XCTAssertEqual(archive.schemaVersion, ConfluenceBackupArchive.currentSchemaVersion)
        XCTAssertEqual(archive.schemaVersion, 3)
        XCTAssertEqual(archive.trackedJournalEntries.count, 1)
        let encoded = try BackupArchiveService.encodeRedactedArchiveData(archive)

        let targetStore = ConfluenceDataStore(inMemory: true)
        let targetSettings = AppSettingsStore()
        let summary = try BackupArchiveService.restoreArchive(
            from: encoded,
            mode: .replace,
            settingsStore: targetSettings,
            dataStore: targetStore
        )
        XCTAssertEqual(summary.schemaVersion, 3)
        XCTAssertEqual(targetStore.loadTrackedJournalEntries().first?.id, "tj-backup-1")

        let csv = BackupArchiveService.buildTrackedJournalCSV(entries: [sampleTracked])
        XCTAssertTrue(csv.contains("ETH/USDT"))
        XCTAssertTrue(csv.contains("weak_and_filtered"))
        XCTAssertTrue(csv.contains("win_tp1"))

        // 3. Legacy v1/v2 archive (omitting trackedJournalEntries, even with obsolete demoWallet key) decodes cleanly
        let legacyJSON = """
        {
          "schemaVersion": 1,
          "exportedAtISO8601": "2026-04-01T00:00:00Z",
          "appBundleId": "com.bilal.confluence",
          "appVersion": "1.4.0",
          "settings": {},
          "signals": [],
          "outcomes": [],
          "tradeLedger": [],
          "journalEntries": [],
          "demoWallet": { "cashBalanceUSD": 1000 }
        }
        """
        let decodedLegacy = try BackupArchiveService.decodeAndValidateArchive(from: Data(legacyJSON.utf8))
        XCTAssertEqual(decodedLegacy.schemaVersion, 1)
        XCTAssertTrue(decodedLegacy.trackedJournalEntries.isEmpty)
    }
}
