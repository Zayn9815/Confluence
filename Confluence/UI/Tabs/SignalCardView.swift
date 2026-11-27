import SwiftUI
@preconcurrency import Pow
import SignalEngine

// MARK: - Native SwiftUI Wrapping Flow Layout (Zero Mid-Word Pill Clipping)

public struct ConfluenceFlowLayout: Layout {
    public var horizontalSpacing: CGFloat
    public var verticalSpacing: CGFloat

    public init(horizontalSpacing: CGFloat = 6, verticalSpacing: CGFloat = 6) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > 0 && currentX + size.width > maxWidth {
                currentX = 0
                currentY += rowHeight + verticalSpacing
                rowHeight = 0
            }
            totalWidth = max(totalWidth, currentX + size.width)
            currentX += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? totalWidth, height: currentY + rowHeight)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > bounds.minX && currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += rowHeight + verticalSpacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height)
            )
            currentX += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Isolated Live Price Leaf Views (Zero Parent Card Invalidation on Ticks)

private struct SignalLivePriceLeafView: View {
    let symbol: String
    let marketClass: MarketClass
    let referencePrice: Double?
    let livePriceService: LivePriceService
    let palette: ConfluencePalette

    var body: some View {
        if let quote = livePriceService.latest(for: symbol) {
            let prec = PriceFormatHelper.precision(
                for: symbol,
                marketClass: marketClass,
                referencePrice: referencePrice ?? quote.price
            )
            let isUp = (referencePrice.map { quote.price >= $0 } ?? true)
            HStack(spacing: 4) {
                Circle()
                    .fill(quote.isStreaming ? palette.longEmerald : palette.secondaryInk)
                    .frame(width: 5, height: 5)
                Text(prec.format(quote.price))
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(isUp ? palette.longEmerald : palette.shortCrimson)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(palette.elevatedSurface, in: Capsule())
        }
    }
}

private struct SignalMiniChartLeafView: View {
    let symbol: String
    let candles: [Candle]
    let levels: TradeLevels?
    let overlays: ChartOverlayData
    let palette: ConfluencePalette
    let height: CGFloat
    let livePriceService: LivePriceService

    @State private var throttledLivePrice: Double? = nil
    @State private var miniThrottle = LiveChartThrottle(minimumIntervalSeconds: 1.0)

    var body: some View {
        let latestPrice = livePriceService.latest(for: symbol)?.price
        MiniCandlestickCanvas(
            candles: candles,
            levels: levels,
            overlays: overlays,
            palette: palette,
            height: height,
            livePrice: throttledLivePrice
        )
        .equatable()
        .onAppear {
            if throttledLivePrice == nil, let latestPrice {
                throttledLivePrice = latestPrice
            }
        }
        .onChange(of: latestPrice) { _, newPrice in
            guard let newPrice else { return }
            let now = Date().timeIntervalSince1970
            if throttledLivePrice == nil || miniThrottle.shouldEmit(at: now) {
                throttledLivePrice = newPrice
            }
        }
    }
}

// MARK: - Signal Card View (Clean Collapsed Face + In-Place Smooth Expansion)

public struct SignalCardView: View {
    let signal: TradeSignal
    let outcome: SignalOutcomeRecord?
    let displayLevelsOverride: TradeLevels?
    let brokerOffsetInfo: BrokerPriceOffset?
    let isBrokerAdjusted: Bool
    let correlationWarnings: [CorrelationPairWarning]
    let use24HourTime: Bool
    let useUTCTimeZone: Bool
    let palette: ConfluencePalette
    let density: CardDensity
    let showMiniChart: Bool
    let animateArrival: Bool
    let hapticsEnabled: Bool
    let isSelecting: Bool
    let isSelected: Bool
    let isExpanded: Bool
    let livePriceService: LivePriceService
    let onToggleExpand: () -> Void
    let onToggleSelect: (() -> Void)?
    let onDelete: (() -> Void)?
    let onToggleBrokerAdjusted: (() -> Void)?
    let onOpenPositionSizer: (() -> Void)?
    let onOpenOrderFlow: ((ChartOrderFlowSummary) -> Void)?
    let onOpenGlossaryTerm: ((String) -> Void)?
    let onOpenChart: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showStrategyDetails = false
    @State private var showScoreExplanation = false
    @State private var arrivalTriggerCount = 0
    @State private var didCopy = false

