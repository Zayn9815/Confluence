import SwiftUI
@preconcurrency import Pow
import SignalEngine

public struct SignalCardView: View {
    let signal: TradeSignal
    let palette: ConfluencePalette
    let density: CardDensity
    let showMiniChart: Bool
    let animateArrival: Bool
    let hapticsEnabled: Bool
    let isSelecting: Bool
    let isSelected: Bool
    let onToggleSelect: (() -> Void)?
    let onDelete: (() -> Void)?
    let onOpenChart: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showStrategies = false
    @State private var showBreakdown = false
    @State private var showPsychology = true
    @State private var arrivalTriggerCount = 0
    @State private var didCopy = false

    public init(
        signal: TradeSignal,
        palette: ConfluencePalette,
        density: CardDensity,
        showMiniChart: Bool,
        animateArrival: Bool,
        hapticsEnabled: Bool,
        isSelecting: Bool = false,
        isSelected: Bool = false,
        onToggleSelect: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onOpenChart: @escaping () -> Void
    ) {
        self.signal = signal
        self.palette = palette
        self.density = density
        self.showMiniChart = showMiniChart
        self.animateArrival = animateArrival
        self.hapticsEnabled = hapticsEnabled
        self.isSelecting = isSelecting
        self.isSelected = isSelected
        self.onToggleSelect = onToggleSelect
        self.onDelete = onDelete
        self.onOpenChart = onOpenChart
    }

    public var body: some View {
        let dec = PriceFormatHelper.decimals(for: signal.symbol, marketClass: signal.marketClass, referencePrice: signal.levels?.entryMid)
        let accentBorder: Color? = {
            if isSelecting && isSelected { return palette.shortCrimson.opacity(0.85) }
            if signal.tier == .aPlusInstitutional { return palette.champagneGold.opacity(0.65) }
            if signal.category == .trapAlert { return palette.trapAmber.opacity(0.65) }
            return nil
        }()

        VStack(alignment: .leading, spacing: density == .compact ? 10 : 13) {
            // 1. Header Row: Selection Checkmark (when selecting), Market, Pair, Direction/Trap Badge, Confidence % Gauge
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
                    HStack(spacing: 6) {
                        badgePill(signal.marketClass.displayName.uppercased(), color: palette.secondaryInk, fill: palette.elevatedSurface)
                        badgePill(signal.timeframe.displayLabel, color: palette.primaryInk, fill: palette.elevatedSurface)
                        directionOrTrapBadge
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(signal.symbol)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(palette.primaryInk)
                        Text(signal.strengthBreakdown?.strengthLabel ?? signal.tier.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.color(for: signal.tier))
                    }
                    // Persisted signal generation date, local time & relative age
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(palette.tertiaryInk)
                        Text(Self.formattedGeneratedStamp(epochSeconds: signal.generatedAtEpochSeconds))
                            .font(.system(size: 10, weight: .medium).monospacedDigit())
                            .foregroundStyle(palette.secondaryInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
                Spacer()
                confidenceGauge
            }

            // 2. Regime, Killzone, Market Closed & News Catalyst Pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    badgePill(signal.regime.badgeLabel, color: palette.color(for: signal.regime), fill: palette.color(for: signal.regime).opacity(0.14))
                    badgePill(signal.killzone.displayName, color: palette.secondaryInk, fill: palette.elevatedSurface)
                    badgePill("HTF \(signal.htfTimeframe.displayLabel): \(signal.htfBias.rawValue.uppercased())", color: palette.color(for: signal.htfBias), fill: palette.elevatedSurface)
                    if signal.isMarketClosedSnapshot {
                        badgePill("Market Closed · Last Bar", color: palette.trapAmber, fill: palette.trapAmber.opacity(0.14))
                    }
                    if let pre = signal.preNewsBadge {
                        badgePill(pre, color: palette.macroIceBlue, fill: palette.macroIceBlue.opacity(0.14))
                    }
                    if let post = signal.postNewsCatalystBadge {
                        badgePill(post, color: palette.champagneGold, fill: palette.champagneGold.opacity(0.14))
                    }
                }
            }

