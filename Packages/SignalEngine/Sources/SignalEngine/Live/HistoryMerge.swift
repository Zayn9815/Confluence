import Foundation

/// Pure-Swift helper for merging older paginated history bars with existing closed chart candles.
/// Guarantees ascending timestamp order, deduplication by `openTimeEpochSeconds`, strict
/// closed-candle filtering, and a hard bar cap (default 5,000).
public enum HistoryMerge {
    public static let defaultCap: Int = 5_000

    public static func merge(
        existing: [Candle],
        older: [Candle],
        serverNowEpochSeconds: TimeInterval,
        cap: Int = defaultCap
    ) -> [Candle] {
        guard cap > 0 else { return [] }
        var byOpenTime: [TimeInterval: Candle] = [:]
        byOpenTime.reserveCapacity(existing.count + older.count)

        func accept(_ bar: Candle) -> Bool {
            guard bar.isClosed,
                  bar.closeTimeEpochSeconds <= serverNowEpochSeconds,
                  bar.closeTimeEpochSeconds > bar.openTimeEpochSeconds,
                  bar.open.isFinite, bar.high.isFinite, bar.low.isFinite, bar.close.isFinite,
                  bar.open > 0, bar.high > 0, bar.low > 0, bar.close > 0,
                  bar.high >= max(bar.open, bar.close),
                  bar.low <= min(bar.open, bar.close)
            else {
                return false
            }
            return true
        }

        // Insert older first so existing (more recent fetch) wins on duplicate timestamps
        for bar in older where accept(bar) {
            byOpenTime[bar.openTimeEpochSeconds] = bar
        }
        for bar in existing where accept(bar) {
            byOpenTime[bar.openTimeEpochSeconds] = bar
        }

        let sorted = byOpenTime.values.sorted { $0.openTimeEpochSeconds < $1.openTimeEpochSeconds }
        if sorted.count > cap {
            return Array(sorted.suffix(cap))
        }
        return sorted
    }
}
