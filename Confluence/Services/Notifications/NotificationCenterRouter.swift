import Foundation
import UserNotifications
import SignalEngine

public enum NotificationUserInfoKey {
    public static let type = "confluence_type"
    public static let signalFingerprint = "confluence_signal_fingerprint"
    public static let symbol = "confluence_symbol"
    public static let market = "confluence_market"
    public static let category = "confluence_category"
    public static let eventID = "confluence_event_id"
    public static let notificationID = "confluence_notification_id"
    public static let timeframe = "confluence_timeframe"
    public static let direction = "confluence_direction"
    public static let confidence = "confluence_confidence"
}

public enum NavigationDeepLink: Equatable, Sendable {
    case signal(fingerprint: String, category: SignalCategory?, market: MarketClass?, symbol: String?)
    case news(eventID: String?)
}

/// Unified Swift 6 `UNUserNotificationCenterDelegate` that synchronizes lock-screen / foreground
/// notifications with the persistent SwiftData Bell inbox, manages app icon badge counts,
/// and routes notification taps to the exact Signal Card or Economic Event.
public final class NotificationCenterRouter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    public static let shared = NotificationCenterRouter()

    @MainActor public var onDeepLink: ((NavigationDeepLink) -> Void)?
    @MainActor public var onForegroundSystemNotification: ((NotificationItemSnapshot) -> Void)?
    @MainActor public var onMarkReadById: ((String) -> Void)?

    private override init() {
        super.init()
    }

    @MainActor
    public func registerAsDelegate() {
        UNUserNotificationCenter.current().delegate = self
    }

    @MainActor
    public func syncAppBadgeCount(_ unreadCount: Int) {
        let clamped = max(0, unreadCount)
        Task {
            try? await UNUserNotificationCenter.current().setBadgeCount(clamped)
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let content = notification.request.content
        let reqId = notification.request.identifier
        let title = content.title
        let subtitle = content.subtitle.isEmpty ? content.body : "\(content.subtitle) · \(content.body)"
        let info = Self.extractStrings(from: content.userInfo)

        let itemType = NotificationItemType(rawValue: info[NotificationUserInfoKey.type] ?? "") ?? .preNewsCountdown
        let market = info[NotificationUserInfoKey.market].flatMap(MarketClass.init(rawValue:))
        let tf = info[NotificationUserInfoKey.timeframe].flatMap(Timeframe.init(rawValue:))
        let dir = info[NotificationUserInfoKey.direction].flatMap(TradeDirection.init(rawValue:))
        let conf = info[NotificationUserInfoKey.confidence].flatMap(Double.init)

        let snapshot = NotificationItemSnapshot(
            id: info[NotificationUserInfoKey.notificationID] ?? reqId,
            createdAt: notification.date,
            type: itemType,
            title: title,
            subtitle: subtitle,
            symbol: info[NotificationUserInfoKey.symbol],
            marketClass: market,
            timeframe: tf,
            direction: dir,
            confidence: conf,
            signalFingerprint: info[NotificationUserInfoKey.signalFingerprint],
            eventID: info[NotificationUserInfoKey.eventID],
            isRead: false
        )

        await MainActor.run {
            self.onForegroundSystemNotification?(snapshot)
        }

        // Foreground signal/trap/macro alerts are rendered by Confluence's translucent PopupView;
        // scheduled Pre-News local triggers also present a clean system banner & sound.
        if itemType == .preNewsCountdown {
            return [.banner, .list, .sound]
        }
        return [.list]
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let content = response.notification.request.content
        let reqId = response.notification.request.identifier
        let info = Self.extractStrings(from: content.userInfo)
        let notifId = info[NotificationUserInfoKey.notificationID] ?? reqId
        let deepLink = Self.parseDeepLink(from: info)

        await MainActor.run {
            self.onMarkReadById?(notifId)
            if let deepLink {
                self.onDeepLink?(deepLink)
            }
        }
    }

    // MARK: - Pure Parsing Helpers (Testable)

    public nonisolated static func extractStrings(from userInfo: [AnyHashable: Any]) -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in userInfo {
            guard let key = k as? String else { continue }
            if let str = v as? String {
                out[key] = str
            } else if let num = v as? NSNumber {
                out[key] = num.stringValue
            }
        }
        return out
    }

    public nonisolated static func parseDeepLink(from info: [String: String]) -> NavigationDeepLink? {
        if let fp = info[NotificationUserInfoKey.signalFingerprint], !fp.isEmpty {
            let category = info[NotificationUserInfoKey.category].flatMap(SignalCategory.init(rawValue:))
            let market = info[NotificationUserInfoKey.market].flatMap(MarketClass.init(rawValue:))
            return .signal(
                fingerprint: fp,
                category: category,
                market: market,
                symbol: info[NotificationUserInfoKey.symbol]
            )
        }
        if let eventID = info[NotificationUserInfoKey.eventID] {
            return .news(eventID: eventID)
        }
        let type = info[NotificationUserInfoKey.type]
        if type == NotificationItemType.preNewsCountdown.rawValue || type == NotificationItemType.newsReleaseImpact.rawValue {
            return .news(eventID: nil)
        }
        return nil
    }
}
