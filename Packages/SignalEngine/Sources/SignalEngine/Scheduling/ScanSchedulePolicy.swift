import Foundation

public enum ScanIntervalOption: Int, Codable, Sendable, CaseIterable, Identifiable {
    case off = 0
    case every5Minutes = 5
    case every15Minutes = 15
    case every30Minutes = 30
    case every60Minutes = 60

    public var id: Int { rawValue }

    public var displayLabel: String {
        switch self {
        case .off: return "Off"
        case .every5Minutes: return "Every 5 minutes"
        case .every15Minutes: return "Every 15 minutes"
        case .every30Minutes: return "Every 30 minutes (Recommended)"
        case .every60Minutes: return "Every 60 minutes"
        }
    }
}

public struct ScanUsageEstimate: Codable, Sendable, Equatable {
    public let scansPerDay: Int
    public let estimatedRequestsPerDay: Int
    public let effectiveIntervalMinutes: Int
    public let lowPowerClamped: Bool
    public let summaryText: String

    public init(
        scansPerDay: Int,
        estimatedRequestsPerDay: Int,
        effectiveIntervalMinutes: Int,
        lowPowerClamped: Bool,
        summaryText: String
    ) {
        self.scansPerDay = scansPerDay
        self.estimatedRequestsPerDay = estimatedRequestsPerDay
        self.effectiveIntervalMinutes = effectiveIntervalMinutes
        self.lowPowerClamped = lowPowerClamped
        self.summaryText = summaryText
    }
}

/// Deterministic foreground scan-on-open & periodic auto-scan scheduler policy.
public enum ScanSchedulePolicy {
    public static let defaultIntervalMinutes: Int = 30
    public static let minimumScanGapSeconds: TimeInterval = 120.0
    public static let lowPowerMinimumIntervalMinutes: Int = 30

    /// Returns effective auto-scan interval in minutes (`0` means disabled).
    /// Low Power Mode enforces a minimum 30-minute interval when auto-scan is enabled.
    public static func effectiveIntervalMinutes(
        configuredMinutes: Int,
        isLowPowerMode: Bool
    ) -> Int {
        guard configuredMinutes > 0 else { return 0 }
        if isLowPowerMode {
            return max(configuredMinutes, lowPowerMinimumIntervalMinutes)
        }
        return configuredMinutes
    }

    /// Returns true if opening the app should trigger a fresh scan (honoring the 2-minute anti-spam gap).
    public static func shouldScanOnOpen(
        enabled: Bool,
        lastScanEpochSeconds: TimeInterval?,
        nowEpochSeconds: TimeInterval,
        minimumGapSeconds: TimeInterval = minimumScanGapSeconds
    ) -> Bool {
        guard enabled else { return false }
        guard let last = lastScanEpochSeconds else { return true }
        let elapsed = nowEpochSeconds - last
        return elapsed >= max(0, minimumGapSeconds)
    }

    /// Returns epoch timestamp for the next scheduled foreground scan, or `nil` when off.
    public static func nextScanEpochSeconds(
        lastScanEpochSeconds: TimeInterval?,
        configuredMinutes: Int,
        isLowPowerMode: Bool,
        nowEpochSeconds: TimeInterval
    ) -> TimeInterval? {
        let effective = effectiveIntervalMinutes(
            configuredMinutes: configuredMinutes,
            isLowPowerMode: isLowPowerMode
        )
        guard effective > 0 else { return nil }
        let intervalSec = TimeInterval(effective * 60)
        guard let last = lastScanEpochSeconds else { return nowEpochSeconds }
        return max(nowEpochSeconds, last + intervalSec)
    }

    /// Estimates daily scan count and approximate API requests for active foreground usage (assuming ~12 active hours/day).
    public static func estimateDailyUsage(
        symbolCount: Int,
        configuredMinutes: Int,
        isLowPowerMode: Bool,
        activeHoursPerDay: Double = 12.0,
        requestsPerSymbolPerScan: Int = 2
    ) -> ScanUsageEstimate {
        let effective = effectiveIntervalMinutes(
            configuredMinutes: configuredMinutes,
            isLowPowerMode: isLowPowerMode
        )
        let clamped = isLowPowerMode && configuredMinutes > 0 && configuredMinutes < lowPowerMinimumIntervalMinutes
        guard effective > 0, symbolCount > 0 else {
            return ScanUsageEstimate(
                scansPerDay: 0,
                estimatedRequestsPerDay: 0,
                effectiveIntervalMinutes: 0,
                lowPowerClamped: false,
                summaryText: "Auto-scan is off (manual refresh only)"
            )
        }

        let totalActiveMinutes = max(0, activeHoursPerDay * 60.0)
        let scans = max(1, Int(floor(totalActiveMinutes / Double(effective))))
        let requests = scans * max(1, symbolCount) * max(1, requestsPerSymbolPerScan)
        let lpNote = clamped ? " (Low Power cap: 30m)" : ""
        return ScanUsageEstimate(
            scansPerDay: scans,
            estimatedRequestsPerDay: requests,
            effectiveIntervalMinutes: effective,
            lowPowerClamped: clamped,
            summaryText: "~\(scans) scans/day · ~\(requests) data requests/day\(lpNote)"
        )
    }
}
