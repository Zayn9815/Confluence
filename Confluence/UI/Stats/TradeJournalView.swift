import SwiftUI
import SignalEngine

public enum JournalFilterTab: String, CaseIterable, Identifiable {
    case all = "All"
    case open = "Open"
    case wins = "Wins"
    case losses = "Losses"
    public var id: String { rawValue }
}

/// Personal Trade Journal comparing real execution (`My Avg R`, `My Win Rate`) against
/// system passive outcomes (`System Avg R`) with 1-tap RFC-4180 CSV export.
public struct TradeJournalView: View {
    @Bindable public var coordinator: MarketScannerCoordinator
    public let palette: ConfluencePalette

    @State private var filter: JournalFilterTab = .all
    @State private var editingEntry: JournalEntrySnapshot?

    public init(coordinator: MarketScannerCoordinator, palette: ConfluencePalette) {
        self.coordinator = coordinator
        self.palette = palette
    }

    private var filteredEntries: [JournalEntrySnapshot] {
        coordinator.journalEntries.filter { e in
            switch filter {
            case .all: return true
            case .open: return e.outcome == .open
            case .wins: return e.outcome == .win
            case .losses: return e.outcome == .loss
            }
        }
    }

    public var body: some View {
        let stats = coordinator.journalSummary
        let use24h = coordinator.settings.payload.use24HourTime
        let useUTC = coordinator.settings.payload.useUTCTimeZone

        ScrollView {
            VStack(spacing: 12) {
                // My Execution vs System Comparison Card
                VStack(alignment: .leading, spacing: 8) {
                    Text("MY EXECUTION VS. SYSTEM")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(palette.tertiaryInk)

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
                        Text("\(stats.totalTaken) logged · \(stats.closedCount) closed")
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

                // Filter Chips + Export CSV
                HStack(spacing: 6) {
                    ForEach(JournalFilterTab.allCases) { tab in
                        let selected = (filter == tab)
                        Button {
                            filter = tab
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

                if filteredEntries.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "book.closed")
                            .font(.title2)
                            .foregroundStyle(palette.champagneGold)
                        Text("No Journal Entries Yet")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(palette.primaryInk)
                        Text("Tap \"Mark Taken\" on any Signal Card to log your real fill price, size, outcome, and review notes.")
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
                            journalRow(entry, use24h: use24h, useUTC: useUTC)
                        }
                    }
                }
            }
            .padding(14)
        }
        .background(palette.canvas)
        .sheet(item: $editingEntry) { item in
            JournalEntryEditorSheet(
                entry: item,
                isExisting: true,
                coordinator: coordinator,
                palette: palette
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

    private func journalRow(_ entry: JournalEntrySnapshot, use24h: Bool, useUTC: Bool) -> some View {
        let dec = PriceFormatHelper.decimals(for: entry.symbol, marketClass: entry.marketClass, referencePrice: entry.plannedEntry)
        let color: Color = {
            switch entry.outcome {
            case .win: return palette.longEmerald
            case .loss: return palette.shortCrimson
            case .open: return palette.champagneGold
            case .breakeven, .scratched: return palette.secondaryInk
            }
        }()

        return Button {
            editingEntry = entry
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(entry.symbol) · \(entry.timeframe.displayLabel)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(palette.primaryInk)
                    Text(entry.direction.rawValue.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(palette.color(for: entry.direction))
                    Spacer()
                    Text(entry.outcome.rawValue)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(color.opacity(0.15), in: Capsule())
                }

                HStack(spacing: 10) {
                    Text("Fill \(PriceFormatHelper.format(entry.actualFillPrice ?? entry.plannedEntry, decimals: dec))")
                    Text("SL \(PriceFormatHelper.format(entry.stopLoss, decimals: dec))")
                    if let ex = entry.exitPrice {
                        Text("Exit \(PriceFormatHelper.format(ex, decimals: dec))")
                    }
                    Spacer()
                    if let r = entry.effectiveRMultiple {
                        Text(String(format: "%+.2fR", r))
                            .fontWeight(.bold)
                            .foregroundStyle(r >= 0 ? palette.longEmerald : palette.shortCrimson)
                    }
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(palette.secondaryInk)

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
                    if let sz = entry.positionSizeText {
                        Text("· \(sz)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(palette.macroIceBlue)
                    }
                    Spacer()
                }
            }
            .padding(12)
            .institutionalCard(palette: palette, accentBorder: color.opacity(0.35))
        }
        .buttonStyle(.plain)
    }
}
