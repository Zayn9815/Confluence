import SwiftUI
import SignalEngine

/// Identifiable sheet payload used by both `SignalsTabView` and `TradeJournalView`
/// to present the plain-English `OrderFlowInsightSheet`.
public struct OrderFlowSheetPayload: Identifiable, Sendable {
    public let id: String
    public let symbol: String
    public let timeframe: Timeframe
    public let direction: TradeDirection
    public let summary: ChartOrderFlowSummary
    public let entry: Double?
    public let stopLoss: Double?
    public let target1: Double?
    public let target2: Double?
    public let isHistoricalSnapshot: Bool

    public init(
        id: String = UUID().uuidString,
        symbol: String,
        timeframe: Timeframe,
        direction: TradeDirection,
        summary: ChartOrderFlowSummary,
        entry: Double?,
        stopLoss: Double?,
        target1: Double?,
        target2: Double?,
        isHistoricalSnapshot: Bool = false
    ) {
        self.id = id
        self.symbol = symbol
        self.timeframe = timeframe
        self.direction = direction
        self.summary = summary
        self.entry = entry
        self.stopLoss = stopLoss
        self.target1 = target1
        self.target2 = target2
        self.isHistoricalSnapshot = isHistoricalSnapshot
    }
}

/// Compact tappable Order Flow sign capsule shared by Signal cards and Journal cards.
/// Displays `OF · Aligned` / `OF · Mixed` / `OF · Conflict` + chevron and opens `OrderFlowInsightSheet`.
public struct OrderFlowSignPill: View {
    public let summary: ChartOrderFlowSummary
    public let palette: ConfluencePalette
    public let onTap: () -> Void

    public init(
        summary: ChartOrderFlowSummary,
        palette: ConfluencePalette,
        onTap: @escaping () -> Void
    ) {
        self.summary = summary
        self.palette = palette
        self.onTap = onTap
    }

    private var descriptor: (label: String, color: Color) {
        switch summary.alignment {
        case OrderFlowAlignment.aligned.rawValue:
            return ("OF · Aligned", palette.longEmerald)
        case OrderFlowAlignment.conflicting.rawValue:
            return ("OF · Conflict", palette.shortCrimson)
        case OrderFlowAlignment.unavailable.rawValue:
            return ("OF · Thin", palette.secondaryInk)
        default:
            return ("OF · Mixed", palette.champagneGold)
        }
    }

