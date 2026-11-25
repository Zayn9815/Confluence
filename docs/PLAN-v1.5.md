# Confluence v1.5 Plan: Live Prices, Live Chart + Risk, AI Providers, Demo Wallet, Plain-English Settings, Auto-Scan, Win-Rate Breakdown

Status: Approved with Modifications 1–4. Executing M1 → M6 sequentially with green CI after each milestone.

## 0. Assumptions (defaults used, no questions asked)
- Version: `project.yml` is currently `1.3.0 (4)`. v1.4 Phase 3b (B1 remote alerts, `Packages/ConfluenceData`, `remote-scan.yml`, `RemoteAlertsSettingsView`) was NOT executed and none of those exist. v1.5 bumps to **`1.5.0 (5)`** (skips 1.4.0; Phase 3b stays pending and can ship later as 1.5.x/1.6).
- Scan interval default 30 min (Off/5/15/30/60), Low Power forces >= 30 min, min gap between scans 2 min, scan-on-open ON.
- Demo wallet $1,000. Leverage defaults: Crypto 1x, Stocks 1x, FX 30x, Gold 20x, Indices 20x. Fees OFF. "Show TradingView option" ON. Default chart view: Confluence chart (Recommended).
- Live service is foreground-only, cap 8 symbols, owner-based lifecycle (no background sockets). TradFi default: Auto — live stream with backup (Yahoo WebSocket -> `biquote.io`/Yahoo 10s polling). Crypto default: Live stream (Binance Vision WS, 3s REST fallback). Twelve Data strictly excluded from live streaming/polling.
- Wording everywhere: "Stop loss", "Target 1", "Target 2" (never "TP1"/"Take profit" in UI copy; chart axis tags stay concise `ENTRY`, `SL`, `TP1`/`T1`, `TP2`/`T2`, `BULL TRAP`, `BEAR TRAP`). Exit choice: "Target 1 | Target 2". Broker button: "Match to broker price".
- Paper trading only. No broker connection, no order execution.

## 1. Verified API facts (source)
| Fact | Source | Status |
|---|---|---|
| Binance market-data WS base `wss://data-stream.binance.vision`; raw `/ws/<stream>`, combined `/stream?streams=a/b`; lowercase symbols; kline `<symbol>@kline_<interval>` (`t,T,o,h,l,c,v,x` where `x` = closed); 2000 ms speed; server ping 20 s, pong <1 min; 24 h max conn; 5 msgs/s in; 1024 streams/conn | github.com/binance/binance-spot-api-docs web-socket-streams.md | Verified |
| Yahoo Live WebSocket `wss://streamer.finance.yahoo.com/`, subscribe `{"subscribe":["EURUSD=X","GBPUSD=X","GC=F","^GSPC","AAPL",...]}`, Base64-encoded `PricingData` Protobuf wire frames (field 1 `id: string`, field 2 `price: float` fixed32, field 3 `time: sint64` ms, field 8 `changePercent: float`, field 12 `marketHours: varint`) | User-verified Yahoo streamer proto wire spec | Verified |
| JS Lightweight Charts `series.update(bar, historicalUpdate?)`, `barsInLogicalRange`, `timeScale().subscribeVisibleLogicalRangeChange`, `createPriceLine/removePriceLine`, `pop` | tradingview.github.io/lightweight-charts/docs/api/interfaces/ISeriesApi | Verified (JS) |
| `LightweightChartsIOS` 5.2.0 Swift wrapper: `SeriesApi`, `TimeScaleApi`, `CandlestickSeriesOptions` (`update`, `scrollToRealTime`, `subscribeVisibleLogicalRangeChange`, `autoscaleInfoProvider`) | Inspect via `gh api` on `tradingview/LightweightChartsIOS` tag `5.2.0` at M3 step 0 | Verify at M3 step 0 (fallback: throttled `setData`) |
| DeepSeek: `GET https://api.deepseek.com/models` with `Authorization: Bearer <key>` returns `data[]` (`id`, `name`, `context_window`, `max_output_tokens`, `input_modalities`). Current IDs: `deepseek-flash` (default cheapest), `deepseek-v4-pro`. Disable thinking via top-level `{"thinking":{"type":"disabled"}}`; JSON mode `response_format:{"type":"json_object"}` (include word `"json"` in prompt) + blank-content retry | api-docs.deepseek.com/api/list-models/, quick_start/pricing, guides/json_mode, guides/thinking_mode | Verified |
| Gemini: `GET https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000` with `x-goog-api-key` header returns `{ models: [{ name, displayName, supportedGenerationMethods }], nextPageToken }`. Filter `supportedGenerationMethods.contains("generateContent")`, strip `"models/"` prefix, follow `nextPageToken` | aistudio.google.com/api-reference/models/list-models | Verified |
| OpenRouter: `GET https://openrouter.ai/api/v1/models` with `Authorization: Bearer <key>` returns `data[]` (`id`, `name`, `pricing: { prompt, completion }`). Free models: `:free` suffix and/or `prompt == "0" && completion == "0"` (20 RPM, 50 RPD free / 1,000 RPD with $10+ lifetime credits; display note in UI) | openrouter.ai/docs/api_reference/models | Verified |
| TradingView Advanced Chart embed inside lazy `WKWebView` HTML: `<script type="text/javascript" src="https://s3.tradingview.com/external-embedding/embed-widget-advanced-chart.js" async> { "autosize": true, "symbol": "<SYM>", "interval": "<TF>", "timezone": "Etc/UTC", "theme": "<dark|light>", "style": "1", "allow_symbol_change": false, "support_host": "https://www.tradingview.com" } </script>` + visible TradingView attribution + clean teardown on dismiss | tradingview.com/widget-docs/ | Verified |

