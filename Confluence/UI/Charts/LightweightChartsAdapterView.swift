import SwiftUI
import UIKit
import LightweightCharts
import SignalEngine

/// Upgraded `LightweightChartsIOS` v5.2+ `UIViewRepresentable` bridge:
/// - In-place live tick updates via `series.update(bar:)` (including clean rollover sealing) without calling `setData(...)` on ticks.
/// - Crisp horizontal price lines (`createPriceLine`) with right-axis badges for Entry, SL, TP1, TP2, BE, Trap, and in-place Live price updates.
/// - Candle markers (`createMarkersPlugin`) for Buy/Sell entry, Trap detection, ICT structure events (BOS / CHoCH / Liquidity Sweep), and Trade Replay pins.
/// - Native `crosshairMoveEvents` (`subscribeCrosshairMove`) wired to the SwiftUI top OHLCV + R:R HUD.
public struct LightweightChartsAdapterView: UIViewRepresentable {
    public let closedCandles: [Candle]
    public let formingCandle: Candle?
    public let lastRolledOverCandle: Candle?
    public let dataSetRevision: Int
    public let liveUpdateToken: Int
    public let fitRequestToken: Int
    public let overlayModel: ChartSignalOverlayModel
    public let replayMarkers: [SeriesMarker]
    public let pricePrecision: ChartPricePrecision
    public let timeframe: Timeframe
    public let providerTag: String
    public let isDark: Bool
    public let onNeedOlderHistory: () -> Void
    public let onCrosshairChange: (ChartCrosshairReadout?) -> Void

    public init(
        closedCandles: [Candle],
        formingCandle: Candle?,
        lastRolledOverCandle: Candle? = nil,
        dataSetRevision: Int,
        liveUpdateToken: Int,
        fitRequestToken: Int,
        overlayModel: ChartSignalOverlayModel,
        replayMarkers: [SeriesMarker] = [],
        pricePrecision: ChartPricePrecision,
        timeframe: Timeframe,
        providerTag: String,
        isDark: Bool,
        onNeedOlderHistory: @escaping () -> Void,
        onCrosshairChange: @escaping (ChartCrosshairReadout?) -> Void
    ) {
        self.closedCandles = closedCandles
        self.formingCandle = formingCandle
        self.lastRolledOverCandle = lastRolledOverCandle
        self.dataSetRevision = dataSetRevision
        self.liveUpdateToken = liveUpdateToken
        self.fitRequestToken = fitRequestToken
        self.overlayModel = overlayModel
        self.replayMarkers = replayMarkers
        self.pricePrecision = pricePrecision
        self.timeframe = timeframe
        self.providerTag = providerTag
        self.isDark = isDark
        self.onNeedOlderHistory = onNeedOlderHistory
        self.onCrosshairChange = onCrosshairChange
    }

    @MainActor
    public final class Coordinator: NSObject, TimeScaleDelegate {
        var series: CandlestickSeries?
        var markersPlugin: SeriesMarkersPlugin<CandlestickSeries>?
        var priceLines: [PriceLine] = []
        var livePriceLine: PriceLine?
        var lastLiveLinePrice: Double?
        var lastLiveLineBullish: Bool?
        var lastDataSignature: String = ""
        var lastThemeDark: Bool?
        var lastOverlaySignature: String = ""
        var lastLiveToken: Int = -1
        var lastFitToken: Int = -1
        var lastRolledOverEpoch: TimeInterval?
        var onNeedOlderHistory: (() -> Void)?
        var onCrosshairChange: ((ChartCrosshairReadout?) -> Void)?
        var crosshairTask: Task<Void, Never>?

        public func didVisibleTimeRangeChange(onTimeScale timeScale: TimeScaleApi, parameters: TimeRange?) {}

        public func didVisibleLogicalRangeChange(onTimeScale timeScale: TimeScaleApi, parameters: LogicalRange?) {
            guard let from = parameters?.from else { return }
            if from <= ChartPagingPolicy.triggerBarsBeforeLeftEdge {
                onNeedOlderHistory?()
            }
        }

