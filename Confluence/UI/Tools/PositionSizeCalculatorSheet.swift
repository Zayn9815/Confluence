import SwiftUI
import SignalEngine

/// Interactive deterministic Position Size Calculator sheet launched from any `SignalCardView`.
/// Supports USD accounts natively and provides a manual USD -> Account Currency conversion rate field
/// for non-USD accounts, plus editable Index CFD & Gold contract specifications.
public struct PositionSizeCalculatorSheet: View {
    public let signal: TradeSignal
    public let activeLevels: TradeLevels
    @Bindable public var coordinator: MarketScannerCoordinator
    public let palette: ConfluencePalette

    @Environment(\.dismiss) private var dismiss

    @State private var balanceText: String
    @State private var riskPercentText: String
    @State private var accountCurrency: AccountCurrency
    @State private var conversionRateText: String
    @State private var entryText: String
    @State private var stopText: String
    @State private var contractSizeText: String
    @State private var pointValueText: String

    public init(
        signal: TradeSignal,
        activeLevels: TradeLevels,
        coordinator: MarketScannerCoordinator,
        palette: ConfluencePalette
    ) {
        self.signal = signal
        self.activeLevels = activeLevels
        self.coordinator = coordinator
        self.palette = palette

        let dec = PriceFormatHelper.decimals(for: signal.symbol, marketClass: signal.marketClass, referencePrice: activeLevels.entryMid)
        let spec = coordinator.settings.contractSpec(for: signal.symbol, marketClass: signal.marketClass)
        _balanceText = State(initialValue: String(format: "%.0f", coordinator.settings.payload.defaultAccountBalance))
        _riskPercentText = State(initialValue: String(format: "%.2f", coordinator.settings.payload.defaultRiskPercent))
        _accountCurrency = State(initialValue: coordinator.settings.payload.defaultAccountCurrency)
        _conversionRateText = State(initialValue: String(format: "%.4f", coordinator.settings.payload.manualUSDToAccountRate))
        _entryText = State(initialValue: PriceFormatHelper.format(activeLevels.entryMid, decimals: dec))
        _stopText = State(initialValue: PriceFormatHelper.format(activeLevels.stopLoss, decimals: dec))
        _contractSizeText = State(initialValue: String(format: "%.2f", spec.contractSize))
        _pointValueText = State(initialValue: String(format: "%.2f", spec.pointValue))
    }

    private var computedResult: PositionSizeResult? {
        guard let bal = Double(balanceText),
              let riskPct = Double(riskPercentText),
              let entry = Double(entryText),
              let stop = Double(stopText) else { return nil }
        let rate = (accountCurrency == .usd) ? 1.0 : (Double(conversionRateText) ?? 1.0)
        let cSize = Double(contractSizeText) ?? InstrumentContractSpec.defaultSpec(for: signal.symbol, marketClass: signal.marketClass).contractSize
        let pVal = Double(pointValueText) ?? 1.0
        let input = PositionSizeInput(
            symbol: signal.symbol,
            marketClass: signal.marketClass,
            entryPrice: entry,
            stopLossPrice: stop,
            tp1Price: activeLevels.tp1,
            accountBalance: bal,
            riskPercent: riskPct,
            accountCurrency: accountCurrency,
            usdToAccountRate: rate,
            contractSpec: InstrumentContractSpec(contractSize: cSize, pointValue: pVal)
        )
        return PositionSizeCalculator.calculate(input)
    }

    private var showContractSpecEditor: Bool {
        signal.marketClass == .indices || signal.marketClass == .metals
    }

