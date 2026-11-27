import SwiftUI
import UIKit
import QuartzCore
import SignalEngine

// MARK: - Self-Stopping CADisplayLink Pan Inertia Controller

@MainActor
private final class WeakDisplayLinkProxy: NSObject {
    weak var owner: SwiftTVInertiaController?

    init(owner: SwiftTVInertiaController) {
        self.owner = owner
    }

    @objc func handleTick(_ link: CADisplayLink) {
        owner?.tick(link)
    }
}

@MainActor
private final class SwiftTVInertiaController {
    private var displayLink: CADisplayLink?
    private var velocityBarsPerSecond: Double = 0
    private var lastTimestamp: CFTimeInterval = 0
    private var onStep: ((Double) -> Bool)?

    func start(velocityBarsPerSecond: Double, onStep: @escaping (Double) -> Bool) {
        stop()
        guard velocityBarsPerSecond.isFinite, abs(velocityBarsPerSecond) >= 0.4 else { return }
        self.velocityBarsPerSecond = velocityBarsPerSecond
        self.lastTimestamp = 0
        self.onStep = onStep

        let proxy = WeakDisplayLinkProxy(owner: self)
        let link = CADisplayLink(target: proxy, selector: #selector(WeakDisplayLinkProxy.handleTick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        velocityBarsPerSecond = 0
        lastTimestamp = 0
        onStep = nil
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt: Double
        if lastTimestamp == 0 {
            dt = 1.0 / 60.0
        } else {
            dt = min(0.05, max(0.001, now - lastTimestamp))
        }
        lastTimestamp = now

        let deltaBars = velocityBarsPerSecond * dt
        // Exponential deceleration tuned for 60Hz/120Hz OLED scrolling
        velocityBarsPerSecond *= pow(0.04, dt)

        let shouldContinue = onStep?(deltaBars) ?? false
        if !shouldContinue || abs(velocityBarsPerSecond) < 0.15 {
            stop()
        }
    }
}

// MARK: - Precomputed Multi-Pane Frame Data

private struct PreparedMultiPaneSlice {
    let visibleBars: [Candle]
    let ma20: [Double?]
    let ma50: [Double?]
    let volMA5: [Double?]
    let volMA10: [Double?]
    let maxVolume: Double
    let minPrice: Double
    let maxPrice: Double

    static func build(
        allBars: [Candle],
        startIndex: Int,
        endIndex: Int
    ) -> PreparedMultiPaneSlice {
        guard startIndex < endIndex, startIndex >= 0, endIndex <= allBars.count else {
            return PreparedMultiPaneSlice(
                visibleBars: [],
                ma20: [],
                ma50: [],
                volMA5: [],
                volMA10: [],
                maxVolume: 0,
                minPrice: 0,
                maxPrice: 1
            )
        }

        let count = endIndex - startIndex
        let visible = Array(allBars[startIndex..<endIndex])

        func sliceSMA(period: Int, valueAt: (Candle) -> Double) -> [Double?] {
            var out = [Double?](repeating: nil, count: count)
            let prefixStart = max(0, startIndex - period + 1)
            var runningSum = 0.0
            var windowCount = 0
            for idx in prefixStart..<endIndex {
                runningSum += valueAt(allBars[idx])
                windowCount += 1
                if windowCount > period {
                    runningSum -= valueAt(allBars[idx - period])
                    windowCount -= 1
                }
                if idx >= startIndex && windowCount >= min(period, 3) {
                    out[idx - startIndex] = runningSum / Double(windowCount)
                }
            }
            return out
        }

        let ma20 = sliceSMA(period: 20, valueAt: \.close)
        let ma50 = sliceSMA(period: 50, valueAt: \.close)
        let volMA5 = sliceSMA(period: 5) { max(0.0, $0.volume ?? 0.0) }
        let volMA10 = sliceSMA(period: 10) { max(0.0, $0.volume ?? 0.0) }

        var minP = Double.greatestFiniteMagnitude
        var maxP = -Double.greatestFiniteMagnitude
        var maxVol = 0.0
        for bar in visible {
            if bar.low.isFinite && bar.low < minP { minP = bar.low }
            if bar.high.isFinite && bar.high > maxP { maxP = bar.high }
            if let v = bar.volume, v.isFinite, v > maxVol { maxVol = v }
        }
        if !minP.isFinite || !maxP.isFinite {
            minP = 0
            maxP = 1
        }
        return PreparedMultiPaneSlice(
            visibleBars: visible,
            ma20: ma20,
            ma50: ma50,
            volMA5: volMA5,
            volMA10: volMA10,
            maxVolume: maxVol,
            minPrice: minP,
            maxPrice: maxP
        )
    }
}

/// Native Multi-Pane SwiftUI `Canvas` financial chart (zero external third-party SwiftTradingView package).
/// - Top pane (75%): Candlesticks + MA(20) gold / MA(50) slate + right-axis colored pills for Entry, SL, TP1, TP2 (emerald), Traps, and Confirmed Walls.
/// - Bottom pane (25%): Volume bars + Vol MA(5) & Vol MA(10).
/// - Smooth `DragGesture` pan + self-stopping `CADisplayLink` inertia, `MagnifyGesture` pinch-zoom,
///   and trailing 68pt price-axis drag-to-scale (`0.25x...4.0x`) + double-tap / `resetTrigger` restore.
public struct SwiftTradingViewAdapterView: ConfluenceChartAdapter {
    public let candles: [Candle]
    public let formingCandle: Candle?
    public let overlayModel: ChartSignalOverlayModel
    public let replayMarkers: [ChartReplayMarker]
    public let timeframe: Timeframe
    public let pricePrecision: ChartPricePrecision
    public let palette: ConfluencePalette
    public let isDark: Bool
    public let resetTrigger: Int
    public let onCrosshairChange: (ChartCrosshairReadout?) -> Void

