import SwiftUI
@preconcurrency import SwiftTradingView
import SignalEngine

/// Multi-pane SwiftUI financial chart powered by `sergiikhliustin/swift-trading-view` (`SwiftTradingView`).
/// - Renders Candlesticks + MA overlay in primary pane and Volume in secondary pane.
/// - Stable `.id` tied strictly to `symbol|timeframe` so live ticks update smoothly without resetting scroll position.
/// - Non-blocking Liquid Glass `ChartSignalOverlayHUD` layered cleanly on top.
public struct SwiftTradingViewAdapterView: ConfluenceChartAdapter {
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

    private var mappedCandleData: [CandleData] {
        var combined = candles.sorted { $0.openTimeEpochSeconds < $1.openTimeEpochSeconds }
        if let forming = formingCandle {
            if let last = combined.last, abs(last.openTimeEpochSeconds - forming.openTimeEpochSeconds) < 1.0 {
                combined[combined.count - 1] = forming
            } else if (combined.last?.openTimeEpochSeconds ?? -1) < forming.openTimeEpochSeconds {
                combined.append(forming)
            }
        }
        return combined.map { bar in
            CandleData(
                time: bar.openTimeEpochSeconds,
                open: bar.open,
                close: bar.close,
                high: bar.high,
                low: bar.low,
                volume: bar.volume ?? 0.0
            )
        }
    }

    public var body: some View {
        let data = mappedCandleData
        ZStack(alignment: .topLeading) {
            if data.isEmpty {
                NativeCanvasFallbackChartView(
                    candles: candles,
                    formingCandle: formingCandle,
                    overlayModel: overlayModel,
                    timeframe: timeframe,
                    pricePrecision: pricePrecision,
                    palette: palette,
                    showVolumePane: true,
                    showMovingAverages: true,
                    onCrosshairChange: onCrosshairChange
                )
            } else {
                TradingView(
                    data: data,
                    candleWidth: 3...22,
                    candleSpacing: 2,
                    secondaryContentHeight: 76,
                    primaryContent: [
                        Candles(),
                        MAIndicator(
                            periods: [
                                .init(value: 20, color: palette.champagneGold),
                                .init(value: 50, color: palette.macroIceBlue)
                            ],
                            lineWidth: 1.25
                        )
                    ],
                    secondaryContent: [
                        VolumeIndicator()
                    ]
                )
                .id("\(overlayModel.symbol)|\(timeframe.rawValue)")
                .background(palette.canvas)
            }

            ChartSignalOverlayHUD(
                overlayModel: overlayModel,
                precision: pricePrecision,
                palette: palette,
                engineBadge: "Swift Trading View"
            )
            .padding(10)
            .allowsHitTesting(false)
        }
        .onChange(of: overlayModel.symbol) { _, _ in
            onCrosshairChange(nil)
        }
        .onChange(of: timeframe) { _, _ in
            onCrosshairChange(nil)
        }
    }
}
