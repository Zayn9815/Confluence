import SwiftUI
import SignalEngine

/// High-performance native SwiftUI `Canvas` candlestick chart used as the Step-1 visual backing
/// for Step-2 chart engine adapter slots (`DGCharts`, `SwiftTradingView`, `CandleKit`).
/// Supports live forming candle rendering, Entry/SL/TP1/TP2/Trap price lines with right-axis tags,
/// and drag-to-inspect crosshair callbacks.
public struct NativeCanvasFallbackChartView: View {
    let candles: [Candle]
    let formingCandle: Candle?
    let overlayModel: ChartSignalOverlayModel
    let pricePrecision: ChartPricePrecision
    let palette: ConfluencePalette
    let onCrosshairChange: (ChartCrosshairReadout?) -> Void

    @State private var inspectedIndex: Int? = nil

    public init(
        candles: [Candle],
        formingCandle: Candle?,
        overlayModel: ChartSignalOverlayModel,
        pricePrecision: ChartPricePrecision,
        palette: ConfluencePalette,
        onCrosshairChange: @escaping (ChartCrosshairReadout?) -> Void
    ) {
        self.candles = candles
        self.formingCandle = formingCandle
        self.overlayModel = overlayModel
        self.pricePrecision = pricePrecision
        self.palette = palette
        self.onCrosshairChange = onCrosshairChange
    }

    private var visibleBars: [Candle] {
        var bars = Array(candles.suffix(80))
        if let forming = formingCandle {
            if let last = bars.last, abs(last.openTimeEpochSeconds - forming.openTimeEpochSeconds) < 1.0 {
                bars[bars.count - 1] = forming
            } else if (bars.last?.openTimeEpochSeconds ?? -1) < forming.openTimeEpochSeconds {
                bars.append(forming)
            }
        }
        return bars
    }

