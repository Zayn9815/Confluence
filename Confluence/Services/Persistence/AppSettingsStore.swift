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

public enum ThemePreset: String, Codable, Sendable, CaseIterable, Identifiable {
    case obsidianTerminal = "Obsidian Terminal"
    case amoledVault = "AMOLED Vault"
    case porcelainDesk = "Porcelain Desk"

    public var id: String { rawValue }
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

public struct PersistedSettingsPayload: Codable, Sendable {
    // Section 1 — Appearance & Display
    public var appearanceMode: AppearanceMode = .dark
    public var themePreset: ThemePreset = .obsidianTerminal
    public var lastDarkThemePreset: ThemePreset = .obsidianTerminal
    public var cardDensity: CardDensity = .standard
    public var showMiniCharts: Bool = true

    // Section 2 — Notifications, Sound & Haptics
    public var inAppSignalSoundEnabled: Bool = true
    public var pushNotificationSoundEnabled: Bool = true
    public var soundPreset: SoundPreset = .terminalChime
    public var trapAlertSoundEnabled: Bool = true
    public var preNewsCountdownSoundEnabled: Bool = true
    public var newsReleaseImpactSoundEnabled: Bool = true
    public var hapticsEnabled: Bool = true
    public var arrivalAnimationsEnabled: Bool = true

    // Section 3 — Markets, News & Data Feeds
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

    // Section 4 — Signal Engine, Risk/TP & Strategy Rules
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
    public var showWeakFilteredSignals: Bool = true
    public var autoSuppressCrisisAlerts: Bool = true

    // Section 4b — Resolved Win Rate & Calibration Counting Rules
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

    /// Custom backwards-compatible decoder so existing v1.0/v1.1 sideloaded installs keep every setting cleanly.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PersistedSettingsPayload()
        appearanceMode = (try? c.decodeIfPresent(AppearanceMode.self, forKey: .appearanceMode)) ?? d.appearanceMode
        themePreset = (try? c.decodeIfPresent(ThemePreset.self, forKey: .themePreset)) ?? d.themePreset
        lastDarkThemePreset = (try? c.decodeIfPresent(ThemePreset.self, forKey: .lastDarkThemePreset)) ?? (themePreset == .amoledVault ? .amoledVault : d.lastDarkThemePreset)
        cardDensity = (try? c.decodeIfPresent(CardDensity.self, forKey: .cardDensity)) ?? d.cardDensity
        showMiniCharts = (try? c.decodeIfPresent(Bool.self, forKey: .showMiniCharts)) ?? d.showMiniCharts

        inAppSignalSoundEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .inAppSignalSoundEnabled)) ?? d.inAppSignalSoundEnabled
        pushNotificationSoundEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .pushNotificationSoundEnabled)) ?? d.pushNotificationSoundEnabled
        soundPreset = (try? c.decodeIfPresent(SoundPreset.self, forKey: .soundPreset)) ?? d.soundPreset
        trapAlertSoundEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .trapAlertSoundEnabled)) ?? d.trapAlertSoundEnabled
        preNewsCountdownSoundEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .preNewsCountdownSoundEnabled)) ?? d.preNewsCountdownSoundEnabled
        newsReleaseImpactSoundEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .newsReleaseImpactSoundEnabled)) ?? d.newsReleaseImpactSoundEnabled
        hapticsEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .hapticsEnabled)) ?? d.hapticsEnabled
        arrivalAnimationsEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .arrivalAnimationsEnabled)) ?? d.arrivalAnimationsEnabled

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
            if payload.themePreset == .obsidianTerminal || payload.themePreset == .amoledVault {
                if payload.lastDarkThemePreset != payload.themePreset {
                    payload.lastDarkThemePreset = payload.themePreset
                }
            }
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

    /// Immediately flips between Dark (`Obsidian Terminal` / `AMOLED Vault`) and Light (`Porcelain Desk`),
    /// persisting across launches and keeping Settings -> Appearance in sync.
    public func toggleDarkLightMode(currentlyDark: Bool) {
        if currentlyDark {
            if payload.themePreset == .obsidianTerminal || payload.themePreset == .amoledVault {
                payload.lastDarkThemePreset = payload.themePreset
            }
            payload.appearanceMode = .light
            payload.themePreset = .porcelainDesk
        } else {
            let restoredDark = (payload.lastDarkThemePreset == .amoledVault) ? ThemePreset.amoledVault : ThemePreset.obsidianTerminal
            payload.appearanceMode = .dark
            payload.themePreset = restoredDark
        }
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
        reliabilityWeights: [String: Double] = [:],
        activeRandomConcepts: Set<StrategyConcept>? = nil
    ) -> EngineConfig {
        let concepts: Set<StrategyConcept>
        switch payload.strategySelectionMode {
        case .defaultAll:
            concepts = Set(StrategyConcept.allCases)
        case .custom:
            concepts = payload.selectedStrategyConcepts.isEmpty
                ? Set(StrategyConcept.allCases)
                : payload.selectedStrategyConcepts
        case .randomSubset:
            concepts = activeRandomConcepts ?? Set(StrategyConcept.allCases)
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
