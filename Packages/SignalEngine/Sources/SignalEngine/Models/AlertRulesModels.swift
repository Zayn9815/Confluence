import Foundation

public struct MarketAlertRule: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var allowPush: Bool
    public var allowBanner: Bool
    public var allowSound: Bool
    /// Optional per-market raw score override (`nil` inherits the global `minimumConfidencePercent` gate).
    public var minScoreOverride: Double?

    public init(
        enabled: Bool = true,
        allowPush: Bool = true,
        allowBanner: Bool = true,
        allowSound: Bool = true,
        minScoreOverride: Double? = nil
    ) {
        self.enabled = enabled
        self.allowPush = allowPush
        self.allowBanner = allowBanner
        self.allowSound = allowSound
        self.minScoreOverride = minScoreOverride
    }
}

public struct QuietHoursConfig: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var startHour: Int
    public var startMinute: Int
    public var endHour: Int
    public var endMinute: Int
    /// Gregorian weekday numbers (`1 = Sunday ... 7 = Saturday`).
    public var activeWeekdays: Set<Int>

    public init(
        enabled: Bool = false,
        startHour: Int = 22,
        startMinute: Int = 0,
        endHour: Int = 7,
        endMinute: Int = 0,
        activeWeekdays: Set<Int> = Set(1...7)
    ) {
        self.enabled = enabled
        self.startHour = max(0, min(23, startHour))
        self.startMinute = max(0, min(59, startMinute))
        self.endHour = max(0, min(23, endHour))
        self.endMinute = max(0, min(59, endMinute))
        self.activeWeekdays = activeWeekdays
    }

    public var formattedWindow: String {
        String(format: "%02d:%02d – %02d:%02d", startHour, startMinute, endHour, endMinute)
    }
}

public struct AlertRulesConfig: Codable, Sendable, Equatable {
    public var marketRules: [MarketClass: MarketAlertRule]
    public var allowStrongSignals: Bool
    public var allowTrapAlerts: Bool
    public var allowPreNewsCountdowns: Bool
    public var allowMacroReleases: Bool
    public var quietHours: QuietHoursConfig

    public init(
        marketRules: [MarketClass: MarketAlertRule] = Dictionary(uniqueKeysWithValues: MarketClass.allCases.map { ($0, MarketAlertRule()) }),
        allowStrongSignals: Bool = true,
        allowTrapAlerts: Bool = true,
        allowPreNewsCountdowns: Bool = true,
        allowMacroReleases: Bool = true,
        quietHours: QuietHoursConfig = QuietHoursConfig()
    ) {
        self.marketRules = marketRules
        self.allowStrongSignals = allowStrongSignals
        self.allowTrapAlerts = allowTrapAlerts
        self.allowPreNewsCountdowns = allowPreNewsCountdowns
        self.allowMacroReleases = allowMacroReleases
        self.quietHours = quietHours
    }

    public func rule(for market: MarketClass) -> MarketAlertRule {
        marketRules[market] ?? MarketAlertRule()
    }
}

public struct AlertDeliveryDecision: Sendable, Equatable {
    public let allowPush: Bool
    public let allowBanner: Bool
    public let allowSound: Bool
    public let suppressedReason: String?

    public var allowAnyDelivery: Bool { allowPush || allowBanner || allowSound }

    public static func suppressedAll(_ reason: String) -> AlertDeliveryDecision {
        AlertDeliveryDecision(allowPush: false, allowBanner: false, allowSound: false, suppressedReason: reason)
    }
}

/// Deterministic alert routing & quiet-hours evaluator shared across foreground banners, sounds,
/// local push notifications, and Pre-News scheduling.
public enum AlertRuleEvaluator {
    /// Checks whether `date` falls inside `quietHours` (handling both overnight windows like `22:00–07:00`
    /// and same-day windows like `13:00–15:00`, respecting `activeWeekdays`).
    public static func isInsideQuietHours(
        _ quietHours: QuietHoursConfig,
        at date: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard quietHours.enabled, !quietHours.activeWeekdays.isEmpty else { return false }
        let comps = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        let weekday = comps.weekday ?? 1
        let nowMinutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let startMinutes = quietHours.startHour * 60 + quietHours.startMinute
        let endMinutes = quietHours.endHour * 60 + quietHours.endMinute

        if startMinutes == endMinutes {
            return quietHours.activeWeekdays.contains(weekday)
        }

        if startMinutes < endMinutes {
            // Same-day window (e.g., 13:00 -> 15:00)
            guard quietHours.activeWeekdays.contains(weekday) else { return false }
            return nowMinutes >= startMinutes && nowMinutes < endMinutes
        } else {
            // Overnight window crossing midnight (e.g., 22:00 -> 07:00)
            if nowMinutes >= startMinutes {
                return quietHours.activeWeekdays.contains(weekday)
            }
            if nowMinutes < endMinutes {
                let prevWeekday = (weekday == 1) ? 7 : (weekday - 1)
                return quietHours.activeWeekdays.contains(prevWeekday)
            }
            return false
        }
    }

    public static func evaluateSignalAlert(
        signal: TradeSignal,
        globalMinScore: Double,
        rules: AlertRulesConfig,
        at date: Date = Date(),
        calendar: Calendar = .current
    ) -> AlertDeliveryDecision {
        if isInsideQuietHours(rules.quietHours, at: date, calendar: calendar) {
            return .suppressedAll("Quiet Hours active (\(rules.quietHours.formattedWindow))")
        }

        if signal.category == .strongSignal && !rules.allowStrongSignals {
            return .suppressedAll("Strong Signal alerts disabled")
        }
        if signal.category == .trapAlert && !rules.allowTrapAlerts {
            return .suppressedAll("Trap Alerts disabled")
        }
        if signal.category == .weakSignal {
            return .suppressedAll("Weak / Filtered signals never trigger alerts")
        }

        let marketRule = rules.rule(for: signal.marketClass)
        guard marketRule.enabled else {
            return .suppressedAll("\(signal.marketClass.displayName) alerts muted")
        }

        let floor = marketRule.minScoreOverride ?? globalMinScore
        if signal.category == .strongSignal && signal.confidencePercent + 1e-6 < floor {
            return .suppressedAll("Score \(Int(signal.confidencePercent.rounded())) below \(signal.marketClass.displayName) alert floor \(Int(floor.rounded()))")
        }

        return AlertDeliveryDecision(
            allowPush: marketRule.allowPush,
            allowBanner: marketRule.allowBanner,
            allowSound: marketRule.allowSound,
            suppressedReason: nil
        )
    }

    public static func shouldAllowPreNews(
        rules: AlertRulesConfig,
        at fireDate: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard rules.allowPreNewsCountdowns else { return false }
        return !isInsideQuietHours(rules.quietHours, at: fireDate, calendar: calendar)
    }

    public static func shouldAllowMacroRelease(
        rules: AlertRulesConfig,
        at date: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard rules.allowMacroReleases else { return false }
        return !isInsideQuietHours(rules.quietHours, at: date, calendar: calendar)
    }
}
