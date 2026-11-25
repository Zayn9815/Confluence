import SwiftUI

public struct GlossaryTerm: Identifiable, Sendable {
    public let id: String
    public let term: String
    public let category: String
    public let definition: String
}

/// Searchable 40-term quantitative, ICT/SMC, candlestick, behavioral psychology, macro & calibration glossary.
public struct GlossaryView: View {
    public let palette: ConfluencePalette
    @State private var searchText: String

    public init(palette: ConfluencePalette, initialQuery: String = "") {
        self.palette = palette
        _searchText = State(initialValue: initialQuery)
    }

    private var filteredTerms: [GlossaryTerm] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return Self.allTerms }
        return Self.allTerms.filter {
            $0.term.lowercased().contains(q) ||
            $0.category.lowercased().contains(q) ||
            $0.definition.lowercased().contains(q)
        }
    }

    public var body: some View {
        List {
            ForEach(filteredTerms) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.term)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(palette.primaryInk)
                        Spacer()
                        Text(item.category.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(palette.macroIceBlue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(palette.macroIceBlue.opacity(0.14), in: Capsule())
                    }
                    Text(item.definition)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 3)
            }
        }
        .searchable(text: $searchText, prompt: "Search terms (FVG, Wilson CI, BOS, ATR...)")
        .navigationTitle("Quant & Trading Glossary")
        .navigationBarTitleDisplayMode(.inline)
    }

    public static let allTerms: [GlossaryTerm] = [
        GlossaryTerm(id: "fvg", term: "Fair Value Gap (FVG)", category: "ICT / SMC", definition: "A 3-candle price imbalance where candle 1's high does not overlap candle 3's low (bullish) or candle 1's low does not overlap candle 3's high (bearish). Price often retraces into unmitigated FVGs before continuing."),
        GlossaryTerm(id: "ob", term: "Order Block (OB)", category: "ICT / SMC", definition: "The last opposing candle immediately prior to a strong displacement impulse that breaks market structure, representing institutional footprint / resting orders."),
        GlossaryTerm(id: "bos", term: "Break of Structure (BOS)", category: "ICT / SMC", definition: "A closed candle breaking beyond a previously confirmed causal swing high (uptrend continuation) or swing low (downtrend continuation)."),
        GlossaryTerm(id: "mss", term: "Market Structure Shift (MSS)", category: "ICT / SMC", definition: "A closed candle reversing through the opposing confirmed swing after a liquidity sweep, signaling an early structural trend change."),
        GlossaryTerm(id: "sweep", term: "Liquidity Sweep / Stop Hunt", category: "ICT / SMC", definition: "Price wicks beyond an obvious swing high/low or round number to trigger clustered stop losses, then closes back inside the range."),
        GlossaryTerm(id: "eq", term: "Premium / Discount Equilibrium (EQ)", category: "ICT / SMC", definition: "The 50% midpoint of the recent dealing range. Institutional longs prefer Discount (below 50% EQ); shorts prefer Premium (above 50% EQ)."),
        GlossaryTerm(id: "killzone", term: "Killzone Session", category: "Sessions", definition: "High-liquidity institutional session windows anchored to Europe/London (London 07:00–10:00) and America/New_York (NY 07:00–10:00, London Close 10:00–12:00) with automatic DST adjustment."),
        GlossaryTerm(id: "htf", term: "Higher Timeframe (HTF) Bias", category: "Structure", definition: "Directional trend context computed on the higher timeframe (e.g., 4H for 1H entries) to align entries with dominant order flow."),
        GlossaryTerm(id: "engulfing", term: "Engulfing Candle", category: "Candlesticks", definition: "A reversal candle whose real body completely engulfs the prior opposing candle's body, confirming aggressive momentum shift."),
        GlossaryTerm(id: "hammer", term: "Hammer / Pin Bar", category: "Candlesticks", definition: "A single-candle rejection with a long wick (>= 2x body) showing trapped breakout traders being reversed."),
        GlossaryTerm(id: "insidebar", term: "Inside Bar Breakout", category: "Candlesticks", definition: "A compression candle fully contained inside the prior bar's high-low range followed by directional expansion."),
        GlossaryTerm(id: "ema", term: "EMA Stack Pullback", category: "Momentum", definition: "Exponential Moving Averages (20/50/200) stacked in trend order where price pulls back toward the 20/50 EMA value area."),
        GlossaryTerm(id: "rsi", term: "RSI Divergence", category: "Momentum", definition: "Price prints a new swing extreme while 14-period Wilder RSI fails to confirm it, indicating waning momentum."),
        GlossaryTerm(id: "atr", term: "Average True Range (ATR)", category: "Volatility", definition: "Wilder 14-period volatility measure used to scale stop buffers, FVG/OB proximity, and realistic timeframe-capped TP ceilings."),
        GlossaryTerm(id: "rvol", term: "Relative Volume (RVOL)", category: "Volume", definition: "Current bar volume divided by its trailing 20-bar mean. Reported honestly as N/A on OTC Forex/Gold feeds lacking centralized volume."),
        GlossaryTerm(id: "squeeze", term: "ATR Volatility Squeeze", category: "Volatility", definition: "Abnormally compressed volatility preceding a directional expansion breakout."),
        GlossaryTerm(id: "regime", term: "Market Regime", category: "Regime", definition: "Causal classification into Trending, Mean-Reverting, High-Vol, or Crisis using Kaufman Efficiency Ratio, ATR z-score, and rolling drawdown."),
        GlossaryTerm(id: "crisis", term: "Crisis Regime Suppression", category: "Risk", definition: "Flash-crash or extreme volatility shock where risk_state=reduce automatically suppresses new directional signals."),
        GlossaryTerm(id: "trap", term: "Behavioral Trap (Bull / Bear)", category: "Psychology", definition: "A 4-stage lifecycle (Trigger -> Active -> Returned -> Invalid) identifying trapped breakout chasers at round numbers, swing highs/lows, or post-news whipsaws."),
        GlossaryTerm(id: "osler", term: "Osler Round-Number Clustering", category: "Psychology", definition: "Academic finding (Carol Osler) that retail stop-loss orders cluster heavily just beyond psychological round numbers, creating stop-run liquidity targets."),
        GlossaryTerm(id: "disposition", term: "Disposition Effect", category: "Psychology", definition: "Behavioral tendency to cut winning trades too early and hold losing trades too long (Shefrin & Statman / Kahneman & Tversky)."),
        GlossaryTerm(id: "fomo", term: "Attention-Induced FOMO", category: "Psychology", definition: "Late retail chasing into extended moves after attention-grabbing headlines or vertical candles (Barber & Odean)."),
        GlossaryTerm(id: "funding", term: "Perpetual Funding Rate (OKX)", category: "Positioning", definition: "Periodic payments between perpetual swap longs and shorts. Extreme crowded funding flags squeeze risk."),
        GlossaryTerm(id: "oi", term: "Open Interest (OI) Divergence", category: "Positioning", definition: "Comparison of price movement against outstanding derivative contracts (UTC-aligned on OKX) to separate genuine expansion from short-covering."),
        GlossaryTerm(id: "cot", term: "CFTC Commitments of Traders (COT)", category: "Positioning", definition: "Weekly US futures positioning (Asset Managers / Leveraged Funds vs Small Speculators). Strictly lagged to Friday 20:30 UTC release to prevent lookahead."),
        GlossaryTerm(id: "prenews", term: "Pre-News Volatility Shield", category: "Macro", definition: "15-minute blackout window before exact-clock high-impact macro releases (CPI, NFP, FOMC) to avoid spread-widening stop hunts."),
        GlossaryTerm(id: "surprise", term: "Macro Surprise Z-Score", category: "Macro", definition: "Standardized deviation of an economic release's Actual print vs Forecast. Unpublished events (actual == nil) are never coerced to 0."),
        GlossaryTerm(id: "whipsaw", term: "Post-News Whipsaw Window", category: "Macro", definition: "5-minute post-release caution window preventing entries during initial algorithmic liquidity sweeps."),
        GlossaryTerm(id: "rr", term: "Risk-to-Reward Ratio (R:R)", category: "Risk", definition: "Planned distance from Entry Mid to TP1 divided by distance from Entry Mid to Stop Loss."),
        GlossaryTerm(id: "rmultiple", term: "R-Multiple", category: "Statistics", definition: "Trade profit or loss expressed in units of initial risk (1R). -1.0R = full stop loss; +2.0R = twice initial risk gained, net of estimated fees/slippage."),
        GlossaryTerm(id: "expectancy", term: "Expectancy (Net R)", category: "Statistics", definition: "Average net R-multiple per resolved filled trade after asset-class fee/slippage bps."),
        GlossaryTerm(id: "score", term: "Raw Confluence Score (0–100)", category: "Calibration", definition: "Deterministic weighted score combining technical, psychology, macro, and regime pillars. NOT a win probability until N >= 100 activates Platt scaling."),
        GlossaryTerm(id: "platt", term: "Walk-Forward Platt Scaling", category: "Calibration", definition: "Monotonic logistic calibration mapping raw scores to empirical win probabilities once >= 100 resolved filled trades exist. Display-only; gating always uses the raw score."),
        GlossaryTerm(id: "brier", term: "Brier Score", category: "Calibration", definition: "Mean squared error between predicted probability and actual outcome (0 or 1). 0.000 is perfect; < 0.200 indicates well-calibrated probabilities."),
        GlossaryTerm(id: "wilson", term: "Wilson 95% Confidence Interval", category: "Statistics", definition: "Exact binomial confidence interval showing the plausible range of true win rate given sample size n — preventing over-interpreting small samples."),
        GlossaryTerm(id: "fillwindow", term: "Entry-Zone Fill Window", category: "Lifecycle", definition: "Maximum closed bars (15m: 16, 1H: 12, 4H: 6, 1D: 3) a signal has to touch [entryLow, entryHigh]. Unfilled signals mark Not Filled and are excluded from Win Rate."),
        GlossaryTerm(id: "fillbar", term: "Fill-Bar SL-Only & Same-Bar Rule", category: "Lifecycle", definition: "Pessimistic anti-bias rule: on the fill bar itself only SL is checked (TP checks start on the next bar); on any later bar hitting both SL and TP, SL resolves first."),
        GlossaryTerm(id: "causal", term: "Prefix Invariance (Anti-Repainting)", category: "Engineering", definition: "Guarantee that every detector outputs the exact same result at closed bar t whether given bars 0...t or future bars 0...N. Open forming bars are always dropped."),
        GlossaryTerm(id: "offset", term: "Broker Price Offset", category: "Workflow", definition: "User-calibrated additive difference between your broker's quote and Confluence's feed (e.g., CFD vs futures basis). Display/Copy only; never alters engine stats."),
        GlossaryTerm(id: "pearson", term: "Rolling Pearson Correlation (ρ)", category: "Portfolio", definition: "Linear correlation (-1.0 to +1.0) of aligned closed-bar log returns between two active signals, highlighting overlapping risk exposure.")
    ]
}
