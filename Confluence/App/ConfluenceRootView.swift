import SwiftUI
import PopupView
import SignalEngine

public struct ConfluenceRootView: View {
    @Bindable var coordinator: MarketScannerCoordinator
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @State private var selectedTab: Int = 0

    public init(coordinator: MarketScannerCoordinator) {
        self.coordinator = coordinator
    }

    private var effectiveColorScheme: ColorScheme {
        switch coordinator.settings.payload.appearanceMode {
        case .system: return systemScheme
        case .dark: return .dark
        case .light: return .light
        }
    }

    private var palette: ConfluencePalette {
        ConfluencePalette.resolve(
            colorScheme: effectiveColorScheme,
            usePureBlackAMOLED: coordinator.settings.payload.usePureBlackAMOLED,
            useColorBlindSafe: coordinator.settings.payload.useColorBlindSafePalette,
            increaseContrast: colorSchemeContrast == .increased
        )
    }

    public var body: some View {
        let isBannerPresented = Binding<Bool>(
            get: { coordinator.activeBanner != nil },
            set: { if !$0 { coordinator.activeBanner = nil } }
        )
        let isOnboardingPresented = Binding<Bool>(
            get: { !coordinator.settings.payload.hasCompletedOnboarding },
            set: { if !$0 { coordinator.settings.payload.hasCompletedOnboarding = true } }
        )

        TabView(selection: $selectedTab) {
            SignalsTabView(coordinator: coordinator, palette: palette)
                .tabItem { Label("Signals", systemImage: "waveform.path.ecg") }
                .tag(0)

            NewsCalendarTabView(coordinator: coordinator, palette: palette)
                .tabItem { Label("News", systemImage: "calendar.badge.clock") }
                .tag(1)

            MarketsScannerTabView(coordinator: coordinator, palette: palette)
                .tabItem { Label("Markets", systemImage: "square.grid.2x2") }
                .tag(2)

            StatsCalibrationTabView(coordinator: coordinator, palette: palette)
                .tabItem { Label("Stats", systemImage: "chart.bar.xaxis") }
                .tag(3)

            SettingsTabView(coordinator: coordinator, palette: palette)
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                .tag(4)
        }
        .tint(palette.champagneGold)
        .preferredColorScheme(coordinator.settings.payload.appearanceMode.colorScheme)
        .fullScreenCover(isPresented: isOnboardingPresented) {
            OnboardingFlowView(palette: palette) {
                coordinator.settings.payload.hasCompletedOnboarding = true
            }
        }
        .sheet(isPresented: $coordinator.isNotificationInboxPresented) {
            NotificationInboxSheet(coordinator: coordinator, palette: palette)
        }
        .onChange(of: coordinator.pendingDeepLink) { _, link in
            guard let link else { return }
            switch link {
            case .signal(let fingerprint, _, _, _):
                selectedTab = 0
                coordinator.highlightedSignalFingerprint = fingerprint
            case .news:
                selectedTab = 1
                coordinator.pendingDeepLink = nil
            }
        }
        .popup(isPresented: isBannerPresented) {
            if let banner = coordinator.activeBanner {
                floatingBannerView(banner)
            }
        } customize: { params in
            params
                .type(.floater(verticalPadding: 12, horizontalPadding: 14, useSafeAreaInset: true))
                .position(.top)
                .animation(.spring(response: 0.38, dampingFraction: 0.85))
                .autohideIn(4.5)
                .dragToDismiss(true)
                .closeOnTap(true)
        }
    }

    private func floatingBannerView(_ banner: FloatingAlertBanner) -> some View {
        let accent: Color = {
            switch banner.kind {
            case .strongSignal(let dir): return dir == .long ? palette.longEmerald : (dir == .short ? palette.shortCrimson : palette.champagneGold)
            case .trapAlert: return palette.trapAmber
            case .macroRelease: return palette.macroIceBlue
            }
        }()

        return Button {
            if let fp = banner.targetSignalId {
                let category: SignalCategory = (banner.kind == .trapAlert) ? .trapAlert : .strongSignal
                coordinator.pendingDeepLink = .signal(fingerprint: fp, category: category, market: nil, symbol: nil)
                selectedTab = 0
            } else {
                selectedTab = (banner.kind == .macroRelease) ? 1 : 0
            }
            coordinator.activeBanner = nil
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(accent)
                    .frame(width: 4, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(banner.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(palette.primaryInk)
                    Text(banner.subtitle)
                        .font(.caption2)
                        .foregroundStyle(palette.secondaryInk)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(palette.tertiaryInk)
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(accent.opacity(0.6), lineWidth: 1.0)
            )
            .shadow(color: .black.opacity(0.28), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
    }
}
