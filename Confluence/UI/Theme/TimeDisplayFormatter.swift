import Foundation
import SignalEngine

/// Lock-free, Swift 6 `Sendable` date/time formatter using `Date.VerbatimFormatStyle`.
/// Eliminates hot-path `DateFormatter()` allocations on the main thread.
public enum TimeDisplayFormatter {
    private static let posixLocale = Locale(identifier: "en_US_POSIX")
    private static let gregorianCalendar = Calendar(identifier: .gregorian)
    private static let utcTimeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

    private static let dateTime24Format: Date.FormatString = "\(month: .abbreviated) \(day: .defaultDigits), \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)"
    private static let dateTime12Format: Date.FormatString = "\(month: .abbreviated) \(day: .defaultDigits), \(hour: .defaultDigits(clock: .twelveHour, hourCycle: .oneBased)):\(minute: .twoDigits) \(dayPeriod: .standard(.abbreviated))"
    private static let shortTime24Format: Date.FormatString = "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)"
    private static let shortTime12Format: Date.FormatString = "\(hour: .defaultDigits(clock: .twelveHour, hourCycle: .oneBased)):\(minute: .twoDigits) \(dayPeriod: .standard(.abbreviated))"
    private static let compact24Format: Date.FormatString = "\(month: .twoDigits)/\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)"
    private static let compact12Format: Date.FormatString = "\(month: .twoDigits)/\(day: .twoDigits) \(hour: .defaultDigits(clock: .twelveHour, hourCycle: .oneBased)):\(minute: .twoDigits) \(dayPeriod: .standard(.abbreviated))"

    private static func format(
        epochSeconds: TimeInterval,
        formatString: Date.FormatString,
        useUTC: Bool
    ) -> String {
        guard epochSeconds.isFinite else { return "—" }
        let style = Date.VerbatimFormatStyle(
            format: formatString,
            locale: posixLocale,
            timeZone: useUTC ? utcTimeZone : TimeZone.current,
            calendar: gregorianCalendar
        )
        let suffix = useUTC ? " UTC" : ""
        return style.format(Date(timeIntervalSince1970: epochSeconds)) + suffix
    }

    public static func formatDateTime(
        epochSeconds: TimeInterval,
        use24Hour: Bool,
        useUTC: Bool
    ) -> String {
        format(
            epochSeconds: epochSeconds,
            formatString: use24Hour ? dateTime24Format : dateTime12Format,
            useUTC: useUTC
        )
    }

    public static func formatShortTime(
        epochSeconds: TimeInterval,
        use24Hour: Bool,
        useUTC: Bool
    ) -> String {
        format(
            epochSeconds: epochSeconds,
            formatString: use24Hour ? shortTime24Format : shortTime12Format,
            useUTC: useUTC
        )
    }

    public static func formatCompactStamp(
        epochSeconds: TimeInterval,
        use24Hour: Bool,
        useUTC: Bool
    ) -> String {
        format(
            epochSeconds: epochSeconds,
            formatString: use24Hour ? compact24Format : compact12Format,
            useUTC: useUTC
        )
    }
}
