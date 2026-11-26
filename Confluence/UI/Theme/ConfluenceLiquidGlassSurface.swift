import SwiftUI

/// SDK-safe iOS 26+ Liquid Glass surface modifier with clean `.ultraThinMaterial` + hairline border fallback.
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
