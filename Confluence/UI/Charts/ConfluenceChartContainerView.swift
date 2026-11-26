import SwiftUI
import LightweightCharts
import SignalEngine

/// Engine-agnostic chart container and lazy router.
/// Instantiates ONLY the currently selected `ChartEngineOption` engine for battery efficiency,
/// and layers the lightweight native SwiftUI top OHLCV + R:R crosshair HUD on top.
public struct ConfluenceChartContainerView: View {
    public let selectedEngine: ChartEngineOption
    public let closedCandles: [Candle]
    public let formingCandle: Candle?
    public let lastRolledOverCandle: Candle?
    public let liveTick: LiveTick?
    public let dataSetRevision: Int
    public let liveUpdateToken: Int
    public let fitRequestToken: Int
    public let overlayModel: ChartSignalOverlayModel
    public let replayMarkers: [SeriesMarker]
    public let pricePrecision: ChartPricePrecision
    public let timeframe: Timeframe
    public let providerTag: String
    public let palette: ConfluencePalette
    public let isDark: Bool
    public let onNeedOlderHistory: () -> Void

    @State private var crosshairReadout: ChartCrosshairReadout? = nil

    public init(
        selectedEngine: ChartEngineOption,
        closedCandles: [Candle],
        formingCandle: Candle?,
        lastRolledOverCandle: Candle? = nil,
        liveTick: LiveTick? = nil,
        dataSetRevision: Int,
        liveUpdateToken: Int,
        fitRequestToken: Int,
        overlayModel: ChartSignalOverlayModel,
        replayMarkers: [SeriesMarker] = [],
        pricePrecision: ChartPricePrecision,
        timeframe: Timeframe,
        providerTag: String,
        palette: ConfluencePalette,
        isDark: Bool,
        onNeedOlderHistory: @escaping () -> Void
    ) {
        self.selectedEngine = selectedEngine
        self.closedCandles = closedCandles
        self.formingCandle = formingCandle
        self.lastRolledOverCandle = lastRolledOverCandle
        self.liveTick = liveTick
        self.dataSetRevision = dataSetRevision
        self.liveUpdateToken = liveUpdateToken
        self.fitRequestToken = fitRequestToken
        self.overlayModel = overlayModel
        self.replayMarkers = replayMarkers
        self.pricePrecision = pricePrecision
        self.timeframe = timeframe
        self.providerTag = providerTag
        self.palette = palette
        self.isDark = isDark
        self.onNeedOlderHistory = onNeedOlderHistory
    }

    public var body: some View {
        VStack(spacing: 0) {
            ChartCrosshairOHLCVHUD(
                readout: crosshairReadout,
                fallbackCandle: formingCandle ?? closedCandles.last,
                overlayModel: overlayModel,
                precision: pricePrecision,
                palette: palette
            )
            Divider().overlay(palette.border)

            // Lazy-instantiate ONLY the active engine (unselected engines are never created)
            switch selectedEngine {
            case .lightweightCharts:
                LightweightChartsAdapterView(
                    closedCandles: closedCandles,
                    formingCandle: formingCandle,
                    lastRolledOverCandle: lastRolledOverCandle,
                    dataSetRevision: dataSetRevision,
                    liveUpdateToken: liveUpdateToken,
                    fitRequestToken: fitRequestToken,
                    overlayModel: overlayModel,
                    replayMarkers: replayMarkers,
                    pricePrecision: pricePrecision,
                    timeframe: timeframe,
                    providerTag: providerTag,
                    isDark: isDark,
                    onNeedOlderHistory: onNeedOlderHistory,
                    onCrosshairChange: { readout in
                        crosshairReadout = readout
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .dgCharts:
                DGChartsAdapterView(
                    candles: closedCandles,
                    formingCandle: formingCandle,
                    liveTick: liveTick,
                    overlayModel: overlayModel,
                    timeframe: timeframe,
                    pricePrecision: pricePrecision,
                    palette: palette,
                    isDark: isDark,
                    onCrosshairChange: { readout in
                        crosshairReadout = readout
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .swiftTradingView:
                SwiftTradingViewAdapterView(
                    candles: closedCandles,
                    formingCandle: formingCandle,
                    liveTick: liveTick,
                    overlayModel: overlayModel,
                    timeframe: timeframe,
                    pricePrecision: pricePrecision,
                    palette: palette,
                    isDark: isDark,
                    onCrosshairChange: { readout in
                        crosshairReadout = readout
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .candleKit:
                CandleKitAdapterView(
                    candles: closedCandles,
                    formingCandle: formingCandle,
                    liveTick: liveTick,
                    overlayModel: overlayModel,
                    timeframe: timeframe,
                    pricePrecision: pricePrecision,
                    palette: palette,
                    isDark: isDark,
                    onCrosshairChange: { readout in
                        crosshairReadout = readout
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
