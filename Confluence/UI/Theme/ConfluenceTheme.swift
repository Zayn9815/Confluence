import SwiftUI
import UIKit
import SignalEngine

// MARK: - Multi-Theme Presets & Liquid Glass Intensity

public enum TerminalThemePreset: String, Codable, Sendable, CaseIterable, Identifiable {
    case champagneObsidian = "champagneObsidian"
    case emeraldDesk = "emeraldDesk"
    case midnightCobalt = "midnightCobalt"
    case ivoryInstitutional = "ivoryInstitutional"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .champagneObsidian: return "Champagne Obsidian"
        case .emeraldDesk: return "Emerald Desk"
        case .midnightCobalt: return "Midnight Cobalt"
        case .ivoryInstitutional: return "Ivory Institutional"
        }
    }

    public var subtitle: String {
        switch self {
        case .champagneObsidian: return "Obsidian slate with warm champagne gold accents"
        case .emeraldDesk: return "Deep trading desk slate with crisp emerald highlights"
        case .midnightCobalt: return "Midnight navy surfaces with sapphire accents"
        case .ivoryInstitutional: return "Warm editorial parchment with antique bronze accents"
        }
    }

    public var swatchBackgroundHex: UInt32 {
        switch self {
        case .champagneObsidian: return 0x0B0D11
        case .emeraldDesk: return 0x07110E
        case .midnightCobalt: return 0x080E1A
        case .ivoryInstitutional: return 0xF5F2EB
        }
    }

    public var swatchAccentHex: UInt32 {
        switch self {
        case .champagneObsidian: return 0xDEB853
        case .emeraldDesk: return 0x10B981
        case .midnightCobalt: return 0x38BDF8
        case .ivoryInstitutional: return 0x85600E
        }
    }

    public var swatchSecondaryHex: UInt32 {
        switch self {
        case .champagneObsidian: return 0x1A1E26
        case .emeraldDesk: return 0x12241E
        case .midnightCobalt: return 0x152238
        case .ivoryInstitutional: return 0xE7E2D6
        }
    }
}

public enum LiquidGlassIntensity: String, Codable, Sendable, CaseIterable, Identifiable {
    case off = "off"
    case subtle = "subtle"
    case standard = "standard"
    case immersive = "immersive"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .off: return "Solid"
        case .subtle: return "Subtle"
        case .standard: return "Standard"
        case .immersive: return "Immersive"
        }
    }
}

// MARK: - Portable Color Tokens

public struct ConfluenceRGB: Sendable, Equatable, Hashable {
    public let r: Double
    public let g: Double
    public let b: Double
    public let a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1.0) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public init(hex: UInt32, alpha: Double = 1.0) {
        self.r = Double((hex & 0xFF0000) >> 16) / 255.0
        self.g = Double((hex & 0x00FF00) >> 8) / 255.0
        self.b = Double(hex & 0x0000FF) / 255.0
        self.a = alpha
    }

    public var color: Color {
        Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    public var uiColor: UIColor {
        UIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
    }

    public var hexString: String {
        let ri = Int((max(0, min(1, r)) * 255.0).rounded())
        let gi = Int((max(0, min(1, g)) * 255.0).rounded())
        let bi = Int((max(0, min(1, b)) * 255.0).rounded())
        return String(format: "#%02X%02X%02X", ri, gi, bi)
    }
}

public struct ConfluenceBadgeToken: Sendable {
    public let foreground: Color
    public let background: Color
    public let border: Color

    public init(foreground: Color, background: Color, border: Color) {
        self.foreground = foreground
        self.background = background
        self.border = border
    }
}

