import SwiftUI
import SignalEngine

/// High-performance 120Hz pure SwiftUI `Canvas` mini candlestick chart for Signal Cards.
/// Plots closed candles, optional display-only live price tick (throttled <= 1/s by caller),
/// active FVG/OB zones, active Trap lifecycle lines (`Trigger`/`Active`),
/// and numeric Entry / Stop loss / Target 1 / Target 2 levels with zero WKWebView overhead.
public struct MiniCandlestickCanvas: View, Equatable {
    let candles: [Candle]
    let levels: TradeLevels?
    let overlays: ChartOverlayData
    let palette: ConfluencePalette
    let height: CGFloat
    let livePrice: Double?

    public static func == (lhs: MiniCandlestickCanvas, rhs: MiniCandlestickCanvas) -> Bool {
        lhs.height == rhs.height &&
        lhs.livePrice == rhs.livePrice &&
        lhs.levels == rhs.levels &&
        lhs.overlays == rhs.overlays &&
        lhs.candles.count == rhs.candles.count &&
        lhs.candles.last == rhs.candles.last &&
        lhs.palette.isLight == rhs.palette.isLight &&
        lhs.palette.isPureBlackAMOLED == rhs.palette.isPureBlackAMOLED &&
        lhs.palette.themePreset == rhs.palette.themePreset
    }

    public init(
        candles: [Candle],
        levels: TradeLevels?,
        overlays: ChartOverlayData,
        palette: ConfluencePalette,
        height: CGFloat = 112,
        livePrice: Double? = nil
    ) {
        self.candles = candles
        self.levels = levels
        self.overlays = overlays
        self.palette = palette
        self.height = height
        self.livePrice = livePrice
    }

