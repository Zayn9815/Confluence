import Foundation

public enum SessionCalendar {
    /// DST-correct ICT / Institutional Killzones anchored to `Europe/London` and `America/New_York`:
    /// - London: `07:00..<10:00` `Europe/London` (06:00–09:00 UTC in BST, 07:00–10:00 UTC in GMT)
    /// - New York: `07:00..<10:00` `America/New_York` (11:00–14:00 UTC in EDT, 12:00–15:00 UTC in EST)
    /// - London Close: `10:00..<12:00` `America/New_York` (14:00–16:00 UTC in EDT, 15:00–17:00 UTC in EST)
    /// - Asian: `00:00..<07:00` `UTC` (evaluated after London so `06:00 UTC` during UK BST resolves to `.london`)
    public static func killzone(at epochSeconds: TimeInterval) -> KillzoneSession {
        let date = Date(timeIntervalSince1970: epochSeconds)
        let londonHour = MarketHolidayCalendar.londonCalendar.component(.hour, from: date)
        if (7..<10).contains(londonHour) {
            return .london
        }
        let nyHour = MarketHolidayCalendar.newYorkCalendar.component(.hour, from: date)
        if (7..<10).contains(nyHour) {
            return .newYork
        }
        if (10..<12).contains(nyHour) {
            return .londonClose
        }
        let utcHour = MarketHolidayCalendar.utcCalendar.component(.hour, from: date)
        if (0..<7).contains(utcHour) {
            return .asian
        }
        return .offSession
    }

    /// DST- and holiday-aware session status for a market class.
    public static func sessionStatus(marketClass: MarketClass, at epochSeconds: TimeInterval) -> MarketSessionStatus {
        MarketHolidayCalendar.sessionStatus(marketClass: marketClass, isUSCashEquityETF: false, at: epochSeconds)
    }

    /// Asset-aware DST + holiday session status distinguishing 23/5 futures/CFD indices (`US500`, `NAS100`)
    /// from US cash equity ETFs (`SPY`, `QQQ`) and single stocks (`AAPL`, `NVDA`, `MSFT`).
    public static func sessionStatus(asset: AssetDescriptor, at epochSeconds: TimeInterval) -> MarketSessionStatus {
        let upper = asset.symbol.uppercased()
        let isETF = asset.marketClass == .indices && (upper == "SPY" || upper == "QQQ")
        return MarketHolidayCalendar.sessionStatus(
            marketClass: asset.marketClass,
            isUSCashEquityETF: isETF,
            at: epochSeconds
        )
    }

    /// DST- and holiday-aware open/closed check by market class.
    public static func isMarketOpen(marketClass: MarketClass, at epochSeconds: TimeInterval) -> Bool {
        sessionStatus(marketClass: marketClass, at: epochSeconds).isOpen
    }

    /// Asset-aware DST + holiday open/closed check.
    public static func isMarketOpen(asset: AssetDescriptor, at epochSeconds: TimeInterval) -> Bool {
        sessionStatus(asset: asset, at: epochSeconds).isOpen
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
        enforceMinimumBars: Bool = true,
        asset: AssetDescriptor? = nil
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

        let resolvedAsset = asset ?? WatchlistDefaults.descriptor(for: symbol)
        let sessionStatus: MarketSessionStatus
        if let resolvedAsset {
            sessionStatus = SessionCalendar.sessionStatus(asset: resolvedAsset, at: serverNowEpochSeconds)
        } else {
            sessionStatus = SessionCalendar.sessionStatus(marketClass: marketClass, at: serverNowEpochSeconds)
        }
        let isOpenNow = sessionStatus.isOpen
        let lastClose = sorted.last?.closeTimeEpochSeconds
        let staleThreshold = max(timeframe.seconds * 2.5, 3_600)
        let age = lastClose.map { serverNowEpochSeconds - $0 } ?? .infinity
        let wasOpenAtThresholdStart: Bool = {
            let probeEpoch = serverNowEpochSeconds - staleThreshold
            if let resolvedAsset {
                return SessionCalendar.isMarketOpen(asset: resolvedAsset, at: probeEpoch)
            }
            return SessionCalendar.isMarketOpen(marketClass: marketClass, at: probeEpoch)
        }()
        let isStale = isOpenNow && wasOpenAtThresholdStart && age > staleThreshold

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
            marketClosedReason: sessionStatus.closedReason,
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
        var dedupedByOpen: [TimeInterval: Candle] = [:]
        for bar in hourlyCandles where bar.isClosed && bar.closeTimeEpochSeconds <= serverNowEpochSeconds {
            dedupedByOpen[bar.openTimeEpochSeconds] = bar
        }
        var buckets: [TimeInterval: [Candle]] = [:]
        for bar in dedupedByOpen.values {
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
