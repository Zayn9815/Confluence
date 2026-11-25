import SwiftUI
import SignalEngine

public struct SignalEngineSettingsView: View {
    @Bindable var coordinator: MarketScannerCoordinator
    let palette: ConfluencePalette

    public var body: some View {
        Form {
            Section("Confluence & Risk Thresholds") {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Minimum Confidence %")
                        Spacer()
                        Text("\(Int(coordinator.settings.payload.minimumConfidencePercent.rounded()))%")
                            .monospacedDigit()
                            .fontWeight(.semibold)
                    }
                    Slider(value: $coordinator.settings.payload.minimumConfidencePercent, in: 55...90, step: 1)
                }

                Picker("Minimum Risk:Reward", selection: $coordinator.settings.payload.minimumRiskReward) {
                    Text("1 : 1.5").tag(1.5)
                    Text("1 : 2.0").tag(2.0)
                    Text("1 : 2.5").tag(2.5)
                    Text("1 : 3.0").tag(3.0)
                }

                VStack(alignment: .leading) {
                    HStack {
                        Text("Max SL % (Crypto / Stocks)")
                        Spacer()
                        Text(String(format: "%.1f%%", coordinator.settings.payload.maxStopLossPercentCryptoStocks))
                            .monospacedDigit()
                    }
                    Slider(value: $coordinator.settings.payload.maxStopLossPercentCryptoStocks, in: 1.0...6.0, step: 0.5)
                }

                VStack(alignment: .leading) {
                    HStack {
                        Text("Max SL % (Forex / Gold / Indices)")
                        Spacer()
                        Text(String(format: "%.1f%%", coordinator.settings.payload.maxStopLossPercentFXMetalsIndices))
                            .monospacedDigit()
                    }
                    Slider(value: $coordinator.settings.payload.maxStopLossPercentFXMetalsIndices, in: 0.5...3.0, step: 0.25)
                }
            }

            Section("Enabled Strategy Modules") {
                ForEach(StrategyGroup.allCases, id: \.self) { group in
                    Toggle(group.displayName, isOn: Binding(
                        get: { coordinator.settings.payload.enabledStrategyGroups.contains(group) },
                        set: { _ in coordinator.settings.toggleStrategyGroup(group) }
                    ))
                }
            }

            Section("Safety & Feed Visibility") {
                Toggle("Show \"Weak / Filtered Signals\" in Feed", isOn: $coordinator.settings.payload.showWeakFilteredSignals)
                Toggle("Auto-Suppress Alerts in Crisis Regime", isOn: $coordinator.settings.payload.autoSuppressCrisisAlerts)
            }
        }
        .navigationTitle("Signal Engine & Psychology")
        .navigationBarTitleDisplayMode(.inline)
    }
}
