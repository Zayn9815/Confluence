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

    // Institutional signal accents
    public let longEmerald = Color(hex: 0x10B981)
    public let shortCrimson = Color(hex: 0xEF4444)
    public let champagneGold = Color(hex: 0xD4AF37)
    public let trapAmber = Color(hex: 0xF59E0B)
    public let macroIceBlue = Color(hex: 0x38BDF8)

    public static func resolve(preset: ThemePreset, colorScheme: ColorScheme) -> ConfluencePalette {
        switch preset {
        case .obsidianTerminal:
            if colorScheme == .light {
                return porcelain
            }
            return ConfluencePalette(
                canvas: Color(hex: 0x0B0D11),
                surface: Color(hex: 0x131720),
                elevatedSurface: Color(hex: 0x1A202D),
                border: Color(hex: 0x232A38),
                primaryInk: Color(hex: 0xF3F5F8),
                secondaryInk: Color(hex: 0x9CA7BA),
                tertiaryInk: Color(hex: 0x677287)
            )
        case .amoledVault:
            if colorScheme == .light {
                return porcelain
            }
            return ConfluencePalette(
                canvas: Color(hex: 0x000000),
                surface: Color(hex: 0x0E1116),
                elevatedSurface: Color(hex: 0x161B24),
                border: Color(hex: 0x222733),
                primaryInk: Color(hex: 0xF8FAFC),
                secondaryInk: Color(hex: 0x94A3B8),
                tertiaryInk: Color(hex: 0x64748B)
            )
        case .porcelainDesk:
            return porcelain
        }
    }

    public static let porcelain = ConfluencePalette(
        canvas: Color(hex: 0xF6F7F9),
        surface: Color(hex: 0xFFFFFF),
        elevatedSurface: Color(hex: 0xEEF1F6),
        border: Color(hex: 0xE2E8F0),
        primaryInk: Color(hex: 0x111827),
        secondaryInk: Color(hex: 0x4B5563),
        tertiaryInk: Color(hex: 0x6B7280)
    )

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

public extension View {
    func institutionalCard(palette: ConfluencePalette, accentBorder: Color? = nil) -> some View {
        modifier(InstitutionalCardModifier(palette: palette, accentBorder: accentBorder))
    }
}

public enum PriceFormatHelper {
    public static func format(_ price: Double, decimals: Int) -> String {
        String(format: "%.\(decimals)f", price)
    }

    public static func decimals(for symbol: String) -> Int {
        WatchlistDefaults.descriptor(for: symbol)?.priceDecimals ?? 2
    }
}
