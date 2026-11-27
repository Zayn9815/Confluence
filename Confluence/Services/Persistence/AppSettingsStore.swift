import Foundation
import SwiftUI
import SignalEngine

public enum AppearanceMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case system = "System"
    case dark = "Dark Mode"
    case light = "Light Mode"

    public var id: String { rawValue }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}

public enum CardDensity: String, Codable, Sendable, CaseIterable, Identifiable {
    case standard = "Standard"
    case compact = "Compact"
    public var id: String { rawValue }
}

public enum SoundPreset: String, Codable, Sendable, CaseIterable, Identifiable {
    case terminalChime = "Terminal Chime"
    case sonarPulse = "Sonar Pulse"
    case vaultLock = "Vault Lock"
    case muted = "Muted / Haptics Only"

    public var id: String { rawValue }

    public var cafFileName: String? {
        switch self {
        case .terminalChime: return "terminal_chime.caf"
        case .sonarPulse: return "sonar_pulse.caf"
        case .vaultLock: return "vault_lock.caf"
        case .muted: return nil
        }
    }
}

public enum CalendarImpactFilter: String, Codable, Sendable, CaseIterable, Identifiable {
    case highOnly = "High Only"
    case mediumAndHigh = "Medium + High"

    public var id: String { rawValue }

    public var minimumImportance: MacroImportance {
        self == .highOnly ? .high : .medium
    }
}

public struct BrokerPriceOffset: Codable, Sendable, Equatable {
    /// Additive price delta (`brokerPrice - providerLastClose`) applied strictly for display/copy.
    public var offset: Double
    public var calibratedAtEpochSeconds: TimeInterval

    public init(offset: Double, calibratedAtEpochSeconds: TimeInterval = Date().timeIntervalSince1970) {
        self.offset = offset
        self.calibratedAtEpochSeconds = calibratedAtEpochSeconds
    }

    public func isStale(nowEpochSeconds: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        (nowEpochSeconds - calibratedAtEpochSeconds) > 86_400
    }
}

public struct PersistedSettingsPayload: Codable, Sendable {
    // Section 1 — Appearance, Accessibility & Time Display
    public var appearanceMode: AppearanceMode = .dark
    public var usePureBlackAMOLED: Bool = false
    public var useColorBlindSafePalette: Bool = false
    public var use24HourTime: Bool = false
    public var useUTCTimeZone: Bool = false
    public var cardDensity: CardDensity = .standard
    public var showMiniCharts: Bool = true
    public var showAdvancedSettings: Bool = false
    public var hasCompletedOnboarding: Bool = false

    // Section 2 — Alerts, Sound, Haptics & Quiet Hours
    public var inAppSignalSoundEnabled: Bool = true
    public var pushNotificationSoundEnabled: Bool = true
    public var soundPreset: SoundPreset = .terminalChime
    public var trapAlertSoundEnabled: Bool = true
    public var preNewsCountdownSoundEnabled: Bool = true
    public var newsReleaseImpactSoundEnabled: Bool = true
    public var hapticsEnabled: Bool = true
    public var arrivalAnimationsEnabled: Bool = true
    public var alertRules: AlertRulesConfig = AlertRulesConfig()

    // Section 3 — Markets, News, Broker Offsets & Data Feeds
    public var enabledMarkets: Set<MarketClass> = Set(MarketClass.allCases)
    public var watchlistSymbols: [String] = WatchlistDefaults.assets.map(\.symbol)
    public var tradFiProviderPreference: TradFiProviderPreference = .auto
    public var cryptoPrimaryExchange: CryptoExchangePreference = .auto
    public var economicCalendarEnabled: Bool = true
    public var breakingNewsRadarEnabled: Bool = true
    public var calendarPushImpactFilter: CalendarImpactFilter = .highOnly
    public var preNewsLead15m: Bool = true
    public var preNewsLead5m: Bool = true
    public var pauseSignalsDuringPreNewsWindow: Bool = true
    public var positioningFeedsEnabled: Bool = true
    public var backgroundRefreshEnabled: Bool = true
    public var backgroundRefreshIntervalMinutes: Int = 30
    public var brokerPriceOffsets: [String: BrokerPriceOffset] = [:]
    public var showBrokerAdjustedLevels: Bool = false

