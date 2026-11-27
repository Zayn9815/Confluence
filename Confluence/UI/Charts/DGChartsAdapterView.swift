import SwiftUI
import UIKit
@preconcurrency import DGCharts
import SignalEngine

/// Native CoreGraphics candlestick engine powered by `ChartsOrg/Charts` (`DGCharts` static library).
/// - Smooth horizontal drag/deceleration + pinch-zoom (`dragXEnabled`, `scaleXEnabled`, `pinchZoomEnabled`).
/// - Deterministic visible-slice Y-axis scaling (`autoScaleMinMaxEnabled = false`) — zero jump/glitch on pan or zoom.
/// - Trailing 68pt right price-axis vertical drag-to-scale (`0.25x...4.0x`) + double-tap / `resetTrigger` reset.
/// - Zero floating overlay HUD; renders Entry, SL, TP1, TP2 (emerald), Trap, and confirmed Crypto Bid/Ask Wall limit lines.
public struct DGChartsAdapterView: ConfluenceChartAdapter {
    public let candles: [Candle]
    public let formingCandle: Candle?
    public let overlayModel: ChartSignalOverlayModel
    public let replayMarkers: [ChartReplayMarker]
    public let timeframe: Timeframe
    public let pricePrecision: ChartPricePrecision
    public let palette: ConfluencePalette
    public let resetTrigger: Int
    public let onCrosshairChange: (ChartCrosshairReadout?) -> Void

    @State private var yScaleMultiplier: Double = 1.0
    @State private var dragStartYScale: Double? = nil

    public init(
        candles: [Candle],
        formingCandle: Candle?,
        overlayModel: ChartSignalOverlayModel,
        replayMarkers: [ChartReplayMarker] = [],
        timeframe: Timeframe,
        pricePrecision: ChartPricePrecision,
        palette: ConfluencePalette,
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
        self.resetTrigger = resetTrigger
        self.onCrosshairChange = onCrosshairChange
    }

