# Confluence — Engineering Progress & Decision Log (`PROGRESS.md`)

## Phase 0 — Plan & Deep Engineering Audit (Approved)
- **Date:** 2026-11-24
- **Audit Decisions Approved by User:**
  1. **Keychain:** Replaced `kishikawakatsumi/KeychainAccess` (blocked by SPM `.unsafeFlags` and Swift 5.0/2021 stagnation) with native Swift 6 `Sendable` `Security.framework` actor `KeychainStore`.
  2. **`EmergeTools/Pow`:** Pinned to commit `1b4b1dda28c50b95f0872927ee2226fe8b58950e` on `main` (fixes Swift 6.1+ `ambiguous use of '.pi'` broken in `1.0.5`).
  3. **`twostraws/Inferno`:** Skipped to avoid headless CI Metal shader friction; metallic A+ sheen delivered with `Pow` + native SwiftUI materials/gradients.
  4. **FX/Gold Keyless OHLC Fallback:** Added `biquote.io/api/{symbol}/ohlc` behind Yahoo Finance (`User-Agent: Mozilla/5.0` + causal `1h -> 4h` resampler).
  5. **News Route Fix:** Used verified `cryptocurrency.cv/api/fear-greed` (with `api.alternative.me/fng/` fallback) and merged `/api/breaking` + `/api/news` + `biquote.io/api/news/market` (HN filtered) + optional Finnhub + native `XMLParser` financial RSS.

## Phase 1 — Repository Scaffolding, JSON Schemas & Asset/Sound Generators (Completed)
- Created `AGENTS.md`, `PROGRESS.md`, `.gitignore`, and portable JSON schemas (`Specs/schemas/*.json`).
- Built pure-Python deterministic generators (`scripts/generate_sounds.py`, `scripts/generate_assets.py`) producing all 5 Linear PCM `.caf` alerts and the matte obsidian + champagne-gold candlestick/BOS `AppIcon-1024.png`.

## Phase 2 — Pure Swift 6 `SignalEngine` Package (Completed)
- Built `Packages/SignalEngine` (`swift-tools-version: 6.0`, Foundation-only, zero UI imports):
  - Models (`MarketTypes`, `Candle`, `PositioningModels`, `MacroModels`, `TrapModels`, `PsychologyModels`, `SignalModels`).
  - Causal Hygiene (`CandleHygieneEngine`, `SessionCalendar`, `1H -> 4H` UTC resampler).
  - `MarketRegimeClassifier` (hard `crisis -> .reduce` rule).
  - Strictly causal `CausalICTDetector`, `CandlestickPatternDetector`, `TrendMomentumDetector`.
  - `TrapLifecycleEngine` (`trigger -> active -> returned -> invalid` on close-through only), `PositioningAnalyzer` (OKX `1Dutc` + CFTC COT Friday lag), `PsychologyReportBuilder` (zero generic filler).
  - `MacroPolarityTable`, `MacroSurpriseEngine` (null-safe actual, `timeMode != .exact`, simultaneous cluster impulse, 40-slot pre-news queue planner), `HeadlineSentimentClassifier`.
  - `TradeLevelCalculator`, `ConfluenceScorer` (`>= 3` gate, calibrated Confidence %, dedup), `PassiveOutcomeEvaluator` (Brier score), `WalkForwardReplayEngine` (fees + slippage vs Buy-and-Hold).
  - Comprehensive unit tests (`SignalEngineCoreTests`, `BehavioralAndMacroTests`, `ScoringAndCalibrationTests`).

## Phase 3 — Data, Positioning, News & Optional AI Adapters (Completed)
- Implemented `HTTPClient` (429 `Retry-After`, backoff, clock-skew, `ProviderRatePacer`), `KeychainStore`, `CryptoOHLCVRouter` (Binance Vision -> OKX -> Kraken), `TradFiOHLCVRouter` (Yahoo `Mozilla/5.0` -> biquote -> Twelve Data), `OKXPositioningAdapter` (`1Dutc`), `CFTCCOTAdapter` (weekly disk cache), `EconomicCalendarService` (biquote + 60m-cooldown FF fallback with HTML guard), `BreakingNewsService`, and optional `GeminiJudgeClient` (`gemini-4-hydrogen`, `thinkingLevel: LOW`, `maxOutputTokens: 2048`, `x-goog-api-key`).

