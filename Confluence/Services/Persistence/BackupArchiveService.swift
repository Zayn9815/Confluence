import Foundation
import SignalEngine

public enum BackupImportMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case merge = "Merge (Keep Existing)"
    case replace = "Replace All Local Data"

    public var id: String { rawValue }
}

public struct ConfluenceBackupArchive: Codable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let exportedAtISO8601: String
    public let appBundleId: String
    public let appVersion: String
    public let settings: PersistedSettingsPayload
    public let signals: [TradeSignal]
    public let outcomes: [SignalOutcomeRecord]
    public let tradeLedger: [TradeLedgerSnapshot]
    public let journalEntries: [JournalEntrySnapshot]
    public let demoWallet: DemoWallet?

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        exportedAtISO8601: String = ISO8601DateFormatter().string(from: Date()),
        appBundleId: String = "com.bilal.confluence",
        appVersion: String,
        settings: PersistedSettingsPayload,
        signals: [TradeSignal],
        outcomes: [SignalOutcomeRecord],
        tradeLedger: [TradeLedgerSnapshot],
        journalEntries: [JournalEntrySnapshot],
        demoWallet: DemoWallet? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAtISO8601 = exportedAtISO8601
        self.appBundleId = appBundleId
        self.appVersion = appVersion
        self.settings = settings
        self.signals = signals
        self.outcomes = outcomes
        self.tradeLedger = tradeLedger
        self.journalEntries = journalEntries
        self.demoWallet = demoWallet
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, exportedAtISO8601, appBundleId, appVersion
        case settings, signals, outcomes, tradeLedger, journalEntries, demoWallet
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        exportedAtISO8601 = try c.decode(String.self, forKey: .exportedAtISO8601)
        appBundleId = try c.decode(String.self, forKey: .appBundleId)
        appVersion = try c.decode(String.self, forKey: .appVersion)
        settings = try c.decode(PersistedSettingsPayload.self, forKey: .settings)
        signals = (try? c.decodeIfPresent([TradeSignal].self, forKey: .signals)) ?? []
        outcomes = (try? c.decodeIfPresent([SignalOutcomeRecord].self, forKey: .outcomes)) ?? []
        tradeLedger = (try? c.decodeIfPresent([TradeLedgerSnapshot].self, forKey: .tradeLedger)) ?? []
        journalEntries = (try? c.decodeIfPresent([JournalEntrySnapshot].self, forKey: .journalEntries)) ?? []
        demoWallet = try? c.decodeIfPresent(DemoWallet.self, forKey: .demoWallet)
    }
}

public struct BackupImportSummary: Sendable, Equatable {
    public let signalsImported: Int
    public let outcomesImported: Int
    public let journalImported: Int
    public let settingsRestored: Bool
    public let schemaVersion: Int
    public let demoWalletRestored: Bool

    public init(
        signalsImported: Int,
        outcomesImported: Int,
        journalImported: Int,
        settingsRestored: Bool,
        schemaVersion: Int,
        demoWalletRestored: Bool = false
    ) {
        self.signalsImported = signalsImported
        self.outcomesImported = outcomesImported
        self.journalImported = journalImported
        self.settingsRestored = settingsRestored
        self.schemaVersion = schemaVersion
        self.demoWalletRestored = demoWalletRestored
    }
}

public enum BackupArchiveError: Error, LocalizedError, Sendable {
    case unsupportedSchemaVersion(Int)
    case invalidBundleIdentifier(String)
    case invalidJSON(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let v):
            return "Backup schema version \(v) is newer than supported version \(ConfluenceBackupArchive.currentSchemaVersion)."
        case .invalidBundleIdentifier(let id):
            return "Backup file belongs to an unrecognized bundle (\(id))."
        case .invalidJSON(let detail):
            return "Could not decode backup JSON: \(detail)"
        }
    }
}

