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

    // MARK: - TradeMonitor Tests (Auto-Close Exit Price + Manual Apply/Dismiss + Outcome Derivation)

    func testTradeMonitorDemoReconcileManualAlertsAndOutcomeDerivation() {
        // 1. Journal outcome derivation fixes "OPEN + Exit + R" bug
        XCTAssertEqual(
            TradeMonitor.deriveJournalOutcome(direction: .long, entryPrice: 100, exitPrice: 106, stopLoss: 98, currentOutcome: .open),
            .win
        )
        XCTAssertEqual(
            TradeMonitor.deriveJournalOutcome(direction: .long, entryPrice: 100, exitPrice: 97, stopLoss: 98, currentOutcome: .open),
            .loss
        )
        XCTAssertEqual(
            TradeMonitor.deriveJournalOutcome(direction: .long, entryPrice: 100, exitPrice: nil, stopLoss: 98, currentOutcome: .open),
            .open
        )

        // 2. Demo position auto-closes cleanly at exact Target 1 level on tick
        let now: TimeInterval = 1_776_175_200 // Tuesday 14:00 UTC
        let req = DemoOrderRequest(
            id: "demo-1",
            symbol: "BTC/USDT",
            marketClass: .crypto,
            direction: .long,
            orderType: .market,
            entryPrice: 60_000,
            stopLoss: 59_000,
            target1: 62_000
        )
        guard case .success((let w1, _)) = DemoWalletEngine.placeOrder(
            wallet: DemoWallet(),
            request: req,
            liveQuotePrice: 60_000,
            liveQuoteEpochSeconds: now,
            nowEpochSeconds: now
        ) else {
            XCTFail("Expected demo order to open")
            return
        }

        let targetQuote = LivePriceQuote(
            symbol: "BTC/USDT",
            price: 62_150,
            asOfEpochSeconds: now + 30,
            sourceLabel: "Binance Live",
            isStreaming: true
        )
        let (w2, events) = TradeMonitor.reconcileDemoWalletOnTick(wallet: w1, quote: targetQuote)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(w2.positions.first?.status, .closedTarget1)
        XCTAssertEqual(w2.positions.first?.exitPrice, 62_000) // Exact Target 1 level

        // 3. Manual journal trades NEVER auto-close; instead they emit an Apply/Dismiss suggestion
        let manualEntry = JournalEntrySnapshot(
            id: "j-manual-1",
            symbol: "BTC/USDT",
            marketClass: .crypto,
            timeframe: .h1,
            direction: .long,
            plannedEntry: 60_000,
            actualFillPrice: 60_000,
            stopLoss: 59_000,
            tp1: 62_000,
            outcome: .open
        )
        let alerts = TradeMonitor.evaluateManualJournalAlerts(
            entries: [manualEntry],
            quote: targetQuote,
            dismissedIds: []
        )
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts.first?.suggestedOutcome, .win)
        XCTAssertEqual(alerts.first?.suggestedExitPrice, 62_000)

        let dismissedAlerts = TradeMonitor.evaluateManualJournalAlerts(
            entries: [manualEntry],
            quote: targetQuote,
            dismissedIds: ["j-manual-1"]
        )
        XCTAssertTrue(dismissedAlerts.isEmpty)
    }

    // MARK: - On-Disk SwiftData v1.4 -> v1.5 Additive Migration Test (9 -> 12 tables)

    @MainActor
    func testSwiftDataV14ToV15AdditiveMigrationPreservesDataAndPersistsDemoWallet() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("confluence_v15_mig_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("confluence_v15.store")

        // 1. Seed a 9-table v1.4 on-disk store (without DemoWalletRecord/DemoPositionRecord/DemoWalletTransactionRecord)
        do {
            let v14Schema = Schema([
                PersistedSignalRecord.self,
                StoredNotificationItem.self,
                DiagnosticLogEntry.self,
                TrapLogEntry.self,
                TradeLedgerEntry.self,
                TradeReplayCandleCache.self,
                PersistedOutcomeRecord.self,
                CrashLogEntry.self,
                JournalEntry.self
            ])
            let v14Config = ModelConfiguration(schema: v14Schema, url: storeURL)
            let v14Container = try ModelContainer(for: v14Schema, configurations: [v14Config])
            let ctx = ModelContext(v14Container)
            ctx.insert(JournalEntry(
                id: "j-v14-keep",
                symbol: "EUR/USD",
                marketRaw: MarketClass.forex.rawValue,
                timeframeRaw: Timeframe.h1.rawValue,
                directionRaw: TradeDirection.long.rawValue,
                plannedEntry: 1.10,
                stopLoss: 1.095,
                tp1: 1.11
            ))
            try ctx.save()
        }

        // 2. Reopen with v1.5 12-table ConfluenceDataStore -> zero quarantine, journal preserved
        let store = ConfluenceDataStore(inMemory: false, customStoreURL: storeURL)
        XCTAssertFalse(store.didQuarantineCorruptStore)
        XCTAssertEqual(store.fetchJournalEntries().first?.id, "j-v14-keep")

        // 3. Save DemoWallet and verify round-trip across disk reopen
        let now: TimeInterval = 1_776_175_200
        let req = DemoOrderRequest(
            id: "demo-disk-1",
            symbol: "BTC/USDT",
            marketClass: .crypto,
            direction: .long,
            orderType: .market,
            entryPrice: 60_000,
            stopLoss: 59_000,
            target1: 62_000
        )
        guard case .success((let wallet, _)) = DemoWalletEngine.placeOrder(
            wallet: DemoWallet(startingBalanceUSD: 1_000),
            request: req,
            liveQuotePrice: 60_000,
            liveQuoteEpochSeconds: now,
            nowEpochSeconds: now
        ) else {
            XCTFail("Expected demo order to open")
            return
        }
        store.saveDemoWallet(wallet)

        let reopened = ConfluenceDataStore(inMemory: false, customStoreURL: storeURL)
        XCTAssertFalse(reopened.didQuarantineCorruptStore)
        let loaded = reopened.loadDemoWallet()
        XCTAssertEqual(loaded.positions.count, 1)
        XCTAssertEqual(loaded.positions.first?.id, "demo-disk-1")
        XCTAssertEqual(loaded.transactions.count, wallet.transactions.count)
    }

    // MARK: - Backup v2 Round-Trip + Legacy v1 Import + SecretRedactor Tests

    @MainActor
    func testBackupV2RoundTripLegacyV1ImportAndSecretRedactor() throws {
        // 1. SecretRedactor strips sk- and sk-or- keys cleanly
        let rawText = "deepseek=sk-1234567890abcdefghij openrouter=sk-or-v1-abcdef0123456789abcdef"
        let scrubbed = SecretRedactor.redact(rawText)
        XCTAssertFalse(scrubbed.contains("sk-1234567890"))
        XCTAssertFalse(scrubbed.contains("sk-or-v1-abcdef"))
        XCTAssertTrue(scrubbed.contains("[REDACTED_API_KEY]"))
        XCTAssertTrue(scrubbed.contains("[REDACTED_OPENROUTER_KEY]"))

        // 2. Backup v2 round-trip includes DemoWallet & CSV export
        let store = ConfluenceDataStore(inMemory: true)
        let settings = AppSettingsStore()
        var wallet = DemoWallet(startingBalanceUSD: 1_500)
        wallet = DemoWalletEngine.adjustBalance(wallet: wallet, newBalanceUSD: 1_750, nowEpochSeconds: 1_776_175_200)
        store.saveDemoWallet(wallet)

        let archive = BackupArchiveService.buildArchive(settings: settings.payload, store: store, appVersion: "1.5.0")
        XCTAssertEqual(archive.schemaVersion, 2)
        XCTAssertEqual(archive.demoWallet?.cashBalanceUSD, 1_750)
        let encoded = try BackupArchiveService.encodeRedactedArchiveData(archive)

        let targetStore = ConfluenceDataStore(inMemory: true)
        let targetSettings = AppSettingsStore()
        let summary = try BackupArchiveService.restoreArchive(
            from: encoded,
            mode: .replace,
            settingsStore: targetSettings,
            dataStore: targetStore
        )
        XCTAssertEqual(summary.schemaVersion, 2)
        XCTAssertTrue(summary.demoWalletRestored)
        XCTAssertEqual(targetStore.loadDemoWallet().cashBalanceUSD, 1_750)

        let csv = BackupArchiveService.buildDemoWalletTransactionsCSV(transactions: wallet.transactions)
        XCTAssertTrue(csv.contains("balanceAdjustment"))

        // 3. Legacy v1 archive (without demoWallet key) still decodes and imports cleanly
        let legacyV1JSON = """
        {
          "schemaVersion": 1,
          "exportedAtISO8601": "2026-04-01T00:00:00Z",
          "appBundleId": "com.bilal.confluence",
          "appVersion": "1.4.0",
          "settings": {},
          "signals": [],
          "outcomes": [],
          "tradeLedger": [],
          "journalEntries": []
        }
        """
        let decodedV1 = try BackupArchiveService.decodeAndValidateArchive(from: Data(legacyV1JSON.utf8))
        XCTAssertEqual(decodedV1.schemaVersion, 1)
        XCTAssertNil(decodedV1.demoWallet)
    }
}
