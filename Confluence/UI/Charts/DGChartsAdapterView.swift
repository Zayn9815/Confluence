import SwiftUI
import UIKit
@preconcurrency import DGCharts
import SignalEngine

/// Native CoreGraphics candlestick engine powered by `ChartsOrg/Charts` (`DGCharts` static library).
/// - Smooth horizontal drag/deceleration + pinch-zoom (`dragXEnabled`, `scaleXEnabled`, `pinchZoomEnabled`).
/// - Custom X-axis timestamp formatter & right Y-axis `ChartPricePrecision` formatter (supports sub-penny crypto).
/// - Preserves scroll position on live tick updates; resets initial window only on symbol/timeframe/series change.
/// - Renders Entry, SL, TP1, TP2, Trap, and confirmed Crypto Bid/Ask Wall `ChartLimitLine`s.
public struct DGChartsAdapterView: ConfluenceChartAdapter {
    public let candles: [Candle]
    public let formingCandle: Candle?
    public let liveTick: LiveTick?
    public let overlayModel: ChartSignalOverlayModel
    public let timeframe: Timeframe
    public let pricePrecision: ChartPricePrecision
    public let palette: ConfluencePalette
    public let isDark: Bool
    public let onCrosshairChange: (ChartCrosshairReadout?) -> Void

    public init(
        candles: [Candle],
        formingCandle: Candle?,
        liveTick: LiveTick?,
        overlayModel: ChartSignalOverlayModel,
        timeframe: Timeframe,
        pricePrecision: ChartPricePrecision,
        palette: ConfluencePalette,
        isDark: Bool,
        onCrosshairChange: @escaping (ChartCrosshairReadout?) -> Void
    ) {
        self.candles = candles
        self.formingCandle = formingCandle
        self.liveTick = liveTick
        self.overlayModel = overlayModel
        self.timeframe = timeframe
        self.pricePrecision = pricePrecision
        self.palette = palette
        self.isDark = isDark
        self.onCrosshairChange = onCrosshairChange
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            DGChartsCandlestickRepresentable(
                candles: candles,
                formingCandle: formingCandle,
                overlayModel: overlayModel,
                timeframe: timeframe,
                pricePrecision: pricePrecision,
                isDark: isDark,
                onCrosshairChange: onCrosshairChange
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            ChartSignalOverlayHUD(
                overlayModel: overlayModel,
                precision: pricePrecision,
                palette: palette,
                engineBadge: "DGCharts"
            )
            .padding(10)
            .allowsHitTesting(false)
        }
    }
}

private final class DGTimestampAxisFormatter: NSObject, AxisValueFormatter {
    var epochs: [TimeInterval] = []
    var isDaily: Bool = false