## 2. Chart bug root cause & overlay preservation
1. **Only ~48 bars:** `ConfluenceScorer.swift:368` stores `recentCandles: Array(candles.suffix(48))`; `FullScreenChartSheet.swift:189` seeds `_activeCandles` from it. Fix: auto-fetch 500 bars on appear via `reloadChartData()` and lazy-load older pages on pan-left up to 5,000 bars (`HistoryMerge`). Keep `recentCandles` at 48 for mini-charts/cards.
2. **Preserve ALL Signal Chart Overlays (matching v1.3 `MSFT · 1H`):**
   - Entry (yellow/amber dashed + `ENTRY` tag), Stop loss (red solid + `SL` tag), Target 1 (green solid + `T1` tag), Target 2 (blue solid + `T2` tag when `isTP2Enabled`), ALL active Trap levels (`BULL TRAP` / `BEAR TRAP`, orange/amber dashed + tags), Live/Last price line (green/red dashed + live price tag), and Breakeven line (when SL moved to breakeven).
3. **Autoscale Fix (Do NOT hide Trap/Target lines arbitrarily):**
   - Fix 48k–80k stretch via `autoscaleInfoProvider` (if supported by `LightweightChartsIOS` 5.2.0) or by fitting visible Y-axis to visible candle high/low + Entry/SL/Target 1 + any Trap/Target 2 within ±20% of price with ~10–12% top/bottom `scaleMargins`, setting marker `autoScale: false`, and calling `fitContent()` ONLY on initial load or tapping **Reset**.
   - Keep ALL Trap, Entry, SL, Target 1, and Target 2 lines plotted on the chart; mark truly extreme >20% off-scale lines with an "off-scale" chip in the collapsible risk strip rather than removing them.

## 3. Invariants and execution rules
- `SignalEngine`: pure Swift 6, Foundation-only, causal, deterministic. Analysis uses CLOSED candles only. Forming/live candles are display-only and must never reach `SignalEngine`, `CandleHygieneEngine`, or `PassiveOutcomeEvaluator` (unit test enforced).
- SwiftData: additive only (new tables `DemoWalletRecord`, `DemoPositionRecord`, `DemoWalletTransaction` as 10th–12th models). Never modify existing `@Model` classes. Settings use `decodeIfPresent`.
- `SecretRedactor` (in `Services/Diagnostics/DiagnosticLogStore.swift`) extended for `sk-` and `sk-or-`. No secrets in git/IPA/logs/exports. `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` stays enabled.
- Run order M1 → M6. Commit + push after each milestone; verify via GitHub Actions CI only; fix CI failures with minimal diffs; do not stop between milestones unless blocked. Each milestone leaves the app building, tests green, shippable.

