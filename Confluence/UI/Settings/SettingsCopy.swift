import SwiftUI
import SignalEngine

/// Plain-English copy bundle for every user-facing setting row, picker, and section.
/// Rules:
/// - `label` and `subtitle` are strictly plain English (no raw trading/engineering jargon).
/// - `helpText` explains what the setting does in everyday language and may include clarifying technical terms.
/// - Never rename `Codable` keys or enum raw values — display strings live here only.
public struct SettingCopy: Sendable, Equatable {
    public let label: String
    public let subtitle: String
    public let helpText: String

    public init(label: String, subtitle: String, helpText: String) {
        self.label = label
        self.subtitle = subtitle
        self.helpText = helpText
    }
}

public enum SettingHelpKey: String, CaseIterable, Sendable, Identifiable {
    // Hub
    case showAdvancedSettings

    // Category 1 — Appearance & Feedback
    case appearanceMode
    case terminalThemePreset
    case liquidGlassIntensity
    case pureBlackBackground
    case colorBlindSafePalette
    case clock24Hour
    case universalTimeDisplay
    case cardDensity
    case miniCharts
    case signalAudio
    case haptics
    case arrivalAnimations

    // Category 2 — Alerts
    case alertCategories
    case quietHours
    case perMarketAlertRules
    case preNewsCountdowns
    case pauseDuringPreNews
    case crisisAlertSuppression

    // Category 3 — Markets & Data
    case enabledMarkets
    case advancedProviderOverrides
    case twelveDataKey
    case macroNewsPositioningFeeds
    case tradFiLiveFeed
    case cryptoLiveFeed
    case chartEngine
    case defaultChartView
    case showTradingViewOption
    case scanOnOpen
    case autoScanSchedule
    case backgroundRefresh
    case matchToBrokerPrice

    // Category 4 — Signal Rules & AI
    case strongSignalScoreGate
    case minimumRewardRatio
    case enableTarget2
    case showWeakFilteredSignals
    case oneSignalPerCorrelatedCluster
    case levelCalculationMode
    case maxStopLossCap
    case strategySelection
    case customCalibrationView
    case aiSecondOpinion
    case aiProviderAndModel
    case sharedDailyAILimit

    // Category 5 — Data, Diagnostics & About
    case backupAndRestore
    case diagnosticsAndLogs

    public var id: String { rawValue }

