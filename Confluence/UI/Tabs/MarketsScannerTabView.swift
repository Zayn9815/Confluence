import SwiftUI
import SignalEngine

public struct MarketsScannerTabView: View {
    @Bindable var coordinator: MarketScannerCoordinator
    let palette: ConfluencePalette

    public init(coordinator: MarketScannerCoordinator, palette: ConfluencePalette) {
        self.coordinator = coordinator
        self.palette = palette
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // 1. Live Manual Scanner Control Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Multi-Market Scanner")
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(palette.primaryInk)
                                Text("\(coordinator.settings.activeWatchlistAssets.count) active instruments · HTF \(coordinator.settings.payload.htfTimeframe.displayLabel) / Entry \(coordinator.settings.payload.entryTimeframe.displayLabel)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(palette.secondaryInk)
                            }
                            Spacer()
                            Button {
                                Task { await coordinator.scanAllMarkets() }
                            } label: {
                                HStack(spacing: 6) {
                                    if coordinator.isScanning {
                                        ProgressView().controlSize(.small).tint(palette.canvas)
                                    } else {
                                        Image(systemName: "radar")
                                    }
                                    Text(coordinator.isScanning ? "Scanning" : "Scan Now")
                                }
                                .font(.caption.weight(.bold))
                                .foregroundStyle(palette.canvas)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(palette.champagneGold, in: Capsule())
                            }
                            .disabled(coordinator.isScanning)
                        }

                        // Timeframe Selector
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("HTF BIAS")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(palette.tertiaryInk)
                                Picker("HTF", selection: $coordinator.settings.payload.htfTimeframe) {
                                    Text("4H").tag(Timeframe.h4)
                                    Text("1D").tag(Timeframe.d1)
                                }
                                .pickerStyle(.segmented)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("ENTRY TF")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(palette.tertiaryInk)
                                Picker("Entry", selection: Binding(
                                    get: { coordinator.settings.payload.entryTimeframe },
                                    set: { newTF in
                                        coordinator.handleEntryTimeframeChanged(to: newTF)
                                    }
                                )) {
                                    Text("15m").tag(Timeframe.m15)
                                    Text("30m").tag(Timeframe.m30)
                                    Text("1H").tag(Timeframe.h1)
                                }
                                .pickerStyle(.segmented)
                            }
                        }

                        // Per-market scan progress
                        if !coordinator.scanProgressByMarket.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(MarketClass.allCases, id: \.self) { m in
                                    if let status = coordinator.scanProgressByMarket[m] {
                                        HStack {
                                            Text(m.displayName)
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(palette.secondaryInk)
                                            Spacer()
                                            Text(status)
                                                .font(.caption2.monospacedDigit())
                                                .foregroundStyle(palette.longEmerald)
                                        }
                                    }
                                }
                            }
                            .padding(10)
                            .background(palette.elevatedSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }

                        if let err = coordinator.lastScanError {
                            Text(err)
                                .font(.caption2)
                                .foregroundStyle(palette.trapAmber)
                        }

                        // Background Refresh Status
                        Toggle(isOn: Binding(
                            get: { coordinator.settings.payload.backgroundRefreshEnabled },
                            set: { newVal in
                                coordinator.settings.payload.backgroundRefreshEnabled = newVal
                                coordinator.scheduleNextBackgroundRefresh()
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Background App Refresh (Best-Effort)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(palette.primaryInk)
                                Text("Uses iOS BGAppRefreshTask (zero persistent WebSockets). Pre-News alerts fire at exact second via local notifications.")
                                    .font(.caption2)
                                    .foregroundStyle(palette.tertiaryInk)
                            }
                        }
                        .tint(palette.champagneGold)
                    }
                    .padding(14)
                    .institutionalCard(palette: palette)

                    // 2. Live Active Traps Summary
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            if coordinator.activeTraps.isEmpty {
                                Label("Behavioral Traps Clear (0)", systemImage: "checkmark.shield.fill")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(palette.longEmerald)
                            } else {
                                Label("Active Behavioral Traps (\(coordinator.activeTraps.count))", systemImage: "exclamationmark.triangle.fill")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(palette.trapAmber)
                            }
                            Spacer()
                        }
                        if coordinator.activeTraps.isEmpty {
                            Text("No active Trigger/Active/Returned traps on the latest closed scan.")
                                .font(.caption)
                                .foregroundStyle(palette.secondaryInk)
                        } else {
                            ForEach(coordinator.activeTraps) { trap in
                                HStack(alignment: .top, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(trap.symbol)
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(palette.primaryInk)
                                            Text(trap.direction.rawValue)
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(palette.trapAmber)
                                            Text(trap.state.rawValue.uppercased())
                                                .font(.system(size: 9, weight: .semibold))
                                                .foregroundStyle(palette.secondaryInk)
                                        }
                                        Text(trap.detail)
                                            .font(.caption2)
                                            .foregroundStyle(palette.secondaryInk)
                                    }
                                    Spacer()
                                }
                                .padding(9)
                                .background(palette.elevatedSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            }
                        }
                    }
                    .padding(14)
                    .institutionalCard(palette: palette)

                    // 3. Multi-Market Watchlist Editor
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Watchlist Instruments")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(palette.primaryInk)

                        ForEach(MarketClass.allCases, id: \.self) { market in
                            let items = WatchlistDefaults.assets.filter { $0.marketClass == market }
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(market.displayName.uppercased())
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(palette.champagneGold)
                                    Spacer()
                                    if !coordinator.settings.payload.enabledMarkets.contains(market) {
                                        Text("MARKET DISABLED")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(palette.tertiaryInk)
                                    }
                                }
                                ForEach(items) { asset in
                                    let isSelected = coordinator.settings.payload.watchlistSymbols.contains(asset.symbol)
                                    Button {
                                        coordinator.settings.toggleWatchlistSymbol(asset.symbol)
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(asset.symbol)
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundStyle(palette.primaryInk)
                                                Text(asset.displayName)
                                                    .font(.caption2)
                                                    .foregroundStyle(palette.secondaryInk)
                                            }
                                            Spacer()
                                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(isSelected ? palette.longEmerald : palette.tertiaryInk)
                                        }
                                        .padding(.vertical, 6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(14)
                    .institutionalCard(palette: palette)
                }
                .padding(14)
            }
            .safeAreaPadding(.bottom, 96)
            .background(palette.canvas)
            .navigationTitle("Markets & Scanner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(palette.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NotificationBellButton(
                        unreadCount: coordinator.unreadNotificationCount,
                        palette: palette
                    ) {
                        coordinator.isNotificationInboxPresented = true
                    }
                }
            }
        }
    }
}
