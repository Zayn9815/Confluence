import SwiftUI
import SignalEngine

public struct MarketsFeedsSettingsView: View {
    @Bindable var coordinator: MarketScannerCoordinator
    let palette: ConfluencePalette

    @State private var twelveDataKeyInput = ""
    @State private var finnhubKeyInput = ""
    @State private var hasTwelveDataKey = false
    @State private var hasFinnhubKey = false

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
                Text("Market Data Providers")
            } footer: {
                Text("TradFi Auto uses Twelve Data (when a key is saved & within quota), defaults to biquote.io, and falls back to Yahoo Finance automatically.")
            }

            Section("Twelve Data API Key & Live Quota") {
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
                            hasTwelveDataKey = await KeychainStore.shared.readEffectiveTwelveDataKey() != nil
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
                            hasTwelveDataKey = await KeychainStore.shared.readEffectiveTwelveDataKey() != nil
                            coordinator.twelveDataQuota = nil
                            coordinator.twelveDataTestMessage = nil
                        }
                    } label: {
                        Label("Remove Saved Twelve Data Key", systemImage: "trash")
                    }
                }
            }

            Section("Economic Calendar & Breaking News") {
                Toggle("Economic Calendar", isOn: $coordinator.settings.payload.economicCalendarEnabled)
                Toggle("Breaking News Radar", isOn: $coordinator.settings.payload.breakingNewsRadarEnabled)

                Picker("Calendar Alert Impact", selection: $coordinator.settings.payload.calendarPushImpactFilter) {
                    ForEach(CalendarImpactFilter.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }

                Toggle("Pre-News Countdown (15m Before)", isOn: $coordinator.settings.payload.preNewsLead15m)
                Toggle("Pre-News Countdown (5m Before)", isOn: $coordinator.settings.payload.preNewsLead5m)
                Toggle("Pause Signals During Pre-News Window", isOn: $coordinator.settings.payload.pauseSignalsDuringPreNewsWindow)

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
            }

            Section("Positioning & Background Refresh") {
                Toggle("Pro-vs-Retail Positioning (OKX + COT)", isOn: $coordinator.settings.payload.positioningFeedsEnabled)
                Button {
                    Task { await coordinator.refreshCOTManually() }
                } label: {
                    Label("Refresh CFTC COT Data Now", systemImage: "arrow.triangle.2.circlepath")
                }

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
        }
        .navigationTitle("Markets, News & Feeds")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            hasTwelveDataKey = await KeychainStore.shared.readEffectiveTwelveDataKey() != nil
            hasFinnhubKey = await KeychainStore.shared.hasValue(for: .finnhubAPIKey)
        }
    }
}
