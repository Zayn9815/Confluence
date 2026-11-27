import SwiftUI
import SignalEngine

/// Isolated live price marker leaf so live WebSocket ticks redraw ONLY this tiny dot on the ladder
/// with zero parent `SignalCardView` re-renders.
private struct LadderLiveMarkerLeaf: View {
    let symbol: String
    let direction: TradeDirection
    let minPrice: Double
    let maxPrice: Double
    let barWidth: CGFloat
    let livePriceService: LivePriceService
    let palette: ConfluencePalette

    var body: some View {
        if let quote = livePriceService.latest(for: symbol), quote.price.isFinite, quote.price > 0 {
            let span = max(maxPrice - minPrice, 1e-9)
            let raw = (direction == .short)
                ? (maxPrice - quote.price) / span
                : (quote.price - minPrice) / span
            let frac = min(1.0, max(0.0, raw))
            Circle()
                .fill(palette.primaryInk)
                .frame(width: 9, height: 9)
                .overlay(Circle().strokeBorder(palette.champagneGold, lineWidth: 1.5))
                .offset(x: max(0, min(barWidth - 9, CGFloat(frac) * barWidth - 4.5)))
                .allowsHitTesting(false)
        }
    }
}

/// Proportional SL -> Entry Zone (gold band) -> TP1 -> TP2 visual price ladder bar with
/// isolated live price marker and collision-free 390pt price anchors.
public struct SignalRiskRewardLadderView: View {
    public let symbol: String
    public let marketClass: MarketClass
    public let direction: TradeDirection
    public let levels: TradeLevels
    public let livePriceService: LivePriceService
    public let palette: ConfluencePalette
    public let showFullAnchors: Bool

    public init(
        symbol: String,
        marketClass: MarketClass,
        direction: TradeDirection,
        levels: TradeLevels,
        livePriceService: LivePriceService,
        palette: ConfluencePalette,
        showFullAnchors: Bool = true
    ) {
        self.symbol = symbol
        self.marketClass = marketClass
        self.direction = direction
        self.levels = levels
        self.livePriceService = livePriceService
        self.palette = palette
        self.showFullAnchors = showFullAnchors
    }

    private func normalizedPosition(_ price: Double, minP: Double, maxP: Double) -> Double {
        let span = max(maxP - minP, 1e-9)
        let raw = (direction == .short)
            ? (maxP - price) / span
            : (price - minP) / span
        return min(1.0, max(0.0, raw))
    }

    public var body: some View {
        let farTarget = levels.isTP2Enabled ? levels.tp2 : levels.tp1
        let minP = min(levels.stopLoss, levels.entryLow, levels.entryHigh, levels.tp1, farTarget)
        let maxP = max(levels.stopLoss, levels.entryLow, levels.entryHigh, levels.tp1, farTarget)

        let slFrac = normalizedPosition(levels.stopLoss, minP: minP, maxP: maxP)
        let entryStart = min(
            normalizedPosition(levels.entryLow, minP: minP, maxP: maxP),
            normalizedPosition(levels.entryHigh, minP: minP, maxP: maxP)
        )
        let entryEnd = max(
            normalizedPosition(levels.entryLow, minP: minP, maxP: maxP),
            normalizedPosition(levels.entryHigh, minP: minP, maxP: maxP)
        )
        let tp1Frac = normalizedPosition(levels.tp1, minP: minP, maxP: maxP)
        let tp2Frac = normalizedPosition(farTarget, minP: minP, maxP: maxP)
        let prec = PriceFormatHelper.precision(for: symbol, marketClass: marketClass, referencePrice: levels.entryMid)

        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let w = max(1, geo.size.width)
                let riskStart = min(slFrac, entryStart) * w
                let riskWidth = max(2, abs(entryStart - slFrac) * w)
                let rewardStart = entryEnd * w
                let rewardWidth = max(2, abs(tp2Frac - entryEnd) * w)
                let entryX = entryStart * w
                let entryW = max(6, (entryEnd - entryStart) * w)

                ZStack(alignment: .leading) {
                    // Base rail
                    Capsule()
                        .fill(palette.border.opacity(0.45))
                        .frame(height: 6)

                    // Risk segment (SL -> Entry)
                    Capsule()
                        .fill(palette.shortCrimson.opacity(0.65))
                        .frame(width: riskWidth, height: 6)
                        .offset(x: riskStart)

                    // Reward segment (Entry -> TP1/TP2)
                    Capsule()
                        .fill(palette.longEmerald.opacity(0.7))
                        .frame(width: rewardWidth, height: 6)
                        .offset(x: rewardStart)

                    // Entry Zone Gold Band
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(palette.champagneGold)
                        .frame(width: entryW, height: 10)
                        .offset(x: max(0, min(w - entryW, entryX)))

                    // TP1 notch when TP2 is enabled
                    if levels.isTP2Enabled {
                        Rectangle()
                            .fill(palette.longEmerald)
                            .frame(width: 2.5, height: 12)
                            .offset(x: max(0, min(w - 2.5, CGFloat(tp1Frac) * w - 1.25)))
                    }

                    // Isolated live price marker leaf
                    LadderLiveMarkerLeaf(
                        symbol: symbol,
                        direction: direction,
                        minPrice: minP,
                        maxPrice: maxP,
                        barWidth: w,
                        livePriceService: livePriceService,
                        palette: palette
                    )
                }
                .frame(height: 12)
            }
            .frame(height: 12)

            if showFullAnchors {
                // Collision-free 2x2 anchor grid on 390pt iPhones (even for 5-decimal FX pairs)
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), alignment: .leading),
                        GridItem(.flexible(), alignment: .trailing)
                    ],
                    spacing: 4
                ) {
                    anchorLabel("SL", price: prec.format(levels.stopLoss), detail: "-\(String(format: "%.2f", levels.riskPercent))%", color: palette.shortCrimson)
                    anchorLabel("ENTRY", price: "\(prec.format(levels.entryLow))–\(prec.format(levels.entryHigh))", detail: "1:\(String(format: "%.1f", levels.riskRewardRatio))", color: palette.champagneGold)
                    anchorLabel("TP1", price: prec.format(levels.tp1), detail: "+\(String(format: "%.2f", levels.reward1Percent))%", color: palette.longEmerald)
                    if levels.isTP2Enabled {
                        anchorLabel("TP2", price: prec.format(levels.tp2), detail: "+\(String(format: "%.2f", levels.reward2Percent))%", color: palette.longEmerald)
                    } else {
                        anchorLabel("TP2", price: "Off", detail: "TP1 Only", color: palette.tertiaryInk)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(palette.elevatedSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(palette.border, lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Risk reward ladder. Stop loss \(prec.format(levels.stopLoss)), Entry \(prec.format(levels.entryMid)), Target 1 \(prec.format(levels.tp1))\(levels.isTP2Enabled ? ", Target 2 \(prec.format(levels.tp2))" : "")"
        )
    }

    private func anchorLabel(_ tag: String, price: String, detail: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
            Text(price)
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(palette.primaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(detail)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(palette.tertiaryInk)
                .lineLimit(1)
        }
    }
}