/// Versioned JSON Backup & Restore + RFC-4180 CSV exporter.
/// Strictly excludes all Keychain API keys and passes every exported payload through `SecretRedactor`.
public enum BackupArchiveService {
    @MainActor
    public static func buildArchive(
        settings: PersistedSettingsPayload,
        store: ConfluenceDataStore,
        appVersion: String
    ) -> ConfluenceBackupArchive {
        ConfluenceBackupArchive(
            schemaVersion: ConfluenceBackupArchive.currentSchemaVersion,
            exportedAtISO8601: ISO8601DateFormatter().string(from: Date()),
            appBundleId: "com.bilal.confluence",
            appVersion: appVersion,
            settings: settings,
            signals: store.fetchSignals(limit: 500),
            outcomes: store.fetchOutcomeRecords(),
            tradeLedger: store.fetchTradeLedger(limit: 500),
            journalEntries: store.fetchJournalEntries(limit: 500),
            demoWallet: store.loadDemoWallet()
        )
    }

    @MainActor
    public static func encodeRedactedArchiveData(_ archive: ConfluenceBackupArchive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let rawData = try encoder.encode(archive)
        let rawString = String(data: rawData, encoding: .utf8) ?? "{}"
        let redacted = SecretRedactor.redact(rawString)
        return Data(redacted.utf8)
    }

    @MainActor
    public static func exportBackupFile(
        settings: PersistedSettingsPayload,
        store: ConfluenceDataStore,
        appVersion: String
    ) -> URL? {
        let archive = buildArchive(settings: settings, store: store, appVersion: appVersion)
        guard let data = try? encodeRedactedArchiveData(archive) else { return nil }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("Confluence_Backup_v\(archive.schemaVersion).json")
        try? data.write(to: tmp, options: .atomic)
        return tmp
    }

    public static func decodeAndValidateArchive(from data: Data) throws -> ConfluenceBackupArchive {
        let archive: ConfluenceBackupArchive
        do {
            archive = try JSONDecoder().decode(ConfluenceBackupArchive.self, from: data)
        } catch {
            throw BackupArchiveError.invalidJSON(error.localizedDescription)
        }
        guard archive.schemaVersion >= 1 && archive.schemaVersion <= ConfluenceBackupArchive.currentSchemaVersion else {
            throw BackupArchiveError.unsupportedSchemaVersion(archive.schemaVersion)
        }
        guard archive.appBundleId == "com.bilal.confluence" else {
            throw BackupArchiveError.invalidBundleIdentifier(archive.appBundleId)
        }
        return archive
    }

    @MainActor
    public static func restoreArchive(
        from data: Data,
        mode: BackupImportMode,
        settingsStore: AppSettingsStore,
        dataStore: ConfluenceDataStore
    ) throws -> BackupImportSummary {
        let archive = try decodeAndValidateArchive(from: data)

        if mode == .replace {
            dataStore.resetCalibrationAndHistory()
            dataStore.clearJournalEntries()
            if archive.demoWallet != nil {
                dataStore.clearDemoWallet()
            }
        }

        settingsStore.payload = archive.settings

        for sig in archive.signals {
            dataStore.upsertSignal(sig)
        }
        for ledger in archive.tradeLedger {
            dataStore.upsertTradeLedgerSnapshot(ledger)
        }
        for outcome in archive.outcomes {
            dataStore.updateOutcome(outcome)
        }
        for entry in archive.journalEntries {
            dataStore.upsertJournalEntry(entry)
        }
        var restoredWallet = false
        if let wallet = archive.demoWallet {
            dataStore.saveDemoWallet(wallet)
            restoredWallet = true
        }

        return BackupImportSummary(
            signalsImported: archive.signals.count,
            outcomesImported: archive.outcomes.count,
            journalImported: archive.journalEntries.count,
            settingsRestored: true,
            schemaVersion: archive.schemaVersion,
            demoWalletRestored: restoredWallet
        )
    }

    // MARK: - RFC-4180 CSV Exports (SecretRedacted)

