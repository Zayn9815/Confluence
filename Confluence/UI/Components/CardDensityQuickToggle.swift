import SwiftUI

/// 1-tap Compact vs. Terminal pill toggle bound directly to persisted `CardDensity` (`"Compact"` / `"Standard"`).
public struct CardDensityQuickToggle: View {
    @Binding public var density: CardDensity
    public let palette: ConfluencePalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(density: Binding<CardDensity>, palette: ConfluencePalette) {
        self._density = density
        self.palette = palette
    }

    private var isCompact: Bool {
        density == .compact
    }

    public var body: some View {
        Button {
            let next: CardDensity = isCompact ? .standard : .compact
            if reduceMotion {
                density = next
            } else {
                withAnimation(.easeInOut(duration: 0.18)) {
                    density = next
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isCompact ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                    .font(.caption2.weight(.bold))
                Text(isCompact ? "Compact" : "Terminal")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(isCompact ? palette.onAccentInk : palette.secondaryInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isCompact ? palette.champagneGold : palette.elevatedSurface, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isCompact ? Color.clear : palette.border, lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCompact ? "Compact card layout active. Tap for full terminal layout." : "Terminal card layout active. Tap for compact layout.")
    }
}
