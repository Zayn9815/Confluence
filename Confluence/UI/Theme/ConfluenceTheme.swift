import SwiftUI
import SignalEngine

public struct ConfluencePalette: Sendable {
    public let canvas: Color
    public let surface: Color
    public let elevatedSurface: Color
    public let border: Color
    public let primaryInk: Color
    public let secondaryInk: Color
    public let tertiaryInk: Color

    // Institutional signal accents (switches to Okabe-Ito Blue/Vermilion when Color-Blind Safe is ON)
    public let longEmerald: Color
    public let shortCrimson: Color
    public let champagneGold: Color
    public let trapAmber: Color
    public let macroIceBlue: Color

    public init(
        canvas: Color,
        surface: Color,
        elevatedSurface: Color,
        border: Color,
        primaryInk: Color,
        secondaryInk: Color,
        tertiaryInk: Color,
        longEmerald: Color = Color(hex: 0x10B981),
        shortCrimson: Color = Color(hex: 0xEF4444),
        champagneGold: Color = Color(hex: 0xD4AF37),
        trapAmber: Color = Color(hex: 0xF59E0B),
        macroIceBlue: Color = Color(hex: 0x38BDF8)
    ) {
        self.canvas = canvas
        self.surface = surface
        self.elevatedSurface = elevatedSurface
        self.border = border
        self.primaryInk = primaryInk
        self.secondaryInk = secondaryInk
        self.tertiaryInk = tertiaryInk
        self.longEmerald = longEmerald
        self.shortCrimson = shortCrimson
        self.champagneGold = champagneGold
        self.trapAmber = trapAmber
        self.macroIceBlue = macroIceBlue
    }

    public static func resolve(
        colorScheme: ColorScheme,
        usePureBlackAMOLED: Bool,
        useColorBlindSafe: Bool = false,
        increaseContrast: Bool = false
    ) -> ConfluencePalette {
        let isLight = (colorScheme == .light)
        let longColor: Color = useColorBlindSafe
            ? (isLight ? Color(hex: 0x0072B2) : Color(hex: 0x38BDF8)) // Okabe-Ito Blue
            : (isLight ? Color(hex: 0x059669) : Color(hex: 0x10B981))
        let shortColor: Color = useColorBlindSafe
            ? (isLight ? Color(hex: 0xD55E00) : Color(hex: 0xFB923C)) // Okabe-Ito Vermilion
            : (isLight ? Color(hex: 0xDC2626) : Color(hex: 0xEF4444))
        let goldColor: Color = isLight ? Color(hex: 0xB48A18) : Color(hex: 0xD4AF37)
        let amberColor: Color = useColorBlindSafe ? Color(hex: 0xE69F00) : Color(hex: 0xF59E0B)
        let iceBlue: Color = useColorBlindSafe ? Color(hex: 0x56B4E9) : Color(hex: 0x38BDF8)

        if isLight {
            return ConfluencePalette(
                canvas: Color(hex: 0xF6F7F9),
                surface: Color(hex: 0xFFFFFF),
                elevatedSurface: increaseContrast ? Color(hex: 0xE2E8F0) : Color(hex: 0xEEF1F6),
                border: increaseContrast ? Color(hex: 0x94A3B8) : Color(hex: 0xE2E8F0),
                primaryInk: Color(hex: 0x090D16),
                secondaryInk: increaseContrast ? Color(hex: 0x1F2937) : Color(hex: 0x4B5563),
                tertiaryInk: increaseContrast ? Color(hex: 0x374151) : Color(hex: 0x6B7280),
                longEmerald: longColor,
                shortCrimson: shortColor,
                champagneGold: goldColor,
                trapAmber: amberColor,
                macroIceBlue: iceBlue
            )
        }
        if usePureBlackAMOLED {
            return ConfluencePalette(
                canvas: Color(hex: 0x000000),
                surface: Color(hex: 0x0E1116),
                elevatedSurface: Color(hex: 0x161B24),
                border: increaseContrast ? Color(hex: 0x475569) : Color(hex: 0x222733),
                primaryInk: Color(hex: 0xFFFFFF),
                secondaryInk: increaseContrast ? Color(hex: 0xCBD5E1) : Color(hex: 0x94A3B8),
                tertiaryInk: increaseContrast ? Color(hex: 0x94A3B8) : Color(hex: 0x64748B),
                longEmerald: longColor,
                shortCrimson: shortColor,
                champagneGold: goldColor,
                trapAmber: amberColor,
                macroIceBlue: iceBlue
            )
        }
        return ConfluencePalette(
            canvas: Color(hex: 0x0B0D11),
            surface: Color(hex: 0x131720),
            elevatedSurface: Color(hex: 0x1A202D),
            border: increaseContrast ? Color(hex: 0x475569) : Color(hex: 0x232A38),
            primaryInk: Color(hex: 0xF8FAFC),
            secondaryInk: increaseContrast ? Color(hex: 0xCBD5E1) : Color(hex: 0x9CA7BA),
            tertiaryInk: increaseContrast ? Color(hex: 0x94A3B8) : Color(hex: 0x677287),
            longEmerald: longColor,
            shortCrimson: shortColor,
            champagneGold: goldColor,
            trapAmber: amberColor,
            macroIceBlue: iceBlue
        )
    }

