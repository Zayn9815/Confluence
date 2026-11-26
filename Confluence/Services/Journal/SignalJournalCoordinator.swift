import Foundation
import Observation
import SignalEngine

public struct JournalLiveTickMetrics: Sendable, Equatable {
    public let price: Double
    public let pnlPercent: Double
    public let rMultiple: Double

    public init(price: Double, pnlPercent: Double, rMultiple: Double) {
        self.price = price
        self.pnlPercent = pnlPercent
        self.rMultiple = rMultiple
    }
}

/// 100% Automatic 3-Section Live Journal Coordinator (`Strong Signals`, `Weak & Filtered`, `Trap Alerts`).
///
/// - **Auto-Capture & Strict Deduplication:** Never duplicates an open trade for `(symbol, timeframe, section, direction)`
///   and never re-captures the same `(symbol, timeframe, section, signalBarTimestamp)`.
/// - **Battery-Safe Live Tracking (Zero Duplicate WebSockets):** Consumes `MarketScannerCoordinator`'s existing
///   `LivePriceService` ticks, coalesced to `<= 2 Hz`, evaluated off `@MainActor`, updating granular per-entry
///   `liveTicksByEntryID` so only tiny leaf number views redraw.
/// - **Gap-Safe Reconciliation:** Walks closed candles on foreground resume and after every scan.
@MainActor
@Observable
public final class SignalJournalCoordinator {
    public static let maxClosedHistoryCount = 500
    private static let tickFlushIntervalNs: UInt64 = 500_000_000 // <= 2 Hz

    private let store: ConfluenceDataStore

    public private(set) var allEntries: [TrackedJournalTrade] = []
    public private(set) var entriesBySection: [JournalSection: [TrackedJournalTrade]] = [
        .strongSignals: [],
        .weakAndFiltered: [],
        .trapAlerts: []
    ]
    public private(set) var liveTicksByEntryID: [String: JournalLiveTickMetrics] = [:]
    public private(set) var sectionStats: [JournalSectionStat] = WinRateBreakdown.byJournalSection(entries: [])

    public var onStatsChanged: (() -> Void)?

    private var pendingQuotesBySymbol: [String: LivePriceQuote] = [:]
    private var tickCoalesceTask: Task<Void, Never>?
    private var lastDiskSyncAt: TimeInterval = 0

    public init(store: ConfluenceDataStore) {
        self.store = store
        loadFromStore()
    }

    public var openTrackedSymbols: [String] {
        Array(Set(allEntries.filter { $0.status.isOpen }.map(\.symbol))).sorted()
    }

    public func entries(for section: JournalSection) -> [TrackedJournalTrade] {
        entriesBySection[section] ?? []
    }

    public func stat(for section: JournalSection) -> JournalSectionStat {
        sectionStats.first { $0.section == section } ?? JournalSectionStat(
            section: section,
            title: section.displayName,
            wins: 0,
            losses: 0,
            liveCount: 0,
            pendingCount: 0,
            expiredCount: 0,
            totalResolved: 0,
            winRate: 0,
            winRateCI: nil,
            averageR: 0
        )
    }

    public func loadFromStore() {
        let loaded = store.loadTrackedJournalEntries()
        applyEntries(loaded)
    }

