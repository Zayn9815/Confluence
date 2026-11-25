import Foundation

public struct MarketSessionStatus: Codable, Sendable, Equatable, Hashable {
    public let isOpen: Bool
    public let closedReason: String?

    public init(isOpen: Bool, closedReason: String?) {
        self.isOpen = isOpen
        self.closedReason = closedReason
    }

    public static let open = MarketSessionStatus(isOpen: true, closedReason: nil)

    public static func closed(_ reason: String) -> MarketSessionStatus {
        MarketSessionStatus(isOpen: false, closedReason: reason)
    }
}

public enum MarketHolidayKind: String, Codable, Sendable, Equatable {
    case fullClose
    case earlyClose1300ET
}

public struct MarketHolidayEntry: Codable, Sendable, Equatable {
    public let name: String
    public let kind: MarketHolidayKind

    public init(name: String, kind: MarketHolidayKind) {
        self.name = name
        self.kind = kind
    }
}

/// Pure-Swift algorithmic US / Global market holiday and DST-aware session calendar.
/// Anchors US equities, Index CFDs, Metals, and FX rollovers to `America/New_York`
/// and London sessions to `Europe/London` — zero hardcoded year tables.
public enum MarketHolidayCalendar {
    public static var newYorkCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York") ?? TimeZone(secondsFromGMT: -5 * 3600)!
        return cal
    }

    public static var londonCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/London") ?? TimeZone(secondsFromGMT: 0)!
        return cal
    }

    public static var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    // MARK: - Algorithmic Gregorian Easter (Meeus / Jones / Butcher)

    /// Returns Gregorian Easter Sunday `(month, day)` for any year >= 1583.
    public static func gregorianEaster(year: Int) -> (month: Int, day: Int) {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        return (month, day)
    }

    /// Returns Good Friday `(month, day)` (Easter Sunday minus 2 days).
    public static func goodFriday(year: Int) -> (month: Int, day: Int) {
        let easter = gregorianEaster(year: year)
        var comps = DateComponents()
        comps.year = year
        comps.month = easter.month
        comps.day = easter.day
        comps.hour = 12
        let cal = utcCalendar
        guard let easterDate = cal.date(from: comps),
              let gfDate = cal.date(byAdding: .day, value: -2, to: easterDate) else {
            return (easter.month, max(1, easter.day - 2))
        }
        let gf = cal.dateComponents([.month, .day], from: gfDate)
        return (gf.month ?? easter.month, gf.day ?? max(1, easter.day - 2))
    }

    // MARK: - NYSE Holiday & Early-Close Rules

    /// Evaluates NYSE full holidays and 13:00 ET early closes for a calendar date in `America/New_York`.
    public static func nyseHoliday(year: Int, month: Int, day: Int) -> MarketHolidayEntry? {
        let cal = utcCalendar
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        guard let date = cal.date(from: comps) else { return nil }
        let weekday = cal.component(.weekday, from: date) // 1 = Sun, 2 = Mon ... 7 = Sat

        // Weekends are not trading days; only evaluate Mon-Fri for NYSE holiday/early-close rules.
        guard weekday >= 2 && weekday <= 6 else { return nil }

        // 1. New Year's Day (Jan 1 weekday, or Mon Jan 2 if Jan 1 is Sunday; NYSE does NOT close Dec 31 if Jan 1 is Sat)
        if month == 1 && day == 1 {
            return MarketHolidayEntry(name: "New Year's Day", kind: .fullClose)
        }
        if month == 1 && day == 2 && weekday == 2 {
            return MarketHolidayEntry(name: "New Year's Day (Observed)", kind: .fullClose)
        }

        // 2. Martin Luther King Jr. Day: 3rd Monday of January
        if month == 1 && weekday == 2 && (15...21).contains(day) {
            return MarketHolidayEntry(name: "MLK Jr. Day", kind: .fullClose)
        }

        // 3. Presidents' Day (Washington's Birthday): 3rd Monday of February
        if month == 2 && weekday == 2 && (15...21).contains(day) {
            return MarketHolidayEntry(name: "Presidents' Day", kind: .fullClose)
        }

        // 4. Good Friday (Gregorian Easter - 2 days)
        let gf = goodFriday(year: year)
        if month == gf.month && day == gf.day {
            return MarketHolidayEntry(name: "Good Friday", kind: .fullClose)
        }

        // 5. Memorial Day: Last Monday of May (May 25-31)
        if month == 5 && weekday == 2 && (25...31).contains(day) {
            return MarketHolidayEntry(name: "Memorial Day", kind: .fullClose)
        }

        // 6. Juneteenth National Independence Day (June 19 observed: Sat -> Fri 18, Sun -> Mon 20)
        if matchesObservedFixedHoliday(month: month, day: day, weekday: weekday, targetMonth: 6, targetDay: 19) {
            let label = (day == 19) ? "Juneteenth" : "Juneteenth (Observed)"
            return MarketHolidayEntry(name: label, kind: .fullClose)
        }

        // 7. Independence Day (July 4 observed: Sat -> Fri 3, Sun -> Mon 5)
        if matchesObservedFixedHoliday(month: month, day: day, weekday: weekday, targetMonth: 7, targetDay: 4) {
            let label = (day == 4) ? "Independence Day" : "Independence Day (Observed)"
            return MarketHolidayEntry(name: label, kind: .fullClose)
        }

        // 8. Labor Day: 1st Monday of September
        if month == 9 && weekday == 2 && (1...7).contains(day) {
            return MarketHolidayEntry(name: "Labor Day", kind: .fullClose)
        }

        // 9. Thanksgiving Day: 4th Thursday of November (Nov 22-28)
        if month == 11 && weekday == 5 && (22...28).contains(day) {
            return MarketHolidayEntry(name: "Thanksgiving Day", kind: .fullClose)
        }

        // 10. Christmas Day (Dec 25 observed: Sat -> Fri 24, Sun -> Mon 26)
        if matchesObservedFixedHoliday(month: month, day: day, weekday: weekday, targetMonth: 12, targetDay: 25) {
            let label = (day == 25) ? "Christmas Day" : "Christmas Day (Observed)"
            return MarketHolidayEntry(name: label, kind: .fullClose)
        }

        // --- NYSE 13:00 ET Early Closes (checked strictly AFTER full holidays) ---

        // Day before Independence Day (July 3 when Mon-Thu; if Fri, July 4 is Sat and July 3 is already fullClose above)
        if month == 7 && day == 3 && (2...5).contains(weekday) {
            return MarketHolidayEntry(name: "Pre-Independence Day", kind: .earlyClose1300ET)
        }

        // Day after Thanksgiving (Black Friday): Friday immediately after 4th Thursday of November (Nov 23-29)
        if month == 11 && weekday == 6 && (23...29).contains(day) {
            return MarketHolidayEntry(name: "Day After Thanksgiving", kind: .earlyClose1300ET)
        }

        // Christmas Eve (Dec 24 when Mon-Thu; if Fri, Dec 25 is Sat and Dec 24 is already fullClose above)
        if month == 12 && day == 24 && (2...5).contains(weekday) {
            return MarketHolidayEntry(name: "Christmas Eve", kind: .earlyClose1300ET)
        }

        return nil
    }

    private static func matchesObservedFixedHoliday(
        month: Int,
        day: Int,
        weekday: Int,
        targetMonth: Int,
        targetDay: Int
    ) -> Bool {
        guard month == targetMonth else { return false }
        if day == targetDay { return true }
        // Friday observation when target falls on Saturday
        if day == targetDay - 1 && weekday == 6 { return true }
        // Monday observation when target falls on Sunday
        if day == targetDay + 1 && weekday == 2 { return true }
        return false
    }

    // MARK: - Asset-Class Session Status (DST + Holiday Aware)

    public static func sessionStatus(
        marketClass: MarketClass,
        isUSCashEquityETF: Bool = false,
        at epochSeconds: TimeInterval
    ) -> MarketSessionStatus {
        if marketClass == .crypto {
            return .open
        }

        let date = Date(timeIntervalSince1970: epochSeconds)
        let nyCal = newYorkCalendar
        let comps = nyCal.dateComponents([.year, .month, .day, .weekday, .hour, .minute], from: date)
        let year = comps.year ?? 2026
        let month = comps.month ?? 1
        let day = comps.day ?? 1
        let weekday = comps.weekday ?? 2 // 1 = Sun, 7 = Sat
        let hour = comps.hour ?? 0
        let minute = comps.minute ?? 0
        let minutesOfDay = hour * 60 + minute

        let effectiveClass: MarketClass = isUSCashEquityETF ? .stocks : marketClass
        let nyseHol = nyseHoliday(year: year, month: month, day: day)

        switch effectiveClass {
        case .crypto:
            return .open

        case .stocks:
            if weekday == 1 || weekday == 7 {
                return .closed("Weekend")
            }
            if let hol = nyseHol {
                switch hol.kind {
                case .fullClose:
                    return .closed("Holiday · \(hol.name)")
                case .earlyClose1300ET:
                    if minutesOfDay < (9 * 60 + 30) {
                        return .closed("Pre-Market")
                    }
                    if minutesOfDay >= (13 * 60) {
                        return .closed("Early Close · \(hol.name) (13:00 ET)")
                    }
                    return .open
                }
            }
            if minutesOfDay < (9 * 60 + 30) {
                return .closed("Pre-Market")
            }
            if minutesOfDay >= (16 * 60) {
                return .closed("After Hours")
            }
            return .open

        case .indices, .metals:
            // Global Index CFDs (US500, NAS100) & Spot Metals (XAU/USD):
            // Anchored to America/New_York (CME Globex / NY rollover):
            // Weekend close: Fri 17:00 ET -> Sun 18:00 ET; daily rollover: Mon-Thu 17:00-18:00 ET.
            if weekday == 7 {
                return .closed("Weekend")
            }
            if weekday == 1 && hour < 18 {
                return .closed("Weekend")
            }
            if weekday == 6 && hour >= 17 {
                return .closed("Weekend")
            }
            // Major global holiday full closes: Christmas (incl. observed), New Year's Day, Good Friday
            if (month == 12 && day == 25) {
                return .closed("Holiday · Christmas Day")
            }
            if (month == 1 && day == 1) {
                return .closed("Holiday · New Year's Day")
            }
            if let hol = nyseHol {
                if hol.kind == .fullClose && (
                    hol.name == "Good Friday" ||
                    hol.name.hasPrefix("Christmas") ||
                    hol.name.hasPrefix("New Year")
                ) {
                    return .closed("Holiday · \(hol.name)")
                }
                if hol.kind == .earlyClose1300ET && minutesOfDay >= (13 * 60) {
                    return .closed("Early Close · \(hol.name) (13:00 ET)")
                }
            }
            if weekday >= 2 && weekday <= 5 && hour == 17 {
                return .closed("Daily Rollover")
            }
            return .open

        case .forex:
            // Spot FX: Sun 17:00 ET through Fri 17:00 ET (auto-tracks US EST/EDT DST).
            if weekday == 7 {
                return .closed("Weekend")
            }
            if weekday == 1 && hour < 17 {
                return .closed("Weekend")
            }
            if weekday == 6 && hour >= 17 {
                return .closed("Weekend")
            }
            if month == 12 && day == 25 {
                return .closed("Holiday · Christmas Day")
            }
            if month == 1 && day == 1 {
                return .closed("Holiday · New Year's Day")
            }
            return .open
        }
    }
}
