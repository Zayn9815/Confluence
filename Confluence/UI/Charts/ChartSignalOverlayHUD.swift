import SwiftUI
import SignalEngine

/// Lightweight native SwiftUI top OHLCV + R:R HUD driven by `subscribeCrosshairMove`
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

/// Reusable, non-blocking SwiftUI Signal Level HUD & Price Overlay component that any chart engine
/// can layer on top so Entry, Stop Loss, Take Profit (TP1 / TP2), R:R, and Trap prices are always visible.
public struct ChartSignalOverlayHUD: View {
    let overlayModel: ChartSignalOverlayModel
    let precision: ChartPricePrecision
    let palette: ConfluencePalette
    let engineBadge: String?

    public init(
        overlayModel: ChartSignalOverlayModel,
        precision: ChartPricePrecision,
        palette: ConfluencePalette,
        engineBadge: String? = nil
    ) {
        self.overlayModel = overlayModel
        self.precision = precision
        self.palette = palette
        self.engineBadge = engineBadge
    }

    public var body: some View {
        if overlayModel.hasAnyOverlayLevels || engineBadge != nil {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    if let dir = overlayModel.direction, dir != .neutral {
                        let isLong = (dir == .long)
                        Text(isLong ? "BUY / LONG" : "SELL / SHORT")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(isLong ? palette.longEmerald : palette.shortCrimson)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((isLong ? palette.longEmerald : palette.shortCrimson).opacity(0.16), in: Capsule())
                    }

                    if let rr = overlayModel.computedLiveRiskReward {
                        Text("R:R 1:\(String(format: "%.2f", rr))")
                            .font(.system(size: 9, weight: .bold).monospacedDigit())
                            .foregroundStyle(palette.champagneGold)
                    }

                    if let badge = engineBadge {
                        Text(badge)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(palette.secondaryInk)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(palette.elevatedSurface.opacity(0.9), in: Capsule())
                    }
                }

                HStack(spacing: 8) {
                    if let entry = overlayModel.entryPrice {
                        badgeItem(title: "ENTRY", price: precision.format(entry), color: palette.champagneGold)
                    }
                    if let sl = overlayModel.stopLoss {
                        badgeItem(title: "SL", price: precision.format(sl), color: palette.shortCrimson)
                    }
                    if let tp1 = overlayModel.takeProfit1 {
                        badgeItem(title: "TP1", price: precision.format(tp1), color: palette.longEmerald)
                    }
                    if overlayModel.isTP2Enabled, let tp2 = overlayModel.takeProfit2 {
                        badgeItem(title: "TP2", price: precision.format(tp2), color: palette.macroIceBlue)
                    }
                }

                if let trap = overlayModel.primaryTrap {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(palette.trapAmber)
                        Text("\(trap.label): \(precision.format(trap.price))")
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(palette.trapAmber)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(palette.border.opacity(0.75), lineWidth: 0.75)
            )
            .allowsHitTesting(false)
        }
    }

    private func badgeItem(title: String, price: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(color)
            Text(price)
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundStyle(palette.primaryInk)
                .lineLimit(1)
        }
    }
}
