import SwiftUI

/// Permanent Risk Disclosure & Methodology screen accessible in Settings -> Data, Diagnostics & About.
public struct RiskDisclosureView: View {
    public let palette: ConfluencePalette

    public init(palette: ConfluencePalette) {
        self.palette = palette
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                disclosureCard(
                    icon: "exclamationmark.shield.fill",
                    accent: palette.trapAmber,
                    title: "Read-Only Analytical Tool — Not Financial Advice",
                    body: "Confluence is strictly a read-only market analysis and educational terminal. It never connects to brokerage execution APIs, never holds trading private keys, and never places orders. Nothing shown in this app constitutes investment, trading, tax, or legal advice."
                )

                disclosureCard(
                    icon: "chart.line.downtrend.xyaxis",
                    accent: palette.shortCrimson,
                    title: "Substantial Risk of Loss",
                    body: "Trading cryptocurrencies, forex, metals, equity indices, CFDs, and stocks involves substantial risk of loss and is not suitable for every investor. Leverage magnifies both gains and losses. Past passive outcomes, backtests, or calibrated probabilities never guarantee future performance."
                )

                disclosureCard(
                    icon: "ruler.fill",
                    accent: palette.macroIceBlue,
                    title: "Estimates, Feed Delays & Broker Differences",
                    body: "Market data comes from third-party public or user-keyed APIs and may differ from your broker's bid/ask spread, rollover swaps, or CFD contract specifications. Position sizing outputs and broker price offsets are estimates only — always verify exact prices, lot sizes, and margin requirements directly in your broker platform."
                )

                disclosureCard(
                    icon: "checkmark.seal.fill",
                    accent: palette.longEmerald,
                    title: "Statistical & Calibration Honesty",
                    body: "Raw Confluence Scores (0–100) are weighted multi-strategy scores, not win probabilities, until at least 100 resolved filled signals activate walk-forward Platt scaling. Passive outcomes enforce closed-candle anti-repainting, entry-zone fill windows, fill-bar SL-only checks, and pessimistic same-bar SL-first resolution."
                )
            }
            .padding(14)
        }
        .background(palette.canvas)
        .navigationTitle("Risk Disclosure")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func disclosureCard(icon: String, accent: Color, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(accent)
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(palette.primaryInk)
            }
            Text(body)
                .font(.caption)
                .foregroundStyle(palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .institutionalCard(palette: palette)
    }
}
