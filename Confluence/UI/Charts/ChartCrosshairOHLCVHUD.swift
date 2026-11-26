import SwiftUI
import SignalEngine

/// Lightweight native SwiftUI top OHLCV + R:R strip driven by chart crosshair movement
/// (or latest candle when crosshair is idle). Zero JS bridge overhead.
public struct ChartCrosshairOHLCVHUD: View {
    let readout: ChartCrosshairReadout?
    let fallbackCandle: Candle?
    let overlayModel: ChartSignalOverlayModel
    let precision: ChartPricePrecision
    let palette: ConfluencePalette

    public init(
        readout: ChartCrosshairReadout?,
        fallbackCandle: Candle?,
        overlayModel: ChartSignalOverlayModel,
        precision: ChartPricePrecision,
        palette: ConfluencePalette
    ) {
        self.readout = readout
        self.fallbackCandle = fallbackCandle
        self.overlayModel = overlayModel
        self.precision = precision
        self.palette = palette
    }

    private var activeOHLC: ChartCrosshairReadout? {
        if let readout { return readout }
        guard let bar = fallbackCandle else { return nil }
        return ChartCrosshairReadout(
            epochSeconds: bar.openTimeEpochSeconds,
            open: bar.open,
            high: bar.high,
            low: bar.low,
            close: bar.close,
            isForming: !bar.isClosed
        )
    }

    public var body: some View {
        HStack(spacing: 8) {
            if let ohlc = activeOHLC {
                let tone = ohlc.isBullish ? palette.longEmerald : palette.shortCrimson
                HStack(spacing: 6) {
                    ohlcChip("O", precision.format(ohlc.open), tone: palette.primaryInk)
                    ohlcChip("H", precision.format(ohlc.high), tone: palette.longEmerald)
                    ohlcChip("L", precision.format(ohlc.low), tone: palette.shortCrimson)
                    ohlcChip("C", precision.format(ohlc.close), tone: tone)
                }
                if let pct = ohlc.changePercent {
                    Text(String(format: "%+.2f%%", pct))
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(tone)
                }
            } else {
                Text("Touch chart to inspect candles")
                    .font(.caption2)
                    .foregroundStyle(palette.tertiaryInk)
            }

            Spacer(minLength: 4)

            if let rr = overlayModel.computedLiveRiskReward {
                Text("1:\(String(format: "%.2f", rr))")
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(palette.champagneGold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(palette.champagneGold.opacity(0.16), in: Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(palette.surface.opacity(0.92))
    }

    private func ohlcChip(_ label: String, _ value: String, tone: Color) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(palette.tertiaryInk)
            Text(value)
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(tone)
                .lineLimit(1)
        }
    }
}