    public var copy: SettingCopy {
        switch self {
        case .showAdvancedSettings:
            return SettingCopy(
                label: "Show extra controls",
                subtitle: "Unlock manual data source overrides, fixed-percentage levels, custom rule filters, and custom stats views.",
                helpText: "Keep this off for a clean everyday setup. Turn it on to tune advanced options like fixed-percent Stop loss / Target rules, per-concept filters, data source overrides, and custom Calibration filters. The AI provider & model picker is always visible even when this is off."
            )

        // Category 1 — Appearance & Feedback
        case .appearanceMode:
            return SettingCopy(
                label: "Color theme",
                subtitle: "Match your iPhone or lock Dark or Light look.",
                helpText: "Switches Confluence between System, Dark Mode, and Light Mode. You can also toggle Dark and Light quickly from the top-left button on the Signals tab."
            )
        case .terminalThemePreset:
            return SettingCopy(
                label: "Color style",
                subtitle: "Pick an accent and surface palette for cards and charts.",
                helpText: "Selects your institutional terminal palette across cards, badges, and all chart engines (Champagne Obsidian, Emerald Desk, Midnight Cobalt, or Ivory Institutional)."
            )
        case .liquidGlassIntensity:
            return SettingCopy(
                label: "Glass transparency",
                subtitle: "Adjust translucent glass depth on floating bars and badges.",
                helpText: "Controls how translucent floating bars and glass pills appear (Solid, Subtle, Standard, or Immersive). Automatically falls back to solid surfaces when iOS Reduce Transparency is enabled."
            )
        case .pureBlackBackground:
            return SettingCopy(
                label: "Pure black dark background",
                subtitle: "Use true black backgrounds in Dark Mode to save screen power.",
                helpText: "Replaces the charcoal canvas with pure black (#000000) in Dark Mode for OLED/AMOLED screens."
            )
        case .colorBlindSafePalette:
            return SettingCopy(
                label: "Color-blind safe colors",
                subtitle: "Use blue and orange instead of green and red.",
                helpText: "Replaces standard green/red directional colors with an accessible Okabe-Ito Blue/Orange palette alongside explicit up/down arrows. System Increase Contrast and Reduce Motion are always respected."
            )
        case .clock24Hour:
            return SettingCopy(
                label: "24-hour clock",
                subtitle: "Show times like 14:30 instead of 2:30 PM.",
                helpText: "Applies consistently across signal timestamps, calendar events, journal entries, and chart closed-bar labels."
            )
        case .universalTimeDisplay:
            return SettingCopy(
                label: "Show world market time",
                subtitle: "Display timestamps in universal market time instead of local phone time.",
                helpText: "Shows all candle close times and news schedules in Coordinated Universal Time (UTC) so they match exchange servers directly."
            )
        case .cardDensity:
            return SettingCopy(
                label: "Card layout spacing",
                subtitle: "Choose between full-detail cards or tighter compact cards.",
                helpText: "Compact mode fits more signal cards on screen at once while keeping Entry, Stop loss, Target 1, and score visible."
            )
        case .miniCharts:
            return SettingCopy(
                label: "Show mini charts on cards",
                subtitle: "Preview recent price action directly on every signal card.",
                helpText: "Renders a lightweight built-in mini candlestick chart on each card. Turn off for a pure numbers list and slightly lower battery use."
            )
        case .signalAudio:
            return SettingCopy(
                label: "Alert sounds",
                subtitle: "Play short chimes for new setups and scheduled reminders.",
                helpText: "Uses iOS ambient audio so your phone's silent switch is always respected and your music or podcasts never stop."
            )
        case .haptics:
            return SettingCopy(
                label: "Touch feedback",
                subtitle: "Gentle taps when scanning, switching themes, or receiving alerts.",
                helpText: "Uses iPhone haptic feedback (CoreHaptics) for tactile confirmation on key actions."
            )
        case .arrivalAnimations:
            return SettingCopy(
                label: "Subtle arrival highlights",
                subtitle: "Briefly highlight brand-new strong setups when a scan finishes.",
                helpText: "Plays a restrained one-time shimmer on newly discovered strong setups. Automatically disabled if Reduce Motion is enabled in iOS."
            )

        // Category 2 — Alerts
        case .alertCategories:
            return SettingCopy(
                label: "Alert types",
                subtitle: "Pick which kinds of market updates can notify you.",
                helpText: "Independently enable or mute Strong Signals, Behavioral Trap warnings, Pre-News countdown reminders, and Major Economic Release impacts."
            )
        case .quietHours:
            return SettingCopy(
                label: "Quiet hours",
                subtitle: "Silence all banners, sounds, and reminders during chosen hours.",
                helpText: "Supports both same-day and overnight windows (such as 22:00 to 07:00) plus per-weekday schedules. During quiet hours, alerts are still logged quietly in your bell inbox."
            )
        case .perMarketAlertRules:
            return SettingCopy(
                label: "Per-market alert rules",
                subtitle: "Mute specific asset groups or require a higher score per market.",
                helpText: "Customize notification channels (push, banner, sound) and an optional minimum score override separately for Crypto, Forex, Gold, Indices, and Stocks."
            )
        case .preNewsCountdowns:
            return SettingCopy(
                label: "Pre-news reminders",
                subtitle: "Get a heads-up 15 or 5 minutes before major economic releases.",
                helpText: "Scheduled strictly for exact-clock calendar releases (never tentative/all-day items) within iOS's safe 40-notification budget."
            )
        case .pauseDuringPreNews:
            return SettingCopy(
                label: "Pause setups right before major news",
                subtitle: "Hold back fresh setups right ahead of high-impact releases.",
                helpText: "Prevents fresh entry alerts right before major scheduled economic prints when spreads widen and price whipsaws."
            )
        case .crisisAlertSuppression:
            return SettingCopy(
                label: "Auto-mute alerts during extreme volatility",
                subtitle: "Hold back alerts when markets enter crisis-level swings.",
                helpText: "When the deterministic regime classifier detects a Crisis regime, alerts are automatically suppressed and risk state switches to reduce-only."
            )

        // Category 3 — Markets & Data
        case .enabledMarkets:
            return SettingCopy(
                label: "Active markets",
                subtitle: "Choose which market groups Confluence scans.",
                helpText: "Turning off markets you do not watch speeds up every scan and lowers network and data-quota usage."
            )
        case .advancedProviderOverrides:
            return SettingCopy(
                label: "Manual data source overrides",
                subtitle: "Force a specific historical candle source instead of automatic fallback.",
                helpText: "Automatic mode selects the best healthy source (Twelve Data when configured and within quota, biquote.io, Yahoo Finance for TradFi; Binance Vision, OKX, Kraken for Crypto) and fails over automatically."
            )
        case .twelveDataKey:
            return SettingCopy(
                label: "Twelve Data personal key",
                subtitle: "Optional key for higher-precision historical candles on stocks, gold, and forex.",
                helpText: "Stored strictly in your iOS Keychain and never bundled in the app. Used only for historical scans and chart history — never consumed by live price streaming or polling."
            )
        case .macroNewsPositioningFeeds:
            return SettingCopy(
                label: "Economic calendar, news & market positioning",
                subtitle: "Pull scheduled releases, breaking headlines, and trader positioning.",
                helpText: "Combines the economic calendar, breaking news radar, and pro-vs-retail positioning (OKX open interest / long-short ratios and weekly CFTC COT reports with strict release-lag guards)."
            )
        case .tradFiLiveFeed:
            return SettingCopy(
                label: "Forex, Gold & Stocks live prices",
                subtitle: "Choose how live quotes refresh while the app is open.",
                helpText: "Auto streams real-time quotes over WebSocket and falls back to 10-second polling (biquote.io / Yahoo) automatically if the stream disconnects. Live feeds stop immediately when you leave the app and never use Twelve Data."
            )
        case .cryptoLiveFeed:
            return SettingCopy(
                label: "Crypto live prices",
                subtitle: "Choose real-time streaming or battery-saving updates for crypto.",
                helpText: "Live stream connects directly to Binance Vision WebSocket while the app is in the foreground (up to 8 symbols at once) and disconnects automatically when backgrounded."
            )
        case .chartEngine:
            return SettingCopy(
                label: "Chart rendering engine",
                subtitle: "Choose the interactive candlestick engine used for full-screen charts.",
                helpText: "Switch seamlessly between CandleKit (default 120Hz SwiftUI Canvas with native order lines), DGCharts (native CoreGraphics candlesticks with price-axis drag-to-scale), Swift Trading View (native multi-pane SwiftUI Canvas with MA and Volume), and TradingView Web (persistent logged-in tradingview.com with Clean Mode & 1-tap Sync Pair)."
            )
        case .defaultChartView:
            return SettingCopy(
                label: "Default full-screen chart",
                subtitle: "Pick whether tapping a signal opens the Confluence chart or TradingView.",
                helpText: "The Confluence chart plots all Entry, Stop loss, Target 1, Target 2, and Trap lines directly on live candles. TradingView opens TradingView's embedded interactive chart."
            )
        case .showTradingViewOption:
            return SettingCopy(
                label: "Show TradingView switch on chart",
                subtitle: "Add a quick switch and Open in TradingView button on the full-screen chart.",
                helpText: "When enabled, you can toggle between the Confluence chart and TradingView's widget, or jump straight into the TradingView app (with web fallback)."
            )
        case .scanOnOpen:
            return SettingCopy(
                label: "Scan automatically when opening the app",
                subtitle: "Refresh setups when you open Confluence if data is older than 2 minutes.",
                helpText: "Skips scanning if you already scanned within the last 2 minutes so switching apps briefly never wastes data or battery."
            )
        case .autoScanSchedule:
            return SettingCopy(
                label: "Automatic scan interval",
                subtitle: "Re-scan your active markets on a schedule while the app is open.",
                helpText: "Runs only while Confluence is active. iOS Low Power Mode automatically slows intervals faster than 30 minutes down to every 30 minutes."
            )
        case .backgroundRefresh:
            return SettingCopy(
                label: "Background updates",
                subtitle: "Let iOS occasionally refresh setups while the app is closed.",
                helpText: "Uses Apple's standard background refresh (BGAppRefreshTask). iOS decides the exact wake times based on battery and usage patterns."
            )
        case .matchToBrokerPrice:
            return SettingCopy(
                label: "Match to broker price",
                subtitle: "Shift displayed prices to match your broker's quote without altering analysis.",
                helpText: "Adds the difference between your broker's live price and the data feed's price purely for display and copying levels. Engine math, calibration stats, and automatic journal fills are never altered."
            )

        // Category 4 — Signal Rules & AI
        case .strongSignalScoreGate:
            return SettingCopy(
                label: "Minimum setup strength",
                subtitle: "Only highlight setups that score at or above this threshold.",
                helpText: "Always checks the deterministic raw Confluence score (0–100), never the display-only calibrated probability. Higher thresholds show fewer, stricter setups."
            )
        case .minimumRewardRatio:
            return SettingCopy(
                label: "Minimum reward-to-risk ratio",
                subtitle: "Skip setups whose Target 1 reward is too small compared to Stop loss risk.",
                helpText: "For example, 1 : 2.0 requires Target 1 to offer at least twice the distance of your Stop loss. Setups below your minimum ratio are filtered out."
            )
        case .enableTarget2:
            return SettingCopy(
                label: "Show extended Target 2",
                subtitle: "Calculate and plot a second farther target beyond Target 1.",
                helpText: "When off, signal cards and charts display only Entry, Stop loss, and Target 1. Target 2 is always capped to realistic timeframe and volatility bounds."
            )
        case .showWeakFilteredSignals:
            return SettingCopy(
                label: "Show filtered setups in feed",
                subtitle: "Display lower-scoring setups in a separate tab for review.",
                helpText: "Even when this is off, Confluence quietly tracks filtered setups in the background so your Calibration Stats can honestly compare Strong vs. Filtered performance."
            )
        case .oneSignalPerCorrelatedCluster:
            return SettingCopy(
                label: "Limit overlapping correlated pairs",
                subtitle: "Keep only the strongest setup among markets that move together.",
                helpText: "Prevents taking multiple simultaneous setups on tightly correlated pairs (such as BTC and ETH, or S&P 500 and Nasdaq) by surfacing only the top-scoring setup per cluster."
            )
        case .levelCalculationMode:
            return SettingCopy(
                label: "How Stop loss and targets are placed",
                subtitle: "Use market structure and volatility, or exact fixed percentages.",
                helpText: "Structure & Volatility mode places Stop loss beyond recent swing invalidation with ATR buffers. Fixed % mode sets exact percentage distances from entry."
            )
        case .maxStopLossCap:
            return SettingCopy(
                label: "Maximum Stop loss width",
                subtitle: "Reject setups whose Stop loss is wider than your safety cap.",
                helpText: "Enforces separate maximum Stop loss percentage ceilings for Crypto/Stocks and Forex/Gold/Indices so wide volatile stops never slip through."
            )
        case .strategySelection:
            return SettingCopy(
                label: "Active trading rule sets",
                subtitle: "Use all built-in confirmations or pick your own custom mix.",
                helpText: "Default combines market structure, candlestick action, trend momentum, behavioral traps, and macro catalysts. Custom lets you choose specific concepts and match rules."
            )
        case .customCalibrationView:
            return SettingCopy(
                label: "Custom stats filter",
                subtitle: "Slice a secondary stats card without changing the main win-rate card.",
                helpText: "The headline Win Rate card is locked to Strong, filled, post-v1.4 setups for statistical honesty. This filter powers the secondary Custom View card and breakdown."
            )
        case .aiSecondOpinion:
            return SettingCopy(
                label: "Optional review assistant",
                subtitle: "Add a second-opinion review on new setups using your own provider key.",
                helpText: "Confluence works 100% natively with this off. When enabled, the selected AI model reviews setups in strict JSON but can never change your Stop loss, Target 1, Target 2, risk caps, or Crisis suppression."
            )
        case .aiProviderAndModel:
            return SettingCopy(
                label: "Assistant provider & model",
                subtitle: "Choose Gemini, DeepSeek, or OpenRouter and test your saved key.",
                helpText: "Keys are stored encrypted per provider in your iOS Keychain and sent only in HTTPS headers. Tapping 'Test key & list models' verifies your key and loads available models live."
            )
        case .sharedDailyAILimit:
            return SettingCopy(
                label: "Daily assistant request cap",
                subtitle: "Cap total automated reviews per day across all providers.",
                helpText: "One shared daily counter protects your quota and spending across Gemini, DeepSeek, and OpenRouter combined."
            )

        // Category 5 — Data, Diagnostics & About
        case .backupAndRestore:
            return SettingCopy(
                label: "Backup and restore",
                subtitle: "Save or restore your settings, history, and automatic signal journal.",
                helpText: "Exports a versioned schema v2 JSON backup (previous v1 backups remain importable). Keychain keys are never included, and all exports pass through SecretRedactor."
            )
        case .diagnosticsAndLogs:
            return SettingCopy(
                label: "Health logs & crash reports",
                subtitle: "Inspect feed health, runtime errors, and crash diagnostics.",
                helpText: "Includes feed latency and errors, crash/hang captures, and one-tap sanitized diagnostic exports with all secrets automatically redacted."
            )
        }
    }

