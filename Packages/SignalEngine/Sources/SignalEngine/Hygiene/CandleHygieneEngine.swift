import Foundation

public enum SessionCalendar {
    private static var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    public static func killzone(at epochSeconds: TimeInterval) -> KillzoneSession {
        let date = Date(timeIntervalSince1970: epochSeconds)
        let hour = utcCalendar.component(.hour, from: date)
        switch hour {
        case 0..<7:
            return .asian
        case 7..<10:
            return .london
        case 12..<15:
            return .newYork
        case 15..<17:
            return .londonClose
        default:
            return .offSession
        }
    }

    /// Best-effort UTC session check so closed weekend/after-hours markets are marked "Market Closed" rather than "Stale Error".
    public static func isMarketOpen(marketClass: MarketClass, at epochSeconds: TimeInterval) -> Bool {
        if marketClass == .crypto {
            return true
        }
        let date = Date(timeIntervalSince1970: epochSeconds)
        let weekday = utcCalendar.component(.weekday, from: date) // 1 = Sun, 7 = Sat
        let hour = utcCalendar.component(.hour, from: date)

        switch marketClass {
        case .crypto:
            return true
        case .forex, .metals:
            // Forex & spot gold run Sun 22:00 UTC through Fri 22:00 UTC.
            if weekday == 7 { return false }
            if weekday == 1 && hour < 22 { return false }
            if weekday == 6 && hour >= 22 { return false }
            return true
        case .indices, .stocks:
            // US regular + extended session approximation (Mon-Fri 13:30-21:00 UTC).
            if weekday == 1 || weekday == 7 { return false }
            return hour >= 13 && hour < 21
        }
    }
}

public enum CandleHygieneEngine {
    public static let maxAllowedClockSkewSeconds: TimeInterval = 180.0
    public static let minimumRequiredBars: Int = 35

    /// Sanitizes raw candles with strict closed-candle anti-repainting, deduplication,
    /// OTC nil-volume honesty, clock-skew guard, and session-aware staleness checks.
    public static func sanitize(
        rawCandles: [Candle],
        symbol: String,
        marketClass: MarketClass,
        timeframe: Timeframe,
        providerName: String,
        serverNowEpochSeconds: TimeInterval,
        clockSkewSeconds: TimeInterval = 0.0,
        enforceMinimumBars: Bool = true
    ) -> SanitizedCandleSeries {
        var droppedOpen = 0
        var droppedMalformed = 0
        var byOpenTime: [TimeInterval: Candle] = [:]
        var duplicates = 0

        for bar in rawCandles {
            guard bar.open.isFinite, bar.high.isFinite, bar.low.isFinite, bar.close.isFinite,
                  bar.open > 0, bar.high > 0, bar.low > 0, bar.close > 0,
                  bar.high >= max(bar.open, bar.close),
                  bar.low <= min(bar.open, bar.close),
                  bar.closeTimeEpochSeconds > bar.openTimeEpochSeconds
            else {
                droppedMalformed += 1
                continue
            }

            // Strictly causal closed-candle gate: drop forming or future-closing bars.
            if !bar.isClosed || bar.closeTimeEpochSeconds > serverNowEpochSeconds {
                droppedOpen += 1
                continue
            }

            // Enforce honest nil volume on OTC feeds when exchange reports 0 or negative.
            let cleanVolume: Double?
            if let v = bar.volume, v.isFinite {
                if marketClass.isOTCVolumeUnavailable && v <= 0 {
                    cleanVolume = nil
                } else {
                    cleanVolume = max(v, 0.0)
                }
            } else {
                cleanVolume = nil
            }

            let sanitized = Candle(
                openTimeEpochSeconds: bar.openTimeEpochSeconds,
                closeTimeEpochSeconds: bar.closeTimeEpochSeconds,
                open: bar.open,
                high: bar.high,
                low: bar.low,
                close: bar.close,
                volume: cleanVolume,
                isClosed: true
            )

            if byOpenTime[sanitized.openTimeEpochSeconds] != nil {
                duplicates += 1
            }
            byOpenTime[sanitized.openTimeEpochSeconds] = sanitized
        }

        let sorted = byOpenTime.values.sorted { $0.openTimeEpochSeconds < $1.openTimeEpochSeconds }

        var gapCount = 0
        let expectedStep = timeframe.seconds
        if sorted.count >= 2 {
            for idx in 1..<sorted.count {
                let delta = sorted[idx].openTimeEpochSeconds - sorted[idx - 1].openTimeEpochSeconds
                if marketClass.is24x7 && delta > expectedStep * 1.5 {
                    gapCount += 1
                } else if !marketClass.is24x7 && delta > expectedStep * 4.0 && delta < 48 * 3_600 {
                    gapCount += 1
                }
            }
        }

        let isOpenNow = SessionCalendar.isMarketOpen(marketClass: marketClass, at: serverNowEpochSeconds)
        let lastClose = sorted.last?.closeTimeEpochSeconds
        let staleThreshold = max(timeframe.seconds * 2.5, 3_600)
        let age = lastClose.map { serverNowEpochSeconds - $0 } ?? .infinity
        let isStale = isOpenNow && age > staleThreshold

        var rejection: HygieneRejectionReason? = nil
        if abs(clockSkewSeconds) > maxAllowedClockSkewSeconds {
            rejection = .excessiveClockSkew
        } else if enforceMinimumBars && sorted.count < minimumRequiredBars {
            rejection = .insufficientBars
        } else if isStale {
            rejection = .staleFeedDuringOpenSession
        }

        let report = HygieneReport(
            originalCount: rawCandles.count,
            closedCount: sorted.count,
            droppedOpenBars: droppedOpen,
            droppedMalformedBars: droppedMalformed,
            duplicateBarsRemoved: duplicates,
            gapCount: gapCount,
            clockSkewSeconds: clockSkewSeconds,
            isMarketClosed: !isOpenNow,
            isStale: isStale,
            rejectionReason: rejection,
            lastClosedBarEpochSeconds: lastClose
        )

        return SanitizedCandleSeries(
            symbol: symbol,
            marketClass: marketClass,
            timeframe: timeframe,
            providerName: providerName,
            candles: sorted,
            report: report
        )
    }

