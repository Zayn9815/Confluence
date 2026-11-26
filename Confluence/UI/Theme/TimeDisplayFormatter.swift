import Foundation
import SignalEngine

public enum TimeDisplayFormatter {
    private static let lock = NSLock()
    private static let utcTimeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    nonisolated(unsafe) private static var cache: [String: DateFormatter] = [:]

    private static func formatter(format: String, useUTC: Bool) -> DateFormatter {
        let tz = useUTC ? utcTimeZone : TimeZone.current
        let key = "\(format)|\(tz.identifier)"
        if let existing = cache[key] {
            return existing
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tz
        f.dateFormat = format
        cache[key] = f
        return f
    }

    public static func formatDateTime(
        epochSeconds: TimeInterval,
        use24Hour: Bool,
        useUTC: Bool
    ) -> String {
        guard epochSeconds.isFinite else { return "—" }
        let fmt = use24Hour ? "MMM d, HH:mm" : "MMM d, h:mm a"
        let suffix = useUTC ? " UTC" : ""
        lock.lock()
        defer { lock.unlock() }
        return formatter(format: fmt, useUTC: useUTC).string(from: Date(timeIntervalSince1970: epochSeconds)) + suffix
    }

    public static func formatShortTime(
        epochSeconds: TimeInterval,
        use24Hour: Bool,
        useUTC: Bool
    ) -> String {
        guard epochSeconds.isFinite else { return "—" }
        let fmt = use24Hour ? "HH:mm" : "h:mm a"
        let suffix = useUTC ? " UTC" : ""
        lock.lock()
        defer { lock.unlock() }
        return formatter(format: fmt, useUTC: useUTC).string(from: Date(timeIntervalSince1970: epochSeconds)) + suffix
    }

    public static func formatCompactStamp(
        epochSeconds: TimeInterval,
        use24Hour: Bool,
        useUTC: Bool
    ) -> String {
        guard epochSeconds.isFinite else { return "—" }
        let fmt = use24Hour ? "MM/dd HH:mm" : "MM/dd h:mm a"
        let suffix = useUTC ? " UTC" : ""
        lock.lock()
        defer { lock.unlock() }
        return formatter(format: fmt, useUTC: useUTC).string(from: Date(timeIntervalSince1970: epochSeconds)) + suffix
    }
}