## 4. Milestones

### M1: SignalEngine pure logic + tests
New files in `Packages/SignalEngine/Sources/SignalEngine/`:
- `Live/LiveCandleAggregator.swift`: `LiveTick(price:epochSeconds:volume:)`, `LiveCandleAggregator(timeframe:seed:maxTickDeviationFraction:)`, `ingest(_:) -> LiveCandleUpdate` (`.formingUpdated(Candle)`, `.rolledOver(closed:forming:)`, `.rejected(String)`). Bad-tick guard (default 2% FX/gold/indices, 5% stocks, 8% crypto, configurable), price > 0 & finite, OTC `volume: nil` preserved.
- `Live/ChartScaleRange.swift`: `ChartScaleRange.compute(candles:levels:traps:maxOverlayDeviationFraction:marginFraction:) -> ChartScaleResult` (visible Y-range covering candles + Entry/SL/Target 1 + overlays within ±20%, plus list of off-scale overlay labels for risk-strip chips).
- `Live/HistoryMerge.swift`: `HistoryMerge.merge(existing:older:serverNowEpochSeconds:cap:) -> [Candle]` (sort ascending, dedupe by `openTimeEpochSeconds`, drop forming bar where `closeTimeEpochSeconds > serverNowEpochSeconds`, cap newest 5,000).
- `Demo/DemoWalletEngine.swift`:
  - `DemoWallet`, `DemoPosition`, `DemoOrderType` (`.market` / `.limit`), `DemoExitTarget` (`.target1` / `.target2`), `DemoOrderRequest`, `DemoMarginSpec.defaultLeverage(for: MarketClass)` (Crypto 1x, Stocks 1x, FX 30x, Gold 20x, Indices 20x), `DemoExecutionGuardResult`.
  - **Execution guards (Mod 3):** Reject Market fills if live quote age > 60s unless `allowStalePriceFill == true`; if market is closed (`SessionCalendar.marketStatus`), block Market fills with a clear message and recommend Limit order. Never invent synthetic bid/ask spreads; fill cleanly at observed live price (Market) or exact entry zone level (Limit), storing immutable fill/exit records and applying exact per-asset point/contract-value P&L math (`InstrumentContractSpec`).
  - Margin reserve/release, size clamp to free margin, Limit fill/expiry, pessimistic fill-bar SL-only & same-bar SL-first evaluation (consistent with `PassiveOutcomeEvaluator`), SL/TP edit validation (`updateStopLoss`, `updateTargets`, `moveStopLossToBreakeven`), optional fee deduction, equity = balance + unrealized.
- `Scheduling/ScanSchedulePolicy.swift`: `ScanIntervalOption` (off, 5m, 15m, 30m default, 60m), `effectiveIntervalMinutes(isLowPowerMode:)`, `shouldScanOnOpen(lastScanEpoch:nowEpoch:minGapSeconds:)`, `estimatedDailyRequests(symbolCount:intervalMinutes:isLowPowerMode:)`.
- `Calibration/WinRateBreakdown.swift`: `SignalOrigin` (`.scanner`, `.news`), `OriginWinRateBucket` (Strong signals / Traps and filtered / News setups), `StrengthWinRateBucket` (50–59.99, 60–69.99, 70–79.99, 80+), exact Wilson 95% CI + `n`. Trap alerts without levels counted via `TrapEvaluationHelper` (respected = "Worked", closed through = "Failed"); that card labels counts `"Worked / Failed"`.
- Modify `SignalModels.swift`: add `origin: SignalOrigin` to `TradeSignal` and `SignalOutcomeRecord` (`decodeIfPresent`, default `.scanner`).
Tests (`Packages/SignalEngine/Tests/SignalEngineTests/`): `LiveCandleAggregatorTests`, `HistoryMergeTests`, `ChartScaleRangeTests`, `DemoWalletEngineTests` (per-asset-class P&L, margin reserve/release, size clamp, limit fill/expiry, stale quote >60s rejection + override, market-closed Market block, same-bar SL-first, fill-bar SL-only, SL/TP edit validation, breakeven), `ScanSchedulePolicyTests`, `WinRateBreakdownTests` (bucket boundaries 59.99/60/69.99/70/79.99/80, empty bucket, trap worked/failed, Wilson CI), `LegacyOriginDecodeTests`, `FormingCandleNeverReachesEngineTests`.
Acceptance: `swift test --package-path Packages/SignalEngine` green in CI.

