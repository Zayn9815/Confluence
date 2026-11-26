import SwiftUI
import CandleKit
import CandleKitCore
import SignalEngine

/// Native 120Hz SwiftUI Canvas candlestick engine powered by `LalanaChami/CandleKit` (`v0.2.0+`).
/// - Persists `@State private var chartState = CandleChartState(candleSpacing: 10)` so live ticks never reset pan/zoom.
/// - Maps sorted unique-timestamp `CandleKitCore.Candle` bars + `ChartOrderLine`s for Entry/SL/TP1/TP2/Confirmed Walls.
/// - Wires `.volumeVisible(true)`, `.headerVisible(false)`, `.priceFractionDigits(pricePrecision.precision)`, and `.onCrosshairChange`.
public struct CandleKitAdapterView: ConfluenceChartAdapter {
    public let candles: [Candle]
    public let formingCandle: Candle?
    public let liveTick: LiveTick?
    public let overlayModel: ChartSignalOverlayModel
    public let timeframe: Timeframe
    public let pricePrecision: ChartPricePrecision
    public let palette: ConfluencePalette
    public let isDark: Bool
    public let onCrosshairChange: (ChartCrosshairReadout?) -> Void

    @State private var chartState = CandleChartState(candleSpacing: 10)

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

    private var mappedCandles: [CandleKitCore.Candle] {
        var byTime: [Int: SignalEngine.Candle] = [:]
        for bar in candles where bar.open.isFinite && bar.high.isFinite && bar.low.isFinite && bar.close.isFinite {
            let key = Int(bar.openTimeEpochSeconds.rounded())
            byTime[key] = bar
        }
        if let forming = formingCandle,
           forming.open.isFinite, forming.high.isFinite, forming.low.isFinite, forming.close.isFinite {
            let key = Int(forming.openTimeEpochSeconds.rounded())
            byTime[key] = forming
        }
        return byTime.values
            .sorted { $0.openTimeEpochSeconds < $1.openTimeEpochSeconds }
            .map { bar in
                CandleKitCore.Candle(
                    time: Date(timeIntervalSince1970: bar.openTimeEpochSeconds),
                    open: bar.open,
                    high: bar.high,
                    low: bar.low,
                    close: bar.close,
                    volume: max(0.0, bar.volume ?? 0.0)
                )
            }
    }

    private var mappedOrderLines: [ChartOrderLine] {
        var lines: [ChartOrderLine] = []
        if let entry = overlayModel.entryPrice {
            lines.append(ChartOrderLine(id: "entry", price: entry, kind: .position, label: "ENTRY"))
        }
        if let sl = overlayModel.stopLoss {
            lines.append(ChartOrderLine(id: "sl", price: sl, kind: .stopLoss, label: "SL"))
        }
        if let tp1 = overlayModel.takeProfit1 {
            lines.append(ChartOrderLine(id: "tp1", price: tp1, kind: .takeProfit, label: "TP1"))
        }
        if overlayModel.isTP2Enabled, let tp2 = overlayModel.takeProfit2 {
            lines.append(ChartOrderLine(id: "tp2", price: tp2, kind: .takeProfit, label: "TP2"))
        }
        if overlayModel.marketClass == .crypto, let of = overlayModel.orderFlowSummary {
            if of.bidWallConfirmed, let bp = of.bidWallPrice {
                lines.append(ChartOrderLine(id: "bid_wall", price: bp, kind: .buy, label: "BID WALL"))
            }
            if of.askWallConfirmed, let ap = of.askWallPrice {
                lines.append(ChartOrderLine(id: "ask_wall", price: ap, kind: .sell, label: "ASK WALL"))
            }
        }
        return lines
    }

    public var body: some View {
        let ckCandles = mappedCandles
        ZStack(alignment: .topLeading) {
            if ckCandles.isEmpty {
                NativeCanvasFallbackChartView(
                    candles: candles,
                    formingCandle: formingCandle,
                    overlayModel: overlayModel,
                    timeframe: timeframe,
                    pricePrecision: pricePrecision,
                    palette: palette,
                    showVolumePane: true,
                    onCrosshairChange: onCrosshairChange
                )
            } else {
                CandlestickChart(ckCandles, state: chartState)
                    .candleChartStyle(CandleChartStyle(
                        upColor: palette.longEmerald,
                        downColor: palette.shortCrimson,
                        gridColor: palette.border.opacity(0.45),
                        axisLabelColor: palette.secondaryInk,
                        crosshairColor: palette.champagneGold.opacity(0.8)
                    ))
                    .orderLines(mappedOrderLines)
                    .volumeVisible(true)
                    .headerVisible(false)
                    .priceFractionDigits(pricePrecision.precision)
                    .onCrosshairChange { candle in
                        if let c = candle {
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
                    .background(palette.canvas)
            }

            ChartSignalOverlayHUD(
                overlayModel: overlayModel,
                precision: pricePrecision,
                palette: palette,
                engineBadge: "CandleKit"
            )
            .padding(10)
            .allowsHitTesting(false)
        }
        .onChange(of: overlayModel.symbol) { _, _ in
            chartState.scrollToLatest()
            onCrosshairChange(nil)
        }
        .onChange(of: timeframe) { _, _ in
            chartState.scrollToLatest()
            onCrosshairChange(nil)
        }
    }
}
