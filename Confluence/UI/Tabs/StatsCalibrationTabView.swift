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
        let filterConfig = coordinator.settings.buildCalibrationFilterConfig()

        let winBreakdownSub: String = {
            if filterConfig.winDefinition == .tp2Only {
                if stats.tp1PartialsExcluded > 0 {
                    return "\(stats.tp2Hits) TP2 · \(stats.slHits) SL (\(stats.tp1PartialsExcluded) TP1 Partial)"
                }
                return "\(stats.tp2Hits) TP2 · \(stats.slHits) SL"
            }
            return "\(stats.tp1Hits) TP1 · \(stats.tp2Hits) TP2 · \(stats.slHits) SL"
        }()

        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // 1. Headline Calibration KPI Grid (strictly real passive outcomes — zero fabricated numbers)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        winRateKPICard(
                            value: stats.resolvedSignals > 0 ? "\(Int((stats.winRate * 100).rounded()))%" : "—",
                            breakdown: winBreakdownSub,
                            filterSummary: filterConfig.summarySubtitle,
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

                    // 2. Interactive Per-Strategy Reliability Ranking -> Strategy Trades -> Chart Replay
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Strategy Reliability Ranking")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(palette.primaryInk)
                            Spacer()
                            if !stats.strategyRankings.isEmpty {
                                Text("Tap to replay")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(palette.tertiaryInk)
                            }
                        }

                        if stats.strategyRankings.isEmpty {
                            Text("No resolved passive outcomes match your active Win-Rate rules yet. As subsequent closed candles hit TP1, TP2, or SL on recorded signals, tap any strategy here to inspect and replay its trades.")
                                .font(.caption)
                                .foregroundStyle(palette.secondaryInk)
                        } else {
                            ForEach(stats.strategyRankings) { item in
                                let prettyName = item.strategyId.replacingOccurrences(of: "_", with: " ").capitalized
                                NavigationLink {
                                    StrategyTradesView(
                                        strategyId: item.strategyId,
                                        displayName: prettyName,
                                        coordinator: coordinator,
                                        palette: palette
                                    )
                                } label: {
                                    HStack(spacing: 10) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(prettyName)
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(palette.primaryInk)
                                                .lineLimit(1)
                                            Text("\(item.wins)/\(item.totalResolved) wins")
                                                .font(.caption2.monospacedDigit())
                                                .foregroundStyle(palette.tertiaryInk)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text("\(Int((item.winRate * 100).rounded()))%")
                                                .font(.caption.weight(.bold).monospacedDigit())
                                                .foregroundStyle(item.winRate >= 0.5 ? palette.longEmerald : palette.shortCrimson)
                                            Text(String(format: "%+.2fR", item.expectancyR))
                                                .font(.caption2.monospacedDigit())
                                                .foregroundStyle(item.expectancyR >= 0 ? palette.champagneGold : palette.shortCrimson)
                                        }
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(palette.tertiaryInk)
                                    }
                                    .padding(10)
                                    .background(palette.elevatedSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 10) {
                        NavigationLink {
                            SignalRulesSettingsView(coordinator: coordinator, palette: palette)
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(palette.primaryInk)
                        }
                        .accessibilityLabel("Win-Rate & Signal Rules")

                        NotificationBellButton(
                            unreadCount: coordinator.unreadNotificationCount,
                            palette: palette
                        ) {
                            coordinator.isNotificationInboxPresented = true
                        }
                    }
                }
            }
        }
    }

    private func winRateKPICard(value: String, breakdown: String, filterSummary: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("RESOLVED WIN RATE")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(palette.tertiaryInk)
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(accent)
            Text(breakdown)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(palette.secondaryInk)
                .lineLimit(2)
            Text(filterSummary)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(palette.champagneGold)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .institutionalCard(palette: palette)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .institutionalCard(palette: palette)
    }
}
