import SwiftUI
import SignalEngine

/// Engine-agnostic chart container and lazy router.
/// Instantiates ONLY the currently selected `ChartEngineOption` engine for battery efficiency,
/// and layers the lightweight native SwiftUI top OHLCV + R:R crosshair strip on top.
public struct ConfluenceChartContainerView: View {
    public let selectedEngine: ChartEngineOption
    public let symbol: String
    public let closedCandles: [Candle]
    public let formingCandle: Candle?
    public let fitRequestToken: Int
    public let overlayModel: ChartSignalOverlayModel
    public let replayMarkers: [ChartReplayMarker]
    public let pricePrecision: ChartPricePrecision
    public let timeframe: Timeframe
    public let palette: ConfluencePalette
    public let isDark: Bool
    public let showMovingAverages: Bool
    @Binding public var tradingViewPreferDesktop: Bool

    @State private var crosshairReadout: ChartCrosshairReadout? = nil

    public init(
        selectedEngine: ChartEngineOption,
        symbol: String? = nil,
        closedCandles: [Candle],
        formingCandle: Candle?,
        fitRequestToken: Int,
        overlayModel: ChartSignalOverlayModel,
        replayMarkers: [ChartReplayMarker] = [],
        pricePrecision: ChartPricePrecision,
        timeframe: Timeframe,
        palette: ConfluencePalette,
        isDark: Bool,
        showMovingAverages: Bool = true,
        tradingViewPreferDesktop: Binding<Bool> = .constant(false)
    ) {
        self.selectedEngine = selectedEngine
        self.symbol = symbol ?? overlayModel.symbol
        self.closedCandles = closedCandles
        self.formingCandle = formingCandle
        self.fitRequestToken = fitRequestToken
        self.overlayModel = overlayModel
        self.replayMarkers = replayMarkers
        self.pricePrecision = pricePrecision
        self.timeframe = timeframe
        self.palette = palette
        self.isDark = isDark
        self.showMovingAverages = showMovingAverages
        self._tradingViewPreferDesktop = tradingViewPreferDesktop
    }

    public var body: some View {
        VStack(spacing: 0) {
            if selectedEngine != .tradingViewWeb {
                ChartCrosshairOHLCVHUD(
                    readout: crosshairReadout,
                    fallbackCandle: formingCandle ?? closedCandles.last,
                    overlayModel: overlayModel,
                    precision: pricePrecision,
                    palette: palette
                )
                Divider().overlay(palette.border)
            }

            // Lazy-instantiate ONLY the active engine (unselected engines are never created)
            switch selectedEngine {
            case .candleKit:
                CandleKitAdapterView(
                    candles: closedCandles,
                    formingCandle: formingCandle,
                    overlayModel: overlayModel,
                    timeframe: timeframe,
                    pricePrecision: pricePrecision,
                    palette: palette,
                    isDark: isDark,
                    resetTrigger: fitRequestToken,
                    onCrosshairChange: { readout in
                        crosshairReadout = readout
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .dgCharts:
                DGChartsAdapterView(
                    candles: closedCandles,
                    formingCandle: formingCandle,
                    overlayModel: overlayModel,
                    replayMarkers: replayMarkers,
                    timeframe: timeframe,
                    pricePrecision: pricePrecision,
                    palette: palette,
                    isDark: isDark,
                    resetTrigger: fitRequestToken,
                    onCrosshairChange: { readout in
                        crosshairReadout = readout
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .swiftTradingView:
                SwiftTradingViewAdapterView(
                    candles: closedCandles,
                    formingCandle: formingCandle,
                    overlayModel: overlayModel,
                    replayMarkers: replayMarkers,
                    timeframe: timeframe,
                    pricePrecision: pricePrecision,
                    palette: palette,
                    isDark: isDark,
                    resetTrigger: fitRequestToken,
                    showMovingAverages: showMovingAverages,
                    onCrosshairChange: { readout in
                        crosshairReadout = readout
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .tradingViewWeb:
                TradingViewWebAdapterView(
                    symbol: symbol,
                    timeframe: timeframe,
                    palette: palette,
                    isDark: isDark,
                    preferDesktop: $tradingViewPreferDesktop
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: selectedEngine) { _, _ in
            crosshairReadout = nil
        }
        .onChange(of: symbol) { _, _ in
            crosshairReadout = nil
        }
        .onChange(of: timeframe) { _, _ in
            crosshairReadout = nil
        }
    }
}
