import SwiftUI
import LightweightCharts
import SignalEngine

/// Pure deterministic helper that snaps Trade Replay Entry & Exit timestamps onto the exact
/// sorted closed candles present on the chart, producing v5.2.0 `SeriesMarker` pins.
public enum TradeReplayMarkerBuilder {
    public struct BuildResult: Sendable {
        public let markers: [SeriesMarker]
        public let hasEntryBar: Bool
        public let hasExitBar: Bool
    }

    public static func buildMarkers(
        for trade: StrategyTradeItem,
        candles: [Candle]
    ) -> BuildResult {
        let sorted = candles.sorted { $0.openTimeEpochSeconds < $1.openTimeEpochSeconds }
        guard !sorted.isEmpty else {
            return BuildResult(markers: [], hasEntryBar: false, hasExitBar: false)
        }

        let tfSec = trade.timeframe.seconds
        let firstOpen = sorted.first!.openTimeEpochSeconds
        let lastClose = sorted.last!.closeTimeEpochSeconds

        func snapCandle(forCloseEpoch targetClose: TimeInterval) -> Candle? {
            // Only snap if targetClose falls within the visible candle window (with 1-bar tolerance)
            guard targetClose >= firstOpen - tfSec && targetClose <= lastClose + tfSec else {
                return nil
            }
            if let exact = sorted.first(where: { abs($0.closeTimeEpochSeconds - targetClose) <= 1.0 }) {
                return exact
            }
            // Nearest candle whose open <= targetClose <= close (or closest by closeTime)
            if let containing = sorted.first(where: { $0.openTimeEpochSeconds <= targetClose && targetClose <= $0.closeTimeEpochSeconds }) {
                return containing
            }
            return sorted.min { abs($0.closeTimeEpochSeconds - targetClose) < abs($1.closeTimeEpochSeconds - targetClose) }
        }

        var raw: [(ts: TimeInterval, marker: SeriesMarker)] = []
        var hasEntry = false
        var hasExit = false

        if let entryBar = snapCandle(forCloseEpoch: trade.entryEpochSeconds) {
            hasEntry = true
            let isLong = (trade.direction == .long)
            let entryMarker = SeriesMarker(
                time: .utc(timestamp: entryBar.openTimeEpochSeconds),
                position: isLong ? .belowBar : .aboveBar,
                shape: isLong ? .arrowUp : .arrowDown,
                color: ChartColor(hex: 0xD4AF37),
                id: "entry-\(trade.fingerprint)",
                text: isLong ? "ENTRY LONG" : "ENTRY SHORT",
                size: 1.5
            )
            raw.append((entryBar.openTimeEpochSeconds, entryMarker))
        }

        if let exitTS = trade.exitEpochSeconds,
           !trade.status.isActive,
           let exitBar = snapCandle(forCloseEpoch: exitTS) {
            hasExit = true
            let isLong = (trade.direction == .long)
            let rText = String(format: "%+.2fR", trade.netRMultiple)
            let exitMarker: SeriesMarker
            switch trade.status {
            case .tp2Win:
                exitMarker = SeriesMarker(
                    time: .utc(timestamp: exitBar.openTimeEpochSeconds),
                    position: isLong ? .aboveBar : .belowBar,
                    shape: .circle,
                    color: ChartColor(hex: 0x10B981),
                    id: "exit-\(trade.fingerprint)",
                    text: "TP2 WIN \(rText)",
                    size: 1.6
                )
            case .tp1Win:
                exitMarker = SeriesMarker(
                    time: .utc(timestamp: exitBar.openTimeEpochSeconds),
                    position: isLong ? .aboveBar : .belowBar,
                    shape: .circle,
                    color: ChartColor(hex: 0x10B981),
                    id: "exit-\(trade.fingerprint)",
                    text: "TP1 WIN \(rText)",
                    size: 1.6
                )
            case .slLoss:
                exitMarker = SeriesMarker(
                    time: .utc(timestamp: exitBar.openTimeEpochSeconds),
                    position: isLong ? .belowBar : .aboveBar,
                    shape: .square,
                    color: ChartColor(hex: 0xEF4444),
                    id: "exit-\(trade.fingerprint)",
                    text: "SL HIT \(rText)",
                    size: 1.6
                )
            case .expired:
                exitMarker = SeriesMarker(
                    time: .utc(timestamp: exitBar.openTimeEpochSeconds),
                    position: .aboveBar,
                    shape: .square,
                    color: ChartColor(hex: 0x9CA7BA),
                    id: "exit-\(trade.fingerprint)",
                    text: "EXPIRED",
                    size: 1.2
                )
            case .notFilled:
                exitMarker = SeriesMarker(
                    time: .utc(timestamp: exitBar.openTimeEpochSeconds),
                    position: .aboveBar,
                    shape: .square,
                    color: ChartColor(hex: 0x9CA7BA),
                    id: "exit-\(trade.fingerprint)",
                    text: "NOT FILLED",
                    size: 1.2
                )
            case .invalidated:
                exitMarker = SeriesMarker(
                    time: .utc(timestamp: exitBar.openTimeEpochSeconds),
                    position: .aboveBar,
                    shape: .square,
                    color: ChartColor(hex: 0xF59E0B),
                    id: "exit-\(trade.fingerprint)",
                    text: "INVALIDATED",
                    size: 1.2
                )
            case .open, .pending:
                exitMarker = SeriesMarker(
                    time: .utc(timestamp: exitBar.openTimeEpochSeconds),
                    position: .aboveBar,
                    shape: .circle,
                    color: ChartColor(hex: 0xD4AF37),
                    id: "exit-\(trade.fingerprint)",
                    text: trade.status.rawValue,
                    size: 1.2
                )
            }
            raw.append((exitBar.openTimeEpochSeconds, exitMarker))
        }

        // LightweightCharts requires markers sorted strictly ascending by time
        let ordered = raw.sorted { $0.ts < $1.ts }.map(\.marker)
        return BuildResult(markers: ordered, hasEntryBar: hasEntry, hasExitBar: hasExit)
    }
}