    public var body: some View {
        Canvas { context, size in
            let slice = Array(candles.suffix(36))
            guard !slice.isEmpty else { return }

            var minPrice = slice.map(\.low).min() ?? 0
            var maxPrice = slice.map(\.high).max() ?? 1
            let refClose = slice.last?.close ?? ((minPrice + maxPrice) * 0.5)

            if let lp = livePrice, lp.isFinite, lp > 0, abs(lp - refClose) / max(refClose, 1e-9) <= 0.20 {
                minPrice = min(minPrice, lp)
                maxPrice = max(maxPrice, lp)
            }

            if let lv = levels {
                minPrice = min(minPrice, lv.stopLoss, lv.tp1, lv.entryLow)
                maxPrice = max(maxPrice, lv.stopLoss, lv.tp1, lv.entryHigh)
            }
            for trap in overlays.traps where trap.isActionable {
                if abs(trap.level - refClose) / max(refClose, 1e-9) <= 0.20 {
                    minPrice = min(minPrice, trap.level)
                    maxPrice = max(maxPrice, trap.level)
                }
            }

            let span = max(maxPrice - minPrice, 1e-9)
            let pad = span * 0.08
            let lowBound = minPrice - pad
            let highBound = maxPrice + pad
            let totalRange = highBound - lowBound

            func yFor(_ price: Double) -> CGFloat {
                let norm = (price - lowBound) / totalRange
                return size.height * (1.0 - CGFloat(norm))
            }

            // 1. Subtle horizontal grid lines
            for frac in [0.25, 0.5, 0.75] {
                let y = size.height * CGFloat(frac)
                var grid = Path()
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(grid, with: .color(palette.chart.grid.color), lineWidth: 0.5)
            }

            // 2. Active FVG & Order Block Zones
            for zone in overlays.zones.prefix(3) {
                let yTop = yFor(zone.top)
                let yBot = yFor(zone.bottom)
                let rect = CGRect(x: 0, y: min(yTop, yBot), width: size.width, height: max(2, abs(yBot - yTop)))
                let fillColor: Color = (zone.direction == .long ? palette.chart.bullCandle.color : palette.chart.bearCandle.color).opacity(zone.kind == .orderBlock ? 0.14 : 0.09)
                context.fill(Path(rect), with: .color(fillColor))
            }

            // 3. Active Trap Lifecycle Lines (Trigger / Active / Returned)
            for trap in overlays.traps where trap.isActionable {
                guard trap.level >= lowBound && trap.level <= highBound else { continue }
                let y = yFor(trap.level)
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(
                    line,
                    with: .color(palette.chart.trap.color.opacity(0.85)),
                    style: StrokeStyle(lineWidth: 1.0, dash: [4, 3])
                )
            }

            // 4. Trade Levels (Entry Band, Stop loss, Target 1, Target 2)
            if let lv = levels {
                let entryTop = yFor(lv.entryHigh)
                let entryBot = yFor(lv.entryLow)
                let entryRect = CGRect(x: 0, y: min(entryTop, entryBot), width: size.width, height: max(2, abs(entryBot - entryTop)))
                context.fill(Path(entryRect), with: .color(palette.chart.entry.color.opacity(0.18)))

                drawLevelLine(context: context, width: size.width, y: yFor(lv.stopLoss), color: palette.chart.stopLoss.color.opacity(0.85), dash: [3, 3])
                drawLevelLine(context: context, width: size.width, y: yFor(lv.tp1), color: palette.chart.tp1.color.opacity(0.85), dash: [4, 2])
                if lv.isTP2Enabled && lv.tp2 >= lowBound && lv.tp2 <= highBound {
                    drawLevelLine(context: context, width: size.width, y: yFor(lv.tp2), color: palette.chart.tp2.color.opacity(0.85), dash: [2, 3])
                }
            }

            // 5. Candlesticks (+ optional display-only live tick marker)
            let hasLive = livePrice != nil && (livePrice ?? 0) > 0
            let totalSlots = slice.count + (hasLive ? 1 : 0)
            let stepX = size.width / CGFloat(max(totalSlots, 1))
            let bodyWidth = max(2.0, stepX * 0.62)

            for (i, bar) in slice.enumerated() {
                let cx = (CGFloat(i) + 0.5) * stepX
                let color = bar.isBullish ? palette.longEmerald : palette.shortCrimson

                var wick = Path()
                wick.move(to: CGPoint(x: cx, y: yFor(bar.high)))
                wick.addLine(to: CGPoint(x: cx, y: yFor(bar.low)))
                context.stroke(wick, with: .color(color.opacity(0.9)), lineWidth: 1.0)

                let oY = yFor(bar.open)
                let cY = yFor(bar.close)
                let bodyRect = CGRect(
                    x: cx - bodyWidth * 0.5,
                    y: min(oY, cY),
                    width: bodyWidth,
                    height: max(1.5, abs(cY - oY))
                )
                context.fill(Path(bodyRect), with: .color(color))
            }

            if let lp = livePrice, lp.isFinite, lp > 0, lp >= lowBound, lp <= highBound {
                let isUp = lp >= refClose
                let liveColor = isUp ? palette.longEmerald : palette.shortCrimson
                let y = yFor(lp)
                drawLevelLine(context: context, width: size.width, y: y, color: liveColor.opacity(0.75), dash: [2, 2])

                let cx = (CGFloat(slice.count) + 0.5) * stepX
                let oY = yFor(refClose)
                let liveRect = CGRect(
                    x: cx - bodyWidth * 0.5,
                    y: min(oY, y),
                    width: bodyWidth,
                    height: max(2.0, abs(y - oY))
                )
                context.fill(Path(liveRect), with: .color(liveColor.opacity(0.85)))
            }
        }
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.canvas.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(palette.border.opacity(0.75), lineWidth: 0.5)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let count = min(candles.count, 36)
        let lastClose = candles.last.map { String(format: "%.2f", $0.close) } ?? "unavailable"
        return "Mini candlestick chart showing \(count) recent closed bars, last close \(lastClose). Double tap to open full interactive chart."
    }

    private func drawLevelLine(context: GraphicsContext, width: CGFloat, y: CGFloat, color: Color, dash: [CGFloat]) {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: width, y: y))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.0, dash: dash))
    }
}