    /// Automatically captures newly scanned signals and actionable traps into the 3 Journal sections
    /// with strict deduplication and 500-closed-entry history pruning.
    @discardableResult
    public func captureFromScan(
        signals: [TradeSignal],
        traps: [BehavioralTrap],
        candlesBySymbol: [String: [Candle]],
        livePrices: [String: Double],
        timeframe: Timeframe,
        activeProfileKey: String = "",
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> Int {
        var working = allEntries
        var inserted: [TrackedJournalTrade] = []

        func isDuplicate(_ candidate: TrackedJournalTrade) -> Bool {
            for existing in working {
                if existing.id == candidate.id {
                    return true
                }
                if existing.symbol == candidate.symbol &&
                   existing.timeframe == candidate.timeframe &&
                   existing.section == candidate.section {
                    // Rule 1: Skip if ANY entry (open or closed) exists for the same signal bar
                    if abs(existing.signalBarTimestamp - candidate.signalBarTimestamp) < 1.0 {
                        return true
                    }
                    // Rule 2: Skip if an OPEN entry already exists for the same direction
                    if existing.status.isOpen && existing.direction == candidate.direction {
                        return true
                    }
                }
            }
            return false
        }

        // 1. Route scanned TradeSignals -> Strong Signals / Weak & Filtered / Trap Alerts
        for signal in signals {
            let section: JournalSection
            let reason: String?
            switch signal.category {
            case .strongSignal:
                section = .strongSignals
                reason = nil
            case .weakSignal:
                section = .weakAndFiltered
                reason = Self.conciseFilterReason(for: signal)
            case .trapAlert:
                section = .trapAlerts
                reason = signal.trapDirection?.rawValue ?? signal.rejectionReasons.first
            }

            let currentPrice = livePrices[signal.symbol]
                ?? candlesBySymbol[signal.symbol]?.last?.close
                ?? signal.recentCandles.last?.close
                ?? signal.levels?.entryMid
                ?? 0

            if let candidate = SignalJournalEngine.createEntry(
                from: signal,
                section: section,
                currentPrice: currentPrice,
                now: now,
                filterReason: reason
            ), !isDuplicate(candidate) {
                working.insert(candidate, at: 0)
                inserted.append(candidate)
            }
        }

        // 2. Route actionable BehavioralTraps (synthesizing ATR-anchored levels when no trap signal existed)
        let signalOFBySymbol = Dictionary(
            signals.map { ($0.symbol, ($0.orderFlowStatus, $0.orderFlowSummary)) },
            uniquingKeysWith: { first, _ in first }
        )
        for trap in traps where trap.isActionable {
            guard let asset = WatchlistDefaults.descriptor(for: trap.symbol) else { continue }
            let candles = candlesBySymbol[trap.symbol] ?? []
            let atrSeries = TrendMomentumDetector.computeATR(candles: candles, period: 14)
            let atr = atrSeries.last ?? (candles.last?.rangeSize ?? (trap.level * 0.003))
            let currentPrice = livePrices[trap.symbol] ?? candles.last?.close ?? trap.level
            let ofInfo = signalOFBySymbol[trap.symbol]

            if let candidate = SignalJournalEngine.createTrapEntry(
                from: trap,
                asset: asset,
                timeframe: timeframe,
                candles: candles,
                atr: atr,
                currentPrice: currentPrice,
                now: now,
                activeStrategyProfileKey: activeProfileKey,
                orderFlowStatus: ofInfo?.0 ?? "off",
                orderFlowSummary: ofInfo?.1
            ), !isDuplicate(candidate) {
                working.insert(candidate, at: 0)
                inserted.append(candidate)
            }
        }

        guard !inserted.isEmpty else { return 0 }

        store.upsertTrackedJournalEntries(inserted)
        store.pruneClosedJournalEntries(keepingNewest: Self.maxClosedHistoryCount)
        loadFromStore()
        onStatsChanged?()
        return inserted.count
    }

    /// Buffers an incoming live quote from `LivePriceService` and evaluates open trades off `@MainActor`
    /// coalesced to `<= 2 Hz`.
    public func enqueueLiveQuote(_ quote: LivePriceQuote) {
        guard quote.price.isFinite, quote.price > 0 else { return }
        guard allEntries.contains(where: { $0.symbol == quote.symbol && $0.status.isOpen }) else { return }

        pendingQuotesBySymbol[quote.symbol] = quote
        guard tickCoalesceTask == nil else { return }

        tickCoalesceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.tickFlushIntervalNs)
            guard let self, !Task.isCancelled else { return }
            self.tickCoalesceTask = nil
            await self.flushPendingLiveTicks()
        }
    }

    private func flushPendingLiveTicks() async {
        let quotes = pendingQuotesBySymbol
        pendingQuotesBySymbol.removeAll(keepingCapacity: true)
        guard !quotes.isEmpty else { return }

        let openToEval = allEntries.filter { $0.status.isOpen && quotes[$0.symbol] != nil }
        guard !openToEval.isEmpty else { return }

        let updatedBatch: [(original: TrackedJournalTrade, updated: TrackedJournalTrade)] = await Task.detached(priority: .utility) {
            var results: [(TrackedJournalTrade, TrackedJournalTrade)] = []
            results.reserveCapacity(openToEval.count)
            for entry in openToEval {
                guard let quote = quotes[entry.symbol] else { continue }
                let next = SignalJournalEngine.evaluateLiveTick(
                    entry: entry,
                    livePrice: quote.price,
                    now: quote.asOfEpochSeconds
                )
                results.append((entry, next))
            }
            return results
        }.value

        var statusChanged = false
        var entriesNeedingPersist: [TrackedJournalTrade] = []
        var mutatedAll = allEntries
        let indexById = Dictionary(uniqueKeysWithValues: mutatedAll.enumerated().map { ($1.id, $0) })
        let now = Date().timeIntervalSince1970
        let shouldPeriodicDiskSync = (now - lastDiskSyncAt) >= 15.0

        for (orig, next) in updatedBatch {
            let metrics = JournalLiveTickMetrics(
                price: next.currentPrice,
                pnlPercent: next.livePnLPercent,
                rMultiple: next.liveRMultiple
            )
            if liveTicksByEntryID[next.id] != metrics {
                liveTicksByEntryID[next.id] = metrics
            }
            if orig.status != next.status {
                statusChanged = true
                entriesNeedingPersist.append(next)
                if let idx = indexById[next.id] {
                    mutatedAll[idx] = next
                }
            } else if shouldPeriodicDiskSync && orig.currentPrice != next.currentPrice {
                entriesNeedingPersist.append(next)
                if let idx = indexById[next.id] {
                    mutatedAll[idx] = next
                }
            }
        }

        if !entriesNeedingPersist.isEmpty {
            store.upsertTrackedJournalEntries(entriesNeedingPersist)
            if statusChanged {
                store.pruneClosedJournalEntries(keepingNewest: Self.maxClosedHistoryCount)
            }
            lastDiskSyncAt = now
        }

        if statusChanged {
            applyEntries(store.loadTrackedJournalEntries())
            onStatsChanged?()
        } else if !entriesNeedingPersist.isEmpty {
            allEntries = mutatedAll
        }
    }

    /// Reconciles all open entries against closed candles (run on foreground resume and after every scan).
    public func reconcileClosedCandles(
        candlesBySymbol: [String: [Candle]],
        livePrices: [String: Double],
        now: TimeInterval = Date().timeIntervalSince1970
    ) async {
        let openEntries = allEntries.filter { $0.status.isOpen }
        guard !openEntries.isEmpty else { return }

        let reconciled: [TrackedJournalTrade] = await Task.detached(priority: .utility) {
            var changed: [TrackedJournalTrade] = []
            for entry in openEntries {
                let bars = candlesBySymbol[entry.symbol] ?? []
                let liveP = livePrices[entry.symbol]
                let next = SignalJournalEngine.reconcile(
                    entry: entry,
                    againstClosedCandles: bars,
                    livePrice: liveP,
                    now: now
                )
                if next != entry {
                    changed.append(next)
                }
            }
            return changed
        }.value

        guard !reconciled.isEmpty else { return }
        store.upsertTrackedJournalEntries(reconciled)
        store.pruneClosedJournalEntries(keepingNewest: Self.maxClosedHistoryCount)
        loadFromStore()
        onStatsChanged?()
    }

    // MARK: - Private Helpers

    private func applyEntries(_ entries: [TrackedJournalTrade]) {
        let sorted = entries.sorted { $0.createdAt > $1.createdAt }
        self.allEntries = sorted

        var grouped: [JournalSection: [TrackedJournalTrade]] = [
            .strongSignals: [],
            .weakAndFiltered: [],
            .trapAlerts: []
        ]
        var ticks: [String: JournalLiveTickMetrics] = [:]
        ticks.reserveCapacity(sorted.count)
        for item in sorted {
            grouped[item.section, default: []].append(item)
            ticks[item.id] = JournalLiveTickMetrics(
                price: item.currentPrice,
                pnlPercent: item.livePnLPercent,
                rMultiple: item.liveRMultiple
            )
        }
        self.entriesBySection = grouped
        self.liveTicksByEntryID = ticks
        self.sectionStats = WinRateBreakdown.byJournalSection(entries: sorted)
    }

    private static func conciseFilterReason(for signal: TradeSignal) -> String {
        if let first = signal.rejectionReasons.first, !first.isEmpty {
            return first
        }
        if signal.killzone == .offSession {
            return "Off-Session"
        }
        return "Score \(Int(signal.confidencePercent.rounded())) filtered"
    }
}
