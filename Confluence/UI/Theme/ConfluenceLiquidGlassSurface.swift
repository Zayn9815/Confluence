import SwiftUI

/// SDK-safe iOS 26+ Liquid Glass surface modifier with Reduce Transparency & Solid-mode opaque fallback,
/// palette-aware glass border/tint, and clean `.ultraThinMaterial` rendering on iOS 17–25.
public struct ConfluenceLiquidGlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.confluencePalette) private var palette

    let cornerRadius: CGFloat
    let borderColorOverride: Color?

    public init(cornerRadius: CGFloat = 12, borderColor: Color? = nil) {
        self.cornerRadius = cornerRadius
        self.borderColorOverride = borderColor
    }

    private var effectiveBorder: Color {
        borderColorOverride ?? palette.glassBorder
    }

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency || palette.glassIntensity == .off {
            content
                .background(palette.glassOpaqueFallback, in: shape)
                .overlay(shape.strokeBorder(effectiveBorder, lineWidth: 0.75))
        } else {
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                content
                    .background(palette.glassTint, in: shape)
                    .glassEffect(.regular, in: shape)
                    .overlay(shape.strokeBorder(effectiveBorder, lineWidth: 0.75))
            } else {
                translucentMaterialSurface(content, shape: shape)
            }
            #else
            translucentMaterialSurface(content, shape: shape)
            #endif
        }
    }

    private func translucentMaterialSurface(_ content: Content, shape: RoundedRectangle) -> some View {
        let material: Material = {
            switch palette.glassIntensity {
            case .off: return .regularMaterial
            case .subtle: return .regularMaterial
            case .standard: return .thinMaterial
            case .immersive: return .ultraThinMaterial
            }
        }()
        return content
            .background(material, in: shape)
            .background(palette.glassTint, in: shape)
            .overlay(shape.strokeBorder(effectiveBorder, lineWidth: 0.75))
    }
}

public extension View {
    func confluenceLiquidGlass(
        cornerRadius: CGFloat = 12,
        borderColor: Color? = nil
    ) -> some View {
        modifier(ConfluenceLiquidGlassSurface(cornerRadius: cornerRadius, borderColor: borderColor))
    }
}
