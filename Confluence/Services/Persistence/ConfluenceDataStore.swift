import Foundation
import SwiftData
import SignalEngine

@Model
public final class PersistedSignalRecord {
    @Attribute(.unique) public var fingerprint: String
    public var symbol: String
    public var directionRaw: String
    public var categoryRaw: String
    public var createdAt: Date
    public var signalJSON: Data
    public var outcomeJSON: Data?

    public init(
        fingerprint: String,
        symbol: String,
        directionRaw: String,
        categoryRaw: String,
        createdAt: Date,
        signalJSON: Data,
        outcomeJSON: Data? = nil
    ) {
        self.fingerprint = fingerprint
        self.symbol = symbol
        self.directionRaw = directionRaw
        self.categoryRaw = categoryRaw
        self.createdAt = createdAt
        self.signalJSON = signalJSON
        self.outcomeJSON = outcomeJSON
    }
}

public struct CalibrationExportBundle: Codable, Sendable {
    public let exportedAtISO8601: String
    public let appBundleId: String
    public let calibrationSummary: CalibrationSummary
    public let signals: [TradeSignal]
    public let outcomes: [SignalOutcomeRecord]
}

@MainActor
public final class ConfluenceDataStore {
    public let container: ModelContainer
    private let context: ModelContext

    public init(inMemory: Bool = false) {
        let schema = Schema([PersistedSignalRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            self.container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Safe fallback to in-memory store if container migration fails
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            self.container = try! ModelContainer(for: schema, configurations: [fallback])
        }
        self.context = ModelContext(container)
    }

    public func upsertSignal(_ signal: TradeSignal) {
        guard let encoded = try? JSONEncoder().encode(signal) else { return }
        let fp = signal.fingerprint
        let descriptor = FetchDescriptor<PersistedSignalRecord>(
            predicate: #Predicate { $0.fingerprint == fp }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.signalJSON = encoded
        } else {
            let record = PersistedSignalRecord(
                fingerprint: fp,
                symbol: signal.symbol,
                directionRaw: signal.direction.rawValue,
                categoryRaw: signal.category.rawValue,
                createdAt: Date(timeIntervalSince1970: signal.generatedAtEpochSeconds),
                signalJSON: encoded
            )
            context.insert(record)
        }
        try? context.save()
    }

    public func updateOutcome(_ outcome: SignalOutcomeRecord) {
        let fp = outcome.signalId
        guard let encoded = try? JSONEncoder().encode(outcome) else { return }
        let descriptor = FetchDescriptor<PersistedSignalRecord>(
            predicate: #Predicate { $0.fingerprint == fp }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.outcomeJSON = encoded
            try? context.save()
        }
    }

    public func fetchSignals(limit: Int = 200) -> [TradeSignal] {
        var descriptor = FetchDescriptor<PersistedSignalRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        guard let rows = try? context.fetch(descriptor) else { return [] }
        return rows.compactMap { try? JSONDecoder().decode(TradeSignal.self, from: $0.signalJSON) }
    }

    public func fetchOutcomeRecords() -> [SignalOutcomeRecord] {
        let descriptor = FetchDescriptor<PersistedSignalRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        guard let rows = try? context.fetch(descriptor) else { return [] }
        return rows.compactMap { row -> SignalOutcomeRecord? in
            guard let data = row.outcomeJSON else { return nil }
            return try? JSONDecoder().decode(SignalOutcomeRecord.self, from: data)
        }
    }

    public func recentDeduplicationHistory() -> [(fingerprint: String, symbol: String, direction: TradeDirection, epochSeconds: TimeInterval)] {
        fetchSignals(limit: 100).map { sig in
            (sig.fingerprint, sig.symbol, sig.direction, sig.generatedAtEpochSeconds)
        }
    }

    public func resetCalibrationAndHistory() {
        let descriptor = FetchDescriptor<PersistedSignalRecord>()
        if let rows = try? context.fetch(descriptor) {
            for r in rows { context.delete(r) }
            try? context.save()
        }
        clearDiskCaches()
    }

    public func clearDiskCaches() {
        guard let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let targets = [
            "confluence_cftc_cot_cache.json",
            "confluence_ff_calendar_cache.json"
        ]
        for file in targets {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(file))
        }
    }

    public func exportCalibrationJSON() -> URL? {
        let signals = fetchSignals(limit: 500)
        let outcomes = fetchOutcomeRecords()
        let summary = PassiveOutcomeEvaluator.summarize(records: outcomes)
        let bundle = CalibrationExportBundle(
            exportedAtISO8601: ISO8601DateFormatter().string(from: Date()),
            appBundleId: "com.bilal.confluence",
            calibrationSummary: summary,
            signals: signals,
            outcomes: outcomes
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(bundle) else { return nil }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("Confluence_Calibration_Export.json")
        try? data.write(to: tmp, options: .atomic)
        return tmp
    }
}
