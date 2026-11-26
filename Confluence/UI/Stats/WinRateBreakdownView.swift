import SwiftUI
import SignalEngine

/// Displays the 3-Bucket Comparison (`Strong Signals`, `Weak & Filtered`, `Trap Alerts`)
/// with Win Rate %, 95% Wilson CI, W / L, Live / Pending, and Avg R, plus the raw score strength
/// bucket breakdown (`50–59`, `60–69`, `70–79`, `80+`).
public struct WinRateBreakdownView: View {
    public let journalSectionStats: [JournalSectionStat]
    public let originStats: [OriginWinRateStat]
    public let strengthBuckets: [StrengthBucketStat]
    public let palette: ConfluencePalette

    public init(
        journalSectionStats: [JournalSectionStat] = [],
        originStats: [OriginWinRateStat],
        strengthBuckets: [StrengthBucketStat],
        palette: ConfluencePalette
    ) {
        self.journalSectionStats = journalSectionStats
        self.originStats = originStats
        self.strengthBuckets = strengthBuckets
        self.palette = palette
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1. 3-Bucket Comparison (Strong Signals / Weak & Filtered / Trap Alerts)
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("3-Bucket Performance Comparison")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(palette.primaryInk)
                    Spacer()
                    Text("95% Wilson CI")
                        .font(.caption2)
                        .foregroundStyle(palette.tertiaryInk)
                }

                if !journalSectionStats.isEmpty {
                    ForEach(journalSectionStats) { stat in
                        journalBucketCard(stat)
                    }
                } else {
                    ForEach(originStats) { stat in
                        originFallbackCard(stat)
                    }
                }
            }
            .padding(14)
            .institutionalCard(palette: palette)

            // 2. Score Strength Bucket Breakdown
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Win Rate by Score Strength")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(palette.primaryInk)
                    Spacer()
                    Text("95% Wilson CI")
                        .font(.caption2)
                        .foregroundStyle(palette.tertiaryInk)
                }

                ForEach(strengthBuckets) { bucket in
                    HStack {
                        Text("Score \(bucket.label)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(palette.primaryInk)
                        Spacer()
                        if bucket.totalResolved == 0 {
                            Text("No trades yet")
                                .font(.caption2)
                                .foregroundStyle(palette.tertiaryInk)
                        } else {
                            let color = bucket.winRate >= 0.5 ? palette.longEmerald : palette.shortCrimson
                            let pct = String(format: "%.1f%%", bucket.winRate * 100.0)
                            let ciText = bucket.winRateCI.map { " \($0.percentRangeLabel)" } ?? ""
                            Text("\(pct)\(ciText) · n=\(bucket.totalResolved)")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(color)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(palette.elevatedSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(14)
            .institutionalCard(palette: palette)
        }
    }

    private func journalBucketCard(_ stat: JournalSectionStat) -> some View {
        let accent: Color = {
            switch stat.section {
            case .strongSignals:
                return stat.totalResolved > 0 ? (stat.winRate >= 0.5 ? palette.longEmerald : palette.shortCrimson) : palette.champagneGold
            case .weakAndFiltered:
                return palette.secondaryInk
            case .trapAlerts:
                return palette.trapAmber
            }
        }()

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(accent)
                        .frame(width: 7, height: 7)
                    Text(stat.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(palette.primaryInk)
                }
                Spacer()
                if stat.totalResolved > 0 {
                    Text(String(format: "%.1f%%", stat.winRate * 100.0))
                        .font(.headline.weight(.bold).monospacedDigit())
                        .foregroundStyle(accent)
                } else {
                    Text("—")
                        .font(.headline.weight(.bold).monospacedDigit())
                        .foregroundStyle(palette.tertiaryInk)
                }
            }

            HStack(spacing: 8) {
                bucketMiniMetric("W / L", "\(stat.wins)W / \(stat.losses)L", palette.primaryInk)
                bucketMiniMetric("LIVE / PEND", "\(stat.liveCount) / \(stat.pendingCount)", stat.liveCount > 0 ? palette.champagneGold : palette.secondaryInk)
                bucketMiniMetric(
                    "AVG R",
                    stat.totalResolved > 0 ? String(format: "%+.2fR", stat.averageR) : "—",
                    stat.totalResolved > 0 ? (stat.averageR >= 0 ? palette.longEmerald : palette.shortCrimson) : palette.tertiaryInk
                )
                bucketMiniMetric(
                    "95% CI",
                    stat.winRateCI?.percentRangeLabel ?? "n=\(stat.totalResolved)",
                    palette.secondaryInk
                )
            }
        }
        .padding(11)
        .background(palette.elevatedSurface.opacity(0.68), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func originFallbackCard(_ stat: OriginWinRateStat) -> some View {
        let accent: Color = {
            if stat.totalResolved == 0 { return palette.secondaryInk }
            switch stat.group {
            case .strongSignals: return stat.winRate >= 0.5 ? palette.longEmerald : palette.shortCrimson
            case .weakAndFiltered: return palette.secondaryInk
            case .trapAlerts: return palette.trapAmber
            }
        }()

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(stat.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(palette.primaryInk)
                Text(stat.countsSummaryText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(palette.secondaryInk)
                if let ci = stat.winRateCI {
                    Text("95% CI \(ci.percentRangeLabel)")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(palette.tertiaryInk)
                }
            }
            Spacer()
            Text(stat.totalResolved > 0 ? String(format: "%.1f%%", stat.winRate * 100.0) : "—")
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(accent)
        }
        .padding(11)
        .background(palette.elevatedSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func bucketMiniMetric(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(palette.tertiaryInk)
            Text(value)
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