public struct ConfluenceChartPalette: Sendable, Equatable {
    public let background: ConfluenceRGB
    public let surface: ConfluenceRGB
    public let grid: ConfluenceRGB
    public let axisText: ConfluenceRGB
    public let border: ConfluenceRGB
    public let bullCandle: ConfluenceRGB
    public let bearCandle: ConfluenceRGB
    public let entry: ConfluenceRGB
    public let stopLoss: ConfluenceRGB
    public let tp1: ConfluenceRGB
    public let tp2: ConfluenceRGB
    public let trap: ConfluenceRGB
    public let ema20: ConfluenceRGB
    public let ema50: ConfluenceRGB
    public let ema200: ConfluenceRGB
    public let equilibrium: ConfluenceRGB

    public init(
        background: ConfluenceRGB,
        surface: ConfluenceRGB,
        grid: ConfluenceRGB,
        axisText: ConfluenceRGB,
        border: ConfluenceRGB,
        bullCandle: ConfluenceRGB,
        bearCandle: ConfluenceRGB,
        entry: ConfluenceRGB,
        stopLoss: ConfluenceRGB,
        tp1: ConfluenceRGB,
        tp2: ConfluenceRGB,
        trap: ConfluenceRGB,
        ema20: ConfluenceRGB,
        ema50: ConfluenceRGB,
        ema200: ConfluenceRGB,
        equilibrium: ConfluenceRGB
    ) {
        self.background = background
        self.surface = surface
        self.grid = grid
        self.axisText = axisText
        self.border = border
        self.bullCandle = bullCandle
        self.bearCandle = bearCandle
        self.entry = entry
        self.stopLoss = stopLoss
        self.tp1 = tp1
        self.tp2 = tp2
        self.trap = trap
        self.ema20 = ema20
        self.ema50 = ema50
        self.ema200 = ema200
        self.equilibrium = equilibrium
    }
}

// MARK: - ConfluencePalette

public struct ConfluencePalette: Sendable {
    public let canvas: Color
    public let surface: Color
    public let elevatedSurface: Color
    public let modalSurface: Color
    public let border: Color
    public let hairlineDivider: Color
    public let cardShadow: Color
    public let primaryInk: Color
    public let secondaryInk: Color
    public let tertiaryInk: Color
    public let onAccentInk: Color
    public let onDestructiveInk: Color

    // Institutional signal accents (switches to Okabe-Ito Blue/Vermilion when Color-Blind Safe is ON)
    public let longEmerald: Color
    public let shortCrimson: Color
    public let champagneGold: Color
    public let trapAmber: Color
    /// Neutral muted slate (remapped from legacy electric cyan for calm dark/light hierarchy).
    public let macroIceBlue: Color

    // Liquid Glass tokens
    public let glassTint: Color
    public let glassBorder: Color
    public let glassOpaqueFallback: Color
    public let glassIntensity: LiquidGlassIntensity

    // Semantic Badge tokens
    public let bullBadge: ConfluenceBadgeToken
    public let bearBadge: ConfluenceBadgeToken
    public let neutralBadge: ConfluenceBadgeToken
    public let accentBadge: ConfluenceBadgeToken
    public let trapBadge: ConfluenceBadgeToken

    // Unified Chart Engine Palette
    public let chart: ConfluenceChartPalette

    // Metadata
    public let themePreset: TerminalThemePreset
    public let isLight: Bool
    public let isPureBlackAMOLED: Bool

