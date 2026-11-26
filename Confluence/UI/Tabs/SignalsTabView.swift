import SwiftUI
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
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedMarket: MarketClass? = nil // nil == All
    @State private var feedFilter: SignalFeedFilter = .strong
    @State private var chartSignal: TradeSignal?
    @State private var sizerSignal: TradeSignal?
    @State private var journalDraft: JournalEntrySnapshot?
    @State private var journalDraftIsExisting: Bool = false
    @State private var glossaryQuery: GlossarySheetQuery?
    @State private var preNewsTick: Date = Date()

    // Signal Deletion & Multi-Select State
    @State private var isSelecting: Bool = false
    @State private var selectedFingerprints: Set<String> = []
    @State private var confirmDeleteSelected: Bool = false
    @State private var confirmDeleteCurrentTab: Bool = false
    @State private var confirmDeleteAll: Bool = false

    public init(coordinator: MarketScannerCoordinator, palette: ConfluencePalette) {
        self.coordinator = coordinator
        self.palette = palette
    }

    private var currentSignalCategory: SignalCategory {
        switch feedFilter {
        case .strong: return .strongSignal
        case .traps: return .trapAlert
        case .weak: return .weakSignal
        }
    }

    private var filteredSignals: [TradeSignal] {
        coordinator.displaySignals.filter { sig in
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
        let _ = preNewsTick // lightweight 30s refresh trigger only when an imminent pre-news event is visible
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

                // Net Exposure Correlation Strip (visible whenever 2+ Strong signals share a macro cluster)
                if feedFilter == .strong && coordinator.netExposureSummary.hasConcentratedRisk {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Label("Net Exposure", systemImage: "point.3.connected.trianglepath.dotted")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(palette.trapAmber)
                            ForEach(coordinator.netExposureSummary.concentratedClusters) { cluster in
                                Text(cluster.summaryBadge)
                                    .font(.caption2.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(palette.primaryInk)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(palette.trapAmber.opacity(0.16), in: Capsule())
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                    }
                    .background(palette.surface.opacity(0.9))
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(palette.border).frame(height: 0.5)
                    }
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

                // Lazy Scroll Feed with Deep-Link ScrollViewReader
                ScrollViewReader { proxy in
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
                                    let isHighlighted = (coordinator.highlightedSignalFingerprint == sig.fingerprint)
                                    let isRowSelected = selectedFingerprints.contains(sig.fingerprint)
                                    let brokerOffset = coordinator.settings.brokerOffset(for: sig.symbol)
                                    let adjLevels = coordinator.settings.displayLevels(for: sig)
                                    let isBrokerAdj = coordinator.settings.payload.showBrokerAdjustedLevels && brokerOffset != nil
                                    let isTaken = coordinator.journalEntry(forSignalFingerprint: sig.fingerprint) != nil

                                    SignalCardView(
                                        signal: sig,
                                        outcome: coordinator.outcomeBySignalId[sig.fingerprint],
                                        displayLevelsOverride: adjLevels,
                                        brokerOffsetInfo: brokerOffset,
                                        isBrokerAdjusted: isBrokerAdj,
                                        correlationWarnings: coordinator.correlationWarningsByFingerprint[sig.fingerprint] ?? [],
                                        isTakenInJournal: isTaken,
                                        use24HourTime: coordinator.settings.payload.use24HourTime,
                                        useUTCTimeZone: coordinator.settings.payload.useUTCTimeZone,
                                        palette: palette,
                                        density: coordinator.settings.payload.cardDensity,
                                        showMiniChart: coordinator.settings.payload.showMiniCharts,
                                        animateArrival: coordinator.settings.payload.arrivalAnimationsEnabled && coordinator.newlyArrivedSignalIds.contains(sig.id),
                                        hapticsEnabled: coordinator.settings.payload.hapticsEnabled,
                                        isSelecting: isSelecting,
                                        isSelected: isRowSelected,
                                        livePrice: coordinator.livePriceService.latest(for: sig.symbol)?.price,
                                        onToggleSelect: {
                                            toggleSelection(for: sig.fingerprint)
                                        },
                                        onDelete: {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                coordinator.deleteSignal(fingerprint: sig.fingerprint)
                                                selectedFingerprints.remove(sig.fingerprint)
                                            }
                                        },
                                        onToggleBrokerAdjusted: {
                                            coordinator.settings.payload.showBrokerAdjustedLevels.toggle()
                                        },
                                        onOpenPositionSizer: {
                                            sizerSignal = sig
                                        },
                                        onMarkAsTaken: {
                                            journalDraftIsExisting = isTaken
                                            journalDraft = coordinator.makeJournalDraft(from: sig)
                                        },
                                        onOpenGlossaryTerm: { term in
                                            glossaryQuery = GlossarySheetQuery(query: term)
                                        },
                                        onOpenChart: { chartSignal = sig }
                                    )
                                    .id(sig.fingerprint)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(isHighlighted ? palette.champagneGold : Color.clear, lineWidth: isHighlighted ? 2.0 : 0)
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, isSelecting ? 84 : 24)
                    }
                    .refreshable {
                        await coordinator.scanAllMarkets()
                    }
                    .onAppear {
                        handlePendingDeepLink(coordinator.pendingDeepLink, proxy: proxy)
                    }
                    .onChange(of: coordinator.pendingDeepLink) { _, link in
                        handlePendingDeepLink(link, proxy: proxy)
                    }
                    .onChange(of: coordinator.settings.payload.showWeakFilteredSignals) { _, showWeak in
                        if !showWeak && feedFilter == .weak {
                            feedFilter = .strong
                        }
                    }
                }
            }
            .background(palette.canvas)
            .safeAreaInset(edge: .bottom) {
                if isSelecting {
                    multiSelectActionBar
                }
            }
            .navigationTitle(isSelecting ? "Select (\(selectedFingerprints.count))" : "Confluence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Leading: Dark/Light Toggle (or Done while selecting)
                ToolbarItem(placement: .topBarLeading) {
                    if isSelecting {
                        Button("Done") {
                            exitSelectionMode()
                        }
                        .font(.subheadline.weight(.semibold))
                    } else {
                        let isDarkActive = (coordinator.settings.payload.appearanceMode == .dark)
                            || (coordinator.settings.payload.appearanceMode == .system && colorScheme == .dark)
                        ThemeModeToggleButton(
                            isDark: isDarkActive,
                            hapticsEnabled: coordinator.settings.payload.hapticsEnabled,
                            palette: palette
                        ) {
                            coordinator.settings.toggleDarkLightMode(currentlyDark: isDarkActive)
                        }
                    }
                }

                // Trailing: Discrete native icon-only ToolbarItems (prevents iOS 27 Liquid Glass clipping!)
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isSelecting = true
                                selectedFingerprints.removeAll()
                            }
                        } label: {
                            Label("Select Signals", systemImage: "checkmark.circle")
                        }
                        .disabled(filteredSignals.isEmpty)

                        Divider()

                        Button(role: .destructive) {
                            confirmDeleteCurrentTab = true
                        } label: {
                            Label("Delete \(feedFilter.rawValue) (\(filteredSignals.count))", systemImage: "trash")
                        }
                        .disabled(filteredSignals.isEmpty)

                        Button(role: .destructive) {
                            confirmDeleteAll = true
                        } label: {
                            Label("Delete All Signals (\(coordinator.signals.count))", systemImage: "trash.slash")
                        }
                        .disabled(coordinator.signals.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(palette.primaryInk)
                    }
                    .accessibilityLabel("Manage signals")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await coordinator.scanAllMarkets() }
                    } label: {
                        if coordinator.isScanning {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "waveform.path.ecg")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(palette.champagneGold)
                        }
                    }
                    .disabled(coordinator.isScanning)
                    .accessibilityLabel("Scan live markets")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    NotificationBellButton(
                        unreadCount: coordinator.unreadNotificationCount,
                        palette: palette
                    ) {
                        coordinator.isNotificationInboxPresented = true
                    }
                }
            }
            .confirmationDialog(
                "Delete \(selectedFingerprints.count) Selected Signal\(selectedFingerprints.count == 1 ? "" : "s")?",
                isPresented: $confirmDeleteSelected,
                titleVisibility: .visible
            ) {
                Button("Delete Selected (\(selectedFingerprints.count))", role: .destructive) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        coordinator.deleteSignals(fingerprints: selectedFingerprints)
                        exitSelectionMode()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Deleted signal cards are permanently removed from the feed. Your Calibration Stats and Trade Ledger history remain preserved.")
            }
            .confirmationDialog(
                "Delete All \(feedFilter.rawValue)?",
                isPresented: $confirmDeleteCurrentTab,
                titleVisibility: .visible
            ) {
                Button("Delete \(feedFilter.rawValue)", role: .destructive) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if selectedMarket != nil {
                            coordinator.deleteSignals(fingerprints: Set(filteredSignals.map(\.fingerprint)))
                        } else {
                            coordinator.deleteSignals(in: currentSignalCategory)
                        }
                        exitSelectionMode()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes all cards from \(feedFilter.rawValue) permanently. Your Calibration Stats and Trade Ledger history remain preserved.")
            }
            .confirmationDialog(
                "Delete All Signals Across All Tabs?",
                isPresented: $confirmDeleteAll,
                titleVisibility: .visible
            ) {
                Button("Delete All Signals", role: .destructive) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        coordinator.deleteAllSignals()
                        exitSelectionMode()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Clears Strong Signals, Trap Alerts, and Weak / Filtered cards permanently. Your Calibration Stats and Trade Ledger history remain preserved.")
            }
            .sheet(item: $chartSignal) { sig in
                FullScreenChartSheet(signal: sig, palette: palette, coordinator: coordinator)
            }
            .sheet(item: $sizerSignal) { sig in
                if let lv = coordinator.settings.displayLevels(for: sig) ?? sig.levels {
                    PositionSizeCalculatorSheet(
                        signal: sig,
                        activeLevels: lv,
                        coordinator: coordinator,
                        palette: palette
                    )
                }
            }
            .sheet(item: $journalDraft) { draft in
                JournalEntryEditorSheet(
                    entry: draft,
                    isExisting: journalDraftIsExisting,
                    coordinator: coordinator,
                    palette: palette
                )
            }
            .sheet(item: $glossaryQuery) { q in
                NavigationStack {
                    GlossaryView(palette: palette, initialQuery: q.query)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { glossaryQuery = nil }
                            }
                        }
                }
            }
            .task(id: coordinator.imminentPreNewsEvent?.event.id) {
                guard coordinator.imminentPreNewsEvent != nil else { return }
                while !Task.isCancelled && coordinator.imminentPreNewsEvent != nil {
                    try? await Task.sleep(for: .seconds(30))
                    preNewsTick = Date()
                }
            }
        }
    }

    private func toggleSelection(for fingerprint: String) {
        if selectedFingerprints.contains(fingerprint) {
            selectedFingerprints.remove(fingerprint)
        } else {
            selectedFingerprints.insert(fingerprint)
        }
    }

    private func exitSelectionMode() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSelecting = false
            selectedFingerprints.removeAll()
        }
    }

    private var multiSelectActionBar: some View {
        let visibleFPs = Set(filteredSignals.map(\.fingerprint))
        let allVisibleSelected = !visibleFPs.isEmpty && visibleFPs.isSubset(of: selectedFingerprints)
        return HStack(spacing: 10) {
            Button {
                if allVisibleSelected {
                    selectedFingerprints.subtract(visibleFPs)
                } else {
                    selectedFingerprints.formUnion(visibleFPs)
                }
            } label: {
                Text(allVisibleSelected ? "Deselect All" : "Select All")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.primaryInk)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(palette.elevatedSurface, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(visibleFPs.isEmpty)

            Spacer()

            Button(role: .destructive) {
                confirmDeleteSelected = true
            } label: {
                Label("Delete (\(selectedFingerprints.count))", systemImage: "trash.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(selectedFingerprints.isEmpty ? palette.tertiaryInk.opacity(0.4) : palette.shortCrimson)
                    )
            }
            .buttonStyle(.plain)
            .disabled(selectedFingerprints.isEmpty)

            Button("Cancel") {
                exitSelectionMode()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(palette.secondaryInk)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.border).frame(height: 0.5)
        }
    }

    private func handlePendingDeepLink(_ link: NavigationDeepLink?, proxy: ScrollViewProxy) {
        guard case let .signal(fp, category, _, _) = link else { return }
        selectedMarket = nil
        if category == .trapAlert {
            feedFilter = .traps
        } else {
            feedFilter = .strong
        }
        coordinator.highlightedSignalFingerprint = fp
        coordinator.pendingDeepLink = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.easeInOut(duration: 0.35)) {
                proxy.scrollTo(fp, anchor: .top)
            }
            try? await Task.sleep(for: .seconds(2.2))
            if coordinator.highlightedSignalFingerprint == fp {
                coordinator.highlightedSignalFingerprint = nil
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
        .nativeShimmer()
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

private struct GlossarySheetQuery: Identifiable {
    let id = UUID()
    let query: String
}
