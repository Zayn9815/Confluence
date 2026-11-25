import SwiftUI
import SignalEngine

/// Settings Category 3: Markets & Data (Enabled Markets, API Keys, Feeds, Calendar/News/Positioning & Background Refresh).
public struct MarketsFeedsSettingsView: View {
    @Bindable var coordinator: MarketScannerCoordinator
    let palette: ConfluencePalette

    @State private var twelveDataKeyInput = ""
    @State private var finnhubKeyInput = ""
    @State private var hasTwelveDataKey = false
    @State private var hasFinnhubKey = false

    public init(coordinator: MarketScannerCoordinator, palette: ConfluencePalette) {
        self.coordinator = coordinator
        self.palette = palette
    }

    public var body: some View {
        Form {
            Section {
                ForEach(MarketClass.allCases, id: \.self) { market in
                    Toggle(market.displayName, isOn: Binding(
                        get: { coordinator.settings.payload.enabledMarkets.contains(market) },
                        set: { _ in coordinator.settings.toggleMarket(market) }
                    ))
                }
            } header: {
                SettingsSectionHeader(SettingHelpKey.enabledMarkets.copy.label, helpKey: .enabledMarkets)
            }

            if coordinator.settings.payload.showAdvancedSettings {
                Section {
                    Picker("Forex / Gold / Stocks / Indices", selection: $coordinator.settings.payload.tradFiProviderPreference) {
                        ForEach(TradFiProviderPreference.allCases) { pref in
                            Text(SettingHelpKey.displayLabel(for: pref)).tag(pref)
                        }
                    }

                    Picker("Crypto data source", selection: $coordinator.settings.payload.cryptoPrimaryExchange) {
                        ForEach(CryptoExchangePreference.allCases) { venue in
                            Text(SettingHelpKey.displayLabel(for: venue)).tag(venue)
                        }
                    }
                } header: {
                    SettingsSectionHeader(SettingHelpKey.advancedProviderOverrides.copy.label, helpKey: .advancedProviderOverrides)
                } footer: {
                    Text(SettingHelpKey.advancedProviderOverrides.copy.subtitle)
                }
            }

            Section {
                HStack {
                    SecureField(
                        hasTwelveDataKey ? "Twelve Data key saved (••••)" : "Enter Twelve Data personal key",
                        text: $twelveDataKeyInput
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    Button("Save") {
                        Task {
                            try? await KeychainStore.shared.save(twelveDataKeyInput, for: .twelveDataAPIKey)
                            twelveDataKeyInput = ""
                            hasTwelveDataKey = await KeychainStore.shared.hasValue(for: .twelveDataAPIKey)
                        }
                    }
                    .disabled(twelveDataKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Button {
                    Task { await coordinator.testTwelveDataKeyAndQuota() }
                } label: {
                    HStack {
                        Label("Test key & check daily limit", systemImage: "gauge.with.dots.needle.67percent")
                        Spacer()
                        if coordinator.isTestingTwelveData {
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .disabled(coordinator.isTestingTwelveData)

                if let msg = coordinator.twelveDataTestMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(msg.hasPrefix("Connected") ? palette.longEmerald : palette.trapAmber)
                }

                HStack {
                    Text("Calls used today")
                    Spacer()
                    Text("\(coordinator.twelveDataLocalDailyUsed) / 780")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(palette.secondaryInk)
                }

                if hasTwelveDataKey {
                    Button(role: .destructive) {
                        Task {
                            try? await KeychainStore.shared.delete(.twelveDataAPIKey)
                            hasTwelveDataKey = await KeychainStore.shared.hasValue(for: .twelveDataAPIKey)
                            coordinator.twelveDataQuota = nil
                            coordinator.twelveDataTestMessage = nil
                        }
                    } label: {
                        Label("Remove saved Twelve Data key", systemImage: "trash")
                    }
                }
            } header: {
                SettingsSectionHeader(SettingHelpKey.twelveDataKey.copy.label, helpKey: .twelveDataKey)
            } footer: {
                Text(SettingHelpKey.twelveDataKey.copy.subtitle)
            }

            Section {
                Toggle("Economic calendar", isOn: $coordinator.settings.payload.economicCalendarEnabled)
                Toggle("Breaking news radar", isOn: $coordinator.settings.payload.breakingNewsRadarEnabled)
                Toggle("Market positioning tracker", isOn: $coordinator.settings.payload.positioningFeedsEnabled)

                if coordinator.settings.payload.showAdvancedSettings {
                    HStack {
                        SecureField(
                            hasFinnhubKey ? "Finnhub key saved (••••)" : "Optional Finnhub news key",
                            text: $finnhubKeyInput
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        Button("Save") {
                            Task {
                                try? await KeychainStore.shared.save(finnhubKeyInput, for: .finnhubAPIKey)
                                finnhubKeyInput = ""
                                hasFinnhubKey = await KeychainStore.shared.hasValue(for: .finnhubAPIKey)
                            }
                        }
                        .disabled(finnhubKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    Button {
                        Task { await coordinator.refreshCOTManually() }
                    } label: {
                        Label("Refresh weekly positioning report now", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            } header: {
                SettingsSectionHeader(SettingHelpKey.macroNewsPositioningFeeds.copy.label, helpKey: .macroNewsPositioningFeeds)
            }

            Section {
                HStack(spacing: 6) {
                    Picker(SettingHelpKey.tradFiLiveFeed.copy.label, selection: Binding(
                        get: { coordinator.settings.payload.tradFiLiveFeedMode },
                        set: { newVal in
                            coordinator.settings.payload.tradFiLiveFeedMode = newVal
                            coordinator.syncLiveFeedModesFromSettings()
                        }
                    )) {
                        ForEach(TradFiLiveFeedMode.allCases) { mode in
                            Text(mode.displayLabel).tag(mode)
                        }
                    }
                    InfoButton(.tradFiLiveFeed)
                }

                HStack(spacing: 6) {
                    Picker(SettingHelpKey.cryptoLiveFeed.copy.label, selection: Binding(
                        get: { coordinator.settings.payload.cryptoLiveFeedMode },
                        set: { newVal in
                            coordinator.settings.payload.cryptoLiveFeedMode = newVal
                            coordinator.syncLiveFeedModesFromSettings()
                        }
                    )) {
                        ForEach(CryptoLiveFeedMode.allCases) { mode in
                            Text(mode.displayLabel).tag(mode)
                        }
                    }
                    InfoButton(.cryptoLiveFeed)
                }

                HStack(spacing: 6) {
                    Picker(SettingHelpKey.defaultChartView.copy.label, selection: $coordinator.settings.payload.defaultChartViewMode) {
                        ForEach(DefaultChartViewMode.allCases) { mode in
                            Text(mode.displayLabel).tag(mode)
                        }
                    }
                    InfoButton(.defaultChartView)
                }

                Toggle(isOn: $coordinator.settings.payload.showTradingViewOption) {
                    HStack(spacing: 6) {
                        Text(SettingHelpKey.showTradingViewOption.copy.label)
                        InfoButton(.showTradingViewOption)
                    }
                }
            } header: {
                Text("Live Price Feeds & Chart View")
            } footer: {
                Text("Live feeds run only while the app is open (up to 8 symbols). Twelve Data is never used for live streaming or polling.")
            }

            Section {
                Toggle(isOn: $coordinator.settings.payload.scanOnOpenEnabled) {
                    HStack(spacing: 6) {
                        Text(SettingHelpKey.scanOnOpen.copy.label)
                        InfoButton(.scanOnOpen)
                    }
                }

                HStack(spacing: 6) {
                    Picker(SettingHelpKey.autoScanSchedule.copy.label, selection: Binding(
                        get: { ScanIntervalOption(rawValue: coordinator.settings.payload.autoScanIntervalMinutes) ?? .every30Minutes },
                        set: { opt in
                            coordinator.settings.payload.autoScanIntervalMinutes = opt.rawValue
                            coordinator.restartAutoScanLoop()
                        }
                    )) {
                        ForEach(ScanIntervalOption.allCases) { opt in
                            Text(opt.displayLabel).tag(opt)
                        }
                    }
                    InfoButton(.autoScanSchedule)
                }

                if let nextEpoch = coordinator.nextScheduledScanEpochSeconds {
                    let remaining = max(0, Int((nextEpoch - Date().timeIntervalSince1970).rounded()))
                    let mins = remaining / 60
                    let secs = remaining % 60
                    HStack {
                        Text("Next scheduled scan")
                        Spacer()
                        Text(mins > 0 ? "In \(mins)m \(secs)s" : "In \(secs)s")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(palette.champagneGold)
                    }
                }

                HStack {
                    Text("Estimated daily usage")
                    Spacer()
                    Text(coordinator.scanUsageEstimate.summaryText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(palette.secondaryInk)
                        .multilineTextAlignment(.trailing)
                }

                Toggle(isOn: Binding(
                    get: { coordinator.settings.payload.backgroundRefreshEnabled },
                    set: { val in
                        coordinator.settings.payload.backgroundRefreshEnabled = val
                        coordinator.scheduleNextBackgroundRefresh()
                    }
                )) {
                    HStack(spacing: 6) {
                        Text(SettingHelpKey.backgroundRefresh.copy.label)
                        InfoButton(.backgroundRefresh)
                    }
                }
            } header: {
                Text("Auto-Scan & Refresh")
            } footer: {
                Text("Low Power Mode automatically limits auto-scan to every 30 minutes or slower. Opening the app skips rescanning if the last scan ran less than 2 minutes ago.")
            }

            Section {
                Toggle("Show broker-matched levels on cards", isOn: $coordinator.settings.payload.showBrokerAdjustedLevels)

                NavigationLink {
                    BrokerPriceOffsetsCalibrationView(coordinator: coordinator, palette: palette)
                } label: {
                    HStack {
                        Label("Match to broker price", systemImage: "arrow.left.arrow.right")
                        Spacer()
                        Text("\(coordinator.settings.payload.brokerPriceOffsets.count) set")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(palette.secondaryInk)
                    }
                }
            } header: {
                SettingsSectionHeader(SettingHelpKey.matchToBrokerPrice.copy.label, helpKey: .matchToBrokerPrice)
            } footer: {
                Text(SettingHelpKey.matchToBrokerPrice.copy.subtitle)
            }
        }
        .navigationTitle("Markets & Data")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            hasTwelveDataKey = await KeychainStore.shared.hasValue(for: .twelveDataAPIKey)
            hasFinnhubKey = await KeychainStore.shared.hasValue(for: .finnhubAPIKey)
        }
    }
}

private struct BrokerPriceOffsetsCalibrationView: View {
    @Bindable var coordinator: MarketScannerCoordinator
    let palette: ConfluencePalette

    @State private var selectedSymbol: String = "XAU/USD"
    @State private var brokerPriceText: String = ""
    @State private var manualOffsetText: String = ""

    private var lastFeedPrice: Double? {
        coordinator.lastKnownPrice(for: selectedSymbol)
    }

    var body: some View {
        Form {
            Section {
                Picker("Instrument", selection: $selectedSymbol) {
                    ForEach(WatchlistDefaults.assets, id: \.symbol) { asset in
                        Text("\(asset.symbol) (\(asset.marketClass.displayName))").tag(asset.symbol)
                    }
                }

                HStack {
                    Text("Last Feed Close")
                    Spacer()
                    if let last = lastFeedPrice {
                        let dec = PriceFormatHelper.decimals(for: selectedSymbol, referencePrice: last)
                        Text(PriceFormatHelper.format(last, decimals: dec))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    } else {
                        Text("Run a scan first (or enter manual offset)")
                            .font(.caption)
                            .foregroundStyle(palette.tertiaryInk)
                    }
                }

                HStack {
                    Text("Your Broker Price")
                    Spacer()
                    TextField("Enter live broker quote", text: $brokerPriceText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                }

                Button("Match to broker price") {
                    guard let bp = Double(brokerPriceText), let feed = lastFeedPrice else { return }
                    coordinator.settings.setBrokerOffset(bp - feed, for: selectedSymbol)
                    brokerPriceText = ""
                }
                .disabled(Double(brokerPriceText) == nil || lastFeedPrice == nil)

                HStack {
                    Text("Or Direct Delta (+/-)")
                    Spacer()
                    TextField("e.g. -2.50", text: $manualOffsetText)
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                }

                Button("Save Direct Offset") {
                    guard let delta = Double(manualOffsetText) else { return }
                    coordinator.settings.setBrokerOffset(delta, for: selectedSymbol)
                    manualOffsetText = ""
                }
                .disabled(Double(manualOffsetText) == nil)
            } header: {
                Text("Calibrate Symbol")
            } footer: {
                Text("Formula: offset = brokerPrice − lastFeedClose. Offsets older than 24 hours are flagged as stale so you can recalibrate.")
            }

            Section("Saved Broker Offsets") {
                if coordinator.settings.payload.brokerPriceOffsets.isEmpty {
                    Text("No broker price offsets saved.")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryInk)
                } else {
                    ForEach(coordinator.settings.payload.brokerPriceOffsets.keys.sorted(), id: \.self) { sym in
                        if let entry = coordinator.settings.payload.brokerPriceOffsets[sym] {
                            let stale = entry.isStale()
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(sym).fontWeight(.semibold)
                                        if stale {
                                            Text("STALE >24h")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(palette.trapAmber)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(palette.trapAmber.opacity(0.16), in: Capsule())
                                        }
                                    }
                                    Text(String(format: "Delta: %+.5f", entry.offset))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(palette.secondaryInk)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    coordinator.settings.setBrokerOffset(0, for: sym)
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Broker Price Offsets")
        .navigationBarTitleDisplayMode(.inline)
    }
}