### M2: Live services, Yahoo WebSocket, history paging, TradeMonitor, additive SwiftData
- `Confluence/Data/Adapters/Live/YahooLiveStreamAdapter.swift`: pure-Swift `URLSessionWebSocketTask` client for `wss://streamer.finance.yahoo.com/`, JSON subscribe `{"subscribe":[...]}`, ~60-line zero-dependency Base64 `PricingData` Protobuf decoder (field 1 `id: string`, field 2 `price: float` fixed32, field 3 `time: sint64` ms, field 8 `changePercent: float`, field 12 `marketHours: varint`), bad-tick guard (>2% FX/gold/indices, >5% stocks), scale guard (never mix `SPY` into `US500`; if `GC=F` diverges from spot `XAU/USD` beyond scale threshold, auto-fallback to `biquote.io` polling for `XAU/USD`).
- `Confluence/Services/Live/LivePriceService.swift`: `actor LivePriceEngine` + `@MainActor final class LivePriceService: ObservableObject`. API: `acquire(owner:symbols:)`, `release(owner:)`, `latest(symbol:) -> LivePriceQuote?` (`price`, `asOf`, `freshness: .live/.delayed/.offline`, `sourceLabel`).
  - Crypto modes (`CryptoLiveFeedMode`): `.liveStream` (Binance Vision WS `wss://data-stream.binance.vision`, 3s REST fallback), `.poll3s`, `.off`.
  - TradFi modes (`TradFiLiveFeedMode`): `.autoStreamWithBackup` (Yahoo WS -> `biquote.io`/Yahoo 10s polling), `.liveStreamOnly`, `.poll10s`, `.off`. Twelve Data strictly excluded.
  - Stops on `scenePhase != .active`; max 8 symbols (LRU drop); Binance ping/pong & 23h proactive reconnect.
- `Confluence/Services/Live/TradeMonitor.swift`: reconciles open demo & journal positions against closed bars (`PassiveOutcomeEvaluator`) and live ticks; auto-close writes exact exit price (Target 1 / Target 2 / Stop loss). Fixes `JournalEntryEditorSheet.saveEntry()` so setting an exit price derives outcome cleanly (no "OPEN + exit + R"). Manual trades never auto-close; they surface an Apply/Dismiss chip.
- History paging: extend `fetchChartCandles(symbol:timeframe:providerChoice:limit:endTimeEpochSeconds:)` in `MarketScannerCoordinator` + Binance `endTime`, OKX `after`, TwelveData `end_date`.
- `ConfluenceV2Models.swift` / `ConfluenceDataStore.swift`: add additive SwiftData models `DemoWalletRecord`, `DemoPositionRecord`, `DemoWalletTransaction` (10th–12th models). Bump `BackupArchiveService.currentSchemaVersion = 2` (v1 still importable; new arrays via `decodeIfPresent`). Add CSV export for wallet transactions.
- `AppSettingsStore.swift`: add `tradFiLiveFeedMode`, `cryptoLiveFeedMode`, `defaultChartViewMode`, `showTradingViewOption`, `scanOnOpenEnabled`, `autoScanIntervalMinutes` (default 30), `demoWalletFeesEnabled`, all with `decodeIfPresent` defaults.
- `SecretRedactor` (`DiagnosticLogStore.swift`): add `sk-` and `sk-or-` patterns.
Tests (`ConfluenceTests`): `YahooProtobufDecoderTests`, `LivePriceServiceTests`, `TradeMonitorTests`, `DemoWalletMigrationTests` (on-disk v1.3 store reopened with new schema), `BackupV2RoundTripTests` (+ v1 import), `SecretRedactorTests`.