    @State private var visibleCount: Double = 60.0
    @State private var trailingOffset: Double = 0.0
    @State private var dragStartOffset: Double? = nil
    @State private var pinchStartVisibleCount: Double? = nil
    @State private var yScaleMultiplier: Double = 1.0
    @State private var dragStartYScale: Double? = nil
    @State private var inspectedVisibleIndex: Int? = nil
    @State private var isCrosshairActive: Bool = false
    @State private var inertia = SwiftTVInertiaController()

    private static let minVisibleBars: Double = 15.0
    private static let maxVisibleBars: Double = 200.0

    private static let dailyAxisStyle = Date.VerbatimFormatStyle(
        format: "\(month: .abbreviated) \(day: .defaultDigits)",
        locale: Locale(identifier: "en_US_POSIX"),
        timeZone: TimeZone(secondsFromGMT: 0) ?? .gmt,
        calendar: Calendar(identifier: .gregorian)
    )
    private static let intradayAxisStyle = Date.VerbatimFormatStyle(
        format: "\(month: .twoDigits)/\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
        locale: Locale(identifier: "en_US_POSIX"),
        timeZone: TimeZone(secondsFromGMT: 0) ?? .gmt,
        calendar: Calendar(identifier: .gregorian)
    )

    public init(
        candles: [Candle],
        formingCandle: Candle?,
        overlayModel: ChartSignalOverlayModel,
        replayMarkers: [ChartReplayMarker] = [],
        timeframe: Timeframe,
        pricePrecision: ChartPricePrecision,
        palette: ConfluencePalette,
        isDark: Bool,
        resetTrigger: Int = 0,
        onCrosshairChange: @escaping (ChartCrosshairReadout?) -> Void
    ) {
        self.candles = candles
        self.formingCandle = formingCandle
        self.overlayModel = overlayModel
        self.replayMarkers = replayMarkers
        self.timeframe = timeframe
        self.pricePrecision = pricePrecision
        self.palette = palette
        self.isDark = isDark
        self.resetTrigger = resetTrigger
        self.onCrosshairChange = onCrosshairChange
    }

    private var allBars: [Candle] {
        var bars = candles.sorted { $0.openTimeEpochSeconds < $1.openTimeEpochSeconds }
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

    private func formatAxisTime(_ epoch: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: epoch)
        return (timeframe == .d1) ? Self.dailyAxisStyle.format(date) : Self.intradayAxisStyle.format(date)
    }

