import SwiftUI
import UIKit
import SignalEngine

/// High-performance 120Hz Interactive Metal-backed SwiftUI `Canvas` candlestick engine:
/// - Smooth horizontal `DragGesture` panning with start-offset tracking + deceleration inertia.
/// - Safe `MagnificationGesture` pinch-zoom (`visibleCount` clamped `15...220`, resetting `lastMagnification = 1.0` in `.onEnded`).
/// - Preserves `trailingOffset` across live tick updates (zero snap-back while inspecting history).
/// - O(visible) slice math, auto-scaling Y-axis, formatted X-axis timestamps, right-axis precision pills,
///   tap/long-press crosshair readout with subtle haptic tick, Entry/SL/TP/Trap/Confirmed Wall lines,
///   optional multi-pane Volume + MA overlay, and a 1-tap Liquid Glass "Latest" snap button.
public struct NativeCanvasFallbackChartView: View {
    let candles: [Candle]
    let formingCandle: Candle?
    let overlayModel: ChartSignalOverlayModel
    let timeframe: Timeframe
    let pricePrecision: ChartPricePrecision
    let palette: ConfluencePalette
    let showVolumePane: Bool
    let showMovingAverages: Bool
    let onCrosshairChange: (ChartCrosshairReadout?) -> Void

    @State private var visibleCount: Double = 70.0
    @State private var trailingOffset: Double = 0.0
    @State private var dragStartOffset: Double? = nil
    @State private var lastMagnification: CGFloat = 1.0
    @State private var inspectedVisibleIndex: Int? = nil
    @State private var isCrosshairActive: Bool = false

    private static let minVisibleBars: Double = 15.0
    private static let maxVisibleBars: Double = 220.0

    public init(
        candles: [Candle],
        formingCandle: Candle?,
        overlayModel: ChartSignalOverlayModel,
        timeframe: Timeframe = .h1,
        pricePrecision: ChartPricePrecision,
        palette: ConfluencePalette,
        showVolumePane: Bool = false,
        showMovingAverages: Bool = false,
        onCrosshairChange: @escaping (ChartCrosshairReadout?) -> Void
    ) {
        self.candles = candles
        self.formingCandle = formingCandle
        self.overlayModel = overlayModel
        self.timeframe = timeframe
        self.pricePrecision = pricePrecision
        self.palette = palette
        self.showVolumePane = showVolumePane
        self.showMovingAverages = showMovingAverages
        self.onCrosshairChange = onCrosshairChange
    }

    private var allBars: [Candle] {
        var bars = candles
        if let forming = formingCandle {
            if let last = bars.last, abs(last.openTimeEpochSeconds - forming.openTimeEpochSeconds) < 1.0 {
                bars[bars.count - 1] = forming
            } else if (bars.last?.openTimeEpochSeconds ?? -1) < forming.openTimeEpochSeconds {
                bars.append(forming)
            }
        }
        return bars
    }

    private func clampedTrailingOffset(for totalCount: Int, visible: Int) -> Int {
        let maxOffset = max(0, totalCount - max(1, visible))
        return max(0, min(maxOffset, Int(trailingOffset.rounded())))
    }

