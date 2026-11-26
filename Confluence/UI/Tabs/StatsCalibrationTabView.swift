import SwiftUI
import SignalEngine

public enum StatsSubTab: String, CaseIterable, Identifiable {
    case calibration = "Calibration"
    case journal = "Journal"
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
        let ofEdge = WinRateBreakdown.cryptoOrderFlowEdgeDelta(entries: coordinator.journalCoordinator.allEntries)
        let filterConfig = coordinator.settings.buildCalibrationFilterConfig()
        let hasCustomFilterDiff = (
            filterConfig.winDefinition != CalibrationFilterConfig.headlineFixed.winDefinition ||
            filterConfig.categoryScope != CalibrationFilterConfig.headlineFixed.categoryScope ||
            filterConfig.minimumConfidencePercent > 0 ||
            filterConfig.minimumRiskReward > 0
        )

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
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            // 1. Fixed 2x2 Headline KPI Grid (Win Rate + CI, Closed Trades n, Avg Realized R:R, Brier Score)
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                                headlineWinRateKPICard(
                                    summary: headline,
                                    accent: headline.resolvedSignals > 0
                                        ? (headline.winRate >= 0.5 ? palette.longEmerald : palette.shortCrimson)
                                        : palette.champagneGold
                                )
                                kpiCard(
                                    title: "CLOSED TRADES",
                                    value: "\(headline.resolvedSignals)",
                                    sub: "\(headline.tp1Hits + headline.tp2Hits)W / \(headline.slHits)L · \(headline.openCount) Open",
                                    accent: palette.primaryInk
                                )
                                kpiCard(
                                    title: "AVG REALIZED R:R",
                                    value: headline.resolvedSignals > 0 ? String(format: "%+.2fR", headline.expectancyR) : "—",
                                    sub: "Net of cost bps · Filled Strong",
                                    accent: headline.resolvedSignals > 0
                                        ? (headline.expectancyR >= 0 ? palette.longEmerald : palette.shortCrimson)
                                        : palette.secondaryInk
                                )
                                kpiCard(
                                    title: "BRIER SCORE",
                                    value: headline.resolvedSignals > 0 ? String(format: "%.3f", headline.brierScore) : "—",
                                    sub: headline.isCalibrationActive
                                        ? "Platt active (n=\(headline.calibrationSampleCount))"
                                        : "Raw score (\(headline.calibrationSampleCount)/\(ConfidenceCalibrator.minimumSamples) to calibrate)",
                                    accent: palette.champagneGold
                                )
                            }

                            // 2. 3-Bucket Comparison Section (Strong Signals / Weak & Filtered / Trap Alerts) + Score Buckets
                            WinRateBreakdownView(
                                journalSectionStats: coordinator.journalSectionStats,
                                originStats: coordinator.originWinRates,
                                strengthBuckets: coordinator.strengthBuckets,
                                palette: palette
                            )

                            // 3. Crypto Order Flow Edge Delta (Aligned vs Conflicting vs Off)
                            orderFlowEdgeCard(ofEdge)

                            // Lifecycle & Legacy Transparency Strip
                            if headline.notFilledCount > 0 || headline.invalidatedCount > 0 || headline.openCount > 0 || headline.legacyExcludedCount > 0 {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "checkmark.shield")
                                            .font(.caption)
                                            .foregroundStyle(palette.champagneGold)
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
                                        Text(custom.resolvedSignals > 0 ? String(format: "%.1f%%", custom.winRate * 100.0) : "—")
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

                            // 4. Interactive Per-Strategy Reliability Ranking -> Strategy Trades -> Chart Replay
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Strategy Performance")
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
                                        let prettyName = StrategyID.displayName(forRawKey: item.strategyId)
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
                                                    Text(String(format: "%.1f%%", item.winRate * 100.0))
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

                            // 5. Asset / Market Breakdown (uniform XX.X% + right-aligned tabular counts)
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Asset Class Breakdown")
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
                                            VStack(alignment: .trailing, spacing: 1) {
                                                Text(String(format: "%.1f%%", stat.winRate * 100.0))
                                                    .font(.caption.weight(.bold).monospacedDigit())
                                                    .foregroundStyle(stat.winRate >= 0.5 ? palette.longEmerald : palette.shortCrimson)
                                                let ciText = stat.winRateCI.map { "\($0.percentRangeLabel) · " } ?? ""
                                                Text("\(ciText)n=\(stat.resolvedCount)")
                                                    .font(.system(size: 10).monospacedDigit())
                                                    .foregroundStyle(palette.tertiaryInk)
                                            }
                                        } else {
                                            Text("Awaiting Filled Outcomes")
                                                .font(.caption2.monospacedDigit())
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
                    .safeAreaPadding(.bottom, 96)
                    .background(palette.canvas)
                }
            }
            .navigationTitle(activeTab == .journal ? "Signal Journal" : "Calibration Stats")
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

    private func orderFlowEdgeCard(_ edge: CryptoOrderFlowEdgeDelta) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Crypto Order Flow Edge")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(palette.primaryInk)
                Spacer()
                if edge.isLowConfidence {
                    Text("Low Sample (<30)")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(palette.trapAmber)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(palette.trapAmber.opacity(0.14), in: Capsule())
                }
            }

            HStack(spacing: 8) {
                ofSliceTile("OF Aligned", stat: edge.aligned, accent: palette.longEmerald)
                ofSliceTile("OF Conflict", stat: edge.conflicting, accent: palette.shortCrimson)
                ofSliceTile("OF Off", stat: edge.off, accent: palette.secondaryInk)
            }

            if let wrDelta = edge.winRateDeltaAlignedVsConflicting {
                let rDeltaStr = edge.avgRDeltaAlignedVsConflicting.map { String(format: " (%+.2fR)", $0) } ?? ""
                Text(String(format: "Aligned vs. Conflicting edge: %+.1f%% win rate%@", wrDelta * 100.0, rDeltaStr))
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(wrDelta >= 0 ? palette.longEmerald : palette.shortCrimson)
            } else {
                Text("Tracks whether live Crypto Order Flow alignment improves realized win rate once resolved crypto setups accumulate.")
                    .font(.caption2)
                    .foregroundStyle(palette.tertiaryInk)
            }
        }
        .padding(14)
        .institutionalCard(palette: palette)
    }

    private func ofSliceTile(_ title: String, stat: WinRateSliceStat, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(palette.tertiaryInk)
            Text(stat.totalResolved > 0 ? String(format: "%.1f%%", stat.winRate * 100.0) : "—")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(stat.totalResolved > 0 ? accent : palette.tertiaryInk)
            Text("n=\(stat.totalResolved)")
                .font(.system(size: 9.5).monospacedDigit())
                .foregroundStyle(palette.secondaryInk)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.elevatedSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func headlineWinRateKPICard(summary: CalibrationSummary, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("WIN RATE")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(palette.tertiaryInk)
            Text(summary.resolvedSignals > 0 ? String(format: "%.1f%%", summary.winRate * 100.0) : "—")
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(accent)
            if let ci = summary.winRateCI {
                Text("95% CI \(ci.percentRangeLabel)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(palette.secondaryInk)
                    .lineLimit(1)
            } else {
                Text("Awaiting filled trades")
                    .font(.caption2)
                    .foregroundStyle(palette.tertiaryInk)
                    .lineLimit(1)
            }
            Text("Strong · TP1/TP2 · Filled")
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
