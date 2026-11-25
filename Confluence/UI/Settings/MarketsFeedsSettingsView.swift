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
            Section("Enabled Markets") {
                ForEach(MarketClass.allCases, id: \.self) { market in
                    Toggle(market.displayName, isOn: Binding(
                        get: { coordinator.settings.payload.enabledMarkets.contains(market) },
                        set: { _ in coordinator.settings.toggleMarket(market) }
                    ))
                }
            }

            if coordinator.settings.payload.showAdvancedSettings {
                Section {
                    Picker("Forex / Gold / Stocks / Indices", selection: $coordinator.settings.payload.tradFiProviderPreference) {
                        ForEach(TradFiProviderPreference.allCases) { pref in
                            Text(pref.rawValue).tag(pref)
                        }
                    }

                    Picker("Crypto Data Venue", selection: $coordinator.settings.payload.cryptoPrimaryExchange) {
                        ForEach(CryptoExchangePreference.allCases) { venue in
                            Text(venue.rawValue).tag(venue)
                        }
                    }
                } header: {
                    Text("Advanced Provider Overrides")
                } footer: {
                    Text("TradFi Auto uses Twelve Data (when your Keychain key is saved & within quota), defaults to biquote.io, and falls back to Yahoo Finance automatically.")
                }
            }

            Section {
                HStack {
                    SecureField(
                        hasTwelveDataKey ? "Twelve Data Key Saved (••••)" : "Enter Twelve Data API Key",
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
                        Label("Test Key & Check Quota", systemImage: "gauge.with.dots.needle.67percent")
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
                    Text("Local Calls Today")
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
                        Label("Remove Saved Twelve Data Key", systemImage: "trash")
                    }
                }
            } header: {
                Text("Twelve Data API Key & Live Quota")
            } footer: {
                Text("Keys are encrypted strictly in your iOS Keychain and never bundled in the app binary.")
            }

            Section("Macro, News & Positioning Feeds") {
                Toggle("Economic Calendar", isOn: $coordinator.settings.payload.economicCalendarEnabled)
                Toggle("Breaking News Radar", isOn: $coordinator.settings.payload.breakingNewsRadarEnabled)
                Toggle("Pro-vs-Retail Positioning (OKX + COT)", isOn: $coordinator.settings.payload.positioningFeedsEnabled)

                if coordinator.settings.payload.showAdvancedSettings {
                    HStack {
                        SecureField(
                            hasFinnhubKey ? "Finnhub Key Saved (••••)" : "Optional Finnhub News Key",
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
                        Label("Refresh CFTC COT Data Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            }

            Section("Background Refresh") {
                Toggle("Background Refresh (BGAppRefreshTask)", isOn: Binding(
                    get: { coordinator.settings.payload.backgroundRefreshEnabled },
                    set: { val in
                        coordinator.settings.payload.backgroundRefreshEnabled = val
                        coordinator.scheduleNextBackgroundRefresh()
                    }
                ))

                Stepper(
                    "Scan Interval: \(coordinator.settings.payload.backgroundRefreshIntervalMinutes)m",
                    value: $coordinator.settings.payload.backgroundRefreshIntervalMinutes,
                    in: 15...120,
                    step: 15
                )
            }

            Section {
                Toggle("Show Broker-Adjusted Levels on Cards", isOn: $coordinator.settings.payload.showBrokerAdjustedLevels)

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
                Text("Match to broker price (Display Only)")
            } footer: {
                Text("Adds your broker-vs-feed price difference to displayed Entry, Stop loss, Target 1, and Target 2 without altering engine math or calibration stats.")
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
