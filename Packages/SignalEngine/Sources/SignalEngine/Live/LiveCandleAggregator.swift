import Foundation

public struct LiveTick: Codable, Sendable, Equatable, Hashable {
    public let price: Double
    public let epochSeconds: TimeInterval
    /// Explicit nil for OTC FX / Gold feeds where exchange volume is unavailable.
    public let volume: Double?

    public init(price: Double, epochSeconds: TimeInterval, volume: Double? = nil) {
        self.price = price
        self.epochSeconds = epochSeconds
        self.volume = volume
    }
}

public enum LiveCandleUpdate: Sendable, Equatable {
    case formingUpdated(Candle)
    case rolledOver(closed: Candle, forming: Candle)
    case rejected(reason: String)
}

/// Pure-Swift causal forming-candle aggregator for display-only live charts.
/// **Hard Invariant:** Forming candles emitted here (`isClosed == false`) are strictly display-only
/// and MUST NEVER be passed to `SignalEngine`, `CandleHygieneEngine`, or `PassiveOutcomeEvaluator`.
public struct LiveCandleAggregator: Sendable, Equatable {
    public let timeframe: Timeframe
    public let maxTickDeviationFraction: Double
    public let isOTCVolumeUnavailable: Bool
    public private(set) var formingCandle: Candle?
    public private(set) var lastValidPrice: Double?
    public private(set) var lastTickEpochSeconds: TimeInterval?
    public private(set) var minAllowedOpenEpochSeconds: TimeInterval?
    private var pendingGapReferencePrice: Double?
    private var pendingGapConfirmCount: Int = 0

    public static func defaultMaxTickDeviation(for marketClass: MarketClass) -> Double {
        switch marketClass {
        case .forex, .metals, .indices:
            return 0.02
        case .stocks:
            return 0.05
        case .crypto:
            return 0.08
        }
    }

    public init(
        timeframe: Timeframe,
        seed: Candle? = nil,
        marketClass: MarketClass = .crypto,
        maxTickDeviationFraction: Double? = nil
    ) {
        self.timeframe = timeframe
        self.isOTCVolumeUnavailable = marketClass.isOTCVolumeUnavailable
        let dev = maxTickDeviationFraction ?? Self.defaultMaxTickDeviation(for: marketClass)
        self.maxTickDeviationFraction = (dev.isFinite && dev > 0) ? dev : Self.defaultMaxTickDeviation(for: marketClass)
        if let seed, seed.close.isFinite, seed.close > 0 {
            self.lastValidPrice = seed.close
            if !seed.isClosed {
                self.formingCandle = seed
                self.minAllowedOpenEpochSeconds = seed.openTimeEpochSeconds
            } else if seed.closeTimeEpochSeconds.isFinite, seed.closeTimeEpochSeconds > 0 {
                // Prevent delayed ticks from spawning a duplicate forming bar for an already-closed seed bucket
                self.minAllowedOpenEpochSeconds = seed.closeTimeEpochSeconds
            }
        }
    }

    /// Computes the UTC bucket open time for a given timestamp and timeframe.
    public static func bucketOpenEpoch(for epochSeconds: TimeInterval, timeframe: Timeframe) -> TimeInterval {
        let step = timeframe.seconds
        return floor(epochSeconds / step) * step
    }

