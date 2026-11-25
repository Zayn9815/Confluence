import SwiftUI
import LightweightCharts
import SignalEngine

/// Tap-to-open Full-Screen Interactive Chart powered by `tradingview/LightweightChartsIOS` (v5.2.0).
/// Supports live in-chart Data Provider switching (Auto, Twelve Data, biquote.io, Yahoo Finance / Crypto venues),
/// Timeframe switching (15m / 1H / 4H / 1D), explicit horizontal/vertical pan & pinch-zoom,
/// exact intraday UTC time axis (`timeVisible: true`), and `.interactiveDismissDisabled(true)` sheet lock.
public struct FullScreenChartSheet: View {
    let signal: TradeSignal
    let palette: ConfluencePalette
    let coordinator: MarketScannerCoordinator?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var activeCandles: [Candle]
    @State private var activeTimeframe: Timeframe
    @State private var activeProviderName: String
    @State private var selectedProvider: ChartProviderChoice = .auto
    @State private var proxySymbolUsed: String? = nil
    @State private var isLoadingCandles: Bool = false
    @State private var loadError: String? = nil

    public init(
        signal: TradeSignal,
        palette: ConfluencePalette,
        coordinator: MarketScannerCoordinator? = nil
    ) {
        self.signal = signal
        self.palette = palette
        self.coordinator = coordinator
        _activeCandles = State(initialValue: signal.recentCandles)
        _activeTimeframe = State(initialValue: signal.timeframe)
        _activeProviderName = State(initialValue: signal.dataProvider)
    }

    private var shouldShowSignalLevels: Bool {
        proxySymbolUsed == nil
    }

