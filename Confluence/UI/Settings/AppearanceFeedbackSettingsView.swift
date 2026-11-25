import SwiftUI
import SignalEngine

/// Settings Category 1: Appearance & Feedback (Theme Mode, Pure Black AMOLED, Card Density, Audio, Haptics & Motion).
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
            } header: {
                Text("Theme & Color Mode")
            } footer: {
                Text("Pure Black (AMOLED) switches the dark canvas to true #000000 black for OLED displays while preserving contrast on cards and price levels.")
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
