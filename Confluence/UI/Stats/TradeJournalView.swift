import SwiftUI
import SignalEngine

public enum JournalFilterTab: String, CaseIterable, Identifiable {
    case all = "All"
    case open = "Live"
    case wins = "Wins"
    case losses = "Losses"
    case expired = "Expired"
    public var id: String { rawValue }
}

// MARK: - Isolated Live Tick Metrics Leaf (Zero Parent Card Re-evaluation on Ticks)

private struct JournalLiveMetricsLeafView: View {
    let entry: TrackedJournalTrade
    let journalCoordinator: SignalJournalCoordinator
    let precision: ChartPricePrecision
    let palette: ConfluencePalette

    var body: some View {
        let tick = journalCoordinator.liveTicksByEntryID[entry.id]
        let price = tick?.price ?? entry.currentPrice
        let pct = tick?.pnlPercent ?? entry.livePnLPercent
        let rMult: Double = entry.status.isOpen
            ? (tick?.rMultiple ?? entry.liveRMultiple)
            : (entry.realizedR ?? entry.liveRMultiple)
        let isPositive = rMult >= 0
        let tone = entry.status == .pending
            ? palette.secondaryInk
            : (isPositive ? palette.longEmerald : palette.shortCrimson)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(entry.status.isOpen ? "Live \(precision.format(price))" : "Last \(precision.format(price))")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(palette.secondaryInk)
                Spacer()
                if entry.status == .pending {
                    Text("Waiting for entry fill")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(palette.tertiaryInk)
                } else if entry.status == .expired {
                    Text("0.00R · Unfilled")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(palette.tertiaryInk)
                } else {
                    Text("\(String(format: "%+.2fR", rMult)) · \(String(format: "%+.2f%%", pct))")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(tone)
                }
            }

            // Compact SL — Entry — Live — TP1 — TP2 visual progress track
            levelProgressTrack(currentPrice: price, isPositive: isPositive)
        }
    }

    private func levelProgressTrack(currentPrice: Double, isPositive: Bool) -> some View {
        let farTarget = entry.hasDistinctTP2 ? entry.target2 : entry.target1
        let minP = min(entry.stopLoss, farTarget)
        let maxP = max(entry.stopLoss, farTarget)
        let span = max(maxP - minP, 1e-9)

        func normalized(_ p: Double) -> Double {
            let raw = entry.direction == .short
                ? (maxP - p) / span
                : (p - minP) / span
            return min(1.0, max(0.0, raw))
        }

        let entryFrac = normalized(entry.anchorEntryPrice)
        let tp1Frac = normalized(entry.target1)
        let liveFrac = normalized(currentPrice)

        return VStack(spacing: 4) {
            GeometryReader { geo in
                let w = max(1, geo.size.width)
                let fillStart = min(entryFrac, liveFrac) * w
                let fillWidth = max(3, abs(liveFrac - entryFrac) * w)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(palette.border.opacity(0.45))
                        .frame(height: 5)
                    if entry.status != .pending && entry.status != .expired {
                        Capsule()
                            .fill(isPositive ? palette.longEmerald : palette.shortCrimson)
                            .frame(width: fillWidth, height: 5)
                            .offset(x: fillStart)
                    }
                    // Entry marker
                    Rectangle()
                        .fill(palette.champagneGold)
                        .frame(width: 2, height: 10)
                        .offset(x: max(0, min(w - 2, entryFrac * w)))
                    // TP1 marker when TP2 is distinct
                    if entry.hasDistinctTP2 {
                        Rectangle()
                            .fill(palette.longEmerald)
                            .frame(width: 2, height: 10)
                            .offset(x: max(0, min(w - 2, tp1Frac * w)))
                    }
                    // Live dot
                    Circle()
                        .fill(entry.status == .pending ? palette.secondaryInk : (isPositive ? palette.longEmerald : palette.shortCrimson))
                        .frame(width: 8, height: 8)
                        .offset(x: max(0, min(w - 8, liveFrac * w - 4)))
                }
            }
            .frame(height: 10)

            HStack(spacing: 4) {
                Text("SL \(precision.format(entry.stopLoss))")
                    .foregroundStyle(palette.shortCrimson)
                Spacer()
                Text("E \(precision.format(entry.anchorEntryPrice))")
                    .foregroundStyle(palette.champagneGold)
                Spacer()
                Text("T1 \(precision.format(entry.target1))")
                    .foregroundStyle(palette.longEmerald)
                if entry.hasDistinctTP2 {
                    Text("· T2 \(precision.format(entry.target2))")
                        .foregroundStyle(palette.longEmerald.opacity(0.9))
                }
            }
            .font(.system(size: 9.5, weight: .medium).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
    }
}

// MARK: - 100% Automatic 3-Section Live Signal Journal View