## Phase 4 — Persistence, Alerts, Audio & Scanner Coordination (Completed)
- Implemented `AppSettingsStore`, `ConfluenceDataStore` (SwiftData + JSON export + cache reset), `SignalSoundEngine` (`AVAudioSession.Category.ambient` + `CoreHaptics`), `PreNewsNotificationScheduler` (40-slot cap + `.caf`), and `MarketScannerCoordinator` (`BGAppRefreshTask`).

## Phase 5–7 — Institutional Liquid Glass UI, XcodeGen, Integration Tests & CI IPA Build (Completed)
- Built `ConfluenceTheme` (Obsidian Terminal, AMOLED Vault, Porcelain Desk), 120Hz `MiniCandlestickCanvas`, lazy `FullScreenChartSheet` (`LightweightChartsIOS` 5.2.0), `SignalCardView` (`Pow` `.shine`/`.pulse`), 5 tabs (Signals, News & Macro, Markets & Scanner, Calibration Stats, 7-section Settings with `Developer : Bilal` & GitHub links), `ConfluenceRootView` (`PopupView`), `project.yml`, `ConfluenceTests`, and `.github/workflows/build-ipa.yml`.
- **CI Verification (`macos-latest`, Run `45509159987`, commit `e398c38`) — PASSED 100%:**
  - `afinfo` validated all 5 generated `.caf` alerts (`terminal_chime`, `sonar_pulse`, `vault_lock`, `trap_warning`, `news_release_ping`).
  - `SignalEnginePackageTests`: **17/17 passed** (0 failures, 0.233s) covering prefix-invariance causality, closed-bar hygiene, OTC `nil` volume, crisis regime risk-reduce, 4-stage trap lifecycle, OKX `1Dutc` short-squeeze, CFTC COT Friday lag, `biquote.io` null-actual & non-exact timeMode guards, simultaneous macro clustering, 40-slot notification cap, Reflex AI code rule, Brier score, and walk-forward replay net of fees/slippage.
  - `ConfluenceTests` (iOS Simulator, Swift 6 strict concurrency + `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`): **6/6 passed** (0 failures, 0.132s).
  - Release `iphoneos` (`CODE_SIGNING_ALLOWED=NO`) compiled with zero warnings; verified `CFBundleIdentifier == com.bilal.confluence`, all 5 root `.caf` alerts, and `LightweightCharts_LightweightCharts.bundle/lightweight-charts.js`.
  - Uploaded unsigned **`Confluence-unsigned-ipa`** (`3.3 MB`, Artifact ID `14974658207`, SHA256 `72bcd0fd6d20ffd42c8222777104410d39b6d1bb57c374ce3d1eaf1e8e450827`).