    public static let porcelain = resolve(colorScheme: .light, usePureBlackAMOLED: false)

    public func color(for direction: TradeDirection) -> Color {
        switch direction {
        case .long: return longEmerald
        case .short: return shortCrimson
        case .neutral: return secondaryInk
        }
    }

    public func color(for regime: MarketRegime) -> Color {
        switch regime {
        case .trending: return longEmerald
        case .meanReverting: return macroIceBlue
        case .highVol: return trapAmber
        case .crisis: return shortCrimson
        }
    }

    public func color(for tier: SignalTier) -> Color {
        switch tier {
        case .aPlusInstitutional: return champagneGold
        case .highConviction: return longEmerald
        case .aligned: return macroIceBlue
        case .trapWarning: return trapAmber
        case .weakFiltered: return secondaryInk
        }
    }
}

public extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex & 0xFF0000) >> 16) / 255.0
        let g = Double((hex & 0x00FF00) >> 8) / 255.0
        let b = Double(hex & 0x0000FF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

public struct InstitutionalCardModifier: ViewModifier {
    let palette: ConfluencePalette
    let accentBorder: Color?

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(palette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(accentBorder ?? palette.border, lineWidth: accentBorder != nil ? 1.0 : 0.75)
                    )
            )
    }
}

/// Zero-dependency SwiftUI skeleton shimmer that respects `@Environment(\.accessibilityReduceMotion)`
/// and replaces the external `SwiftUI-Shimmer` package cleanly.
public struct NativeShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -0.6

    public func body(content: Content) -> some View {
        if reduceMotion {
            content.opacity(0.65)
        } else {
            content
                .overlay {
                    GeometryReader { geo in
                        let w = max(geo.size.width, 1)
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: Color.white.opacity(0.14), location: 0.5),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: w * 0.7)
                        .offset(x: phase * w)
                        .clipped()
                    }
                    .allowsHitTesting(false)
                }
                .mask(content)
                .onAppear {
                    withAnimation(.linear(duration: 1.35).repeatForever(autoreverses: false)) {
                        phase = 1.4
                    }
                }
        }
    }
}

public extension View {
    func institutionalCard(palette: ConfluencePalette, accentBorder: Color? = nil) -> some View {
        modifier(InstitutionalCardModifier(palette: palette, accentBorder: accentBorder))
    }

    func nativeShimmer() -> some View {
        modifier(NativeShimmerModifier())
    }
}

public enum PriceFormatHelper {
    public static func format(_ price: Double, decimals: Int) -> String {
        String(format: "%.\(decimals)f", price)
    }

    public static func decimals(for symbol: String, marketClass: MarketClass? = nil, referencePrice: Double? = nil) -> Int {
        ChartPricePrecision.resolve(symbol: symbol, marketClass: marketClass, referencePrice: referencePrice).precision
    }

    public static func precision(for symbol: String, marketClass: MarketClass? = nil, referencePrice: Double? = nil) -> ChartPricePrecision {
        ChartPricePrecision.resolve(symbol: symbol, marketClass: marketClass, referencePrice: referencePrice)
    }
}