/// 100% Automatic 3-Section Signal Journal (`Strong Signals` | `Weak & Filtered` | `Trap Alerts`).
/// Zero manual entry buttons, zero Demo Wallet rows, battery-safe <= 2 Hz live tracking.
public struct TradeJournalView: View {
    @Bindable public var coordinator: MarketScannerCoordinator
    public let palette: ConfluencePalette

    @State private var selectedSection: JournalSection = .strongSignals
    @State private var statusFilter: JournalFilterTab = .all
    @State private var orderFlowPayload: OrderFlowSheetPayload? = nil

    public init(coordinator: MarketScannerCoordinator, palette: ConfluencePalette) {
        self.coordinator = coordinator
        self.palette = palette
    }

    private var sectionEntries: [TrackedJournalTrade] {
        coordinator.journalCoordinator.entries(for: selectedSection)
    }

    private var filteredEntries: [TrackedJournalTrade] {
        sectionEntries.filter { entry in
            switch statusFilter {
            case .all: return true
            case .open: return entry.status.isOpen
            case .wins: return entry.status.isCountedWin
            case .losses: return entry.status.isCountedLoss
            case .expired: return entry.status == .expired
            }
        }
    }

    public var body: some View {
        let stat = coordinator.journalCoordinator.stat(for: selectedSection)
        let use24h = coordinator.settings.payload.use24HourTime
        let useUTC = coordinator.settings.payload.useUTCTimeZone

        ScrollView {
            VStack(spacing: 12) {
                // 1. 3-Section Selector Bar with live/total badge counts
                HStack(spacing: 6) {
                    ForEach(JournalSection.allCases) { section in
                        let isSelected = (selectedSection == section)
                        let secStat = coordinator.journalCoordinator.stat(for: section)
                        let totalCount = coordinator.journalCoordinator.entries(for: section).count
                        let liveBadge = secStat.liveCount + secStat.pendingCount
                        Button {
                            selectedSection = section
                        } label: {
                            VStack(spacing: 2) {
                                Text(shortSectionTitle(section))
                                    .font(.caption2.weight(.bold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                Text(liveBadge > 0 ? "\(liveBadge) live · \(totalCount)" : "\(totalCount) total")
                                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                                    .opacity(isSelected ? 0.9 : 0.75)
                            }
                            .foregroundStyle(isSelected ? palette.canvas : palette.primaryInk)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity)
                            .background(isSelected ? palette.champagneGold : palette.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .strokeBorder(isSelected ? Color.clear : palette.border, lineWidth: 0.75)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                // 2. Section Summary Strip (Live, Pending, Win Rate, Avg R)
                HStack(spacing: 8) {
                    summaryCell("LIVE", "\(stat.liveCount)", palette.champagneGold)
                    summaryCell("PENDING", "\(stat.pendingCount)", palette.secondaryInk)
                    summaryCell(
                        "WIN RATE",
                        stat.totalResolved > 0 ? String(format: "%.1f%%", stat.winRate * 100.0) : "—",
                        stat.totalResolved > 0 ? (stat.winRate >= 0.5 ? palette.longEmerald : palette.shortCrimson) : palette.tertiaryInk
                    )
                    summaryCell(
                        "AVG R",
                        stat.totalResolved > 0 ? String(format: "%+.2fR", stat.averageR) : "—",
                        stat.totalResolved > 0 ? (stat.averageR >= 0 ? palette.longEmerald : palette.shortCrimson) : palette.tertiaryInk
                    )
                }
                .padding(10)
                .institutionalCard(palette: palette)

                // 3. Status Filter Chips + CSV ShareLink
                HStack(spacing: 6) {
                    ScrollView(.horizontal, showsIndicators: false) {
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
                        }
                    }

                    if let csvURL = coordinator.exportJournalCSVURL(), !coordinator.journalCoordinator.allEntries.isEmpty {
                        ShareLink(item: csvURL) {
                            Label("CSV", systemImage: "square.and.arrow.up")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(palette.primaryInk)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(palette.elevatedSurface, in: Capsule())
                                .overlay(Capsule().strokeBorder(palette.border, lineWidth: 0.75))
                        }
                    }
                }

                // 4. Automatic Tracked Signal Feed (LazyVStack with deterministic IDs)
                if filteredEntries.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "waveform.path.ecg.rectangle")
                            .font(.title2)
                            .foregroundStyle(palette.champagneGold)
                        Text("No \(selectedSection.displayName) Logged Yet")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(palette.primaryInk)
                        Text("Confluence automatically records and tracks every scanned Strong Signal, Weak/Filtered setup, and Trap Alert live against market prices — zero manual entry required.")
                            .font(.caption)
                            .foregroundStyle(palette.secondaryInk)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .institutionalCard(palette: palette)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredEntries) { entry in
                            journalCard(entry, use24h: use24h, useUTC: useUTC)
                                .id(entry.id)
                        }
                    }
                }
            }
            .padding(14)
        }
        .safeAreaPadding(.bottom, 96)
        .background(palette.canvas)
        .onAppear {
            coordinator.acquireActivePositionsLiveFeed()
        }
        .sheet(item: $orderFlowPayload) { payload in
            OrderFlowInsightSheet(
                payload: payload,
                palette: palette,
                use24HourTime: use24h,
                useUTCTimeZone: useUTC
            )
        }
    }

