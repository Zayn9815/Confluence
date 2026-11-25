import SwiftUI
import SignalEngine

/// Settings Category 4: Signal Rules & AI
/// Consolidates core Score/R:R/TP rules, Advanced Fixed-%/Strategy-Selection/Custom-Calibration rules
/// (with Random Subset permanently removed), and embedded optional Gemini AI Second-Opinion settings.
public struct SignalRulesSettingsView: View {
    @Bindable var coordinator: MarketScannerCoordinator
    let palette: ConfluencePalette

    @State private var geminiKeyInput = ""
    @State private var hasGeminiKey = false

    private let confidencePresets: [Double] = [65, 70, 80, 90]
    private let calibrationConfidencePresets: [Double] = [0, 70, 80, 90]

    public init(coordinator: MarketScannerCoordinator, palette: ConfluencePalette) {
        self.coordinator = coordinator
        self.palette = palette
    }

    private var fixedRatioPreview: String {
        let sl = max(0.05, coordinator.settings.payload.fixedStopLossPercent)
        let tp1 = max(0.10, coordinator.settings.payload.fixedTP1Percent)
        let ratio = tp1 / sl
        return "1 : \(String(format: "%.2f", ratio))"
    }

    public var body: some View {
        let isAdvanced = coordinator.settings.payload.showAdvancedSettings

        Form {
            // SECTION 1 — Strong Signal Raw Score Gate
            Section {
                HStack(spacing: 8) {
                    ForEach(confidencePresets, id: \.self) { preset in
                        let isSelected = Int(coordinator.settings.payload.minimumConfidencePercent.rounded()) == Int(preset)
                        Button {
                            coordinator.settings.payload.minimumConfidencePercent = preset
                        } label: {
                            Text("\(Int(preset))+")
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(isSelected ? palette.canvas : palette.primaryInk)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(isSelected ? palette.champagneGold : palette.elevatedSurface, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)

                VStack(alignment: .leading) {
                    HStack {
                        Text("Strong Signal Raw Score Floor")
                        Spacer()
                        Text("\(Int(coordinator.settings.payload.minimumConfidencePercent.rounded()))/100")
                            .monospacedDigit()
                            .fontWeight(.bold)
                            .foregroundStyle(palette.longEmerald)
                    }
                    Slider(value: $coordinator.settings.payload.minimumConfidencePercent, in: 55...95, step: 1)
                }

                if isAdvanced {
                    Stepper(
                        "Fine Adjust: \(Int(coordinator.settings.payload.minimumConfidencePercent.rounded()))",
                        value: $coordinator.settings.payload.minimumConfidencePercent,
                        in: 55...95,
                        step: 1
                    )
                    .font(.caption)
                }
            } header: {
                Text("Strong Signal Score Gate")
            } footer: {
                Text("Always evaluates the deterministic RAW confluence score (never calibrated probability). Setups below this floor are filtered out.")
            }

            // SECTION 2 — Risk:Reward & Targets
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Minimum R:R Floor")
                        Spacer()
                        Text("1 : \(String(format: "%.1f", coordinator.settings.payload.minimumRiskReward))")
                            .monospacedDigit()
                            .fontWeight(.semibold)
                    }
                    HStack(spacing: 6) {
                        ForEach([1.5, 2.0, 2.5, 3.0], id: \.self) { rr in
                            let selected = abs(coordinator.settings.payload.minimumRiskReward - rr) < 0.05
                            Button {
                                coordinator.settings.payload.minimumRiskReward = rr
                            } label: {
                                Text("1:\(String(format: "%.1f", rr))")
                                    .font(.caption2.weight(.bold).monospacedDigit())
                                    .foregroundStyle(selected ? palette.canvas : palette.primaryInk)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(selected ? palette.champagneGold : palette.elevatedSurface, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                    if isAdvanced {
                        Stepper(
                            "Fine R:R: 1 : \(String(format: "%.1f", coordinator.settings.payload.minimumRiskReward))",
                            value: $coordinator.settings.payload.minimumRiskReward,
                            in: 1.0...5.0,
                            step: 0.1
                        )
                        .font(.caption)
                    }
                }

                Toggle("Enable TP2 Target Generation", isOn: $coordinator.settings.payload.enableTP2Target)
                Toggle("Show \"Weak / Filtered Signals\" in Feed", isOn: $coordinator.settings.payload.showWeakFilteredSignals)
                Toggle("Max 1 Signal Per Correlated Cluster", isOn: Binding(
                    get: { coordinator.settings.payload.oneSignalPerCorrelatedCluster },
                    set: { newValue in
                        coordinator.settings.payload.oneSignalPerCorrelatedCluster = newValue
                        coordinator.recomputeCorrelations()
                    }
                ))

                if isAdvanced {
                    Picker("Level Calculation Mode", selection: $coordinator.settings.payload.levelCalculationMode) {
                        ForEach(TradeLevelMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }

                    if coordinator.settings.payload.levelCalculationMode == .fixedPercent {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Fixed Stop Loss %")
                                Spacer()
                                Text(String(format: "%.2f%%", coordinator.settings.payload.fixedStopLossPercent))
                                    .monospacedDigit()
                                    .fontWeight(.semibold)
                                    .foregroundStyle(palette.shortCrimson)
                            }
                            Slider(value: $coordinator.settings.payload.fixedStopLossPercent, in: 0.25...5.0, step: 0.25)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Fixed TP1 %")
                                Spacer()
                                Text(String(format: "%.2f%%", coordinator.settings.payload.fixedTP1Percent))
                                    .monospacedDigit()
                                    .fontWeight(.semibold)
                                    .foregroundStyle(palette.longEmerald)
                            }
                            Slider(value: $coordinator.settings.payload.fixedTP1Percent, in: 0.5...12.0, step: 0.25)
                        }

                        if coordinator.settings.payload.enableTP2Target {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Fixed TP2 %")
                                    Spacer()
                                    Text(String(format: "%.2f%%", coordinator.settings.payload.fixedTP2Percent))
                                        .monospacedDigit()
                                        .fontWeight(.semibold)
                                        .foregroundStyle(palette.macroIceBlue)
                                }
                                Slider(value: $coordinator.settings.payload.fixedTP2Percent, in: 1.0...20.0, step: 0.5)
                            }
                        }

                        HStack {
                            Text("Computed Fixed R:R")
                            Spacer()
                            Text(fixedRatioPreview)
                                .font(.subheadline.weight(.bold).monospacedDigit())
                                .foregroundStyle(palette.champagneGold)
                        }
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
                            Text(String(format: "%.2f%%", coordinator.settings.payload.maxStopLossPercentFXMetalsIndices))
                                .monospacedDigit()
                        }
                        Slider(value: $coordinator.settings.payload.maxStopLossPercentFXMetalsIndices, in: 0.5...3.0, step: 0.25)
                    }
                }
            } header: {
                Text("Risk:Reward & Feed Visibility")
            } footer: {
                Text(isAdvanced
                     ? "Structure / ATR anchors SL beyond institutional swing/OB invalidation. Fixed % Ratio sets exact percentage SL/TP distances around Entry Mid."
                     : "Enable \"Show Advanced Settings\" in Settings for Fixed % SL/TP tuning, custom concept filters, and custom calibration views.")
            }

            // SECTION 3 — Strategy & Concept Selection (Advanced)
            if isAdvanced {
                Section {
                    Picker("Selection Mode", selection: $coordinator.settings.payload.strategySelectionMode) {
                        ForEach(StrategySelectionMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }

                    if coordinator.settings.payload.strategySelectionMode == .defaultAll {
                        ForEach(StrategyGroup.allCases, id: \.self) { group in
                            Toggle(group.displayName, isOn: Binding(
                                get: { coordinator.settings.payload.enabledStrategyGroups.contains(group) },
                                set: { _ in coordinator.settings.toggleStrategyGroup(group) }
                            ))
                        }
                    } else {
                        Picker("Custom Match Rule", selection: $coordinator.settings.payload.customStrategyMatchRule) {
                            ForEach(CustomStrategyMatchRule.allCases) { rule in
                                Text(rule.rawValue).tag(rule)
                            }
                        }

                        if coordinator.settings.payload.customStrategyMatchRule == .anyWithMinConfluence {
                            Stepper(
                                "Min Aligned Confluence: \(coordinator.settings.payload.minimumAlignedStrategies)",
                                value: $coordinator.settings.payload.minimumAlignedStrategies,
                                in: 1...6,
                                step: 1
                            )
                        }

                        HStack {
                            Text("Selected Concepts (\(coordinator.settings.payload.selectedStrategyConcepts.count)/\(StrategyConcept.allCases.count))")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(palette.secondaryInk)
                            Spacer()
                            Button("Select All") {
                                coordinator.settings.payload.selectedStrategyConcepts = Set(StrategyConcept.allCases)
                            }
                            .font(.caption2.weight(.semibold))
                        }

                        ForEach(StrategyConcept.allCases) { concept in
                            Toggle(concept.displayName, isOn: Binding(
                                get: { coordinator.settings.payload.selectedStrategyConcepts.contains(concept) },
                                set: { _ in coordinator.settings.toggleStrategyConcept(concept) }
                            ))
                        }
                    }
                } header: {
                    Text("Advanced Strategy & Concept Selection")
                } footer: {
                    if coordinator.settings.payload.strategySelectionMode == .custom {
                        Text("When 1–2 custom concepts are selected, Confluence clamps the required count to match your selection so custom rules can fire cleanly.")
                    }
                }

                // SECTION 4 — Custom Calibration View Filter (Advanced — never alters Fixed Headline Win Rate)
                Section {
                    Picker("Win Definition", selection: $coordinator.settings.payload.calibrationWinDefinition) {
                        ForEach(CalibrationWinDefinition.allCases) { def in
                            Text(def.rawValue).tag(def)
                        }
                    }

                    Picker("Included Categories", selection: $coordinator.settings.payload.calibrationCategoryScope) {
                        ForEach(CalibrationCategoryScope.allCases) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Min Score Filter")
                            Spacer()
                            Text(coordinator.settings.payload.calibrationMinConfidencePercent > 0
                                 ? "≥\(Int(coordinator.settings.payload.calibrationMinConfidencePercent.rounded()))"
                                 : "Any")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(palette.macroIceBlue)
                        }
                        HStack(spacing: 6) {
                            ForEach(calibrationConfidencePresets, id: \.self) { val in
                                let selected = Int(coordinator.settings.payload.calibrationMinConfidencePercent.rounded()) == Int(val)
                                Button {
                                    coordinator.settings.payload.calibrationMinConfidencePercent = val
                                } label: {
                                    Text(val == 0 ? "Any" : "≥\(Int(val))")
                                        .font(.caption2.weight(.bold).monospacedDigit())
                                        .foregroundStyle(selected ? palette.canvas : palette.primaryInk)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 5)
                                        .background(selected ? palette.macroIceBlue : palette.elevatedSurface, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Picker("Min R:R Filter", selection: $coordinator.settings.payload.calibrationMinRiskReward) {
                        Text("Any R:R").tag(0.0)
                        Text("≥ 1 : 1.5").tag(1.5)
                        Text("≥ 1 : 2.0").tag(2.0)
                        Text("≥ 1 : 2.5").tag(2.5)
                        Text("≥ 1 : 3.0").tag(3.0)
                    }

                    HStack {
                        Text("Custom View Filter")
                            .font(.caption)
                            .foregroundStyle(palette.secondaryInk)
                        Spacer()
                        Text(coordinator.settings.buildCalibrationFilterConfig().summarySubtitle)
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(palette.champagneGold)
                    }
                } header: {
                    Text("Custom Calibration View (Filtered)")
                } footer: {
                    Text("Affects only the secondary Custom View card and strategy breakdown in Stats. The top Headline Win Rate card always stays fixed to Strong · TP1/TP2 · Filled v1.4+.")
                }
            }

            // SECTION 5 — Embedded AI Second-Opinion (Optional)
            Section {
                Toggle("Enable Gemini AI Judge", isOn: $coordinator.settings.payload.geminiEnabled)

                if isAdvanced {
                    Picker("Gemini Model", selection: $coordinator.settings.payload.geminiModel) {
                        ForEach(GeminiModelOption.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                }

                HStack {
                    SecureField(
                        hasGeminiKey ? "Gemini Key Encrypted in Keychain" : "Enter Gemini API Key",
                        text: $geminiKeyInput
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    Button("Save") {
                        Task {
                            try? await KeychainStore.shared.save(geminiKeyInput, for: .geminiAPIKey)
                            geminiKeyInput = ""
                            hasGeminiKey = await KeychainStore.shared.hasValue(for: .geminiAPIKey)
                        }
                    }
                    .disabled(geminiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if hasGeminiKey {
                    Button(role: .destructive) {
                        Task {
                            try? await KeychainStore.shared.delete(.geminiAPIKey)
                            hasGeminiKey = await KeychainStore.shared.hasValue(for: .geminiAPIKey)
                        }
                    } label: {
                        Label("Remove Saved Gemini Key", systemImage: "trash")
                    }
                }

                Stepper(
                    "Daily AI Call Limit: \(coordinator.settings.payload.geminiDailyCallLimit)",
                    value: $coordinator.settings.payload.geminiDailyCallLimit,
                    in: 5...100,
                    step: 5
                )

                HStack {
                    Text("Today's AI Usage")
                    Spacer()
                    Text("\(coordinator.geminiDailyCallsUsed) / \(coordinator.settings.payload.geminiDailyCallLimit)")
                        .monospacedDigit()
                        .foregroundStyle(palette.secondaryInk)
                }
            } header: {
                Text("AI Second-Opinion (Optional)")
            } footer: {
                Text("Confluence works 100% natively with AI OFF. When enabled, Gemini reviews new Strong Signals & Trap Alerts using strict JSON schema, but can NEVER override deterministic SL/TP levels, risk limits, or Crisis suppression.")
            }
        }
        .navigationTitle("Signal Rules & AI")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            hasGeminiKey = await KeychainStore.shared.hasValue(for: .geminiAPIKey)
        }
        .onChange(of: coordinator.settings.payload.calibrationWinDefinition) { _, _ in
            coordinator.recomputeCalibration()
        }
        .onChange(of: coordinator.settings.payload.calibrationCategoryScope) { _, _ in
            coordinator.recomputeCalibration()
        }
        .onChange(of: coordinator.settings.payload.calibrationMinConfidencePercent) { _, _ in
            coordinator.recomputeCalibration()
        }
        .onChange(of: coordinator.settings.payload.calibrationMinRiskReward) { _, _ in
            coordinator.recomputeCalibration()
        }
    }
}