    func stringForValue(_ value: Double, axis: AxisBase?) -> String {
        let idx = Int(value.rounded())
        guard idx >= 0, idx < epochs.count else { return "" }
        let date = Date(timeIntervalSince1970: epochs[idx])
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = isDaily ? "MMM d" : "MM/dd HH:mm"
        return f.string(from: date)
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
    let timeframe: Timeframe
    let pricePrecision: ChartPricePrecision
    let isDark: Bool
    let onCrosshairChange: (ChartCrosshairReadout?) -> Void

    @MainActor
    final class Coordinator: NSObject, ChartViewDelegate {
        var bars: [Candle] = []
        var lastSeriesKey: String = ""
        var lastOverlayKey: String = ""
        var lastThemeDark: Bool?
        let xFormatter = DGTimestampAxisFormatter()
        let yFormatter: DGPrecisionPriceAxisFormatter
        var onCrosshairChange: ((ChartCrosshairReadout?) -> Void)?

        init(precision: ChartPricePrecision) {
            self.yFormatter = DGPrecisionPriceAxisFormatter(precision: precision)
        }

        nonisolated func chartValueSelected(_ chartView: ChartViewBase, entry: ChartDataEntry, highlight: Highlight) {
            let xIndex = Int(entry.x.rounded())
            MainActor.assumeIsolated {
                guard xIndex >= 0, xIndex < self.bars.count else { return }
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
            MainActor.assumeIsolated {
                self.onCrosshairChange?(nil)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(precision: pricePrecision)
    }

    func makeUIView(context: Context) -> CandleStickChartView {
        let chart = CandleStickChartView(frame: .zero)
        let coord = context.coordinator
        coord.onCrosshairChange = onCrosshairChange
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
        chart.autoScaleMinMaxEnabled = true
        chart.highlightPerDragEnabled = false
        chart.highlightPerTapEnabled = true
        chart.minOffset = 8.0
        chart.extraRightOffset = 6.0

        chart.xAxis.labelPosition = .bottom
        chart.xAxis.drawGridLinesEnabled = true
        chart.xAxis.avoidFirstLastClippingEnabled = true
        chart.xAxis.valueFormatter = coord.xFormatter

        chart.rightAxis.enabled = true
        chart.rightAxis.drawGridLinesEnabled = true
        chart.rightAxis.drawLimitLinesBehindDataEnabled = false
        chart.rightAxis.valueFormatter = coord.yFormatter

        applyTheme(to: chart, isDark: isDark)
        coord.lastThemeDark = isDark
        updateDataAndOverlays(on: chart, coordinator: coord, forceViewportReset: true)
        return chart
    }

    func updateUIView(_ uiView: CandleStickChartView, context: Context) {
        let coord = context.coordinator
        coord.onCrosshairChange = onCrosshairChange
        coord.yFormatter.precision = pricePrecision

        if coord.lastThemeDark != isDark {
            coord.lastThemeDark = isDark
            applyTheme(to: uiView, isDark: isDark)
        }

        let firstOpen = candles.first?.openTimeEpochSeconds ?? 0
        let seriesKey = "\(overlayModel.symbol)|\(timeframe.rawValue)|\(Int(firstOpen))"
        let isSeriesReset = (coord.lastSeriesKey != seriesKey)
        updateDataAndOverlays(on: uiView, coordinator: coord, forceViewportReset: isSeriesReset)
    }

    static func dismantleUIView(_ uiView: CandleStickChartView, coordinator: Coordinator) {
        coordinator.onCrosshairChange = nil
        uiView.delegate = nil
    }

    private func applyTheme(to chart: CandleStickChartView, isDark: Bool) {
        let bg = isDark
            ? UIColor(red: 11.0 / 255.0, green: 13.0 / 255.0, blue: 17.0 / 255.0, alpha: 1.0)
            : UIColor(red: 246.0 / 255.0, green: 247.0 / 255.0, blue: 249.0 / 255.0, alpha: 1.0)
        let ink = isDark
            ? UIColor(red: 156.0 / 255.0, green: 167.0 / 255.0, blue: 186.0 / 255.0, alpha: 1.0)
            : UIColor(red: 55.0 / 255.0, green: 65.0 / 255.0, blue: 81.0 / 255.0, alpha: 1.0)
        let grid = isDark
            ? UIColor(red: 27.0 / 255.0, green: 34.0 / 255.0, blue: 48.0 / 255.0, alpha: 0.7)
            : UIColor(red: 229.0 / 255.0, green: 231.0 / 255.0, blue: 235.0 / 255.0, alpha: 0.85)

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
        forceViewportReset: Bool
    ) {
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
        dataSet.decreasingColor = UIColor(red: 239.0 / 255.0, green: 68.0 / 255.0, blue: 68.0 / 255.0, alpha: 1.0)
        dataSet.decreasingFilled = true
        dataSet.increasingColor = UIColor(red: 16.0 / 255.0, green: 185.0 / 255.0, blue: 129.0 / 255.0, alpha: 1.0)
        dataSet.increasingFilled = true
        dataSet.neutralColor = UIColor(red: 156.0 / 255.0, green: 167.0 / 255.0, blue: 186.0 / 255.0, alpha: 1.0)
        dataSet.highlightColor = UIColor(red: 212.0 / 255.0, green: 175.0 / 255.0, blue: 55.0 / 255.0, alpha: 0.75)

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

            addLimit(overlayModel.entryPrice, label: "ENTRY", color: UIColor(red: 212.0 / 255.0, green: 175.0 / 255.0, blue: 55.0 / 255.0, alpha: 1.0), dashed: true)
            addLimit(overlayModel.stopLoss, label: "SL", color: UIColor(red: 239.0 / 255.0, green: 68.0 / 255.0, blue: 68.0 / 255.0, alpha: 1.0), dashed: false)
            addLimit(overlayModel.takeProfit1, label: "TP1", color: UIColor(red: 16.0 / 255.0, green: 185.0 / 255.0, blue: 129.0 / 255.0, alpha: 1.0), dashed: false)
            if overlayModel.isTP2Enabled {
                addLimit(overlayModel.takeProfit2, label: "TP2", color: UIColor(red: 56.0 / 255.0, green: 189.0 / 255.0, blue: 248.0 / 255.0, alpha: 1.0), dashed: true)
            }
            if let trap = overlayModel.primaryTrap {
                addLimit(trap.price, label: trap.label, color: UIColor(red: 245.0 / 255.0, green: 158.0 / 255.0, blue: 11.0 / 255.0, alpha: 1.0), dashed: true)
            }
            if overlayModel.marketClass == .crypto, let of = overlayModel.orderFlowSummary {
                if of.bidWallConfirmed {
                    addLimit(of.bidWallPrice, label: "BID WALL", color: UIColor(red: 16.0 / 255.0, green: 185.0 / 255.0, blue: 129.0 / 255.0, alpha: 0.8), dashed: true)
                }
                if of.askWallConfirmed {
                    addLimit(of.askWallPrice, label: "ASK WALL", color: UIColor(red: 239.0 / 255.0, green: 68.0 / 255.0, blue: 68.0 / 255.0, alpha: 0.8), dashed: true)
                }
            }
        }

        // Initial viewport window on symbol/timeframe load ONLY (never snap back during live ticks!)
        if forceViewportReset && !bars.isEmpty {
            chart.setVisibleXRangeMaximum(60)
            chart.setVisibleXRangeMinimum(10)
            chart.moveViewToX(Double(max(0, bars.count - 1)))
        } else {
            chart.notifyDataSetChanged()
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
        return "\(e)|\(sl)|\(tp1)|\(tp2)|\(tr)|\(bw)|\(aw)|\(pricePrecision.precision)"
    }
}