    public init(
        canvas: Color,
        surface: Color,
        elevatedSurface: Color,
        modalSurface: Color? = nil,
        border: Color,
        hairlineDivider: Color? = nil,
        cardShadow: Color = .clear,
        primaryInk: Color,
        secondaryInk: Color,
        tertiaryInk: Color,
        onAccentInk: Color = Color(hex: 0x090D16),
        onDestructiveInk: Color = .white,
        longEmerald: Color = Color(hex: 0x10B981),
        shortCrimson: Color = Color(hex: 0xEF4444),
        champagneGold: Color = Color(hex: 0xDEB853),
        trapAmber: Color = Color(hex: 0xF59E0B),
        macroIceBlue: Color = Color(hex: 0x94A3B8),
        glassTint: Color = Color.white.opacity(0.06),
        glassBorder: Color = Color.white.opacity(0.14),
        glassOpaqueFallback: Color? = nil,
        glassIntensity: LiquidGlassIntensity = .standard,
        bullBadge: ConfluenceBadgeToken? = nil,
        bearBadge: ConfluenceBadgeToken? = nil,
        neutralBadge: ConfluenceBadgeToken? = nil,
        accentBadge: ConfluenceBadgeToken? = nil,
        trapBadge: ConfluenceBadgeToken? = nil,
        chart: ConfluenceChartPalette? = nil,
        themePreset: TerminalThemePreset = .champagneObsidian,
        isLight: Bool = false,
        isPureBlackAMOLED: Bool = false
    ) {
        self.canvas = canvas
        self.surface = surface
        self.elevatedSurface = elevatedSurface
        self.modalSurface = modalSurface ?? surface
        self.border = border
        self.hairlineDivider = hairlineDivider ?? border
        self.cardShadow = cardShadow
        self.primaryInk = primaryInk
        self.secondaryInk = secondaryInk
        self.tertiaryInk = tertiaryInk
        self.onAccentInk = onAccentInk
        self.onDestructiveInk = onDestructiveInk
        self.longEmerald = longEmerald
        self.shortCrimson = shortCrimson
        self.champagneGold = champagneGold
        self.trapAmber = trapAmber
        self.macroIceBlue = macroIceBlue
        self.glassTint = glassTint
        self.glassBorder = glassBorder
        self.glassOpaqueFallback = glassOpaqueFallback ?? elevatedSurface
        self.glassIntensity = glassIntensity
        self.bullBadge = bullBadge ?? ConfluenceBadgeToken(
            foreground: longEmerald,
            background: longEmerald.opacity(0.14),
            border: longEmerald.opacity(0.28)
        )
        self.bearBadge = bearBadge ?? ConfluenceBadgeToken(
            foreground: shortCrimson,
            background: shortCrimson.opacity(0.14),
            border: shortCrimson.opacity(0.28)
        )
        self.neutralBadge = neutralBadge ?? ConfluenceBadgeToken(
            foreground: secondaryInk,
            background: elevatedSurface,
            border: border
        )
        self.accentBadge = accentBadge ?? ConfluenceBadgeToken(
            foreground: champagneGold,
            background: champagneGold.opacity(0.15),
            border: champagneGold.opacity(0.32)
        )
        self.trapBadge = trapBadge ?? ConfluenceBadgeToken(
            foreground: trapAmber,
            background: trapAmber.opacity(0.15),
            border: trapAmber.opacity(0.32)
        )
        self.chart = chart ?? ConfluenceChartPalette(
            background: ConfluenceRGB(hex: isLight ? 0xFFFFFF : (isPureBlackAMOLED ? 0x000000 : 0x0B0D11)),
            surface: ConfluenceRGB(hex: isLight ? 0xF4F5F7 : (isPureBlackAMOLED ? 0x0E1116 : 0x13161C)),
            grid: ConfluenceRGB(hex: isLight ? 0xCBD5E1 : 0x334155, alpha: isLight ? 0.55 : 0.35),
            axisText: ConfluenceRGB(hex: isLight ? 0x475569 : 0x94A3B8),
            border: ConfluenceRGB(hex: isLight ? 0xCBD5E1 : 0x334155, alpha: 0.5),
            bullCandle: ConfluenceRGB(hex: isLight ? 0x15803D : 0x10B981),
            bearCandle: ConfluenceRGB(hex: isLight ? 0xB91C1C : 0xEF4444),
            entry: ConfluenceRGB(hex: isLight ? 0x85600E : 0xDEB853),
            stopLoss: ConfluenceRGB(hex: isLight ? 0xB91C1C : 0xEF4444),
            tp1: ConfluenceRGB(hex: isLight ? 0x15803D : 0x10B981),
            tp2: ConfluenceRGB(hex: isLight ? 0x047857 : 0x34D399),
            trap: ConfluenceRGB(hex: isLight ? 0xB45309 : 0xF59E0B),
            ema20: ConfluenceRGB(hex: isLight ? 0x2563EB : 0x60A5FA),
            ema50: ConfluenceRGB(hex: isLight ? 0x7C3AED : 0xA78BFA),
            ema200: ConfluenceRGB(hex: isLight ? 0x475569 : 0x94A3B8),
            equilibrium: ConfluenceRGB(hex: isLight ? 0x64748B : 0x94A3B8, alpha: 0.7)
        )
        self.themePreset = themePreset
        self.isLight = isLight
        self.isPureBlackAMOLED = isPureBlackAMOLED
    }