        public func didReceiveTimeScaleSizeChangeWithParameters(onTimeScale timeScale: TimeScaleApi, parameters: LWCChartRectangle?) {}
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeUIView(context: Context) -> LightweightCharts {
        let options = makeChartOptions(isDark: isDark)
        let chartView = LightweightCharts(options: options)
        let builtInFormat = PriceFormat.builtIn(BuiltInPriceFormat(
            type: .price,
            precision: Double(pricePrecision.precision),
            minMove: pricePrecision.minMove
        ))
        let seriesOptions = CandlestickSeriesOptions(
            priceFormat: builtInFormat,
            autoscaleInfoProvider: buildAutoscaleProvider(),
            upColor: ChartColor(hex: 0x10B981),
            downColor: ChartColor(hex: 0xEF4444),
            wickUpColor: ChartColor(hex: 0x10B981),
            wickDownColor: ChartColor(hex: 0xEF4444)
        )

        let series = chartView.addCandlestickSeries(options: seriesOptions)
        let coord = context.coordinator
        coord.series = series
        coord.lastThemeDark = isDark
        coord.onNeedOlderHistory = onNeedOlderHistory
        coord.onCrosshairChange = onCrosshairChange

        let timeScale = chartView.timeScale()
        timeScale.delegate = coord
        timeScale.subscribeVisibleLogicalRangeChange()

        // Wire native LightweightCharts v5.2 crosshair stream (auto-manages subscribeCrosshairMove)
        let stream = chartView.crosshairMoveEvents
        coord.crosshairTask = Task { @MainActor [weak coord] in
            for await params in stream {
                guard !Task.isCancelled, let coord, let activeSeries = coord.series else { break }
                if let barData = params.data(forSeries: activeSeries),
                   let o = barData.open, let h = barData.high, let l = barData.low, let c = barData.close,
                   o.isFinite, h.isFinite, l.isFinite, c.isFinite {
                    let epoch: TimeInterval?
                    if case .utc(let ts) = params.time {
                        epoch = ts
                    } else {
                        epoch = nil
                    }
                    coord.onCrosshairChange?(ChartCrosshairReadout(
                        epochSeconds: epoch,
                        open: o,
                        high: h,
                        low: l,
                        close: c
                    ))
                } else {
                    coord.onCrosshairChange?(nil)
                }
            }
        }

        applyFullData(to: chartView, coordinator: coord, shouldFit: true)
        applyOverlays(to: chartView, coordinator: coord)
        updateLivePriceLine(coordinator: coord)
        return chartView
    }

    public func updateUIView(_ uiView: LightweightCharts, context: Context) {
        let coord = context.coordinator
        coord.onNeedOlderHistory = onNeedOlderHistory
        coord.onCrosshairChange = onCrosshairChange

        // Apply theme updates in-place without calling setData() or tearing down the chart
        if coord.lastThemeDark != isDark {
            coord.lastThemeDark = isDark
            uiView.applyOptions(options: makeChartOptions(isDark: isDark))
        }

        let dataSig = "\(dataSetRevision)|\(timeframe.rawValue)|\(providerTag)|\(pricePrecision.precision)"
        let shouldFit = (coord.lastFitToken != fitRequestToken)

        if coord.lastDataSignature != dataSig {
            applyFullData(to: uiView, coordinator: coord, shouldFit: shouldFit)
        } else if shouldFit {
            coord.lastFitToken = fitRequestToken
            uiView.priceScale(priceScaleId: "right").setAutoScale(on: true)
            uiView.timeScale().fitContent()
            uiView.timeScale().scrollToRealTime()
        }

        // Incremental display-only live candle update via native series.update(bar:)
        if coord.lastLiveToken != liveUpdateToken, let series = coord.series {
            coord.lastLiveToken = liveUpdateToken
            if let rolled = lastRolledOverCandle, coord.lastRolledOverEpoch != rolled.openTimeEpochSeconds {
                coord.lastRolledOverEpoch = rolled.openTimeEpochSeconds
                series.update(bar: CandlestickData(
                    time: .utc(timestamp: rolled.openTimeEpochSeconds),
                    open: rolled.open,
                    high: rolled.high,
                    low: rolled.low,
                    close: rolled.close
                ))
            }
            if let forming = formingCandle {
                series.update(bar: CandlestickData(
                    time: .utc(timestamp: forming.openTimeEpochSeconds),
                    open: forming.open,
                    high: forming.high,
                    low: forming.low,
                    close: forming.close
                ))
            }
        }

        let overlaySig = buildOverlaySignature()
        if coord.lastOverlaySignature != overlaySig {
            applyOverlays(to: uiView, coordinator: coord)
        }
        updateLivePriceLine(coordinator: coord)
    }

    public static func dismantleUIView(_ uiView: LightweightCharts, coordinator: Coordinator) {
        coordinator.crosshairTask?.cancel()
        coordinator.crosshairTask = nil
        coordinator.onNeedOlderHistory = nil
        coordinator.onCrosshairChange = nil
        uiView.timeScale().delegate = nil
    }