    private var lastClosedUTCLabel: String {
        guard let last = activeCandles.sorted(by: { $0.closeTimeEpochSeconds < $1.closeTimeEpochSeconds }).last else {
            return "No closed bars"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = activeTimeframe == .d1 ? "MMM d 'UTC'" : "HH:mm 'UTC'"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return "Closed \(formatter.string(from: Date(timeIntervalSince1970: last.closeTimeEpochSeconds)))"
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header numeric ribbon (hidden if viewing an ETF proxy with a different price scale)
                if let lv = signal.levels, shouldShowSignalLevels {
                    let dec = PriceFormatHelper.decimals(for: signal.symbol)
                    HStack(spacing: 12) {
                        levelPill("ENTRY", PriceFormatHelper.format(lv.entryMid, decimals: dec), palette.champagneGold)
                        levelPill("SL", PriceFormatHelper.format(lv.stopLoss, decimals: dec), palette.shortCrimson)
                        levelPill("TP1", PriceFormatHelper.format(lv.tp1, decimals: dec), palette.longEmerald)
                        levelPill("TP2", PriceFormatHelper.format(lv.tp2, decimals: dec), palette.macroIceBlue)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(palette.surface)
                    Divider().overlay(palette.border)
                }

                // Live Timeframe & Provider Switcher Bar
                if coordinator != nil {
                    chartControlsBar
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(palette.surface)
                    Divider().overlay(palette.border)
                }

                // ETF Proxy Notice Banner
                if let proxy = proxySymbolUsed {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(palette.trapAmber)
                        Text("ETF Proxy: \(proxy) (Twelve Data Basic Plan) — index SL/TP lines hidden to avoid scale mismatch.")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(palette.primaryInk)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(palette.trapAmber.opacity(0.14))
                }

                // Inline Load Error Notice
                if let err = loadError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(palette.shortCrimson)
                        Text(err)
                            .font(.caption2)
                            .foregroundStyle(palette.primaryInk)
                            .lineLimit(2)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(palette.shortCrimson.opacity(0.14))
                }

                // Main Interactive LightweightCharts Surface
                ZStack {
                    LightweightChartContainer(
                        candles: activeCandles,
                        levels: shouldShowSignalLevels ? signal.levels : nil,
                        overlays: shouldShowSignalLevels ? signal.overlays : ChartOverlayData(),
                        timeframe: activeTimeframe,
                        providerTag: activeProviderName,
                        isDark: colorScheme == .dark
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if isLoadingCandles {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(palette.champagneGold)
                            Text("Loading \(activeTimeframe.displayLabel)...")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(palette.primaryInk)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                }

                // Footer: TradingView Attribution + Exact Closed Candle UTC
                HStack(spacing: 8) {
                    Text("TradingView Lightweight Charts")
                        .font(.caption2)
                        .foregroundStyle(palette.tertiaryInk)
                        .lineLimit(1)
                    Spacer()
                    Text("\(activeTimeframe.displayLabel) · \(activeProviderName) · \(lastClosedUTCLabel)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(palette.secondaryInk)
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(palette.surface)
            }
            .background(palette.canvas)
            .navigationTitle("\(signal.symbol) · \(activeTimeframe.displayLabel)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if coordinator != nil {
                        Button {
                            Task { await reloadChartData() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.subheadline.weight(.semibold))
                        }
                        .disabled(isLoadingCandles)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .interactiveDismissDisabled(true)
    }

    private var chartControlsBar: some View {
        HStack(spacing: 8) {
            // Timeframe pills
            HStack(spacing: 4) {
                ForEach(Timeframe.allCases, id: \.self) { tf in
                    let isSelected = (activeTimeframe == tf)
                    Button {
                        guard activeTimeframe != tf else { return }
                        activeTimeframe = tf
                        Task { await reloadChartData() }
                    } label: {
                        Text(tf.displayLabel)
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(isSelected ? palette.canvas : palette.secondaryInk)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(isSelected ? palette.champagneGold : palette.elevatedSurface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoadingCandles)
                }
            }

            Spacer()

            // Data Provider Switcher Menu
            Menu {
                ForEach(ChartProviderChoice.choices(for: signal.marketClass)) { choice in
                    Button {
                        selectedProvider = choice
                        Task { await reloadChartData() }
                    } label: {
                        if selectedProvider == choice {
                            Label(choice.rawValue, systemImage: "checkmark")
                        } else {
                            Text(choice.rawValue)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.caption2)
                    Text(selectedProvider.rawValue)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(palette.primaryInk)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(palette.elevatedSurface, in: Capsule())
                .overlay(Capsule().strokeBorder(palette.border, lineWidth: 0.75))
            }
            .disabled(isLoadingCandles)
        }
    }

    private func reloadChartData() async {
        guard let coordinator else { return }
        isLoadingCandles = true
        loadError = nil
        defer { isLoadingCandles = false }

        do {
            let res = try await coordinator.fetchChartCandles(
                symbol: signal.symbol,
                timeframe: activeTimeframe,
                providerChoice: selectedProvider
            )
            guard !res.candles.isEmpty else {
                loadError = "Provider returned 0 closed candles for \(signal.symbol)."
                return
            }
            activeCandles = res.candles
            activeProviderName = res.providerName
            proxySymbolUsed = res.proxySymbolUsed
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func levelPill(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(palette.primaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LightweightChartContainer: UIViewRepresentable {
    let candles: [Candle]
    let levels: TradeLevels?
    let overlays: ChartOverlayData
    let timeframe: Timeframe
    let providerTag: String
    let isDark: Bool

    final class Coordinator {
        var series: CandlestickSeries?
        var priceLines: [PriceLine] = []
        var lastSignature: String = ""
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> LightweightCharts {
        let bgHex: UInt32 = isDark ? 0x0B0D11 : 0xF6F7F9
        let textHex: UInt32 = isDark ? 0x9CA7BA : 0x374151
        let gridHex: UInt32 = isDark ? 0x1B2230 : 0xE5E7EB

        let options = ChartOptions(
            autoSize: true,
            layout: .init(
                background: .solid(color: ChartColor(hex: bgHex)),
                textColor: ChartColor(hex: textHex)
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

        let chartView = LightweightCharts(options: options)
        let seriesOptions = CandlestickSeriesOptions(
            upColor: ChartColor(hex: 0x10B981),
            downColor: ChartColor(hex: 0xEF4444),
            wickUpColor: ChartColor(hex: 0x10B981),
            wickDownColor: ChartColor(hex: 0xEF4444)
        )

        let series = chartView.addCandlestickSeries(options: seriesOptions)
        context.coordinator.series = series
        applyData(to: chartView, coordinator: context.coordinator)
        return chartView
    }

    func updateUIView(_ uiView: LightweightCharts, context: Context) {
        let sig = renderSignature
        guard context.coordinator.lastSignature != sig else { return }
        applyData(to: uiView, coordinator: context.coordinator)
    }

    private var renderSignature: String {
        let firstTS = candles.first?.openTimeEpochSeconds ?? 0
        let lastTS = candles.last?.closeTimeEpochSeconds ?? 0
        let hasLevels = levels != nil ? "1" : "0"
        return "\(timeframe.rawValue)|\(providerTag)|\(candles.count)|\(Int(firstTS))|\(Int(lastTS))|\(hasLevels)|\(isDark)"
    }

    private func applyData(to chartView: LightweightCharts, coordinator: Coordinator) {
        guard let series = coordinator.series else { return }
        coordinator.lastSignature = renderSignature

        let data = candles
            .sorted { $0.openTimeEpochSeconds < $1.openTimeEpochSeconds }
            .map { bar in
                CandlestickData(
                    time: .utc(timestamp: bar.openTimeEpochSeconds),
                    open: bar.open,
                    high: bar.high,
                    low: bar.low,
                    close: bar.close
                )
            }
        series.setData(data: data)

        // Update time axis visibility when switching between intraday and 1D
        chartView.timeScale().applyOptions(options: TimeScaleOptions(
            timeVisible: timeframe != .d1,
            secondsVisible: false
        ))

        // Remove prior price lines before applying current set
        for oldLine in coordinator.priceLines {
            series.removePriceLine(line: oldLine)
        }
        coordinator.priceLines.removeAll()

        if let lv = levels {
            coordinator.priceLines.append(series.createPriceLine(options: PriceLineOptions(
                price: lv.entryMid,
                color: ChartColor(hex: 0xD4AF37),
                lineWidth: .one,
                lineStyle: .dashed,
                axisLabelVisible: true,
                title: "ENTRY"
            )))
            coordinator.priceLines.append(series.createPriceLine(options: PriceLineOptions(
                price: lv.stopLoss,
                color: ChartColor(hex: 0xEF4444),
                lineWidth: .two,
                lineStyle: .solid,
                axisLabelVisible: true,
                title: "SL"
            )))
            coordinator.priceLines.append(series.createPriceLine(options: PriceLineOptions(
                price: lv.tp1,
                color: ChartColor(hex: 0x10B981),
                lineWidth: .two,
                lineStyle: .solid,
                axisLabelVisible: true,
                title: "TP1"
            )))
            coordinator.priceLines.append(series.createPriceLine(options: PriceLineOptions(
                price: lv.tp2,
                color: ChartColor(hex: 0x38BDF8),
                lineWidth: .one,
                lineStyle: .dashed,
                axisLabelVisible: true,
                title: "TP2"
            )))
        }

        for trap in overlays.traps where trap.isActionable {
            coordinator.priceLines.append(series.createPriceLine(options: PriceLineOptions(
                price: trap.level,
                color: ChartColor(hex: 0xF59E0B),
                lineWidth: .one,
                lineStyle: .dotted,
                axisLabelVisible: true,
                title: trap.direction.rawValue
            )))
        }

        chartView.timeScale().fitContent()
    }
}
