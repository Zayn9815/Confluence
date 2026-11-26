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

/// SDK-safe iOS 26/27 Liquid Glass surface modifier with clean `.ultraThinMaterial` + hairline border fallback.
public struct ConfluenceLiquidGlassSurface: ViewModifier {
    let cornerRadius: CGFloat
    let borderColor: Color

    public init(cornerRadius: CGFloat = 12, borderColor: Color = Color.white.opacity(0.18)) {
        self.cornerRadius = cornerRadius
        self.borderColor = borderColor
    }

    public func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            fallbackSurface(content)
        }
        #else
        fallbackSurface(content)
        #endif
    }

    private func fallbackSurface(_ content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 0.75)
            )
    }
}

public extension View {
    func confluenceLiquidGlass(
        cornerRadius: CGFloat = 12,
        borderColor: Color = Color.white.opacity(0.18)
    ) -> some View {
        modifier(ConfluenceLiquidGlassSurface(cornerRadius: cornerRadius, borderColor: borderColor))
    }
}

/// Compact non-blocking Crypto-Only Order Flow Micro-HUD with Bid/Ask Pressure Bar & live venue badge.
/// Automatically hidden on Forex/TradFi or when Order Flow is OFF (`summary == nil`).
public struct CryptoOrderFlowMicroStrip: View {
    let summary: ChartOrderFlowSummary
    let palette: ConfluencePalette

    public init(summary: ChartOrderFlowSummary, palette: ConfluencePalette) {
        self.summary = summary
        self.palette = palette
    }

    private var alignmentColor: Color {
        switch summary.alignment {
        case "aligned": return palette.longEmerald
        case "conflicting": return palette.shortCrimson
        default: return palette.champagneGold
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle()
                    .fill(alignmentColor)
                    .frame(width: 6, height: 6)

                Text("\(summary.venue) \(summary.isLiveStream ? "Live" : "REST")")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(palette.primaryInk)

                Text(String(format: "OBI %+.0f%%", summary.obiWeighted * 100.0))
                    .font(.system(size: 8.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(summary.obiWeighted >= 0 ? palette.longEmerald : palette.shortCrimson)

                if let absTag = summary.absorptionTag {
                    Text(absTag)
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(palette.canvas)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(palette.champagneGold, in: Capsule())
                }

                if let divTag = summary.divergenceTag {
                    Text(divTag)
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(divTag == "DIV+" ? palette.longEmerald : palette.shortCrimson, in: Capsule())
                }
            }

            // Razor-thin 4pt horizontal Bid/Ask Pressure Bar (emerald vs crimson split driven by obiWeighted)
            GeometryReader { geo in
                let totalW = max(1, geo.size.width)
                let bidW = totalW * CGFloat(summary.bidPressureFraction)
                HStack(spacing: 1) {
                    Rectangle()
                        .fill(palette.longEmerald)
                        .frame(width: max(2, bidW - 0.5))
                    Rectangle()
                        .fill(palette.shortCrimson)
                        .frame(maxWidth: .infinity)
                }
                .clipShape(Capsule())
            }
            .frame(height: 4)
        }
        .allowsHitTesting(false)
    }
}

/// Reusable, non-blocking SwiftUI Signal Level HUD & Price Overlay component that any chart engine
/// can layer on top so Entry, Stop Loss, Take Profit (TP1 / TP2), R:R, Trap prices, and optional
/// Crypto-Only live Order Flow pressure bar are always visible without blocking chart gestures.
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

                if overlayModel.entryPrice != nil || overlayModel.stopLoss != nil || overlayModel.takeProfit1 != nil {
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

                if overlayModel.marketClass == .crypto, let of = overlayModel.orderFlowSummary {
                    CryptoOrderFlowMicroStrip(summary: of, palette: palette)
                        .frame(minWidth: 155, maxWidth: 225)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .confluenceLiquidGlass(cornerRadius: 11, borderColor: palette.border.opacity(0.75))
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
