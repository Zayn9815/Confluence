import SwiftUI
import SignalEngine

/// Settings Category 1: Appearance & Feedback (Theme Mode, Pure Black AMOLED, Accessibility, Time Format, Audio & Haptics).
public struct AppearanceFeedbackSettingsView: View {
    @Bindable var coordinator: MarketScannerCoordinator
    let palette: ConfluencePalette

    public init(coordinator: MarketScannerCoordinator, palette: ConfluencePalette) {
        self.coordinator = coordinator
        self.palette = palette
    }

    public var body: some View {
        Form {
            Section {
                Picker("Appearance Mode", selection: $coordinator.settings.payload.appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                if coordinator.settings.payload.appearanceMode != .light {
                    Toggle("Pure Black (AMOLED)", isOn: $coordinator.settings.payload.usePureBlackAMOLED)
                }

                Toggle("Color-Blind Safe Palette (Blue / Orange)", isOn: $coordinator.settings.payload.useColorBlindSafePalette)
            } header: {
                Text("Theme & Accessibility")
            } footer: {
                Text("Color-Blind Safe replaces green/red directional cues with Okabe-Ito Blue/Orange alongside explicit directional arrows. System Increase Contrast & Reduce Motion are honored automatically.")
            }

            Section("Time Display") {
                Toggle("24-Hour Clock (14:30 vs 2:30 PM)", isOn: $coordinator.settings.payload.use24HourTime)
                Toggle("Show Timestamps in UTC", isOn: $coordinator.settings.payload.useUTCTimeZone)
            }

            Section("Feed Layout") {
                Picker("Card Density", selection: $coordinator.settings.payload.cardDensity) {
                    ForEach(CardDensity.allCases) { d in
                        Text(d.rawValue).tag(d)
                    }
                }

                Toggle("Show Signal Mini-Charts", isOn: $coordinator.settings.payload.showMiniCharts)
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

                if coordinator.settings.payload.showAdvancedSettings {
                    Toggle("Trap Alert Sound", isOn: $coordinator.settings.payload.trapAlertSoundEnabled)
                    Toggle("Pre-News Countdown Sound", isOn: $coordinator.settings.payload.preNewsCountdownSoundEnabled)
                    Toggle("News Release Impact Sound", isOn: $coordinator.settings.payload.newsReleaseImpactSoundEnabled)
                }
            }

            Section("Tactile & Motion") {
                Toggle("Haptic Feedback (CoreHaptics)", isOn: $coordinator.settings.payload.hapticsEnabled)
                Toggle("Signal Arrival Animations", isOn: $coordinator.settings.payload.arrivalAnimationsEnabled)
            }
        }
        .navigationTitle("Appearance & Feedback")
        .navigationBarTitleDisplayMode(.inline)
    }
}