    private func shortSectionTitle(_ section: JournalSection) -> String {
        switch section {
        case .strongSignals: return "Strong"
        case .weakAndFiltered: return "Weak / Filtered"
        case .trapAlerts: return "Trap Alerts"
        }
    }

    private func summaryCell(_ title: String, _ value: String, _ accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(palette.tertiaryInk)
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func journalCard(_ entry: TrackedJournalTrade, use24h: Bool, useUTC: Bool) -> some View {
        let prec = ChartPricePrecision.resolve(
            symbol: entry.symbol,
            marketClass: entry.assetClass,
            referencePrice: entry.anchorEntryPrice
        )
        let statusTone = statusColor(for: entry.status)

        return VStack(alignment: .leading, spacing: 8) {
            // Header Row: Symbol + TF + Direction + Score + Status Pill
            HStack(spacing: 6) {
                Text(entry.symbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(palette.primaryInk)
                    .lineLimit(1)

                Text(entry.timeframe.displayLabel)
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(palette.secondaryInk)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(palette.elevatedSurface, in: Capsule())

                Text(entry.direction.rawValue.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.color(for: entry.direction))

                Text("\(Int(entry.score.rounded()))")
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(palette.champagneGold)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(palette.champagneGold.opacity(0.14), in: Capsule())

                Spacer(minLength: 4)

                Text(entry.status.badgeLabel)
                    .font(.system(size: 9.5, weight: .heavy))
                    .foregroundStyle(statusTone)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusTone.opacity(0.15), in: Capsule())
            }

            // Filter Reason pill (Weak & Filtered / Trap Alerts) + Tappable Crypto Order Flow Sign
            if entry.filterReason != nil || (entry.assetClass == .crypto && entry.orderFlowSummary != nil) {
                ConfluenceFlowLayout(horizontalSpacing: 6, verticalSpacing: 5) {
                    if let reason = entry.filterReason, !reason.isEmpty {
                        Text(reason)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(entry.section == .trapAlerts ? palette.trapAmber : palette.secondaryInk)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background((entry.section == .trapAlerts ? palette.trapAmber.opacity(0.14) : palette.elevatedSurface), in: Capsule())
                    }

                    if entry.assetClass == .crypto, let ofSummary = entry.orderFlowSummary {
                        OrderFlowSignPill(summary: ofSummary, palette: palette) {
                            orderFlowPayload = OrderFlowSheetPayload(
                                id: "journal_\(entry.id)",
                                symbol: entry.symbol,
                                timeframe: entry.timeframe,
                                direction: entry.direction,
                                summary: ofSummary,
                                entry: entry.anchorEntryPrice,
                                stopLoss: entry.stopLoss,
                                target1: entry.target1,
                                target2: entry.hasDistinctTP2 ? entry.target2 : nil,
                                isHistoricalSnapshot: true
                            )
                        }
                    }
                }
            }

            // Isolated Live Metrics & SL — Entry — Live — TP1 — TP2 Track
            JournalLiveMetricsLeafView(
                entry: entry,
                journalCoordinator: coordinator.journalCoordinator,
                precision: prec,
                palette: palette
            )

            // Footer Timestamp
            HStack {
                Text("Captured \(TimeDisplayFormatter.formatDateTime(epochSeconds: entry.createdAt, use24Hour: use24h, useUTC: useUTC))")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(palette.tertiaryInk)
                Spacer()
                if let closedAt = entry.closedAt {
                    Text("Closed \(TimeDisplayFormatter.formatShortTime(epochSeconds: closedAt, use24Hour: use24h, useUTC: useUTC))")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(palette.tertiaryInk)
                } else if entry.isWinLocked {
                    Text("WIN LOCKED · Runner")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(palette.longEmerald)
                }
            }
        }
        .padding(12)
        .institutionalCard(palette: palette, accentBorder: entry.status == .winTrackingTP2 ? palette.longEmerald.opacity(0.45) : nil)
    }

    private func statusColor(for status: JournalTradeStatus) -> Color {
        switch status {
        case .pending: return palette.secondaryInk
        case .live: return palette.champagneGold
        case .winTrackingTP2, .winTP1, .winTP2: return palette.longEmerald
        case .loss: return palette.shortCrimson
        case .expired: return palette.tertiaryInk
        }
    }
}
