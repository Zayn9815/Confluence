import SwiftUI
import SignalEngine

public enum JournalFilterTab: String, CaseIterable, Identifiable {
    case all = "All"
    case open = "Open"
    case wins = "Wins"
    case losses = "Losses"
    public var id: String { rawValue }
}

public enum JournalSourceFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case demo = "Demo"
    case real = "Real"
    public var id: String { rawValue }
}

/// Unified Trade Journal supporting All / Demo / Real filter chips, live P/L rows (R, %, $),
/// Stop loss -> Target 1 progress bars, OFFLINE freshness badges, and non-auto-closing
/// Apply / Dismiss level alerts for manual real trades.
public struct TradeJournalView: View {
    @Bindable public var coordinator: MarketScannerCoordinator
    public let palette: ConfluencePalette

    @State private var sourceFilter: JournalSourceFilter = .all
    @State private var statusFilter: JournalFilterTab = .all
    @State private var editingEntry: JournalEntrySnapshot?
    @State private var showPlaceTrade: Bool = false

    public init(coordinator: MarketScannerCoordinator, palette: ConfluencePalette) {
        self.coordinator = coordinator
        self.palette = palette
    }

    private var filteredRealEntries: [JournalEntrySnapshot] {
        guard sourceFilter != .demo else { return [] }
        return coordinator.journalEntries.filter { e in
            switch statusFilter {
            case .all: return true
            case .open: return e.outcome == .open
            case .wins: return e.outcome == .win
            case .losses: return e.outcome == .loss
            }
        }
    }

    private var filteredDemoPositions: [DemoPosition] {
        guard sourceFilter != .real else { return [] }
        return coordinator.demoWallet.positions.filter { pos in
            switch statusFilter {
            case .all: return true
            case .open: return pos.status.isActive
            case .wins: return pos.status == .closedTarget1 || pos.status == .closedTarget2 || (pos.status == .closedManual && pos.realizedPnLUSD > 0)
            case .losses: return pos.status == .closedStopLoss || (pos.status == .closedManual && pos.realizedPnLUSD < 0)
            }
        }
    }

