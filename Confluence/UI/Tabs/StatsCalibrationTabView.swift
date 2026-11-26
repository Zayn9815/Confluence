import SwiftUI
import SignalEngine

public enum StatsSubTab: String, CaseIterable, Identifiable {
    case calibration = "Calibration"
    case journal = "Journal"
    case wallet = "Demo Wallet"
    public var id: String { rawValue }
}

public struct StatsCalibrationTabView: View {
    @Bindable var coordinator: MarketScannerCoordinator
    let palette: ConfluencePalette

    @State private var activeTab: StatsSubTab = .calibration

    public init(coordinator: MarketScannerCoordinator, palette: ConfluencePalette) {
        self.coordinator = coordinator
        self.palette = palette
    }

    public var body: some View {
        let headline = coordinator.headlineCalibrationSummary
        let custom = coordinator.calibrationSummary
        let filterConfig = coordinator.settings.buildCalibrationFilterConfig()
        let hasCustomFilterDiff = (
            filterConfig.winDefinition != CalibrationFilterConfig.headlineFixed.winDefinition ||
            filterConfig.categoryScope != CalibrationFilterConfig.headlineFixed.categoryScope ||
            filterConfig.minimumConfidencePercent > 0 ||
            filterConfig.minimumRiskReward > 0
        )

        let headlineBreakdownSub = "\(headline.tp1Hits) Target 1 · \(headline.tp2Hits) Target 2 · \(headline.slHits) Stop loss"
        let customBreakdownSub: String = {
            if filterConfig.winDefinition == .tp2Only {
                if custom.tp1PartialsExcluded > 0 {
                    return "\(custom.tp2Hits) Target 2 · \(custom.slHits) Stop loss (\(custom.tp1PartialsExcluded) Target 1 Partial)"
                }
                return "\(custom.tp2Hits) Target 2 · \(custom.slHits) Stop loss"
            }
            return "\(custom.tp1Hits) Target 1 · \(custom.tp2Hits) Target 2 · \(custom.slHits) Stop loss"
        }()

        NavigationStack {
            VStack(spacing: 0) {
                Picker("Stats Mode", selection: $activeTab) {
                    ForEach(StatsSubTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(palette.canvas)

                if activeTab == .journal {
                    TradeJournalView(coordinator: coordinator, palette: palette)
                } else if activeTab == .wallet {
                    DemoWalletView(coordinator: coordinator, palette: palette)
                } else {
            ScrollView {
                VStack(spacing: 14) {
                    // 0. Three Origin Win-Rate Cards (Strong signals / Traps and filtered / News setups) + Score Strength Buckets
                    WinRateBreakdownView(
                        originStats: coordinator.originWinRates,
                        strengthBuckets: coordinator.strengthBuckets,
                        palette: palette
                    )

                    // 1. Fixed Un-Cherry-Pickable Headline Calibration KPI Grid (Strong · Target 1/2 · Filled v1.4+)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        headlineWinRateKPICard(
                            summary: headline,
                            breakdown: headlineBreakdownSub,
                            accent: headline.winRate >= 0.5 ? palette.longEmerald : palette.champagneGold
                        )
                        kpiCard(
                            title: "BRIER SCORE",
                            value: headline.resolvedSignals > 0 ? String(format: "%.3f", headline.brierScore) : "—",
                            sub: headline.isCalibrationActive
                                ? "Platt active (n=\(headline.calibrationSampleCount))"
                                : "Raw score (\(headline.calibrationSampleCount)/\(ConfidenceCalibrator.minimumSamples) to calibrate)",
                            accent: palette.macroIceBlue
                        )
                        kpiCard(
                            title: "EXPECTANCY (NET R)",
                            value: headline.resolvedSignals > 0 ? String(format: "%+.2fR", headline.expectancyR) : "—",
                            sub: "Filled Strong · net of cost bps",
                            accent: headline.expectancyR >= 0 ? palette.longEmerald : palette.shortCrimson
                        )
                        kpiCard(
                            title: "TRAP / MACRO HIT",
                            value: headline.trapAccuracy.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
                            sub: "Macro: \(headline.macroCatalystHitRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "N/A")",
                            accent: palette.trapAmber
                        )
                    }

                    // Lifecycle & Legacy Transparency Strip
                    if headline.notFilledCount > 0 || headline.invalidatedCount > 0 || headline.openCount > 0 || headline.legacyExcludedCount > 0 {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.shield")
                                    .font(.caption)
                                    .foregroundStyle(palette.macroIceBlue)
                                Text("Fill Lifecycle Transparency")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(palette.primaryInk)
                                Spacer()
                                if headline.openCount > 0 {
                                    Text("\(headline.openCount) Open")
                                        .font(.caption2.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(palette.champagneGold)
                                }
                            }
                            Text("Not filled: \(headline.notFilledCount) · Invalidated before fill: \(headline.invalidatedCount) (excluded from Win Rate denominator)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(palette.secondaryInk)
                            if headline.legacyExcludedCount > 0 {
                                Text("Excludes \(headline.legacyExcludedCount) pre-v1.4 legacy-immediate-fill trade(s) from the headline Win Rate.")
                                    .font(.caption2)
                                    .foregroundStyle(palette.trapAmber)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .institutionalCard(palette: palette)
                    }

                    // Optional Custom View (Filtered) card when user configured non-headline custom rules
                    if hasCustomFilterDiff {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("CUSTOM VIEW (FILTERED)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(palette.champagneGold)
                                Spacer()
                                Text(filterConfig.summarySubtitle)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(palette.secondaryInk)
                                    .lineLimit(1)
                            }
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(custom.resolvedSignals > 0 ? "\(Int((custom.winRate * 100).rounded()))%" : "—")
                                    .font(.title3.weight(.bold).monospacedDigit())
                                    .foregroundStyle(custom.winRate >= 0.5 ? palette.longEmerald : palette.shortCrimson)
                                if let ci = custom.winRateCI {
                                    Text("95% CI \(ci.formattedSummary)")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(palette.secondaryInk)
                                }
                                Spacer()
                                Text(custom.resolvedSignals > 0 ? String(format: "%+.2fR", custom.expectancyR) : "—")
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundStyle(custom.expectancyR >= 0 ? palette.champagneGold : palette.shortCrimson)
                            }
                            Text("\(customBreakdownSub) · Headline record above remains fixed to Strong · TP1/TP2 · Filled v1.4+.")
                                .font(.caption2)
                                .foregroundStyle(palette.tertiaryInk)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .institutionalCard(palette: palette, accentBorder: palette.champagneGold.opacity(0.45))
                    }

                    // 2. Interactive Per-Strategy Reliability Ranking -> Strategy Trades -> Chart Replay
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Strategy Reliability Ranking")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(palette.primaryInk)
                            Spacer()
                            if !custom.strategyRankings.isEmpty {
                                Text("Tap to replay")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(palette.tertiaryInk)
                            }
                        }

                        if custom.strategyRankings.isEmpty {
                            Text("No resolved passive outcomes match yet. Signals must first touch their Entry Zone within the fill window, then hit TP1, TP2, or SL on subsequent closed bars.")
                                .font(.caption)
                                .foregroundStyle(palette.secondaryInk)
                        } else {
                            ForEach(custom.strategyRankings) { item in
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
                                            let ciText = item.winRateCI.map { " · CI \($0.percentRangeLabel)" } ?? ""
                                            Text("\(item.wins)/\(item.totalResolved) wins (n=\(item.totalResolved))\(ciText)")
                                                .font(.caption2.monospacedDigit())
                                                .foregroundStyle(palette.tertiaryInk)
                                                .lineLimit(1)
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

                    // 3. Per-Market Breakdown (Headline Filled Outcomes + Wilson 95% CI)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Per-Market Breakdown")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(palette.primaryInk)

                        ForEach(MarketClass.allCases, id: \.self) { market in
                            let mStat = headline.marketStats[market]
                            HStack {
                                Text(market.displayName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(palette.primaryInk)
                                Spacer()
                                if let stat = mStat {
                                    let ciText = stat.winRateCI.map { " \($0.formattedSummary)" } ?? " (n=\(stat.resolvedCount))"
                                    Text("\(Int((stat.winRate * 100).rounded()))%\(ciText)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(stat.winRate >= 0.5 ? palette.longEmerald : palette.shortCrimson)
                                } else {
                                    Text("Awaiting Filled Outcomes")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(palette.tertiaryInk)
                                }
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
                }
            }
            .navigationTitle(activeTab == .journal ? "Trade Journal" : (activeTab == .wallet ? "Demo Wallet" : "Calibration Stats"))
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

    private func headlineWinRateKPICard(summary: CalibrationSummary, breakdown: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("HEADLINE WIN RATE")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(palette.tertiaryInk)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(summary.resolvedSignals > 0 ? "\(Int((summary.winRate * 100).rounded()))%" : "—")
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(accent)
                if let ci = summary.winRateCI {
                    Text(ci.formattedSummary)
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(palette.secondaryInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Text(breakdown)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(palette.secondaryInk)
                .lineLimit(2)
            Text("Fixed: Strong · TP1/TP2 · Filled")
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