    public var body: some View {
        ZStack(alignment: .trailing) {
            DGChartsCandlestickRepresentable(
                candles: candles,
                formingCandle: formingCandle,
                overlayModel: overlayModel,
                replayMarkers: replayMarkers,
                timeframe: timeframe,
                pricePrecision: pricePrecision,
                palette: palette,
                yScaleMultiplier: yScaleMultiplier,
                resetTrigger: resetTrigger,
                onCrosshairChange: onCrosshairChange
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Trailing 68pt hit-testable strip over right price axis for vertical drag-to-scale
            Color.clear
                .contentShape(Rectangle())
                .frame(width: 68)
                .frame(maxHeight: .infinity)
                .gesture(
                    DragGesture(minimumDistance: 3)
                        .onChanged { value in
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
        .onChange(of: resetTrigger) { _, _ in
            yScaleMultiplier = 1.0
            dragStartYScale = nil
        }
        .onChange(of: overlayModel.symbol) { _, _ in
            yScaleMultiplier = 1.0
            dragStartYScale = nil
        }
        .onChange(of: timeframe) { _, _ in
            yScaleMultiplier = 1.0
            dragStartYScale = nil
        }
    }
}

private final class DGTimestampAxisFormatter: NSObject, AxisValueFormatter {
    private static let dailyStyle = Date.VerbatimFormatStyle(
        format: "\(month: .abbreviated) \(day: .defaultDigits)",
        locale: Locale(identifier: "en_US_POSIX"),
        timeZone: TimeZone(secondsFromGMT: 0) ?? .gmt,
        calendar: Calendar(identifier: .gregorian)
    )
    private static let intradayStyle = Date.VerbatimFormatStyle(
        format: "\(month: .twoDigits)/\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
        locale: Locale(identifier: "en_US_POSIX"),
        timeZone: TimeZone(secondsFromGMT: 0) ?? .gmt,
        calendar: Calendar(identifier: .gregorian)
    )

    var epochs: [TimeInterval] = []
    var isDaily: Bool = false

    func stringForValue(_ value: Double, axis: AxisBase?) -> String {
        let idx = Int(value.rounded())
        guard idx >= 0, idx < epochs.count else { return "" }
        let date = Date(timeIntervalSince1970: epochs[idx])
        return isDaily ? Self.dailyStyle.format(date) : Self.intradayStyle.format(date)
    }
}

private final class DGPrecisionPriceAxisFormatter: NSObject, AxisValueFormatter {
    var precision: ChartPricePrecision

    init(precision: ChartPricePrecision) {
        self.precision = precision
    }

    func stringForValue(_ value: Double, axis: AxisBase?) -> String {
        precision.format(value)
    }
}

private struct DGChartsCandlestickRepresentable: UIViewRepresentable {
    let candles: [Candle]
    let formingCandle: Candle?
    let overlayModel: ChartSignalOverlayModel
    let replayMarkers: [ChartReplayMarker]
    let timeframe: Timeframe
    let pricePrecision: ChartPricePrecision
    let palette: ConfluencePalette
    let yScaleMultiplier: Double
    let resetTrigger: Int
    let onCrosshairChange: (ChartCrosshairReadout?) -> Void

    @MainActor
    final class Coordinator: NSObject, ChartViewDelegate {
        var bars: [Candle] = []
        var lastSeriesKey: String = ""
        var lastOverlayKey: String = ""
        var lastResetTrigger: Int = 0
        var yScaleMultiplier: Double = 1.0
        weak var chartView: CandleStickChartView?
        let xFormatter = DGTimestampAxisFormatter()
        let yFormatter: DGPrecisionPriceAxisFormatter
        var onCrosshairChange: ((ChartCrosshairReadout?) -> Void)?

        init(precision: ChartPricePrecision) {
            self.yFormatter = DGPrecisionPriceAxisFormatter(precision: precision)
        }

        func applyVisibleYAxisBounds(on chart: CandleStickChartView) {
            guard !bars.isEmpty else { return }
            let loIdx = max(0, min(bars.count - 1, Int(floor(chart.lowestVisibleX))))
            let hiIdx = max(loIdx, min(bars.count - 1, Int(ceil(chart.highestVisibleX))))

            var minLow = Double.greatestFiniteMagnitude
            var maxHigh = -Double.greatestFiniteMagnitude
            for i in loIdx...hiIdx {
                let bar = bars[i]
                if bar.low.isFinite && bar.low < minLow { minLow = bar.low }
                if bar.high.isFinite && bar.high > maxHigh { maxHigh = bar.high }
            }
            guard minLow.isFinite, maxHigh.isFinite, maxHigh >= minLow else { return }

            let midPrice = (minLow + maxHigh) * 0.5
            let rawSpan = maxHigh - minLow
            let flooredSpan = max(rawSpan, max(abs(midPrice) * 0.0005, 1e-9))
            let paddedHalf = (flooredSpan * 0.5) * 1.16 * min(4.0, max(0.25, yScaleMultiplier))

            let axisMin = midPrice - paddedHalf
            let axisMax = midPrice + paddedHalf
            guard axisMin.isFinite, axisMax.isFinite, axisMax > axisMin else { return }

            chart.rightAxis.axisMinimum = axisMin
            chart.rightAxis.axisMaximum = axisMax
            chart.setNeedsDisplay()
        }

        nonisolated func chartTranslated(_ chartView: ChartViewBase, dX: CGFloat, dY: CGFloat) {
            Task { @MainActor [weak self] in
                guard let self, let chart = self.chartView else { return }
                self.applyVisibleYAxisBounds(on: chart)
            }
        }

        nonisolated func chartScaled(_ chartView: ChartViewBase, scaleX: CGFloat, scaleY: CGFloat) {
            Task { @MainActor [weak self] in
                guard let self, let chart = self.chartView else { return }
                self.applyVisibleYAxisBounds(on: chart)
            }
        }

        nonisolated func chartValueSelected(_ chartView: ChartViewBase, entry: ChartDataEntry, highlight: Highlight) {
            let xIndex = Int(entry.x.rounded())
            Task { @MainActor [weak self] in
                guard let self, xIndex >= 0, xIndex < self.bars.count else { return }
                let bar = self.bars[xIndex]
                self.onCrosshairChange?(ChartCrosshairReadout(
                    epochSeconds: bar.openTimeEpochSeconds,
                    open: bar.open,
                    high: bar.high,
                    low: bar.low,
                    close: bar.close,
                    isForming: !bar.isClosed
                ))
            }
        }

        nonisolated func chartValueNothingSelected(_ chartView: ChartViewBase) {
            Task { @MainActor [weak self] in
                self?.onCrosshairChange?(nil)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(precision: pricePrecision)
    }

    func makeUIView(context: Context) -> CandleStickChartView {
        let chart = CandleStickChartView(frame: .zero)
        let coord = context.coordinator
        coord.chartView = chart
        coord.onCrosshairChange = onCrosshairChange
        coord.yScaleMultiplier = yScaleMultiplier
        coord.lastResetTrigger = resetTrigger
        chart.delegate = coord

        chart.chartDescription.enabled = false
        chart.legend.enabled = false
        chart.leftAxis.enabled = false
        chart.dragEnabled = true
        chart.dragXEnabled = true
        chart.dragYEnabled = false
        chart.scaleXEnabled = true
        chart.scaleYEnabled = false
        chart.pinchZoomEnabled = true
        chart.doubleTapToZoomEnabled = true
        chart.dragDecelerationEnabled = true
        chart.dragDecelerationFrictionCoef = 0.92
        chart.autoScaleMinMaxEnabled = false
        chart.highlightPerDragEnabled = false
        chart.highlightPerTapEnabled = true
        chart.minOffset = 8.0
        chart.extraRightOffset = 6.0

        chart.xAxis.labelPosition = .bottom
        chart.xAxis.drawGridLinesEnabled = true
        chart.xAxis.granularityEnabled = true
        chart.xAxis.setLabelCount(4, force: false)
        chart.xAxis.avoidFirstLastClippingEnabled = true
        chart.xAxis.valueFormatter = coord.xFormatter

        chart.rightAxis.enabled = true
        chart.rightAxis.drawGridLinesEnabled = true
        chart.rightAxis.drawLimitLinesBehindDataEnabled = false
        chart.rightAxis.valueFormatter = coord.yFormatter

        applyTheme(to: chart, palette: palette)
        updateDataAndOverlays(on: chart, coordinator: coord, forceViewportReset: true)
        return chart
    }

    func updateUIView(_ uiView: CandleStickChartView, context: Context) {
        let coord = context.coordinator
        coord.chartView = uiView
        coord.onCrosshairChange = onCrosshairChange
        coord.yFormatter.precision = pricePrecision

        applyTheme(to: uiView, palette: palette)

        let scaleChanged = abs(coord.yScaleMultiplier - yScaleMultiplier) > 1e-4
        coord.yScaleMultiplier = yScaleMultiplier

        let resetRequested = (coord.lastResetTrigger != resetTrigger)
        if resetRequested {
            coord.lastResetTrigger = resetTrigger
        }

        let firstOpen = candles.first?.openTimeEpochSeconds ?? 0
        let seriesKey = "\(overlayModel.symbol)|\(timeframe.rawValue)|\(Int(firstOpen))"
        let isSeriesReset = (coord.lastSeriesKey != seriesKey) || resetRequested

        updateDataAndOverlays(
            on: uiView,
            coordinator: coord,
            forceViewportReset: isSeriesReset,
            reapplyYBoundsOnly: !isSeriesReset && scaleChanged
        )
    }

    static func dismantleUIView(_ uiView: CandleStickChartView, coordinator: Coordinator) {
        coordinator.onCrosshairChange = nil
        coordinator.chartView = nil
        uiView.delegate = nil
    }

    private func applyTheme(to chart: CandleStickChartView, palette: ConfluencePalette) {
        let bg = UIColor(palette.canvas)
        let ink = UIColor(palette.secondaryInk)
        let grid = UIColor(palette.border).withAlphaComponent(0.75)

        chart.backgroundColor = bg
        chart.gridBackgroundColor = bg
        chart.xAxis.labelTextColor = ink
        chart.xAxis.gridColor = grid
        chart.xAxis.axisLineColor = grid
        chart.rightAxis.labelTextColor = ink
        chart.rightAxis.gridColor = grid
        chart.rightAxis.axisLineColor = grid
    }

    private func combinedBars() -> [Candle] {
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

    private func updateDataAndOverlays(
        on chart: CandleStickChartView,
        coordinator: Coordinator,
        forceViewportReset: Bool,
        reapplyYBoundsOnly: Bool = false
    ) {
        if reapplyYBoundsOnly {
            coordinator.applyVisibleYAxisBounds(on: chart)
            return
        }

        let bars = combinedBars()
        coordinator.bars = bars
        coordinator.xFormatter.epochs = bars.map(\.openTimeEpochSeconds)
        coordinator.xFormatter.isDaily = (timeframe == .d1)

        let firstOpen = candles.first?.openTimeEpochSeconds ?? 0
        coordinator.lastSeriesKey = "\(overlayModel.symbol)|\(timeframe.rawValue)|\(Int(firstOpen))"

        let entries: [CandleChartDataEntry] = bars.enumerated().map { idx, bar in
            CandleChartDataEntry(
                x: Double(idx),
                shadowH: bar.high,
                shadowL: bar.low,
                open: bar.open,
                close: bar.close
            )
        }

        let dataSet = CandleChartDataSet(entries: entries, label: overlayModel.symbol)
        dataSet.axisDependency = .right
        dataSet.drawIconsEnabled = false
        dataSet.drawValuesEnabled = false
        dataSet.shadowColorSameAsCandle = true
        dataSet.shadowWidth = 1.0
        dataSet.decreasingColor = UIColor(palette.shortCrimson)
        dataSet.decreasingFilled = true
        dataSet.increasingColor = UIColor(palette.longEmerald)
        dataSet.increasingFilled = true
        dataSet.neutralColor = UIColor(palette.macroIceBlue)
        dataSet.highlightColor = UIColor(palette.champagneGold).withAlphaComponent(0.75)

        chart.data = CandleChartData(dataSet: dataSet)

        // Apply LimitLines ONLY when overlay signature changes
        let overlaySig = buildOverlaySignature()
        if coordinator.lastOverlayKey != overlaySig {
            coordinator.lastOverlayKey = overlaySig
            let rightAxis = chart.rightAxis
            rightAxis.removeAllLimitLines()

            func addLimit(_ price: Double?, label: String, color: UIColor, dashed: Bool) {
                guard let price, price.isFinite, price > 0 else { return }
                let line = ChartLimitLine(limit: price, label: "\(label) \(pricePrecision.format(price))")
                line.lineColor = color
                line.lineWidth = dashed ? 1.1 : 1.5
                if dashed {
                    line.lineDashLengths = [5, 4]
                }
                line.valueTextColor = color
                line.valueFont = .monospacedDigitSystemFont(ofSize: 9, weight: .bold)
                line.labelPosition = .rightTop
                rightAxis.addLimitLine(line)
            }

            let goldColor = UIColor(palette.champagneGold)
            let crimsonColor = UIColor(palette.shortCrimson)
            let emeraldColor = UIColor(palette.longEmerald)
            let mutedSlateColor = UIColor(palette.macroIceBlue)
            let amberColor = UIColor(palette.trapAmber)

            addLimit(overlayModel.entryPrice, label: "ENTRY", color: goldColor, dashed: true)
            addLimit(overlayModel.stopLoss, label: "SL", color: crimsonColor, dashed: false)
            addLimit(overlayModel.takeProfit1, label: "TP1", color: emeraldColor, dashed: false)
            if overlayModel.isTP2Enabled {
                addLimit(overlayModel.takeProfit2, label: "TP2", color: emeraldColor, dashed: true)
            }
            if let be = overlayModel.breakevenPrice {
                addLimit(be, label: "BE", color: mutedSlateColor, dashed: true)
            }
            for trap in overlayModel.traps where trap.isActionable {
                addLimit(trap.price, label: trap.label, color: amberColor, dashed: true)
            }
            if overlayModel.marketClass == .crypto, let of = overlayModel.orderFlowSummary {
                if of.bidWallConfirmed {
                    addLimit(of.bidWallPrice, label: "BID WALL", color: emeraldColor.withAlphaComponent(0.8), dashed: true)
                }
                if of.askWallConfirmed {
                    addLimit(of.askWallPrice, label: "ASK WALL", color: crimsonColor.withAlphaComponent(0.8), dashed: true)
                }
            }

            let xAxis = chart.xAxis
            xAxis.removeAllLimitLines()
            for marker in replayMarkers {
                if let idx = bars.firstIndex(where: { abs($0.openTimeEpochSeconds - marker.timeEpochSeconds) < 1.0 }) {
                    let r = CGFloat((marker.colorHex & 0xFF0000) >> 16) / 255.0
                    let g = CGFloat((marker.colorHex & 0x00FF00) >> 8) / 255.0
                    let b = CGFloat(marker.colorHex & 0x0000FF) / 255.0
                    let color = UIColor(red: r, green: g, blue: b, alpha: 0.95)
                    let line = ChartLimitLine(limit: Double(idx), label: marker.text)
                    line.lineColor = color
                    line.lineWidth = 1.2
                    line.lineDashLengths = [4, 3]
                    line.valueTextColor = color
                    line.valueFont = .monospacedDigitSystemFont(ofSize: 9, weight: .bold)
                    line.labelPosition = (marker.position == .aboveBar) ? .rightTop : .rightBottom
                    xAxis.addLimitLine(line)
                }
            }
        }

        let count = bars.count
        if count > 0 {
            let minVis = Double(min(10, max(1, count)))
            let maxVis = Double(max(180, count))
            if forceViewportReset {
                chart.fitScreen()
                let initialWindow = Double(min(50, max(1, count)))
                chart.setVisibleXRangeMinimum(minVis)
                chart.setVisibleXRangeMaximum(initialWindow)
                chart.moveViewToX(Double(max(0, count - 1)))
                chart.setVisibleXRangeMaximum(maxVis)
            } else {
                chart.setVisibleXRangeMinimum(minVis)
                chart.setVisibleXRangeMaximum(maxVis)
            }
            coordinator.applyVisibleYAxisBounds(on: chart)
        }
    }

    private func buildOverlaySignature() -> String {
        let e = overlayModel.entryPrice.map { String(format: "%.8f", $0) } ?? "n"
        let sl = overlayModel.stopLoss.map { String(format: "%.8f", $0) } ?? "n"
        let tp1 = overlayModel.takeProfit1.map { String(format: "%.8f", $0) } ?? "n"
        let tp2 = overlayModel.isTP2Enabled ? (overlayModel.takeProfit2.map { String(format: "%.8f", $0) } ?? "n") : "off"
        let tr = overlayModel.trapPrice.map { String(format: "%.8f", $0) } ?? "n"
        let bw = overlayModel.orderFlowSummary?.bidWallConfirmed == true ? (overlayModel.orderFlowSummary?.bidWallPrice.map { String(format: "%.6f", $0) } ?? "n") : "n"
        let aw = overlayModel.orderFlowSummary?.askWallConfirmed == true ? (overlayModel.orderFlowSummary?.askWallPrice.map { String(format: "%.6f", $0) } ?? "n") : "n"
        let rm = replayMarkers.map { "\($0.id):\(Int($0.timeEpochSeconds))" }.joined(separator: ",")
        return "\(e)|\(sl)|\(tp1)|\(tp2)|\(tr)|\(bw)|\(aw)|\(pricePrecision.precision)|\(rm)"
    }
}
