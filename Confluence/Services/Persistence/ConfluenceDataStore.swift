import Foundation
import SwiftData
import SignalEngine

/// v1.0 persisted signal model — kept top-level and structurally unchanged so existing
/// sideloaded iPhones migrate automatically to v1.1's additive tables with zero data loss.
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
    public static let maxStoredNotifications = 250
    public static let maxStoredLogs = 500
    public static let maxStoredTraps = 300
    public static let maxStoredCrashLogs = 100

    public let container: ModelContainer
    private let context: ModelContext
    public private(set) var didQuarantineCorruptStore: Bool = false

    public init(inMemory: Bool = false, customStoreURL: URL? = nil) {
        let schema = Schema([
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

        let config: ModelConfiguration
        if let url = customStoreURL {
            config = ModelConfiguration(schema: schema, url: url)
        } else {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        }

        do {
            self.container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            if !inMemory {
                // Quarantine corrupted SQLite trio (.store, -wal, -shm) and recreate a clean persistent store
                Self.quarantineStoreFiles(at: config.url)
                self.didQuarantineCorruptStore = true
                if let recovered = try? ModelContainer(for: schema, configurations: [config]) {
                    self.container = recovered
                } else {
                    let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                    self.container = try! ModelContainer(for: schema, configurations: [fallback])
                }
            } else {
                let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                self.container = try! ModelContainer(for: schema, configurations: [fallback])
            }
        }
        self.context = ModelContext(container)
        backfillPersistedOutcomesIfNeeded()
    }

    private func backfillPersistedOutcomesIfNeeded() {
        guard let legacyRows = try? context.fetch(FetchDescriptor<PersistedSignalRecord>()) else { return }
        let existingOutcomeIDs: Set<String> = Set(
            ((try? context.fetch(FetchDescriptor<PersistedOutcomeRecord>())) ?? []).map(\.signalId)
        )
        var insertedAny = false
        for row in legacyRows {
            guard let data = row.outcomeJSON,
                  let decoded = try? JSONDecoder().decode(SignalOutcomeRecord.self, from: data),
                  !existingOutcomeIDs.contains(decoded.signalId)
            else { continue }
            let resolvedDate = decoded.resolvedAtEpochSeconds.map { Date(timeIntervalSince1970: $0) } ?? row.createdAt
            context.insert(PersistedOutcomeRecord(signalId: decoded.signalId, outcomeJSON: data, resolvedAt: resolvedDate))
            insertedAny = true
        }
        if insertedAny {
            try? context.save()
        }
    }

    private static func quarantineStoreFiles(at storeURL: URL) {
        let fm = FileManager.default
        let stamp = Int(Date().timeIntervalSince1970)
        for suffix in ["", "-wal", "-shm"] {
            let src = URL(fileURLWithPath: storeURL.path + suffix)
            if fm.fileExists(atPath: src.path) {
                let dst = URL(fileURLWithPath: storeURL.path + ".quarantine.\(stamp)" + suffix)
                try? fm.moveItem(at: src, to: dst)
            }
        }
    }

    // MARK: - Signals, Permanent Signal Deletion & Decoupled Outcomes

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

        // Also record Strong & Trap setups into the structured Trade Ledger
        if let lv = signal.levels, (signal.category == .strongSignal || signal.category == .trapAlert) {
            upsertTradeLedgerEntry(from: signal, levels: lv)
        }
        try? context.save()
    }

    public func updateOutcome(_ outcome: SignalOutcomeRecord) {
        let fp = outcome.signalId
        guard let encoded = try? JSONEncoder().encode(outcome) else { return }

        // Persist into decoupled PersistedOutcomeRecord (survives signal card deletion!)
        let outcomeDesc = FetchDescriptor<PersistedOutcomeRecord>(
            predicate: #Predicate { $0.signalId == fp }
        )
        let resolvedDate = outcome.resolvedAtEpochSeconds.map { Date(timeIntervalSince1970: $0) } ?? Date()
        if let existingOutcome = try? context.fetch(outcomeDesc).first {
            existingOutcome.outcomeJSON = encoded
            existingOutcome.resolvedAt = resolvedDate
        } else {
            context.insert(PersistedOutcomeRecord(signalId: fp, outcomeJSON: encoded, resolvedAt: resolvedDate))
        }

        // Also mirror onto PersistedSignalRecord if still present
        let descriptor = FetchDescriptor<PersistedSignalRecord>(
            predicate: #Predicate { $0.fingerprint == fp }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.outcomeJSON = encoded
        }

        let ledgerDesc = FetchDescriptor<TradeLedgerEntry>(
            predicate: #Predicate { $0.fingerprint == fp }
        )
        if let ledger = try? context.fetch(ledgerDesc).first {
            switch outcome.status {
            case .hitTP2: ledger.statusRaw = TradeLedgerStatus.tp2Win.rawValue
            case .hitTP1: ledger.statusRaw = TradeLedgerStatus.tp1Win.rawValue
            case .hitSL: ledger.statusRaw = TradeLedgerStatus.slLoss.rawValue
            case .expired: ledger.statusRaw = TradeLedgerStatus.expired.rawValue
            case .notFilled: ledger.statusRaw = TradeLedgerStatus.notFilled.rawValue
            case .invalidated: ledger.statusRaw = TradeLedgerStatus.invalidated.rawValue
            case .open: ledger.statusRaw = TradeLedgerStatus.open.rawValue
            case .pending: ledger.statusRaw = TradeLedgerStatus.pending.rawValue
            }
            ledger.netRMultiple = outcome.rMultiple
            if let ts = outcome.resolvedAtEpochSeconds {
                ledger.exitedAt = Date(timeIntervalSince1970: ts)
            }
        }
        try? context.save()
    }

    /// Permanently deletes a single signal card from the feed WITHOUT removing Calibration Stats or Trade Ledger entries.
    public func deleteSignal(fingerprint: String) {
        let desc = FetchDescriptor<PersistedSignalRecord>(
            predicate: #Predicate { $0.fingerprint == fingerprint }
        )
        if let rows = try? context.fetch(desc) {
            for r in rows { context.delete(r) }
            try? context.save()
        }
    }

    /// Permanently deletes a selected set of signal cards WITHOUT removing Calibration Stats or Trade Ledger entries.
    public func deleteSignals(fingerprints: Set<String>) {
        guard !fingerprints.isEmpty else { return }
        if let rows = try? context.fetch(FetchDescriptor<PersistedSignalRecord>()) {
            for r in rows where fingerprints.contains(r.fingerprint) {
                context.delete(r)
            }
            try? context.save()
        }
    }

    /// Permanently deletes all signal cards in a specific tab category WITHOUT removing Calibration Stats.
    public func deleteSignals(category: SignalCategory) {
        let raw = category.rawValue
        let desc = FetchDescriptor<PersistedSignalRecord>(
            predicate: #Predicate { $0.categoryRaw == raw }
        )
        if let rows = try? context.fetch(desc) {
            for r in rows { context.delete(r) }
            try? context.save()
        }
    }

    /// Permanently clears all signal cards from the Signals feed WITHOUT removing Calibration Stats or Trade Ledger entries.
    public func deleteAllSignals() {
        if let rows = try? context.fetch(FetchDescriptor<PersistedSignalRecord>()) {
            for r in rows { context.delete(r) }
            try? context.save()
        }
    }

    private func upsertTradeLedgerEntry(from signal: TradeSignal, levels: TradeLevels) {
        let fp = signal.fingerprint
        let desc = FetchDescriptor<TradeLedgerEntry>(
            predicate: #Predicate { $0.fingerprint == fp }
        )
        if (try? context.fetch(desc).first) != nil {
            return
        }
        let stratData = (try? JSONEncoder().encode(signal.alignedStrategies.map(\.id))) ?? Data()
        let entry = TradeLedgerEntry(
            fingerprint: fp,
            symbol: signal.symbol,
            marketRaw: signal.marketClass.rawValue,
            timeframeRaw: signal.timeframe.rawValue,
            directionRaw: signal.direction.rawValue,
            entryLow: levels.entryLow,
            entryHigh: levels.entryHigh,
            entryMid: levels.entryMid,
            stopLoss: levels.stopLoss,
            tp1: levels.tp1,
            tp2: levels.tp2,
            confidencePercent: signal.confidencePercent,
            regimeRaw: signal.regime.rawValue,
            killzoneRaw: signal.killzone.rawValue,
            dataProvider: signal.dataProvider,
            alignedStrategyIDsJSON: stratData,
            statusRaw: TradeLedgerStatus.pending.rawValue,
            netRMultiple: 0.0,
            createdAt: Date(timeIntervalSince1970: signal.generatedAtEpochSeconds)
        )
        context.insert(entry)
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
        var bySignalId: [String: SignalOutcomeRecord] = [:]

        // Primary decoupled source (survives signal card deletion)
        let outcomeDesc = FetchDescriptor<PersistedOutcomeRecord>(
            sortBy: [SortDescriptor(\.resolvedAt, order: .reverse)]
        )
        if let outcomeRows = try? context.fetch(outcomeDesc) {
            for row in outcomeRows {
                if let decoded = try? JSONDecoder().decode(SignalOutcomeRecord.self, from: row.outcomeJSON) {
                    bySignalId[decoded.signalId] = decoded
                }
            }
        }

        // Legacy fallback merge
        let legacyDesc = FetchDescriptor<PersistedSignalRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        if let legacyRows = try? context.fetch(legacyDesc) {
            for row in legacyRows {
                guard let data = row.outcomeJSON,
                      let decoded = try? JSONDecoder().decode(SignalOutcomeRecord.self, from: data),
                      bySignalId[decoded.signalId] == nil
                else { continue }
                bySignalId[decoded.signalId] = decoded
            }
        }

        return bySignalId.values.sorted {
            ($0.resolvedAtEpochSeconds ?? 0) > ($1.resolvedAtEpochSeconds ?? 0)
        }
    }

    public func fetchTradeLedger(limit: Int = 300) -> [TradeLedgerSnapshot] {
        var descriptor = FetchDescriptor<TradeLedgerEntry>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        guard let rows = try? context.fetch(descriptor) else { return [] }
        return rows.map { $0.toSnapshot() }
    }

    public func recentDeduplicationHistory() -> [(fingerprint: String, symbol: String, direction: TradeDirection, epochSeconds: TimeInterval)] {
        fetchSignals(limit: 100).map { sig in
            (sig.fingerprint, sig.symbol, sig.direction, sig.generatedAtEpochSeconds)
        }
    }

    // MARK: - Stored Notification Inbox (Latest 250)

    @discardableResult
    public func saveNotification(_ item: NotificationItemSnapshot) -> Bool {
        let targetId = item.id
        let desc = FetchDescriptor<StoredNotificationItem>(
            predicate: #Predicate { $0.id == targetId }
        )
        if (try? context.fetch(desc).first) != nil {
            return false // Deduplicated
        }

        let model = StoredNotificationItem(
            id: item.id,
            createdAt: item.createdAt,
            typeRaw: item.type.rawValue,
            title: item.title,
            subtitle: item.subtitle,
            symbol: item.symbol,
            marketRaw: item.marketClass?.rawValue,
            timeframeRaw: item.timeframe?.rawValue,
            directionRaw: item.direction?.rawValue,
            confidence: item.confidence,
            signalFingerprint: item.signalFingerprint,
            eventID: item.eventID,
            isRead: item.isRead
        )
        context.insert(model)
        pruneNotificationsIfNeeded()
        try? context.save()
        return true
    }

    public func fetchNotifications(limit: Int = maxStoredNotifications) -> [NotificationItemSnapshot] {
        var desc = FetchDescriptor<StoredNotificationItem>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        desc.fetchLimit = limit
        guard let rows = try? context.fetch(desc) else { return [] }
        return rows.map { $0.toSnapshot() }
    }

    public func unreadNotificationCount() -> Int {
        let desc = FetchDescriptor<StoredNotificationItem>(
            predicate: #Predicate { $0.isRead == false }
        )
        return (try? context.fetchCount(desc)) ?? 0
    }

    public func markNotificationRead(id: String, read: Bool = true) {
        let desc = FetchDescriptor<StoredNotificationItem>(
            predicate: #Predicate { $0.id == id }
        )
        if let row = try? context.fetch(desc).first {
            row.isRead = read
            try? context.save()
        }
    }

    public func markAllNotificationsRead() {
        let desc = FetchDescriptor<StoredNotificationItem>(
            predicate: #Predicate { $0.isRead == false }
        )
        if let rows = try? context.fetch(desc) {
            for r in rows { r.isRead = true }
            try? context.save()
        }
    }

    public func deleteNotification(id: String) {
        let desc = FetchDescriptor<StoredNotificationItem>(
            predicate: #Predicate { $0.id == id }
        )
        if let row = try? context.fetch(desc).first {
            context.delete(row)
            try? context.save()
        }
    }

    public func clearAllNotifications() {
        let desc = FetchDescriptor<StoredNotificationItem>()
        if let rows = try? context.fetch(desc) {
            for r in rows { context.delete(r) }
            try? context.save()
        }
    }

    private func pruneNotificationsIfNeeded() {
        let desc = FetchDescriptor<StoredNotificationItem>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        guard let all = try? context.fetch(desc), all.count > Self.maxStoredNotifications else { return }
        for stale in all.dropFirst(Self.maxStoredNotifications) {
            context.delete(stale)
        }
    }

    // MARK: - Diagnostic Runtime Logs (500-Entry Ring Buffer)

    public func appendDiagnosticLog(_ entry: DiagnosticLogSnapshot) {
        let model = DiagnosticLogEntry(
            id: entry.id,
            timestamp: entry.timestamp,
            severityRaw: entry.severity.rawValue,
            categoryRaw: entry.category.rawValue,
            message: entry.message,
            detail: entry.detail
        )
        context.insert(model)
        pruneLogsIfNeeded()
        try? context.save()
    }

    public func fetchDiagnosticLogs(limit: Int = maxStoredLogs) -> [DiagnosticLogSnapshot] {
        var desc = FetchDescriptor<DiagnosticLogEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        desc.fetchLimit = limit
        guard let rows = try? context.fetch(desc) else { return [] }
        return rows.map { $0.toSnapshot() }
    }

    public func clearDiagnosticLogs() {
        let desc = FetchDescriptor<DiagnosticLogEntry>()
        if let rows = try? context.fetch(desc) {
            for r in rows { context.delete(r) }
            try? context.save()
        }
    }

    private func pruneLogsIfNeeded() {
        let desc = FetchDescriptor<DiagnosticLogEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        guard let all = try? context.fetch(desc), all.count > Self.maxStoredLogs else { return }
        for stale in all.dropFirst(Self.maxStoredLogs) {
            context.delete(stale)
        }
    }

    // MARK: - Trap Lifecycle Logs

    public func upsertTrapLog(
        trap: BehavioralTrap,
        timeframe: Timeframe,
        positioningContext: String,
        postTrapOutcome: TrapRespectOutcome? = nil
    ) {
        let key = "\(trap.symbol)|\(timeframe.rawValue)|\(trap.direction.rawValue)|\(Int(trap.triggerEpochSeconds))"
        let desc = FetchDescriptor<TrapLogEntry>(
            predicate: #Predicate { $0.trapKey == key }
        )
        let now = Date()
        if let existing = try? context.fetch(desc).first {
            existing.currentStateRaw = trap.state.rawValue
            if trap.state == .active && existing.activatedAt == nil { existing.activatedAt = now }
            if trap.state == .returned && existing.returnedAt == nil { existing.returnedAt = now }
            if trap.state == .invalid && existing.invalidatedAt == nil { existing.invalidatedAt = now }
            if let outcome = postTrapOutcome {
                existing.postTrapOutcomeRaw = outcome.rawValue
            }
        } else {
            let entry = TrapLogEntry(
                trapKey: key,
                symbol: trap.symbol,
                timeframeRaw: timeframe.rawValue,
                directionRaw: trap.direction.rawValue,
                triggerKindRaw: trap.triggerKind.rawValue,
                priceLevel: trap.level,
                positioningContext: positioningContext,
                triggeredAt: Date(timeIntervalSince1970: trap.triggerEpochSeconds),
                activatedAt: trap.state != .trigger ? now : nil,
                returnedAt: trap.state == .returned ? now : nil,
                invalidatedAt: trap.state == .invalid ? now : nil,
                currentStateRaw: trap.state.rawValue,
                postTrapOutcomeRaw: (postTrapOutcome ?? .pending).rawValue
            )
            context.insert(entry)
            pruneTrapLogsIfNeeded()
        }
        try? context.save()
    }

    public func fetchTrapLogs(limit: Int = maxStoredTraps) -> [TrapLogSnapshot] {
        var desc = FetchDescriptor<TrapLogEntry>(
            sortBy: [SortDescriptor(\.triggeredAt, order: .reverse)]
        )
        desc.fetchLimit = limit
        guard let rows = try? context.fetch(desc) else { return [] }
        return rows.map { $0.toSnapshot() }
    }

    private func pruneTrapLogsIfNeeded() {
        let desc = FetchDescriptor<TrapLogEntry>(
            sortBy: [SortDescriptor(\.triggeredAt, order: .reverse)]
        )
        guard let all = try? context.fetch(desc), all.count > Self.maxStoredTraps else { return }
        for stale in all.dropFirst(Self.maxStoredTraps) {
            context.delete(stale)
        }
    }

    // MARK: - Trade Replay Candle Cache & Signal Lookups

    public static let maxReplayCaches = 200

    public func fetchSignal(fingerprint: String) -> TradeSignal? {
        let desc = FetchDescriptor<PersistedSignalRecord>(
            predicate: #Predicate { $0.fingerprint == fingerprint }
        )
        guard let row = try? context.fetch(desc).first else { return nil }
        return try? JSONDecoder().decode(TradeSignal.self, from: row.signalJSON)
    }

    public func fetchSignalsByFingerprint(limit: Int = 500) -> [String: TradeSignal] {
        let all = fetchSignals(limit: limit)
        var map: [String: TradeSignal] = [:]
        map.reserveCapacity(all.count)
        for s in all {
            map[s.fingerprint] = s
        }
        return map
    }

    public func saveReplayCandles(
        fingerprint: String,
        symbol: String,
        timeframe: Timeframe,
        providerName: String,
        candles: [Candle]
    ) {
        let merged = Self.deduplicateAndSortCandles(candles)
        guard !merged.isEmpty, let encoded = try? JSONEncoder().encode(merged) else { return }
        let desc = FetchDescriptor<TradeReplayCandleCache>(
            predicate: #Predicate { $0.fingerprint == fingerprint }
        )
        if let existing = try? context.fetch(desc).first {
            existing.candlesJSON = encoded
            existing.providerName = providerName
            existing.updatedAt = Date()
        } else {
            let row = TradeReplayCandleCache(
                fingerprint: fingerprint,
                symbol: symbol,
                timeframeRaw: timeframe.rawValue,
                providerName: providerName,
                candlesJSON: encoded
            )
            context.insert(row)
            pruneReplayCachesIfNeeded()
        }
        try? context.save()
    }

    public func fetchReplayCandles(fingerprint: String) -> (candles: [Candle], providerName: String)? {
        let desc = FetchDescriptor<TradeReplayCandleCache>(
            predicate: #Predicate { $0.fingerprint == fingerprint }
        )
        guard let row = try? context.fetch(desc).first,
              let decoded = try? JSONDecoder().decode([Candle].self, from: row.candlesJSON),
              !decoded.isEmpty
        else { return nil }
        return (Self.deduplicateAndSortCandles(decoded), row.providerName)
    }

    private func pruneReplayCachesIfNeeded() {
        let desc = FetchDescriptor<TradeReplayCandleCache>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        guard let all = try? context.fetch(desc), all.count > Self.maxReplayCaches else { return }
        for stale in all.dropFirst(Self.maxReplayCaches) {
            context.delete(stale)
        }
    }

    public static func deduplicateAndSortCandles(_ candles: [Candle]) -> [Candle] {
        var byOpen: [Int: Candle] = [:]
        for bar in candles where bar.isClosed {
            let key = Int(bar.openTimeEpochSeconds.rounded())
            byOpen[key] = bar
        }
        return byOpen.values.sorted { $0.openTimeEpochSeconds < $1.openTimeEpochSeconds }
    }

    // MARK: - Native Crash Logs (Latest 100)

    @discardableResult
    public func saveCrashLog(_ snapshot: CrashLogSnapshot) -> Bool {
        let targetId = snapshot.id
        let desc = FetchDescriptor<CrashLogEntry>(
            predicate: #Predicate { $0.id == targetId }
        )
        if (try? context.fetch(desc).first) != nil {
            return false // Already stored
        }
        let row = CrashLogEntry(
            id: snapshot.id,
            timestamp: snapshot.timestamp,
            sourceRaw: snapshot.source.rawValue,
            appVersion: snapshot.appVersion,
            appBuild: snapshot.appBuild,
            crashType: snapshot.crashType,
            summary: snapshot.summary,
            stackTrace: snapshot.stackTrace
        )
        context.insert(row)
        pruneCrashLogsIfNeeded()
        try? context.save()
        return true
    }

    public func fetchCrashLogs(limit: Int = maxStoredCrashLogs) -> [CrashLogSnapshot] {
        var desc = FetchDescriptor<CrashLogEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        desc.fetchLimit = limit
        guard let rows = try? context.fetch(desc) else { return [] }
        return rows.map { $0.toSnapshot() }
    }

    public func clearCrashLogs() {
        if let rows = try? context.fetch(FetchDescriptor<CrashLogEntry>()) {
            for r in rows { context.delete(r) }
            try? context.save()
        }
    }

    private func pruneCrashLogsIfNeeded() {
        let desc = FetchDescriptor<CrashLogEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        guard let all = try? context.fetch(desc), all.count > Self.maxStoredCrashLogs else { return }
        for stale in all.dropFirst(Self.maxStoredCrashLogs) {
            context.delete(stale)
        }
    }

    // MARK: - Trade Journal (v1.4 Purely Additive 9th Table)

    public func upsertJournalEntry(_ snapshot: JournalEntrySnapshot) {
        let targetId = snapshot.id
        let stratData = (try? JSONEncoder().encode(snapshot.strategyIDs)) ?? Data()
        let tagsData = (try? JSONEncoder().encode(snapshot.tags)) ?? Data()
        let desc = FetchDescriptor<JournalEntry>(
            predicate: #Predicate { $0.id == targetId }
        )
        if let existing = try? context.fetch(desc).first {
            existing.signalFingerprint = snapshot.signalFingerprint
            existing.symbol = snapshot.symbol
            existing.marketRaw = snapshot.marketClass.rawValue
            existing.timeframeRaw = snapshot.timeframe.rawValue
            existing.directionRaw = snapshot.direction.rawValue
            existing.plannedEntry = snapshot.plannedEntry
            existing.actualFillPrice = snapshot.actualFillPrice
            existing.stopLoss = snapshot.stopLoss
            existing.tp1 = snapshot.tp1
            existing.tp2 = snapshot.tp2
            existing.exitPrice = snapshot.exitPrice
            existing.positionSizeText = snapshot.positionSizeText
            existing.outcomeRaw = snapshot.outcome.rawValue
            existing.actualRMultiple = snapshot.actualRMultiple
            existing.systemRMultiple = snapshot.systemRMultiple
            existing.strategyIDsJSON = stratData
            existing.tagsJSON = tagsData
            existing.notes = snapshot.notes
            existing.takenAt = snapshot.takenAt
            existing.closedAt = snapshot.closedAt
        } else {
            let row = JournalEntry(
                id: snapshot.id,
                signalFingerprint: snapshot.signalFingerprint,
                symbol: snapshot.symbol,
                marketRaw: snapshot.marketClass.rawValue,
                timeframeRaw: snapshot.timeframe.rawValue,
                directionRaw: snapshot.direction.rawValue,
                plannedEntry: snapshot.plannedEntry,
                actualFillPrice: snapshot.actualFillPrice,
                stopLoss: snapshot.stopLoss,
                tp1: snapshot.tp1,
                tp2: snapshot.tp2,
                exitPrice: snapshot.exitPrice,
                positionSizeText: snapshot.positionSizeText,
                outcomeRaw: snapshot.outcome.rawValue,
                actualRMultiple: snapshot.actualRMultiple,
                systemRMultiple: snapshot.systemRMultiple,
                strategyIDsJSON: stratData,
                tagsJSON: tagsData,
                notes: snapshot.notes,
                takenAt: snapshot.takenAt,
                closedAt: snapshot.closedAt
            )
            context.insert(row)
        }
        try? context.save()
    }

    public func fetchJournalEntries(limit: Int = 500) -> [JournalEntrySnapshot] {
        var desc = FetchDescriptor<JournalEntry>(
            sortBy: [SortDescriptor(\.takenAt, order: .reverse)]
        )
        desc.fetchLimit = limit
        guard let rows = try? context.fetch(desc) else { return [] }
        return rows.map { $0.toSnapshot() }
    }

    public func journalEntry(forSignalFingerprint fp: String) -> JournalEntrySnapshot? {
        let targetFP: String? = fp
        let desc = FetchDescriptor<JournalEntry>(
            predicate: #Predicate { $0.signalFingerprint == targetFP }
        )
        return (try? context.fetch(desc).first)?.toSnapshot()
    }

    public func deleteJournalEntry(id: String) {
        let desc = FetchDescriptor<JournalEntry>(
            predicate: #Predicate { $0.id == id }
        )
        if let rows = try? context.fetch(desc) {
            for r in rows { context.delete(r) }
            try? context.save()
        }
    }

    public func clearJournalEntries() {
        if let rows = try? context.fetch(FetchDescriptor<JournalEntry>()) {
            for r in rows { context.delete(r) }
            try? context.save()
        }
    }

    // MARK: - Reset & Export

    public func resetCalibrationAndHistory() {
        if let rows = try? context.fetch(FetchDescriptor<PersistedSignalRecord>()) {
            for r in rows { context.delete(r) }
        }
        if let rows = try? context.fetch(FetchDescriptor<PersistedOutcomeRecord>()) {
            for r in rows { context.delete(r) }
        }
        if let rows = try? context.fetch(FetchDescriptor<TradeLedgerEntry>()) {
            for r in rows { context.delete(r) }
        }
        if let rows = try? context.fetch(FetchDescriptor<TrapLogEntry>()) {
            for r in rows { context.delete(r) }
        }
        if let rows = try? context.fetch(FetchDescriptor<DiagnosticLogEntry>()) {
            for r in rows { context.delete(r) }
        }
        if let rows = try? context.fetch(FetchDescriptor<TradeReplayCandleCache>()) {
            for r in rows { context.delete(r) }
        }
        try? context.save()
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
        let summary = PassiveOutcomeEvaluator.summarize(records: outcomes, filter: .headlineFixed)
        let bundle = CalibrationExportBundle(
            exportedAtISO8601: ISO8601DateFormatter().string(from: Date()),
            appBundleId: "com.bilal.confluence",
            calibrationSummary: summary,
            signals: signals,
            outcomes: outcomes
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let raw = try? encoder.encode(bundle),
              let rawStr = String(data: raw, encoding: .utf8) else { return nil }
        let safe = SecretRedactor.redact(rawStr)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("Confluence_Calibration_Export.json")
        try? Data(safe.utf8).write(to: tmp, options: .atomic)
        return tmp
    }
}
