import SwiftUI
import SignalEngine

/// Complete drill-down Settings screen for Signal Generation, Risk/TP Ratios,
/// Confidence % Presets, Strategy Selection Modes, and Calibration Win-Rate Counting Rules.
public struct SignalRulesSettingsView: View {
    @Bindable var coordinator: MarketScannerCoordinator
    let palette: ConfluencePalette

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
        Form {
            // SECTION 1 — Risk:Reward & SL/TP Controls
            Section {
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

                Toggle("Enable TP2 Target Generation", isOn: $coordinator.settings.payload.enableTP2Target)

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
                    Stepper(
                        "Fine R:R: 1 : \(String(format: "%.1f", coordinator.settings.payload.minimumRiskReward))",
                        value: $coordinator.settings.payload.minimumRiskReward,
                        in: 1.0...5.0,
                        step: 0.1
                    )
                    .font(.caption)
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
            } header: {
                Text("Risk:Reward & SL/TP Controls")
            } footer: {
                Text("Structure / ATR anchors SL beyond institutional swing/OB invalidation. Fixed % Ratio sets exact percentage SL/TP distances around Entry Mid.")
            }

            // SECTION 2 — Probability / Confidence % Gate for Strong Signals
            Section {
                HStack(spacing: 8) {
                    ForEach(confidencePresets, id: \.self) { preset in
                        let isSelected = Int(coordinator.settings.payload.minimumConfidencePercent.rounded()) == Int(preset)
                        Button {
                            coordinator.settings.payload.minimumConfidencePercent = preset
                        } label: {
                            Text("\(Int(preset))%+")
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
                        Text("Strong Signal Confidence Floor")
                        Spacer()
                        Text("\(Int(coordinator.settings.payload.minimumConfidencePercent.rounded()))%+")
                            .monospacedDigit()
                            .fontWeight(.bold)
                            .foregroundStyle(palette.longEmerald)
                    }
                    Slider(value: $coordinator.settings.payload.minimumConfidencePercent, in: 55...95, step: 1)
                }

                Stepper(
                    "Fine Adjust: \(Int(coordinator.settings.payload.minimumConfidencePercent.rounded()))%",
                    value: $coordinator.settings.payload.minimumConfidencePercent,
                    in: 55...95,
                    step: 1
                )
                .font(.caption)
            } header: {
                Text("Strong Signal Confidence Gate")
            } footer: {
                Text("Only setups meeting or exceeding this threshold are promoted into Strong Signals. Lower-confidence setups go to Weak / Filtered (or are hidden if disabled below).")
            }

            // SECTION 3 — Strategy & Concept Selection Mode
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
                } else if coordinator.settings.payload.strategySelectionMode == .custom {
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
                } else {
                    // Random Subset Mode info
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Each live scan deterministically selects 3–6 real strategies from your enabled groups for unbiased discovery (zero fabricated signals).")
                            .font(.caption)
                            .foregroundStyle(palette.secondaryInk)
                        if !coordinator.lastRandomSubsetConcepts.isEmpty {
                            Text("Last Scan Subset: \(coordinator.lastRandomSubsetConcepts.map(\.displayName).joined(separator: ", "))")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(palette.champagneGold)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Strategy & Concept Selection")
            } footer: {
                if coordinator.settings.payload.strategySelectionMode == .custom {
                    Text("When 1–2 custom concepts are selected, Confluence automatically clamps the required count to match your selection so custom rules can fire cleanly.")
                }
            }

            // SECTION 4 — Resolved Win Rate & Calibration Counting Rules
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
                        Text("Min Confidence Filter")
                        Spacer()
                        Text(coordinator.settings.payload.calibrationMinConfidencePercent > 0
                             ? "≥\(Int(coordinator.settings.payload.calibrationMinConfidencePercent.rounded()))%"
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
                                Text(val == 0 ? "Any" : "≥\(Int(val))%")
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
                    Text("Active Stats Filter")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryInk)
                    Spacer()
                    Text(coordinator.settings.buildCalibrationFilterConfig().summarySubtitle)
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(palette.champagneGold)
                }
            } header: {
                Text("Resolved Win Rate & Calibration Rules")
            } footer: {
                Text("Controls what counts in the Calibration Stats tab. In TP2 Only mode, TP1 hits are tracked separately as TP1 Partial (excluded from the Win/Loss denominator).")
            }

            // SECTION 5 — Feed Visibility & Crisis Guard
            Section("Safety & Feed Visibility") {
                Toggle("Show \"Weak / Filtered Signals\" in Feed", isOn: $coordinator.settings.payload.showWeakFilteredSignals)
                Toggle("Auto-Suppress Alerts in Crisis Regime", isOn: $coordinator.settings.payload.autoSuppressCrisisAlerts)
            }
        }
        .navigationTitle("Signal Rules & Win-Rate")
        .navigationBarTitleDisplayMode(.inline)
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
