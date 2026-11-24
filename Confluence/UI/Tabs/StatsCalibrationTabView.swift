import SwiftUI
import SignalEngine

public struct StatsCalibrationTabView: View {
    @Bindable var coordinator: MarketScannerCoordinator
    let palette: ConfluencePalette

    public init(coordinator: MarketScannerCoordinator, palette: ConfluencePalette) {
        self.coordinator = coordinator
        self.palette = palette
    }

    public var body: some View {
        let stats = coordinator.calibrationSummary
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // 1. Headline Calibration KPI Grid (strictly real passive outcomes — zero fabricated numbers)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        kpiCard(
                            title: "RESOLVED WIN RATE",
                            value: stats.resolvedSignals > 0 ? "\(Int((stats.winRate * 100).rounded()))%" : "—",
                            sub: "\(stats.tp1Hits) TP1 · \(stats.tp2Hits) TP2 · \(stats.slHits) SL",
                            accent: stats.winRate >= 0.5 ? palette.longEmerald : palette.champagneGold
                        )
                        kpiCard(
                            title: "BRIER SCORE",
                            value: stats.resolvedSignals > 0 ? String(format: "%.3f", stats.brierScore) : "—",
                            sub: "Lower is better (<0.20 calibrated)",
                            accent: palette.macroIceBlue
                        )
                        kpiCard(
                            title: "EXPECTANCY (NET R)",
                            value: stats.resolvedSignals > 0 ? String(format: "%+.2fR", stats.expectancyR) : "—",
                            sub: "Net of asset-class cost bps",
                            accent: stats.expectancyR >= 0 ? palette.longEmerald : palette.shortCrimson
                        )
                        kpiCard(
                            title: "TRAP / MACRO HIT",
                            value: stats.trapAccuracy.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
                            sub: "Macro: \(stats.macroCatalystHitRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "N/A")",
                            accent: palette.trapAmber
                        )
                    }

                    // 2. Per-Strategy Accuracy Ranking
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Strategy Reliability Ranking")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(palette.primaryInk)

                        if stats.strategyRankings.isEmpty {
                            Text("No resolved passive outcomes yet. As subsequent closed candles hit TP1, TP2, or SL on recorded signals, real per-strategy expectancy and Brier calibration populate here.")
                                .font(.caption)
                                .foregroundStyle(palette.secondaryInk)
                        } else {
                            ForEach(stats.strategyRankings) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.strategyId.replacingOccurrences(of: "_", with: " ").capitalized)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(palette.primaryInk)
                                        Text("\(item.wins)/\(item.totalResolved) wins")
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(palette.tertiaryInk)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("\(Int((item.winRate * 100).rounded()))%")
                                            .font(.caption.weight(.bold).monospacedDigit())
                                            .foregroundStyle(palette.longEmerald)
                                        Text(String(format: "%+.2fR", item.expectancyR))
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(item.expectancyR >= 0 ? palette.champagneGold : palette.shortCrimson)
                                    }
                                }
                                .padding(9)
                                .background(palette.elevatedSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            }
                        }
                    }
                    .padding(14)
                    .institutionalCard(palette: palette)

                    // 3. Per-Market Breakdown
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Per-Market Breakdown")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(palette.primaryInk)

                        ForEach(MarketClass.allCases, id: \.self) { market in
                            let rate = stats.marketBreakdown[market]
                            HStack {
                                Text(market.displayName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(palette.primaryInk)
                                Spacer()
                                Text(rate.map { "\(Int(($0 * 100).rounded()))% Win Rate" } ?? "Awaiting Closed Outcomes")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(rate != nil ? palette.longEmerald : palette.tertiaryInk)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(14)
                    .institutionalCard(palette: palette)
                }
                .padding(14)
            }
            .background(palette.canvas)
            .navigationTitle("Calibration Stats")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func kpiCard(title: String, value: String, sub: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(palette.tertiaryInk)
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(accent)
            Text(sub)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(palette.secondaryInk)
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .institutionalCard(palette: palette)
    }
}
