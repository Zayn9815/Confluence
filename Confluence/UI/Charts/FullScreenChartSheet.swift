import SwiftUI
import UIKit
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
                    text: "T2 WIN \(rText)",
                    size: 1.6
                )
            case .tp1Win:
                exitMarker = SeriesMarker(
                    time: .utc(timestamp: exitBar.openTimeEpochSeconds),
                    position: isLong ? .aboveBar : .belowBar,
                    shape: .circle,
                    color: ChartColor(hex: 0x10B981),
                    id: "exit-\(trade.fingerprint)",
                    text: "T1 WIN \(rText)",
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

        let ordered = raw.sorted { $0.ts < $1.ts }.map(\.marker)
        return BuildResult(markers: ordered, hasEntryBar: hasEntry, hasExitBar: hasExit)
    }
}

/// Tap-to-open Full-Screen Interactive Chart powered by `tradingview/LightweightChartsIOS` (v5.2.0).
/// - Auto-fetches 500 bars on open and lazy-loads older history on pan-left (up to 5,000 bars via `HistoryMerge`).
/// - Plots live forming candles via native `series.update(bar:)` (display-only; never touches `SignalEngine`).
/// - Preserves ALL signal & psychology overlays (Entry, Stop loss, Target 1, Target 2, active Traps, Live price, Breakeven)
///   with clean `autoscaleInfoProvider` + `scaleMargins` (never stretching Y-axis on extreme >20% lines).
/// - Includes Reset view, collapsible Risk strip, labeled "Trade" button, and live Demo position actions.
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

    @State private var session: ChartSessionController
    @State private var activeProviderName: String
    @State private var selectedProvider: ChartProviderChoice = .auto
    @State private var proxySymbolUsed: String? = nil
    @State private var loadError: String? = nil
    @State private var showRiskStrip: Bool = true

    @State private var isTradeSheetPresented: Bool = false
    @State private var journalDraft: JournalEntrySnapshot? = nil
    @State private var journalDraftIsExisting: Bool = false
    @State private var editingPosition: DemoPosition? = nil
    @State private var actionFeedback: String? = nil
    @State private var chartViewMode: DefaultChartViewMode

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
        !isReplayMode && (coordinator?.settings.payload.showTradingViewOption ?? false)
    }
    private var effectiveChartViewMode: DefaultChartViewMode {
        showTradingViewControls ? chartViewMode : .confluence
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

    private var activeDemoPosition: DemoPosition? {
        coordinator?.demoWallet.activePositions.first { $0.symbol == symbol }
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

    /// Combines signal levels with any live edits made to an active Demo position on this symbol.
    private var effectiveLevels: TradeLevels? {
        guard shouldShowSignalLevels else { return nil }
        if let pos = activeDemoPosition {
            let entry = pos.filledPrice ?? pos.entryPrice
            let riskPct = abs(entry - pos.stopLoss) / max(entry, 1e-9) * 100.0
            let rew1Pct = abs(pos.target1 - entry) / max(entry, 1e-9) * 100.0
            let t2Val = pos.target2 ?? pos.target1
            let rew2Pct = abs(t2Val - entry) / max(entry, 1e-9) * 100.0
            let rr1 = riskPct > 1e-9 ? rew1Pct / riskPct : 0
            let rr2 = riskPct > 1e-9 ? rew2Pct / riskPct : 0
            return TradeLevels(
                entryLow: pos.entryLow,
                entryHigh: pos.entryHigh,
                entryMid: entry,
                stopLoss: pos.stopLoss,
                tp1: pos.target1,
                tp2: t2Val,
                riskPercent: riskPct,
                reward1Percent: rew1Pct,
                reward2Percent: rew2Pct,
                riskRewardRatio: rr1,
                tp2RiskRewardRatio: rr2,
                isTP2Enabled: pos.target2 != nil
            )
        }
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

                // Active Demo Position quick-action bar (Close / Breakeven / Edit SL & Targets)
                if let pos = activeDemoPosition, !isReplayMode {
                    activePositionActionBar(pos: pos, precision: prec)
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
                            .foregroundStyle(palette.macroIceBlue)
                        Text("Switch back to Confluence chart to view Entry, Stop loss, Target & Trap lines directly on candles.")
                            .font(.caption2)
                            .foregroundStyle(palette.secondaryInk)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(palette.macroIceBlue.opacity(0.10))
                }

                // Inline Load Error / Action Feedback
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
                } else if let msg = actionFeedback {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(palette.longEmerald)
                        Text(msg)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(palette.primaryInk)
                        Spacer()
                        Button("Dismiss") { actionFeedback = nil }
                            .font(.caption2.weight(.semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(palette.longEmerald.opacity(0.14))
                }

                // Main Interactive Chart Surface (Confluence LightweightCharts vs Lazy TradingView Widget)
                ZStack {
                    if effectiveChartViewMode == .tradingView {
                        TradingViewWidgetView(
                            symbol: symbol,
                            timeframe: session.timeframe,
                            isDark: colorScheme == .dark
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        LightweightChartContainer(
                            closedCandles: session.closedCandles,
                            formingCandle: session.formingCandle,
                            dataSetRevision: session.dataSetRevision,
                            liveUpdateToken: session.liveUpdateToken,
                            fitRequestToken: session.fitRequestToken,
                            levels: effectiveLevels,
                            overlays: shouldShowSignalLevels ? overlays : ChartOverlayData(),
                            livePrice: activeQuote?.price,
                            breakevenPrice: (activeDemoPosition?.isStopLossAtBreakeven == true) ? activeDemoPosition?.stopLoss : nil,
                            markers: replayMarkerBuild?.markers ?? [],
                            pricePrecision: prec,
                            timeframe: session.timeframe,
                            providerTag: activeProviderName,
                            isDark: colorScheme == .dark,
                            onNeedOlderHistory: {
                                Task { await loadOlderHistoryPage() }
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if session.isLoadingInitial || session.isLoadingOlder {
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
                    Text(effectiveChartViewMode == .tradingView ? "Chart by TradingView" : "TradingView Lightweight Charts")
                        .font(.caption2)
                        .foregroundStyle(palette.tertiaryInk)
                        .lineLimit(1)
                    Spacer()
                    if effectiveChartViewMode == .tradingView {
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
                    if coordinator != nil && !isReplayMode && effectiveLevels != nil {
                        Button {
                            isTradeSheetPresented = true
                        } label: {
                            Text("Trade")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(palette.canvas)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 5)
                                .background(palette.champagneGold, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .task {
                if !isReplayMode {
                    coordinator?.livePriceService.acquire(owner: "chart_\(symbol)", symbols: [symbol])
                    if session.closedCandles.count < 120 {
                        await reloadChartData()
                    }
                }
            }
            .onDisappear {
                if !isReplayMode {
                    coordinator?.livePriceService.release(owner: "chart_\(symbol)")
                }
            }
            .onChange(of: activeQuote) { _, newQuote in
                guard let q = newQuote, !isReplayMode else { return }
                session.ingestLiveQuote(q)
            }
            .sheet(isPresented: $isTradeSheetPresented) {
                if let coord = coordinator, let lv = effectiveLevels {
                    QuickChartTradeSheet(
                        symbol: symbol,
                        marketClass: marketClass,
                        timeframe: session.timeframe,
                        direction: sourceSignal?.direction ?? (lv.tp1 >= lv.entryMid ? .long : .short),
                        levels: lv,
                        sourceSignal: sourceSignal,
                        coordinator: coord,
                        palette: palette,
                        onOpenJournalDraft: { draft, isExisting in
                            journalDraft = draft
                            journalDraftIsExisting = isExisting
                        },
                        onDemoPlaced: { pos in
                            actionFeedback = "Demo \(pos.direction.rawValue.uppercased()) \(pos.symbol) placed (\(pos.status == .open ? "Filled" : "Limit"))."
                        }
                    )
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
            .sheet(item: $editingPosition) { pos in
                if let coord = coordinator {
                    EditDemoLevelsSheet(
                        position: pos,
                        precision: prec,
                        coordinator: coord,
                        palette: palette,
                        onSaved: { msg in
                            actionFeedback = msg
                        }
                    )
                }
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
            case .live: return quote?.isStreaming == true ? palette.longEmerald : palette.macroIceBlue
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
        let walletBalance = coordinator?.demoWallet.cashBalanceUSD ?? DemoWallet.defaultStartingBalanceUSD
        let riskPctAccount = coordinator?.settings.payload.defaultRiskPercent ?? 1.0
        let riskUSD = walletBalance * (riskPctAccount / 100.0)
        let reward1USD = riskUSD * max(lv.riskRewardRatio, 0)

        return VStack(alignment: .leading, spacing: 8) {
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
                    levelPill("Entry", prec.format(lv.entryMid), sub: nil, palette.champagneGold)
                    levelPill(
                        "Stop loss",
                        prec.format(lv.stopLoss),
                        sub: "-\(String(format: "%.2f", lv.riskPercent))% · -$\(String(format: "%.0f", riskUSD))",
                        palette.shortCrimson
                    )
                    levelPill(
                        "Target 1",
                        prec.format(lv.tp1),
                        sub: "+\(String(format: "%.2f", lv.reward1Percent))% · +$\(String(format: "%.0f", reward1USD))",
                        palette.longEmerald
                    )
                    if lv.isTP2Enabled {
                        levelPill(
                            "Target 2",
                            prec.format(lv.tp2),
                            sub: "1:\(String(format: "%.1f", lv.tp2RiskRewardRatio))",
                            palette.macroIceBlue
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

    private func activePositionActionBar(pos: DemoPosition, precision prec: ChartPricePrecision) -> some View {
        let mark = activeQuote?.price ?? session.closedCandles.last?.close ?? pos.entryPrice
        let pnl = pos.status == .open ? DemoWalletEngine.pnlUSD(for: pos, markPrice: mark) : 0.0
        let rMult = pos.status == .open ? DemoWalletEngine.rMultiple(for: pos, markPrice: mark) : 0.0
        let pnlColor = pnl >= 0 ? palette.longEmerald : palette.shortCrimson

        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Demo \(pos.direction.rawValue.uppercased()) · \(pos.status == .open ? "OPEN" : "LIMIT")")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.champagneGold)
                Text("\(pnl >= 0 ? "+" : "-")$\(String(format: "%.2f", abs(pnl))) (\(String(format: "%+.2fR", rMult)))")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(pnlColor)
            }
            Spacer()
            if pos.status == .open && !pos.isStopLossAtBreakeven {
                Button("Move SL to BE") {
                    if let coord = coordinator {
                        switch coord.moveDemoStopLossToBreakeven(positionId: pos.id) {
                        case .success:
                            actionFeedback = "Stop loss moved to breakeven (\(prec.format(pos.filledPrice ?? pos.entryPrice)))."
                        case .failure(let err):
                            loadError = err.userMessage
                        }
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(palette.macroIceBlue)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(palette.macroIceBlue.opacity(0.14), in: Capsule())
            }
            Button("Edit") {
                editingPosition = pos
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(palette.primaryInk)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(palette.elevatedSurface, in: Capsule())

            Button("Close now") {
                if coordinator?.closeDemoPositionManually(positionId: pos.id) == true {
                    actionFeedback = "Demo position closed at \(prec.format(mark))."
                }
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(palette.shortCrimson)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(palette.shortCrimson.opacity(0.14), in: Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(palette.elevatedSurface.opacity(0.65))
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
            accent = palette.macroIceBlue; icon = "clock"
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
            // Timeframe pills
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
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(isSelected ? palette.champagneGold : palette.elevatedSurface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(session.isLoadingInitial)
                }
            }

            Spacer()

            // Reset button (fits content + scrolls to real time + restores autoscale)
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
        } catch {
            loadError = error.localizedDescription
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

// MARK: - Quick In-Chart Trade & Edit Sheets

private struct QuickChartTradeSheet: View {
    let symbol: String
    let marketClass: MarketClass
    let timeframe: Timeframe
    let direction: TradeDirection
    let levels: TradeLevels
    let sourceSignal: TradeSignal?
    @Bindable var coordinator: MarketScannerCoordinator
    let palette: ConfluencePalette
    let onOpenJournalDraft: (JournalEntrySnapshot, Bool) -> Void
    let onDemoPlaced: (DemoPosition) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var mode: Int = 0 // 0 = Demo, 1 = Log real trade
    @State private var orderType: DemoOrderType = .market
    @State private var exitTarget: DemoExitTarget = .target1
    @State private var riskPercent: Double = 1.0
    @State private var allowStaleOverride: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showStaleConfirm: Bool = false

    var body: some View {
        let quote = coordinator.livePriceService.latest(for: symbol)
        let leverage = DemoMarginSpec.defaultLeverage(for: marketClass)

        NavigationStack {
            Form {
                Section {
                    Picker("Mode", selection: $mode) {
                        Text("Demo trade").tag(0)
                        Text("Log real trade").tag(1)
                    }
                    .pickerStyle(.segmented)
                }

                if mode == 0 {
                    Section("Paper wallet") {
                        HStack {
                            Text("Free margin")
                            Spacer()
                            Text("$\(String(format: "%.2f", coordinator.demoWallet.freeMarginUSD))")
                                .fontWeight(.semibold).monospacedDigit()
                        }
                        HStack {
                            Text("Leverage (\(marketClass.displayName))")
                            Spacer()
                            Text("\(String(format: "%.0f", leverage))x").monospacedDigit()
                        }
                        if let q = quote {
                            HStack {
                                Text("Live price")
                                Spacer()
                                Text("\(ChartPricePrecision.resolve(symbol: symbol, marketClass: marketClass, referencePrice: q.price).format(q.price)) · \(q.statusBadgeText())")
                                    .monospacedDigit()
                            }
                        }
                    }

                    Section("Order setup") {
                        Picker("Order type", selection: $orderType) {
                            Text("Market (live price)").tag(DemoOrderType.market)
                            Text("Limit (entry level)").tag(DemoOrderType.limit)
                        }
                        Picker("Exit target", selection: $exitTarget) {
                            Text("Target 1").tag(DemoExitTarget.target1)
                            if levels.isTP2Enabled {
                                Text("Target 2").tag(DemoExitTarget.target2)
                            }
                        }
                        .pickerStyle(.segmented)

                        VStack(alignment: .leading) {
                            HStack {
                                Text("Risk per trade")
                                Spacer()
                                Text("\(String(format: "%.1f", riskPercent))%")
                                    .monospacedDigit()
                            }
                            Slider(value: $riskPercent, in: 0.5...5.0, step: 0.5)
                        }
                    }

                    if let err = errorMessage {
                        Section {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(palette.shortCrimson)
                            if showStaleConfirm {
                                Toggle("Confirm fill using stale price (>60s)", isOn: $allowStaleOverride)
                                    .font(.caption)
                            }
                        }
                    }

                    Section {
                        Button {
                            submitDemoOrder()
                        } label: {
                            Text("Place Demo \(direction.rawValue.uppercased())")
                                .frame(maxWidth: .infinity)
                                .fontWeight(.bold)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(direction == .long ? palette.longEmerald : palette.shortCrimson)
                    }
                } else {
                    Section {
                        Text("Log this setup in your personal real-trade journal (no broker connection or order execution).")
                            .font(.caption)
                            .foregroundStyle(palette.secondaryInk)
                        Button("Open Trade Journal Entry") {
                            let existing = sourceSignal.flatMap { coordinator.journalEntry(forSignalFingerprint: $0.fingerprint) }
                            let draft: JournalEntrySnapshot
                            if let existing {
                                draft = existing
                            } else if let sig = sourceSignal {
                                draft = coordinator.makeJournalDraft(from: sig)
                            } else {
                                draft = JournalEntrySnapshot(
                                    symbol: symbol,
                                    marketClass: marketClass,
                                    timeframe: timeframe,
                                    direction: direction,
                                    plannedEntry: levels.entryMid,
                                    stopLoss: levels.stopLoss,
                                    tp1: levels.tp1,
                                    tp2: levels.isTP2Enabled ? levels.tp2 : nil
                                )
                            }
                            dismiss()
                            onOpenJournalDraft(draft, existing != nil)
                        }
                    }
                }
            }
            .navigationTitle("Trade \(symbol)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func submitDemoOrder() {
        errorMessage = nil
        showStaleConfirm = false
        let now = Date().timeIntervalSince1970
        let fillBars = PassiveOutcomeEvaluator.defaultFillWindowBars(for: timeframe)
        let expiry = now + Double(fillBars) * timeframe.seconds

        let req = DemoOrderRequest(
            signalId: sourceSignal?.id,
            symbol: symbol,
            marketClass: marketClass,
            timeframe: timeframe,
            direction: direction,
            orderType: orderType,
            entryPrice: levels.entryMid,
            entryLow: levels.entryLow,
            entryHigh: levels.entryHigh,
            stopLoss: levels.stopLoss,
            target1: levels.tp1,
            target2: levels.isTP2Enabled ? levels.tp2 : nil,
            exitTarget: exitTarget,
            riskPercent: riskPercent,
            limitExpiryEpochSeconds: orderType == .limit ? expiry : nil,
            allowStalePriceFill: allowStaleOverride,
            feesEnabled: coordinator.settings.payload.demoWalletFeesEnabled
        )

        switch coordinator.placeDemoOrder(req) {
        case .success(let pos):
            dismiss()
            onDemoPlaced(pos)
        case .failure(let err):
            errorMessage = err.userMessage
            if case .staleLiveQuote = err {
                showStaleConfirm = true
            } else if case .marketClosed(_, true) = err {
                orderType = .limit
            }
        }
    }
}

private struct EditDemoLevelsSheet: View {
    let position: DemoPosition
    let precision: ChartPricePrecision
    @Bindable var coordinator: MarketScannerCoordinator
    let palette: ConfluencePalette
    let onSaved: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var slText: String
    @State private var t1Text: String
    @State private var t2Text: String
    @State private var exitTarget: DemoExitTarget
    @State private var errorMessage: String? = nil

    init(
        position: DemoPosition,
        precision: ChartPricePrecision,
        coordinator: MarketScannerCoordinator,
        palette: ConfluencePalette,
        onSaved: @escaping (String) -> Void
    ) {
        self.position = position
        self.precision = precision
        self.coordinator = coordinator
        self.palette = palette
        self.onSaved = onSaved
        _slText = State(initialValue: precision.format(position.stopLoss))
        _t1Text = State(initialValue: precision.format(position.target1))
        _t2Text = State(initialValue: position.target2.map { precision.format($0) } ?? "")
        _exitTarget = State(initialValue: position.exitTarget)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Levels (\(position.symbol) · \(position.direction.rawValue.uppercased()))") {
                    HStack {
                        Text("Stop loss")
                        Spacer()
                        TextField("Stop loss", text: $slText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Target 1")
                        Spacer()
                        TextField("Target 1", text: $t1Text)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Target 2 (optional)")
                        Spacer()
                        TextField("Optional", text: $t2Text)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Picker("Exit target", selection: $exitTarget) {
                        Text("Target 1").tag(DemoExitTarget.target1)
                        Text("Target 2").tag(DemoExitTarget.target2)
                    }
                    .pickerStyle(.segmented)
                }

                if let err = errorMessage {
                    Section {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(palette.shortCrimson)
                    }
                }
            }
            .navigationTitle("Edit Stop loss & Targets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveEdits() }
                }
            }
        }
    }

    private func saveEdits() {
        errorMessage = nil
        guard let newSL = Double(slText), let newT1 = Double(t1Text) else {
            errorMessage = "Enter valid numeric values for Stop loss and Target 1."
            return
        }
        let newT2: Double? = t2Text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : Double(t2Text)
        if !t2Text.trimmingCharacters(in: .whitespaces).isEmpty && newT2 == nil {
            errorMessage = "Target 2 must be a valid number."
            return
        }

        if case .failure(let err) = coordinator.updateDemoStopLoss(positionId: position.id, newStopLoss: newSL) {
            errorMessage = err.userMessage
            return
        }
        if case .failure(let err) = coordinator.updateDemoTargets(
            positionId: position.id,
            newTarget1: newT1,
            newTarget2: newT2,
            newExitTarget: exitTarget
        ) {
            errorMessage = err.userMessage
            return
        }
        dismiss()
        onSaved("Updated Stop loss and targets for \(position.symbol).")
    }
}

// MARK: - LightweightCharts v5.2.0 Bridge (Mod 1 Overlays + Native update() + Paging Delegate)

private struct LightweightChartContainer: UIViewRepresentable {
    let closedCandles: [Candle]
    let formingCandle: Candle?
    let dataSetRevision: Int
    let liveUpdateToken: Int
    let fitRequestToken: Int
    let levels: TradeLevels?
    let overlays: ChartOverlayData
    let livePrice: Double?
    let breakevenPrice: Double?
    let markers: [SeriesMarker]
    let pricePrecision: ChartPricePrecision
    let timeframe: Timeframe
    let providerTag: String
    let isDark: Bool
    let onNeedOlderHistory: () -> Void

    @MainActor
    final class Coordinator: NSObject, TimeScaleDelegate {
        var series: CandlestickSeries?
        var markersPlugin: SeriesMarkersPlugin<CandlestickSeries>?
        var priceLines: [PriceLine] = []
        var livePriceLine: PriceLine?
        var lastDataSignature: String = ""
        var lastOverlaySignature: String = ""
        var lastLiveToken: Int = -1
        var lastFitToken: Int = -1
        var onNeedOlderHistory: (() -> Void)?

        func didVisibleTimeRangeChange(onTimeScale timeScale: TimeScaleApi, parameters: TimeRange?) {}

        func didVisibleLogicalRangeChange(onTimeScale timeScale: TimeScaleApi, parameters: LogicalRange?) {
            guard let from = parameters?.from else { return }
            if from <= ChartPagingPolicy.triggerBarsBeforeLeftEdge {
                onNeedOlderHistory?()
            }
        }

        func didReceiveTimeScaleSizeChangeWithParameters(onTimeScale timeScale: TimeScaleApi, parameters: LWCChartRectangle?) {}
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
        context.coordinator.series = series
        context.coordinator.onNeedOlderHistory = onNeedOlderHistory

        let timeScale = chartView.timeScale()
        timeScale.delegate = context.coordinator
        timeScale.subscribeVisibleLogicalRangeChange()

        applyFullData(to: chartView, coordinator: context.coordinator, shouldFit: true)
        applyOverlays(to: chartView, coordinator: context.coordinator)
        return chartView
    }

    func updateUIView(_ uiView: LightweightCharts, context: Context) {
        let coord = context.coordinator
        coord.onNeedOlderHistory = onNeedOlderHistory

        let dataSig = "\(dataSetRevision)|\(timeframe.rawValue)|\(providerTag)|\(pricePrecision.precision)|\(isDark)"
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
        if coord.lastLiveToken != liveUpdateToken, let forming = formingCandle, let series = coord.series {
            coord.lastLiveToken = liveUpdateToken
            series.update(bar: CandlestickData(
                time: .utc(timestamp: forming.openTimeEpochSeconds),
                open: forming.open,
                high: forming.high,
                low: forming.low,
                close: forming.close
            ))
        }

        let overlaySig = buildOverlaySignature()
        if coord.lastOverlaySignature != overlaySig {
            applyOverlays(to: uiView, coordinator: coord)
        }
        updateLivePriceLine(coordinator: coord)
    }

    private func buildAutoscaleProvider() -> AutoscaleInfoProvider {
        var corePrices: [Double] = []
        if let lv = levels {
            corePrices.append(contentsOf: [lv.entryMid, lv.stopLoss, lv.tp1])
            if lv.isTP2Enabled {
                corePrices.append(lv.tp2)
            }
        }
        for trap in overlays.traps where trap.isActionable {
            corePrices.append(trap.level)
        }
        let js = ChartAutoscaleScriptBuilder.makeProviderJS(corePrices: corePrices, maxDeviationFraction: 0.20)
        return AutoscaleInfoProvider(.javaScript(js))
    }

    private func buildOverlaySignature() -> String {
        let lvSig: String
        if let lv = levels {
            lvSig = "\(lv.entryMid)|\(lv.stopLoss)|\(lv.tp1)|\(lv.tp2)|\(lv.isTP2Enabled)"
        } else {
            lvSig = "none"
        }
        let trapSig = overlays.traps.filter(\.isActionable).map { "\($0.direction.rawValue):\($0.level)" }.joined(separator: ",")
        let beSig = breakevenPrice.map { String(format: "%.6f", $0) } ?? "none"
        return "\(lvSig)|\(trapSig)|\(beSig)|\(markers.count)"
    }

    private func applyFullData(to chartView: LightweightCharts, coordinator: Coordinator, shouldFit: Bool) {
        guard let series = coordinator.series else { return }
        coordinator.lastDataSignature = "\(dataSetRevision)|\(timeframe.rawValue)|\(providerTag)|\(pricePrecision.precision)|\(isDark)"

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

        // Preserve ALL trade overlays: Entry, Stop loss, Target 1, Target 2, Active Traps, Breakeven
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
                title: "T1"
            )))
            if lv.isTP2Enabled {
                coordinator.priceLines.append(series.createPriceLine(options: PriceLineOptions(
                    price: lv.tp2,
                    color: ChartColor(hex: 0x38BDF8),
                    lineWidth: .one,
                    lineStyle: .dashed,
                    axisLabelVisible: true,
                    title: "T2"
                )))
            }
        }

        if let be = breakevenPrice, be.isFinite, be > 0 {
            coordinator.priceLines.append(series.createPriceLine(options: PriceLineOptions(
                price: be,
                color: ChartColor(hex: 0x38BDF8),
                lineWidth: .one,
                lineStyle: .dashed,
                axisLabelVisible: true,
                title: "BE"
            )))
        }

        for trap in overlays.traps where trap.isActionable {
            coordinator.priceLines.append(series.createPriceLine(options: PriceLineOptions(
                price: trap.level,
                color: ChartColor(hex: 0xF59E0B),
                lineWidth: .one,
                lineStyle: .dashed,
                axisLabelVisible: true,
                title: trap.direction.rawValue
            )))
        }

        // Trade Replay Markers with autoScale: false so markers never stretch price axis
        if !markers.isEmpty {
            if let plugin = coordinator.markersPlugin {
                plugin.setMarkers(markers)
            } else {
                coordinator.markersPlugin = series.createMarkersPlugin(
                    data: markers,
                    options: SeriesMarkersOptions(active: true, autoScale: false)
                )
            }
        } else if let plugin = coordinator.markersPlugin {
            plugin.setMarkers([])
        }
    }

    private func updateLivePriceLine(coordinator: Coordinator) {
        guard let series = coordinator.series else { return }
        if let existing = coordinator.livePriceLine {
            series.removePriceLine(line: existing)
            coordinator.livePriceLine = nil
        }
        guard let lp = livePrice, lp.isFinite, lp > 0 else { return }
        let ref = closedCandles.last?.close ?? lp
        let colorHex: UInt32 = (lp >= ref) ? 0x10B981 : 0xEF4444
        coordinator.livePriceLine = series.createPriceLine(options: PriceLineOptions(
            price: lp,
            color: ChartColor(hex: colorHex),
            lineWidth: .one,
            lineStyle: .dashed,
            axisLabelVisible: true,
            title: "LIVE"
        ))
    }
}
