import SwiftUI
import CandleKit
import CandleKitCore
import SignalEngine

/// Native 120Hz SwiftUI Canvas candlestick engine powered by `LalanaChami/CandleKit` (`v0.2.0+`).
/// - Persists `@State private var chartState = CandleChartState(candleSpacing: 10)` so live ticks never reset pan/zoom.
/// - Maps sorted unique-timestamp `CandleKitCore.Candle` bars and locked horizontal `Drawing` lines
///   for Entry, Stop Loss, TP1, TP2, Breakeven, Traps, and Confirmed Crypto Bid/Ask Walls.
/// - Wires `.volumeVisible(true)`, `.headerVisible(false)`, `.priceFractionDigits(pricePrecision.precision)`,
///   and `.onCrosshairChange`, with zero floating overlay HUD obstruction.
public struct CandleKitAdapterView: ConfluenceChartAdapter {
    public let candles: [EngineCandle]
    public let formingCandle: EngineCandle?
    public let overlayModel: ChartSignalOverlayModel
    public let timeframe: Timeframe
    public let pricePrecision: ChartPricePrecision
    public let palette: ConfluencePalette
    public let resetTrigger: Int
    public let onCrosshairChange: (ChartCrosshairReadout?) -> Void

    @State private var chartState = CandleChartState(candleSpacing: 10)

    public init(
        candles: [EngineCandle],
        formingCandle: EngineCandle?,
        overlayModel: ChartSignalOverlayModel,
        timeframe: Timeframe,
        pricePrecision: ChartPricePrecision,
        palette: ConfluencePalette,
        resetTrigger: Int = 0,
        onCrosshairChange: @escaping (ChartCrosshairReadout?) -> Void
    ) {
        self.candles = candles
        self.formingCandle = formingCandle
        self.overlayModel = overlayModel
        self.timeframe = timeframe
        self.pricePrecision = pricePrecision
        self.palette = palette
        self.resetTrigger = resetTrigger
        self.onCrosshairChange = onCrosshairChange
    }

    private func drawingColor(from color: Color, opacity: Double) -> DrawingColor {
        var r: CGFloat = 0.5
        var g: CGFloat = 0.5
        var b: CGFloat = 0.5
        var a: CGFloat = 1.0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return DrawingColor(red: Double(r), green: Double(g), blue: Double(b), opacity: opacity)
    }

    private var mappedCandles: [CandleKitCore.Candle] {
        var byEpoch: [TimeInterval: EngineCandle] = [:]
        byEpoch.reserveCapacity(candles.count + 1)
        for c in candles where c.open.isFinite && c.high.isFinite && c.low.isFinite && c.close.isFinite && c.openTimeEpochSeconds.isFinite {
            byEpoch[c.openTimeEpochSeconds] = c
        }
        if let f = formingCandle,
           f.open.isFinite && f.high.isFinite && f.low.isFinite && f.close.isFinite && f.openTimeEpochSeconds.isFinite {
            byEpoch[f.openTimeEpochSeconds] = f
        }
        let sortedKeys = byEpoch.keys.sorted()
        return sortedKeys.compactMap { ts in
            guard let c = byEpoch[ts] else { return nil }
            let vol = (c.volume != nil && c.volume!.isFinite && c.volume! >= 0) ? c.volume! : 0.0
            return CandleKitCore.Candle(
                time: Date(timeIntervalSince1970: ts),
                open: c.open,
                high: c.high,
                low: c.low,
                close: c.close,
                volume: vol
            )
        }
    }

    private func buildHorizontalOverlayDrawings(anchorDate: Date) -> [Drawing] {
        var result: [Drawing] = []

        func addLine(price: Double, color: DrawingColor, lineWidth: Double, dash: [Double]?) {
            guard price.isFinite && price > 0 else { return }
            result.append(Drawing(
                kind: .horizontalLine,
                anchors: [DrawingAnchor(time: anchorDate, price: price)],
                style: DrawingStyle(color: color, lineWidth: lineWidth, dash: dash),
                isLocked: true,
                isHidden: false
            ))
        }

        let gold = drawingColor(from: palette.champagneGold, opacity: 0.95)
        let crimson = drawingColor(from: palette.shortCrimson, opacity: 0.95)
        let emerald = drawingColor(from: palette.longEmerald, opacity: 0.95)
        let mutedSlate = drawingColor(from: palette.macroIceBlue, opacity: 0.90)
        let amber = drawingColor(from: palette.trapAmber, opacity: 0.90)

        if let entry = overlayModel.entryPrice {
            addLine(price: entry, color: gold, lineWidth: 1.5, dash: [6, 4])
        }
        if let sl = overlayModel.stopLoss {
            addLine(price: sl, color: crimson, lineWidth: 1.8, dash: nil)
        }
        if let tp1 = overlayModel.takeProfit1 {
            addLine(price: tp1, color: emerald, lineWidth: 1.8, dash: nil)
        }
        if overlayModel.isTP2Enabled, let tp2 = overlayModel.takeProfit2 {
            addLine(price: tp2, color: emerald, lineWidth: 1.3, dash: [5, 4])
        }
        if let be = overlayModel.breakevenPrice {
            addLine(price: be, color: mutedSlate, lineWidth: 1.2, dash: [2, 3])
        }
        for trap in overlayModel.traps where trap.isActionable {
            addLine(price: trap.price, color: amber, lineWidth: 1.2, dash: [5, 4])
        }
        if overlayModel.marketClass == .crypto, let orderFlow = overlayModel.orderFlowSummary {
            if orderFlow.bidWallConfirmed, let bidWall = orderFlow.bidWallPrice {
                addLine(price: bidWall, color: emerald, lineWidth: 1.2, dash: [2, 3])
            }
            if orderFlow.askWallConfirmed, let askWall = orderFlow.askWallPrice {
                addLine(price: askWall, color: crimson, lineWidth: 1.2, dash: [2, 3])
            }
        }
        return result
    }

    public var body: some View {
        let series = mappedCandles
        ZStack(alignment: .topLeading) {
            if series.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.title3)
                        .foregroundStyle(palette.tertiaryInk)
                    Text("No closed candles available")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(palette.secondaryInk)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.canvas)
            } else {
                let anchorDate = series.last?.time ?? Date()
                let drawings = buildHorizontalOverlayDrawings(anchorDate: anchorDate)

                CandlestickChart(series, state: chartState)
                    .volumeVisible(true)
                    .headerVisible(false)
                    .priceFractionDigits(pricePrecision.precision)
                    .drawings(.constant(drawings))
                    .onCrosshairChange { inspected in
                        if let c = inspected {
                            onCrosshairChange(ChartCrosshairReadout(
                                epochSeconds: c.time.timeIntervalSince1970,
                                open: c.open,
                                high: c.high,
                                low: c.low,
                                close: c.close
                            ))
                        } else {
                            onCrosshairChange(nil)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(palette.canvas)
                    .id("\(overlayModel.symbol)|\(timeframe.rawValue)")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: resetTrigger) { _, _ in
            chartState = CandleChartState(candleSpacing: 10)
        }
    }
}
