import SwiftUI
import UIKit
import SignalEngine

/// Pure deterministic helper that snaps Trade Replay Entry & Exit timestamps onto the exact
/// sorted closed candles present on the chart, producing engine-agnostic `ChartReplayMarker` pins.
public enum TradeReplayMarkerBuilder {
    public struct BuildResult: Sendable {
        public let markers: [ChartReplayMarker]
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
            guard targetClose >= firstOpen - tfSec && targetClose <= lastClose + tfSec else {
                return nil
            }
            if let exact = sorted.first(where: { abs($0.closeTimeEpochSeconds - targetClose) <= 1.0 }) {
                return exact
            }
            if let containing = sorted.first(where: { $0.openTimeEpochSeconds <= targetClose && targetClose <= $0.closeTimeEpochSeconds }) {
                return containing
            }
            return sorted.min { abs($0.closeTimeEpochSeconds - targetClose) < abs($1.closeTimeEpochSeconds - targetClose) }
        }

        var raw: [(ts: TimeInterval, marker: ChartReplayMarker)] = []
        var hasEntry = false
        var hasExit = false

        if let entryBar = snapCandle(forCloseEpoch: trade.entryEpochSeconds) {
            hasEntry = true
            let isLong = (trade.direction == .long)
            let entryMarker = ChartReplayMarker(
                id: "entry-\(trade.fingerprint)",
                timeEpochSeconds: entryBar.openTimeEpochSeconds,
                position: isLong ? .belowBar : .aboveBar,
                shape: isLong ? .arrowUp : .arrowDown,
                colorHex: 0xDEB853,
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
            let exitMarker: ChartReplayMarker
            switch trade.status {
            case .tp2Win:
                exitMarker = ChartReplayMarker(
                    id: "exit-\(trade.fingerprint)",
                    timeEpochSeconds: exitBar.openTimeEpochSeconds,
                    position: isLong ? .aboveBar : .belowBar,
                    shape: .circle,
                    colorHex: 0x10B981,
                    text: "T2 WIN \(rText)",
                    size: 1.6
                )
            case .tp1Win:
                exitMarker = ChartReplayMarker(
                    id: "exit-\(trade.fingerprint)",
                    timeEpochSeconds: exitBar.openTimeEpochSeconds,
                    position: isLong ? .aboveBar : .belowBar,
                    shape: .circle,
                    colorHex: 0x10B981,
                    text: "T1 WIN \(rText)",
                    size: 1.6
                )
            case .slLoss:
                exitMarker = ChartReplayMarker(
                    id: "exit-\(trade.fingerprint)",
                    timeEpochSeconds: exitBar.openTimeEpochSeconds,
                    position: isLong ? .belowBar : .aboveBar,
                    shape: .square,
                    colorHex: 0xEF4444,
                    text: "SL HIT \(rText)",
                    size: 1.6
                )
            case .expired:
                exitMarker = ChartReplayMarker(
                    id: "exit-\(trade.fingerprint)",
                    timeEpochSeconds: exitBar.openTimeEpochSeconds,
                    position: .aboveBar,
                    shape: .square,
                    colorHex: 0x9CA7BA,
                    text: "EXPIRED",
                    size: 1.2
                )
            case .notFilled:
                exitMarker = ChartReplayMarker(
                    id: "exit-\(trade.fingerprint)",
                    timeEpochSeconds: exitBar.openTimeEpochSeconds,
                    position: .aboveBar,
                    shape: .square,
                    colorHex: 0x9CA7BA,
                    text: "NOT FILLED",
                    size: 1.2
                )
            case .invalidated:
                exitMarker = ChartReplayMarker(
                    id: "exit-\(trade.fingerprint)",
                    timeEpochSeconds: exitBar.openTimeEpochSeconds,
                    position: .aboveBar,
                    shape: .square,
                    colorHex: 0xF59E0B,
                    text: "INVALIDATED",
                    size: 1.2
                )
            case .open, .pending:
                exitMarker = ChartReplayMarker(
                    id: "exit-\(trade.fingerprint)",
                    timeEpochSeconds: exitBar.openTimeEpochSeconds,
                    position: .aboveBar,
                    shape: .circle,
                    colorHex: 0xDEB853,
                    text: trade.status.rawValue,
                    size: 1.2
                )
            }
            raw.append((exitBar.openTimeEpochSeconds, exitMarker))
        }

        let ordered = raw.sorted { $0.ts < $1.ts }.map(\.marker)
        return BuildResult(markers: ordered, hasEntryBar: hasEntry, hasExitBar: hasExit)
    }
}

