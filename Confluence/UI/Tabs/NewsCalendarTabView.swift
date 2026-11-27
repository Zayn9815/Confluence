import SwiftUI
import SignalEngine

public enum NewsSubTab: String, CaseIterable, Identifiable {
    case calendar = "Economic Calendar"
    case radar = "Breaking Radar"
    public var id: String { rawValue }
}

public struct NewsCalendarTabView: View {
    @Bindable var coordinator: MarketScannerCoordinator
    let palette: ConfluencePalette

    @State private var subTab: NewsSubTab = .calendar
    @State private var impactFilter: MacroImportance = .medium
    @State private var selectedCurrency: String = "ALL"
    @State private var selectedAnalysisTarget: NewsAnalysisTarget?

    private let currencies = ["ALL", "USD", "EUR", "GBP", "JPY"]

    public init(coordinator: MarketScannerCoordinator, palette: ConfluencePalette) {
        self.coordinator = coordinator
        self.palette = palette
    }

    private var filteredCalendar: [EconomicEvent] {
        coordinator.calendarEvents.filter { ev in
            ev.importance >= impactFilter &&
            (selectedCurrency == "ALL" || ev.currency == selectedCurrency)
        }
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("News Section", selection: $subTab) {
                    ForEach(NewsSubTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                if subTab == .calendar {
                    calendarContent
                } else {
                    breakingRadarContent
                }
            }
            .background(palette.canvas)
            .navigationTitle("News & Macro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await coordinator.scanAllMarkets() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(coordinator.isScanning)
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
            .sheet(item: $selectedAnalysisTarget) { target in
                NewsTradeAnalysisSheet(target: target, coordinator: coordinator, palette: palette)
            }
        }
    }

    private var calendarContent: some View {
        VStack(spacing: 8) {
            // Filters
            HStack(spacing: 8) {
                Menu {
                    Button("High Only") { impactFilter = .high }
                    Button("Medium + High") { impactFilter = .medium }
                    Button("All Impact") { impactFilter = .low }
                } label: {
                    Label(impactFilter == .high ? "High Impact" : (impactFilter == .medium ? "Med + High" : "All"), systemImage: "line.3.horizontal.decrease.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.primaryInk)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(palette.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(palette.border, lineWidth: 0.75))
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(currencies, id: \.self) { ccy in
                            Button {
                                selectedCurrency = ccy
                            } label: {
                                Text(ccy == "ALL" ? "All / Gold & Crypto" : ccy)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(selectedCurrency == ccy ? palette.onAccentInk : palette.secondaryInk)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(selectedCurrency == ccy ? palette.champagneGold : palette.surface))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        // Source & Pre-News queue status banner
                        HStack {
                            Text("Feed: \(coordinator.calendarSourceLabel)")
                                .font(.caption2)
                                .foregroundStyle(palette.tertiaryInk)
                            Spacer()
                            Text("\(coordinator.scheduledPreNewsCount) pre-news alerts queued")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(palette.champagneGold)
                        }
                        .padding(.horizontal, 4)

                        if filteredCalendar.isEmpty {
                            emptyCard(
                                icon: "calendar.badge.clock",
                                title: "No Macro Events Loaded",
                                body: "Tap refresh to fetch live scheduled economic releases from biquote.io (with cached Forex Factory fallback)."
                            )
                        } else {
                            let nowEpoch = Date().timeIntervalSince1970
                            ForEach(filteredCalendar) { ev in
                                calendarEventCard(ev, nowEpoch: nowEpoch)
                                    .id(ev.id)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 16)
                }
                .contentMargins(.bottom, 24, for: .scrollContent)
                .refreshable {
                    await coordinator.scanAllMarkets()
                }
                .onChange(of: coordinator.highlightedNewsEventID) { _, eventID in
                    guard let eventID else { return }
                    selectedCurrency = "ALL"
                    impactFilter = .low
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(120))
                        proxy.scrollTo(eventID, anchor: .top)
                        try? await Task.sleep(for: .seconds(2.5))
                        if coordinator.highlightedNewsEventID == eventID {
                            coordinator.highlightedNewsEventID = nil
                        }
                    }
                }
            }
        }
    }

    private func calendarEventCard(_ ev: EconomicEvent, nowEpoch: TimeInterval) -> some View {
        let surprise = MacroSurpriseEngine.evaluateSurprise(event: ev, nowEpochSeconds: nowEpoch)
        let impactColor: Color = {
            switch ev.importance {
            case .high: return palette.shortCrimson
            case .medium: return palette.trapAmber
            case .low: return palette.tertiaryInk
            }
        }()

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Circle().fill(impactColor).frame(width: 7, height: 7)
                        Text("\(ev.countryCode) · \(ev.currency)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(palette.secondaryInk)
                        Text(ev.importance.rawValue.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(impactColor)
                        if ev.hasRevision {
                            Text("REVISED")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(palette.champagneGold)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(palette.champagneGold.opacity(0.14), in: Capsule())
                        }
                    }
                    Text(ev.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.primaryInk)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if ev.isExactClock {
                        Text(
                            TimeDisplayFormatter.formatDateTime(
                                epochSeconds: ev.scheduledEpochSeconds,
                                use24Hour: coordinator.settings.payload.use24HourTime,
                                useUTC: coordinator.settings.payload.useUTCTimeZone
                            )
                        )
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(palette.secondaryInk)
                        if !ev.isPublished && ev.scheduledEpochSeconds > nowEpoch {
                            let mins = Int(ceil((ev.scheduledEpochSeconds - nowEpoch) / 60.0))
                            Text(mins < 120 ? "in \(mins)m" : "in \(mins / 60)h \(mins % 60)m")
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(palette.champagneGold)
                        }
                    } else {
                        // Strict rule: non-exact timeMode displays date only & suppresses countdown
                        Text(ev.scheduledDate.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(palette.tertiaryInk)
                        Text(ev.timeMode.rawValue.uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(palette.tertiaryInk)
                    }
                }
            }

            // Actual / Forecast / Previous numeric strip (nil stays "—", NEVER 0)
            HStack(spacing: 8) {
                macroValCell("ACTUAL", formatMacroNumber(ev.actual, unit: ev.unit, multiplier: ev.multiplier), accent: ev.isPublished ? palette.primaryInk : palette.tertiaryInk)
                macroValCell("FORECAST", formatMacroNumber(ev.forecast, unit: ev.unit, multiplier: ev.multiplier), accent: palette.secondaryInk)
                macroValCell("PREVIOUS", formatMacroNumber(ev.revisedPrevious ?? ev.previous, unit: ev.unit, multiplier: ev.multiplier), accent: palette.tertiaryInk)
            }

            if let surp = surprise {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(surp.summaryLine)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(palette.champagneGold)
                        Spacer()
                        Text(String(format: "%+.1f%%", surp.surprisePercent))
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(surp.currencyStance == .hawkish ? palette.longEmerald : (surp.currencyStance == .dovish ? palette.shortCrimson : palette.secondaryInk))
                    }
                    if surp.isInPostNewsWhipsawWindow {
                        Label("Whipsaw Caution: first 5 minutes post-release — wait for closed confirmation bar.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(palette.trapAmber)
                    }
                }
                .padding(8)
                .background(palette.elevatedSurface.opacity(0.75), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else if !ev.supportsActualRelease {
                Text("Schedule fallback (Forex Factory): powers Pre-News Shield; actual prints require biquote.io.")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.tertiaryInk)
            }

            HStack {
                Label("Analyze Market Direction & Trade Setup", systemImage: "scope")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(palette.champagneGold)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(palette.tertiaryInk)
            }
            .padding(.top, 2)
        }
        .padding(12)
        .institutionalCard(
            palette: palette,
            accentBorder: coordinator.highlightedNewsEventID == ev.id ? palette.champagneGold : nil
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedAnalysisTarget = .event(ev)
        }
    }

    private var breakingRadarContent: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                // Crypto Fear & Greed Gauge (strictly Crypto-only)
                if coordinator.settings.payload.enabledMarkets.contains(.crypto),
                   let fg = coordinator.fearGreed {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .stroke(palette.border, lineWidth: 4)
                            Circle()
                                .trim(from: 0, to: CGFloat(max(0, min(100, fg.value))) / 100.0)
                                .stroke(fg.value >= 60 ? palette.longEmerald : (fg.value <= 40 ? palette.shortCrimson : palette.champagneGold), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Text("\(fg.value)")
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(palette.primaryInk)
                        }
                        .frame(width: 44, height: 44)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("Crypto Fear & Greed Index")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(palette.secondaryInk)
                                Text("CRYPTO ONLY")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(palette.champagneGold)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(palette.champagneGold.opacity(0.14), in: Capsule())
                            }
                            Text(fg.classification)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(palette.primaryInk)
                            Text("Source: \(fg.source)")
                                .font(.caption2)
                                .foregroundStyle(palette.tertiaryInk)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .institutionalCard(palette: palette)
                }

                if coordinator.breakingNews.isEmpty {
                    emptyCard(
                        icon: "newspaper",
                        title: "No Breaking Headlines Loaded",
                        body: "Pull to refresh or run a scan to load live headlines from cryptocurrency.cv, biquote.io, RSS wires, and optional Finnhub."
                    )
                } else {
                    ForEach(coordinator.breakingNews) { item in
                        newsCard(item)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 16)
        }
        .contentMargins(.bottom, 24, for: .scrollContent)
        .refreshable {
            await coordinator.scanAllMarkets()
        }
    }