            // 3. Pure SwiftUI Canvas Mini-Chart (tap -> full-screen LightweightCharts)
            if showMiniChart && !signal.recentCandles.isEmpty {
                Button {
                    if isSelecting {
                        onToggleSelect?()
                    } else {
                        onOpenChart()
                    }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        MiniCandlestickCanvas(
                            candles: signal.recentCandles,
                            levels: signal.levels,
                            overlays: signal.overlays,
                            palette: palette,
                            height: density == .compact ? 86 : 112
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

            // 4. Numeric Execution Grid (Code owns ALL numbers, zero truncation)
            if let lv = signal.levels {
                let levelDec = PriceFormatHelper.decimals(for: signal.symbol, marketClass: signal.marketClass, referencePrice: lv.entryMid)
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ], spacing: 8) {
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
                        sub: lv.isTP2Enabled ? "TP2 1:\(String(format: "%.1f", lv.tp2RiskRewardRatio))" : "TP1 Target Only",
                        accent: palette.primaryInk
                    )
                    metricCell(
                        title: "TP1 TARGET",
                        value: PriceFormatHelper.format(lv.tp1, decimals: levelDec),
                        sub: "+\(String(format: "%.2f", lv.reward1Percent))%",
                        accent: palette.longEmerald
                    )
                    if lv.isTP2Enabled {
                        metricCell(
                            title: "TP2 TARGET",
                            value: PriceFormatHelper.format(lv.tp2, decimals: levelDec),
                            sub: "+\(String(format: "%.2f", lv.reward2Percent))%",
                            accent: palette.macroIceBlue
                        )
                    } else {
                        metricCell(
                            title: "TP2 TARGET",
                            value: "Disabled",
                            sub: "Settings -> Rules",
                            accent: palette.tertiaryInk
                        )
                    }
                    metricCell(
                        title: "CONFLUENCE",
                        value: "\(signal.alignedStrategies.count) Signals",
                        sub: signal.dataProvider,
                        accent: palette.secondaryInk
                    )
                }
            }

