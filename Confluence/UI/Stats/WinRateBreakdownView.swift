import SwiftUI
import SignalEngine

/// Displays the three honest Win Rate by Origin cards (Strong signals, Traps and filtered, News setups)
/// and the raw score strength bucket breakdown (50–59, 60–69, 70–79, 80+) with Wilson 95% CI and
/// `"No trades yet"` for empty buckets.
public struct WinRateBreakdownView: View {
    public let originStats: [OriginWinRateStat]
    public let strengthBuckets: [StrengthBucketStat]
    public let palette: ConfluencePalette

    public init(
        originStats: [OriginWinRateStat],
        strengthBuckets: [StrengthBucketStat],
        palette: ConfluencePalette
    ) {
        self.originStats = originStats
        self.strengthBuckets = strengthBuckets
        self.palette = palette
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1. Three Origin Win-Rate Cards
            VStack(alignment: .leading, spacing: 8) {
                Text("Win Rate by Origin")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(palette.primaryInk)

                ForEach(originStats) { stat in
                    originCard(stat)
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
                            Text(bucket.summaryText)
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(color)
                        }
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    .background(palette.elevatedSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(14)
            .institutionalCard(palette: palette)
        }
    }

    private func originCard(_ stat: OriginWinRateStat) -> some View {
        let accent: Color = {
            if stat.totalResolved == 0 { return palette.secondaryInk }
            switch stat.group {
            case .strongSignals: return stat.winRate >= 0.5 ? palette.longEmerald : palette.shortCrimson
            case .trapsAndFiltered: return palette.trapAmber
            case .newsSetups: return palette.macroIceBlue
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
            Text(stat.totalResolved > 0 ? "\(Int((stat.winRate * 100).rounded()))%" : "—")
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(accent)
        }
        .padding(11)
        .background(palette.elevatedSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
