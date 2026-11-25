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
                        Text("Minimum strength threshold")
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
                        "Fine adjust: \(Int(coordinator.settings.payload.minimumConfidencePercent.rounded()))",
                        value: $coordinator.settings.payload.minimumConfidencePercent,
                        in: 55...95,
                        step: 1
                    )
                    .font(.caption)
                }
            } header: {
                SettingsSectionHeader(SettingHelpKey.strongSignalScoreGate.copy.label, helpKey: .strongSignalScoreGate)
            } footer: {
                Text(SettingHelpKey.strongSignalScoreGate.copy.subtitle)
            }

            // SECTION 2 — Reward-to-Risk & Targets
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(SettingHelpKey.minimumRewardRatio.copy.label)
                        InfoButton(.minimumRewardRatio)
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
                            "Fine ratio: 1 : \(String(format: "%.1f", coordinator.settings.payload.minimumRiskReward))",
                            value: $coordinator.settings.payload.minimumRiskReward,
                            in: 1.0...5.0,
                            step: 0.1
                        )
                        .font(.caption)
                    }
                }

                Toggle(isOn: $coordinator.settings.payload.enableTP2Target) {
                    HStack(spacing: 6) {
                        Text(SettingHelpKey.enableTarget2.copy.label)
                        InfoButton(.enableTarget2)
                    }
                }
                Toggle(isOn: $coordinator.settings.payload.showWeakFilteredSignals) {
                    HStack(spacing: 6) {
                        Text(SettingHelpKey.showWeakFilteredSignals.copy.label)
                        InfoButton(.showWeakFilteredSignals)
                    }
                }
                Toggle(isOn: Binding(
                    get: { coordinator.settings.payload.oneSignalPerCorrelatedCluster },
                    set: { newValue in
                        coordinator.settings.payload.oneSignalPerCorrelatedCluster = newValue
                        coordinator.recomputeCorrelations()
                    }
                )) {
                    HStack(spacing: 6) {
                        Text(SettingHelpKey.oneSignalPerCorrelatedCluster.copy.label)
                        InfoButton(.oneSignalPerCorrelatedCluster)
                    }
                }

                if isAdvanced {
                    HStack(spacing: 6) {
                        Picker(SettingHelpKey.levelCalculationMode.copy.label, selection: $coordinator.settings.payload.levelCalculationMode) {
                            ForEach(TradeLevelMode.allCases) { mode in
                                Text(SettingHelpKey.displayLabel(for: mode)).tag(mode)
                            }
                        }
                        InfoButton(.levelCalculationMode)
                    }

                    if coordinator.settings.payload.levelCalculationMode == .fixedPercent {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Fixed Stop loss %")
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
                                Text("Fixed Target 1 %")
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
                                    Text("Fixed Target 2 %")
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
                            Text("Computed reward-to-risk")
                            Spacer()
                            Text(fixedRatioPreview)
                                .font(.subheadline.weight(.bold).monospacedDigit())
                                .foregroundStyle(palette.champagneGold)
                        }
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Max Stop loss % (Crypto / Stocks)")
                            InfoButton(.maxStopLossCap)
                            Spacer()
                            Text(String(format: "%.1f%%", coordinator.settings.payload.maxStopLossPercentCryptoStocks))
                                .monospacedDigit()
                        }
                        Slider(value: $coordinator.settings.payload.maxStopLossPercentCryptoStocks, in: 1.0...6.0, step: 0.5)
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Max Stop loss % (Forex / Gold / Indices)")
                            Spacer()
                            Text(String(format: "%.2f%%", coordinator.settings.payload.maxStopLossPercentFXMetalsIndices))
                                .monospacedDigit()
                        }
                        Slider(value: $coordinator.settings.payload.maxStopLossPercentFXMetalsIndices, in: 0.5...3.0, step: 0.25)
                    }
                }
            } header: {
                Text("Risk, Targets & Feed Visibility")
            } footer: {
                Text(isAdvanced
                     ? SettingHelpKey.levelCalculationMode.copy.subtitle
                     : "Turn on \"Show extra controls\" in Settings for fixed-percentage levels, custom rule filters, and custom stats views.")
            }

            // SECTION 3 — Strategy & Concept Selection (Advanced)
            if isAdvanced {
                Section {
                    Picker("Rule mix", selection: $coordinator.settings.payload.strategySelectionMode) {
                        ForEach(StrategySelectionMode.allCases) { mode in
                            Text(SettingHelpKey.displayLabel(for: mode)).tag(mode)
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
                        Picker("Custom match rule", selection: $coordinator.settings.payload.customStrategyMatchRule) {
                            ForEach(CustomStrategyMatchRule.allCases) { rule in
                                Text(SettingHelpKey.displayLabel(for: rule)).tag(rule)
                            }
                        }

                        if coordinator.settings.payload.customStrategyMatchRule == .anyWithMinConfluence {
                            Stepper(
                                "Minimum aligned rules: \(coordinator.settings.payload.minimumAlignedStrategies)",
                                value: $coordinator.settings.payload.minimumAlignedStrategies,
                                in: 1...6,
                                step: 1
                            )
                        }

                        HStack {
                            Text("Selected rules (\(coordinator.settings.payload.selectedStrategyConcepts.count)/\(StrategyConcept.allCases.count))")
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
                    SettingsSectionHeader(SettingHelpKey.strategySelection.copy.label, helpKey: .strategySelection)
                } footer: {
                    if coordinator.settings.payload.strategySelectionMode == .custom {
                        Text("When 1–2 custom rules are selected, Confluence matches the required count to your selection so custom rules can fire cleanly.")
                    }
                }

                // SECTION 4 — Custom Calibration View Filter (Advanced — never alters Fixed Headline Win Rate)
                Section {
                    Picker("Win rule", selection: $coordinator.settings.payload.calibrationWinDefinition) {
                        ForEach(CalibrationWinDefinition.allCases) { def in
                            Text(SettingHelpKey.displayLabel(for: def)).tag(def)
                        }
                    }

                    Picker("Included setups", selection: $coordinator.settings.payload.calibrationCategoryScope) {
                        ForEach(CalibrationCategoryScope.allCases) { scope in
                            Text(SettingHelpKey.displayLabel(for: scope)).tag(scope)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Minimum strength filter")
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

                    Picker("Minimum reward-to-risk filter", selection: $coordinator.settings.payload.calibrationMinRiskReward) {
                        Text("Any ratio").tag(0.0)
                        Text("≥ 1 : 1.5").tag(1.5)
                        Text("≥ 1 : 2.0").tag(2.0)
                        Text("≥ 1 : 2.5").tag(2.5)
                        Text("≥ 1 : 3.0").tag(3.0)
                    }

                    HStack {
                        Text("Active filter")
                            .font(.caption)
                            .foregroundStyle(palette.secondaryInk)
                        Spacer()
                        Text(coordinator.settings.buildCalibrationFilterConfig().summarySubtitle)
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(palette.champagneGold)
                    }
                } header: {
                    SettingsSectionHeader(SettingHelpKey.customCalibrationView.copy.label, helpKey: .customCalibrationView)
                } footer: {
                    Text(SettingHelpKey.customCalibrationView.copy.subtitle)
                }
            }

            // SECTION 5 — Embedded AI Second-Opinion (Optional · Always Visible Provider & Model Picker)
            Section {
                Toggle(isOn: $coordinator.settings.payload.geminiEnabled) {
                    HStack(spacing: 6) {
                        Text(SettingHelpKey.aiSecondOpinion.copy.label)
                        InfoButton(.aiSecondOpinion)
                    }
                }

                HStack(spacing: 6) {
                    Picker("Provider", selection: Binding(
                        get: { coordinator.settings.payload.aiProvider },
                        set: { newProvider in
                            coordinator.settings.payload.aiProvider = newProvider
                            let models = coordinator.availableModels(for: newProvider)
                            if !models.contains(where: { $0.id == coordinator.settings.payload.aiModelID }) {
                                coordinator.settings.payload.aiModelID = newProvider.defaultModelID
                            }
                            Task {
                                hasGeminiKey = await KeychainStore.shared.hasValue(for: newProvider.keychainKey)
                            }
                        }
                    )) {
                        ForEach(AIProviderOption.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    InfoButton(.aiProviderAndModel)
                }

                let activeProvider = coordinator.settings.payload.aiProvider
                let models = coordinator.availableModels(for: activeProvider)
                Picker("Model", selection: $coordinator.settings.payload.aiModelID) {
                    ForEach(models) { m in
                        Text(m.displayName).tag(m.id)
                    }
                    if !models.contains(where: { $0.id == coordinator.settings.payload.aiModelID }) {
                        Text(coordinator.settings.payload.aiModelID).tag(coordinator.settings.payload.aiModelID)
                    }
                }

                HStack {
                    SecureField(
                        hasGeminiKey ? "\(activeProvider.shortLabel) key saved (••••)" : "Enter \(activeProvider.shortLabel) personal key",
                        text: $geminiKeyInput
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    Button("Save") {
                        Task {
                            try? await KeychainStore.shared.save(geminiKeyInput, for: activeProvider.keychainKey)
                            geminiKeyInput = ""
                            hasGeminiKey = await KeychainStore.shared.hasValue(for: activeProvider.keychainKey)
                        }
                    }
                    .disabled(geminiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Button {
                    Task { await coordinator.testSelectedAIProviderKey() }
                } label: {
                    HStack {
                        Label("Test key & list models", systemImage: "sparkles")
                        Spacer()
                        if coordinator.isTestingAIKey {
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .disabled(coordinator.isTestingAIKey)

                if let msg = coordinator.aiKeyTestMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(msg.hasPrefix("Connected") ? palette.longEmerald : palette.trapAmber)
                }

                if let note = activeProvider.rateLimitNote {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(palette.secondaryInk)
                }

                if hasGeminiKey {
                    Button(role: .destructive) {
                        Task {
                            try? await KeychainStore.shared.delete(activeProvider.keychainKey)
                            hasGeminiKey = await KeychainStore.shared.hasValue(for: activeProvider.keychainKey)
                            coordinator.aiKeyTestMessage = nil
                        }
                    } label: {
                        Label("Remove saved \(activeProvider.shortLabel) key", systemImage: "trash")
                    }
                }

                HStack(spacing: 6) {
                    Stepper(
                        "Daily limit: \(coordinator.settings.payload.geminiDailyCallLimit)",
                        value: $coordinator.settings.payload.geminiDailyCallLimit,
                        in: 5...100,
                        step: 5
                    )
                    InfoButton(.sharedDailyAILimit)
                }

                HStack {
                    Text("Used today (all providers)")
                    Spacer()
                    Text("\(coordinator.geminiDailyCallsUsed) / \(coordinator.settings.payload.geminiDailyCallLimit)")
                        .monospacedDigit()
                        .foregroundStyle(palette.secondaryInk)
                }
            } header: {
                Text("Optional Review Assistant (AI)")
            } footer: {
                Text("Confluence works 100% natively with this off. When enabled, your selected provider reviews new Strong setups, Trap warnings, and News setups, but can NEVER override deterministic Stop loss, Target 1, Target 2, risk limits, or Crisis suppression.")
            }
        }
        .navigationTitle("Signal Rules & AI")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let activeProvider = coordinator.settings.payload.aiProvider
            hasGeminiKey = await KeychainStore.shared.hasValue(for: activeProvider.keychainKey)
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