    public mutating func ingest(_ tick: LiveTick) -> LiveCandleUpdate {
        guard tick.price.isFinite, tick.price > 0 else {
            return .rejected(reason: "Non-positive or non-finite tick price")
        }
        guard tick.epochSeconds.isFinite, tick.epochSeconds > 0 else {
            return .rejected(reason: "Invalid tick timestamp")
        }

        if let lastEpoch = lastTickEpochSeconds, tick.epochSeconds < lastEpoch {
            return .rejected(reason: "Out-of-order tick timestamp")
        }

        if let ref = lastValidPrice, ref > 0 {
            let deviation = abs(tick.price - ref) / ref
            if deviation > maxTickDeviationFraction {
                // Require 3 consecutive clustered ticks to confirm a legitimate Sunday/CPI/earnings gap
                // while still rejecting isolated bad-tick spikes.
                if let gapRef = pendingGapReferencePrice, gapRef > 0,
                   abs(tick.price - gapRef) / gapRef <= maxTickDeviationFraction {
                    pendingGapConfirmCount += 1
                    pendingGapReferencePrice = tick.price
                } else {
                    pendingGapReferencePrice = tick.price
                    pendingGapConfirmCount = 1
                }
                if pendingGapConfirmCount < 3 {
                    return .rejected(
                        reason: "Tick deviation \(String(format: "%.2f", deviation * 100))% exceeds guard (\(String(format: "%.2f", maxTickDeviationFraction * 100))%)"
                    )
                }
                // 3-tick gap confirmed: re-anchor reference price cleanly
                pendingGapReferencePrice = nil
                pendingGapConfirmCount = 0
            } else {
                pendingGapReferencePrice = nil
                pendingGapConfirmCount = 0
            }
        }

        let bucketOpen = Self.bucketOpenEpoch(for: tick.epochSeconds, timeframe: timeframe)
        if let minOpen = minAllowedOpenEpochSeconds, bucketOpen < minOpen {
            return .rejected(reason: "Delayed tick falls inside an already-closed candle bucket")
        }
        let bucketClose = bucketOpen + timeframe.seconds
        let sanitizedVol: Double? = {
            if isOTCVolumeUnavailable { return nil }
            guard let v = tick.volume, v.isFinite, v >= 0 else { return nil }
            return v
        }()

        if let current = formingCandle {
            if bucketOpen < current.openTimeEpochSeconds {
                return .rejected(reason: "Out-of-order tick for an earlier candle bucket")
            }

            if bucketOpen == current.openTimeEpochSeconds {
                let updatedVolume: Double?
                if isOTCVolumeUnavailable {
                    updatedVolume = nil
                } else if let curV = current.volume, let addV = sanitizedVol {
                    updatedVolume = curV + addV
                } else {
                    updatedVolume = current.volume ?? sanitizedVol
                }

                let updated = Candle(
                    openTimeEpochSeconds: current.openTimeEpochSeconds,
                    closeTimeEpochSeconds: current.closeTimeEpochSeconds,
                    open: current.open,
                    high: max(current.high, tick.price),
                    low: min(current.low, tick.price),
                    close: tick.price,
                    volume: updatedVolume,
                    isClosed: false
                )
                formingCandle = updated
                lastValidPrice = tick.price
                lastTickEpochSeconds = tick.epochSeconds
                return .formingUpdated(updated)
            } else {
                // Rollover: seal previous forming bar as closed and start new forming bar
                let closed = Candle(
                    openTimeEpochSeconds: current.openTimeEpochSeconds,
                    closeTimeEpochSeconds: current.closeTimeEpochSeconds,
                    open: current.open,
                    high: current.high,
                    low: current.low,
                    close: current.close,
                    volume: current.volume,
                    isClosed: true
                )
                let nextForming = Candle(
                    openTimeEpochSeconds: bucketOpen,
                    closeTimeEpochSeconds: bucketClose,
                    open: tick.price,
                    high: tick.price,
                    low: tick.price,
                    close: tick.price,
                    volume: sanitizedVol,
                    isClosed: false
                )
                formingCandle = nextForming
                lastValidPrice = tick.price
                lastTickEpochSeconds = tick.epochSeconds
                minAllowedOpenEpochSeconds = bucketOpen
                return .rolledOver(closed: closed, forming: nextForming)
            }
        } else {
            let started = Candle(
                openTimeEpochSeconds: bucketOpen,
                closeTimeEpochSeconds: bucketClose,
                open: tick.price,
                high: tick.price,
                low: tick.price,
                close: tick.price,
                volume: sanitizedVol,
                isClosed: false
            )
            formingCandle = started
            lastValidPrice = tick.price
            lastTickEpochSeconds = tick.epochSeconds
            minAllowedOpenEpochSeconds = bucketOpen
            return .formingUpdated(started)
        }
    }
}