### M3: Full-screen chart (W2 + Mod 1)
- **Step 0:** Inspect `LightweightChartsIOS` v5.2.0 Swift source via `gh api` (`SeriesApi`, `TimeScaleApi`, `CandlestickSeriesOptions`) to confirm exact signatures for `update`, `scrollToRealTime`, `subscribeVisibleLogicalRangeChange`, `autoscaleInfoProvider`.
- `FullScreenChartSheet.swift`:
  - Auto-fetch 500 bars on appear via `reloadChartData()`; lazy older pages on pan-left (cap 5,000, `HistoryMerge`).
  - Preserve ALL overlays: Entry (`ENTRY`), Stop loss (`SL`), Target 1 (`T1`), Target 2 (`T2` when enabled), all active Traps (`BULL TRAP` / `BEAR TRAP`), Live/Last price line, and Breakeven line (when moved to BE).
  - Autoscale fix via `autoscaleInfoProvider` (or `scaleMargins` ~10–12% + `ChartScaleRange`), marker `autoScale: false`, `fitContent()` ONLY on initial load or **Reset** button; off-scale (>20%) lines remain plotted and show an "off-scale" chip in the risk strip.
  - Live forming candle via `series.update` (or throttled `setData` <= 1/s fallback); freshness badge ("Live" / "Updates every ~10s" / "Delayed" / "Offline").
  - Collapsible **Risk strip** (distance %, R, $ at wallet size, off-scale chips); labeled **Trade** button replacing bookmark icon; position actions: Close now, Move stop loss to breakeven, Edit stop loss / targets.
  - Rename broker-offset button to "Match to broker price".
- `MiniCandlestickCanvas.swift`: redraw from live price at most 1/s.
Tests: `ChartViewModelTests`.

### M4: Wallet UI, Journal live rows, notifications, scan schedule, win-rate cards
- `Confluence/UI/Wallet/DemoWalletView.swift`, `PlaceDemoTradeSheet.swift` ("Demo" vs "Log real trade", margin/leverage, size, "Target 1 | Target 2" exit choice, stale-price confirmation & market-closed Limit suggestion), balance edit, `All / Demo / Real` chips in Journal.
- Journal live rows: live price, P/L in R / % / $, progress bar from Stop loss to Target 1, OFFLINE badge, Apply/Dismiss chip for manual trades hitting levels.
- `NotificationCenterRouter`: immediate local notifications on demo trade close (respecting the 40-slot pre-news budget).
- W7 wiring: `MarketScannerCoordinator.scanOnOpenIfDue()`, timer/scheduler via `ScanSchedulePolicy`, Settings row with next-scan countdown & daily usage estimate.
- W8: `StatsCalibrationTabView` shows 3 cards (**Strong signals**, **Traps and filtered**, **News setups**) + `WinRateBreakdownView` strength buckets (empty buckets read `"No trades yet"`); every win rate displays `n` and Wilson 95% CI. Weak/filtered signals tracked passively for stats even when "Show Weak / Filtered" is OFF (no cards/notifications). `NewsTradeAnalysisSheet` tracks setups with `origin = .news`.
Tests: `JournalLiveRowTests`, `ScanOnOpenTests`, `WinRateBreakdownViewModelTests`.

