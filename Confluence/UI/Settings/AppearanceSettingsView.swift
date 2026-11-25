import SwiftUI
import SignalEngine

public struct AppearanceSettingsView: View {
    @Bindable var coordinator: MarketScannerCoordinator
    let palette: ConfluencePalette

    public var body: some View {
        Form {
            Section("Theme & Color Mode") {
                Picker("Appearance Mode", selection: $coordinator.settings.payload.appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                Picker("Theme Style", selection: $coordinator.settings.payload.themePreset) {
                    ForEach(ThemePreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
            }

            Section("Feed Layout") {
                Picker("Card Density", selection: $coordinator.settings.payload.cardDensity) {
                    ForEach(CardDensity.allCases) { d in
                        Text(d.rawValue).tag(d)
                    }
                }

                Toggle("Show Signal Mini-Charts", isOn: $coordinator.settings.payload.showMiniCharts)
            }
        }
        .navigationTitle("Appearance & Display")
        .navigationBarTitleDisplayMode(.inline)
    }
}