/// Tap-to-open Full-Screen Interactive Chart powered by `ConfluenceChartContainerView`
/// (`CandleKit`, `DGCharts`, native multi-pane `Swift Trading View`, or persistent `TradingView Web`).
/// - Auto-fetches 500 bars on open and lazy-loads older history on pan-left (up to 5,000 bars via `HistoryMerge`).
/// - Plots live forming candles via display-only `LiveCandleAggregator` (never touches `SignalEngine`).
/// - Includes timeframe bar (`15m | 30m | 1H | 4H | 1D`), Reset view, collapsible Risk strip, and clean read-only chrome.
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
    @AppStorage(ChartEngineOption.appStorageKey) private var storedChartEngineRaw: String = ChartEngineOption.candleKit.rawValue

    @State private var sheetInstanceId: String = UUID().uuidString
    @State private var session: ChartSessionController
    @State private var activeProviderName: String
    @State private var selectedProvider: ChartProviderChoice = .auto
    @State private var proxySymbolUsed: String? = nil
    @State private var loadError: String? = nil
    @State private var showRiskStrip: Bool = true
    @State private var chartViewMode: DefaultChartViewMode

    private static let dailyUTCFormat = Date.VerbatimFormatStyle(
        format: "\(month: .abbreviated) \(day: .defaultDigits) UTC",
        locale: Locale(identifier: "en_US_POSIX"),
        timeZone: TimeZone(secondsFromGMT: 0) ?? .gmt,
        calendar: Calendar(identifier: .gregorian)
    )
    private static let dailyLocalFormat: Date.FormatString = "\(month: .abbreviated) \(day: .defaultDigits)"

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
        _session = State(initialValue: ChartSessionController(
            symbol: signal.symbol,
            marketClass: signal.marketClass,
            timeframe: signal.timeframe,
            initialCandles: signal.recentCandles
        ))
        _activeProviderName = State(initialValue: signal.dataProvider)
        let allowTV = coordinator?.settings.payload.showTradingViewOption ?? true
        let preferred = coordinator?.settings.payload.defaultChartViewMode ?? .confluence
        _chartViewMode = State(initialValue: allowTV ? preferred : .confluence)
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
        _session = State(initialValue: ChartSessionController(
            symbol: trade.symbol,
            marketClass: trade.marketClass,
            timeframe: trade.timeframe,
            initialCandles: replayContext.initialCandles
        ))
        _activeProviderName = State(initialValue: replayContext.providerName)
        _chartViewMode = State(initialValue: .confluence)
    }

    private var isReplayMode: Bool { replayContext != nil }
    private var shouldShowSignalLevels: Bool { proxySymbolUsed == nil }
    private var showTradingViewControls: Bool {
        !isReplayMode
            && activeChartEngine != .tradingViewWeb
            && (coordinator?.settings.payload.showTradingViewOption ?? false)
    }
    private var effectiveChartViewMode: DefaultChartViewMode {
        showTradingViewControls ? chartViewMode : .confluence
    }

    private var activeChartEngine: ChartEngineOption {
        coordinator?.settings.payload.chartEngine
            ?? ChartEngineOption.fromStoredRawValue(storedChartEngineRaw)
    }

    private var activeOrderFlowSummary: ChartOrderFlowSummary? {
        guard !isReplayMode,
              marketClass == .crypto,
              coordinator?.settings.payload.isOrderFlowEnabled == true
        else { return nil }
        if let live = coordinator?.liveOrderFlowService,
           live.activeSymbol == symbol,
           let assessment = live.latestAssessment,
           let summary = assessment.chartSummary {
            return summary
        }
        return sourceSignal?.orderFlowSummary
    }

    private var activeOverlayModel: ChartSignalOverlayModel {
        let dir: TradeDirection? = sourceSignal?.direction
            ?? replayContext?.trade.direction
            ?? effectiveLevels.map { $0.tp1 >= $0.entryMid ? .long : .short }
        let entryTS: TimeInterval? = replayContext?.trade.entryEpochSeconds
            ?? sourceSignal?.recentCandles.last?.openTimeEpochSeconds
            ?? sourceSignal?.barCloseEpochSeconds
            ?? session.closedCandles.last?.openTimeEpochSeconds
        return ChartSignalOverlayModel.build(
            symbol: symbol,
            marketClass: marketClass,
            timeframe: session.timeframe,
            direction: dir,
            levels: effectiveLevels,
            overlays: shouldShowSignalLevels ? overlays : ChartOverlayData(),
            entryTimestamp: entryTS,
            breakevenPrice: nil,
            livePrice: activeQuote?.price,
            orderFlowSummary: activeOrderFlowSummary
        )
    }

    private func openInTradingView() {
        let deepURL = TradingViewSymbolMapper.deepLinkURL(for: symbol, timeframe: session.timeframe)
        let webURL = TradingViewSymbolMapper.webFallbackURL(for: symbol, timeframe: session.timeframe)
        Task { @MainActor in
            if let deep = deepURL {
                let opened = await UIApplication.shared.open(deep)
                if !opened, let fallback = webURL {
                    _ = await UIApplication.shared.open(fallback)
                }
            } else if let fallback = webURL {
                _ = await UIApplication.shared.open(fallback)
            }
        }
    }

    private var activeQuote: LivePriceQuote? {
        guard !isReplayMode else { return nil }
        return coordinator?.livePriceService.latest(for: symbol)
    }

    private var currentReferencePrice: Double? {
        activeQuote?.price ?? session.formingCandle?.close ?? session.closedCandles.last?.close ?? levels?.entryMid
    }

    private var activePricePrecision: ChartPricePrecision {
        ChartPricePrecision.resolve(
            symbol: symbol,
            marketClass: marketClass,
            referencePrice: currentReferencePrice
        )
    }

    private var effectiveLevels: TradeLevels? {
        guard shouldShowSignalLevels else { return nil }
        return levels
    }

    private var replayMarkerBuild: TradeReplayMarkerBuilder.BuildResult? {
        guard let trade = replayContext?.trade else { return nil }
        return TradeReplayMarkerBuilder.buildMarkers(for: trade, candles: session.closedCandles)
    }

    private var lastClosedUTCLabel: String {
        guard let last = session.closedCandles.last else { return "No closed bars" }
        let use24 = coordinator?.settings.payload.use24HourTime ?? true
        let useUTC = coordinator?.settings.payload.useUTCTimeZone ?? true
        if session.timeframe == .d1 {
            let date = Date(timeIntervalSince1970: last.closeTimeEpochSeconds)
            if useUTC {
                return "Closed \(Self.dailyUTCFormat.format(date))"
            }
            let localStyle = Date.VerbatimFormatStyle(
                format: Self.dailyLocalFormat,
                locale: Locale(identifier: "en_US_POSIX"),
                timeZone: TimeZone.current,
                calendar: Calendar(identifier: .gregorian)
            )
            return "Closed \(localStyle.format(date))"
        }
        return "Closed \(TimeDisplayFormatter.formatShortTime(epochSeconds: last.closeTimeEpochSeconds, use24Hour: use24, useUTC: useUTC))"
    }

    public var body: some View {
        let prec = activePricePrecision
        let scaleResult = session.computeScaleResult(levels: effectiveLevels, traps: shouldShowSignalLevels ? overlays.traps : [])

        NavigationStack {
            VStack(spacing: 0) {
                // Trade Replay Outcome Banner
                if let trade = replayContext?.trade {
                    replayOutcomeBanner(trade: trade, build: replayMarkerBuild)
                    Divider().overlay(palette.border)
                }

                // Live Quote + Freshness + Collapsible Risk Strip
                if let lv = effectiveLevels {
                    collapsibleRiskStrip(levels: lv, precision: prec, scaleResult: scaleResult)
                    Divider().overlay(palette.border)
                } else if let quote = activeQuote {
                    liveQuoteOnlyBar(quote: quote, precision: prec)
                    Divider().overlay(palette.border)
                }

                // Live Timeframe, Provider Switcher & Reset View Bar
                if coordinator != nil && !isReplayMode {
                    chartControlsBar
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(palette.surface)
                    Divider().overlay(palette.border)
                }

                // Optional TradingView Switcher & Deep-Link Bar
                if showTradingViewControls {
                    HStack(spacing: 8) {
                        Picker("Chart View", selection: $chartViewMode) {
                            Text("Confluence").tag(DefaultChartViewMode.confluence)
                            Text("TradingView").tag(DefaultChartViewMode.tradingView)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 210)

                        Spacer()

                        Button {
                            openInTradingView()
                        } label: {
                            HStack(spacing: 4) {
                                Text("Open in TradingView")
                                    .font(.caption2.weight(.semibold))
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundStyle(palette.primaryInk)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(palette.elevatedSurface, in: Capsule())
                            .overlay(Capsule().strokeBorder(palette.border, lineWidth: 0.75))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(palette.surface)
                    Divider().overlay(palette.border)
                }

                // ETF Proxy Notice Banner
                if effectiveChartViewMode == .confluence, let proxy = proxySymbolUsed {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(palette.trapAmber)
                        Text("ETF Proxy: \(proxy) (Twelve Data Basic Plan) — index levels hidden to avoid scale mismatch.")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(palette.primaryInk)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(palette.trapAmber.opacity(0.14))
                } else if effectiveChartViewMode == .tradingView && effectiveLevels != nil {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(palette.secondaryInk)
                        Text("Switch back to Confluence chart to view Entry, Stop loss, Target & Trap lines directly on candles.")
                            .font(.caption2)
                            .foregroundStyle(palette.secondaryInk)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(palette.elevatedSurface)
                }

                // Inline Load Error
                if let err = loadError, effectiveChartViewMode == .confluence {
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

                // Main Interactive Chart Surface
                ZStack {
                    if effectiveChartViewMode == .tradingView {
                        TradingViewWidgetView(
                            symbol: symbol,
                            timeframe: session.timeframe,
                            isDark: colorScheme == .dark
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ConfluenceChartContainerView(
                            selectedEngine: activeChartEngine,
                            symbol: symbol,
                            assetClass: marketClass,
                            closedCandles: session.closedCandles,
                            formingCandle: session.formingCandle,
                            lastRolledOverCandle: session.lastRolledOverCandle,
                            liveTick: session.latestLiveTick,
                            dataSetRevision: session.dataSetRevision,
                            liveUpdateToken: session.liveUpdateToken,
                            fitRequestToken: session.fitRequestToken,
                            overlayModel: activeOverlayModel,
                            replayMarkers: replayMarkerBuild?.markers ?? [],
                            pricePrecision: prec,
                            timeframe: session.timeframe,
                            providerTag: activeProviderName,
                            palette: palette,
                            isDark: colorScheme == .dark,
                            tradingViewPreferDesktop: Binding(
                                get: { coordinator?.settings.payload.tradingViewPreferDesktop ?? false },
                                set: { newVal in
                                    coordinator?.settings.payload.tradingViewPreferDesktop = newVal
                                }
                            ),
                            onNeedOlderHistory: {
                                Task { await loadOlderHistoryPage() }
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if activeChartEngine != .tradingViewWeb && (session.isLoadingInitial || session.isLoadingOlder) {
                            VStack {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .tint(palette.champagneGold)
                                    Text(session.isLoadingOlder ? "Loading older bars..." : "Loading \(session.timeframe.displayLabel)...")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(palette.primaryInk)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(.top, 10)
                                Spacer()
                            }
                        }
                    }
                }

                // Footer: Attribution + Loaded Bars + Exact Closed Candle Time
                HStack(spacing: 8) {
                    Text(effectiveChartViewMode == .tradingView ? "Chart by TradingView" : activeChartEngine.attributionLabel)
                        .font(.caption2)
                        .foregroundStyle(palette.tertiaryInk)
                        .lineLimit(1)
                    Spacer()
                    if effectiveChartViewMode == .tradingView || activeChartEngine == .tradingViewWeb {
                        Text(TradingViewSymbolMapper.tradingViewSymbol(for: symbol))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(palette.secondaryInk)
                            .lineLimit(1)
                    } else {
                        Text("\(session.closedCandles.count) bars · \(activeProviderName) · \(lastClosedUTCLabel)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(palette.secondaryInk)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(palette.surface)
            }
            .background(palette.canvas)
            .navigationTitle(isReplayMode ? "Replay · \(symbol) \(session.timeframe.displayLabel)" : "\(symbol) · \(session.timeframe.displayLabel)")
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
                        .disabled(session.isLoadingInitial)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .task {
                if !isReplayMode {
                    coordinator?.livePriceService.acquire(owner: "chart_\(symbol)_\(sheetInstanceId)", symbols: [symbol])
                    if marketClass == .crypto, coordinator?.settings.payload.isOrderFlowEnabled == true {
                        let focusDir: TradeDirection = sourceSignal?.direction
                            ?? effectiveLevels.map { $0.tp1 >= $0.entryMid ? .long : .short }
                            ?? .neutral
                        coordinator?.liveOrderFlowService.focus(
                            symbol: symbol,
                            assetClass: marketClass,
                            direction: focusDir,
                            entryPrice: effectiveLevels?.entryMid,
                            takeProfit1: effectiveLevels?.tp1
                        )
                    }
                    if session.closedCandles.count < 120 {
                        await reloadChartData()
                    }
                }
            }
            .onDisappear {
                if !isReplayMode {
                    coordinator?.livePriceService.release(owner: "chart_\(symbol)_\(sheetInstanceId)")
                    coordinator?.liveOrderFlowService.unfocus(symbol: symbol)
                }
            }
            .onChange(of: activeQuote) { _, newQuote in
                guard let q = newQuote, !isReplayMode else { return }
                session.ingestLiveQuote(q)
            }
        }
        .interactiveDismissDisabled(true)
    }

    // MARK: - Collapsible Risk Strip & Live Freshness

    private func liveFreshnessBadge(quote: LivePriceQuote?) -> some View {
        let now = Date().timeIntervalSince1970
        let freshness = quote?.freshness(nowEpochSeconds: now) ?? .offline
        let text = quote?.statusBadgeText(nowEpochSeconds: now) ?? "OFFLINE"
        let color: Color = {
            switch freshness {
            case .live: return quote?.isStreaming == true ? palette.longEmerald : palette.secondaryInk
            case .delayed: return palette.trapAmber
            case .offline: return palette.shortCrimson
            }
        }()
        return HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.14), in: Capsule())
    }

    private func liveQuoteOnlyBar(quote: LivePriceQuote, precision: ChartPricePrecision) -> some View {
        HStack {
            Text("Live \(precision.format(quote.price))")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(palette.primaryInk)
            liveFreshnessBadge(quote: quote)
            Spacer()
            Text(quote.sourceLabel)
                .font(.caption2)
                .foregroundStyle(palette.tertiaryInk)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(palette.surface)
    }

    private func collapsibleRiskStrip(
        levels lv: TradeLevels,
        precision prec: ChartPricePrecision,
        scaleResult: ChartScaleResult?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let q = activeQuote {
                    Text(prec.format(q.price))
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(palette.primaryInk)
                }
                if !isReplayMode {
                    liveFreshnessBadge(quote: activeQuote)
                }
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showRiskStrip.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Risk & Levels")
                            .font(.caption2.weight(.semibold))
                        Image(systemName: showRiskStrip ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(palette.secondaryInk)
                }
                .buttonStyle(.plain)
            }

            if showRiskStrip {
                HStack(spacing: 10) {
                    levelPill("Entry", prec.format(lv.entryMid), sub: "R:R 1:\(String(format: "%.1f", lv.riskRewardRatio))", palette.champagneGold)
                    levelPill(
                        "Stop loss",
                        prec.format(lv.stopLoss),
                        sub: "-\(String(format: "%.2f", lv.riskPercent))%",
                        palette.shortCrimson
                    )
                    levelPill(
                        "Target 1",
                        prec.format(lv.tp1),
                        sub: "+\(String(format: "%.2f", lv.reward1Percent))%",
                        palette.longEmerald
                    )
                    if lv.isTP2Enabled {
                        levelPill(
                            "Target 2",
                            prec.format(lv.tp2),
                            sub: "+\(String(format: "%.2f", lv.reward2Percent))% · 1:\(String(format: "%.1f", lv.tp2RiskRewardRatio))",
                            palette.longEmerald
                        )
                    }
                }

                if let offScale = scaleResult?.offScaleOverlays, !offScale.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(offScale) { notice in
                                Text("\(notice.label) off-scale (\(prec.format(notice.price)))")
                                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(palette.trapAmber)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(palette.trapAmber.opacity(0.14), in: Capsule())
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(palette.surface)
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
            accent = palette.longEmerald; icon = "checkmark.seal.fill"
            headline = "Target 2 WIN \(rStr)\(exitTimeStr)"
        case .tp1Win:
            accent = palette.longEmerald; icon = "checkmark.circle.fill"
            headline = "Target 1 WIN \(rStr)\(exitTimeStr)"
        case .slLoss:
            accent = palette.shortCrimson; icon = "xmark.octagon.fill"
            headline = "Stop loss HIT \(rStr)\(exitTimeStr)"
        case .expired:
            accent = palette.secondaryInk; icon = "clock.badge.xmark"
            headline = "EXPIRED (No level hit within window)"
        case .notFilled:
            accent = palette.secondaryInk; icon = "tray.and.arrow.down"
            headline = "NOT FILLED (Entry zone untouched)"
        case .invalidated:
            accent = palette.trapAmber; icon = "exclamationmark.triangle"
            headline = "INVALIDATED BEFORE FILL"
        case .pending:
            accent = palette.secondaryInk; icon = "clock"
            headline = "PENDING FILL · \(trade.direction.rawValue.uppercased())"
        case .open:
            accent = palette.champagneGold; icon = "hourglass"
            headline = "OPEN (FILLED) · \(trade.direction.rawValue.uppercased())"
        }

        let missingExitNote = (trade.exitEpochSeconds != nil && !trade.status.isActive && build?.hasExitBar == false)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(accent)
                Text(headline)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(palette.primaryInk)
                Spacer()
                Text("\(Int(trade.confidencePercent.rounded())) Score")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(palette.secondaryInk)
            }
            if missingExitNote {
                Text("Historical exit bar predates the loaded bar window; showing cached entry snapshot.")
                    .font(.caption2)
                    .foregroundStyle(palette.trapAmber)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(accent.opacity(0.14))
    }

    private var chartControlsBar: some View {
        HStack(spacing: 6) {
            // Timeframe pills (15m | 30m | 1H | 4H | 1D)
            HStack(spacing: 4) {
                ForEach(Timeframe.allCases, id: \.self) { tf in
                    let isSelected = (session.timeframe == tf)
                    Button {
                        guard session.timeframe != tf else { return }
                        session.timeframe = tf
                        Task { await reloadChartData() }
                    } label: {
                        Text(tf.displayLabel)
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(isSelected ? palette.canvas : palette.secondaryInk)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                            .background(isSelected ? palette.champagneGold : palette.elevatedSurface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(session.isLoadingInitial)
                }
            }

            Spacer()

            // Reset button (fits content + scrolls to real time + restores Y-scale)
            Button {
                session.requestResetView()
            } label: {
                Text("Reset")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(palette.primaryInk)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(palette.elevatedSurface, in: Capsule())
                    .overlay(Capsule().strokeBorder(palette.border, lineWidth: 0.75))
            }
            .buttonStyle(.plain)

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
                HStack(spacing: 3) {
                    Text(selectedProvider.rawValue)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(palette.primaryInk)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(palette.elevatedSurface, in: Capsule())
                .overlay(Capsule().strokeBorder(palette.border, lineWidth: 0.75))
            }
            .disabled(session.isLoadingInitial)
        }
    }

    private func reloadChartData() async {
        guard let coordinator else { return }
        session.beginInitialLoad(for: session.timeframe)
        loadError = nil

        do {
            let res = try await coordinator.fetchChartCandles(
                symbol: symbol,
                timeframe: session.timeframe,
                providerChoice: selectedProvider,
                limit: 500
            )
            guard !res.candles.isEmpty else {
                loadError = "Provider returned 0 closed candles for \(symbol)."
                session.failInitialLoad()
                return
            }
            activeProviderName = res.providerName
            proxySymbolUsed = res.proxySymbolUsed
            session.finishInitialLoad(candles: res.candles)
        } catch is CancellationError {
            session.failInitialLoad()
        } catch let urlErr as URLError where urlErr.code == .cancelled {
            session.failInitialLoad()
        } catch {
            if !Task.isCancelled {
                loadError = error.localizedDescription
            }
            session.failInitialLoad()
        }
    }

    private func loadOlderHistoryPage() async {
        guard let coordinator, !isReplayMode,
              let oldestOpen = session.oldestOpenTimeEpochSeconds,
              !session.isLoadingInitial, !session.isLoadingOlder, !session.hasReachedHistoryEnd
        else { return }

        session.beginOlderPageLoad()
        do {
            let res = try await coordinator.fetchChartCandles(
                symbol: symbol,
                timeframe: session.timeframe,
                providerChoice: selectedProvider,
                limit: 500,
                endTimeEpochSeconds: oldestOpen - 1.0
            )
            session.finishOlderPageLoad(
                olderCandles: res.candles,
                serverNowEpochSeconds: Date().timeIntervalSince1970
            )
        } catch {
            session.failOlderPageLoad()
        }
    }

    private func levelPill(_ title: String, _ value: String, sub: String?, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(palette.primaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let sub {
                Text(sub)
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundStyle(palette.tertiaryInk)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
