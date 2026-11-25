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

