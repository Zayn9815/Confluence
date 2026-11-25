import SwiftUI

/// 4-page first-run onboarding flow with mandatory Risk Disclosure acknowledgement.
public struct OnboardingFlowView: View {
    public let palette: ConfluencePalette
    public let onComplete: () -> Void

    @State private var page = 0
    @State private var acceptedDisclosure = false

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

                onboardingPage(
                    icon: "lock.shield.fill",
                    accent: palette.macroIceBlue,
                    title: "Private, Read-Only & Keychain-First",
                    subtitle: "Confluence works out of the box with free feeds and zero bundled secrets.",
                    bullets: [
                        "Optional Twelve Data, Gemini AI, and Finnhub keys are stored strictly in your device's encrypted iOS Keychain.",
                        "Read-only terminal: never connects to brokers, never executes orders, never requests private trading keys."
                    ]
                ).tag(2)

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
                        withAnimation { page -= 1 }
                    }
                    .foregroundStyle(palette.secondaryInk)
                }
                Spacer()
                if page < 3 {
                    Button {
                        withAnimation { page += 1 }
                    } label: {
                        Text("Next")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(palette.canvas)
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
                            .foregroundStyle(palette.canvas)
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