    // Section 4 — Signal Rules, Risk/TP, Sizing, Correlation & Strategy Selection
    public var htfTimeframe: Timeframe = .h4
    public var entryTimeframe: Timeframe = .h1
    public var minimumConfidencePercent: Double = 70.0
    public var minimumRiskReward: Double = 2.0
    public var maxStopLossPercentCryptoStocks: Double = 3.0
    public var maxStopLossPercentFXMetalsIndices: Double = 1.5
    public var levelCalculationMode: TradeLevelMode = .structureATR
    public var fixedStopLossPercent: Double = 1.0
    public var fixedTP1Percent: Double = 2.0
    public var fixedTP2Percent: Double = 3.5
    public var enableTP2Target: Bool = true
    public var minimumAlignedStrategies: Int = 3
    /// v1.6 individual strategy toggles (JSON array of `StrategyID` raw values). Fresh installs start with Proven Winners.
    public var enabledStrategies: Set<StrategyID> = StrategyID.provenWinners
    /// Crypto-only live Order Flow & Institutional Absorption module (skipped on Forex/TradFi with zero penalty).
    public var isOrderFlowEnabled: Bool = false
    public var showWeakFilteredSignals: Bool = false
    public var autoSuppressCrisisAlerts: Bool = true
    public var oneSignalPerCorrelatedCluster: Bool = false

    // Position Sizing Defaults (USD native + manual conversion rate for non-USD accounts)
    public var defaultAccountBalance: Double = 10_000.0
    public var defaultRiskPercent: Double = 1.0
    public var defaultAccountCurrency: AccountCurrency = .usd
    public var manualUSDToAccountRate: Double = 1.0
    public var customContractSpecs: [String: InstrumentContractSpec] = [:]

    // Section 4b — Custom Calibration View Filter Rules (headline win rate always stays fixed!)
    public var calibrationWinDefinition: CalibrationWinDefinition = .tp1OrTp2
    public var calibrationCategoryScope: CalibrationCategoryScope = .strongOnly
    public var calibrationMinConfidencePercent: Double = 0.0
    public var calibrationMinRiskReward: Double = 0.0

    // Section 5 — AI Second-Opinion (Optional)
    public var geminiEnabled: Bool = false
    public var aiProvider: AIProviderOption = .gemini
    public var aiModelID: String = GeminiModelOption.hydrogen.rawValue
    public var geminiDailyCallLimit: Int = 25
    public var geminiConfirmationThreshold: Double = 0.80

    // Section 6 — Live Feeds, Chart Options & Auto-Scan
    public var tradFiLiveFeedMode: TradFiLiveFeedMode = .autoStreamWithBackup
    public var cryptoLiveFeedMode: CryptoLiveFeedMode = .liveStream
    public var defaultChartViewMode: DefaultChartViewMode = .confluence
    public var chartEngine: ChartEngineOption = .candleKit
    public var tradingViewPreferDesktop: Bool = false
    public var showTradingViewOption: Bool = true
    public var scanOnOpenEnabled: Bool = true
    public var autoScanIntervalMinutes: Int = ScanSchedulePolicy.defaultIntervalMinutes

    public init() {}

    enum CodingKeys: String, CodingKey {
        case appearanceMode, usePureBlackAMOLED, useColorBlindSafePalette, use24HourTime, useUTCTimeZone
        case cardDensity, showMiniCharts, showAdvancedSettings, hasCompletedOnboarding
        case inAppSignalSoundEnabled, pushNotificationSoundEnabled, soundPreset
        case trapAlertSoundEnabled, preNewsCountdownSoundEnabled, newsReleaseImpactSoundEnabled
        case hapticsEnabled, arrivalAnimationsEnabled, alertRules
        case enabledMarkets, watchlistSymbols, tradFiProviderPreference, cryptoPrimaryExchange
        case economicCalendarEnabled, breakingNewsRadarEnabled, calendarPushImpactFilter
        case preNewsLead15m, preNewsLead5m, pauseSignalsDuringPreNewsWindow
        case positioningFeedsEnabled, backgroundRefreshEnabled, backgroundRefreshIntervalMinutes
        case brokerPriceOffsets, showBrokerAdjustedLevels
        case htfTimeframe, entryTimeframe, minimumConfidencePercent, minimumRiskReward
        case maxStopLossPercentCryptoStocks, maxStopLossPercentFXMetalsIndices
        case levelCalculationMode, fixedStopLossPercent, fixedTP1Percent, fixedTP2Percent
        case enableTP2Target, minimumAlignedStrategies, enabledStrategies, isOrderFlowEnabled
        case showWeakFilteredSignals, autoSuppressCrisisAlerts, oneSignalPerCorrelatedCluster
        case defaultAccountBalance, defaultRiskPercent, defaultAccountCurrency
        case manualUSDToAccountRate, customContractSpecs
        case calibrationWinDefinition, calibrationCategoryScope
        case calibrationMinConfidencePercent, calibrationMinRiskReward
        case geminiEnabled, aiProvider, aiModelID, geminiDailyCallLimit, geminiConfirmationThreshold
        case tradFiLiveFeedMode, cryptoLiveFeedMode, defaultChartViewMode, chartEngine, tradingViewPreferDesktop, showTradingViewOption
        case scanOnOpenEnabled, autoScanIntervalMinutes
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case themePreset
        case lastDarkThemePreset
        case enabledStrategyGroups
        case strategySelectionMode
        case selectedStrategyConcepts
        case geminiModel
    }