    public static func csvEscape(_ field: String) -> String {
        let cleaned = SecretRedactor.redact(field)
        if cleaned.contains(",") || cleaned.contains("\"") || cleaned.contains("\n") || cleaned.contains("\r") {
            let doubled = cleaned.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(doubled)\""
        }
        return cleaned
    }

    public static func buildTradeLedgerCSV(entries: [TradeLedgerSnapshot]) -> String {
        let iso = ISO8601DateFormatter()
        var lines: [String] = [
            "fingerprint,symbol,market,timeframe,direction,entry_low,entry_high,entry_mid,stop_loss,tp1,tp2,score,regime,killzone,provider,status,net_r,created_at,exited_at,strategies"
        ]
        for t in entries {
            let row: [String] = [
                t.fingerprint,
                t.symbol,
                t.marketClass.rawValue,
                t.timeframe.rawValue,
                t.direction.rawValue,
                String(format: "%.6f", t.entryLow),
                String(format: "%.6f", t.entryHigh),
                String(format: "%.6f", t.entryMid),
                String(format: "%.6f", t.stopLoss),
                String(format: "%.6f", t.tp1),
                String(format: "%.6f", t.tp2),
                String(format: "%.1f", t.confidencePercent),
                t.regime.rawValue,
                t.killzone.rawValue,
                t.dataProvider,
                t.status.rawValue,
                String(format: "%.3f", t.netRMultiple),
                iso.string(from: t.createdAt),
                t.exitedAt.map { iso.string(from: $0) } ?? "",
                t.alignedStrategyIDs.joined(separator: ";")
            ]
            lines.append(row.map(csvEscape).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n")
    }

    public static func buildJournalCSV(entries: [JournalEntrySnapshot]) -> String {
        let iso = ISO8601DateFormatter()
        var lines: [String] = [
            "id,signal_fingerprint,symbol,market,timeframe,direction,planned_entry,actual_fill,stop_loss,tp1,tp2,exit_price,position_size,outcome,my_r,system_r,tags,notes,taken_at,closed_at"
        ]
        for j in entries {
            let row: [String] = [
                j.id,
                j.signalFingerprint ?? "",
                j.symbol,
                j.marketClass.rawValue,
                j.timeframe.rawValue,
                j.direction.rawValue,
                String(format: "%.6f", j.plannedEntry),
                j.actualFillPrice.map { String(format: "%.6f", $0) } ?? "",
                String(format: "%.6f", j.stopLoss),
                String(format: "%.6f", j.tp1),
                j.tp2.map { String(format: "%.6f", $0) } ?? "",
                j.exitPrice.map { String(format: "%.6f", $0) } ?? "",
                j.positionSizeText ?? "",
                j.outcome.rawValue,
                j.effectiveRMultiple.map { String(format: "%.3f", $0) } ?? "",
                j.systemRMultiple.map { String(format: "%.3f", $0) } ?? "",
                j.tags.joined(separator: ";"),
                j.notes,
                iso.string(from: j.takenAt),
                j.closedAt.map { iso.string(from: $0) } ?? ""
            ]
            lines.append(row.map(csvEscape).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n")
    }

    public static func buildDemoWalletTransactionsCSV(transactions: [DemoWalletTransaction]) -> String {
        let iso = ISO8601DateFormatter()
        var lines: [String] = [
            "id,timestamp,kind,symbol,position_id,amount_usd,balance_after_usd,note"
        ]
        for tx in transactions {
            let row: [String] = [
                tx.id,
                iso.string(from: Date(timeIntervalSince1970: tx.timestampEpochSeconds)),
                tx.kind.rawValue,
                tx.symbol ?? "",
                tx.positionId ?? "",
                String(format: "%.4f", tx.amountUSD),
                String(format: "%.4f", tx.balanceAfterUSD),
                tx.note
            ]
            lines.append(row.map(csvEscape).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n")
    }

    public static func writeCSVToTemporaryFile(content: String, filename: String) -> URL? {
        let safe = SecretRedactor.redact(content)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try Data(safe.utf8).write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
