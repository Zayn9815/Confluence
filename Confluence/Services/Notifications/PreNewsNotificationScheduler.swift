import Foundation
import UserNotifications
import SignalEngine

/// Manages `UNUserNotificationCenter` permissions, instant signal/trap/news release alerts,
/// and exact Stage-1 Pre-News Countdown scheduling strictly bounded to <= 40 pending slots
/// (safely respecting iOS's 64-notification hard cap).
@MainActor
public final class PreNewsNotificationScheduler {
    public static let shared = PreNewsNotificationScheduler()
    public static let preNewsPrefix = "confluence.prenews."
    public static let maxPreNewsSlots = 40

    private let center = UNUserNotificationCenter.current()

    public init() {}

    public func requestAuthorizationIfNeeded() async -> UNAuthorizationStatus {
        let current = await authorizationStatus()
        if current == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            return await authorizationStatus()
        }
        return current
    }

    public func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }

    /// Cancels stale `confluence.prenews.*` reminders and schedules exact-clock pre-news countdowns
    /// for upcoming events (max 40 slots total).
    public func reschedulePreNewsCountdowns(
        events: [EconomicEvent],
        settings: PersistedSettingsPayload,
        nowEpochSeconds: TimeInterval = Date().timeIntervalSince1970
    ) async -> Int {
        let pending = await center.pendingNotificationRequests()
        let staleIds = pending.map(\.identifier).filter { $0.hasPrefix(Self.preNewsPrefix) }
        if !staleIds.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: staleIds)
        }

        guard settings.economicCalendarEnabled else { return 0 }
        var leads: [Int] = []
        if settings.preNewsLead15m { leads.append(15) }
        if settings.preNewsLead5m { leads.append(5) }
        guard !leads.isEmpty else { return 0 }

        let slots = MacroSurpriseEngine.planPreNewsNotificationSlots(
            events: events,
            nowEpochSeconds: nowEpochSeconds,
            leadTimesMinutes: leads,
            minimumImportance: settings.calendarPushImpactFilter.minimumImportance,
            maxSlots: Self.maxPreNewsSlots
        )

        var scheduled = 0
        for slot in slots {
            let content = UNMutableNotificationContent()
            content.title = "Pre-News Volatility Shield · \(slot.event.countryCode)"
            content.subtitle = "\(slot.event.name) in \(slot.leadMinutes)m"
            content.body = "High-impact \(slot.event.currency) release ahead. Expect spreads & stop-hunt whipsaws."
            content.categoryIdentifier = "PRE_NEWS_SHIELD"
            content.userInfo = [
                NotificationUserInfoKey.type: NotificationItemType.preNewsCountdown.rawValue,
                NotificationUserInfoKey.notificationID: slot.identifier,
                NotificationUserInfoKey.eventID: slot.event.id,
                NotificationUserInfoKey.symbol: slot.event.currency
            ]
            if settings.pushNotificationSoundEnabled && settings.preNewsCountdownSoundEnabled {
                content.sound = UNNotificationSound(named: UNNotificationSoundName("news_release_ping.caf"))
            }

            let fireDate = Date(timeIntervalSince1970: slot.fireEpochSeconds)
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let req = UNNotificationRequest(identifier: slot.identifier, content: content, trigger: trigger)
            do {
                try await center.add(req)
                scheduled += 1
            } catch {
                continue
            }
        }
        return scheduled
    }

    public func postSignalNotification(_ signal: TradeSignal, settings: PersistedSettingsPayload) async {
        let content = UNMutableNotificationContent()
        let notifId = "confluence.signal.\(signal.fingerprint)"
        let itemType: NotificationItemType = (signal.category == .trapAlert) ? .trapAlert : .strongSignal
        if signal.category == .trapAlert, let trap = signal.trapDirection {
            content.title = "\(trap.rawValue) · \(signal.symbol) (\(signal.timeframe.displayLabel))"
            content.body = signal.psychologyReport.whatHappened
            if settings.pushNotificationSoundEnabled && settings.trapAlertSoundEnabled {
                content.sound = UNNotificationSound(named: UNNotificationSoundName("trap_warning.caf"))
            }
        } else {
            let dir = signal.direction.rawValue.uppercased()
            let rr = signal.levels.map { "1:\(String(format: "%.1f", $0.riskRewardRatio))" } ?? ""
            content.title = "\(dir) \(signal.symbol) · \(Int(signal.confidencePercent.rounded()))% (\(signal.tier.displayName))"
            content.body = "\(signal.timeframe.displayLabel) \(rr) · \(signal.psychologyReport.whatHappened)"
            if settings.pushNotificationSoundEnabled, let caf = settings.soundPreset.cafFileName {
                content.sound = UNNotificationSound(named: UNNotificationSoundName(caf))
            }
        }
        content.userInfo = [
            NotificationUserInfoKey.type: itemType.rawValue,
            NotificationUserInfoKey.notificationID: notifId,
            NotificationUserInfoKey.signalFingerprint: signal.fingerprint,
            NotificationUserInfoKey.symbol: signal.symbol,
            NotificationUserInfoKey.market: signal.marketClass.rawValue,
            NotificationUserInfoKey.category: signal.category.rawValue,
            NotificationUserInfoKey.timeframe: signal.timeframe.rawValue,
            NotificationUserInfoKey.direction: signal.direction.rawValue,
            NotificationUserInfoKey.confidence: String(format: "%.1f", signal.confidencePercent)
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let req = UNNotificationRequest(identifier: notifId, content: content, trigger: trigger)
        try? await center.add(req)
    }

    public func postMacroReleaseNotification(_ cluster: MacroClusterImpulse, settings: PersistedSettingsPayload) async {
        let content = UNMutableNotificationContent()
        let id = "confluence.macro.\(cluster.currency).\(Int(cluster.clusterEpochSeconds))"
        content.title = "Macro Release · \(cluster.currency)"
        content.body = cluster.headlineStrip
        content.userInfo = [
            NotificationUserInfoKey.type: NotificationItemType.newsReleaseImpact.rawValue,
            NotificationUserInfoKey.notificationID: id,
            NotificationUserInfoKey.symbol: cluster.currency,
            NotificationUserInfoKey.eventID: cluster.results.first?.event.id ?? id
        ]
        if settings.pushNotificationSoundEnabled && settings.newsReleaseImpactSoundEnabled {
            content.sound = UNNotificationSound(named: UNNotificationSoundName("news_release_ping.caf"))
        }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await center.add(req)
    }
}