    public var body: some View {
        NavigationStack {
            Form {
                if let res = computedResult {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(formatQuantity(res.primaryQuantity))
                                    .font(.largeTitle.weight(.bold).monospacedDigit())
                                    .foregroundStyle(palette.champagneGold)
                                Text(res.primaryUnitLabel)
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(palette.primaryInk)
                                Spacer()
                            }

                            if let sec = res.secondaryQuantity, let secLabel = res.secondaryUnitLabel {
                                Text("= \(formatQuantity(sec)) \(secLabel)")
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(palette.secondaryInk)
                            }

                            Divider().overlay(palette.border)

                            HStack {
                                resultPill("RISK", "\(accountCurrency.symbolPrefix)\(String(format: "%.2f", res.riskAmountAccount))", palette.shortCrimson)
                                if let rw = res.estimatedReward1Account {
                                    resultPill("TP1 EST.", "+\(accountCurrency.symbolPrefix)\(String(format: "%.2f", rw))", palette.longEmerald)
                                }
                                resultPill("NOTIONAL", "$\(String(format: "%.0f", res.estimatedNotionalUSD))", palette.macroIceBlue)
                            }

                            Text(res.formulaSummary)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(palette.secondaryInk)
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("\(signal.symbol) · \(signal.direction.rawValue.uppercased()) Position Size")
                    } footer: {
                        Text(res.disclaimer)
                            .foregroundStyle(palette.trapAmber)
                    }
                } else {
                    Section("Position Size") {
                        Text("Enter valid positive account balance, risk %, entry, and stop-loss prices (entry != stop loss).")
                            .font(.caption)
                            .foregroundStyle(palette.shortCrimson)
                    }
                }

                Section("Account & Risk") {
                    Picker("Account Currency", selection: $accountCurrency) {
                        ForEach(AccountCurrency.allCases) { cur in
                            Text(cur.rawValue).tag(cur)
                        }
                    }

                    if accountCurrency != .usd {
                        HStack {
                            Text("1 USD = (\(accountCurrency.rawValue))")
                            Spacer()
                            TextField("e.g. 0.92", text: $conversionRateText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                        }
                    }

                    HStack {
                        Text("Account Balance (\(accountCurrency.rawValue))")
                        Spacer()
                        TextField("10000", text: $balanceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }

                    HStack {
                        Text("Risk Per Trade (%)")
                        Spacer()
                        TextField("1.0", text: $riskPercentText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }

                    HStack(spacing: 8) {
                        ForEach(["0.25", "0.50", "1.00", "2.00"], id: \.self) { preset in
                            Button("\(preset)%") {
                                riskPercentText = preset
                            }
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(palette.elevatedSurface, in: Capsule())
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                }

                Section("Setup Prices") {
                    HStack {
                        Text("Entry Price")
                        Spacer()
                        TextField("Entry", text: $entryText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }
                    HStack {
                        Text("Stop Loss")
                        Spacer()
                        TextField("SL", text: $stopText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }
                }

                if showContractSpecEditor {
                    Section {
                        HStack {
                            Text(signal.marketClass == .metals ? "Oz per Lot" : "Contract Size")
                            Spacer()
                            TextField("1.0", text: $contractSizeText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                        }
                        if signal.marketClass == .indices {
                            HStack {
                                Text("USD Point Value")
                                Spacer()
                                TextField("1.0", text: $pointValueText)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .monospacedDigit()
                            }
                        }
                    } header: {
                        Text("Broker Contract Spec (\(signal.symbol))")
                    } footer: {
                        Text("Default: 1.0 contract × $1.00/pt for US500/NAS100 CFDs, 100 oz/lot for XAU/USD. Saved per symbol when you tap Save Defaults.")
                    }
                }
            }
            .navigationTitle("Position Size Calculator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Defaults") {
                        persistDefaults()
                        dismiss()
                    }
                }
            }
        }
    }

    private func persistDefaults() {
        if let bal = Double(balanceText), bal > 0 {
            coordinator.settings.payload.defaultAccountBalance = bal
        }
        if let risk = Double(riskPercentText), risk > 0 {
            coordinator.settings.payload.defaultRiskPercent = risk
        }
        coordinator.settings.payload.defaultAccountCurrency = accountCurrency
        if let rate = Double(conversionRateText), rate > 0 {
            coordinator.settings.payload.manualUSDToAccountRate = rate
        }
        if showContractSpecEditor, let cs = Double(contractSizeText), cs > 0 {
            let pv = Double(pointValueText) ?? 1.0
            coordinator.settings.setContractSpec(
                InstrumentContractSpec(contractSize: cs, pointValue: max(pv, 1e-6)),
                for: signal.symbol
            )
        }
    }

    private func resultPill(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(palette.tertiaryInk)
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatQuantity(_ value: Double) -> String {
        if value >= 1000 { return String(format: "%.1f", value) }
        if value >= 10 { return String(format: "%.2f", value) }
        if value >= 0.1 { return String(format: "%.3f", value) }
        return String(format: "%.4f", value)
    }
}