    public var body: some View {
        let stats = coordinator.journalSummary
        let use24h = coordinator.settings.payload.use24HourTime
        let useUTC = coordinator.settings.payload.useUTCTimeZone
        let now = Date().timeIntervalSince1970

        ScrollView {
            VStack(spacing: 12) {
                // My Execution vs System Comparison Card
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("MY EXECUTION VS. SYSTEM")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(palette.tertiaryInk)
                        Spacer()
                        Button {
                            showPlaceTrade = true
                        } label: {
                            Label("New Trade", systemImage: "plus")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(palette.canvas)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(palette.champagneGold, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        journalMetric(
                            title: "MY WIN RATE",
                            value: stats.myWinRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
                            sub: stats.myWinRateCI.map { "95% CI \($0.formattedSummary)" } ?? "\(stats.winsCount)W / \(stats.lossesCount)L",
                            accent: (stats.myWinRate ?? 0.5) >= 0.5 ? palette.longEmerald : palette.shortCrimson
                        )
                        journalMetric(
                            title: "MY AVG R vs SYSTEM",
                            value: stats.myAvgR.map { String(format: "%+.2fR", $0) } ?? "—",
                            sub: "System: \(stats.systemAvgR.map { String(format: "%+.2fR", $0) } ?? "N/A")",
                            accent: (stats.myAvgR ?? 0) >= 0 ? palette.champagneGold : palette.shortCrimson
                        )
                    }

                    HStack {
                        Text("\(stats.totalTaken) real · \(coordinator.demoWallet.positions.count) demo")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(palette.secondaryInk)
                        Spacer()
                        if let ratio = stats.takenRatio {
                            Text("Taken Ratio: \(Int((ratio * 100).rounded()))%")
                                .font(.caption2.weight(.semibold).monospacedDigit())
                                .foregroundStyle(palette.macroIceBlue)
                        }
                    }
                }
                .padding(12)
                .institutionalCard(palette: palette)

                // Source Chips: All / Demo / Real
                HStack(spacing: 6) {
                    ForEach(JournalSourceFilter.allCases) { src in
                        let selected = (sourceFilter == src)
                        Button {
                            sourceFilter = src
                        } label: {
                            Text(src.rawValue)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(selected ? palette.canvas : palette.primaryInk)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(selected ? palette.macroIceBlue : palette.elevatedSurface, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    if let csvURL = coordinator.exportJournalCSVURL(), !coordinator.journalEntries.isEmpty {
                        ShareLink(item: csvURL) {
                            Label("CSV", systemImage: "square.and.arrow.up")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(palette.macroIceBlue)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(palette.elevatedSurface, in: Capsule())
                        }
                    }
                }

                // Status Filter Chips: All / Open / Wins / Losses
                HStack(spacing: 6) {
                    ForEach(JournalFilterTab.allCases) { tab in
                        let selected = (statusFilter == tab)
                        Button {
                            statusFilter = tab
                        } label: {
                            Text(tab.rawValue)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(selected ? palette.canvas : palette.secondaryInk)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(selected ? palette.champagneGold : palette.elevatedSurface, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }

                if filteredDemoPositions.isEmpty && filteredRealEntries.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "book.closed")
                            .font(.title2)
                            .foregroundStyle(palette.champagneGold)
                        Text("No Trades Logged Yet")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(palette.primaryInk)
                        Text("Tap \"New Trade\" above or \"Trade\" on any interactive chart to place a paper Demo trade or log a real trade.")
                            .font(.caption)
                            .foregroundStyle(palette.secondaryInk)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .institutionalCard(palette: palette)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredDemoPositions) { pos in
                            demoJournalRow(pos, use24h: use24h, useUTC: useUTC, now: now)
                        }
                        ForEach(filteredRealEntries) { entry in
                            realJournalRow(entry, use24h: use24h, useUTC: useUTC, now: now)
                        }
                    }
                }
            }
            .padding(14)
        }
        .background(palette.canvas)
        .onAppear {
            coordinator.acquireActivePositionsLiveFeed()
        }
        .sheet(item: $editingEntry) { item in
            JournalEntryEditorSheet(
                entry: item,
                isExisting: true,
                coordinator: coordinator,
                palette: palette
            )
        }
        .sheet(isPresented: $showPlaceTrade) {
            PlaceDemoTradeSheet(
                coordinator: coordinator,
                palette: palette,
                onOpenJournalDraft: { draft, _ in
                    editingEntry = draft
                }
            )
        }
    }

    private func journalMetric(title: String, value: String, sub: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(palette.tertiaryInk)
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(accent)
            Text(sub)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(palette.secondaryInk)
                .lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.elevatedSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func demoJournalRow(_ pos: DemoPosition, use24h: Bool, useUTC: Bool, now: TimeInterval) -> some View {
        let quote = coordinator.livePriceService.latest(for: pos.symbol)
        let entry = pos.filledPrice ?? pos.entryPrice
        let prec = ChartPricePrecision.resolve(symbol: pos.symbol, marketClass: pos.marketClass, referencePrice: entry)
        let mark = pos.status.isActive ? (quote?.price ?? entry) : (pos.exitPrice ?? entry)
        let pnlUSD = pos.status.isActive ? (pos.status == .open ? DemoWalletEngine.pnlUSD(for: pos, markPrice: mark) : 0) : pos.realizedPnLUSD
        let metrics = LivePositionRowMetrics.compute(
            direction: pos.direction,
            entryPrice: entry,
            stopLoss: pos.stopLoss,
            initialStopLoss: pos.initialStopLoss,
            target1: pos.target1,
            liveQuote: quote,
            fallbackPrice: mark,
            pnlUSD: pnlUSD,
            marginUSD: pos.marginReservedUSD,
            nowEpochSeconds: now
        )
        let displayR: Double = pos.status.isActive ? (pos.status == .open ? metrics.rMultiple : 0.0) : pos.rMultiple
        let displayPct: Double = (pos.status == .pendingLimit) ? 0.0 : metrics.returnPercent
        let pnlColor = pnlUSD >= 0 ? palette.longEmerald : palette.shortCrimson

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("DEMO")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(palette.macroIceBlue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(palette.macroIceBlue.opacity(0.15), in: Capsule())
                Text("\(pos.symbol) · \(pos.timeframe.displayLabel)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(palette.primaryInk)
                Text(pos.direction.rawValue.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(palette.color(for: pos.direction))
                Spacer()
                if pos.status.isActive && metrics.freshness == .offline {
                    Text("OFFLINE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(palette.shortCrimson)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(palette.shortCrimson.opacity(0.15), in: Capsule())
                } else {
                    Text(pos.status.isActive ? (pos.status == .open ? "OPEN" : "LIMIT") : "CLOSED")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(pos.status.isActive ? palette.champagneGold : pnlColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background((pos.status.isActive ? palette.champagneGold : pnlColor).opacity(0.15), in: Capsule())
                }
            }

            HStack(spacing: 8) {
                Text(pos.status.isActive ? "Live \(prec.format(mark))" : "Exit \(prec.format(mark))")
                    .foregroundStyle(palette.secondaryInk)
                Spacer()
                Text("\(pnlUSD >= 0 ? "+" : "-")$\(String(format: "%.2f", abs(pnlUSD)))")
                    .fontWeight(.bold)
                    .foregroundStyle(pnlColor)
                Text("(\(String(format: "%+.2fR", displayR)) · \(String(format: "%+.1f%%", displayPct)))")
                    .foregroundStyle(pnlColor)
            }
            .font(.caption2.monospacedDigit())

            if pos.status.isActive {
                progressBar(
                    progress: metrics.stopToTargetProgress,
                    entryFraction: metrics.entryMarkerFraction,
                    stopLabel: "Stop loss \(prec.format(pos.stopLoss))",
                    targetLabel: "Target 1 \(prec.format(pos.target1))",
                    isProfit: pnlUSD >= 0
                )
            }

            HStack {
                Text(TimeDisplayFormatter.formatDateTime(epochSeconds: pos.createdAtEpochSeconds, use24Hour: use24h, useUTC: useUTC))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(palette.tertiaryInk)
                Spacer()
                if pos.status.isActive {
                    Button("Close now") {
                        _ = coordinator.closeDemoPositionManually(positionId: pos.id)
                    }
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(palette.shortCrimson)
                }
            }
        }
        .padding(12)
        .institutionalCard(palette: palette)
    }

    private func realJournalRow(_ entry: JournalEntrySnapshot, use24h: Bool, useUTC: Bool, now: TimeInterval) -> some View {
        let dec = PriceFormatHelper.decimals(for: entry.symbol, marketClass: entry.marketClass, referencePrice: entry.plannedEntry)
        let entryPrice = entry.actualFillPrice ?? entry.plannedEntry
        let quote = (entry.outcome == .open) ? coordinator.livePriceService.latest(for: entry.symbol) : nil
        let liveMetrics = (entry.outcome == .open)
            ? LivePositionRowMetrics.compute(
                direction: entry.direction,
                entryPrice: entryPrice,
                stopLoss: entry.stopLoss,
                target1: entry.tp1,
                liveQuote: quote,
                fallbackPrice: entryPrice,
                nowEpochSeconds: now
            )
            : nil
        let suggestion = coordinator.manualTradeSuggestions[entry.id]

        let color: Color = {
            switch entry.outcome {
            case .win: return palette.longEmerald
            case .loss: return palette.shortCrimson
            case .open: return palette.champagneGold
            case .breakeven, .scratched: return palette.secondaryInk
            }
        }()

        return VStack(alignment: .leading, spacing: 6) {
            Button {
                editingEntry = entry
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("REAL")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(palette.champagneGold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(palette.champagneGold.opacity(0.15), in: Capsule())
                        Text("\(entry.symbol) · \(entry.timeframe.displayLabel)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(palette.primaryInk)
                        Text(entry.direction.rawValue.uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(palette.color(for: entry.direction))
                        Spacer()
                        if let m = liveMetrics, m.freshness == .offline {
                            Text("OFFLINE")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(palette.shortCrimson)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(palette.shortCrimson.opacity(0.14), in: Capsule())
                        }
                        Text(entry.outcome.rawValue)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(color.opacity(0.15), in: Capsule())
                    }

                    HStack(spacing: 8) {
                        Text("Entry \(PriceFormatHelper.format(entryPrice, decimals: dec))")
                        if let q = quote {
                            Text("Live \(PriceFormatHelper.format(q.price, decimals: dec))")
                        } else if let ex = entry.exitPrice {
                            Text("Exit \(PriceFormatHelper.format(ex, decimals: dec))")
                        }
                        Spacer()
                        if let m = liveMetrics {
                            let c = m.rMultiple >= 0 ? palette.longEmerald : palette.shortCrimson
                            Text("\(String(format: "%+.2fR", m.rMultiple)) · \(String(format: "%+.2f%%", m.returnPercent))")
                                .fontWeight(.bold)
                                .foregroundStyle(c)
                        } else if let r = entry.effectiveRMultiple {
                            Text(String(format: "%+.2fR", r))
                                .fontWeight(.bold)
                                .foregroundStyle(r >= 0 ? palette.longEmerald : palette.shortCrimson)
                        }
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(palette.secondaryInk)

                    if let m = liveMetrics {
                        progressBar(
                            progress: m.stopToTargetProgress,
                            entryFraction: m.entryMarkerFraction,
                            stopLabel: "Stop loss \(PriceFormatHelper.format(entry.stopLoss, decimals: dec))",
                            targetLabel: "Target 1 \(PriceFormatHelper.format(entry.tp1, decimals: dec))",
                            isProfit: m.rMultiple >= 0
                        )
                    }

                    if !entry.notes.isEmpty {
                        Text(entry.notes)
                            .font(.caption2)
                            .foregroundStyle(palette.tertiaryInk)
                            .lineLimit(2)
                    }

                    HStack {
                        Text(TimeDisplayFormatter.formatDateTime(epochSeconds: entry.takenAt.timeIntervalSince1970, use24Hour: use24h, useUTC: useUTC))
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(palette.tertiaryInk)
                        Spacer()
                        Text("Tap to edit")
                            .font(.system(size: 10))
                            .foregroundStyle(palette.tertiaryInk)
                    }
                }
            }
            .buttonStyle(.plain)

            // Manual trades NEVER auto-close: surface non-destructive Apply / Dismiss chip when level hit
            if let sug = suggestion {
                HStack(spacing: 8) {
                    Image(systemName: "bell.badge.fill")
                        .font(.caption2)
                        .foregroundStyle(palette.champagneGold)
                    Text(sug.message)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(palette.primaryInk)
                    Spacer()
                    Button("Apply") {
                        coordinator.applyManualTradeSuggestion(sug)
                    }
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(palette.canvas)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(palette.longEmerald, in: Capsule())

                    Button("Dismiss") {
                        coordinator.dismissManualTradeSuggestion(entryId: entry.id)
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(palette.secondaryInk)
                }
                .padding(8)
                .background(palette.champagneGold.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(12)
        .institutionalCard(palette: palette)
    }

    private func progressBar(
        progress: Double,
        entryFraction: Double,
        stopLabel: String,
        targetLabel: String,
        isProfit: Bool
    ) -> some View {
        VStack(spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.border.opacity(0.4)).frame(height: 5)
                    Capsule()
                        .fill(isProfit ? palette.longEmerald : palette.shortCrimson)
                        .frame(width: max(4, geo.size.width * progress), height: 5)
                    Rectangle()
                        .fill(palette.champagneGold)
                        .frame(width: 2, height: 9)
                        .offset(x: max(0, min(geo.size.width - 2, geo.size.width * entryFraction)))
                }
            }
            .frame(height: 9)

            HStack {
                Text(stopLabel).foregroundStyle(palette.shortCrimson)
                Spacer()
                Text(targetLabel).foregroundStyle(palette.longEmerald)
            }
            .font(.system(size: 10).monospacedDigit())
        }
    }
}
