import SwiftUI
import SignalEngine

/// Settings Category 2: Alerts (iOS Notification Permissions, Bell Inbox, Pre-News Leads & Safety Suppression).
public struct AlertsSettingsView: View {
    @Bindable var coordinator: MarketScannerCoordinator
    let palette: ConfluencePalette

    public init(coordinator: MarketScannerCoordinator, palette: ConfluencePalette) {
        self.coordinator = coordinator
        self.palette = palette
    }

    public var body: some View {
        Form {
            Section("System Notification Permission") {
                HStack {
                    Text("iOS Notifications")
                    Spacer()
                    Button(coordinator.notificationStatusDescription) {
                        Task { await coordinator.requestNotifications() }
                    }
                    .font(.caption.weight(.semibold))
                }

                HStack {
                    Text("Stored Bell Inbox")
                    Spacer()
                    Text("\(coordinator.notifications.count) saved · \(coordinator.unreadNotificationCount) unread")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(palette.secondaryInk)
                }

                Button {
                    coordinator.isNotificationInboxPresented = true
                } label: {
                    Label("Open Notification Inbox", systemImage: "bell.badge")
                }
            }

            Section {
                Picker("Calendar Alert Impact", selection: $coordinator.settings.payload.calendarPushImpactFilter) {
                    ForEach(CalendarImpactFilter.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }

                Toggle("Pre-News Countdown (15m Before)", isOn: $coordinator.settings.payload.preNewsLead15m)
                Toggle("Pre-News Countdown (5m Before)", isOn: $coordinator.settings.payload.preNewsLead5m)
                Toggle("Pause Signals During Pre-News Window", isOn: $coordinator.settings.payload.pauseSignalsDuringPreNewsWindow)
            } header: {
                Text("Macro & Pre-News Alerts")
            } footer: {
                Text("Pre-news countdown notifications are scheduled strictly for exact-clock calendar events within iOS's 40-slot pre-news budget.")
            }

            Section("Risk Protection") {
                Toggle("Auto-Suppress Alerts in Crisis Regime", isOn: $coordinator.settings.payload.autoSuppressCrisisAlerts)
            }
        }
        .navigationTitle("Alerts")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await coordinator.refreshNotificationStatus()
        }
    }
}