    public init(
        signal: TradeSignal,
        outcome: SignalOutcomeRecord? = nil,
        displayLevelsOverride: TradeLevels? = nil,
        brokerOffsetInfo: BrokerPriceOffset? = nil,
        isBrokerAdjusted: Bool = false,
        correlationWarnings: [CorrelationPairWarning] = [],
        use24HourTime: Bool = false,
        useUTCTimeZone: Bool = false,
        palette: ConfluencePalette,
        density: CardDensity,
        showMiniChart: Bool,
        animateArrival: Bool,
        hapticsEnabled: Bool,
        isSelecting: Bool = false,
        isSelected: Bool = false,
        isExpanded: Bool = false,
        livePriceService: LivePriceService,
        onToggleExpand: @escaping () -> Void = {},
        onToggleSelect: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onToggleBrokerAdjusted: (() -> Void)? = nil,
        onOpenPositionSizer: (() -> Void)? = nil,
        onOpenOrderFlow: ((ChartOrderFlowSummary) -> Void)? = nil,
        onOpenGlossaryTerm: ((String) -> Void)? = nil,
        onOpenChart: @escaping () -> Void
    ) {
        self.signal = signal
        self.outcome = outcome
        self.displayLevelsOverride = displayLevelsOverride
        self.brokerOffsetInfo = brokerOffsetInfo
        self.isBrokerAdjusted = isBrokerAdjusted
        self.correlationWarnings = correlationWarnings
        self.use24HourTime = use24HourTime
        self.useUTCTimeZone = useUTCTimeZone
        self.palette = palette
        self.density = density
        self.showMiniChart = showMiniChart
        self.animateArrival = animateArrival
        self.hapticsEnabled = hapticsEnabled
        self.isSelecting = isSelecting
        self.isSelected = isSelected
        self.isExpanded = isExpanded
        self.livePriceService = livePriceService
        self.onToggleExpand = onToggleExpand
        self.onToggleSelect = onToggleSelect
        self.onDelete = onDelete
        self.onToggleBrokerAdjusted = onToggleBrokerAdjusted
        self.onOpenPositionSizer = onOpenPositionSizer
        self.onOpenOrderFlow = onOpenOrderFlow
        self.onOpenGlossaryTerm = onOpenGlossaryTerm
        self.onOpenChart = onOpenChart
    }

    private var activeLevels: TradeLevels? {
        displayLevelsOverride ?? signal.levels
    }

    private var compactPreviewLine: String {
        let stratCount = max(signal.matchedStrategyIDs.count, signal.alignedStrategies.count)
        let proDir = signal.psychologyReport.proDirection.rawValue.capitalized
        var parts: [String] = []
        if stratCount > 0 {
            parts.append("\(stratCount) \(stratCount == 1 ? "strategy" : "strategies")")
        }
        parts.append("Pro: \(proDir)")
        parts.append(signal.killzone.displayName)
        return parts.joined(separator: " · ")
    }

