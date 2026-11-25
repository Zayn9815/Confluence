import Foundation
import SignalEngine

public enum TimeDisplayFormatter {
    public static func formatDateTime(
        epochSeconds: TimeInterval,
        use24Hour: Bool,
        useUTC: Bool
    ) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = useUTC ? TimeZone(secondsFromGMT: 0) : TimeZone.current
        f.dateFormat = use24Hour ? "MMM d, HH:mm" : "MMM d, h:mm a"
        let suffix = useUTC ? " UTC" : ""
        return f.string(from: Date(timeIntervalSince1970: epochSeconds)) + suffix
    }

    public static func formatShortTime(
        epochSeconds: TimeInterval,
        use24Hour: Bool,
        useUTC: Bool
    ) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = useUTC ? TimeZone(secondsFromGMT: 0) : TimeZone.current
        f.dateFormat = use24Hour ? "HH:mm" : "h:mm a"
        let suffix = useUTC ? " UTC" : ""
        return f.string(from: Date(timeIntervalSince1970: epochSeconds)) + suffix
    }

    public static func formatCompactStamp(
        epochSeconds: TimeInterval,
        use24Hour: Bool,
        useUTC: Bool
    ) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = useUTC ? TimeZone(secondsFromGMT: 0) : TimeZone.current
        f.dateFormat = use24Hour ? "MM/dd HH:mm" : "MM/dd h:mm a"
        let suffix = useUTC ? " UTC" : ""
        return f.string(from: Date(timeIntervalSince1970: epochSeconds)) + suffix
    }
}
