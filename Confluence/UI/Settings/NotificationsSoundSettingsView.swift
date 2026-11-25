import SwiftUI
import SignalEngine

public struct NotificationsSoundSettingsView: View {
    @Bindable var coordinator: MarketScannerCoordinator
    let palette: ConfluencePalette

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

            Section("Signal & Alert Audio") {
                Toggle("In-App Signal Sound", isOn: $coordinator.settings.payload.inAppSignalSoundEnabled)
                Toggle("Push Notification Sound", isOn: $coordinator.settings.payload.pushNotificationSoundEnabled)

                Picker("Sound Preset", selection: $coordinator.settings.payload.soundPreset) {
                    ForEach(SoundPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }

                Button {
                    SignalSoundEngine.shared.previewSound(preset: coordinator.settings.payload.soundPreset)
                } label: {
                    Label("Preview Sound", systemImage: "speaker.wave.2.fill")
                }

                Toggle("Trap Alert Sound", isOn: $coordinator.settings.payload.trapAlertSoundEnabled)
                Toggle("Pre-News Countdown Sound", isOn: $coordinator.settings.payload.preNewsCountdownSoundEnabled)
                Toggle("News Release Impact Sound", isOn: $coordinator.settings.payload.newsReleaseImpactSoundEnabled)
            }

            Section("Tactile & Motion") {
                Toggle("Haptic Feedback (CoreHaptics)", isOn: $coordinator.settings.payload.hapticsEnabled)
                Toggle("Signal Arrival Animations", isOn: $coordinator.settings.payload.arrivalAnimationsEnabled)
            }
        }
        .navigationTitle("Notifications & Sound")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await coordinator.refreshNotificationStatus()
        }
    }
}