## Phase 8 — v1.1 Upgrade: Notification Bell Inbox, Twelve Data + biquote.io Switcher, Chart UX, Antigravity Diagnostics & Drill-Down Settings Hub
- **Notification Bell & Persistent Stored Inbox:** Added `NotificationCenterRouter` (`UNUserNotificationCenterDelegate`), `StoredNotificationItem` (250-item SwiftData cap), `NotificationBellButton` across all tabs, `NotificationInboxSheet` (`All`/`Signals`/`Traps`/`News`, `Today`/`Earlier`, swipe actions, deep-link scrolling + 2.2s highlight pulse).
- **First-Class Twelve Data + biquote.io Default + Yahoo Finance Fallback:** Added `TwelveDataAdapter` (`timezone=UTC`, native `15min`/`1h`/`4h`/`1day`, `Authorization: apikey`, HTTP-200 error code handling, 7/min & 780/day `ProviderRatePacer`, `/api_usage` live quota check), `BiquoteAvailabilityCache` for unsupported symbols, `SPY`/`QQQ` watchlist & ETF proxy safety, and optional CI `TWELVE_DATA_API_KEY` secret injection into `Info.plist`.
- **Full-Screen `LightweightCharts` Upgrade:** Live in-chart Data Provider & Timeframe switchers, `TimeScaleOptions(timeVisible: true, secondsVisible: false)`, explicit pan/pinch `handleScroll`/`handleScale`, `autoSize: true`, `.interactiveDismissDisabled(true)`, manual refresh, ETF proxy banner, and exact last closed candle UTC footer.
- **Comprehensive App Logs & Antigravity Diagnostics:** Additive SwiftData v1.1 models (`DiagnosticLogEntry`, `TrapLogEntry`, `TradeLedgerEntry`) preserving v1.0 `PersistedSignalRecord` migration compatibility + SQLite quarantine fallback, `SecretRedactor` scrubbing, `DiagnosticLogStore` + `OSLog`, per-strategy best/worst pair & regime failure analysis, post-trap respect accuracy, and 1-tap **"Copy Antigravity Report"** (Markdown) + **"Share Full Diagnostic JSON"**.
- **Drill-Down Settings Hub:** Refactored `SettingsTabView` into a clean 7-row icon-badged hub drilling into dedicated sub-screens (`Appearance`, `Notifications & Sound`, `Markets, News & Feeds`, `Signal Engine & Psychology`, `AI Second-Opinion` with Gemini model picker, `Logs & Diagnostics`, `About & Developer`).
- **CI Verification (`macos-latest`, Run `45530845391`, commit `15d296c`):** 19/19 `SignalEngine` tests + 10/10 Simulator `ConfluenceTests` passed; uploaded `Confluence-unsigned-ipa` (`3.8 MB`, Artifact ID `14984094537`).

## Phase 9 — v1.2.0 Upgrade: Theme Toggle, TradingView Dynamic Price Precision, Signal/Risk/Win-Rate Rules & Interactive Strategy Trade Replay
- **Top-Left Dark/Light Toggle:** Removed the wrapped scan-time pill (`8:28 AM`) in `SignalsTabView` and replaced it with `ThemeModeToggleButton` (`sun.max.fill` / `moon.fill`, light haptic feedback, remembers `lastDarkThemePreset`).
- **TradingView-Style Dynamic Price Precision:** Added pure-Swift `ChartPricePrecision` (`5` dp / `0.00001` for non-JPY FX & `<10`, `4` dp / `0.0001` for `<100`, `3` dp / `0.001` for `JPY`, `2` dp / `0.01` for `>=100`) applied to `LightweightCharts v5.2.0` `CandlestickSeriesOptions.priceFormat` and `VisiblePriceScaleOptions.minimumWidth` on creation and live provider/timeframe switches.
- **Signal Rules, Risk/TP, Strategy Selection & Win-Rate Controls:** Added `SignalRulesSettingsView` (backwards-compatible `PersistedSettingsPayload` defaults) supporting `Structure/ATR` vs `Fixed % Ratio` (`SL %`, `TP1 %`, optional `TP2 %`), `enableTP2Target`, Confidence % presets (`65%+`/`70%+`/`80%+`/`90%+`), `Default` / `Custom` (`Require All Selected` or clamped `Any + Min Confluence`) / `Random Subset` strategy modes, and live `CalibrationFilterConfig` (`TP1 or TP2 = Win` vs `TP2 Only = Win` with separate `TP1 Partial` tracking, category scope, min confidence, min R:R).
- **Interactive Strategy Reliability Ranking -> Trade List -> Win/Loss Chart Replay:** Made every row in `StatsCalibrationTabView` a `NavigationLink` to `StrategyTradesView` (`All`/`Wins`/`Losses`/`Open`), and added **Trade Replay Mode** to `FullScreenChartSheet` backed by additive SwiftData `TradeReplayCandleCache` + verified `LightweightCharts v5.2.0` `SeriesMarkersPlugin` pinning exact Entry & Exit (WIN/LOSS) candles.
- **CI Verification (`macos-latest`, Run `45546502336`, commit `ed7b576`):** 23/23 `SignalEngine` tests + 13/13 Simulator `ConfluenceTests` passed; uploaded `Confluence-unsigned-ipa` (`4.0 MB`, Artifact ID `14992765155`).

