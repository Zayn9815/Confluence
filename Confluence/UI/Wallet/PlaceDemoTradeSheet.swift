import SwiftUI
import SignalEngine

/// Standalone Paper-Trading Place Trade sheet supporting segmented "Demo" vs "Log real trade",
/// "Target 1 | Target 2" exit choice, leverage/margin preview, stale-price confirmation (>60s),
/// and market-closed Limit suggestion (Mod 3 safeguards).
public struct PlaceDemoTradeSheet: View {
    public enum TradeMode: String, CaseIterable, Identifiable {
        case demo = "Demo"
        case real = "Log real trade"
        public var id: String { rawValue }
    }

    @Bindable var coordinator: MarketScannerCoordinator
    let palette: ConfluencePalette
    let prefilledSignal: TradeSignal?
    let initialSymbol: String
    let onOpenJournalDraft: ((JournalEntrySnapshot, Bool) -> Void)?
    let onDemoPlaced: ((DemoPosition) -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var mode: TradeMode = .demo
    @State private var selectedSymbol: String
    @State private var direction: TradeDirection
    @State private var orderType: DemoOrderType = .market
    @State private var entryText: String
    @State private var stopLossText: String
    @State private var target1Text: String
    @State private var target2Text: String
    @State private var exitTarget: DemoExitTarget = .target1
    @State private var riskPercent: Double
    @State private var allowStaleFill: Bool = false
    @State private var showStaleConfirm: Bool = false
    @State private var errorMessage: String? = nil

    public init(
        coordinator: MarketScannerCoordinator,
        palette: ConfluencePalette,
        prefilledSignal: TradeSignal? = nil,
        initialSymbol: String = "BTC/USDT",
        onOpenJournalDraft: ((JournalEntrySnapshot, Bool) -> Void)? = nil,
        onDemoPlaced: ((DemoPosition) -> Void)? = nil
    ) {
        self.coordinator = coordinator
        self.palette = palette
        self.prefilledSignal = prefilledSignal
        let sym = prefilledSignal?.symbol ?? initialSymbol
        self.initialSymbol = sym
        self.onOpenJournalDraft = onOpenJournalDraft
        self.onDemoPlaced = onDemoPlaced

        let asset = WatchlistDefaults.descriptor(for: sym)
        let mc = prefilledSignal?.marketClass ?? asset?.marketClass ?? .crypto
        let lv = prefilledSignal?.levels
        let liveRef = coordinator.livePriceService.latest(for: sym)?.price
            ?? lv?.entryMid
            ?? coordinator.lastKnownPrice(for: sym)
            ?? 100.0
        let prec = ChartPricePrecision.resolve(symbol: sym, marketClass: mc, referencePrice: liveRef)

        _selectedSymbol = State(initialValue: sym)
        _direction = State(initialValue: (prefilledSignal?.direction == .short) ? .short : .long)
        _entryText = State(initialValue: prec.format(lv?.entryMid ?? liveRef))
        _stopLossText = State(initialValue: prec.format(lv?.stopLoss ?? (liveRef * 0.99)))
        _target1Text = State(initialValue: prec.format(lv?.tp1 ?? (liveRef * 1.02)))
        _target2Text = State(initialValue: (lv?.isTP2Enabled == true) ? prec.format(lv!.tp2) : "")
        _riskPercent = State(initialValue: max(0.5, min(coordinator.settings.payload.defaultRiskPercent, 5.0)))
    }

    private var currentAsset: AssetDescriptor {
        WatchlistDefaults.descriptor(for: selectedSymbol) ?? WatchlistDefaults.assets[0]
    }

    public var body: some View {
        let asset = currentAsset
        let quote = coordinator.livePriceService.latest(for: asset.symbol)
        let leverage = DemoMarginSpec.defaultLeverage(for: asset.marketClass)
        let wallet = coordinator.demoWallet

        NavigationStack {
            Form {
                Section {
                    Picker("Mode", selection: $mode) {
                        ForEach(TradeMode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(mode == .demo
                         ? "Simulated paper trade using your virtual Demo Wallet. No real money or broker connection."
                         : "Records a personal real-trade journal entry for your own tracking. Confluence never places broker orders.")
                }

                Section("Setup") {
                    if prefilledSignal == nil {
                        Picker("Instrument", selection: $selectedSymbol) {
                            ForEach(WatchlistDefaults.assets, id: \.symbol) { item in
                                Text("\(item.symbol) · \(item.marketClass.displayName)").tag(item.symbol)
                            }
                        }
                        .onChange(of: selectedSymbol) { _, newSym in
                            coordinator.livePriceService.acquire(owner: "place_demo_sheet", symbols: [newSym])
                            if let ref = coordinator.livePriceService.latest(for: newSym)?.price ?? coordinator.lastKnownPrice(for: newSym) {
                                let mc = WatchlistDefaults.descriptor(for: newSym)?.marketClass ?? .crypto
                                let prec = ChartPricePrecision.resolve(symbol: newSym, marketClass: mc, referencePrice: ref)
                                entryText = prec.format(ref)
                                stopLossText = prec.format(direction == .long ? ref * 0.99 : ref * 1.01)
                                target1Text = prec.format(direction == .long ? ref * 1.02 : ref * 0.98)
                                target2Text = ""
                            }
                        }
                    } else {
                        HStack {
                            Text("Instrument")
                            Spacer()
                            Text("\(asset.symbol) (\(asset.marketClass.displayName))")
                                .fontWeight(.semibold)
                        }
                    }

                    Picker("Direction", selection: $direction) {
                        Text("Long").tag(TradeDirection.long)
                        Text("Short").tag(TradeDirection.short)
                    }
                    .pickerStyle(.segmented)

                    if mode == .demo {
                        Picker("Order type", selection: $orderType) {
                            Text("Market (live price)").tag(DemoOrderType.market)
                            Text("Limit (entry price)").tag(DemoOrderType.limit)
                        }
                        if let q = quote {
                            HStack {
                                Text("Live price")
                                Spacer()
                                Text("\(ChartPricePrecision.resolve(symbol: asset.symbol, marketClass: asset.marketClass, referencePrice: q.price).format(q.price)) · \(q.statusBadgeText())")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(palette.secondaryInk)
                            }
                        }
                    }
                }

                Section("Levels") {
                    if orderType == .limit || mode == .real {
                        levelField("Entry", text: $entryText)
                    }
                    levelField("Stop loss", text: $stopLossText)
                    levelField("Target 1", text: $target1Text)
                    levelField("Target 2 (optional)", text: $target2Text)

                    if mode == .demo {
                        Picker("Exit choice", selection: $exitTarget) {
                            Text("Target 1").tag(DemoExitTarget.target1)
                            Text("Target 2").tag(DemoExitTarget.target2)
                        }
                        .pickerStyle(.segmented)
                    }
                }

                if mode == .demo {
                    Section("Demo margin & risk") {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Risk per trade")
                                Spacer()
                                Text("\(String(format: "%.1f", riskPercent))% ($\(String(format: "%.2f", wallet.cashBalanceUSD * riskPercent / 100.0)))")
                                    .fontWeight(.semibold).monospacedDigit()
                            }
                            Slider(value: $riskPercent, in: 0.5...5.0, step: 0.5)
                        }
                        HStack {
                            Text("Free demo margin")
                            Spacer()
                            Text("$\(String(format: "%.2f", wallet.freeMarginUSD))").monospacedDigit()
                        }
                        HStack {
                            Text("Default leverage (\(asset.marketClass.displayName))")
                            Spacer()
                            Text("\(String(format: "%.0f", leverage))x").monospacedDigit()
                        }
                    }

                    if let err = errorMessage {
                        Section {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(palette.shortCrimson)
                            if showStaleConfirm {
                                Toggle("Confirm stale-price fill (>60s old)", isOn: $allowStaleFill)
                                    .font(.caption)
                            }
                        }
                    }

                    Section {
                        Button {
                            submitDemoTrade()
                        } label: {
                            Text("Place Demo \(direction.rawValue.uppercased())")
                                .frame(maxWidth: .infinity)
                                .fontWeight(.bold)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(direction == .long ? palette.longEmerald : palette.shortCrimson)
                    }
                } else {
                    Section {
                        Button {
                            openRealJournalEntry()
                        } label: {
                            Text("Continue to Trade Journal")
                                .frame(maxWidth: .infinity)
                                .fontWeight(.bold)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(palette.champagneGold)
                    }
                }
            }
            .navigationTitle(mode == .demo ? "Place Demo Trade" : "Log Real Trade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                coordinator.livePriceService.acquire(owner: "place_demo_sheet", symbols: [selectedSymbol])
            }
            .onDisappear {
                coordinator.livePriceService.release(owner: "place_demo_sheet")
            }
        }
    }

    private func levelField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
    }

    private func submitDemoTrade() {
        errorMessage = nil
        showStaleConfirm = false
        let asset = currentAsset
        guard let sl = Double(stopLossText), let t1 = Double(target1Text) else {
            errorMessage = "Enter valid numbers for Stop loss and Target 1."
            return
        }
        let t2Trim = target2Text.trimmingCharacters(in: .whitespaces)
        let t2: Double? = t2Trim.isEmpty ? nil : Double(t2Trim)
        if !t2Trim.isEmpty && t2 == nil {
            errorMessage = "Target 2 must be a valid number."
            return
        }
        let entry = Double(entryText) ?? coordinator.livePriceService.latest(for: asset.symbol)?.price ?? 0
        let tf = prefilledSignal?.timeframe ?? coordinator.settings.payload.entryTimeframe
        let now = Date().timeIntervalSince1970
        let expiry = now + Double(PassiveOutcomeEvaluator.defaultFillWindowBars(for: tf)) * tf.seconds

        let req = DemoOrderRequest(
            signalId: prefilledSignal?.id,
            symbol: asset.symbol,
            marketClass: asset.marketClass,
            timeframe: tf,
            direction: direction,
            orderType: orderType,
            entryPrice: entry,
            entryLow: prefilledSignal?.levels?.entryLow ?? entry,
            entryHigh: prefilledSignal?.levels?.entryHigh ?? entry,
            stopLoss: sl,
            target1: t1,
            target2: t2,
            exitTarget: (exitTarget == .target2 && t2 == nil) ? .target1 : exitTarget,
            riskPercent: riskPercent,
            limitExpiryEpochSeconds: orderType == .limit ? expiry : nil,
            allowStalePriceFill: allowStaleFill,
            feesEnabled: coordinator.settings.payload.demoWalletFeesEnabled
        )

        switch coordinator.placeDemoOrder(req) {
        case .success(let pos):
            dismiss()
            onDemoPlaced?(pos)
        case .failure(let err):
            errorMessage = err.userMessage
            if case .staleLiveQuote = err {
                showStaleConfirm = true
            } else if case .marketClosed(_, true) = err {
                orderType = .limit
            }
        }
    }

    private func openRealJournalEntry() {
        let asset = currentAsset
        let entry = Double(entryText) ?? coordinator.livePriceService.latest(for: asset.symbol)?.price ?? 0
        let sl = Double(stopLossText) ?? entry * 0.99
        let t1 = Double(target1Text) ?? entry * 1.02
        let t2 = Double(target2Text)
        let existing = prefilledSignal.flatMap { coordinator.journalEntry(forSignalFingerprint: $0.fingerprint) }
        let draft = existing ?? JournalEntrySnapshot(
            signalFingerprint: prefilledSignal?.fingerprint,
            symbol: asset.symbol,
            marketClass: asset.marketClass,
            timeframe: prefilledSignal?.timeframe ?? coordinator.settings.payload.entryTimeframe,
            direction: direction,
            plannedEntry: entry,
            stopLoss: sl,
            tp1: t1,
            tp2: t2
        )
        dismiss()
        onOpenJournalDraft?(draft, existing != nil)
    }
}