    /// Maps legacy v1.2–v1.5 rule settings to individual `StrategyID`s (custom concepts win over groups).
    public static func migrateLegacyStrategies(
        mode: StrategySelectionMode,
        groups: Set<StrategyGroup>,
        concepts: Set<StrategyConcept>
    ) -> Set<StrategyID> {
        switch mode {
        case .custom where !concepts.isEmpty:
            return StrategyID.migrate(fromConcepts: concepts)
        default:
            return StrategyID.migrate(fromGroups: groups)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        let d = PersistedSettingsPayload()

        let decodedMode = try? c.decodeIfPresent(AppearanceMode.self, forKey: .appearanceMode)
        let legacyPreset = try? legacy.decodeIfPresent(String.self, forKey: .themePreset)
        let legacyDarkPreset = try? legacy.decodeIfPresent(String.self, forKey: .lastDarkThemePreset)

        if let mode = decodedMode {
            appearanceMode = mode
        } else if legacyPreset == "Porcelain Desk" {
            appearanceMode = .light
        } else {
            appearanceMode = d.appearanceMode
        }

        if let explicitAMOLED = try? c.decodeIfPresent(Bool.self, forKey: .usePureBlackAMOLED) {
            usePureBlackAMOLED = explicitAMOLED
        } else {
            usePureBlackAMOLED = (legacyPreset == "AMOLED Vault" || legacyDarkPreset == "AMOLED Vault")
        }

        useColorBlindSafePalette = (try? c.decodeIfPresent(Bool.self, forKey: .useColorBlindSafePalette)) ?? d.useColorBlindSafePalette
        use24HourTime = (try? c.decodeIfPresent(Bool.self, forKey: .use24HourTime)) ?? d.use24HourTime
        useUTCTimeZone = (try? c.decodeIfPresent(Bool.self, forKey: .useUTCTimeZone)) ?? d.useUTCTimeZone
        cardDensity = (try? c.decodeIfPresent(CardDensity.self, forKey: .cardDensity)) ?? d.cardDensity
        showMiniCharts = (try? c.decodeIfPresent(Bool.self, forKey: .showMiniCharts)) ?? d.showMiniCharts
        showAdvancedSettings = (try? c.decodeIfPresent(Bool.self, forKey: .showAdvancedSettings)) ?? d.showAdvancedSettings
        hasCompletedOnboarding = (try? c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding)) ?? d.hasCompletedOnboarding

        inAppSignalSoundEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .inAppSignalSoundEnabled)) ?? d.inAppSignalSoundEnabled
        pushNotificationSoundEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .pushNotificationSoundEnabled)) ?? d.pushNotificationSoundEnabled
        soundPreset = (try? c.decodeIfPresent(SoundPreset.self, forKey: .soundPreset)) ?? d.soundPreset
        trapAlertSoundEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .trapAlertSoundEnabled)) ?? d.trapAlertSoundEnabled
        preNewsCountdownSoundEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .preNewsCountdownSoundEnabled)) ?? d.preNewsCountdownSoundEnabled
        newsReleaseImpactSoundEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .newsReleaseImpactSoundEnabled)) ?? d.newsReleaseImpactSoundEnabled
        hapticsEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .hapticsEnabled)) ?? d.hapticsEnabled
        arrivalAnimationsEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .arrivalAnimationsEnabled)) ?? d.arrivalAnimationsEnabled
        alertRules = (try? c.decodeIfPresent(AlertRulesConfig.self, forKey: .alertRules)) ?? d.alertRules

        enabledMarkets = (try? c.decodeIfPresent(Set<MarketClass>.self, forKey: .enabledMarkets)) ?? d.enabledMarkets
        watchlistSymbols = (try? c.decodeIfPresent([String].self, forKey: .watchlistSymbols)) ?? d.watchlistSymbols
        tradFiProviderPreference = (try? c.decodeIfPresent(TradFiProviderPreference.self, forKey: .tradFiProviderPreference)) ?? d.tradFiProviderPreference
        cryptoPrimaryExchange = (try? c.decodeIfPresent(CryptoExchangePreference.self, forKey: .cryptoPrimaryExchange)) ?? d.cryptoPrimaryExchange
        economicCalendarEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .economicCalendarEnabled)) ?? d.economicCalendarEnabled
        breakingNewsRadarEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .breakingNewsRadarEnabled)) ?? d.breakingNewsRadarEnabled
        calendarPushImpactFilter = (try? c.decodeIfPresent(CalendarImpactFilter.self, forKey: .calendarPushImpactFilter)) ?? d.calendarPushImpactFilter
        preNewsLead15m = (try? c.decodeIfPresent(Bool.self, forKey: .preNewsLead15m)) ?? d.preNewsLead15m
        preNewsLead5m = (try? c.decodeIfPresent(Bool.self, forKey: .preNewsLead5m)) ?? d.preNewsLead5m
        pauseSignalsDuringPreNewsWindow = (try? c.decodeIfPresent(Bool.self, forKey: .pauseSignalsDuringPreNewsWindow)) ?? d.pauseSignalsDuringPreNewsWindow
        positioningFeedsEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .positioningFeedsEnabled)) ?? d.positioningFeedsEnabled
        backgroundRefreshEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .backgroundRefreshEnabled)) ?? d.backgroundRefreshEnabled
        backgroundRefreshIntervalMinutes = (try? c.decodeIfPresent(Int.self, forKey: .backgroundRefreshIntervalMinutes)) ?? d.backgroundRefreshIntervalMinutes
        brokerPriceOffsets = (try? c.decodeIfPresent([String: BrokerPriceOffset].self, forKey: .brokerPriceOffsets)) ?? d.brokerPriceOffsets
        showBrokerAdjustedLevels = (try? c.decodeIfPresent(Bool.self, forKey: .showBrokerAdjustedLevels)) ?? d.showBrokerAdjustedLevels

        htfTimeframe = (try? c.decodeIfPresent(Timeframe.self, forKey: .htfTimeframe)) ?? d.htfTimeframe
        entryTimeframe = (try? c.decodeIfPresent(Timeframe.self, forKey: .entryTimeframe)) ?? d.entryTimeframe
        minimumConfidencePercent = (try? c.decodeIfPresent(Double.self, forKey: .minimumConfidencePercent)) ?? d.minimumConfidencePercent
        minimumRiskReward = (try? c.decodeIfPresent(Double.self, forKey: .minimumRiskReward)) ?? d.minimumRiskReward
        maxStopLossPercentCryptoStocks = (try? c.decodeIfPresent(Double.self, forKey: .maxStopLossPercentCryptoStocks)) ?? d.maxStopLossPercentCryptoStocks
        maxStopLossPercentFXMetalsIndices = (try? c.decodeIfPresent(Double.self, forKey: .maxStopLossPercentFXMetalsIndices)) ?? d.maxStopLossPercentFXMetalsIndices
        levelCalculationMode = (try? c.decodeIfPresent(TradeLevelMode.self, forKey: .levelCalculationMode)) ?? d.levelCalculationMode
        fixedStopLossPercent = (try? c.decodeIfPresent(Double.self, forKey: .fixedStopLossPercent)) ?? d.fixedStopLossPercent
        fixedTP1Percent = (try? c.decodeIfPresent(Double.self, forKey: .fixedTP1Percent)) ?? d.fixedTP1Percent
        fixedTP2Percent = (try? c.decodeIfPresent(Double.self, forKey: .fixedTP2Percent)) ?? d.fixedTP2Percent
        enableTP2Target = (try? c.decodeIfPresent(Bool.self, forKey: .enableTP2Target)) ?? d.enableTP2Target
        minimumAlignedStrategies = (try? c.decodeIfPresent(Int.self, forKey: .minimumAlignedStrategies)) ?? d.minimumAlignedStrategies
        if let raw = try? c.decodeIfPresent([String].self, forKey: .enabledStrategies) {
            // Unknown raw values (future/removed detectors) are skipped instead of resetting the whole selection.
            enabledStrategies = Set(raw.compactMap(StrategyID.init(rawValue:)))
        } else if legacy.contains(.enabledStrategyGroups) || legacy.contains(.strategySelectionMode) || legacy.contains(.selectedStrategyConcepts) {
            // One-time legacy migration: map the old grouped / custom-concept selection to individual StrategyIDs.
            let legacyGroups = (try? legacy.decodeIfPresent(Set<StrategyGroup>.self, forKey: .enabledStrategyGroups)) ?? Set(StrategyGroup.allCases)
            let legacyMode = (try? legacy.decodeIfPresent(StrategySelectionMode.self, forKey: .strategySelectionMode)) ?? .defaultAll
            let legacyConcepts = (try? legacy.decodeIfPresent(Set<StrategyConcept>.self, forKey: .selectedStrategyConcepts)) ?? Set(StrategyConcept.allCases)
            enabledStrategies = PersistedSettingsPayload.migrateLegacyStrategies(
                mode: legacyMode,
                groups: legacyGroups,
                concepts: legacyConcepts
            )
        } else {
            enabledStrategies = d.enabledStrategies
        }
        isOrderFlowEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .isOrderFlowEnabled)) ?? d.isOrderFlowEnabled
        showWeakFilteredSignals = (try? c.decodeIfPresent(Bool.self, forKey: .showWeakFilteredSignals)) ?? d.showWeakFilteredSignals
        autoSuppressCrisisAlerts = (try? c.decodeIfPresent(Bool.self, forKey: .autoSuppressCrisisAlerts)) ?? d.autoSuppressCrisisAlerts
        oneSignalPerCorrelatedCluster = (try? c.decodeIfPresent(Bool.self, forKey: .oneSignalPerCorrelatedCluster)) ?? d.oneSignalPerCorrelatedCluster

        defaultAccountBalance = (try? c.decodeIfPresent(Double.self, forKey: .defaultAccountBalance)) ?? d.defaultAccountBalance
        defaultRiskPercent = (try? c.decodeIfPresent(Double.self, forKey: .defaultRiskPercent)) ?? d.defaultRiskPercent
        defaultAccountCurrency = (try? c.decodeIfPresent(AccountCurrency.self, forKey: .defaultAccountCurrency)) ?? d.defaultAccountCurrency
        manualUSDToAccountRate = (try? c.decodeIfPresent(Double.self, forKey: .manualUSDToAccountRate)) ?? d.manualUSDToAccountRate
        customContractSpecs = (try? c.decodeIfPresent([String: InstrumentContractSpec].self, forKey: .customContractSpecs)) ?? d.customContractSpecs

        calibrationWinDefinition = (try? c.decodeIfPresent(CalibrationWinDefinition.self, forKey: .calibrationWinDefinition)) ?? d.calibrationWinDefinition
        calibrationCategoryScope = (try? c.decodeIfPresent(CalibrationCategoryScope.self, forKey: .calibrationCategoryScope)) ?? d.calibrationCategoryScope
        calibrationMinConfidencePercent = (try? c.decodeIfPresent(Double.self, forKey: .calibrationMinConfidencePercent)) ?? d.calibrationMinConfidencePercent
        calibrationMinRiskReward = (try? c.decodeIfPresent(Double.self, forKey: .calibrationMinRiskReward)) ?? d.calibrationMinRiskReward

        geminiEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .geminiEnabled)) ?? d.geminiEnabled
        let decodedLegacyGemini = (try? legacy.decodeIfPresent(GeminiModelOption.self, forKey: .geminiModel)) ?? .hydrogen
        // Migrate legacy `geminiModel` cleanly to `aiProvider` + `aiModelID` when new keys are absent
        aiProvider = (try? c.decodeIfPresent(AIProviderOption.self, forKey: .aiProvider)) ?? .gemini
        aiModelID = (try? c.decodeIfPresent(String.self, forKey: .aiModelID)) ?? decodedLegacyGemini.rawValue
        geminiDailyCallLimit = (try? c.decodeIfPresent(Int.self, forKey: .geminiDailyCallLimit)) ?? d.geminiDailyCallLimit
        geminiConfirmationThreshold = (try? c.decodeIfPresent(Double.self, forKey: .geminiConfirmationThreshold)) ?? d.geminiConfirmationThreshold

        tradFiLiveFeedMode = (try? c.decodeIfPresent(TradFiLiveFeedMode.self, forKey: .tradFiLiveFeedMode)) ?? d.tradFiLiveFeedMode
        cryptoLiveFeedMode = (try? c.decodeIfPresent(CryptoLiveFeedMode.self, forKey: .cryptoLiveFeedMode)) ?? d.cryptoLiveFeedMode
        defaultChartViewMode = (try? c.decodeIfPresent(DefaultChartViewMode.self, forKey: .defaultChartViewMode)) ?? d.defaultChartViewMode
        chartEngine = (try? c.decodeIfPresent(ChartEngineOption.self, forKey: .chartEngine)) ?? d.chartEngine
        tradingViewPreferDesktop = (try? c.decodeIfPresent(Bool.self, forKey: .tradingViewPreferDesktop)) ?? d.tradingViewPreferDesktop
        showTradingViewOption = (try? c.decodeIfPresent(Bool.self, forKey: .showTradingViewOption)) ?? d.showTradingViewOption
        scanOnOpenEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .scanOnOpenEnabled)) ?? d.scanOnOpenEnabled
        autoScanIntervalMinutes = (try? c.decodeIfPresent(Int.self, forKey: .autoScanIntervalMinutes)) ?? d.autoScanIntervalMinutes
    }
}