    /// Causally resamples closed 1H candles into UTC-aligned 4H candles (00:00, 04:00, 08:00, 12:00, 16:00, 20:00 UTC).
    /// Drops any incomplete 4H bucket whose closeTime exceeds `serverNowEpochSeconds`.
    public static func resample1HTo4H(
        hourlyCandles: [Candle],
        serverNowEpochSeconds: TimeInterval
    ) -> [Candle] {
        let bucketSeconds: TimeInterval = Timeframe.h4.seconds
        var buckets: [TimeInterval: [Candle]] = [:]

        for bar in hourlyCandles where bar.isClosed && bar.closeTimeEpochSeconds <= serverNowEpochSeconds {
            let bucketStart = floor(bar.openTimeEpochSeconds / bucketSeconds) * bucketSeconds
            buckets[bucketStart, default: []].append(bar)
        }

        var result: [Candle] = []
        for bucketStart in buckets.keys.sorted() {
            let bucketClose = bucketStart + bucketSeconds
            guard bucketClose <= serverNowEpochSeconds else { continue }
            guard let group = buckets[bucketStart]?.sorted(by: { $0.openTimeEpochSeconds < $1.openTimeEpochSeconds }),
                  let first = group.first,
                  let last = group.last
            else { continue }

            let high = group.map(\.high).max() ?? first.high
            let low = group.map(\.low).min() ?? first.low
            let volumes = group.compactMap(\.volume)
            let totalVolume: Double? = volumes.isEmpty ? nil : volumes.reduce(0, +)

            result.append(
                Candle(
                    openTimeEpochSeconds: bucketStart,
                    closeTimeEpochSeconds: bucketClose,
                    open: first.open,
                    high: high,
                    low: low,
                    close: last.close,
                    volume: totalVolume,
                    isClosed: true
                )
            )
        }
        return result
    }
}
