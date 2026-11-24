import SwiftUI
import LightweightCharts
import SignalEngine

/// Tap-to-open Full-Screen Interactive Chart powered by `tradingview/LightweightChartsIOS` (v5.2.0).
/// Instantiated lazily ONLY when the user taps a Signal Card mini-chart to keep scroll feeds at 120Hz
/// and battery draw minimal.
public struct FullScreenChartSheet: View {
    let signal: TradeSignal
    let palette: ConfluencePalette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    public init(signal: TradeSignal, palette: ConfluencePalette) {
        self.signal = signal
        self.palette = palette
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header numeric ribbon
                if let lv = signal.levels {
                    let dec = PriceFormatHelper.decimals(for: signal.symbol)
                    HStack(spacing: 12) {
                        levelPill("ENTRY", PriceFormatHelper.format(lv.entryMid, decimals: dec), palette.champagneGold)
                        levelPill("SL", PriceFormatHelper.format(lv.stopLoss, decimals: dec), palette.shortCrimson)
                        levelPill("TP1", PriceFormatHelper.format(lv.tp1, decimals: dec), palette.longEmerald)
                        levelPill("TP2", PriceFormatHelper.format(lv.tp2, decimals: dec), palette.macroIceBlue)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(palette.surface)
                    Divider().overlay(palette.border)
                }

                LightweightChartContainer(
                    candles: signal.recentCandles,
                    levels: signal.levels,
                    overlays: signal.overlays,
                    isDark: colorScheme == .dark
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Footer TradingView attribution + Psychology summary
                HStack {
                    Text("Charts powered by TradingView Lightweight Charts")
                        .font(.caption2)
                        .foregroundStyle(palette.tertiaryInk)
                    Spacer()
                    Text("\(signal.timeframe.displayLabel) · \(signal.dataProvider)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(palette.secondaryInk)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(palette.surface)
            }
            .background(palette.canvas)
            .navigationTitle("\(signal.symbol) · \(signal.timeframe.displayLabel)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
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
    let isDark: Bool

    func makeUIView(context: Context) -> LightweightCharts {
        let bgHex: UInt32 = isDark ? 0x0B0D11 : 0xF6F7F9
        let textHex: UInt32 = isDark ? 0x9CA7BA : 0x374151
        let gridHex: UInt32 = isDark ? 0x1B2230 : 0xE5E7EB

        let options = ChartOptions(
            layout: LightweightCharts.LayoutOptions(
                background: .solid(color: ChartColor(hex: bgHex)),
                textColor: ChartColor(hex: textHex)
            ),
            grid: GridOptions(
                verticalLines: GridLineOptions(color: ChartColor(hex: gridHex)),
                horizontalLines: GridLineOptions(color: ChartColor(hex: gridHex))
            )
        )

        let chartView = LightweightCharts(options: options)
        let seriesOptions = CandlestickSeriesOptions(
            upColor: ChartColor(hex: 0x10B981),
            downColor: ChartColor(hex: 0xEF4444),
            wickUpColor: ChartColor(hex: 0x10B981),
            wickDownColor: ChartColor(hex: 0xEF4444)
        )

        let series = chartView.addCandlestickSeries(options: seriesOptions)
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

        if let lv = levels {
            _ = series.createPriceLine(options: PriceLineOptions(
                price: lv.entryMid,
                color: ChartColor(hex: 0xD4AF37),
                lineWidth: .one,
                lineStyle: .dashed,
                axisLabelVisible: true,
                title: "ENTRY"
            ))
            _ = series.createPriceLine(options: PriceLineOptions(
                price: lv.stopLoss,
                color: ChartColor(hex: 0xEF4444),
                lineWidth: .two,
                lineStyle: .solid,
                axisLabelVisible: true,
                title: "SL"
            ))
            _ = series.createPriceLine(options: PriceLineOptions(
                price: lv.tp1,
                color: ChartColor(hex: 0x10B981),
                lineWidth: .two,
                lineStyle: .solid,
                axisLabelVisible: true,
                title: "TP1"
            ))
            _ = series.createPriceLine(options: PriceLineOptions(
                price: lv.tp2,
                color: ChartColor(hex: 0x38BDF8),
                lineWidth: .one,
                lineStyle: .dashed,
                axisLabelVisible: true,
                title: "TP2"
            ))
        }

        for trap in overlays.traps where trap.isActionable {
            _ = series.createPriceLine(options: PriceLineOptions(
                price: trap.level,
                color: ChartColor(hex: 0xF59E0B),
                lineWidth: .one,
                lineStyle: .dotted,
                axisLabelVisible: true,
                title: trap.direction.rawValue
            ))
        }

        return chartView
    }

    func updateUIView(_ uiView: LightweightCharts, context: Context) {
        // Static snapshot on open; no redundant JS bridge churn
    }
}