    public var body: some View {
        let bars = visibleBars
        GeometryReader { geo in
            let axisWidth = CGFloat(min(max(pricePrecision.minimumPriceScaleWidth, 68.0), 96.0))
            let plotWidth = max(40, geo.size.width - axisWidth)

            Canvas { context, size in
                guard !bars.isEmpty else { return }

                var minPrice = bars.map(\.low).min() ?? 0
                var maxPrice = bars.map(\.high).max() ?? 1
                let refClose = bars.last?.close ?? ((minPrice + maxPrice) * 0.5)

                func includeIfNear(_ p: Double?) {
                    guard let p, p.isFinite, p > 0, refClose > 0 else { return }
                    if abs(p - refClose) / refClose <= 0.25 {
                        minPrice = min(minPrice, p)
                        maxPrice = max(maxPrice, p)
                    }
                }

                includeIfNear(overlayModel.entryPrice)
                includeIfNear(overlayModel.stopLoss)
                includeIfNear(overlayModel.takeProfit1)
                if overlayModel.isTP2Enabled { includeIfNear(overlayModel.takeProfit2) }
                includeIfNear(overlayModel.trapPrice)
                includeIfNear(overlayModel.livePrice)

                let span = max(maxPrice - minPrice, max(refClose * 0.002, Double.leastNormalMagnitude))
                let pad = span * 0.10
                let lowBound = max(Double.leastNormalMagnitude, minPrice - pad)
                let highBound = max(lowBound + Double.leastNormalMagnitude, maxPrice + pad)
                let totalRange = highBound - lowBound

                func yFor(_ price: Double) -> CGFloat {
                    let norm = (price - lowBound) / totalRange
                    return size.height * (1.0 - CGFloat(norm))
                }

                // 1. Subtle horizontal grid + right-axis price ticks
                for frac in [0.15, 0.38, 0.62, 0.85] {
                    let y = size.height * CGFloat(frac)
                    var grid = Path()
                    grid.move(to: CGPoint(x: 0, y: y))
                    grid.addLine(to: CGPoint(x: plotWidth, y: y))
                    context.stroke(grid, with: .color(palette.border.opacity(0.45)), lineWidth: 0.5)

                    let tickPrice = highBound - Double(frac) * totalRange
                    let tickText = Text(pricePrecision.format(tickPrice))
                        .font(.system(size: 9, weight: .medium).monospacedDigit())
                        .foregroundStyle(palette.tertiaryInk)
                    context.draw(tickText, at: CGPoint(x: plotWidth + 6, y: y), anchor: .leading)
                }

                // 2. Right-axis divider
                var axisDivider = Path()
                axisDivider.move(to: CGPoint(x: plotWidth, y: 0))
                axisDivider.addLine(to: CGPoint(x: plotWidth, y: size.height))
                context.stroke(axisDivider, with: .color(palette.border.opacity(0.75)), lineWidth: 0.75)

                // 3. FVG / OB Zones
                for zone in overlayModel.zones.prefix(3) {
                    let yTop = yFor(zone.top)
                    let yBot = yFor(zone.bottom)
                    let rect = CGRect(x: 0, y: min(yTop, yBot), width: plotWidth, height: max(2, abs(yBot - yTop)))
                    let fillColor: Color = (zone.direction == .long ? palette.longEmerald : palette.shortCrimson).opacity(zone.kind == .orderBlock ? 0.14 : 0.08)
                    context.fill(Path(rect), with: .color(fillColor))
                }

                // 4. Signal Price Lines (Entry, SL, TP1, TP2, Trap, Live)
                func drawLevel(_ price: Double?, label: String, color: Color, dash: [CGFloat]) {
                    guard let price, price.isFinite, price >= lowBound, price <= highBound else { return }
                    let y = yFor(price)
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: plotWidth, y: y))
                    context.stroke(path, with: .color(color.opacity(0.9)), style: StrokeStyle(lineWidth: 1.1, dash: dash))

                    let tagRect = CGRect(x: plotWidth + 2, y: max(2, min(size.height - 16, y - 7)), width: axisWidth - 4, height: 14)
                    context.fill(Path(roundedRect: tagRect, cornerRadius: 3), with: .color(color))
                    let tagText = Text("\(label) \(pricePrecision.format(price))")
                        .font(.system(size: 8, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                    context.draw(tagText, at: CGPoint(x: tagRect.midX, y: tagRect.midY), anchor: .center)
                }

                drawLevel(overlayModel.trapPrice, label: "TRAP", color: palette.trapAmber, dash: [4, 3])
                drawLevel(overlayModel.entryPrice, label: "E", color: palette.champagneGold, dash: [5, 3])
                drawLevel(overlayModel.stopLoss, label: "SL", color: palette.shortCrimson, dash: [])
                drawLevel(overlayModel.takeProfit1, label: "T1", color: palette.longEmerald, dash: [])
                if overlayModel.isTP2Enabled {
                    drawLevel(overlayModel.takeProfit2, label: "T2", color: palette.macroIceBlue, dash: [3, 3])
                }
                if let lp = overlayModel.livePrice {
                    let liveColor = lp >= refClose ? palette.longEmerald : palette.shortCrimson
                    drawLevel(lp, label: "LIVE", color: liveColor, dash: [2, 2])
                }

                // 5. Candlesticks
                let stepX = plotWidth / CGFloat(max(bars.count, 1))
                let bodyWidth = max(2.0, min(10.0, stepX * 0.65))
                for (idx, bar) in bars.enumerated() {
                    let cx = (CGFloat(idx) + 0.5) * stepX
                    let color = bar.isBullish ? palette.longEmerald : palette.shortCrimson
                    var wick = Path()
                    wick.move(to: CGPoint(x: cx, y: yFor(bar.high)))
                    wick.addLine(to: CGPoint(x: cx, y: yFor(bar.low)))
                    context.stroke(wick, with: .color(color.opacity(0.95)), lineWidth: 1.0)

                    let oY = yFor(bar.open)
                    let cY = yFor(bar.close)
                    let bodyRect = CGRect(
                        x: cx - bodyWidth * 0.5,
                        y: min(oY, cY),
                        width: bodyWidth,
                        height: max(1.5, abs(cY - oY))
                    )
                    context.fill(Path(bodyRect), with: .color(bar.isClosed ? color : color.opacity(0.75)))
                }

                // 6. Crosshair guide line when dragging
                if let idx = inspectedIndex, idx >= 0, idx < bars.count {
                    let bar = bars[idx]
                    let cx = (CGFloat(idx) + 0.5) * stepX
                    let cy = yFor(bar.close)
                    var vLine = Path()
                    vLine.move(to: CGPoint(x: cx, y: 0))
                    vLine.addLine(to: CGPoint(x: cx, y: size.height))
                    context.stroke(vLine, with: .color(palette.secondaryInk.opacity(0.6)), style: StrokeStyle(lineWidth: 0.75, dash: [3, 3]))

                    var hLine = Path()
                    hLine.move(to: CGPoint(x: 0, y: cy))
                    hLine.addLine(to: CGPoint(x: plotWidth, y: cy))
                    context.stroke(hLine, with: .color(palette.secondaryInk.opacity(0.6)), style: StrokeStyle(lineWidth: 0.75, dash: [3, 3]))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !bars.isEmpty else { return }
                        let clampedX = max(0, min(plotWidth - 1, value.location.x))
                        let idx = min(bars.count - 1, max(0, Int((clampedX / plotWidth) * CGFloat(bars.count))))
                        if inspectedIndex != idx {
                            inspectedIndex = idx
                            let bar = bars[idx]
                            onCrosshairChange(ChartCrosshairReadout(
                                epochSeconds: bar.openTimeEpochSeconds,
                                open: bar.open,
                                high: bar.high,
                                low: bar.low,
                                close: bar.close,
                                isForming: !bar.isClosed
                            ))
                        }
                    }
                    .onEnded { _ in
                        inspectedIndex = nil
                        onCrosshairChange(nil)
                    }
            )
        }
        .background(palette.canvas)
    }
}
