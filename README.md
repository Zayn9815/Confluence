# Confluence (Confluence Terminal)

An institutional-grade, strictly read-only native iPhone multi-market analysis terminal (**Swift 6 + SwiftUI**, iOS 17+, Bundle ID `com.bilal.confluence`) that analyzes live OHLCV candles, public Pro-vs-Retail positioning, economic calendar releases, and breaking financial news using deterministic ICT/SMC + Candlestick + Trend/Momentum + Behavioral Finance Trap Lifecycle + Macro Surprise strategies.

## Highlights
- **Pure Swift 6 `SignalEngine` (`Packages/SignalEngine`):** Zero UI imports (`Foundation`-only) + portable JSON schemas (`Specs/schemas/`) ready for future 1:1 Kotlin/Android parity.
- **Strictly Causal & Anti-Repainting:** Closed-candle enforcement, UTC `1H -> 4H` resampling, clock-skew guard, OTC `volume == nil` (`RVOL = N/A`) honesty, and prefix-invariant ICT/SMC detectors.
- **Behavioral Psychology & 4-Stage Trap Lifecycle:** `Trigger -> Active -> Returned -> Invalid` (invalidated ONLY on candle close through level) covering Osler round-number stop-clusters, Barber-Odean attention FOMO spikes, post-news whipsaw traps, OKX Funding/OI (`1Dutc` aligned), and weekly CFTC COT positioning.
- **3-Stage Macro News & Whipsaw Shield:** Keyless `biquote.io` primary calendar (null-safe `actual`, `timeMode == exact` enforcement, simultaneous release clustering) + disk-cached Forex Factory fallback + 40-slot iOS pre-news notification scheduler (respecting iOS's 64-notification limit).
- **Optional Gemini 4 Hydrogen Judge:** Works 100% natively OFF; optional `gemini-4-hydrogen` (`thinkingLevel: LOW`, strict JSON schema, encrypted Keychain storage, daily call cap) can never override hard code gates.
- **Unsigned `Confluence.ipa` CI Pipeline:** Automatically tested and built via `.github/workflows/build-ipa.yml` on `macos-latest`.

## Attribution
- Developer : Bilal ([GitHub](https://github.com/Zayn9815))
- Full-screen interactive charts and UI animations powered by `CandleKit`, `DGCharts`, `Pow`, and `PopupView`.
