import SwiftUI
import SignalEngine

public struct SettingsTabView: View {
    @Bindable var coordinator: MarketScannerCoordinator
    let palette: ConfluencePalette

    @State private var twelveDataKeyInput = ""
    @State private var finnhubKeyInput = ""
    @State private var geminiKeyInput = ""
    @State private var hasTwelveDataKey = false
    @State private var hasFinnhubKey = false
    @State private var hasGeminiKey = false
    @State private var showResetConfirmation = false
    @State private var showLicensesSheet = false
    @State private var exportURL: URL?

    private let developerProfileURL = URL(string: "https://github.com/Zayn9815")!
    private let projectRepositoryURL = URL(string: "https://github.com/Zayn9815/Confluence")!

    public init(coordinator: MarketScannerCoordinator, palette: ConfluencePalette) {
        self.coordinator = coordinator
        self.palette = palette
    }

    public var body: some View {
        NavigationStack {
            Form {
                // SECTION 1 — Appearance & Display
                Section("Appearance & Display") {
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

                    Picker("Card Density", selection: $coordinator.settings.payload.cardDensity) {
                        ForEach(CardDensity.allCases) { d in
                            Text(d.rawValue).tag(d)
                        }
                    }

                    Toggle("Show Signal Mini-Charts", isOn: $coordinator.settings.payload.showMiniCharts)
                }

                // SECTION 2 — Sound, Haptics & Animations
                Section("Sound, Haptics & Animations") {
                    Toggle("In-App Signal Sound", isOn: $coordinator.settings.payload.inAppSignalSoundEnabled)
                    Toggle("Push Notification Sound", isOn: $coordinator.settings.payload.pushNotificationSoundEnabled)

                    Picker("Sound Preset", selection: $coordinator.settings.payload.soundPreset) {
                        ForEach(SoundPreset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }

                    Button {
                        SignalSoundEngine.shared.previewSound(preset: coordinator.settings.payload.soundPreset)
                    } label: {
                        Label("Preview Sound", systemImage: "speaker.wave.2.fill")
                    }

                    Toggle("Trap Alert Sound", isOn: $coordinator.settings.payload.trapAlertSoundEnabled)
                    Toggle("Pre-News Countdown Sound", isOn: $coordinator.settings.payload.preNewsCountdownSoundEnabled)
                    Toggle("News Release Impact Sound", isOn: $coordinator.settings.payload.newsReleaseImpactSoundEnabled)
                    Toggle("Haptic Feedback (CoreHaptics)", isOn: $coordinator.settings.payload.hapticsEnabled)
                    Toggle("Signal Arrival Animations", isOn: $coordinator.settings.payload.arrivalAnimationsEnabled)
                }

                // SECTION 3 — Markets, News & Data Feeds
                Section("Markets, News & Data Feeds") {
                    ForEach(MarketClass.allCases, id: \.self) { market in
                        Toggle(market.displayName, isOn: Binding(
                            get: { coordinator.settings.payload.enabledMarkets.contains(market) },
                            set: { _ in coordinator.settings.toggleMarket(market) }
                        ))
                    }

                    Picker("Crypto Primary Exchange", selection: $coordinator.settings.payload.cryptoPrimaryExchange) {
                        ForEach(CryptoExchangePreference.allCases) { venue in
                            Text(venue.rawValue).tag(venue)
                        }
                    }

                    // Optional Twelve Data API Key (encrypted Keychain)
                    HStack {
                        SecureField(hasTwelveDataKey ? "Twelve Data Key Saved (••••)" : "Optional Twelve Data API Key", text: $twelveDataKeyInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Save") {
                            Task {
                                try? await KeychainStore.shared.save(twelveDataKeyInput, for: .twelveDataAPIKey)
                                twelveDataKeyInput = ""
                                hasTwelveDataKey = await KeychainStore.shared.hasValue(for: .twelveDataAPIKey)
                            }
                        }
                        .disabled(twelveDataKeyInput.isEmpty)
                    }

                    // Optional Finnhub API Key (encrypted Keychain)
                    HStack {
                        SecureField(hasFinnhubKey ? "Finnhub Key Saved (••••)" : "Optional Finnhub News Key", text: $finnhubKeyInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Save") {
                            Task {
                                try? await KeychainStore.shared.save(finnhubKeyInput, for: .finnhubAPIKey)
                                finnhubKeyInput = ""
                                hasFinnhubKey = await KeychainStore.shared.hasValue(for: .finnhubAPIKey)
                            }
                        }
                        .disabled(finnhubKeyInput.isEmpty)
                    }

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

                    Stepper("Scan Interval: \(coordinator.settings.payload.backgroundRefreshIntervalMinutes)m", value: $coordinator.settings.payload.backgroundRefreshIntervalMinutes, in: 15...120, step: 15)

                    HStack {
                        Text("Notifications")
                        Spacer()
                        Button(coordinator.notificationStatusDescription) {
                            Task { await coordinator.requestNotifications() }
                        }
                        .font(.caption)
                    }
                }

                // SECTION 4 — Signal Engine & Psychology Filters
                Section("Signal Engine & Psychology Filters") {
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

                    ForEach(StrategyGroup.allCases, id: \.self) { group in
                        Toggle(group.displayName, isOn: Binding(
                            get: { coordinator.settings.payload.enabledStrategyGroups.contains(group) },
                            set: { _ in coordinator.settings.toggleStrategyGroup(group) }
                        ))
                    }

                    Toggle("Show \"Weak / Filtered Signals\" in Feed", isOn: $coordinator.settings.payload.showWeakFilteredSignals)
                    Toggle("Auto-Suppress Alerts in Crisis Regime", isOn: $coordinator.settings.payload.autoSuppressCrisisAlerts)
                }

                // SECTION 5 — AI Second-Opinion (Optional)
                Section("AI Second-Opinion (Optional)") {
                    Toggle("Enable Gemini 4 Hydrogen Judge", isOn: $coordinator.settings.payload.geminiEnabled)

                    HStack {
                        SecureField(hasGeminiKey ? "Gemini Key Encrypted in Keychain" : "Enter Gemini API Key", text: $geminiKeyInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Save") {
                            Task {
                                try? await KeychainStore.shared.save(geminiKeyInput, for: .geminiAPIKey)
                                geminiKeyInput = ""
                                hasGeminiKey = await KeychainStore.shared.hasValue(for: .geminiAPIKey)
                            }
                        }
                        .disabled(geminiKeyInput.isEmpty)
                    }

                    Stepper("Daily AI Call Limit: \(coordinator.settings.payload.geminiDailyCallLimit)", value: $coordinator.settings.payload.geminiDailyCallLimit, in: 5...100, step: 5)

                    HStack {
                        Text("Today's AI Usage")
                        Spacer()
                        Text("\(coordinator.geminiDailyCallsUsed) / \(coordinator.settings.payload.geminiDailyCallLimit)")
                            .monospacedDigit()
                            .foregroundStyle(palette.secondaryInk)
                    }
                }

                // SECTION 6 — Calibration & Diagnostics
                Section("Calibration & Diagnostics") {
                    Button {
                        Task { await coordinator.runFeedHealthCheck() }
                    } label: {
                        HStack {
                            Label("Feed Health & Latency Check", systemImage: "stethoscope")
                            Spacer()
                            if coordinator.isCheckingHealth {
                                ProgressView().controlSize(.small)
                            }
                        }
                    }

                    ForEach(coordinator.feedHealthResults) { entry in
                        HStack {
                            Image(systemName: entry.healthy ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundStyle(entry.healthy ? palette.longEmerald : palette.shortCrimson)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.name).font(.caption.weight(.semibold))
                                Text(entry.detail).font(.caption2).foregroundStyle(palette.secondaryInk)
                            }
                            Spacer()
                            if entry.latencyMs > 0 {
                                Text("\(Int(entry.latencyMs.rounded()))ms")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(palette.tertiaryInk)
                            }
                        }
                    }

                    if let url = exportURL {
                        ShareLink(item: url) {
                            Label("Share Exported Calibration JSON", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button {
                            exportURL = coordinator.store.exportCalibrationJSON()
                        } label: {
                            Label("Export Calibration & Signal History (JSON)", systemImage: "doc.badge.arrow.up")
                        }
                    }

                    Button(role: .destructive) {
                        showResetConfirmation = true
                    } label: {
                        Label("Reset Calibration Stats & Clear Caches", systemImage: "trash")
                    }
                }

                // SECTION 7 — About & Developer
                Section("About & Developer") {
                    HStack {
                        Text("App Name")
                        Spacer()
                        Text("Confluence").foregroundStyle(palette.secondaryInk)
                    }
                    HStack {
                        Text("Bundle ID")
                        Spacer()
                        Text("com.bilal.confluence").font(.caption.monospaced()).foregroundStyle(palette.secondaryInk)
                    }
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("\(appVersion) (\(appBuild))").monospacedDigit().foregroundStyle(palette.secondaryInk)
                    }

                    HStack {
                        Text("Developer : Bilal")
                            .fontWeight(.semibold)
                            .foregroundStyle(palette.primaryInk)
                        Spacer()
                    }

                    Link(destination: developerProfileURL) {
                        HStack {
                            Label("GitHub Profile (@Zayn9815)", systemImage: "person.crop.circle")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(palette.tertiaryInk)
                        }
                    }

                    Link(destination: projectRepositoryURL) {
                        HStack {
                            Label("Project Repository (Confluence)", systemImage: "chevron.left.forwardslash.chevron.right")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(palette.tertiaryInk)
                        }
                    }

                    Button {
                        showLicensesSheet = true
                    } label: {
                        Label("Open-Source Licenses & Attribution", systemImage: "doc.plaintext")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                hasTwelveDataKey = await KeychainStore.shared.hasValue(for: .twelveDataAPIKey)
                hasFinnhubKey = await KeychainStore.shared.hasValue(for: .finnhubAPIKey)
                hasGeminiKey = await KeychainStore.shared.hasValue(for: .geminiAPIKey)
                await coordinator.refreshNotificationStatus()
            }
            .alert("Reset Calibration & Caches?", isPresented: $showResetConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    coordinator.store.resetCalibrationAndHistory()
                    coordinator.loadPersistedState()
                }
            } message: {
                Text("This clears recorded signal history, passive calibration stats, and cached CFTC COT / calendar files. Your Keychain API keys remain untouched.")
            }
            .sheet(isPresented: $showLicensesSheet) {
                OpenSourceAttributionSheet(palette: palette)
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

private struct OpenSourceAttributionSheet: View {
    let palette: ConfluencePalette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Interactive Charting (Apache 2.0)") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TradingView Lightweight Charts™ (LightweightChartsIOS)")
                            .font(.subheadline.weight(.semibold))
                        Text("Copyright (c) TradingView, Inc. Licensed under the Apache License, Version 2.0. Charts displayed in the Full-Screen Interactive Chart view use TradingView Lightweight Charts.")
                            .font(.caption)
                            .foregroundStyle(palette.secondaryInk)
                    }
                }
                Section("SwiftUI Packages (MIT)") {
                    licenseRow("EmergeTools/Pow", "MIT License — Restrained arrival micro-interactions")
                    licenseRow("exyte/PopupView", "MIT License — Translucent floating live alert banners")
                    licenseRow("markiv/SwiftUI-Shimmer", "MIT License — Subtle scan skeletons")
                }
                Section("Public Data & Research Attribution") {
                    licenseRow("CFTC Commitments of Traders", "Public Domain Socrata JSON (publicreporting.cftc.gov)")
                    licenseRow("Behavioral Finance Foundations", "Carol Osler (Stop-Loss Clustering), Barber & Odean (Attention FOMO), Kahneman & Tversky / Shefrin & Statman (Disposition Effect)")
                }
            }
            .navigationTitle("Licenses & Attribution")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func licenseRow(_ title: String, _ desc: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(desc).font(.caption).foregroundStyle(palette.secondaryInk)
        }
    }
}
