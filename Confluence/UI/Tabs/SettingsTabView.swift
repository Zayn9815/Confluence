import SwiftUI
import SignalEngine

/// Clean 5-category Drill-Down Settings Hub with a top-level `Show Advanced Settings` toggle (default OFF).
public struct SettingsTabView: View {
    @Bindable var coordinator: MarketScannerCoordinator
    let palette: ConfluencePalette

    public init(coordinator: MarketScannerCoordinator, palette: ConfluencePalette) {
        self.coordinator = coordinator
        self.palette = palette
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.5.0"
    }

    private var themeSummary: String {
        let mode = coordinator.settings.payload.appearanceMode.rawValue
        if coordinator.settings.payload.appearanceMode != .light && coordinator.settings.payload.usePureBlackAMOLED {
            return "\(mode) (Pure Black) · \(coordinator.settings.payload.cardDensity.rawValue)"
        }
        return "\(mode) · \(coordinator.settings.payload.cardDensity.rawValue)"
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        AppearanceFeedbackSettingsView(coordinator: coordinator, palette: palette)
                    } label: {
                        settingsRow(
                            icon: "paintbrush.fill",
                            color: palette.champagneGold,
                            title: "Appearance & Feedback",
                            subtitle: themeSummary
                        )
                    }

                    NavigationLink {
                        AlertsSettingsView(coordinator: coordinator, palette: palette)
                    } label: {
                        settingsRow(
                            icon: "bell.badge.fill",
                            color: palette.shortCrimson,
                            title: "Alerts",
                            subtitle: "\(coordinator.notificationStatusDescription) · \(coordinator.unreadNotificationCount) unread"
                        )
                    }

                    NavigationLink {
                        MarketsFeedsSettingsView(coordinator: coordinator, palette: palette)
                    } label: {
                        settingsRow(
                            icon: "antenna.radiowaves.left.and.right",
                            color: palette.secondaryInk,
                            title: "Markets & Data",
                            subtitle: "\(coordinator.settings.payload.enabledMarkets.count) markets · \(coordinator.settings.payload.tradFiProviderPreference.shortLabel) / \(coordinator.settings.payload.cryptoPrimaryExchange.shortLabel)"
                        )
                    }

                    NavigationLink {
                        SignalRulesSettingsView(coordinator: coordinator, palette: palette)
                    } label: {
                        let aiBadge = coordinator.settings.payload.geminiEnabled ? coordinator.settings.payload.aiProvider.shortLabel : "Native"
                        settingsRow(
                            icon: "waveform.path.ecg",
                            color: palette.longEmerald,
                            title: "Signal Rules & AI",
                            subtitle: "Strength ≥\(Int(coordinator.settings.payload.minimumConfidencePercent.rounded())) · 1:\(String(format: "%.1f", coordinator.settings.payload.minimumRiskReward)) · \(aiBadge)"
                        )
                    }

                    NavigationLink {
                        DataDiagnosticsAboutSettingsView(coordinator: coordinator, palette: palette)
                    } label: {
                        settingsRow(
                            icon: "stethoscope",
                            color: palette.trapAmber,
                            title: "Data, Diagnostics & About",
                            subtitle: "v\(appVersion) · \(coordinator.diagnosticLog.errorOnlyCount) errors · \(coordinator.crashLogStore.entries.count) crashes"
                        )
                    }
                } header: {
                    Text("Configuration")
                }

                Section {
                    Toggle(isOn: $coordinator.settings.payload.showAdvancedSettings) {
                        HStack(alignment: .center, spacing: 6) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(SettingHelpKey.showAdvancedSettings.copy.label)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(palette.primaryInk)
                                Text(SettingHelpKey.showAdvancedSettings.copy.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(palette.secondaryInk)
                            }
                            Spacer(minLength: 4)
                            ConfluenceInfoButton(.showAdvancedSettings)
                        }
                    }
                    .tint(palette.champagneGold)
                }
            }
            .listStyle(.insetGrouped)
            .safeAreaPadding(.bottom, 96)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NotificationBellButton(
                        unreadCount: coordinator.unreadNotificationCount,
                        palette: palette
                    ) {
                        coordinator.isNotificationInboxPresented = true
                    }
                }
            }
        }
    }

    private func settingsRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(0.18))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.primaryInk)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryInk)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}