## Phase 10 — v1.3.0 Upgrade: Full Quantitative Math Audit Fixes, Persisted Timestamps, Signal Deletion, Crash/Error Logs & Interactive News Trade Analysis
- **11 Audited Quantitative & Engineering Fixes:**
  - `TradeLevelCalculator`: Added timeframe-aware R:R (`TP1 <= 4.0R`, `TP2 <= 6.0R`) and ATR ceiling (`<= 8x` on `15m`, `<= 10x` on `1H+`) caps in `.structureATR` mode, eliminating unrealistic `TP2 1:16.7` outliers while preserving `.fixedPercent` verbatim.
  - `ConfluenceScorer` + `SignalStrengthBreakdown`: Replaced saturating linear confidence with a 4-pillar (`Technical Math`, `Psychology & Positioning`, `News & Macro`, `Regime / Risk Adj.`) calibrated logistic curve (cap `<= 92%`, closed-market `-12` penalty capped `<= 72%`).
  - `PsychologyReportBuilder`: Separated **Intraday Pro Flow** (`proDirection`) from **Weekly Macro COT / OKX Bias** (`macroPositioningDirection`, `macroPositioningLabel`, `macroAlignsWithSetup`) to eliminate counter-trend weekly COT contradictions.
  - `CausalICTDetector`, `TrendMomentumDetector`, `MarketRegimeClassifier`, `CandleHygieneEngine`, `SignalEngine`: Gated FVG/OB proximity by causal 14-bar ATR, fixed flat-market `RSI == 50.0` & 3-bar pivot RSI divergence, excluded `currentATR` from baseline z-score + added asset-class drawdown thresholds, distinguished 23/5 futures/CFD index hours (`NAS100`, `US500`) from US cash hours (`SPY`, `QQQ`, stocks), eliminated duplicate detector passes, and fused live `breakingNews` + `fearGreed` into `SignalEngine.analyze(...)`.
  - `HeadlineSentimentClassifier`, `MacroPolarityTable`, `MacroNewsAdapters`: Fixed word-boundary matching (so `"Central Bank"` never triggers `"ban"`), expanded USD macro impacts (`NAS100`, `GBP/USD`, `SPY`, `QQQ`, US stocks), and replaced `abs(hashValue)` with deterministic FNV-1a 64-bit hex IDs.
- **UI/UX, Signal Deletion & Persisted Timestamps:** Fixed iOS 27 Liquid Glass toolbar clipping via discrete `ToolbarItem`s (Dark/Light toggle, Manage/Select menu, Scan, Bell), added persisted `Generated Date · Time · age` stamp, stacked zero-truncation `ENTRY ZONE`, expandable `Signal Strength Breakdown`, and permanent single/multi-select/tab/all signal deletion decoupled from Calibration Stats via additive SwiftData `PersistedOutcomeRecord`.
- **Native Crash & Error Logs:** Added additive `CrashLogEntry` + `CrashLogStore` (`MetricKit` `MXMetricManagerSubscriber` + `NSSetUncaughtExceptionHandler` + async-signal-safe POSIX breadcrumbs + `SecretRedactor` scrubbing) and dedicated **All Runtime Logs**, **Error Logs**, and **Crash & Hang Logs** viewers in `DiagnosticsHubView` + Antigravity exports.
- **Interactive News & Calendar Analysis:** Added pure-Swift `NewsTradeAnalyzer` and `NewsTradeAnalysisSheet` making every Breaking News article and Economic Calendar event tappable to inspect expected market direction per pair and generate fused News+Math trade setups (with 1-tap interactive chart launch) or explicit `WAIT / NO TRADE` safety verdicts.



