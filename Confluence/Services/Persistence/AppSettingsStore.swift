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
    public var enabledStrategyGroups: Set<StrategyGroup> = Set(StrategyGroup.allCases)
    public var strategySelectionMode: StrategySelectionMode = .defaultAll
    public var selectedStrategyConcepts: Set<StrategyConcept> = Set(StrategyConcept.allCases)
    public var customStrategyMatchRule: CustomStrategyMatchRule = .anyWithMinConfluence
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
    public var geminiModel: GeminiModelOption = .hydrogen
    public var geminiDailyCallLimit: Int = 25
    public var geminiConfirmationThreshold: Double = 0.80

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
        case enableTP2Target, minimumAlignedStrategies, enabledStrategyGroups
        case strategySelectionMode, selectedStrategyConcepts, customStrategyMatchRule
        case showWeakFilteredSignals, autoSuppressCrisisAlerts, oneSignalPerCorrelatedCluster
        case defaultAccountBalance, defaultRiskPercent, defaultAccountCurrency
        case manualUSDToAccountRate, customContractSpecs
        case calibrationWinDefinition, calibrationCategoryScope
        case calibrationMinConfidencePercent, calibrationMinRiskReward
        case geminiEnabled, geminiModel, geminiDailyCallLimit, geminiConfirmationThreshold
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case themePreset
        case lastDarkThemePreset
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
        enabledStrategyGroups = (try? c.decodeIfPresent(Set<StrategyGroup>.self, forKey: .enabledStrategyGroups)) ?? d.enabledStrategyGroups
        strategySelectionMode = (try? c.decodeIfPresent(StrategySelectionMode.self, forKey: .strategySelectionMode)) ?? d.strategySelectionMode
        selectedStrategyConcepts = (try? c.decodeIfPresent(Set<StrategyConcept>.self, forKey: .selectedStrategyConcepts)) ?? d.selectedStrategyConcepts
        customStrategyMatchRule = (try? c.decodeIfPresent(CustomStrategyMatchRule.self, forKey: .customStrategyMatchRule)) ?? d.customStrategyMatchRule
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
        geminiModel = (try? c.decodeIfPresent(GeminiModelOption.self, forKey: .geminiModel)) ?? d.geminiModel
        geminiDailyCallLimit = (try? c.decodeIfPresent(Int.self, forKey: .geminiDailyCallLimit)) ?? d.geminiDailyCallLimit
        geminiConfirmationThreshold = (try? c.decodeIfPresent(Double.self, forKey: .geminiConfirmationThreshold)) ?? d.geminiConfirmationThreshold
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
           let decoded = try? JSONDecoder().decode(PersistedSettingsPayload.self, from: data) {
            self.payload = decoded
        } else {
            self.payload = PersistedSettingsPayload()
        }
    }

    private func save() {
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
        let concepts: Set<StrategyConcept>
        switch payload.strategySelectionMode {
        case .defaultAll:
            concepts = Set(StrategyConcept.allCases)
        case .custom:
            concepts = payload.selectedStrategyConcepts.isEmpty
                ? Set(StrategyConcept.allCases)
                : payload.selectedStrategyConcepts
        }

        let groups: Set<StrategyGroup> = (payload.strategySelectionMode == .defaultAll)
            ? payload.enabledStrategyGroups
            : Set(concepts.map(\.group))

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
            enabledStrategyGroups: groups,
            strategySelectionMode: payload.strategySelectionMode,
            selectedStrategyConcepts: concepts,
            customStrategyMatchRule: payload.customStrategyMatchRule,
            pauseSignalsDuringPreNewsWindow: payload.pauseSignalsDuringPreNewsWindow,
            preNewsBlackoutMinutesBefore: 15,
            postNewsWhipsawMinutesAfter: 5,
            suppressAlertsInCrisisRegime: payload.autoSuppressCrisisAlerts,
            aiConfirmationThreshold: payload.geminiConfirmationThreshold,
            signalCooldownSeconds: 3_600,
            historicalReliabilityWeights: reliabilityWeights
        )
    }

    public func toggleMarket(_ market: MarketClass) {
        if payload.enabledMarkets.contains(market) {
            payload.enabledMarkets.remove(market)
        } else {
            payload.enabledMarkets.insert(market)
        }
    }

    public func toggleStrategyGroup(_ group: StrategyGroup) {
        if payload.enabledStrategyGroups.contains(group) {
            payload.enabledStrategyGroups.remove(group)
        } else {
            payload.enabledStrategyGroups.insert(group)
        }
    }

    public func toggleStrategyConcept(_ concept: StrategyConcept) {
        if payload.selectedStrategyConcepts.contains(concept) {
            if payload.selectedStrategyConcepts.count > 1 {
                payload.selectedStrategyConcepts.remove(concept)
            }
        } else {
            payload.selectedStrategyConcepts.insert(concept)
        }
    }

    public func toggleWatchlistSymbol(_ symbol: String) {
        if let idx = payload.watchlistSymbols.firstIndex(of: symbol) {
            payload.watchlistSymbols.remove(at: idx)
        } else {
            payload.watchlistSymbols.append(symbol)
        }
    }
}