    /// Plain-English display labels for enum pickers (never alters Codable raw values).
    public static func displayLabel(for mode: TradeLevelMode) -> String {
        switch mode {
        case .structureATR: return "Market structure & volatility"
        case .fixedPercent: return "Fixed percentage distances"
        }
    }

    public static func displayLabel(for def: CalibrationWinDefinition) -> String {
        switch def {
        case .tp1OrTp2: return "Target 1 or Target 2 counts as a win"
        case .tp2Only: return "Target 2 only (Target 1 counts as breakeven)"
        }
    }

    public static func displayLabel(for pref: TradFiProviderPreference) -> String {
        switch pref {
        case .auto: return "Automatic with fallback"
        case .twelveData: return "Twelve Data (requires personal key)"
        case .biquote: return "biquote.io"
        case .yahooFinance: return "Yahoo Finance"
        }
    }

    public static func displayLabel(for exchange: CryptoExchangePreference) -> String {
        switch exchange {
        case .auto: return "Automatic with fallback"
        case .binanceVision: return "Binance Vision"
        case .okx: return "OKX"
        case .bybit: return "Bybit"
        case .kraken: return "Kraken"
        case .twelveData: return "Twelve Data"
        }
    }

    public static func displayLabel(for scope: CalibrationCategoryScope) -> String {
        switch scope {
        case .strongOnly: return "Strong setups only"
        case .strongAndTraps: return "Strong setups and trap warnings"
        case .allEvaluated: return "All evaluated setups"
        }
    }

