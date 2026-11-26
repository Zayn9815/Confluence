import SwiftUI
import SignalEngine

public enum NotificationInboxFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case signals = "Signals"
    case traps = "Traps"
    case news = "News"

    public var id: String { rawValue }
}

/// Persistent stored-notification inbox (latest 250 alerts) with category filter chips,
/// Today / Earlier grouping, unread dots, swipe-to-delete & mark-read, and tap-to-navigate.
public struct NotificationInboxSheet: View {
    @Bindable public var coordinator: MarketScannerCoordinator
    public let palette: ConfluencePalette
    @Environment(\.dismiss) private var dismiss

    @State private var filter: NotificationInboxFilter = .all
    @State private var showClearConfirm: Bool = false

    private var filteredItems: [NotificationItemSnapshot] {
        coordinator.notifications.filter { item in
            switch filter {
            case .all: return true
            case .signals: return item.type == .strongSignal
            case .traps: return item.type == .trapAlert
            case .news: return item.type == .preNewsCountdown || item.type == .newsReleaseImpact
            }
        }
    }

    private var todayItems: [NotificationItemSnapshot] {
        filteredItems.filter { Calendar.current.isDateInToday($0.createdAt) }
    }

    private var earlierItems: [NotificationItemSnapshot] {
        filteredItems.filter { !Calendar.current.isDateInToday($0.createdAt) }
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(palette.surface)

                Divider().overlay(palette.border)

                if filteredItems.isEmpty {
                    emptyState
                } else {
                    List {
                        if !todayItems.isEmpty {
                            Section {
                                ForEach(todayItems) { item in
                                    notificationRow(item)
                                }
                            } header: {
                                Text("TODAY")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(palette.secondaryInk)
                            }
                            .listRowBackground(palette.surface)
                        }

                        if !earlierItems.isEmpty {
                            Section {
                                ForEach(earlierItems) { item in
                                    notificationRow(item)
                                }
                            } header: {
                                Text("EARLIER")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(palette.secondaryInk)
                            }
                            .listRowBackground(palette.surface)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(palette.canvas)
                }
            }
            .background(palette.canvas.ignoresSafeArea())
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if coordinator.unreadNotificationCount > 0 {
                        Button("Mark All Read") {
                            coordinator.markAllNotificationsRead()
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.champagneGold)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        if !coordinator.notifications.isEmpty {
                            Button("Clear All") {
                                showClearConfirm = true
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.shortCrimson)
                        }
                        Button("Done") { dismiss() }
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            .confirmationDialog(
                "Clear all stored notifications?",
                isPresented: $showClearConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear All Notifications", role: .destructive) {
                    coordinator.clearAllNotifications()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(NotificationInboxFilter.allCases) { tab in
                let selected = (filter == tab)
                Button {
                    filter = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(selected ? palette.canvas : palette.secondaryInk)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selected ? palette.champagneGold : palette.elevatedSurface, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bell.slash")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(palette.tertiaryInk)
            Text("No Stored Alerts Yet")
                .font(.headline)
                .foregroundStyle(palette.primaryInk)
            Text("Strong Signals, Behavioral Trap Warnings, Pre-News Countdowns, and Macro Release impacts are saved here automatically so nothing is lost when dismissed from the lock screen.")
                .font(.caption)
                .foregroundStyle(palette.secondaryInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func notificationRow(_ item: NotificationItemSnapshot) -> some View {
        let isHighConviction = (item.confidence ?? 0) >= 70.0
        let isLowScoreMuted = item.confidence.map { $0 < 50.0 } ?? false
        let rowAccent = isLowScoreMuted ? palette.secondaryInk : accentColor(for: item)

        return Button {
            coordinator.handleNotificationTap(item)
            dismiss()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(rowAccent.opacity(isLowScoreMuted ? 0.10 : 0.16))
                        .frame(width: 34, height: 34)
                    Image(systemName: iconName(for: item))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(rowAccent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if !item.isRead {
                            Circle()
                                .fill(palette.champagneGold)
                                .frame(width: 7, height: 7)
                        }
                        Text(item.title)
                            .font(.subheadline.weight(isHighConviction || !item.isRead ? .bold : .medium))
                            .foregroundStyle(isLowScoreMuted ? palette.secondaryInk : palette.primaryInk)
                            .lineLimit(1)
                        Spacer()
                        Text(item.createdAt, style: .relative)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(palette.tertiaryInk)
                    }

                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(isLowScoreMuted ? palette.tertiaryInk : palette.secondaryInk)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Text(item.type.displayName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(rowAccent)
                        if let tf = item.timeframe {
                            Text("· \(tf.displayLabel)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(palette.tertiaryInk)
                        }
                        if let conf = item.confidence {
                            let scoreInt = Int(conf.rounded())
                            Text("\(scoreInt)/100")
                                .font(.system(size: 10, weight: .bold).monospacedDigit())
                                .foregroundStyle(isHighConviction ? palette.champagneGold : (isLowScoreMuted ? palette.tertiaryInk : palette.secondaryInk))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background((isHighConviction ? palette.champagneGold.opacity(0.16) : palette.elevatedSurface), in: Capsule())
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .opacity(isLowScoreMuted ? 0.72 : 1.0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                coordinator.deleteNotification(id: item.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                coordinator.markNotificationRead(id: item.id, read: !item.isRead)
            } label: {
                Label(item.isRead ? "Unread" : "Read", systemImage: item.isRead ? "envelope.badge" : "envelope.open")
            }
            .tint(palette.champagneGold)
        }
    }

    private func iconName(for item: NotificationItemSnapshot) -> String {
        switch item.type {
        case .strongSignal:
            return item.direction == .short ? "arrow.down.right.circle.fill" : "arrow.up.right.circle.fill"
        case .trapAlert:
            return "exclamationmark.triangle.fill"
        case .preNewsCountdown:
            return "clock.badge.exclamationmark.fill"
        case .newsReleaseImpact:
            return "newspaper.fill"
        }
    }

    private func accentColor(for item: NotificationItemSnapshot) -> Color {
        switch item.type {
        case .strongSignal:
            return item.direction == .short ? palette.shortCrimson : palette.longEmerald
        case .trapAlert:
            return palette.trapAmber
        case .preNewsCountdown:
            return palette.champagneGold
        case .newsReleaseImpact:
            return palette.champagneGold
        }
    }
}