    private func makeChartOptions(isDark: Bool) -> ChartOptions {
        let bgHex: UInt32 = isDark ? 0x0B0D11 : 0xF6F7F9
        let textHex: UInt32 = isDark ? 0x9CA7BA : 0x374151
        let gridHex: UInt32 = isDark ? 0x1B2230 : 0xE5E7EB

        return ChartOptions(
            autoSize: true,
            layout: .init(
                background: .solid(color: ChartColor(hex: bgHex)),
                textColor: ChartColor(hex: textHex)
            ),
            rightPriceScale: VisiblePriceScaleOptions(
                autoScale: true,
                alignLabels: true,
                scaleMargins: PriceScaleMargins(top: 0.11, bottom: 0.11),
                borderVisible: true,
                entireTextOnly: true,
                minimumWidth: pricePrecision.minimumPriceScaleWidth
            ),
            timeScale: TimeScaleOptions(
                timeVisible: timeframe != .d1,
                secondsVisible: false
            ),
            grid: GridOptions(
                verticalLines: GridLineOptions(color: ChartColor(hex: gridHex)),
                horizontalLines: GridLineOptions(color: ChartColor(hex: gridHex))
            ),
            handleScroll: .options(.init(
                mouseWheel: true,
                pressedMouseMove: true,
                horzTouchDrag: true,
                vertTouchDrag: true
            )),
            handleScale: .options(.init(
                mouseWheel: true,
                pinch: true,
                axisPressedMouseMove: .enabled(true),
                axisDoubleClickReset: .enabled(true)
            ))
        )
    }

    private func buildAutoscaleProvider() -> AutoscaleInfoProvider {
        var corePrices: [Double] = []
        if let e = overlayModel.entryPrice { corePrices.append(e) }
        if let sl = overlayModel.stopLoss { corePrices.append(sl) }
        if let tp1 = overlayModel.takeProfit1 { corePrices.append(tp1) }
        if overlayModel.isTP2Enabled, let tp2 = overlayModel.takeProfit2 { corePrices.append(tp2) }
        for trap in overlayModel.traps where trap.isActionable {
            corePrices.append(trap.price)
        }
        let js = ChartAutoscaleScriptBuilder.makeProviderJS(corePrices: corePrices, maxDeviationFraction: 0.20)
        return AutoscaleInfoProvider(.javaScript(js))
    }

    private func buildOverlaySignature() -> String {
        let e = overlayModel.entryPrice.map { String(format: "%.8f", $0) } ?? "n"
        let sl = overlayModel.stopLoss.map { String(format: "%.8f", $0) } ?? "n"
        let tp1 = overlayModel.takeProfit1.map { String(format: "%.8f", $0) } ?? "n"
        let tp2 = overlayModel.isTP2Enabled ? (overlayModel.takeProfit2.map { String(format: "%.8f", $0) } ?? "n") : "off"
        let trapSig = overlayModel.traps.filter(\.isActionable).map { "\($0.id):\($0.price)" }.joined(separator: ",")
        let structSig = overlayModel.structureEvents.map { "\($0.id):\($0.timestampEpochSeconds)" }.joined(separator: ",")
        let beSig = overlayModel.breakevenPrice.map { String(format: "%.8f", $0) } ?? "n"
        return "\(e)|\(sl)|\(tp1)|\(tp2)|\(trapSig)|\(structSig)|\(beSig)|\(replayMarkers.count)|\(closedCandles.count)"
    }

    private func applyFullData(to chartView: LightweightCharts, coordinator: Coordinator, shouldFit: Bool) {
        guard let series = coordinator.series else { return }
        coordinator.lastDataSignature = "\(dataSetRevision)|\(timeframe.rawValue)|\(providerTag)|\(pricePrecision.precision)"

        let builtInFormat = PriceFormat.builtIn(BuiltInPriceFormat(
            type: .price,
            precision: Double(pricePrecision.precision),
            minMove: pricePrecision.minMove
        ))
        series.applyOptions(options: CandlestickSeriesOptions(
            priceFormat: builtInFormat,
            autoscaleInfoProvider: buildAutoscaleProvider()
        ))
        series.priceScale().applyOptions(options: PriceScaleOptions(
            autoScale: true,
            alignLabels: true,
            scaleMargins: PriceScaleMargins(top: 0.11, bottom: 0.11),
            borderVisible: true,
            entireTextOnly: true,
            minimumWidth: pricePrecision.minimumPriceScaleWidth
        ))

        var allBars = closedCandles.sorted { $0.openTimeEpochSeconds < $1.openTimeEpochSeconds }
        if let forming = formingCandle,
           (allBars.last?.openTimeEpochSeconds ?? -1) < forming.openTimeEpochSeconds {
            allBars.append(forming)
        }

        let data = allBars.map { bar in
            CandlestickData(
                time: .utc(timestamp: bar.openTimeEpochSeconds),
                open: bar.open,
                high: bar.high,
                low: bar.low,
                close: bar.close
            )
        }
        series.setData(data: data)

        chartView.timeScale().applyOptions(options: TimeScaleOptions(
            timeVisible: timeframe != .d1,
            secondsVisible: false
        ))

        if shouldFit {
            coordinator.lastFitToken = fitRequestToken
            chartView.timeScale().fitContent()
        }
    }

