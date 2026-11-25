import SwiftUI
import SignalEngine

/// Settings Category 5: Data, Diagnostics & About (Diagnostics Hub, Logs, Crash Reports & Developer Info).
public struct DataDiagnosticsAboutSettingsView: View {
    @Bindable var coordinator: MarketScannerCoordinator
    let palette: ConfluencePalette

    public init(coordinator: MarketScannerCoordinator, palette: ConfluencePalette) {
        self.coordinator = coordinator
        self.palette = palette
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.3.0"
    }

    public var body: some View {
        Form {
            Section("Diagnostics, Logs & Calibration Data") {
                NavigationLink {
                    DiagnosticsHubView(coordinator: coordinator, palette: palette)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "stethoscope")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(palette.trapAmber)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Logs, Feed Health & Trade Ledger")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(palette.primaryInk)
                            Text("\(coordinator.diagnosticLog.entries.count) logs · \(coordinator.diagnosticLog.errorOnlyCount) err · \(coordinator.crashLogStore.entries.count) crashes")
                                .font(.caption)
                                .foregroundStyle(palette.secondaryInk)
                        }
                    }
                }
            }

            Section("About & Attribution") {
                NavigationLink {
                    AboutDeveloperSettingsView(palette: palette)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(palette.macroIceBlue)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("About Confluence & Developer")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(palette.primaryInk)
                            Text("v\(appVersion) · Developer : Bilal")
                                .font(.caption)
                                .foregroundStyle(palette.secondaryInk)
                        }
                    }
                }
            }
        }
        .navigationTitle("Data, Diagnostics & About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