    public var body: some View {
        let desc = descriptor
        Button(action: onTap) {
            HStack(spacing: 4) {
                Circle()
                    .fill(desc.color)
                    .frame(width: 6, height: 6)
                Text(desc.label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(desc.color)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(desc.color.opacity(0.85))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(desc.color.opacity(0.14), in: Capsule())
            .overlay(Capsule().strokeBorder(desc.color.opacity(0.35), lineWidth: 0.75))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(desc.label). Tap for plain-English order flow details.")
    }
}

/// Tappable plain-English Order Flow Detail Sheet driven by `OrderFlowNarrativeBuilder`.
/// Works identically for live `TradeSignal` cards and captured `TrackedJournalTrade` records.
public struct OrderFlowInsightSheet: View {
    public let payload: OrderFlowSheetPayload
    public let palette: ConfluencePalette
    public let use24HourTime: Bool
    public let useUTCTimeZone: Bool

    @Environment(\.dismiss) private var dismiss

    public init(
        payload: OrderFlowSheetPayload,
        palette: ConfluencePalette,
        use24HourTime: Bool = true,
        useUTCTimeZone: Bool = true
    ) {
        self.payload = payload
        self.palette = palette
        self.use24HourTime = use24HourTime
        self.useUTCTimeZone = useUTCTimeZone
    }

    private var precision: ChartPricePrecision {
        ChartPricePrecision.resolve(
            symbol: payload.symbol,
            marketClass: .crypto,
            referencePrice: payload.entry ?? payload.summary.bidWallPrice ?? payload.summary.askWallPrice
        )
    }

    private var narrative: OrderFlowNarrative {
        OrderFlowNarrativeBuilder.build(
            summary: payload.summary,
            direction: payload.direction,
            entry: payload.entry,
            stopLoss: payload.stopLoss,
            target1: payload.target1,
            target2: payload.target2,
            precision: precision
        )
    }

    private var alignmentAccent: Color {
        switch narrative.alignment {
        case OrderFlowAlignment.aligned.rawValue: return palette.longEmerald
        case OrderFlowAlignment.conflicting.rawValue: return palette.shortCrimson
        case OrderFlowAlignment.unavailable.rawValue: return palette.secondaryInk
        default: return palette.champagneGold
        }
    }

    private var alignmentTitle: String {
        switch narrative.alignment {
        case OrderFlowAlignment.aligned.rawValue: return "ALIGNED"
        case OrderFlowAlignment.conflicting.rawValue: return "CONFLICT"
        case OrderFlowAlignment.unavailable.rawValue: return "THIN BOOK"
        default: return "MIXED"
        }
    }

    private var capturedStampLabel: String {
        if let ts = narrative.capturedAtEpochSeconds {
            let formatted = TimeDisplayFormatter.formatDateTime(
                epochSeconds: ts,
                use24Hour: use24HourTime,
                useUTC: useUTCTimeZone
            )
            if payload.isHistoricalSnapshot {
                return "Captured at Signal Time · \(formatted)"
            }
            let ageSec = max(0, Int(Date().timeIntervalSince1970 - ts))
            let ageText: String
            if ageSec < 60 {
                ageText = "\(ageSec)s ago"
            } else if ageSec < 3_600 {
                ageText = "\(ageSec / 60)m ago"
            } else {
                ageText = "\(ageSec / 3_600)h ago"
            }
            return "\(formatted) · \(ageText)"
        }
        return payload.isHistoricalSnapshot ? "Captured at Signal Time" : "Live Scan Snapshot"
    }

    public var body: some View {
        let info = narrative
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    heroVerdictCard(info)
                    bookAndFlowCard(info)
                    eventsSection(info)
                    wallsSection(info)
                    takeawayCallout(info)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(palette.canvas)
            .navigationTitle("Order Flow · \(payload.symbol)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Section 1: Hero Directional Verdict

    private func heroVerdictCard(_ info: OrderFlowNarrative) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ConfluenceFlowLayout(horizontalSpacing: 8, verticalSpacing: 6) {
                Text(alignmentTitle)
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(alignmentAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(alignmentAccent.opacity(0.16), in: Capsule())

                Text("\(info.venue) · \(info.isLiveStream ? "Live Stream" : "REST Snapshot")")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(palette.primaryInk)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(palette.elevatedSurface, in: Capsule())

                if let spread = info.spreadBps, spread.isFinite {
                    Text(String(format: "%.1f bps spread", spread))
                        .font(.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(palette.secondaryInk)
                }
            }

            Text(info.heroVerdict)
                .font(.headline.weight(.bold))
                .foregroundStyle(palette.primaryInk)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 5) {
                Image(systemName: payload.isHistoricalSnapshot ? "camera.aperture" : "clock")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.tertiaryInk)
                Text(capturedStampLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(palette.secondaryInk)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .institutionalCard(palette: palette, accentBorder: alignmentAccent.opacity(0.45))
    }

    // MARK: - Section 2: Resting Book Pressure & Aggressive Flow (CVD)

    private func bookAndFlowCard(_ info: OrderFlowNarrative) -> some View {
        let bidPct = Int((info.bidPressureFraction * 100.0).rounded())
        let askPct = 100 - bidPct
        let buyPct = Int((info.aggressiveBuyFraction * 100.0).rounded())
        let sellPct = 100 - buyPct

        return VStack(alignment: .leading, spacing: 14) {
            Text("BOOK PRESSURE & AGGRESSIVE TAPE")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(palette.tertiaryInk)

            // Resting Order Book Bar
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Resting Book Pressure")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.primaryInk)
                    Spacer()
                    Text(String(format: "OBI %+.0f%%", info.obiWeighted * 100.0))
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(info.obiWeighted >= 0 ? palette.longEmerald : palette.shortCrimson)
                }

                pressureSplitBar(leftFraction: info.bidPressureFraction)

                HStack {
                    Text("Bids \(bidPct)%")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(palette.longEmerald)
                    Spacer()
                    Text("Asks \(askPct)%")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(palette.shortCrimson)
                }

                Text(info.restingBookSummary)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().overlay(palette.border)

            // Aggressive Flow (CVD) Bar
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Aggressive Flow (CVD)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.primaryInk)
                    Spacer()
                    Text(String(format: "CVD %+.0f%%", info.cvdRatio * 100.0))
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(info.cvdRatio >= 0 ? palette.longEmerald : palette.shortCrimson)
                }

                pressureSplitBar(leftFraction: info.aggressiveBuyFraction)

                HStack {
                    Text("Market Buys \(buyPct)%")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(palette.longEmerald)
                    Spacer()
                    Text("Market Sells \(sellPct)%")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(palette.shortCrimson)
                }

                Text(info.aggressiveFlowSummary)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .institutionalCard(palette: palette)
    }

    private func pressureSplitBar(leftFraction: Double) -> some View {
        let clamped = min(0.96, max(0.04, leftFraction))
        return GeometryReader { geo in
            let totalW = max(1, geo.size.width)
            let leftW = totalW * CGFloat(clamped)
            HStack(spacing: 2) {
                Rectangle()
                    .fill(palette.longEmerald)
                    .frame(width: max(4, leftW - 1))
                Rectangle()
                    .fill(palette.shortCrimson)
                    .frame(maxWidth: .infinity)
            }
            .clipShape(Capsule())
        }
        .frame(height: 8)
    }

    // MARK: - Section 3: What Happened & How

    private func eventsSection(_ info: OrderFlowNarrative) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHAT HAPPENED & HOW")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(palette.tertiaryInk)

            ForEach(info.eventCards) { card in
                let toneColor = color(for: card.tone)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(card.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.primaryInk)
                        Spacer()
                        Text(card.statusLabel)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(toneColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(toneColor.opacity(0.14), in: Capsule())
                    }
                    Text(card.detail)
                        .font(.caption)
                        .foregroundStyle(card.isEvaluated ? palette.secondaryInk : palette.tertiaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.elevatedSurface.opacity(0.75), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .institutionalCard(palette: palette)
    }

    // MARK: - Section 4: Liquidity Walls vs. Your Levels

    private func wallsSection(_ info: OrderFlowNarrative) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LIQUIDITY WALLS VS. YOUR LEVELS")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(palette.tertiaryInk)

            if info.wallLevelComparisons.isEmpty {
                Text("No oversized resting bid or ask walls detected near your planned levels.")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryInk)
            } else {
                ForEach(info.wallLevelComparisons) { wall in
                    let isBid = wall.side.lowercased().contains("bid")
                    let sideColor = wall.isBlockingTarget
                        ? palette.trapAmber
                        : (isBid ? palette.longEmerald : palette.shortCrimson)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Text(wall.side.uppercased())
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(sideColor)
                            Text(wall.formattedPrice)
                                .font(.subheadline.weight(.bold).monospacedDigit())
                                .foregroundStyle(palette.primaryInk)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Spacer(minLength: 4)
                            Text(wall.statusBadge)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(wall.isConfirmed ? sideColor : palette.secondaryInk)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background((wall.isConfirmed ? sideColor : palette.secondaryInk).opacity(0.14), in: Capsule())
                                .lineLimit(1)
                        }

                        if (wall.distanceBps?.isFinite == true) || ((wall.sizeMultiple ?? 0).isFinite && (wall.sizeMultiple ?? 0) > 0) {
                            HStack(spacing: 8) {
                                if let bps = wall.distanceBps, bps.isFinite {
                                    Text(String(format: "%.0f bps away", bps))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(palette.tertiaryInk)
                                }
                                if let mult = wall.sizeMultiple, mult.isFinite, mult > 0 {
                                    Text(String(format: "%.1fx depth", mult))
                                        .font(.caption2.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(palette.secondaryInk)
                                }
                            }
                        }

                        Text(wall.levelRelation)
                            .font(.caption)
                            .foregroundStyle(wall.isBlockingTarget ? palette.primaryInk : palette.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(wall.isBlockingTarget ? palette.trapAmber.opacity(0.10) : palette.elevatedSurface.opacity(0.75))
                    )
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .institutionalCard(palette: palette)
    }

    // MARK: - Section 5: 2-Line Actionable Takeaway

    private func takeawayCallout(_ info: OrderFlowNarrative) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.max.fill")
                    .font(.caption)
                    .foregroundStyle(palette.champagneGold)
                Text("DIRECTIONAL TAKEAWAY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.champagneGold)
            }
            Text(info.actionableTakeaway)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(palette.primaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.champagneGold.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(palette.champagneGold.opacity(0.35), lineWidth: 1.0)
                )
        )
    }

    private func color(for tone: OrderFlowEventTone) -> Color {
        switch tone {
        case .bullish: return palette.longEmerald
        case .bearish: return palette.shortCrimson
        case .warning: return palette.trapAmber
        case .neutral: return palette.secondaryInk
        case .unavailable: return palette.tertiaryInk
        }
    }
}
