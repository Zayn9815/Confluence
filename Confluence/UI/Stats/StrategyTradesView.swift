import SwiftUI
import SignalEngine

public enum StrategyTradeFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case wins = "Wins"
    case losses = "Losses"
    case open = "Open"

    public var id: String { rawValue }
}

/// Interactive drill-down screen opened when tapping any row in `Strategy Reliability Ranking`.
/// Lists every recorded trade containing that strategy and launches `FullScreenChartSheet` in
/// **Trade Outcome Chart Replay Mode** when any trade is tapped.
public struct StrategyTradesView: View {
    public let strategyId: String
    public let displayName: String
    @Bindable public var coordinator: MarketScannerCoordinator
    public let palette: ConfluencePalette

    @State private var filter: StrategyTradeFilter = .all
    @State private var replayContext: TradeReplayContext? = nil
    @State private var loadingTradeId: String? = nil

    public init(
        strategyId: String,
        displayName: String,
        coordinator: MarketScannerCoordinator,
        palette: ConfluencePalette
    ) {
        self.strategyId = strategyId
        self.displayName = displayName
        self.coordinator = coordinator
        self.palette = palette
    }

    private var allTrades: [StrategyTradeItem] {
        coordinator.trades(forStrategyId: strategyId)
    }

    private var filteredTrades: [StrategyTradeItem] {
        allTrades.filter { trade in
            switch filter {
            case .all: return true
            case .wins: return trade.status.isWin
            case .losses: return trade.status.isLoss
            case .open: return trade.status.isActive
            }
        }
    }

    private var breakdown: StrategyDiagnosticBreakdown? {
        coordinator.strategyBreakdowns.first { $0.strategyId == strategyId }
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let stats = breakdown {
                strategySummaryHeader(stats)
                Divider().overlay(palette.border)
            }

            // Filter Chips
            HStack(spacing: 8) {
                ForEach(StrategyTradeFilter.allCases) { tab in
                    let isSelected = (filter == tab)
                    Button {
                        filter = tab
                    } label: {
                        Text("\(tab.rawValue) (\(count(for: tab)))")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(isSelected ? palette.canvas : palette.secondaryInk)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(isSelected ? palette.champagneGold : palette.elevatedSurface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(palette.canvas)

            if filteredTrades.isEmpty {
                ContentUnavailableView(
                    "No \(filter.rawValue) Trades",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("No recorded setups match this filter for \(displayName).")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.canvas)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredTrades) { trade in
                            tradeCard(trade)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 16)
                }
                .safeAreaPadding(.bottom, 96)
                .background(palette.canvas)
            }
        }
        .background(palette.canvas.ignoresSafeArea())
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: replaySheetBinding) { wrapper in
            FullScreenChartSheet(
                replayContext: wrapper.context,
                palette: palette,
                coordinator: coordinator
            )
        }
    }

    private var replaySheetBinding: Binding<ReplaySheetWrapper?> {
        Binding(
            get: { replayContext.map { ReplaySheetWrapper(context: $0) } },
            set: { if $0 == nil { replayContext = nil } }
        )
    }

    private func count(for tab: StrategyTradeFilter) -> Int {
        switch tab {
        case .all: return allTrades.count
        case .wins: return allTrades.filter { $0.status.isWin }.count
        case .losses: return allTrades.filter { $0.status.isLoss }.count
        case .open: return allTrades.filter { $0.status.isActive }.count
        }
    }

    private func strategySummaryHeader(_ s: StrategyDiagnosticBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                let wrText: String = {
                    let pct = String(format: "%.1f%%", s.winRate * 100.0)
                    if let ci = s.winRateCI {
                        return "\(pct) (\(ci.percentRangeLabel))"
                    }
                    return pct
                }()
                statPill("WIN RATE (95% CI)", wrText, s.winRate >= 0.5 ? palette.longEmerald : palette.shortCrimson)
                statPill("EXPECTANCY", String(format: "%+.2fR", s.expectancyR), s.expectancyR >= 0 ? palette.champagneGold : palette.shortCrimson)
                statPill("RECORD", "\(s.wins)W / \(s.losses)L", palette.primaryInk)
                statPill("BRIER", String(format: "%.3f", s.brierContribution), palette.champagneGold)
            }
            if !s.bestPairs.isEmpty || !s.worstPairs.isEmpty {
                HStack(spacing: 8) {
                    if !s.bestPairs.isEmpty {
                        Text("Best: \(s.bestPairs.joined(separator: ", "))")
                            .foregroundStyle(palette.longEmerald)
                    }
                    if !s.worstPairs.isEmpty {
                        Text("Weak: \(s.worstPairs.joined(separator: ", "))")
                            .foregroundStyle(palette.shortCrimson)
                    }
                }
                .font(.caption2.weight(.medium))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(palette.surface)
    }