            // 5. Expandable Signal Strength Breakdown (4 transparent quantitative pillars)
            if let bd = signal.strengthBreakdown {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showBreakdown.toggle() }
                    } label: {
                        HStack {
                            Image(systemName: "slider.horizontal.3")
                                .font(.caption2)
                                .foregroundStyle(palette.macroIceBlue)
                            Text("Signal Strength Breakdown · \(bd.strengthLabel)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(palette.secondaryInk)
                            Spacer()
                            Image(systemName: showBreakdown ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(palette.tertiaryInk)
                        }
                    }
                    .buttonStyle(.plain)

                    if showBreakdown {
                        VStack(alignment: .leading, spacing: 6) {
                            breakdownRow("Technical Math (ICT / Trend / HTF)", score: bd.technicalScore)
                            breakdownRow("Psychology & Positioning", score: bd.psychologyScore)
                            breakdownRow("News & Macro Catalyst", score: bd.newsMacroScore)
                            breakdownRow("Regime & Session Risk Adj.", score: bd.regimeRiskAdjustment)
                            Divider().overlay(palette.border)
                            HStack {
                                Text("Calibrated Confidence")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(palette.primaryInk)
                                Spacer()
                                Text("\(Int(bd.finalConfidencePercent.rounded()))% · \(bd.strengthLabel)")
                                    .font(.caption2.weight(.bold).monospacedDigit())
                                    .foregroundStyle(palette.color(for: signal.tier))
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
                }
            }

            // 6. Aligned Strategies Chips (Expandable with weight & historical win-rate)
            if !signal.alignedStrategies.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showStrategies.toggle() }
                    } label: {
                        HStack {
                            Text("Aligned Strategies (\(signal.alignedStrategies.count))")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(palette.secondaryInk)
                            Spacer()
                            Image(systemName: showStrategies ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(palette.tertiaryInk)
                        }
                    }
                    .buttonStyle(.plain)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(signal.alignedStrategies) { strat in
                                badgePill(strat.name, color: palette.primaryInk, fill: palette.elevatedSurface)
                            }
                        }
                    }

                    if showStrategies {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(signal.alignedStrategies) { strat in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle()
                                        .fill(palette.color(for: strat.direction))
                                        .frame(width: 6, height: 6)
                                        .padding(.top, 5)
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text(strat.name)
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
                                    }
                                }
                            }
                        }
                        .padding(10)
                        .background(palette.elevatedSurface.opacity(0.75), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }

            // 7. Market Psychology & Pro-vs-Beginner Module
            psychologyModule

            // 8. Optional Gemini 4 Hydrogen 1-line Bear / Invalidation Badge
            if let ai = signal.aiJudgment {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: signal.aiConfirmed ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(signal.aiConfirmed ? palette.champagneGold : palette.trapAmber)
                        .font(.caption)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(signal.aiConfirmed ? "Gemini 4 Hydrogen Confirmed (Q\(ai.setupQuality)/3 · \(Int((ai.confidence * 100).rounded()))%)" : "Gemini 4 Hydrogen Caution (Q\(ai.setupQuality)/3 · \(ai.riskState.rawValue))")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(signal.aiConfirmed ? palette.champagneGold : palette.trapAmber)
                        Text(ai.invalidationCheck)
                            .font(.caption2)
                            .foregroundStyle(palette.secondaryInk)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.elevatedSurface.opacity(0.8), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            // 9. Footer Actions: Closed Bar Timestamp + Delete + One-Tap Copy Setup
            HStack(spacing: 8) {
                Text("Bar \(Date(timeIntervalSince1970: signal.barCloseEpochSeconds).formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(palette.tertiaryInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer()
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
                    UIPasteboard.general.string = signal.formattedCopyText(decimals: dec)
                    SignalSoundEngine.shared.playCopyConfirmationHaptic(enabled: hapticsEnabled)
                    withAnimation { didCopy = true }
                    Task {
                        try? await Task.sleep(nanoseconds: 1_400_000_000)
                        withAnimation { didCopy = false }
                    }
                } label: {
                    Label(didCopy ? "Copied" : "Copy Setup", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(didCopy ? palette.longEmerald : palette.primaryInk)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(palette.elevatedSurface, in: Capsule())
                        .overlay(Capsule().strokeBorder(palette.border, lineWidth: 0.75))
                }
                .buttonStyle(.plain)
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
            Button {
                UIPasteboard.general.string = signal.formattedCopyText(decimals: dec)
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
        // One-shot metallic Pow shine on arrival (respects Reduce Motion, then settles static to save battery)
        .changeEffect(.shine(duration: 0.9), value: arrivalTriggerCount, isEnabled: animateArrival && !reduceMotion)
        .onAppear {
            if animateArrival && !reduceMotion && arrivalTriggerCount == 0 {
                arrivalTriggerCount = 1
            }
        }
    }

    private static func formattedGeneratedStamp(epochSeconds: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: epochSeconds)
        let dateTime = date.formatted(date: .abbreviated, time: .shortened)
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
        return "Generated \(dateTime) · \(ageText)"
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
                badgePill(trap.rawValue, color: palette.trapAmber, fill: palette.trapAmber.opacity(0.16))
            } else if signal.category == .weakSignal {
                badgePill("WEAK · \(signal.direction.rawValue.uppercased())", color: palette.secondaryInk, fill: palette.elevatedSurface)
            } else {
                let c = palette.color(for: signal.direction)
                badgePill(signal.direction.rawValue.uppercased(), color: c, fill: c.opacity(0.16))
            }
        }
    }

    private var confidenceGauge: some View {
        let pct = max(0, min(99, Int(signal.confidencePercent.rounded())))
        let ringColor = palette.color(for: signal.tier)
        return ZStack {
            Circle()
                .stroke(palette.border, lineWidth: 3.5)
            Circle()
                .trim(from: 0, to: CGFloat(pct) / 100.0)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(pct)%")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(palette.primaryInk)
        }
        .frame(width: 46, height: 46)
        .changeEffect(
            .pulse(shape: Circle(), style: ringColor.opacity(0.5), count: 1),
            value: arrivalTriggerCount,
            isEnabled: animateArrival && !reduceMotion
        )
    }

    private var psychologyModule: some View {
        let psych = signal.psychologyReport
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showPsychology.toggle() }
            } label: {
                HStack {
                    Image(systemName: "brain.head.profile")
                        .font(.caption)
                        .foregroundStyle(palette.champagneGold)
                    Text("Market Psychology & Pro vs. Beginner")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.primaryInk)
                    Spacer()
                    Image(systemName: showPsychology ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(palette.tertiaryInk)
                }
            }
            .buttonStyle(.plain)

            // Intraday Pro Flow vs Beginner Direction Strip (plus separate Weekly Macro COT row when present)
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

            // Provenance + Behavioral Badges
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    badgePill(psych.provenanceBadge, color: palette.macroIceBlue, fill: palette.macroIceBlue.opacity(0.12))
                    ForEach(psych.behavioralBadges, id: \.self) { b in
                        badgePill(b, color: palette.trapAmber, fill: palette.trapAmber.opacity(0.14))
                    }
                }
            }

            if showPsychology {
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
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(10)
                .background(palette.canvas.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
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
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(fill, in: Capsule())
    }
}