    private func newsCard(_ item: BreakingNewsItem) -> some View {
        let sentColor: Color = {
            switch item.sentiment {
            case .bullish: return palette.longEmerald
            case .bearish: return palette.shortCrimson
            case .volatileNeutral: return palette.trapAmber
            }
        }()

        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(item.sentiment.rawValue.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(sentColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(sentColor.opacity(0.14), in: Capsule())

                Text(item.source)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(palette.secondaryInk)

                Spacer()

                Text(
                    TimeDisplayFormatter.formatShortTime(
                        epochSeconds: item.publishedEpochSeconds,
                        use24Hour: coordinator.settings.payload.use24HourTime,
                        useUTC: coordinator.settings.payload.useUTCTimeZone
                    )
                )
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(palette.tertiaryInk)
            }

            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.primaryInk)
                .multilineTextAlignment(.leading)

            if !item.affectedAssets.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(item.affectedAssets, id: \.self) { sym in
                            Text(sym)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(palette.secondaryInk)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(palette.elevatedSurface, in: Capsule())
                        }
                    }
                }
            }

            if let note = item.aiImpactNote {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(palette.champagneGold)
            }

            HStack {
                Label("Analyze Direction & News+Math Setup", systemImage: "scope")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(palette.champagneGold)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(palette.tertiaryInk)
            }
            .padding(.top, 2)
        }
        .padding(12)
        .institutionalCard(palette: palette)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedAnalysisTarget = .article(item)
        }
    }

    private func macroValCell(_ title: String, _ value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(palette.tertiaryInk)
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(7)
        .background(palette.elevatedSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func formatMacroNumber(_ val: Double?, unit: String?, multiplier: String?) -> String {
        guard let val else { return "—" }
        let suffix: String
        switch multiplier?.lowercased() {
        case "thousands": suffix = "K"
        case "millions": suffix = "M"
        case "billions": suffix = "B"
        default: suffix = (unit?.lowercased() == "percent") ? "%" : ""
        }
        if abs(val) >= 1000 {
            return String(format: "%.0f%@", val, suffix)
        }
        return String(format: "%.2f%@", val, suffix)
    }

    private func emptyCard(icon: String, title: String, body: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(palette.champagneGold)
            Text(title).font(.headline).foregroundStyle(palette.primaryInk)
            Text(body).font(.caption).foregroundStyle(palette.secondaryInk).multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .institutionalCard(palette: palette)
    }
}
