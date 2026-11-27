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
                HStack(spacing: 6) {
                    Picker(SettingHelpKey.appearanceMode.copy.label, selection: $coordinator.settings.payload.appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    ConfluenceInfoButton(.appearanceMode)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(SettingHelpKey.terminalThemePreset.copy.label)
                            .font(.subheadline)
                        ConfluenceInfoButton(.terminalThemePreset)
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(TerminalThemePreset.allCases) { preset in
                            let isSelected = coordinator.settings.payload.terminalThemePreset == preset
                            Button {
                                coordinator.settings.payload.terminalThemePreset = preset
                            } label: {
                                HStack(spacing: 8) {
                                    ZStack {
                                        Circle()
                                            .fill(Color(hex: preset.swatchBackgroundHex))
                                            .frame(width: 22, height: 22)
                                        Circle()
                                            .fill(Color(hex: preset.swatchAccentHex))
                                            .frame(width: 10, height: 10)
                                    }
                                    .overlay(
                                        Circle()
                                            .strokeBorder(palette.border, lineWidth: 0.75)
                                    )
                                    Text(preset.displayName)
                                        .font(.caption.weight(isSelected ? .bold : .medium))
                                        .foregroundStyle(palette.primaryInk)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(isSelected ? palette.champagneGold.opacity(0.14) : palette.elevatedSurface)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(isSelected ? palette.champagneGold : palette.border, lineWidth: isSelected ? 1.25 : 0.75)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 4)

                if coordinator.settings.payload.appearanceMode != .light {
                    Toggle(isOn: $coordinator.settings.payload.usePureBlackAMOLED) {
                        HStack(spacing: 6) {
                            Text(SettingHelpKey.pureBlackBackground.copy.label)
                            ConfluenceInfoButton(.pureBlackBackground)
                        }
                    }
                }

                HStack(spacing: 6) {
                    Picker(SettingHelpKey.liquidGlassIntensity.copy.label, selection: $coordinator.settings.payload.liquidGlassIntensity) {
                        ForEach(LiquidGlassIntensity.allCases) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    ConfluenceInfoButton(.liquidGlassIntensity)
                }

                Toggle(isOn: $coordinator.settings.payload.useColorBlindSafePalette) {
                    HStack(spacing: 6) {
                        Text(SettingHelpKey.colorBlindSafePalette.copy.label)
                        ConfluenceInfoButton(.colorBlindSafePalette)
                    }
                }
            } header: {
                Text("Theme & Accessibility")
            } footer: {
                Text(SettingHelpKey.colorBlindSafePalette.copy.subtitle)
            }

            Section("Time Display") {
                Toggle(isOn: $coordinator.settings.payload.use24HourTime) {
                    HStack(spacing: 6) {
                        Text(SettingHelpKey.clock24Hour.copy.label)
                        ConfluenceInfoButton(.clock24Hour)
                    }
                }
                Toggle(isOn: $coordinator.settings.payload.useUTCTimeZone) {
                    HStack(spacing: 6) {
                        Text(SettingHelpKey.universalTimeDisplay.copy.label)
                        ConfluenceInfoButton(.universalTimeDisplay)
                    }
                }
            }

            Section("Feed Layout") {
                HStack(spacing: 6) {
                    Picker(SettingHelpKey.cardDensity.copy.label, selection: $coordinator.settings.payload.cardDensity) {
                        ForEach(CardDensity.allCases) { d in
                            Text(d.rawValue).tag(d)
                        }
                    }
                    ConfluenceInfoButton(.cardDensity)
                }

                Toggle(isOn: $coordinator.settings.payload.showMiniCharts) {
                    HStack(spacing: 6) {
                        Text(SettingHelpKey.miniCharts.copy.label)
                        ConfluenceInfoButton(.miniCharts)
                    }
                }
            }

            Section {
                Toggle("In-app signal sound", isOn: $coordinator.settings.payload.inAppSignalSoundEnabled)
                Toggle("Notification sound", isOn: $coordinator.settings.payload.pushNotificationSoundEnabled)

                Picker("Sound style", selection: $coordinator.settings.payload.soundPreset) {
                    ForEach(SoundPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }

                Button {
                    SignalSoundEngine.shared.previewSound(
                        preset: coordinator.settings.payload.soundPreset,
                        hapticsEnabled: coordinator.settings.payload.hapticsEnabled
                    )
                } label: {
                    Label("Preview sound", systemImage: "speaker.wave.2.fill")
                }

                if coordinator.settings.payload.showAdvancedSettings {
                    Toggle("Trap warning sound", isOn: $coordinator.settings.payload.trapAlertSoundEnabled)
                    Toggle("Pre-news reminder sound", isOn: $coordinator.settings.payload.preNewsCountdownSoundEnabled)
                    Toggle("News release sound", isOn: $coordinator.settings.payload.newsReleaseImpactSoundEnabled)
                }
            } header: {
                SettingsSectionHeader("Signal & Alert Audio", helpKey: .signalAudio)
            }

            Section("Touch & Motion") {
                Toggle(isOn: $coordinator.settings.payload.hapticsEnabled) {
                    HStack(spacing: 6) {
                        Text(SettingHelpKey.haptics.copy.label)
                        ConfluenceInfoButton(.haptics)
                    }
                }
                Toggle(isOn: $coordinator.settings.payload.arrivalAnimationsEnabled) {
                    HStack(spacing: 6) {
                        Text(SettingHelpKey.arrivalAnimations.copy.label)
                        ConfluenceInfoButton(.arrivalAnimations)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.canvas)
        .navigationTitle("Appearance & Feedback")
        .navigationBarTitleDisplayMode(.inline)
    }
}
