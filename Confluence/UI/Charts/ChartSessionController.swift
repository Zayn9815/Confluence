import Foundation
import Observation
import SignalEngine

/// Pure 1 Hz (or configurable interval) redraw throttle for live mini-charts and UI overlays.
public struct LiveChartThrottle: Sendable, Equatable {
    public let minimumIntervalSeconds: TimeInterval
    public private(set) var lastAcceptedEpochSeconds: TimeInterval?

    public init(minimumIntervalSeconds: TimeInterval = 1.0) {
        self.minimumIntervalSeconds = max(0.05, minimumIntervalSeconds)
    }

    public mutating func shouldEmit(at epochSeconds: TimeInterval) -> Bool {
        if let last = lastAcceptedEpochSeconds, (epochSeconds - last) < minimumIntervalSeconds {
            return false
        }
        lastAcceptedEpochSeconds = epochSeconds
        return true
    }

    public mutating func reset() {
        lastAcceptedEpochSeconds = nil
    }
}

/// Pure policy deciding when panning left should request another older page of closed candles.
public enum ChartPagingPolicy {
    public static let triggerBarsBeforeLeftEdge: Double = 40.0
    public static let maxLoadedBars: Int = HistoryMerge.defaultCap

    public static func shouldRequestOlderPage(
        visibleFromLogical: Double,
        currentBarCount: Int,
        isLoadingInitial: Bool,
        isLoadingOlder: Bool,
        hasReachedHistoryEnd: Bool,
        cap: Int = maxLoadedBars
    ) -> Bool {
        guard !isLoadingInitial, !isLoadingOlder, !hasReachedHistoryEnd else { return false }
        guard currentBarCount > 0, currentBarCount < cap else { return false }
        return visibleFromLogical <= triggerBarsBeforeLeftEdge
    }
}

/// Display-only controller for `FullScreenChartSheet` managing closed history, lazy pan-left paging,
/// and live display-only forming candle updates. Forming candles NEVER flow back to `SignalEngine`.
@MainActor
@Observable
public final class ChartSessionController {
    public let symbol: String
    public let marketClass: MarketClass
    public var timeframe: Timeframe

    public private(set) var closedCandles: [Candle]
    public private(set) var formingCandle: Candle?
    public private(set) var isLoadingInitial: Bool = false
    public private(set) var isLoadingOlder: Bool = false
    public private(set) var hasReachedHistoryEnd: Bool = false
    public private(set) var fitRequestToken: Int = 1

    private var aggregator: LiveCandleAggregator

    public init(
        symbol: String,
        marketClass: MarketClass,
        timeframe: Timeframe,
        initialCandles: [Candle]
    ) {
        self.symbol = symbol
        self.marketClass = marketClass
        self.timeframe = timeframe
        let sorted = initialCandles
            .filter(\.isClosed)
            .sorted { $0.openTimeEpochSeconds < $1.openTimeEpochSeconds }
        self.closedCandles = sorted
        self.aggregator = LiveCandleAggregator(
            timeframe: timeframe,
            seed: sorted.last,
            marketClass: marketClass
        )
    }

    public var oldestOpenTimeEpochSeconds: TimeInterval? {
        closedCandles.first?.openTimeEpochSeconds
    }

    public func beginInitialLoad(for newTimeframe: Timeframe) {
        timeframe = newTimeframe
        isLoadingInitial = true
        hasReachedHistoryEnd = false
        formingCandle = nil
    }

    public func finishInitialLoad(candles: [Candle]) {
        let sorted = candles
            .filter(\.isClosed)
            .sorted { $0.openTimeEpochSeconds < $1.openTimeEpochSeconds }
        closedCandles = sorted
        formingCandle = nil
        aggregator = LiveCandleAggregator(
            timeframe: timeframe,
            seed: sorted.last,
            marketClass: marketClass
        )
        isLoadingInitial = false
        hasReachedHistoryEnd = sorted.count < 20
        fitRequestToken += 1
    }

    public func failInitialLoad() {
        isLoadingInitial = false
    }

    public func beginOlderPageLoad() {
        isLoadingOlder = true
    }

    public func finishOlderPageLoad(olderCandles: [Candle], serverNowEpochSeconds: TimeInterval) {
        let beforeCount = closedCandles.count
        let merged = HistoryMerge.merge(
            existing: closedCandles,
            older: olderCandles,
            serverNowEpochSeconds: serverNowEpochSeconds,
            cap: ChartPagingPolicy.maxLoadedBars
        )
        closedCandles = merged
        isLoadingOlder = false
        if merged.count <= beforeCount || merged.count >= ChartPagingPolicy.maxLoadedBars {
            hasReachedHistoryEnd = true
        }
        // Do NOT bump fitRequestToken so user scroll stays intact!
    }

    public func failOlderPageLoad() {
        isLoadingOlder = false
    }

    public func requestResetView() {
        fitRequestToken += 1
    }

    /// Ingests a foreground live quote into the display-only `LiveCandleAggregator`
    /// without bumping `fitRequestToken`.
    @discardableResult
    public func ingestLiveQuote(_ quote: LivePriceQuote) -> Candle? {
        guard quote.symbol == symbol else { return nil }
        let tick = LiveTick(price: quote.price, epochSeconds: quote.asOfEpochSeconds, volume: nil)
        let update = aggregator.ingest(tick)
        switch update {
        case .formingUpdated(let forming):
            formingCandle = forming
            return forming
        case .rolledOver(let closed, let nextForming):
            if let last = closedCandles.last, closed.openTimeEpochSeconds > last.openTimeEpochSeconds {
                closedCandles.append(closed)
                if closedCandles.count > ChartPagingPolicy.maxLoadedBars {
                    closedCandles.removeFirst(closedCandles.count - ChartPagingPolicy.maxLoadedBars)
                }
            }
            formingCandle = nextForming
            return nextForming
        case .rejected:
            return nil
        }
    }

    public func computeScaleResult(levels: TradeLevels?, traps: [BehavioralTrap]) -> ChartScaleResult? {
        let sample = Array(closedCandles.suffix(120))
        return ChartScaleRange.compute(candles: sample, levels: levels, traps: traps)
    }
}
