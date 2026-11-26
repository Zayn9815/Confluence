import SwiftUI
import SignalEngine

/// Step-1 adapter stub for **CandleKit (Native SwiftUI Canvas)**.
/// Renders Confluence's native SwiftUI Canvas candlestick fallback + the universal Signal Level HUD
/// so Step 1 compiles 100% cleanly on CI without adding external SPM dependencies.
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
        // STEP 2 ADAPTER SLOT: Replace body with `CandleKit` Native SwiftUI Canvas chart
        // Exact inputs available:
        // - `candles: [Candle]` (closed UTC bars sorted ascending)
        // - `formingCandle: Candle?` (display-only active bar)
        // - `liveTick: LiveTick?` (latest foreground tick for incremental update)
        // - `overlayModel: ChartSignalOverlayModel` (Entry, SL, TP1/TP2, R:R, Trap price/zone, ICT structure events)
        // - `timeframe: Timeframe`
        // - `pricePrecision: ChartPricePrecision`
        // - `onCrosshairChange: (ChartCrosshairReadout?) -> Void`
        ZStack(alignment: .topLeading) {
            NativeCanvasFallbackChartView(
                candles: candles,
                formingCandle: formingCandle,
                overlayModel: overlayModel,
                pricePrecision: pricePrecision,
                palette: palette,
                onCrosshairChange: onCrosshairChange
            )

            ChartSignalOverlayHUD(
                overlayModel: overlayModel,
                precision: pricePrecision,
                palette: palette,
                engineBadge: "CandleKit · Step 2 Slot"
            )
            .padding(10)
        }
    }
}
