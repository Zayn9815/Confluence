import SwiftUI
import SignalEngine

/// Clean, uncluttered 7-row Drill-Down Settings Hub.
/// Zero toggles, sliders, or text fields live on the root screen — every row drills into a dedicated sub-screen.
public struct SettingsTabView: View {
    @Bindable var coordinator: MarketScannerCoordinator
    let palette: ConfluencePalette

    public init(coordinator: MarketScannerCoordinator, palette: ConfluencePalette) {
        self.coordinator = coordinator
        self.palette = palette
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.0"
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Terminal Preferences") {
                    NavigationLink {
                        AppearanceSettingsView(coordinator: coordinator, palette: palette)
                    } label: {
                        settingsRow(
                            icon: "paintbrush.fill",
                            color: palette.champagneGold,
                            title: "Appearance & Display",
                            subtitle: "\(coordinator.settings.payload.themePreset.rawValue) · \(coordinator.settings.payload.cardDensity.rawValue)"
                        )
                    }

                    NavigationLink {
                        NotificationsSoundSettingsView(coordinator: coordinator, palette: palette)
                    } label: {
                        settingsRow(
                            icon: "bell.badge.fill",
                            color: palette.shortCrimson,
                            title: "Notifications, Sound & Haptics",
                            subtitle: "\(coordinator.settings.payload.soundPreset.rawValue) · \(coordinator.unreadNotificationCount) unread"
                        )
                    }
                }

                Section("Market Data & Intelligence") {
                    NavigationLink {
                        MarketsFeedsSettingsView(coordinator: coordinator, palette: palette)
                    } label: {
                        settingsRow(
                            icon: "antenna.radiowaves.left.and.right",
                            color: palette.macroIceBlue,
                            title: "Markets, News & Data Feeds",
                            subtitle: "\(coordinator.settings.payload.enabledMarkets.count) markets · \(coordinator.settings.payload.tradFiProviderPreference.shortLabel) / \(coordinator.settings.payload.cryptoPrimaryExchange.shortLabel)"
                        )
                    }

                    NavigationLink {
                        SignalEngineSettingsView(coordinator: coordinator, palette: palette)
                    } label: {
                        settingsRow(
                            icon: "waveform.path.ecg",
                            color: palette.longEmerald,
                            title: "Signal Engine & Psychology",
                            subtitle: "Min \(Int(coordinator.settings.payload.minimumConfidencePercent.rounded()))% · R:R 1:\(String(format: "%.1f", coordinator.settings.payload.minimumRiskReward))"
                        )
                    }

                    NavigationLink {
                        AISecondOpinionSettingsView(coordinator: coordinator, palette: palette)
                    } label: {
                        settingsRow(
                            icon: "sparkles",
                            color: Color(hex: 0xA855F7),
                            title: "AI Second-Opinion",
                            subtitle: coordinator.settings.payload.geminiEnabled
                                ? "ON · \(coordinator.settings.payload.geminiModel.displayName)"
                                : "OFF · 100% Native Deterministic Mode"
                        )
                    }
                }

                Section("Diagnostics & Info") {
                    NavigationLink {
                        DiagnosticsHubView(coordinator: coordinator, palette: palette)
                    } label: {
                        settingsRow(
                            icon: "stethoscope",
                            color: palette.trapAmber,
                            title: "Calibration, Logs & Diagnostics",
                            subtitle: "\(coordinator.diagnosticLog.entries.count) logs · \(coordinator.tradeLedger.count) trades · \(coordinator.trapLogs.count) traps"
                        )
                    }

                    NavigationLink {
                        AboutDeveloperSettingsView(palette: palette)
                    } label: {
                        settingsRow(
                            icon: "info.circle.fill",
                            color: palette.secondaryInk,
                            title: "About & Developer",
                            subtitle: "Confluence v\(appVersion) · Developer : Bilal"
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)
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
