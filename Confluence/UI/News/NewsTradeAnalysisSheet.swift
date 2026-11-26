import SwiftUI
import SignalEngine

public enum NewsAnalysisTarget: Identifiable, Hashable, Sendable {
    case event(EconomicEvent)
    case article(BreakingNewsItem)

    public var id: String {
        switch self {
        case .event(let ev): return "event-\(ev.id)"
        case .article(let item): return "article-\(item.id)"
        }
    }
}

public struct NewsTradeAnalysisSheet: View {
    let target: NewsAnalysisTarget
    @Bindable var coordinator: MarketScannerCoordinator
    let palette: ConfluencePalette

    @Environment(\.dismiss) private var dismiss

    @State private var selectedSymbol: String = ""
    @State private var evaluation: NewsTradeEvaluation?
    @State private var isEvaluating: Bool = false
    @State private var chartSignal: TradeSignal?
    @State private var aiNewsNote: String? = nil

    public init(target: NewsAnalysisTarget, coordinator: MarketScannerCoordinator, palette: ConfluencePalette) {
        self.target = target
        self.coordinator = coordinator
        self.palette = palette
    }

    private var summary: NewsMarketSummary {
        switch target {
        case .event(let ev):
            return NewsTradeAnalyzer.summarize(
                event: ev,
                nowEpochSeconds: Date().timeIntervalSince1970,
                whipsawWindowMinutes: coordinator.settings.buildEngineConfig().postNewsWhipsawMinutesAfter
            )
        case .article(let item):
            return NewsTradeAnalyzer.summarize(newsItem: item)
        }
    }

    private var candidateSymbols: [String] {
        let fromSummary = summary.assetImpacts.map(\.symbol)
        return fromSummary.isEmpty ? ["BTC/USDT", "XAU/USD", "EUR/USD", "US500", "NAS100"] : fromSummary
    }