    public var body: some View {
        let bars = allBars
        let total = bars.count
        let visInt = max(Int(Self.minVisibleBars), min(Int(Self.maxVisibleBars), Int(visibleCount.rounded())))
        let clampedOffset = clampedTrailingOffset(for: total, visible: visInt)
        let endIdx = max(0, total - clampedOffset)
        let startIdx = max(0, endIdx - visInt)
        // Precompute visible slice + moving averages outside Canvas draw closure
        let prepared = PreparedMultiPaneSlice.build(allBars: bars, startIndex: startIdx, endIndex: endIdx)

        GeometryReader { geo in
            let axisWidth = CGFloat(min(max(pricePrecision.minimumPriceScaleWidth, 68.0), 94.0))
            let xAxisHeight: CGFloat = 22.0
            let plotWidth = max(40.0, geo.size.width - axisWidth)
            let totalPlotHeight = max(80.0, geo.size.height - xAxisHeight)
            let pricePlotHeight = totalPlotHeight * 0.75
            let volumeTop = pricePlotHeight
            let volumeHeight = max(24.0, totalPlotHeight - pricePlotHeight)

            ZStack(alignment: .trailing) {
                ZStack(alignment: .bottomTrailing) {
                    Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: false) { context, size in
                        let visibleSlice = prepared.visibleBars
                        guard !visibleSlice.isEmpty else { return }

                        let refClose = visibleSlice.last?.close ?? ((prepared.minPrice + prepared.maxPrice) * 0.5)
                        let midPrice = (prepared.minPrice + prepared.maxPrice) * 0.5
                        let rawSpan = prepared.maxPrice - prepared.minPrice
                        let flooredSpan = max(rawSpan, max(abs(midPrice) * 0.0005, 1e-9))
                        let paddedHalf = (flooredSpan * 0.5) * 1.18 * min(4.0, max(0.25, yScaleMultiplier))
                        let lowBound = midPrice - paddedHalf
                        let highBound = midPrice + paddedHalf
                        let totalRange = max(highBound - lowBound, 1e-9)

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
                            context.stroke(grid, with: .color(palette.border.opacity(0.45)), lineWidth: 0.5)

                            let tickPrice = highBound - Double(frac) * totalRange
                            let tickText = Text(pricePrecision.format(tickPrice))
                                .font(.system(size: 9, weight: .medium).monospacedDigit())
                                .foregroundStyle(palette.tertiaryInk)
                            context.draw(tickText, at: CGPoint(x: plotWidth + 5, y: y), anchor: .leading)
                        }

                        // 2. X-axis timestamps & vertical dividers (max 4 non-overlapping labels)
                        let stepX = plotWidth / CGFloat(max(visibleSlice.count, 1))
                        let tickStep = max(1, visibleSlice.count / 4)
                        for idx in stride(from: 0, to: visibleSlice.count, by: tickStep) {
                            let cx = (CGFloat(idx) + 0.5) * stepX
                            var vGrid = Path()
                            vGrid.move(to: CGPoint(x: cx, y: 0))
                            vGrid.addLine(to: CGPoint(x: cx, y: totalPlotHeight))
                            context.stroke(vGrid, with: .color(palette.border.opacity(0.24)), lineWidth: 0.5)

                            let label = formatAxisTime(visibleSlice[idx].openTimeEpochSeconds)
                            let xText = Text(label)
                                .font(.system(size: 8.5, weight: .medium).monospacedDigit())
                                .foregroundStyle(palette.tertiaryInk)
                            context.draw(xText, at: CGPoint(x: min(plotWidth - 28, max(28, cx)), y: totalPlotHeight + 11), anchor: .center)
                        }

                        // Pane & axis borders
                        var borders = Path()
                        borders.move(to: CGPoint(x: plotWidth, y: 0))
                        borders.addLine(to: CGPoint(x: plotWidth, y: totalPlotHeight))
                        borders.move(to: CGPoint(x: 0, y: pricePlotHeight))
                        borders.addLine(to: CGPoint(x: size.width, y: pricePlotHeight))
                        borders.move(to: CGPoint(x: 0, y: totalPlotHeight))
                        borders.addLine(to: CGPoint(x: size.width, y: totalPlotHeight))
                        context.stroke(borders, with: .color(palette.border.opacity(0.8)), lineWidth: 0.75)

                        // Volume pane label
                        let volLabel = Text("VOL · MA 5/10")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(palette.tertiaryInk)
                        context.draw(volLabel, at: CGPoint(x: 6, y: volumeTop + 8), anchor: .leading)

                        // 3. FVG / OB Zones
                        for zone in overlayModel.zones.prefix(3) {
                            let yTop = max(0, min(pricePlotHeight, yFor(zone.top)))
                            let yBot = max(0, min(pricePlotHeight, yFor(zone.bottom)))
                            let rect = CGRect(x: 0, y: min(yTop, yBot), width: plotWidth, height: max(2, abs(yBot - yTop)))
                            let fillColor: Color = (zone.direction == .long ? palette.longEmerald : palette.shortCrimson)
                                .opacity(zone.kind == .orderBlock ? 0.14 : 0.08)
                            context.fill(Path(rect), with: .color(fillColor))
                        }

                        // 4. Candlesticks (top pane) & Volume bars (bottom pane)
                        let bodyWidth = max(2.0, min(14.0, stepX * 0.66))
                        for (idx, bar) in visibleSlice.enumerated() {
                            let cx = (CGFloat(idx) + 0.5) * stepX
                            let color = bar.isBullish ? palette.longEmerald : palette.shortCrimson

                            let hiY = max(0, min(pricePlotHeight, yFor(bar.high)))
                            let loY = max(0, min(pricePlotHeight, yFor(bar.low)))
                            var wick = Path()
                            wick.move(to: CGPoint(x: cx, y: hiY))
                            wick.addLine(to: CGPoint(x: cx, y: loY))
                            context.stroke(wick, with: .color(color.opacity(0.95)), lineWidth: 1.0)

                            let oY = max(0, min(pricePlotHeight, yFor(bar.open)))
                            let cY = max(0, min(pricePlotHeight, yFor(bar.close)))
                            let bodyRect = CGRect(
                                x: cx - bodyWidth * 0.5,
                                y: min(oY, cY),
                                width: bodyWidth,
                                height: max(1.5, abs(cY - oY))
                            )
                            context.fill(Path(bodyRect), with: .color(bar.isClosed ? color : color.opacity(0.75)))

                            if prepared.maxVolume > 0, let vol = bar.volume, vol.isFinite, vol > 0 {
                                let usableVolH = max(4.0, volumeHeight - 16.0)
                                let barH = max(1.5, CGFloat(min(1.0, vol / prepared.maxVolume)) * usableVolH)
                                let vRect = CGRect(
                                    x: cx - bodyWidth * 0.5,
                                    y: totalPlotHeight - barH - 2.0,
                                    width: bodyWidth,
                                    height: barH
                                )
                                context.fill(Path(vRect), with: .color(color.opacity(0.36)))
                            }
                        }

                        // 5. Moving Averages (MA20 gold, MA50 muted slate) on top pane
                        func drawPriceCurve(_ values: [Double?], color: Color) {
                            var path = Path()
                            var started = false
                            for (i, val) in values.enumerated() {
                                guard let val, val.isFinite else { continue }
                                let y = yFor(val)
                                guard y >= -20, y <= pricePlotHeight + 20 else {
                                    started = false
                                    continue
                                }
                                let pt = CGPoint(x: (CGFloat(i) + 0.5) * stepX, y: max(0, min(pricePlotHeight, y)))
                                if !started {
                                    path.move(to: pt)
                                    started = true
                                } else {
                                    path.addLine(to: pt)
                                }
                            }
                            context.stroke(path, with: .color(color.opacity(0.88)), lineWidth: 1.2)
                        }
                        drawPriceCurve(prepared.ma20, color: palette.champagneGold)
                        drawPriceCurve(prepared.ma50, color: palette.macroIceBlue)

                        // 6. Volume MA(5) & MA(10) curves on bottom pane
                        if prepared.maxVolume > 0 {
                            let usableVolH = max(4.0, volumeHeight - 16.0)
                            func drawVolCurve(_ values: [Double?], color: Color) {
                                var path = Path()
                                var started = false
                                for (i, val) in values.enumerated() {
                                    guard let val, val.isFinite, val > 0 else { continue }
                                    let frac = CGFloat(min(1.0, val / prepared.maxVolume))
                                    let y = totalPlotHeight - (frac * usableVolH) - 2.0
                                    let pt = CGPoint(x: (CGFloat(i) + 0.5) * stepX, y: y)
                                    if !started {
                                        path.move(to: pt)
                                        started = true
                                    } else {
                                        path.addLine(to: pt)
                                    }
                                }
                                context.stroke(path, with: .color(color.opacity(0.85)), lineWidth: 1.0)
                            }
                            drawVolCurve(prepared.volMA5, color: palette.champagneGold)
                            drawVolCurve(prepared.volMA10, color: palette.macroIceBlue)
                        }

                        // 7. Signal, Trap & Wall Horizontal Lines with Right-Axis Colored Pills
                        func drawLevel(_ price: Double?, label: String, color: Color, dash: [CGFloat]) {
                            guard let price, price.isFinite, price >= lowBound, price <= highBound else { return }
                            let y = yFor(price)
                            var line = Path()
                            line.move(to: CGPoint(x: 0, y: y))
                            line.addLine(to: CGPoint(x: plotWidth, y: y))
                            context.stroke(line, with: .color(color.opacity(0.92)), style: StrokeStyle(lineWidth: 1.1, dash: dash))

                            let tagRect = CGRect(
                                x: plotWidth + 2,
                                y: max(2, min(pricePlotHeight - 16, y - 7)),
                                width: axisWidth - 4,
                                height: 14
                            )
                            context.fill(Path(roundedRect: tagRect, cornerRadius: 3), with: .color(color))
                            let tagText = Text("\(label) \(pricePrecision.format(price))")
                                .font(.system(size: 7.5, weight: .bold).monospacedDigit())
                                .foregroundStyle(.white)
                            context.draw(tagText, at: CGPoint(x: tagRect.midX, y: tagRect.midY), anchor: .center)
                        }

                        for trap in overlayModel.traps where trap.isActionable {
                            drawLevel(trap.price, label: "TRAP", color: palette.trapAmber, dash: [4, 3])
                        }
                        if overlayModel.marketClass == .crypto, let of = overlayModel.orderFlowSummary {
                            if of.bidWallConfirmed {
                                drawLevel(of.bidWallPrice, label: "BID", color: palette.longEmerald.opacity(0.85), dash: [2, 3])
                            }
                            if of.askWallConfirmed {
                                drawLevel(of.askWallPrice, label: "ASK", color: palette.shortCrimson.opacity(0.85), dash: [2, 3])
                            }
                        }
                        drawLevel(overlayModel.entryPrice, label: "E", color: palette.champagneGold, dash: [5, 3])
                        drawLevel(overlayModel.stopLoss, label: "SL", color: palette.shortCrimson, dash: [])
                        drawLevel(overlayModel.takeProfit1, label: "T1", color: palette.longEmerald, dash: [])
                        if overlayModel.isTP2Enabled {
                            drawLevel(overlayModel.takeProfit2, label: "T2", color: palette.longEmerald, dash: [3, 3])
                        }
                        if let lp = overlayModel.livePrice {
                            let liveColor = lp >= refClose ? palette.longEmerald : palette.shortCrimson
                            drawLevel(lp, label: "LIVE", color: liveColor, dash: [2, 2])
                        }

                        // 7b. Trade Replay Entry / Exit Markers
                        for marker in replayMarkers {
                            if let idx = visibleSlice.firstIndex(where: { abs($0.openTimeEpochSeconds - marker.timeEpochSeconds) < 1.0 }) {
                                let bar = visibleSlice[idx]
                                let cx = (CGFloat(idx) + 0.5) * stepX
                                let markerColor = Color(hex: marker.colorHex)
                                let isAbove = (marker.position == .aboveBar)
                                let cy = isAbove
                                    ? max(12.0, yFor(bar.high) - 10.0)
                                    : min(pricePlotHeight - 12.0, yFor(bar.low) + 10.0)

                                var pin = Path()
                                if isAbove {
                                    pin.move(to: CGPoint(x: cx, y: cy + 5))
                                    pin.addLine(to: CGPoint(x: cx - 4, y: cy - 2))
                                    pin.addLine(to: CGPoint(x: cx + 4, y: cy - 2))
                                    pin.closeSubpath()
                                } else {
                                    pin.move(to: CGPoint(x: cx, y: cy - 5))
                                    pin.addLine(to: CGPoint(x: cx - 4, y: cy + 2))
                                    pin.addLine(to: CGPoint(x: cx + 4, y: cy + 2))
                                    pin.closeSubpath()
                                }
                                context.fill(pin, with: .color(markerColor))

                                let labelY = isAbove ? max(7.0, cy - 9.0) : min(pricePlotHeight - 7.0, cy + 9.0)
                                let markerText = Text(marker.text)
                                    .font(.system(size: 8.5, weight: .bold))
                                    .foregroundStyle(markerColor)
                                context.draw(markerText, at: CGPoint(x: cx, y: labelY), anchor: .center)
                            }
                        }

                        // 8. Crosshair Guide
                        if let idx = inspectedVisibleIndex, idx >= 0, idx < visibleSlice.count {
                            let bar = visibleSlice[idx]
                            let cx = (CGFloat(idx) + 0.5) * stepX
                            let cy = max(0, min(pricePlotHeight, yFor(bar.close)))

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
                                inertia.stop()
                                guard !prepared.visibleBars.isEmpty else { return }
                                if isCrosshairActive {
                                    updateCrosshair(atX: value.location.x, plotWidth: plotWidth, visibleSlice: prepared.visibleBars)
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
                                dragStartOffset = nil
                                let barsPerPt = Double(visInt) / Double(max(plotWidth, 1.0))
                                let velocityPtsPerSec = Double(value.velocity.width)
                                let velocityBarsPerSec = velocityPtsPerSec * barsPerPt
                                let maxOff = Double(max(0, total - visInt))

                                inertia.start(velocityBarsPerSecond: velocityBarsPerSec) { deltaBars in
                                    let next = trailingOffset + deltaBars
                                    let clamped = max(0.0, min(maxOff, next))
                                    let hitEdge = abs(clamped - next) > 1e-6
                                    trailingOffset = clamped
                                    return !hitEdge
                                }
                            }
                    )
                    .simultaneousGesture(
                        MagnifyGesture()
                            .onChanged { value in
                                inertia.stop()
                                guard value.magnification.isFinite, value.magnification > 0 else { return }
                                if pinchStartVisibleCount == nil {
                                    pinchStartVisibleCount = visibleCount
                                }
                                let base = pinchStartVisibleCount ?? visibleCount
                                let proposed = base / Double(value.magnification)
                                visibleCount = max(Self.minVisibleBars, min(Self.maxVisibleBars, proposed))
                            }
                            .onEnded { _ in
                                pinchStartVisibleCount = nil
                            }
                    )
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.25)
                            .onEnded { _ in
                                inertia.stop()
                                isCrosshairActive = true
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                    )
                    .onTapGesture { location in
                        guard !prepared.visibleBars.isEmpty else { return }
                        if isCrosshairActive || inspectedVisibleIndex != nil {
                            isCrosshairActive = false
                            inspectedVisibleIndex = nil
                            onCrosshairChange(nil)
                        } else {
                            updateCrosshair(atX: location.x, plotWidth: plotWidth, visibleSlice: prepared.visibleBars)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }

                    if clampedOffset > 0 {
                        Button {
                            inertia.stop()
                            withAnimation(.easeOut(duration: 0.22)) {
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

                // Trailing 68pt hit-testable strip over right price axis for vertical drag-to-scale
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: 68)
                    .frame(maxHeight: .infinity)
                    .gesture(
                        DragGesture(minimumDistance: 3)
                            .onChanged { value in
                                inertia.stop()
                                if dragStartYScale == nil {
                                    dragStartYScale = yScaleMultiplier
                                }
                                let base = dragStartYScale ?? yScaleMultiplier
                                let factor = exp(Double(value.translation.height) / 180.0)
                                yScaleMultiplier = min(4.0, max(0.25, base * factor))
                            }
                            .onEnded { _ in
                                dragStartYScale = nil
                            }
                    )
                    .onTapGesture(count: 2) {
                        yScaleMultiplier = 1.0
                    }
            }
        }
        .background(palette.canvas)
        .onChange(of: resetTrigger) { _, _ in
            resetViewport()
        }
        .onChange(of: overlayModel.symbol) { _, _ in
            resetViewport()
        }
        .onChange(of: timeframe) { _, _ in
            resetViewport()
        }
        .onDisappear {
            inertia.stop()
        }
    }

    private func resetViewport() {
        inertia.stop()
        trailingOffset = 0.0
        visibleCount = 60.0
        yScaleMultiplier = 1.0
        dragStartOffset = nil
        pinchStartVisibleCount = nil
        dragStartYScale = nil
        inspectedVisibleIndex = nil
        isCrosshairActive = false
        onCrosshairChange(nil)
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