/// Tap-to-open Full-Screen Interactive Chart powered by `tradingview/LightweightChartsIOS` (v5.2.0).
/// Supports live in-chart Data Provider & Timeframe switchers, TradingView-style dynamic price precision
/// (`1.31002` for FX, `159.178` for JPY, `2` decimals for >=100), explicit pan & pinch zoom,
/// exact intraday UTC time axis, and Trade Outcome Chart Replay Mode with Entry & Exit markers.
public struct FullScreenChartSheet: View {
    let symbol: String
    let marketClass: MarketClass
    let levels: TradeLevels?
    let overlays: ChartOverlayData
    let palette: ConfluencePalette
    let coordinator: MarketScannerCoordinator?
    let replayContext: TradeReplayContext?
    let sourceSignal: TradeSignal?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var activeCandles: [Candle]
    @State private var activeTimeframe: Timeframe
    @State private var activeProviderName: String
    @State private var selectedProvider: ChartProviderChoice = .auto
    @State private var proxySymbolUsed: String? = nil
    @State private var isLoadingCandles: Bool = false
    @State private var loadError: String? = nil
    @State private var journalDraft: JournalEntrySnapshot? = nil
    @State private var journalDraftIsExisting: Bool = false

    public init(
        signal: TradeSignal,
        palette: ConfluencePalette,
        coordinator: MarketScannerCoordinator? = nil
    ) {
        self.symbol = signal.symbol
        self.marketClass = signal.marketClass
        self.levels = signal.levels
        self.overlays = signal.overlays
        self.palette = palette
        self.coordinator = coordinator
        self.replayContext = nil
        self.sourceSignal = signal
        _activeCandles = State(initialValue: signal.recentCandles)
        _activeTimeframe = State(initialValue: signal.timeframe)
        _activeProviderName = State(initialValue: signal.dataProvider)
    }

    public init(
        replayContext: TradeReplayContext,
        palette: ConfluencePalette,
        coordinator: MarketScannerCoordinator? = nil
    ) {
        let trade = replayContext.trade
        self.symbol = trade.symbol
        self.marketClass = trade.marketClass
        self.levels = trade.levels
        self.overlays = trade.sourceSignal?.overlays ?? ChartOverlayData()
        self.palette = palette
        self.coordinator = coordinator
        self.replayContext = replayContext
        self.sourceSignal = trade.sourceSignal
        _activeCandles = State(initialValue: replayContext.initialCandles)
        _activeTimeframe = State(initialValue: trade.timeframe)
        _activeProviderName = State(initialValue: replayContext.providerName)
    }

    private var isReplayMode: Bool {
        replayContext != nil
    }

    private var shouldShowSignalLevels: Bool {
        proxySymbolUsed == nil
    }

    private var currentReferencePrice: Double? {
        activeCandles.last?.close ?? levels?.entryMid
    }

    private var activePricePrecision: ChartPricePrecision {
        ChartPricePrecision.resolve(
            symbol: symbol,
            marketClass: marketClass,
            referencePrice: currentReferencePrice
        )
    }

    private var replayMarkerBuild: TradeReplayMarkerBuilder.BuildResult? {
        guard let trade = replayContext?.trade else { return nil }
        return TradeReplayMarkerBuilder.buildMarkers(for: trade, candles: activeCandles)
    }