    public var body: some View {
        let currentSummary = summary
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // 1. News / Event Recap Card
                    recapSection(currentSummary)

                    // Optional AI Second-Opinion note (routed via selected AI provider; never overrides deterministic levels)
                    if let aiNote = aiNewsNote, !aiNote.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("AI Second Opinion (\(coordinator.settings.payload.aiProvider.shortLabel))", systemImage: "sparkles")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(palette.champagneGold)
                            Text(aiNote)
                                .font(.caption)
                                .foregroundStyle(palette.primaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .institutionalCard(palette: palette, accentBorder: palette.champagneGold.opacity(0.4))
                    }

                    // 2. Expected Market Direction & Why It Moves Markets
                    directionSection(currentSummary)

                    // 3. Interactive News + Math Trade Setup Generator
                    tradeGeneratorSection(currentSummary)
                }
                .padding(14)
                .padding(.bottom, 20)
            }
            .background(palette.canvas)
            .navigationTitle("News & Trade Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                }
            }
            .sheet(item: $chartSignal) { sig in
                FullScreenChartSheet(signal: sig, palette: palette, coordinator: coordinator)
            }
            .task {
                if selectedSymbol.isEmpty, let first = candidateSymbols.first {
                    selectedSymbol = first
                    await runEvaluation(summary: currentSummary, symbol: first)
                }
                if coordinator.settings.payload.geminiEnabled, aiNewsNote == nil {
                    aiNewsNote = await coordinator.summarizeBreakingNewsImpact(
                        headline: currentSummary.title,
                        affectedAssets: candidateSymbols
                    )
                }
            }
        }
    }

    // MARK: - Section 1: Recap

    private func recapSection(_ s: NewsMarketSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                pill(s.severity.rawValue.uppercased(), color: severityColor(s.severity))
                pill(s.headlineBias.rawValue, color: biasColor(s.headlineBias))
                Spacer()
                Text(Date(timeIntervalSince1970: s.timestampEpochSeconds).formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(palette.tertiaryInk)
            }

            Text(s.title)
                .font(.headline.weight(.bold))
                .foregroundStyle(palette.primaryInk)

            Text("Source: \(s.source)")
                .font(.caption2.weight(.medium))
                .foregroundStyle(palette.secondaryInk)

            Text(s.recap)
                .font(.caption)
                .foregroundStyle(palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            if case let .event(ev) = target {
                HStack(spacing: 8) {
                    macroValueBox("ACTUAL", formatEventNumber(ev.actual, unit: ev.unit, multiplier: ev.multiplier), accent: ev.isPublished ? palette.primaryInk : palette.tertiaryInk)
                    macroValueBox("FORECAST", formatEventNumber(ev.forecast, unit: ev.unit, multiplier: ev.multiplier), accent: palette.secondaryInk)
                    macroValueBox("PREVIOUS", formatEventNumber(ev.revisedPrevious ?? ev.previous, unit: ev.unit, multiplier: ev.multiplier), accent: palette.tertiaryInk)
                }
            }

            if let urlStr = s.url, let url = URL(string: urlStr) {
                Link(destination: url) {
                    Label("Open Source Article", systemImage: "safari")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.macroIceBlue)
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .institutionalCard(palette: palette)
    }

    // MARK: - Section 2: Expected Market Direction

    private func directionSection(_ s: NewsMarketSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Expected Market Direction", systemImage: "arrow.up.right.and.arrow.down.right")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(palette.primaryInk)

            if !s.whyItMovesMarket.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("WHY THIS MOVES THE MARKET")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(palette.tertiaryInk)
                    ForEach(s.whyItMovesMarket, id: \.self) { bullet in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(palette.champagneGold)
                            Text(bullet)
                                .font(.caption2)
                                .foregroundStyle(palette.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.elevatedSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            ForEach(s.assetImpacts) { impact in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(impact.symbol)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(palette.primaryInk)
                            Text(impact.displayName)
                                .font(.caption2)
                                .foregroundStyle(palette.tertiaryInk)
                        }
                        Text(impact.rationale)
                            .font(.caption2)
                            .foregroundStyle(palette.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    pill(impact.direction.rawValue, color: biasColor(impact.direction))
                }
                .padding(10)
                .background(palette.elevatedSurface.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(14)
        .institutionalCard(palette: palette)
    }

    // MARK: - Section 3: Interactive News + Math Trade Generator

    private func tradeGeneratorSection(_ s: NewsMarketSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("News + Math Trade Setup", systemImage: "scope")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(palette.primaryInk)
                Spacer()
                Text(coordinator.settings.payload.entryTimeframe.displayLabel)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(palette.champagneGold)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(palette.champagneGold.opacity(0.14), in: Capsule())
            }

            Text("Select an impacted pair to run closed-candle ICT, Trend, Trap, Regime & Risk math against this catalyst:")
                .font(.caption2)
                .foregroundStyle(palette.secondaryInk)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(candidateSymbols, id: \.self) { sym in
                        let isSelected = (selectedSymbol == sym)
                        Button {
                            selectedSymbol = sym
                            Task { await runEvaluation(summary: s, symbol: sym) }
                        } label: {
                            Text(sym)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(isSelected ? palette.canvas : palette.primaryInk)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(isSelected ? palette.champagneGold : palette.elevatedSurface))
                                .overlay(Capsule().strokeBorder(isSelected ? Color.clear : palette.border, lineWidth: 0.75))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if isEvaluating {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Evaluating live closed candles & confluence for \(selectedSymbol)...")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(palette.elevatedSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else if let eval = evaluation {
                evaluationResultCard(eval)
            }
        }
        .padding(14)
        .institutionalCard(palette: palette)
    }

    @ViewBuilder
    private func evaluationResultCard(_ eval: NewsTradeEvaluation) -> some View {
        let isActionable = (eval.verdict == .actionableSetup)
        let verdictColor = isActionable ? palette.longEmerald : palette.trapAmber

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(
                    eval.verdict.rawValue,
                    systemImage: isActionable ? "checkmark.seal.fill" : "hand.raised.fill"
                )
                .font(.caption.weight(.bold))
                .foregroundStyle(verdictColor)
                Spacer()
                pill("News: \(eval.newsBias.rawValue)", color: biasColor(eval.newsBias))
            }

            Text(eval.headlineSummary)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.primaryInk)
                .fixedSize(horizontal: false, vertical: true)

            if let sig = eval.signal, let lv = sig.levels {
                let dec = PriceFormatHelper.decimals(for: sig.symbol, marketClass: sig.marketClass, referencePrice: lv.entryMid)
                HStack(spacing: 8) {
                    levelBox("DIRECTION", sig.direction.rawValue.uppercased(), sub: "\(Int(sig.confidencePercent.rounded()))% · \(sig.strengthBreakdown?.strengthLabel ?? sig.tier.displayName)", accent: palette.color(for: sig.direction))
                    levelBox("R:R RATIO", "1:\(String(format: "%.2f", lv.riskRewardRatio))", sub: lv.isTP2Enabled ? "Target 2 1:\(String(format: "%.1f", lv.tp2RiskRewardRatio))" : "Target 1 Only", accent: palette.primaryInk)
                }

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ], spacing: 8) {
                    levelBox("ENTRY ZONE", "\(PriceFormatHelper.format(lv.entryLow, decimals: dec))\nto \(PriceFormatHelper.format(lv.entryHigh, decimals: dec))", sub: "Mid \(PriceFormatHelper.format(lv.entryMid, decimals: dec))", accent: palette.champagneGold)
                    levelBox("STOP LOSS", PriceFormatHelper.format(lv.stopLoss, decimals: dec), sub: "-\(String(format: "%.2f", lv.riskPercent))% Risk", accent: palette.shortCrimson)
                    levelBox("TARGET 1", PriceFormatHelper.format(lv.tp1, decimals: dec), sub: "+\(String(format: "%.2f", lv.reward1Percent))%", accent: palette.longEmerald)
                    levelBox("TARGET 2", lv.isTP2Enabled ? PriceFormatHelper.format(lv.tp2, decimals: dec) : "Disabled", sub: lv.isTP2Enabled ? "+\(String(format: "%.2f", lv.reward2Percent))%" : "Settings -> Rules", accent: lv.isTP2Enabled ? palette.longEmerald : palette.tertiaryInk)
                }
            }

            if !eval.alignmentNotes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TECHNICAL & NEWS ALIGNMENT")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(palette.tertiaryInk)
                    ForEach(eval.alignmentNotes, id: \.self) { note in
                        Text("• \(note)")
                            .font(.caption2)
                            .foregroundStyle(palette.secondaryInk)
                    }
                }
            }

            if !eval.requiredConfirmations.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CONFIRMATIONS REQUIRED BEFORE TRADING")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(palette.trapAmber)
                    ForEach(eval.requiredConfirmations, id: \.self) { req in
                        Text("• \(req)")
                            .font(.caption2)
                            .foregroundStyle(palette.secondaryInk)
                    }
                }
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.trapAmber.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

            if let sig = eval.signal {
                Button {
                    chartSignal = sig
                } label: {
                    HStack {
                        Image(systemName: "chart.xyaxis.line")
                        Text(isActionable ? "Open Interactive Chart Setup" : "Inspect Live Chart Structure")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(palette.canvas)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(isActionable ? palette.champagneGold : palette.primaryInk, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(palette.elevatedSurface.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(verdictColor.opacity(0.45), lineWidth: 1)
        )
    }

    private func runEvaluation(summary: NewsMarketSummary, symbol: String) async {
        isEvaluating = true
        let result = await coordinator.evaluateNewsTrade(summary: summary, symbol: symbol)
        guard selectedSymbol == symbol else { return }
        self.evaluation = result
        isEvaluating = false
    }

    // MARK: - Styling Helpers

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
    }

    private func macroValueBox(_ title: String, _ value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 9, weight: .bold)).foregroundStyle(palette.tertiaryInk)
            Text(value).font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(palette.elevatedSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func levelBox(_ title: String, _ value: String, sub: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 9, weight: .bold)).foregroundStyle(palette.tertiaryInk)
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(accent)
                .fixedSize(horizontal: false, vertical: true)
            Text(sub)
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(palette.secondaryInk)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(8)
        .background(palette.canvas.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func severityColor(_ sev: NewsCatalystSeverity) -> Color {
        switch sev {
        case .high: return palette.shortCrimson
        case .medium: return palette.trapAmber
        case .low: return palette.secondaryInk
        }
    }

    private func biasColor(_ bias: NewsDirectionBias) -> Color {
        switch bias {
        case .bullish: return palette.longEmerald
        case .bearish: return palette.shortCrimson
        case .twoWayWhipsaw: return palette.trapAmber
        case .neutral: return palette.secondaryInk
        }
    }

    private func formatEventNumber(_ val: Double?, unit: String?, multiplier: String?) -> String {
        guard let val else { return "—" }
        let suffix: String
        switch multiplier?.lowercased() {
        case "thousands": suffix = "K"
        case "millions": suffix = "M"
        case "billions": suffix = "B"
        default: suffix = (unit?.lowercased() == "percent") ? "%" : ""
        }
        if abs(val) >= 1000 {
            return String(format: "%.0f%@", val, suffix)
        }
        return String(format: "%.2f%@", val, suffix)
    }
}
