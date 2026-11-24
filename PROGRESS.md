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
- Next: Push branch to GitHub and verify the real `macos-latest` CI workflow run end-to-end (unit tests, simulator tests, Release build, and unsigned `Confluence.ipa` artifact)!