    private func statPill(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(palette.tertiaryInk)
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tradeCard(_ trade: StrategyTradeItem) -> some View {
        let prec = ChartPricePrecision.resolve(
            symbol: trade.symbol,
            marketClass: trade.marketClass,
            referencePrice: trade.levels.entryMid
        )
        let outcomeColor = statusColor(trade.status)
        let isLoading = (loadingTradeId == trade.fingerprint)

        return Button {
            guard loadingTradeId == nil else { return }
            loadingTradeId = trade.fingerprint
            Task {
                let ctx = await coordinator.loadTradeReplayContext(for: trade)
                loadingTradeId = nil
                replayContext = ctx
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(trade.symbol)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(palette.primaryInk)
                    Text(trade.timeframe.displayLabel)
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(palette.secondaryInk)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(palette.elevatedSurface, in: Capsule())
                    Text(trade.direction.rawValue.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(trade.direction == .long ? palette.longEmerald : palette.shortCrimson)
                    Spacer()

                    Text(trade.status.rawValue)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(outcomeColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(outcomeColor.opacity(0.15), in: Capsule())
                }

                // Price levels row (dynamic precision)
                HStack(spacing: 10) {
                    levelPair("ENTRY", prec.format(trade.levels.entryMid), palette.champagneGold)
                    levelPair("SL", prec.format(trade.levels.stopLoss), palette.shortCrimson)
                    levelPair("TP1", prec.format(trade.levels.tp1), palette.longEmerald)
                    if trade.levels.isTP2Enabled {
                        levelPair("TP2", prec.format(trade.levels.tp2), palette.longEmerald)
                    }
                }

                // Footer: Net R, Score, Entry/Exit UTC, Replay cue
                HStack(spacing: 8) {
                    Text(String(format: "%+.2fR", trade.netRMultiple))
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(trade.netRMultiple >= 0 ? palette.longEmerald : palette.shortCrimson)
                    Text("· Score \(Int(trade.confidencePercent.rounded()))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(palette.secondaryInk)
                    Text("· In \(formatUTC(trade.entryEpochSeconds))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(palette.tertiaryInk)
                    if let ex = trade.exitEpochSeconds {
                        Text("→ Out \(formatUTC(ex))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(palette.tertiaryInk)
                    }
                    Spacer()
                    if isLoading {
                        ProgressView().controlSize(.mini)
                    } else {
                        Label("Replay", systemImage: "play.circle.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(palette.champagneGold)
                    }
                }
            }
            .padding(12)
            .institutionalCard(palette: palette, accentBorder: outcomeColor.opacity(0.35))
        }
        .buttonStyle(.plain)
    }

    private func levelPair(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
            Text(value)
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(palette.primaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusColor(_ status: TradeLedgerStatus) -> Color {
        switch status {
        case .tp1Win, .tp2Win: return palette.longEmerald
        case .slLoss: return palette.shortCrimson
        case .open: return palette.champagneGold
        case .pending: return palette.secondaryInk
        case .invalidated: return palette.trapAmber
        case .notFilled, .expired: return palette.tertiaryInk
        }
    }

    private func formatUTC(_ epoch: TimeInterval) -> String {
        TimeDisplayFormatter.formatCompactStamp(
            epochSeconds: epoch,
            use24Hour: coordinator.settings.payload.use24HourTime,
            useUTC: coordinator.settings.payload.useUTCTimeZone
        )
    }
}

private struct ReplaySheetWrapper: Identifiable {
    let id: String
    let context: TradeReplayContext

    init(context: TradeReplayContext) {
        self.id = context.trade.fingerprint
        self.context = context
    }
}
