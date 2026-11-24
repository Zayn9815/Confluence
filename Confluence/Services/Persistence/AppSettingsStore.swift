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
    public var cardDensity: CardDensity = .standard
    public var showMiniCharts: Bool = true

    // Section 2 — Sound, Haptics & Animations
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
    public var cryptoPrimaryExchange: CryptoExchangePreference = .binanceVision
    public var economicCalendarEnabled: Bool = true
    public var breakingNewsRadarEnabled: Bool = true
    public var calendarPushImpactFilter: CalendarImpactFilter = .highOnly
    public var preNewsLead15m: Bool = true
    public var preNewsLead5m: Bool = true
    public var pauseSignalsDuringPreNewsWindow: Bool = true
    public var positioningFeedsEnabled: Bool = true
    public var backgroundRefreshEnabled: Bool = true
    public var backgroundRefreshIntervalMinutes: Int = 30

    // Section 4 — Signal Engine & Psychology Filters
    public var htfTimeframe: Timeframe = .h4
    public var entryTimeframe: Timeframe = .h1
    public var minimumConfidencePercent: Double = 70.0
    public var minimumRiskReward: Double = 2.0
    public var maxStopLossPercentCryptoStocks: Double = 3.0
    public var maxStopLossPercentFXMetalsIndices: Double = 1.5
    public var enabledStrategyGroups: Set<StrategyGroup> = Set(StrategyGroup.allCases)
    public var showWeakFilteredSignals: Bool = true
    public var autoSuppressCrisisAlerts: Bool = true

    // Section 5 — AI Second-Opinion (Optional)
    public var geminiEnabled: Bool = false
    public var geminiDailyCallLimit: Int = 25
    public var geminiConfirmationThreshold: Double = 0.80

    public init() {}
}

@MainActor
@Observable
public final class AppSettingsStore {
    private static let storageKey = "com.bilal.confluence.settings.v1"

    public var payload: PersistedSettingsPayload {
        didSet { save() }
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

    public func buildEngineConfig(reliabilityWeights: [String: Double] = [:]) -> EngineConfig {
        EngineConfig(
            htfTimeframe: payload.htfTimeframe,
            entryTimeframe: payload.entryTimeframe,
            minimumConfidencePercent: payload.minimumConfidencePercent,
            minimumRiskReward: payload.minimumRiskReward,
            maxStopLossPercentCryptoStocks: payload.maxStopLossPercentCryptoStocks,
            maxStopLossPercentFXMetalsIndices: payload.maxStopLossPercentFXMetalsIndices,
            minimumAlignedStrategies: 3,
            enabledStrategyGroups: payload.enabledStrategyGroups,
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

    public func toggleWatchlistSymbol(_ symbol: String) {
        if let idx = payload.watchlistSymbols.firstIndex(of: symbol) {
            payload.watchlistSymbols.remove(at: idx)
        } else {
            payload.watchlistSymbols.append(symbol)
        }
    }
}