    private func formatXAxisTimestamp(_ epoch: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: epoch)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = (timeframe == .d1) ? "MMM d" : "MM/dd HH:mm"
        return f.string(from: date)
    }

    public var body: some View {
        let bars = allBars
        let total = bars.count
        let visInt = max(Int(Self.minVisibleBars), min(Int(Self.maxVisibleBars), Int(visibleCount.rounded())))
        let clampedOffset = clampedTrailingOffset(for: total, visible: visInt)
        let endIdx = max(0, total - clampedOffset)
        let startIdx = max(0, endIdx - visInt)
        let visibleSlice = (startIdx < endIdx) ? Array(bars[startIdx..<endIdx]) : []

        GeometryReader { geo in
            let axisWidth = CGFloat(min(max(pricePrecision.minimumPriceScaleWidth, 70.0), 98.0))
            let xAxisHeight: CGFloat = 22.0
            let plotWidth = max(40.0, geo.size.width - axisWidth)
            let totalPlotHeight = max(60.0, geo.size.height - xAxisHeight)
            let volumeHeight: CGFloat = showVolumePane ? min(56.0, totalPlotHeight * 0.22) : 0.0
            let pricePlotHeight = max(40.0, totalPlotHeight - volumeHeight)

            ZStack(alignment: .bottomTrailing) {
                Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: false) { context, size in
                    guard !visibleSlice.isEmpty else { return }

                    var minPrice = Double.greatestFiniteMagnitude
                    var maxPrice = -Double.greatestFiniteMagnitude
                    var maxVolume = 0.0
                    for bar in visibleSlice {
                        if bar.low < minPrice { minPrice = bar.low }
                        if bar.high > maxPrice { maxPrice = bar.high }
                        if let v = bar.volume, v.isFinite, v > maxVolume { maxVolume = v }
                    }
                    let refClose = visibleSlice.last?.close ?? ((minPrice + maxPrice) * 0.5)

                    func includeIfNear(_ p: Double?) {
                        guard let p, p.isFinite, p > 0, refClose > 0 else { return }
                        if abs(p - refClose) / refClose <= 0.22 {
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
                    if let of = overlayModel.orderFlowSummary {
                        if of.bidWallConfirmed { includeIfNear(of.bidWallPrice) }
                        if of.askWallConfirmed { includeIfNear(of.askWallPrice) }
                    }

                    let span = max(maxPrice - minPrice, max(refClose * 0.002, Double.leastNormalMagnitude))
                    let pad = span * 0.10
                    let lowBound = max(Double.leastNormalMagnitude, minPrice - pad)
                    let highBound = max(lowBound + Double.leastNormalMagnitude, maxPrice + pad)
                    let totalRange = highBound - lowBound

                    func yFor(_ price: Double) -> CGFloat {
                        let norm = (price - lowBound) / totalRange
                        return pricePlotHeight * (1.0 - CGFloat(norm))
                    }

                    // 1. Horizontal grid + right-axis price ticks
                    for frac in [0.12, 0.36, 0.62, 0.86] {
                        let y = pricePlotHeight * CGFloat(frac)
                        var grid = Path()
                        grid.move(to: CGPoint(x: 0, y: y))
                        grid.addLine(to: CGPoint(x: plotWidth, y: y))
                        context.stroke(grid, with: .color(palette.border.opacity(0.42)), lineWidth: 0.5)

                        let tickPrice = highBound - Double(frac) * totalRange
                        let tickText = Text(pricePrecision.format(tickPrice))
                            .font(.system(size: 9, weight: .medium).monospacedDigit())
                            .foregroundStyle(palette.tertiaryInk)
                        context.draw(tickText, at: CGPoint(x: plotWidth + 5, y: y), anchor: .leading)
                    }

                    // 2. Vertical X-axis timestamps & divider lines
                    let stepX = plotWidth / CGFloat(max(visibleSlice.count, 1))
                    let tickStep = max(1, visibleSlice.count / 4)
                    for idx in stride(from: 0, to: visibleSlice.count, by: tickStep) {
                        let cx = (CGFloat(idx) + 0.5) * stepX
                        var vGrid = Path()
                        vGrid.move(to: CGPoint(x: cx, y: 0))
                        vGrid.addLine(to: CGPoint(x: cx, y: totalPlotHeight))
                        context.stroke(vGrid, with: .color(palette.border.opacity(0.24)), lineWidth: 0.5)

                        let label = formatXAxisTimestamp(visibleSlice[idx].openTimeEpochSeconds)
                        let xText = Text(label)
                            .font(.system(size: 8.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(palette.tertiaryInk)
                        context.draw(xText, at: CGPoint(x: min(plotWidth - 26, max(24, cx)), y: totalPlotHeight + 11), anchor: .center)
                    }

                    // Right-axis & X-axis border dividers
                    var axisDivider = Path()
                    axisDivider.move(to: CGPoint(x: plotWidth, y: 0))
                    axisDivider.addLine(to: CGPoint(x: plotWidth, y: totalPlotHeight))
                    axisDivider.move(to: CGPoint(x: 0, y: totalPlotHeight))
                    axisDivider.addLine(to: CGPoint(x: size.width, y: totalPlotHeight))
                    if showVolumePane {
                        axisDivider.move(to: CGPoint(x: 0, y: pricePlotHeight))
                        axisDivider.addLine(to: CGPoint(x: plotWidth, y: pricePlotHeight))
                    }
                    context.stroke(axisDivider, with: .color(palette.border.opacity(0.75)), lineWidth: 0.75)

                    // 3. FVG / OB Zones
                    for zone in overlayModel.zones.prefix(3) {
                        let yTop = max(0, min(pricePlotHeight, yFor(zone.top)))
                        let yBot = max(0, min(pricePlotHeight, yFor(zone.bottom)))
                        let rect = CGRect(x: 0, y: min(yTop, yBot), width: plotWidth, height: max(2, abs(yBot - yTop)))
                        let fillColor: Color = (zone.direction == .long ? palette.longEmerald : palette.shortCrimson)
                            .opacity(zone.kind == .orderBlock ? 0.14 : 0.08)
                        context.fill(Path(rect), with: .color(fillColor))
                    }

                    // 4. Optional Moving Averages (EMA 20 / 50 approximation over visible window)
                    if showMovingAverages && visibleSlice.count >= 10 {
                        func drawSMA(period: Int, color: Color) {
                            var path = Path()
                            var started = false
                            for i in 0..<visibleSlice.count {
                                let lo = max(0, i - period + 1)
                                var sum = 0.0
                                for j in lo...i { sum += visibleSlice[j].close }
                                let avg = sum / Double(i - lo + 1)
                                let pt = CGPoint(x: (CGFloat(i) + 0.5) * stepX, y: yFor(avg))
                                if !started {
                                    path.move(to: pt)
                                    started = true
                                } else {
                                    path.addLine(to: pt)
                                }
                            }
                            context.stroke(path, with: .color(color.opacity(0.85)), lineWidth: 1.15)
                        }
                        drawSMA(period: 9, color: palette.champagneGold)
                        drawSMA(period: 21, color: palette.macroIceBlue)
                    }

                    // 5. Signal & Confirmed Crypto Wall Price Lines with Right-Axis Pills
                    func drawLevel(_ price: Double?, label: String, color: Color, dash: [CGFloat]) {
                        guard let price, price.isFinite, price >= lowBound, price <= highBound else { return }
                        let y = yFor(price)
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: plotWidth, y: y))
                        context.stroke(path, with: .color(color.opacity(0.9)), style: StrokeStyle(lineWidth: 1.1, dash: dash))

                        let tagRect = CGRect(x: plotWidth + 2, y: max(2, min(pricePlotHeight - 16, y - 7)), width: axisWidth - 4, height: 14)
                        context.fill(Path(roundedRect: tagRect, cornerRadius: 3), with: .color(color))
                        let tagText = Text("\(label) \(pricePrecision.format(price))")
                            .font(.system(size: 7.5, weight: .bold).monospacedDigit())
                            .foregroundStyle(.white)
                        context.draw(tagText, at: CGPoint(x: tagRect.midX, y: tagRect.midY), anchor: .center)
                    }

                    drawLevel(overlayModel.trapPrice, label: "TRAP", color: palette.trapAmber, dash: [4, 3])
                    if overlayModel.marketClass == .crypto, let of = overlayModel.orderFlowSummary {
                        if of.bidWallConfirmed {
                            drawLevel(of.bidWallPrice, label: "BWALL", color: palette.longEmerald.opacity(0.85), dash: [2, 3])
                        }
                        if of.askWallConfirmed {
                            drawLevel(of.askWallPrice, label: "AWALL", color: palette.shortCrimson.opacity(0.85), dash: [2, 3])
                        }
                    }
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

                    // 6. Candlesticks & Optional Volume Pane
                    let bodyWidth = max(2.0, min(14.0, stepX * 0.68))
                    for (idx, bar) in visibleSlice.enumerated() {
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

                        if showVolumePane, maxVolume > 0, let vol = bar.volume, vol.isFinite, vol > 0 {
                            let vFrac = CGFloat(min(1.0, vol / maxVolume))
                            let barH = max(1.5, vFrac * (volumeHeight - 6.0))
                            let vRect = CGRect(
                                x: cx - bodyWidth * 0.5,
                                y: totalPlotHeight - barH - 2.0,
                                width: bodyWidth,
                                height: barH
                            )
                            context.fill(Path(vRect), with: .color(color.opacity(0.38)))
                        }
                    }

                    // 7. Interactive Crosshair Guide
                    if let idx = inspectedVisibleIndex, idx >= 0, idx < visibleSlice.count {
                        let bar = visibleSlice[idx]
                        let cx = (CGFloat(idx) + 0.5) * stepX
                        let cy = yFor(bar.close)
                        var vLine = Path()
                        vLine.move(to: CGPoint(x: cx, y: 0))
                        vLine.addLine(to: CGPoint(x: cx, y: totalPlotHeight))
                        context.stroke(vLine, with: .color(palette.secondaryInk.opacity(0.7)), style: StrokeStyle(lineWidth: 0.75, dash: [3, 3]))

                        var hLine = Path()
                        hLine.move(to: CGPoint(x: 0, y: cy))
                        hLine.addLine(to: CGPoint(x: plotWidth, y: cy))
                        context.stroke(hLine, with: .color(palette.secondaryInk.opacity(0.7)), style: StrokeStyle(lineWidth: 0.75, dash: [3, 3]))
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            guard !visibleSlice.isEmpty else { return }
                            if isCrosshairActive {
                                updateCrosshair(atX: value.location.x, plotWidth: plotWidth, visibleSlice: visibleSlice)
                                return
                            }
                            if dragStartOffset == nil {
                                dragStartOffset = trailingOffset
                            }
                            let barsPerPt = Double(visInt) / Double(max(plotWidth, 1.0))
                            let deltaBars = Double(value.translation.width) * barsPerPt
                            let maxOff = Double(max(0, total - visInt))
                            let proposed = (dragStartOffset ?? trailingOffset) + deltaBars
                            trailingOffset = max(0.0, min(maxOff, proposed))
                        }
                        .onEnded { value in
                            if isCrosshairActive {
                                isCrosshairActive = false
                                inspectedVisibleIndex = nil
                                onCrosshairChange(nil)
                                return
                            }
                            let barsPerPt = Double(visInt) / Double(max(plotWidth, 1.0))
                            let predictedDelta = Double(value.predictedEndTranslation.width - value.translation.width) * barsPerPt * 0.45
                            let maxOff = Double(max(0, total - visInt))
                            let target = max(0.0, min(maxOff, trailingOffset + predictedDelta))
                            dragStartOffset = nil
                            withAnimation(.easeOut(duration: 0.28)) {
                                trailingOffset = target
                            }
                        }
                )
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            guard value.isFinite, value > 0 else { return }
                            let delta = value / max(lastMagnification, 0.01)
                            lastMagnification = value
                            let proposed = visibleCount / Double(delta)
                            visibleCount = max(Self.minVisibleBars, min(Self.maxVisibleBars, proposed))
                        }
                        .onEnded { _ in
                            // CRITICAL: Reset lastMagnification to 1.0 so pinch zoom never compounds/explodes
                            lastMagnification = 1.0
                        }
                )
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.25)
                        .onEnded { _ in
                            isCrosshairActive = true
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                )
                .onTapGesture { location in
                    guard !visibleSlice.isEmpty else { return }
                    if isCrosshairActive || inspectedVisibleIndex != nil {
                        isCrosshairActive = false
                        inspectedVisibleIndex = nil
                        onCrosshairChange(nil)
                    } else {
                        updateCrosshair(atX: location.x, plotWidth: plotWidth, visibleSlice: visibleSlice)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }

                // 1-tap Liquid Glass "Latest" snap button whenever panned left into history
                if clampedOffset > 0 {
                    Button {
                        withAnimation(.easeOut(duration: 0.24)) {
                            trailingOffset = 0.0
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Latest")
                                .font(.caption2.weight(.bold))
                            Image(systemName: "arrow.right.to.line")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(palette.primaryInk)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .confluenceLiquidGlass(cornerRadius: 14, borderColor: palette.champagneGold.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, axisWidth + 10)
                    .padding(.bottom, xAxisHeight + 10)
                }
            }
        }
        .background(palette.canvas)
        .onChange(of: overlayModel.symbol) { _, _ in
            trailingOffset = 0.0
            inspectedVisibleIndex = nil
            isCrosshairActive = false
            onCrosshairChange(nil)
        }
        .onChange(of: timeframe) { _, _ in
            trailingOffset = 0.0
            inspectedVisibleIndex = nil
            isCrosshairActive = false
            onCrosshairChange(nil)
        }
    }

    private func updateCrosshair(atX x: CGFloat, plotWidth: CGFloat, visibleSlice: [Candle]) {
        guard !visibleSlice.isEmpty else { return }
        let clampedX = max(0, min(plotWidth - 1, x))
        let idx = min(visibleSlice.count - 1, max(0, Int((clampedX / plotWidth) * CGFloat(visibleSlice.count))))
        if inspectedVisibleIndex != idx {
            inspectedVisibleIndex = idx
            let bar = visibleSlice[idx]
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
}