    private var lastClosedUTCLabel: String {
        guard let last = activeCandles.sorted(by: { $0.closeTimeEpochSeconds < $1.closeTimeEpochSeconds }).last else {
            return "No closed bars"
        }
        let use24 = coordinator?.settings.payload.use24HourTime ?? true
        let useUTC = coordinator?.settings.payload.useUTCTimeZone ?? true
        if activeTimeframe == .d1 {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = useUTC ? "MMM d 'UTC'" : "MMM d"
            formatter.timeZone = useUTC ? TimeZone(secondsFromGMT: 0) : TimeZone.current
            return "Closed \(formatter.string(from: Date(timeIntervalSince1970: last.closeTimeEpochSeconds)))"
        }
        return "Closed \(TimeDisplayFormatter.formatShortTime(epochSeconds: last.closeTimeEpochSeconds, use24Hour: use24, useUTC: useUTC))"
    }

    public var body: some View {
        let prec = activePricePrecision
        NavigationStack {
            VStack(spacing: 0) {
                // Trade Replay Outcome Banner (WIN / LOSS / OPEN)
                if let trade = replayContext?.trade {
                    replayOutcomeBanner(trade: trade, build: replayMarkerBuild)
                    Divider().overlay(palette.border)
                }

                // Header numeric ribbon (hidden if viewing an ETF proxy with a different price scale)
                if let lv = levels, shouldShowSignalLevels {
                    HStack(spacing: 12) {
                        levelPill("ENTRY", prec.format(lv.entryMid), palette.champagneGold)
                        levelPill("SL", prec.format(lv.stopLoss), palette.shortCrimson)
                        levelPill("TP1", prec.format(lv.tp1), palette.longEmerald)
                        if lv.isTP2Enabled {
                            levelPill("TP2", prec.format(lv.tp2), palette.macroIceBlue)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(palette.surface)
                    Divider().overlay(palette.border)
                }

                // Live Timeframe & Provider Switcher Bar (live chart mode)
                if coordinator != nil && !isReplayMode {
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
                        levels: shouldShowSignalLevels ? levels : nil,
                        overlays: shouldShowSignalLevels ? overlays : ChartOverlayData(),
                        markers: replayMarkerBuild?.markers ?? [],
                        pricePrecision: prec,
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
            .navigationTitle(isReplayMode ? "Replay · \(symbol) \(activeTimeframe.displayLabel)" : "\(symbol) · \(activeTimeframe.displayLabel)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if coordinator != nil && !isReplayMode {
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
                    if let coord = coordinator, let sig = sourceSignal {
                        let existing = coord.journalEntry(forSignalFingerprint: sig.fingerprint)
                        Button {
                            if let existing {
                                journalDraft = existing
                                journalDraftIsExisting = true
                            } else {
                                journalDraft = coord.makeJournalDraft(from: sig)
                                journalDraftIsExisting = false
                            }
                        } label: {
                            Image(systemName: existing != nil ? "book.closed.fill" : "bookmark.circle")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(existing != nil ? palette.champagneGold : palette.primaryInk)
                        }
                        .accessibilityLabel(existing != nil ? "Edit Trade Journal entry" : "Mark trade taken in Journal")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(item: $journalDraft) { draft in
                if let coord = coordinator {
                    JournalEntryEditorSheet(
                        entry: draft,
                        isExisting: journalDraftIsExisting,
                        coordinator: coord,
                        palette: palette
                    )
                }
            }
        }
        .interactiveDismissDisabled(true)
    }

    private func replayOutcomeBanner(
        trade: StrategyTradeItem,
        build: TradeReplayMarkerBuilder.BuildResult?
    ) -> some View {
        let accent: Color
        let icon: String
        let headline: String
        let rStr = String(format: "%+.2fR", trade.netRMultiple)

        let exitTimeStr: String = {
            guard let ts = trade.exitEpochSeconds else { return "" }
            let use24 = coordinator?.settings.payload.use24HourTime ?? true
            let useUTC = coordinator?.settings.payload.useUTCTimeZone ?? true
            return " at \(TimeDisplayFormatter.formatDateTime(epochSeconds: ts, use24Hour: use24, useUTC: useUTC))"
        }()

        switch trade.status {
        case .tp2Win:
            accent = palette.longEmerald
            icon = "checkmark.seal.fill"
            headline = "TP2 WIN \(rStr)\(exitTimeStr)"
        case .tp1Win:
            accent = palette.longEmerald
            icon = "checkmark.circle.fill"
            headline = "TP1 WIN \(rStr)\(exitTimeStr)"
        case .slLoss:
            accent = palette.shortCrimson
            icon = "xmark.octagon.fill"
            headline = "SL LOSS \(rStr)\(exitTimeStr)"
        case .expired:
            accent = palette.secondaryInk
            icon = "clock.badge.xmark"
            headline = "EXPIRED (No TP/SL hit within window)"
        case .notFilled:
            accent = palette.secondaryInk
            icon = "tray.and.arrow.down"
            headline = "NOT FILLED (Entry zone untouched in fill window)"
        case .invalidated:
            accent = palette.trapAmber
            icon = "exclamationmark.triangle"
            headline = "INVALIDATED BEFORE FILL (SL/TP1 hit prior to entry)"
        case .pending:
            accent = palette.macroIceBlue
            icon = "clock"
            headline = "PENDING FILL · \(trade.direction.rawValue.uppercased()) · Awaiting Entry Zone"
        case .open:
            accent = palette.champagneGold
            icon = "hourglass"
            headline = "OPEN (FILLED) · \(trade.direction.rawValue.uppercased()) · Awaiting TP/SL"
        }

        let missingExitNote = (trade.exitEpochSeconds != nil && !trade.status.isActive && build?.hasExitBar == false)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(accent)
                Text(headline)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(palette.primaryInk)
                Spacer()
                Text("\(Int(trade.confidencePercent.rounded()))% Conf")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(palette.secondaryInk)
            }
            if missingExitNote {
                Text("Historical exit bar predates the live provider's 220-bar window; showing cached entry snapshot.")
                    .font(.caption2)
                    .foregroundStyle(palette.trapAmber)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(accent.opacity(0.14))
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
                ForEach(ChartProviderChoice.choices(for: marketClass)) { choice in
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
                symbol: symbol,
                timeframe: activeTimeframe,
                providerChoice: selectedProvider
            )
            guard !res.candles.isEmpty else {
                loadError = "Provider returned 0 closed candles for \(symbol)."
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
    let markers: [SeriesMarker]
    let pricePrecision: ChartPricePrecision
    let timeframe: Timeframe
    let providerTag: String
    let isDark: Bool

    final class Coordinator {
        var series: CandlestickSeries?
        var markersPlugin: SeriesMarkersPlugin<CandlestickSeries>?
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
            rightPriceScale: VisiblePriceScaleOptions(
                alignLabels: true,
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

        let chartView = LightweightCharts(options: options)
        let builtInFormat = PriceFormat.builtIn(BuiltInPriceFormat(
            type: .price,
            precision: Double(pricePrecision.precision),
            minMove: pricePrecision.minMove
        ))
        let seriesOptions = CandlestickSeriesOptions(
            priceFormat: builtInFormat,
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
        let tp2Flag = (levels?.isTP2Enabled ?? false) ? "1" : "0"
        return "\(timeframe.rawValue)|\(providerTag)|\(candles.count)|\(Int(firstTS))|\(Int(lastTS))|\(hasLevels)|\(tp2Flag)|\(pricePrecision.precision)|\(markers.count)|\(isDark)"
    }

    private func applyData(to chartView: LightweightCharts, coordinator: Coordinator) {
        guard let series = coordinator.series else { return }
        coordinator.lastSignature = renderSignature

        // Re-apply TradingView dynamic price precision & anti-clipping right price scale width
        let builtInFormat = PriceFormat.builtIn(BuiltInPriceFormat(
            type: .price,
            precision: Double(pricePrecision.precision),
            minMove: pricePrecision.minMove
        ))
        series.applyOptions(options: CandlestickSeriesOptions(priceFormat: builtInFormat))
        series.priceScale().applyOptions(options: PriceScaleOptions(
            alignLabels: true,
            borderVisible: true,
            entireTextOnly: true,
            minimumWidth: pricePrecision.minimumPriceScaleWidth
        ))

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
            if lv.isTP2Enabled {
                coordinator.priceLines.append(series.createPriceLine(options: PriceLineOptions(
                    price: lv.tp2,
                    color: ChartColor(hex: 0x38BDF8),
                    lineWidth: .one,
                    lineStyle: .dashed,
                    axisLabelVisible: true,
                    title: "TP2"
                )))
            }
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

        // Apply Trade Replay Entry / Exit Markers via verified v5.2.0 SeriesMarkersPlugin
        if !markers.isEmpty {
            if let plugin = coordinator.markersPlugin {
                plugin.setMarkers(markers)
            } else {
                coordinator.markersPlugin = series.createMarkersPlugin(
                    data: markers,
                    options: SeriesMarkersOptions(active: true, autoScale: true)
                )
            }
        } else if let plugin = coordinator.markersPlugin {
            plugin.setMarkers([])
        }

        chartView.timeScale().fitContent()
    }
}