    public static func resolve(
        colorScheme: ColorScheme,
        usePureBlackAMOLED: Bool,
        useColorBlindSafe: Bool = false,
        increaseContrast: Bool = false,
        themePreset: TerminalThemePreset = .champagneObsidian,
        glassIntensity: LiquidGlassIntensity = .standard
    ) -> ConfluencePalette {
        let isLight = (colorScheme == .light)
        let isOLED = (!isLight && usePureBlackAMOLED)

        // Semantic directional colors (WCAG 2.1 AA >= 4.5:1 verified)
        let longHex: UInt32 = useColorBlindSafe
            ? (isLight ? 0x00669E : 0x56B4E9)
            : (isLight ? 0x15803D : 0x10B981)
        let shortHex: UInt32 = useColorBlindSafe
            ? (isLight ? 0xB84B00 : 0xFB923C)
            : (isLight ? 0xB91C1C : 0xEF4444)
        // WCAG AA Light Color-Blind trapAmber (#9A6700 >= 4.7:1 on white)
        let amberHex: UInt32 = useColorBlindSafe
            ? (isLight ? 0x9A6700 : 0xE69F00)
            : (isLight ? 0xA14B08 : 0xF59E0B)

        // Preset accent color (WCAG AA light gold #85600E >= 5.3:1 on white)
        let accentHex: UInt32
        switch themePreset {
        case .champagneObsidian:
            accentHex = isLight ? 0x85600E : 0xDEB853
        case .emeraldDesk:
            accentHex = isLight ? 0x0F766E : 0x2DD4BF
        case .midnightCobalt:
            accentHex = isLight ? 0x1D4ED8 : 0x60A5FA
        case .ivoryInstitutional:
            accentHex = isLight ? 0x85600E : 0xE2C275
        }

        let mutedSlateHex: UInt32 = isLight ? 0x475569 : 0x94A3B8
        let longColor = Color(hex: longHex)
        let shortColor = Color(hex: shortHex)
        let accentColor = Color(hex: accentHex)
        let amberColor = Color(hex: amberHex)
        let mutedSlate = Color(hex: mutedSlateHex)

        // Adaptive ink on filled accent / destructive pills
        let onAccentInk: Color = isLight ? .white : Color(hex: 0x090D16)
        let onDestructiveInk: Color = .white

        // Surface hierarchy by light / OLED / preset
        let canvasHex: UInt32
        let surfaceHex: UInt32
        let elevatedHex: UInt32
        let modalHex: UInt32
        let primaryInkHex: UInt32
        let secondaryInkHex: UInt32
        let tertiaryInkHex: UInt32

        if isLight {
            switch themePreset {
            case .ivoryInstitutional:
                canvasHex = 0xF5F2EB
                surfaceHex = 0xFFFDF9
                elevatedHex = increaseContrast ? 0xE2DDD0 : 0xECE8DE
                modalHex = 0xFFFDF9
            case .emeraldDesk:
                canvasHex = 0xF1F6F4
                surfaceHex = 0xFFFFFF
                elevatedHex = increaseContrast ? 0xD9E8E2 : 0xE6F0EC
                modalHex = 0xFFFFFF
            case .midnightCobalt:
                canvasHex = 0xF1F4FA
                surfaceHex = 0xFFFFFF
                elevatedHex = increaseContrast ? 0xD8E2F2 : 0xE7EDF8
                modalHex = 0xFFFFFF
            case .champagneObsidian:
                canvasHex = 0xF4F5F7
                surfaceHex = 0xFFFFFF
                elevatedHex = increaseContrast ? 0xE2E8F0 : 0xF1F3F6
                modalHex = 0xFFFFFF
            }
            primaryInkHex = 0x090D16
            secondaryInkHex = increaseContrast ? 0x1F2937 : 0x4B5563
            tertiaryInkHex = increaseContrast ? 0x374151 : 0x596270
        } else if isOLED {
            canvasHex = 0x000000
            surfaceHex = 0x0C0F14
            elevatedHex = 0x151A23
            modalHex = 0x0A0C10
            primaryInkHex = 0xFFFFFF
            secondaryInkHex = increaseContrast ? 0xCBD5E1 : 0x9CA7BA
            // WCAG 2.1 AA Dark tertiaryInk (#828FA6 >= 5.6:1 on #0C0F14 & #000000)
            tertiaryInkHex = increaseContrast ? 0xA8B5C9 : 0x828FA6
        } else {
            switch themePreset {
            case .champagneObsidian:
                canvasHex = 0x0B0D11
                surfaceHex = 0x13161C
                elevatedHex = 0x1A1E26
                modalHex = 0x101319
            case .emeraldDesk:
                canvasHex = 0x07110E
                surfaceHex = 0x0F1C18
                elevatedHex = 0x162822
                modalHex = 0x0C1714
            case .midnightCobalt:
                canvasHex = 0x080E1A
                surfaceHex = 0x10192B
                elevatedHex = 0x18243C
                modalHex = 0x0D1524
            case .ivoryInstitutional:
                canvasHex = 0x12110E
                surfaceHex = 0x1B1915
                elevatedHex = 0x25221C
                modalHex = 0x171512
            }
            primaryInkHex = 0xF8FAFC
            secondaryInkHex = increaseContrast ? 0xCBD5E1 : 0xA3AFC2
            // WCAG 2.1 AA Dark tertiaryInk (#828FA6 >= 4.7:1 on #13161C / #1B1915)
            tertiaryInkHex = increaseContrast ? 0xA8B5C9 : 0x828FA6
        }

        let borderColor: Color = isLight
            ? (increaseContrast ? Color(hex: 0x64748B) : Color.black.opacity(0.08))
            : (increaseContrast ? Color(hex: 0x64748B) : Color.white.opacity(0.10))
        let hairlineColor: Color = isLight
            ? Color.black.opacity(increaseContrast ? 0.16 : 0.07)
            : Color.white.opacity(increaseContrast ? 0.20 : 0.08)

        let glassTintAlpha: Double
        let glassBorderAlpha: Double
        switch glassIntensity {
        case .off:
            glassTintAlpha = 1.0
            glassBorderAlpha = isLight ? 0.12 : 0.14
        case .subtle:
            glassTintAlpha = isLight ? 0.72 : 0.48
            glassBorderAlpha = isLight ? 0.10 : 0.12
        case .standard:
            glassTintAlpha = isLight ? 0.52 : 0.30
            glassBorderAlpha = isLight ? 0.14 : 0.18
        case .immersive:
            glassTintAlpha = isLight ? 0.34 : 0.18
            glassBorderAlpha = isLight ? 0.18 : 0.24
        }

        let glassTint = Color(hex: surfaceHex, opacity: glassTintAlpha)
        let glassBorder = isLight
            ? Color.black.opacity(increaseContrast ? 0.24 : glassBorderAlpha)
            : Color.white.opacity(increaseContrast ? 0.28 : glassBorderAlpha)
        let glassOpaqueFallback = Color(hex: elevatedHex)

        let chartPalette = ConfluenceChartPalette(
            background: ConfluenceRGB(hex: canvasHex),
            surface: ConfluenceRGB(hex: surfaceHex),
            grid: ConfluenceRGB(hex: isLight ? 0xCBD5E1 : 0x334155, alpha: isLight ? 0.55 : 0.32),
            axisText: ConfluenceRGB(hex: secondaryInkHex),
            border: ConfluenceRGB(hex: isLight ? 0x94A3B8 : 0x475569, alpha: 0.45),
            bullCandle: ConfluenceRGB(hex: longHex),
            bearCandle: ConfluenceRGB(hex: shortHex),
            entry: ConfluenceRGB(hex: accentHex),
            stopLoss: ConfluenceRGB(hex: shortHex),
            tp1: ConfluenceRGB(hex: longHex),
            tp2: ConfluenceRGB(hex: useColorBlindSafe ? (isLight ? 0x0369A1 : 0x38BDF8) : (isLight ? 0x047857 : 0x34D399)),
            trap: ConfluenceRGB(hex: amberHex),
            ema20: ConfluenceRGB(hex: isLight ? 0x2563EB : 0x60A5FA),
            ema50: ConfluenceRGB(hex: isLight ? 0x7C3AED : 0xA78BFA),
            ema200: ConfluenceRGB(hex: mutedSlateHex),
            equilibrium: ConfluenceRGB(hex: tertiaryInkHex, alpha: 0.75)
        )

        return ConfluencePalette(
            canvas: Color(hex: canvasHex),
            surface: Color(hex: surfaceHex),
            elevatedSurface: Color(hex: elevatedHex),
            modalSurface: Color(hex: modalHex),
            border: borderColor,
            hairlineDivider: hairlineColor,
            cardShadow: isLight ? Color.black.opacity(0.06) : .clear,
            primaryInk: Color(hex: primaryInkHex),
            secondaryInk: Color(hex: secondaryInkHex),
            tertiaryInk: Color(hex: tertiaryInkHex),
            onAccentInk: onAccentInk,
            onDestructiveInk: onDestructiveInk,
            longEmerald: longColor,
            shortCrimson: shortColor,
            champagneGold: accentColor,
            trapAmber: amberColor,
            macroIceBlue: mutedSlate,
            glassTint: glassTint,
            glassBorder: glassBorder,
            glassOpaqueFallback: glassOpaqueFallback,
            glassIntensity: glassIntensity,
            chart: chartPalette,
            themePreset: themePreset,
            isLight: isLight,
            isPureBlackAMOLED: isOLED
        )
    }

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
        case .aligned: return champagneGold
        case .trapWarning: return trapAmber
        case .weakFiltered: return secondaryInk
        }
    }
}

