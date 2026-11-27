import SwiftUI
import UIKit

/// Clean circular Dark/Light theme toggle button (`moon.fill` in Light mode, `sun.max.fill` in Dark mode)
/// with light haptic feedback and instant persistence via `AppSettingsStore`.
public struct ThemeModeToggleButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public let isDark: Bool
    public let hapticsEnabled: Bool
    public let palette: ConfluencePalette
    public let action: () -> Void

    public init(
        isDark: Bool,
        hapticsEnabled: Bool,
        palette: ConfluencePalette,
        action: @escaping () -> Void
    ) {
        self.isDark = isDark
        self.hapticsEnabled = hapticsEnabled
        self.palette = palette
        self.action = action
    }

    public var body: some View {
        Button {
            if hapticsEnabled {
                let gen = UIImpactFeedbackGenerator(style: .light)
                gen.impactOccurred()
            }
            if reduceMotion {
                action()
            } else {
                withAnimation(.easeInOut(duration: 0.22)) {
                    action()
                }
            }
        } label: {
            Image(systemName: isDark ? "sun.max.fill" : "moon.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isDark ? palette.champagneGold : palette.primaryInk)
                .frame(width: 30, height: 30)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isDark ? "Switch to Light Mode" : "Switch to Dark Mode")
    }
}
