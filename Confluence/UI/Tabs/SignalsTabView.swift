import SwiftUI
@preconcurrency import Shimmer
import SignalEngine

public enum SignalFeedFilter: String, CaseIterable, Identifiable {
    case strong = "Strong Signals"
    case traps = "Trap Alerts"
    case weak = "Weak / Filtered"

    public var id: String { rawValue }
}

public struct SignalsTabView: View {
    @Bindable var coordinator: MarketScannerCoordinator
    let palette: ConfluencePalette

    @State private var selectedMarket: MarketClass? = nil // nil == All
    @State private var feedFilter: SignalFeedFilter = .strong
    @State private var chartSignal: TradeSignal?

    public init(coordinator: MarketScannerCoordinator, palette: ConfluencePalette) {
        self.coordinator = coordinator
        self.palette = palette
    }

    private var filteredSignals: [TradeSignal] {
        coordinator.signals.filter { sig in
            if let market = selectedMarket, sig.marketClass != market {
                return false
            }
            switch feedFilter {
            case .strong: return sig.category == .strongSignal
            case .traps: return sig.category == .trapAlert
            case .weak: return sig.category == .weakSignal && coordinator.settings.payload.showWeakFilteredSignals
            }
        }
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Sticky compact Pre-News Countdown Strip whenever a high-impact event is < 60m away
                if let shield = coordinator.imminentPreNewsEvent {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .foregroundStyle(palette.macroIceBlue)
                        Text(shield.badgeText)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(palette.primaryInk)
                        Spacer()
                        if shield.isBlackoutActive {
                            Text("SHIELD ON")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(palette.trapAmber)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(palette.trapAmber.opacity(0.16), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(palette.border).frame(height: 0.5)
                    }
                }

                // Crisis Regime Warning Banner if any active signal is in Crisis
                if coordinator.signals.contains(where: { $0.regime == .crisis }) {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.trianglebadge.exclamationmark.fill")
                            .foregroundStyle(palette.shortCrimson)
                        Text("Crisis volatility regime detected on tracked markets — risk forced to REDUCE.")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(palette.primaryInk)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(palette.shortCrimson.opacity(0.14))
                }

                // Market & Category Filter Bar
                VStack(spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            marketChip(title: "All", isSelected: selectedMarket == nil) {
                                selectedMarket = nil
                            }
                            ForEach(MarketClass.allCases, id: \.self) { market in
                                marketChip(title: market.displayName, isSelected: selectedMarket == market) {
                                    selectedMarket = market
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                    }

                    Picker("Category", selection: $feedFilter) {
                        ForEach(SignalFeedFilter.allCases) { f in
                            if f != .weak || coordinator.settings.payload.showWeakFilteredSignals {
                                Text(f.rawValue).tag(f)
                            }
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 14)
                }
                .padding(.vertical, 10)
                .background(palette.canvas)

                // Lazy Scroll Feed
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if coordinator.isScanning && filteredSignals.isEmpty {
                            ForEach(0..<3, id: \.self) { _ in
                                skeletonCard
                            }
                        } else if filteredSignals.isEmpty {
                            emptyStateView
                        } else {
                            ForEach(filteredSignals) { sig in
                                SignalCardView(
                                    signal: sig,
                                    palette: palette,
                                    density: coordinator.settings.payload.cardDensity,
                                    showMiniChart: coordinator.settings.payload.showMiniCharts,
                                    animateArrival: coordinator.settings.payload.arrivalAnimationsEnabled && coordinator.newlyArrivedSignalIds.contains(sig.id),
                                    hapticsEnabled: coordinator.settings.payload.hapticsEnabled,
                                    onOpenChart: { chartSignal = sig }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 24)
                }
                .refreshable {
                    await coordinator.scanAllMarkets()
                }
            }
            .background(palette.canvas)
            .navigationTitle("Confluence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let last = coordinator.lastScanDate {
                        Text(last.formatted(date: .omitted, time: .shortened))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(palette.tertiaryInk)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await coordinator.scanAllMarkets() }
                    } label: {
                        if coordinator.isScanning {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Scan", systemImage: "waveform.path.ecg")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .disabled(coordinator.isScanning)
                }
            }
            .sheet(item: $chartSignal) { sig in
                FullScreenChartSheet(signal: sig, palette: palette)
            }
        }
    }

    private func marketChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? palette.canvas : palette.secondaryInk)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isSelected ? palette.champagneGold : palette.surface)
                )
                .overlay(
                    Capsule().strokeBorder(isSelected ? Color.clear : palette.border, lineWidth: 0.75)
                )
        }
        .buttonStyle(.plain)
    }

    private var skeletonCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 6).fill(palette.elevatedSurface).frame(width: 140, height: 18)
            RoundedRectangle(cornerRadius: 10).fill(palette.elevatedSurface).frame(height: 92)
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 8).fill(palette.elevatedSurface).frame(height: 44)
                RoundedRectangle(cornerRadius: 8).fill(palette.elevatedSurface).frame(height: 44)
                RoundedRectangle(cornerRadius: 8).fill(palette.elevatedSurface).frame(height: 44)
            }
        }
        .padding(14)
        .institutionalCard(palette: palette)
        .shimmering()
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: feedFilter == .traps ? "exclamationmark.triangle" : "scope")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(palette.champagneGold)
            Text("No \(feedFilter.rawValue) Yet")
                .font(.headline)
                .foregroundStyle(palette.primaryInk)
            Text("Confluence displays strictly live, closed-candle multi-strategy analysis — never placeholder signals. Run a live market scan to evaluate your watchlist.")
                .font(.caption)
                .foregroundStyle(palette.secondaryInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            Button {
                Task { await coordinator.scanAllMarkets() }
            } label: {
                Label("Run Live Scan", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.canvas)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(palette.champagneGold, in: Capsule())
            }
            .padding(.top, 4)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .institutionalCard(palette: palette)
        .padding(.top, 16)
    }
}