    public var body: some View {
        let dec = PriceFormatHelper.decimals(for: signal.symbol, marketClass: signal.marketClass, referencePrice: activeLevels?.entryMid)
        let accentBorder: Color? = {
            if isSelecting && isSelected { return palette.shortCrimson.opacity(0.85) }
            if signal.tier == .aPlusInstitutional { return palette.champagneGold.opacity(0.60) }
            if signal.category == .trapAlert { return palette.trapAmber.opacity(0.60) }
            return nil
        }()
        let gridCols: [GridItem] = dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
            : [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

        VStack(alignment: .leading, spacing: density == .compact ? 10 : 12) {
            // 1. Header Row: Selection Checkmark (when selecting), Market/TF/Direction, Symbol + Isolated Live Price, Score Ring
            HStack(alignment: .center, spacing: 10) {
                if isSelecting {
                    Button {
                        onToggleSelect?()
                    } label: {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isSelected ? palette.shortCrimson : palette.tertiaryInk)
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 4) {
                    ConfluenceFlowLayout(horizontalSpacing: 6, verticalSpacing: 4) {
                        badgePill(signal.marketClass.displayName.uppercased(), color: palette.secondaryInk, fill: palette.elevatedSurface)
                        badgePill(signal.timeframe.displayLabel, color: palette.primaryInk, fill: palette.elevatedSurface)
                        directionOrTrapBadge
                    }
                    HStack(alignment: .center, spacing: 6) {
                        Text(signal.symbol)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(palette.primaryInk)
                            .lineLimit(1)
                            .layoutPriority(1)
                        SignalLivePriceLeafView(
                            symbol: signal.symbol,
                            marketClass: signal.marketClass,
                            referencePrice: activeLevels?.entryMid ?? signal.recentCandles.last?.close,
                            livePriceService: livePriceService,
                            palette: palette
                        )
                    }
                    HStack(spacing: 5) {
                        Text(signal.strengthBreakdown?.strengthLabel ?? signal.tier.displayName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(palette.color(for: signal.tier))
                            .lineLimit(1)
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(palette.tertiaryInk)
                        Text(formattedGeneratedStamp(epochSeconds: signal.generatedAtEpochSeconds))
                            .font(.caption2.weight(.medium).monospacedDigit())
                            .foregroundStyle(palette.secondaryInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
                Spacer(minLength: 4)
                confidenceGauge
            }

            // 2. Compact Status Row (Max 3 high-signal pills: Lifecycle + Regime + Tappable Order Flow Sign)
            ConfluenceFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                if let lifecycle = lifecycleBadge {
                    badgePill(lifecycle.text, color: lifecycle.color, fill: lifecycle.color.opacity(0.14))
                }
                badgePill(signal.regime.badgeLabel, color: palette.color(for: signal.regime), fill: palette.color(for: signal.regime).opacity(0.14))
                if signal.marketClass == .crypto, let ofSummary = signal.orderFlowSummary {
                    OrderFlowSignPill(summary: ofSummary, palette: palette) {
                        onOpenOrderFlow?(ofSummary)
                    }
                } else if signal.isMarketClosedSnapshot {
                    let reasonText = signal.marketClosedReason ?? "Closed"
                    badgePill("Market Closed · \(reasonText)", color: palette.trapAmber, fill: palette.trapAmber.opacity(0.14))
                }
            }

            // 3. Non-Interactive Mini Candlestick Snapshot (tap -> FullScreenChartSheet)
            if showMiniChart && !signal.recentCandles.isEmpty {
                Button {
                    if isSelecting {
                        onToggleSelect?()
                    } else {
                        onOpenChart()
                    }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        SignalMiniChartLeafView(
                            symbol: signal.symbol,
                            candles: signal.recentCandles,
                            levels: activeLevels,
                            overlays: signal.overlays,
                            palette: palette,
                            height: density == .compact ? 84 : 108,
                            livePriceService: livePriceService
                        )
                        Label("Interactive", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(palette.secondaryInk)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(6)
                    }
                }
                .buttonStyle(.plain)
            }

            // 4. Visual Risk-Reward Ladder + 2x3 Numeric Trade Grid (Compact shows full-anchor ladder only; Standard shows compact rail + full 2x3 grid)
            if let lv = activeLevels {
                let levelDec = PriceFormatHelper.decimals(for: signal.symbol, marketClass: signal.marketClass, referencePrice: lv.entryMid)
                SignalRiskRewardLadderView(
                    symbol: signal.symbol,
                    marketClass: signal.marketClass,
                    direction: signal.direction,
                    levels: lv,
                    livePriceService: livePriceService,
                    palette: palette,
                    showFullAnchors: density == .compact
                )

                if density != .compact {
                    LazyVGrid(columns: gridCols, spacing: 8) {
                        entryZoneCell(
                            low: PriceFormatHelper.format(lv.entryLow, decimals: levelDec),
                            high: PriceFormatHelper.format(lv.entryHigh, decimals: levelDec),
                            mid: PriceFormatHelper.format(lv.entryMid, decimals: levelDec)
                        )
                        metricCell(
                            title: "STOP LOSS",
                            value: PriceFormatHelper.format(lv.stopLoss, decimals: levelDec),
                            sub: "-\(String(format: "%.2f", lv.riskPercent))% Risk",
                            accent: palette.shortCrimson
                        )
                        metricCell(
                            title: "R:R RATIO",
                            value: "1:\(String(format: "%.2f", lv.riskRewardRatio))",
                            sub: lv.isTP2Enabled ? "Target 2 1:\(String(format: "%.1f", lv.tp2RiskRewardRatio))" : "Target 1 Only",
                            accent: palette.primaryInk
                        )
                        metricCell(
                            title: "TARGET 1",
                            value: PriceFormatHelper.format(lv.tp1, decimals: levelDec),
                            sub: "+\(String(format: "%.2f", lv.reward1Percent))%",
                            accent: palette.longEmerald
                        )
                        if lv.isTP2Enabled {
                            metricCell(
                                title: "TARGET 2",
                                value: PriceFormatHelper.format(lv.tp2, decimals: levelDec),
                                sub: "+\(String(format: "%.2f", lv.reward2Percent))%",
                                accent: palette.longEmerald
                            )
                        } else {
                            metricCell(
                                title: "TARGET 2",
                                value: "Disabled",
                                sub: "Settings -> Rules",
                                accent: palette.tertiaryInk
                            )
                        }
                        metricCell(
                            title: "CONFLUENCE",
                            value: "\(signal.alignedStrategies.count) Signals",
                            sub: isBrokerAdjusted ? "\(signal.dataProvider) + Offset" : signal.dataProvider,
                            accent: palette.secondaryInk
                        )
                    }
                }
            }

            // 5. Full-Width "Show more info" / "Hide info" Toggle Bar
            Button {
                onToggleExpand()
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isExpanded ? "Hide info" : "Show more info")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.primaryInk)
                        if !isExpanded {
                            Text(compactPreviewLine)
                                .font(.caption2)
                                .foregroundStyle(palette.secondaryInk)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(palette.champagneGold)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: isExpanded)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.elevatedSurface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(palette.border, lineWidth: 0.75)
                )
            }
            .buttonStyle(.plain)

            // 6. Expanded In-Place Institutional Details
            if isExpanded {
                expandedDetailContent(decimals: dec)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(density == .compact ? 12 : 15)
        .institutionalCard(palette: palette, accentBorder: accentBorder)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting {
                onToggleSelect?()
            }
        }
        .contextMenu {
            Button {
                onOpenChart()
            } label: {
                Label("Open Interactive Chart", systemImage: "chart.xyaxis.line")
            }
            if signal.marketClass == .crypto, let ofSummary = signal.orderFlowSummary {
                Button {
                    onOpenOrderFlow?(ofSummary)
                } label: {
                    Label("Order Flow Breakdown", systemImage: "waveform.path.ecg")
                }
            }
            if let onOpenPositionSizer, activeLevels != nil {
                Button {
                    onOpenPositionSizer()
                } label: {
                    Label("Position Size Calculator", systemImage: "function")
                }
            }
            Button {
                UIPasteboard.general.string = formattedSetupCopyText(decimals: dec)
            } label: {
                Label("Copy Setup", systemImage: "doc.on.doc")
            }
            if let onDelete {
                Divider()
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete Signal", systemImage: "trash")
                }
            }
        }
        .changeEffect(.shine(duration: 0.9), value: arrivalTriggerCount, isEnabled: animateArrival && !reduceMotion)
        .onAppear {
            if animateArrival && !reduceMotion && arrivalTriggerCount == 0 {
                arrivalTriggerCount = 1
            }
        }
    }

    // MARK: - Expanded In-Place Content

    @ViewBuilder
    private func expandedDetailContent(decimals dec: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Wrapping context pills (zero mid-word clipping)
            ConfluenceFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                badgePill(signal.killzone.displayName, color: palette.secondaryInk, fill: palette.elevatedSurface)
                badgePill("HTF \(signal.htfTimeframe.displayLabel): \(signal.htfBias.rawValue.uppercased())", color: palette.color(for: signal.htfBias), fill: palette.elevatedSurface)

                ForEach(correlationWarnings.prefix(3)) { warn in
                    badgePill(warn.badgeText, color: palette.trapAmber, fill: palette.trapAmber.opacity(0.14))
                }
                if let offsetInfo = brokerOffsetInfo {
                    Button {
                        onToggleBrokerAdjusted?()
                    } label: {
                        let staleSuffix = offsetInfo.isStale() ? " · Stale >24h" : ""
                        let label = isBrokerAdjusted ? "Broker-Adjusted\(staleSuffix)" : "Feed Prices (Tap for Broker)"
                        badgePill(
                            label,
                            color: isBrokerAdjusted ? palette.champagneGold : palette.secondaryInk,
                            fill: (isBrokerAdjusted ? palette.champagneGold : palette.elevatedSurface).opacity(isBrokerAdjusted ? 0.16 : 1.0)
                        )
                    }
                    .buttonStyle(.plain)
                }
                if signal.isMarketClosedSnapshot, signal.marketClass == .crypto, signal.orderFlowSummary != nil {
                    let reasonText = signal.marketClosedReason ?? "Last Bar"
                    badgePill("Market Closed · \(reasonText)", color: palette.trapAmber, fill: palette.trapAmber.opacity(0.14))
                }
                if let pre = signal.preNewsBadge {
                    badgePill(pre, color: palette.trapAmber, fill: palette.trapAmber.opacity(0.14))
                }
                if let post = signal.postNewsCatalystBadge {
                    badgePill(post, color: palette.champagneGold, fill: palette.champagneGold.opacity(0.14))
                }
            }

            // Signal Strength Breakdown (4 transparent quantitative pillars)
            if let bd = signal.strengthBreakdown {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.caption2)
                            .foregroundStyle(palette.champagneGold)
                        Text("Signal Strength Breakdown · \(bd.strengthLabel)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.primaryInk)
                    }
                    breakdownRow("Technical Math (ICT / Trend / HTF)", score: bd.technicalScore)
                    breakdownRow("Psychology & Positioning", score: bd.psychologyScore)
                    breakdownRow("News & Macro Catalyst", score: bd.newsMacroScore)
                    breakdownRow("Regime & Session Risk Adj.", score: bd.regimeRiskAdjustment)
                    Divider().overlay(palette.border)
                    HStack {
                        Text("Raw Confluence Score")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(palette.primaryInk)
                        Spacer()
                        Text("\(Int(bd.finalConfidencePercent.rounded()))/100 · \(bd.strengthLabel)")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(palette.color(for: signal.tier))
                    }
                    if let calProb = signal.calibratedProbability {
                        HStack {
                            Text("Calibrated Win Prob. (n=\(signal.calibrationSampleCount ?? 100))")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(palette.secondaryInk)
                            Spacer()
                            Text("\(Int((calProb * 100.0).rounded()))%")
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(palette.champagneGold)
                        }
                    }
                    if !bd.notes.isEmpty {
                        Text(bd.notes.joined(separator: " · "))
                            .font(.system(size: 10))
                            .foregroundStyle(palette.tertiaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .background(palette.elevatedSurface.opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            // Matched Strategies Provenance (Wrapping FlowLayout + Glossary (i) deep-link)
            if !signal.alignedStrategies.isEmpty || !signal.matchedStrategyIDs.isEmpty {
                let matchedCount = max(signal.matchedStrategyIDs.count, signal.alignedStrategies.count)
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("Matched Strategies (\(matchedCount))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.primaryInk)
                        Spacer()
                        if !signal.alignedStrategies.isEmpty {
                            Button {
                                withAnimation(.snappy(duration: 0.22, extraBounce: 0.0)) {
                                    showStrategyDetails.toggle()
                                }
                            } label: {
                                Text(showStrategyDetails ? "Hide weights" : "Show weights")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(palette.champagneGold)
                            }
                            .buttonStyle(.plain)
                        }
                        if let onOpenGlossaryTerm {
                            Button {
                                onOpenGlossaryTerm("")
                            } label: {
                                Image(systemName: "info.circle")
                                    .font(.caption)
                                    .foregroundStyle(palette.secondaryInk)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open strategy glossary")
                        }
                    }

                    ConfluenceFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                        if !signal.matchedStrategyIDs.isEmpty {
                            ForEach(signal.matchedStrategyIDs) { sid in
                                Button {
                                    onOpenGlossaryTerm?(sid.displayName)
                                } label: {
                                    badgePill(sid.displayName, color: palette.primaryInk, fill: palette.elevatedSurface)
                                }
                                .buttonStyle(.plain)
                            }
                        } else {
                            ForEach(signal.alignedStrategies) { strat in
                                Button {
                                    onOpenGlossaryTerm?(strat.name)
                                } label: {
                                    badgePill(StrategyID.displayName(forRawKey: strat.name), color: palette.primaryInk, fill: palette.elevatedSurface)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if showStrategyDetails {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(signal.alignedStrategies) { strat in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle()
                                        .fill(palette.color(for: strat.direction))
                                        .frame(width: 6, height: 6)
                                        .padding(.top, 5)
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text(StrategyID.displayName(forRawKey: strat.name))
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(palette.primaryInk)
                                            Spacer()
                                            Text("W \(String(format: "%.2f", strat.weight)) · WR \(Int((strat.historicalWinRate * 100).rounded()))%")
                                                .font(.caption2.monospacedDigit())
                                                .foregroundStyle(palette.tertiaryInk)
                                        }
                                        Text(strat.detail)
                                            .font(.caption2)
                                            .foregroundStyle(palette.secondaryInk)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                        .padding(10)
                        .background(palette.elevatedSurface.opacity(0.75), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }

            // Market Psychology & Pro-vs-Beginner Module
            psychologyModule

            // Optional AI Judge 1-line Caution / Confirmation Badge
            if let ai = signal.aiJudgment {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: signal.aiConfirmed ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(signal.aiConfirmed ? palette.champagneGold : palette.trapAmber)
                        .font(.caption)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(signal.aiConfirmed ? "AI Judge Confirmed (Q\(ai.setupQuality)/3 · \(Int((ai.confidence * 100).rounded()))%)" : "AI Judge Caution (Q\(ai.setupQuality)/3 · \(ai.riskState.rawValue))")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(signal.aiConfirmed ? palette.champagneGold : palette.trapAmber)
                        Text(ai.invalidationCheck)
                            .font(.caption2)
                            .foregroundStyle(palette.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.elevatedSurface.opacity(0.8), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            // Footer Actions: Bar Timestamp + Position Sizer + Order Flow + Delete + Copy Setup
            VStack(alignment: .leading, spacing: 8) {
                Text("Bar \(TimeDisplayFormatter.formatDateTime(epochSeconds: signal.barCloseEpochSeconds, use24Hour: use24HourTime, useUTC: useUTCTimeZone))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(palette.tertiaryInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                ConfluenceFlowLayout(horizontalSpacing: 7, verticalSpacing: 7) {
                    if let onOpenPositionSizer, activeLevels != nil {
                        Button {
                            onOpenPositionSizer()
                        } label: {
                            Label("Size", systemImage: "function")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(palette.primaryInk)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(palette.elevatedSurface, in: Capsule())
                                .overlay(Capsule().strokeBorder(palette.border, lineWidth: 0.75))
                        }
                        .buttonStyle(.plain)
                    }

                    if signal.marketClass == .crypto, let ofSummary = signal.orderFlowSummary {
                        Button {
                            onOpenOrderFlow?(ofSummary)
                        } label: {
                            Label("Order Flow", systemImage: "waveform.path.ecg")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(palette.champagneGold)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(palette.elevatedSurface, in: Capsule())
                                .overlay(Capsule().strokeBorder(palette.champagneGold.opacity(0.4), lineWidth: 0.75))
                        }
                        .buttonStyle(.plain)
                    }

                    if !isSelecting, let onDelete {
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(palette.shortCrimson.opacity(0.85))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(palette.elevatedSurface, in: Capsule())
                                .overlay(Capsule().strokeBorder(palette.border, lineWidth: 0.75))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete signal")
                    }

                    Button {
                        UIPasteboard.general.string = formattedSetupCopyText(decimals: dec)
                        SignalSoundEngine.shared.playCopyConfirmationHaptic(enabled: hapticsEnabled)
                        withAnimation { didCopy = true }
                        Task {
                            try? await Task.sleep(nanoseconds: 1_400_000_000)
                            withAnimation { didCopy = false }
                        }
                    } label: {
                        Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(didCopy ? palette.longEmerald : palette.primaryInk)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(palette.elevatedSurface, in: Capsule())
                            .overlay(Capsule().strokeBorder(palette.border, lineWidth: 0.75))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func formattedSetupCopyText(decimals: Int) -> String {
        guard isBrokerAdjusted, let lv = activeLevels else {
            return signal.formattedCopyText(decimals: decimals)
        }
        let fmt = "%.\(decimals)f"
        var lines = [
            "CONFLUENCE \(signal.direction.rawValue.uppercased()) | \(signal.symbol) (\(signal.timeframe.displayLabel)) [Broker-Adjusted]",
            "Score: \(Int(signal.confidencePercent.rounded()))/100 (\(signal.tier.displayName)) | Regime: \(signal.regime.badgeLabel) | \(signal.killzone.displayName)",
            "Entry Zone: \(String(format: fmt, lv.entryLow)) - \(String(format: fmt, lv.entryHigh))",
            "Stop Loss: \(String(format: fmt, lv.stopLoss)) (-\(String(format: "%.2f", lv.riskPercent))%)",
            "TP1: \(String(format: fmt, lv.tp1)) (+\(String(format: "%.2f", lv.reward1Percent))%) | R:R 1:\(String(format: "%.2f", lv.riskRewardRatio))"
        ]
        if lv.isTP2Enabled {
            lines.append("TP2: \(String(format: fmt, lv.tp2)) (+\(String(format: "%.2f", lv.reward2Percent))%)")
        }
        return lines.joined(separator: "\n")
    }

    private func formattedGeneratedStamp(epochSeconds: TimeInterval) -> String {
        let dateTime = TimeDisplayFormatter.formatDateTime(epochSeconds: epochSeconds, use24Hour: use24HourTime, useUTC: useUTCTimeZone)
        let ageSeconds = max(0, Date().timeIntervalSince1970 - epochSeconds)
        let ageText: String
        if ageSeconds < 60 {
            ageText = "just now"
        } else if ageSeconds < 3_600 {
            ageText = "\(Int(ageSeconds / 60))m ago"
        } else if ageSeconds < 86_400 {
            ageText = "\(Int(ageSeconds / 3_600))h ago"
        } else {
            ageText = "\(Int(ageSeconds / 86_400))d ago"
        }
        return "\(dateTime) · \(ageText)"
    }

    private func entryZoneCell(low: String, high: String, mid: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("ENTRY ZONE")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(palette.tertiaryInk)
            Text(low)
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(palette.champagneGold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("to \(high)")
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(palette.champagneGold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("Mid \(mid)")
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(palette.secondaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(palette.elevatedSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func breakdownRow(_ title: String, score: Double) -> some View {
        let color: Color = score > 0.05 ? palette.longEmerald : (score < -0.05 ? palette.shortCrimson : palette.secondaryInk)
        return HStack {
            Text(title)
                .font(.caption2)
                .foregroundStyle(palette.secondaryInk)
            Spacer()
            Text(String(format: "%+.1f pts", score))
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
        }
    }

    private var directionOrTrapBadge: some View {
        Group {
            if signal.category == .trapAlert, let trap = signal.trapDirection {
                iconBadgePill(trap.rawValue, systemImage: "exclamationmark.triangle.fill", color: palette.trapAmber, fill: palette.trapAmber.opacity(0.16))
            } else if signal.category == .weakSignal {
                let icon = signal.direction == .long ? "arrow.up.right" : (signal.direction == .short ? "arrow.down.right" : "minus")
                iconBadgePill("WEAK · \(signal.direction.rawValue.uppercased())", systemImage: icon, color: palette.secondaryInk, fill: palette.elevatedSurface)
            } else {
                let c = palette.color(for: signal.direction)
                let icon = signal.direction == .long ? "arrow.up.right" : (signal.direction == .short ? "arrow.down.right" : "minus")
                iconBadgePill(signal.direction.rawValue.uppercased(), systemImage: icon, color: c, fill: c.opacity(0.16))
            }
        }
    }

    private var lifecycleBadge: (text: String, color: Color)? {
        guard signal.category == .strongSignal || signal.category == .trapAlert else { return nil }
        guard let rec = outcome else {
            return ("Pending Fill", palette.secondaryInk)
        }
        switch rec.status {
        case .pending:
            return ("Pending Fill", palette.secondaryInk)
        case .open:
            return ("Open · Filled", palette.champagneGold)
        case .hitTP2:
            return ("TP2 Win", palette.longEmerald)
        case .hitTP1:
            return ("TP1 Win", palette.longEmerald)
        case .hitSL:
            return ("SL Hit", palette.shortCrimson)
        case .notFilled:
            return ("Not Filled", palette.secondaryInk)
        case .invalidated:
            return ("Invalidated", palette.trapAmber)
        case .expired:
            return ("Expired", palette.tertiaryInk)
        }
    }

    private var confidenceGauge: some View {
        let rawScore = max(0, min(99, Int(signal.confidencePercent.rounded())))
        let ringColor = palette.color(for: signal.tier)
        let calPct: Int? = signal.calibratedProbability.map { max(1, min(99, Int(($0 * 100.0).rounded()))) }
        let sampleN = signal.calibrationSampleCount ?? 0
        let a11yText = calPct.map { "Signal score \(rawScore), calibrated probability \($0) percent" } ?? "Signal score \(rawScore) out of 100"

        return Button {
            showScoreExplanation = true
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    Circle()
                        .stroke(palette.border, lineWidth: 3.5)
                    Circle()
                        .trim(from: 0, to: CGFloat(rawScore) / 100.0)
                        .stroke(ringColor, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(rawScore)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(palette.primaryInk)
                        Text(calPct == nil ? "SCORE" : "RAW")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(palette.tertiaryInk)
                    }
                }
                .frame(width: 48, height: 48)
                .changeEffect(
                    .pulse(shape: Circle(), style: ringColor.opacity(0.5), count: 1),
                    value: arrivalTriggerCount,
                    isEnabled: animateArrival && !reduceMotion
                )

                if let calPct {
                    Text("Cal \(calPct)%")
                        .font(.system(size: 9, weight: .bold).monospacedDigit())
                        .foregroundStyle(palette.champagneGold)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(a11yText)
        .alert("Signal Score vs. Probability", isPresented: $showScoreExplanation) {
            Button("OK", role: .cancel) {}
        } message: {
            if let calPct {
                Text("Raw Confluence Score: \(rawScore)/100.\nCalibrated Win Probability: \(calPct)% (walk-forward Platt scaling fitted on n=\(sampleN) resolved filled trades).\n\nCalibrated probability is display-only; the minimum score gate always evaluates the raw score.")
            } else {
                Text("Score \(rawScore)/100 is a deterministic weighted confluence score — not a calibrated win probability yet.\n\nWalk-forward Platt calibration activates automatically once 100 resolved filled Strong signals are recorded. The minimum score gate always evaluates the raw score.")
            }
        }
    }

    private var psychologyModule: some View {
        let psych = signal.psychologyReport
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.caption)
                    .foregroundStyle(palette.champagneGold)
                Text("Market Psychology & Pro vs. Beginner")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.primaryInk)
            }

            VStack(spacing: 7) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("INTRADAY PRO FLOW")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(palette.tertiaryInk)
                        Text(psych.proDirection.rawValue.uppercased())
                            .font(.caption.weight(.bold))
                            .foregroundStyle(palette.color(for: psych.proDirection))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider().frame(height: 22).overlay(palette.border)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("RETAIL / BEGINNER CROWD")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(palette.tertiaryInk)
                        Text(psych.retailCrowdDirection.rawValue.uppercased())
                            .font(.caption.weight(.bold))
                            .foregroundStyle(palette.color(for: psych.retailCrowdDirection))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let macroDir = psych.macroPositioningDirection, macroDir != .neutral {
                    Divider().overlay(palette.border)
                    HStack(spacing: 6) {
                        Text((psych.macroPositioningLabel ?? "MACRO COT BIAS").uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(palette.tertiaryInk)
                        Text(macroDir.rawValue.uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(palette.color(for: macroDir))
                        Spacer()
                        if let aligns = psych.macroAlignsWithSetup {
                            badgePill(
                                aligns ? "Aligned" : "Counter-Trend",
                                color: aligns ? palette.longEmerald : palette.trapAmber,
                                fill: (aligns ? palette.longEmerald : palette.trapAmber).opacity(0.14)
                            )
                        }
                    }
                }
            }
            .padding(9)
            .background(palette.elevatedSurface.opacity(0.8), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Wrapping FlowLayout so long badges like "Osler Round-Number Sweep" never clip mid-word
            ConfluenceFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                badgePill(psych.provenanceBadge, color: palette.secondaryInk, fill: palette.elevatedSurface)
                ForEach(psych.behavioralBadges, id: \.self) { b in
                    badgePill(b, color: palette.trapAmber, fill: palette.trapAmber.opacity(0.14))
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                psychLine(label: "What Happened", text: psych.whatHappened, accent: palette.primaryInk)
                psychLine(label: "Beginner Mistake / Trap", text: psych.beginnerPsychology, accent: palette.trapAmber)
                psychLine(label: "Institutional Play", text: psych.proPsychology, accent: palette.longEmerald)

                if signal.category == .weakSignal && !signal.rejectionReasons.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Why Filtered Out")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(palette.shortCrimson)
                        ForEach(signal.rejectionReasons, id: \.self) { reason in
                            Text("• \(reason)")
                                .font(.caption2)
                                .foregroundStyle(palette.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(10)
            .background(palette.canvas.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func psychLine(label: String, text: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(accent)
            Text(text)
                .font(.caption2)
                .foregroundStyle(palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func metricCell(title: String, value: String, sub: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(palette.tertiaryInk)
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
            Text(sub)
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(palette.secondaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(palette.elevatedSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func badgePill(_ text: String, color: Color, fill: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold).monospacedDigit())
            .foregroundStyle(color)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(fill, in: Capsule())
    }

    private func iconBadgePill(_ text: String, systemImage: String, color: Color, fill: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
        }
        .foregroundStyle(color)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(fill, in: Capsule())
    }
}