    private func applyOverlays(to chartView: LightweightCharts, coordinator: Coordinator) {
        guard let series = coordinator.series else { return }
        coordinator.lastOverlaySignature = buildOverlaySignature()

        for oldLine in coordinator.priceLines {
            series.removePriceLine(line: oldLine)
        }
        coordinator.priceLines.removeAll()

        if let entry = overlayModel.entryPrice {
            coordinator.priceLines.append(series.createPriceLine(options: PriceLineOptions(
                price: entry,
                color: ChartColor(hex: 0xD4AF37),
                lineWidth: .one,
                lineStyle: .dashed,
                axisLabelVisible: true,
                title: "ENTRY"
            )))
        }
        if let sl = overlayModel.stopLoss {
            coordinator.priceLines.append(series.createPriceLine(options: PriceLineOptions(
                price: sl,
                color: ChartColor(hex: 0xEF4444),
                lineWidth: .two,
                lineStyle: .solid,
                axisLabelVisible: true,
                title: "SL"
            )))
        }
        if let tp1 = overlayModel.takeProfit1 {
            coordinator.priceLines.append(series.createPriceLine(options: PriceLineOptions(
                price: tp1,
                color: ChartColor(hex: 0x10B981),
                lineWidth: .two,
                lineStyle: .solid,
                axisLabelVisible: true,
                title: "TP1"
            )))
        }
        if overlayModel.isTP2Enabled, let tp2 = overlayModel.takeProfit2 {
            coordinator.priceLines.append(series.createPriceLine(options: PriceLineOptions(
                price: tp2,
                color: ChartColor(hex: 0x38BDF8),
                lineWidth: .one,
                lineStyle: .dashed,
                axisLabelVisible: true,
                title: "TP2"
            )))
        }
        if let be = overlayModel.breakevenPrice {
            coordinator.priceLines.append(series.createPriceLine(options: PriceLineOptions(
                price: be,
                color: ChartColor(hex: 0x38BDF8),
                lineWidth: .one,
                lineStyle: .dashed,
                axisLabelVisible: true,
                title: "BE"
            )))
        }
        for trap in overlayModel.traps where trap.isActionable {
            coordinator.priceLines.append(series.createPriceLine(options: PriceLineOptions(
                price: trap.price,
                color: ChartColor(hex: 0xF59E0B),
                lineWidth: .one,
                lineStyle: .dashed,
                axisLabelVisible: true,
                title: trap.label
            )))
        }

        // Combined candle markers: Trade Replay pins + Buy/Sell Entry + Traps + ICT BOS/CHoCH/Liquidity Sweeps
        let combinedMarkers = buildCombinedMarkers()
        if !combinedMarkers.isEmpty {
            if let plugin = coordinator.markersPlugin {
                plugin.setMarkers(combinedMarkers)
            } else {
                coordinator.markersPlugin = series.createMarkersPlugin(
                    data: combinedMarkers,
                    options: SeriesMarkersOptions(active: true, autoScale: false)
                )
            }
        } else if let plugin = coordinator.markersPlugin {
            plugin.setMarkers([])
        }
    }

