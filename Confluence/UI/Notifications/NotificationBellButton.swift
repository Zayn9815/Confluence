import SwiftUI

/// Standard top-right navigation bar Notification Bell with live unread count badge.
public struct NotificationBellButton: View {
    public let unreadCount: Int
    public let palette: ConfluencePalette
    public let action: () -> Void

    public init(unreadCount: Int, palette: ConfluencePalette, action: @escaping () -> Void) {
        self.unreadCount = unreadCount
        self.palette = palette
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: unreadCount > 0 ? "bell.badge.fill" : "bell")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(unreadCount > 0 ? palette.champagneGold : palette.primaryInk)
                    .frame(width: 30, height: 30)

                if unreadCount > 0 {
                    Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(palette.shortCrimson, in: Capsule())
                        .offset(x: 5, y: -2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(unreadCount > 0 ? "Notifications, \(unreadCount) unread" : "Notifications")
    }
}