### M5: AI providers (W3 + Mod 4)
- `Confluence/Data/AI/AIJudgeClient.swift`: `protocol AIJudgeClient: Sendable` (`judge`, `listModels`), `AIProviderOption` (`.gemini`, `.deepseek`, `.openrouter`), `AIModelInfo`.
- `GeminiJudgeClient` conforms (strict JSON, `x-goog-api-key`, `GET /v1beta/models?pageSize=1000` with `nextPageToken` pagination & `generateContent` filter).
- `OpenAICompatibleJudgeClient`: DeepSeek (`deepseek-flash` default, `deepseek-v4-pro`, `GET /models`, `thinking: {type: "disabled"}`, `response_format: {type: "json_object"}`, blank-content retry) and OpenRouter (`GET /api/v1/models`, `:free` / zero-price badge + rate-limit UI note: 20 RPM, 50 RPD free / 1,000 RPD with $10+ credits).
- Per-family request shaping, 1 retry on 400 with relaxed params, friendly 429 message, shared daily cap across providers.
- `KeychainStore.SecretKey`: add `deepseek`, `openrouter`.
- `AppSettingsStore`: add `aiProvider`, `aiModelID`; migrate legacy `geminiModel` cleanly.
- Settings: provider & model picker always visible (not behind Advanced), "Test key" fetches live model list. `NewsTradeAnalysisSheet` routes through selected provider. AI still cannot override code risk/confluence gates; app works 100% with AI OFF.
Tests: `AIProviderRequestTests` (mocked `URLProtocol` for Gemini/DeepSeek/OpenRouter discovery, headers, 400 retry, 429, blank retry), `AISettingsMigrationTests`.

### M6: Plain-English settings, TradingView, version, docs, ship
- `Confluence/UI/Settings/SettingsCopy.swift`: `enum SettingHelpKey: CaseIterable` -> title, subtitle, help text; `InfoButton` `(i)` popover. Apply plain-English display copy across Settings (including Mod 2 live-feed & default chart view pickers). Never rename Codable keys/raw values.
- `SettingsCopyTests`: non-empty help for every key; whole-word case-sensitive jargon check on option labels & subtitles only (not help text), ignoring `"Confluence"`.
- W6: `TradingViewSymbolMapper` (pure; BTC/USDT -> `BINANCE:BTCUSDT`, GBP/USD -> `OANDA:GBPUSD`, XAU/USD -> `OANDA:XAUUSD`, indices via widget-safe CFD symbols), "Open in TradingView" (`tradingview://` -> https fallback), lazy `WKWebView` widget embed (Mod 4 snippet + attribution + teardown), segmented `Confluence | TradingView` toggle in `FullScreenChartSheet` when `"Show TradingView option"` is ON, honoring default chart view setting. Tests: `TradingViewSymbolMapperTests`.
- `project.yml` -> `MARKETING_VERSION: "1.5.0"`, `CURRENT_PROJECT_VERSION: "5"`; update About / backup copy (`schemaVersion = 2`).
- Update `AGENTS.md` and `PROGRESS.md` (forming-bar display-only invariant, paper-only demo wallet, same-bar SL-first applies to demo trades, settings copy lives in `SettingsCopy.swift`, v1.5 changelog, Phase 3b still pending).
- Final CI: `SignalEngine` tests, `xcodegen`, Simulator tests, Release `iphoneos` build, `Info.plist` secret guard, unsigned `Confluence-unsigned-ipa` artifact.

## 5. Manual iPhone checklist (post-ship)
1. Journal: live P/L updates; airplane mode shows OFFLINE badge.
2. Chart: live candle moves; pan left loads older history; price scale fits (BTC ~59k, no 48k–80k stretch) while all Entry/SL/T1/T2/Trap lines stay plotted; Reset works; risk strip collapses.
3. AI: picker visible with Advanced OFF; "Test key" lists models; DeepSeek key works.
4. Demo trade: Target 1 | Target 2 exit, margin reserve, auto-close, edit stop loss/targets, balance edit.
5. Scan on open runs; 30-min countdown; usage estimate shown.
6. Settings read in plain English with `(i)` popovers, including live-feed & chart-view pickers.
7. Stats: three win-rate cards + bucket breakdown; empty buckets read `"No trades yet"`.

## 6. Out of scope
Broker connection or order execution, remote scanner (Phase 3b), widgets, new data providers, any server.