    private func buildCombinedMarkers() -> [SeriesMarker] {
        let sortedBars = closedCandles.sorted { $0.openTimeEpochSeconds < $1.openTimeEpochSeconds }
        guard let firstOpen = sortedBars.first?.openTimeEpochSeconds,
              let lastClose = sortedBars.last?.closeTimeEpochSeconds
        else {
            return replayMarkers
        }

        func snapBarOpen(for targetEpoch: TimeInterval) -> TimeInterval? {
            let tfSec = timeframe.seconds
            guard targetEpoch >= firstOpen - tfSec, targetEpoch <= lastClose + tfSec else { return nil }
            if let exact = sortedBars.first(where: { abs($0.openTimeEpochSeconds - targetEpoch) <= 1.0 }) {
                return exact.openTimeEpochSeconds
            }
            if let containing = sortedBars.first(where: { $0.openTimeEpochSeconds <= targetEpoch && targetEpoch <= $0.closeTimeEpochSeconds }) {
                return containing.openTimeEpochSeconds
            }
            return sortedBars.min { abs($0.openTimeEpochSeconds - targetEpoch) < abs($1.openTimeEpochSeconds - targetEpoch) }?.openTimeEpochSeconds
        }

        var timed: [(ts: TimeInterval, marker: SeriesMarker)] = []

        // 1. Trade replay markers take priority when present
        if !replayMarkers.isEmpty {
            for m in replayMarkers {
                if case .utc(let ts) = m.time {
                    timed.append((ts, m))
                }
            }
        } else if let dir = overlayModel.direction, dir != .neutral,
                  let entryTS = overlayModel.entryTimestamp,
                  let snapped = snapBarOpen(for: entryTS) {
            // 2. Active Buy/Sell Signal Entry marker
            let isLong = (dir == .long)
            timed.append((snapped, SeriesMarker(
                time: .utc(timestamp: snapped),
                position: isLong ? .belowBar : .aboveBar,
                shape: isLong ? .arrowUp : .arrowDown,
                color: ChartColor(hex: isLong ? 0x10B981 : 0xEF4444),
                id: "signal-entry-\(Int(snapped))",
                text: isLong ? "BUY" : "SELL",
                size: 1.4
            )))
        }

        // 3. Actionable Trap detection markers
        for trap in overlayModel.traps where trap.isActionable {
            guard let snapped = snapBarOpen(for: trap.timestampEpochSeconds) else { continue }
            let isBullTrap = (trap.direction == .bullTrap)
            timed.append((snapped, SeriesMarker(
                time: .utc(timestamp: snapped),
                position: isBullTrap ? .aboveBar : .belowBar,
                shape: .circle,
                color: ChartColor(hex: 0xF59E0B),
                id: "trap-marker-\(trap.id)",
                text: isBullTrap ? "BULL TRAP" : "BEAR TRAP",
                size: 1.2
            )))
        }

        // 4. ICT Structure Event markers (BOS / CHoCH / Liquidity Sweep)
        for ev in overlayModel.structureEvents {
            guard let snapped = snapBarOpen(for: ev.timestampEpochSeconds) else { continue }
            let isBull = (ev.direction == .long)
            let hex: UInt32
            let shape: SeriesMarkerShape
            switch ev.kind {
            case .bos:
                hex = isBull ? 0x10B981 : 0xEF4444
                shape = isBull ? .arrowUp : .arrowDown
            case .choch:
                hex = 0x38BDF8
                shape = .square
            case .liquiditySweep:
                hex = 0xD4AF37
                shape = .circle
            }
            timed.append((snapped, SeriesMarker(
                time: .utc(timestamp: snapped),
                position: isBull ? .belowBar : .aboveBar,
                shape: shape,
                color: ChartColor(hex: hex),
                id: "ict-\(ev.id)",
                text: ev.label,
                size: 1.0
            )))
        }

        return timed.sorted { $0.ts < $1.ts }.map(\.marker)
    }

    private func updateLivePriceLine(coordinator: Coordinator) {
        guard let series = coordinator.series else { return }
        guard let lp = overlayModel.livePrice, lp.isFinite, lp > 0 else {
            if let existing = coordinator.livePriceLine {
                series.removePriceLine(line: existing)
                coordinator.livePriceLine = nil
                coordinator.lastLiveLinePrice = nil
                coordinator.lastLiveLineBullish = nil
            }
            return
        }

        let ref = closedCandles.last?.close ?? lp
        let isBullish = (lp >= ref)
        // Skip redundant JS bridge calls when live price & color have not changed
        if coordinator.lastLiveLinePrice == lp && coordinator.lastLiveLineBullish == isBullish && coordinator.livePriceLine != nil {
            return
        }
        coordinator.lastLiveLinePrice = lp
        coordinator.lastLiveLineBullish = isBullish

        let colorHex: UInt32 = isBullish ? 0x10B981 : 0xEF4444
        let opts = PriceLineOptions(
            price: lp,
            color: ChartColor(hex: colorHex),
            lineWidth: .one,
            lineStyle: .dashed,
            axisLabelVisible: true,
            title: "LIVE"
        )
        if let existing = coordinator.livePriceLine {
            existing.applyOptions(options: opts)
        } else {
            coordinator.livePriceLine = series.createPriceLine(options: opts)
        }
    }
}
