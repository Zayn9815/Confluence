# Confluence — Engineering & Agent Rules (`AGENTS.md`)

> Read `AGENTS.md` and `PROGRESS.md` first in every session.

## 1. Product Identity & Hard Boundaries
- **App Display Name:** `Confluence` (Subtitle: `Confluence Terminal`)
- **Bundle Identifier:** `com.bilal.confluence`
- **Target Platform:** Native iOS 17+ (`Swift 6` + `SwiftUI`), unsigned `Confluence.ipa` built on GitHub Actions `macos-latest`.
- **Developer Credit (Settings -> About):** `Developer : Bilal`
- **Links (Settings -> About):** Developer Profile `https://github.com/Zayn9815` + Project Repository `https://github.com/Zayn9815/Confluence`.
- **Read-Only Analysis Only:** Never add order execution, brokerage write endpoints, or trading/exchange private keys.

## 2. Two-Layer Architecture & Portability Rules
1. **`Packages/SignalEngine` (Pure Swift 6, Foundation-only):**
   - ZERO `SwiftUI`, `UIKit`, `Combine`, `AVFoundation`, `CoreHaptics`, or `SwiftData` imports.
   - 100% deterministic, strictly causal, non-repainting.
   - All public models conform to `Codable`, `Sendable`, `Equatable`, and align with `Specs/schemas/*.json` for future 1:1 Kotlin/Android parity.
   - **Code owns ALL numbers:** Entry Zone, Stop Loss, TP1, TP2, % risk, % gain, R:R, Confidence %, and regime/risk gating are computed exclusively in deterministic Swift code.
2. **Optional AI Judge (`GeminiJudgeClient`):**
   - Model ID: `gemini-4-hydrogen`, `thinkingLevel: "LOW"`, `maxOutputTokens: 2048`, strict JSON schema, API key sent exclusively via `x-goog-api-key` header (never query params, never logged).
   - App MUST function 100% natively with AI OFF.
   - AI can NEVER override hard code risk limits, `crisis` suppression, confluence gate (`>= 3`), or numeric SL/TP levels.
   - Hard confirmation rule in code: badge = Confirmed ONLY when `agree == true && setupQuality >= 2 && confidence >= threshold && riskState == .safe`.

## 3. Causality, Hygiene & Zero-Mock-Data Invariants
- **Closed-Candle Anti-Repainting:** Drop any open/forming bar (`closeTime > serverNow` or exchange `confirm == "0"` or `isOpen == true`) before running detectors.
- **Prefix Invariance:** Every detector (`CausalICTDetector`, `CandlestickPatternDetector`, `TrendMomentumDetector`, `TrapLifecycleEngine`) MUST produce identical output at bar `t` whether given bars `0...t` or `0...N`.
- **No Fake Data in UI:** Never hardcode mock signals, fake win-rates, or fabricated news prints in production views. Empty states must honestly guide the user to run a live scan.
- **OTC Volume Honesty:** When an OTC/FX feed has no real volume (`volume == 0` or missing), store `volume: nil` and report `RVOL = N/A` (never fake `0`).
- **Economic Calendar Safety:**
  - `actual == nil` means unpublished — NEVER coerce `nil` to `0`.
  - `timeMode != .exact` suppresses countdown timers and local pre-news notifications.
  - Forex Factory fallback must enforce >= 60-minute refresh cooldown, 24-hour disk cache fallback, and validate HTTP `Content-Type` + leading `[` to reject HTTP 200 HTML `"Request Denied"` responses.
  - Respect iOS's 64-notification queue limit by capping pre-news notifications at a strict 40-slot budget (`confluence.prenews.*`).
- **OKX OI UTC Alignment:** Always request `period=1Dutc` (never `1D`) for daily OI bars; respect 1,440-point cap.
- **CFTC COT Lookahead Guard:** COT Tuesday snapshots are only observable after Friday 20:30 UTC release.

## 4. Swift 6, Dependencies & Battery Discipline
- Enable Swift 6 strict concurrency and warnings-as-errors on `SignalEngine` and `Confluence` app targets.
- Pinned dependencies in `project.yml`:
  - `EmergeTools/Pow` pinned to commit `1b4b1dda28c50b95f0872927ee2226fe8b58950e` (fixes Swift 6.1+ `.pi` ambiguity in `1.0.5`).
  - `exyte/PopupView` from `5.0.9`.
  - `markiv/SwiftUI-Shimmer` from `1.5.1` (product `Shimmer`).
  - `tradingview/LightweightChartsIOS` from `5.2.0` (product `LightweightCharts`, Apache 2.0 attribution required in Settings -> About).
  - Keychain storage uses native Swift 6 `Security.framework` (`KeychainStore`) — zero external dependency, no `unsafeFlags`.
- **Battery:** Zero persistent WebSockets, zero continuous idle animations, `LazyVStack` on feeds, pure SwiftUI `Canvas` for Signal Card mini-charts (`LightweightCharts` instantiated lazily ONLY on full-screen sheet).
- **Audio:** Custom `.caf` files live at the root of `Confluence.app`. Use `AVAudioSession.Category.ambient` with `.mixWithOthers` so hardware mute switch is always respected.

## 5. Verification Checklist Before Shipping
1. `swift test --package-path Packages/SignalEngine` passes 100% (including prefix-invariance causality, trap lifecycle, calendar/news edge cases, walk-forward replay net of fees/slippage, and Brier score).
2. GitHub Actions `.github/workflows/build-ipa.yml` on `macos-latest` succeeds: `xcodegen generate`, `xcodebuild test`, Release `iphoneos` build (`CODE_SIGNING_ALLOWED=NO`), bundle asset sanity check, and unsigned `Confluence.ipa` artifact upload.
3. Never commit API keys or secrets.
