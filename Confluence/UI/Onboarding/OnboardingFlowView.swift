import SwiftUI
import UserNotifications

/// 4-page first-run onboarding flow with mandatory Risk Disclosure acknowledgement.
public struct OnboardingFlowView: View {
    public let palette: ConfluencePalette
    public let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0
    @State private var acceptedDisclosure = false
    @State private var notificationsRequested = false
    @State private var notificationsGranted = false

    public init(palette: ConfluencePalette, onComplete: @escaping () -> Void) {
        self.palette = palette
        self.onComplete = onComplete
    }

    public var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                onboardingPage(
                    icon: "waveform.path.ecg",
                    accent: palette.champagneGold,
                    title: "Deterministic Closed-Candle Analysis",
                    subtitle: "Confluence scans Crypto, FX, Gold, Indices, and US Stocks strictly on closed candles — dropping open forming bars to eliminate repainting.",
                    bullets: [
                        "ICT/SMC, Candlesticks, Momentum, Behavioral Traps & Macro News fused in pure Swift code.",
                        "All Entry, Stop Loss, TP1/TP2, and R:R numbers are computed deterministically."
                    ]
                ).tag(0)

                onboardingPage(
                    icon: "checkmark.shield.fill",
                    accent: palette.longEmerald,
                    title: "Honest Scores & Causal Fill Rules",
                    subtitle: "No fake win rates or optimistic fills. Every passive outcome must first touch its Entry Zone within the fill window.",
                    bullets: [
                        "Raw Scores (0–100) are labeled Score until 100 resolved filled trades activate walk-forward Platt calibration.",
                        "Fill bars check SL only; same-bar SL + TP conflicts resolve pessimistically as SL first.",
                        "Every Win Rate shows sample size n and its exact Wilson 95% Confidence Interval."
                    ]
                ).tag(1)

                VStack(alignment: .leading, spacing: 14) {
                    Spacer()
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(palette.macroIceBlue)
                    Text("Private, Read-Only & Keychain-First")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(palette.primaryInk)
                    Text("Confluence works out of the box with free feeds and zero bundled secrets.")
                        .font(.subheadline)
                        .foregroundStyle(palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach([
                            "Optional Twelve Data, Gemini, DeepSeek, OpenRouter, and Finnhub keys are stored strictly in your device's encrypted iOS Keychain.",
                            "Read-only terminal: never connects to brokers, never executes orders, never requests private trading keys."
                        ], id: \.self) { b in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(palette.macroIceBlue)
                                    .padding(.top, 2)
                                Text(b)
                                    .font(.caption)
                                    .foregroundStyle(palette.secondaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(14)
                    .institutionalCard(palette: palette)

                    Button {
                        Task {
                            let status = await PreNewsNotificationScheduler.shared.requestAuthorizationIfNeeded()
                            notificationsRequested = true
                            notificationsGranted = (status == .authorized || status == .provisional || status == .ephemeral)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: notificationsGranted ? "bell.badge.fill" : "bell.fill")
                                .foregroundStyle(notificationsGranted ? palette.longEmerald : palette.champagneGold)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(notificationsGranted ? "Live Signal & Pre-News Alerts Enabled" : "Enable Signal & Pre-News Alerts (Optional)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(palette.primaryInk)
                                Text(notificationsRequested && !notificationsGranted
                                     ? "You can enable alerts anytime in iOS Settings -> Confluence."
                                     : "Receive local alerts for new Strong setups, Trap alerts, and 15m/5m macro countdowns.")
                                    .font(.caption2)
                                    .foregroundStyle(palette.secondaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .institutionalCard(palette: palette)
                    }
                    .buttonStyle(.plain)
                    .disabled(notificationsGranted)

                    Spacer()
                }
                .padding(24)
                .tag(2)

                VStack(alignment: .leading, spacing: 14) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(palette.trapAmber)
                    Text("Risk Disclosure")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(palette.primaryInk)
                    Text("Trading financial markets involves substantial risk of loss. Confluence provides deterministic analytical tools and position-sizing estimates for informational purposes only — not financial advice. Always verify prices, spreads, contract sizes, and risk directly with your broker.")
                        .font(.subheadline)
                        .foregroundStyle(palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)

                    Toggle(isOn: $acceptedDisclosure) {
                        Text("I understand Confluence is a read-only analysis tool, not financial advice, and I am solely responsible for my trading decisions.")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.primaryInk)
                    }
                    .tint(palette.champagneGold)
                    .padding(12)
                    .institutionalCard(palette: palette)

                    Spacer()
                }
                .padding(24)
                .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            HStack {
                if page > 0 {
                    Button("Back") {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { page -= 1 }
                    }
                    .foregroundStyle(palette.secondaryInk)
                }
                Spacer()
                if page < 3 {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { page += 1 }
                    } label: {
                        Text("Next")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(palette.onAccentInk)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(palette.champagneGold, in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        onComplete()
                    } label: {
                        Text("Enter Confluence")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(palette.onAccentInk)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(acceptedDisclosure ? palette.champagneGold : palette.tertiaryInk.opacity(0.5), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!acceptedDisclosure)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(palette.canvas.ignoresSafeArea())
        .interactiveDismissDisabled(true)
    }

    private func onboardingPage(icon: String, accent: Color, title: String, subtitle: String, bullets: [String]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 42))
                .foregroundStyle(accent)
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(palette.primaryInk)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(bullets, id: \.self) { b in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(accent)
                            .padding(.top, 2)
                        Text(b)
                            .font(.caption)
                            .foregroundStyle(palette.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(14)
            .institutionalCard(palette: palette)
            Spacer()
        }
        .padding(24)
    }
}