@MainActor
@Observable
public final class AppSettingsStore {
    private static let storageKey = "com.bilal.confluence.settings.v1"

    public var payload: PersistedSettingsPayload {
        didSet {
            save()
        }
    }

    public init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           var decoded = try? JSONDecoder().decode(PersistedSettingsPayload.self, from: data) {
            if let storedEngineRaw = UserDefaults.standard.string(forKey: ChartEngineOption.appStorageKey) {
                decoded.chartEngine = ChartEngineOption.fromStoredRawValue(storedEngineRaw)
            }
            self.payload = decoded
        } else {
            var initial = PersistedSettingsPayload()
            if let storedEngineRaw = UserDefaults.standard.string(forKey: ChartEngineOption.appStorageKey) {
                initial.chartEngine = ChartEngineOption.fromStoredRawValue(storedEngineRaw)
            }
            self.payload = initial
        }
    }

    private func save() {
        UserDefaults.standard.set(payload.chartEngine.rawValue, forKey: ChartEngineOption.appStorageKey)
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    public func toggleDarkLightMode(currentlyDark: Bool) {
        payload.appearanceMode = currentlyDark ? .light : .dark
    }

    public func contractSpec(for symbol: String, marketClass: MarketClass) -> InstrumentContractSpec {
        payload.customContractSpecs[symbol] ?? InstrumentContractSpec.defaultSpec(for: symbol, marketClass: marketClass)
    }

    public func setContractSpec(_ spec: InstrumentContractSpec, for symbol: String) {
        payload.customContractSpecs[symbol] = spec
    }

    public func brokerOffset(for symbol: String) -> BrokerPriceOffset? {
        payload.brokerPriceOffsets[symbol]
    }

    public func setBrokerOffset(_ offset: Double, for symbol: String) {
        if abs(offset) < 1e-12 {
            payload.brokerPriceOffsets.removeValue(forKey: symbol)
        } else {
            payload.brokerPriceOffsets[symbol] = BrokerPriceOffset(offset: offset, calibratedAtEpochSeconds: Date().timeIntervalSince1970)
        }
    }

    /// Returns display-adjusted TradeLevels (adding broker offset strictly for UI/Copy; never mutates stored signal/outcome).
    public func displayLevels(for signal: TradeSignal) -> TradeLevels? {
        guard let lv = signal.levels else { return nil }
        guard payload.showBrokerAdjustedLevels, let delta = payload.brokerPriceOffsets[signal.symbol]?.offset, abs(delta) > 1e-12 else {
            return lv
        }
        return TradeLevels(
            entryLow: lv.entryLow + delta,
            entryHigh: lv.entryHigh + delta,
            entryMid: lv.entryMid + delta,
            stopLoss: lv.stopLoss + delta,
            tp1: lv.tp1 + delta,
            tp2: lv.tp2 + delta,
            riskPercent: lv.riskPercent,
            reward1Percent: lv.reward1Percent,
            reward2Percent: lv.reward2Percent,
            riskRewardRatio: lv.riskRewardRatio,
            tp2RiskRewardRatio: lv.tp2RiskRewardRatio,
            isTP2Enabled: lv.isTP2Enabled
        )
    }

    public var preNewsLeadTimesMinutes: [Int] {
        var out: [Int] = []
        if payload.preNewsLead15m { out.append(15) }
        if payload.preNewsLead5m { out.append(5) }
        return out
    }

    public var activeWatchlistAssets: [AssetDescriptor] {
        payload.watchlistSymbols.compactMap { sym in
            guard let desc = WatchlistDefaults.descriptor(for: sym) else { return nil }
            return payload.enabledMarkets.contains(desc.marketClass) ? desc : nil
        }
    }

    /// Single source of truth for currently enabled strategies + Crypto-Only Order Flow.
    public var activeStrategyProfile: ActiveStrategyProfile {
        ActiveStrategyProfile(
            enabledStrategies: payload.enabledStrategies,
            isOrderFlowEnabled: payload.isOrderFlowEnabled
        )
    }

    public func buildCalibrationFilterConfig() -> CalibrationFilterConfig {
        CalibrationFilterConfig(
            winDefinition: payload.calibrationWinDefinition,
            categoryScope: payload.calibrationCategoryScope,
            minimumConfidencePercent: payload.calibrationMinConfidencePercent,
            minimumRiskReward: payload.calibrationMinRiskReward
        )
    }

    public func buildEngineConfig(
        reliabilityWeights: [String: Double] = [:]
    ) -> EngineConfig {
        return EngineConfig(
            htfTimeframe: payload.htfTimeframe,
            entryTimeframe: payload.entryTimeframe,
            minimumConfidencePercent: payload.minimumConfidencePercent,
            minimumRiskReward: payload.minimumRiskReward,
            maxStopLossPercentCryptoStocks: payload.maxStopLossPercentCryptoStocks,
            maxStopLossPercentFXMetalsIndices: payload.maxStopLossPercentFXMetalsIndices,
            levelCalculationMode: payload.levelCalculationMode,
            fixedStopLossPercent: payload.fixedStopLossPercent,
            fixedTP1Percent: payload.fixedTP1Percent,
            fixedTP2Percent: payload.fixedTP2Percent,
            enableTP2Target: payload.enableTP2Target,
            minimumAlignedStrategies: payload.minimumAlignedStrategies,
            pauseSignalsDuringPreNewsWindow: payload.pauseSignalsDuringPreNewsWindow,
            preNewsBlackoutMinutesBefore: 15,
            postNewsWhipsawMinutesAfter: 5,
            suppressAlertsInCrisisRegime: payload.autoSuppressCrisisAlerts,
            aiConfirmationThreshold: payload.geminiConfirmationThreshold,
            signalCooldownSeconds: 3_600,
            historicalReliabilityWeights: reliabilityWeights,
            enabledStrategies: payload.enabledStrategies,
            isOrderFlowEnabled: payload.isOrderFlowEnabled
        )
    }

    public func toggleMarket(_ market: MarketClass) {
        if payload.enabledMarkets.contains(market) {
            payload.enabledMarkets.remove(market)
        } else {
            payload.enabledMarkets.insert(market)
        }
    }

    public func toggleStrategy(_ id: StrategyID) {
        if payload.enabledStrategies.contains(id) {
            payload.enabledStrategies.remove(id)
        } else {
            payload.enabledStrategies.insert(id)
        }
    }

    /// Settings UI helper enforcing a minimum of 1 enabled core OHLC strategy.
    /// Returns `false` if turning off `id` was blocked because it is the last enabled core OHLC strategy.
    @discardableResult
    public func setStrategyEnforcingCoreFloor(_ id: StrategyID, enabled: Bool) -> Bool {
        if enabled {
            payload.enabledStrategies.insert(id)
            return true
        }
        if id.isCoreOHLC {
            let remainingCore = payload.enabledStrategies.filter { $0.isCoreOHLC && $0 != id }
            if remainingCore.isEmpty {
                return false
            }
        }
        payload.enabledStrategies.remove(id)
        return true
    }

    public func toggleWatchlistSymbol(_ symbol: String) {
        if let idx = payload.watchlistSymbols.firstIndex(of: symbol) {
            payload.watchlistSymbols.remove(at: idx)
        } else {
            payload.watchlistSymbols.append(symbol)
        }
    }
}