// MARK: - SwiftUI Environment Key

private struct ConfluencePaletteEnvironmentKey: EnvironmentKey {
    static let defaultValue: ConfluencePalette = .resolve(colorScheme: .dark, usePureBlackAMOLED: false)
}

public extension EnvironmentValues {
    var confluencePalette: ConfluencePalette {
        get { self[ConfluencePaletteEnvironmentKey.self] }
        set { self[ConfluencePaletteEnvironmentKey.self] = newValue }
    }
}

// MARK: - Helpers & Modifiers

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
                    .shadow(color: palette.cardShadow, radius: 10, x: 0, y: 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(accentBorder ?? palette.border, lineWidth: accentBorder != nil ? 1.0 : 0.75)
                    )
            )
    }
}

/// Zero-dependency SwiftUI skeleton shimmer that respects `@Environment(\.accessibilityReduceMotion)`
/// and adapts highlight contrast cleanly across Light and Dark modes.
public struct NativeShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var phase: CGFloat = -0.6

    public func body(content: Content) -> some View {
        if reduceMotion {
            content.opacity(0.65)
        } else {
            let highlightColor = (colorScheme == .light)
                ? Color.black.opacity(0.08)
                : Color.white.opacity(0.14)
            content
                .overlay {
                    GeometryReader { geo in
                        let w = max(geo.size.width, 1)
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: highlightColor, location: 0.5),
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