    /// All plain-English option labels audited by `SettingsCopyTests`.
    public static var allPlainEnglishOptionLabels: [String] {
        var labels: [String] = []
        labels.append(contentsOf: TradFiLiveFeedMode.allCases.map(\.displayLabel))
        labels.append(contentsOf: CryptoLiveFeedMode.allCases.map(\.displayLabel))
        labels.append(contentsOf: DefaultChartViewMode.allCases.map(\.displayLabel))
        labels.append(contentsOf: ScanIntervalOption.allCases.map(\.displayLabel))
        labels.append(contentsOf: TradeLevelMode.allCases.map { displayLabel(for: $0) })
        labels.append(contentsOf: CalibrationWinDefinition.allCases.map { displayLabel(for: $0) })
        labels.append(contentsOf: TradFiProviderPreference.allCases.map { displayLabel(for: $0) })
        labels.append(contentsOf: CalibrationCategoryScope.allCases.map { displayLabel(for: $0) })
        return labels
    }
}

/// Reusable section header with a plain-English title and `(i)` popover trigger.
public struct SettingsSectionHeader: View {
    public let title: String
    public let helpKey: SettingHelpKey

    public init(_ title: String, helpKey: SettingHelpKey) {
        self.title = title
        self.helpKey = helpKey
    }

    public var body: some View {
        HStack(spacing: 6) {
            Text(title)
            ConfluenceInfoButton(helpKey)
        }
    }
}
