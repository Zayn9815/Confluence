import SwiftUI
import UIKit
import SignalEngine

public struct DiagnosticsHubView: View {
    @Bindable var coordinator: MarketScannerCoordinator
    let palette: ConfluencePalette

    @State private var copiedConfirmation: Bool = false
    @State private var diagnosticJSONURL: URL?
    @State private var showResetConfirmation: Bool = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.3.0"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "4"
    }

    public var body: some View {
        Form {
            // 1. 1-Tap Antigravity Diagnostic Exports
            Section {
                Button {
                    let report = coordinator.diagnosticLog.buildAntigravityMarkdownReport(
                        appVersion: appVersion,
                        appBuild: appBuild,
                        twelveDataQuota: coordinator.twelveDataQuota,
                        twelveDataLocalDailyUsed: coordinator.twelveDataLocalDailyUsed,
                        feedHealth: coordinator.feedHealthResults,
                        calibration: coordinator.calibrationSummary,
                        strategyBreakdowns: coordinator.strategyBreakdowns,
                        tradeLedger: coordinator.tradeLedger,
                        trapLogs: coordinator.trapLogs,
                        crashLogs: coordinator.crashLogStore.entries
                    )
                    UIPasteboard.general.string = report
                    copiedConfirmation = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(2.2))
                        copiedConfirmation = false
                    }
                } label: {
                    HStack {
                        Label(
                            copiedConfirmation ? "Copied Antigravity Report!" : "Copy Antigravity Report (Markdown)",
                            systemImage: copiedConfirmation ? "checkmark.circle.fill" : "doc.on.clipboard"
                        )
                        .foregroundStyle(copiedConfirmation ? palette.longEmerald : palette.champagneGold)
                        Spacer()
                    }
                }

                if let jsonURL = diagnosticJSONURL {
                    ShareLink(item: jsonURL) {
                        Label("Share Full Diagnostic JSON", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button {
                        diagnosticJSONURL = coordinator.diagnosticLog.exportAntigravityJSONFile(
                            appVersion: appVersion,
                            appBuild: appBuild,
                            twelveDataQuota: coordinator.twelveDataQuota,
                            feedHealth: coordinator.feedHealthResults,
                            calibration: coordinator.calibrationSummary,
                            strategyBreakdowns: coordinator.strategyBreakdowns,
                            tradeLedger: coordinator.tradeLedger,
                            trapLogs: coordinator.trapLogs,
                            crashLogs: coordinator.crashLogStore.entries
                        )
                    } label: {
                        Label("Prepare Full Diagnostic JSON", systemImage: "doc.badge.arrow.up")
                    }
                }
            } header: {
                Text("Antigravity Diagnostic Export")
            } footer: {
                Text("Includes runtime logs, error logs, MetricKit/POSIX crash logs, trade ledger, and strategy stats — automatically scrubbed of API keys and tokens.")
            }

            // 2. Dedicated Observability Logs (Runtime, Error, Crash)
            Section("Runtime, Error & Crash Logs") {
                NavigationLink {
                    RuntimeLogViewer(coordinator: coordinator, palette: palette)
                } label: {
                    HStack {
                        Label("All Runtime Logs", systemImage: "terminal")
                        Spacer()
                        Text("\(coordinator.diagnosticLog.entries.count) entries")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(palette.secondaryInk)
                    }
                }

                NavigationLink {
                    ErrorLogsViewer(coordinator: coordinator, palette: palette)
                } label: {
                    HStack {
                        Label("Error Logs", systemImage: "exclamationmark.octagon")
                            .foregroundStyle(coordinator.diagnosticLog.errorOnlyCount > 0 ? palette.shortCrimson : palette.primaryInk)
                        Spacer()
                        Text("\(coordinator.diagnosticLog.errorOnlyCount) err · \(coordinator.diagnosticLog.warnAndErrorCount) total")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(coordinator.diagnosticLog.warnAndErrorCount > 0 ? palette.shortCrimson : palette.secondaryInk)
                    }
                }

                NavigationLink {
                    CrashLogsViewer(coordinator: coordinator, palette: palette)
                } label: {
                    HStack {
                        Label("Crash & Hang Logs", systemImage: "ladybug.fill")
                            .foregroundStyle(coordinator.crashLogStore.entries.isEmpty ? palette.primaryInk : palette.shortCrimson)
                        Spacer()
                        Text("\(coordinator.crashLogStore.entries.count) recorded")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(coordinator.crashLogStore.entries.isEmpty ? palette.secondaryInk : palette.shortCrimson)
                    }
                }
            }

            // 3. Drill-Down Ledgers & Strategy Breakdown
            Section("Trade Ledger & Strategy Breakdown") {
                NavigationLink {
                    TradeLedgerViewer(entries: coordinator.tradeLedger, palette: palette)
                } label: {
                    HStack {
                        Label("Detailed Trade Outcome Ledger", systemImage: "list.bullet.rectangle")
                        Spacer()
                        Text("\(coordinator.tradeLedger.count) setups")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(palette.secondaryInk)
                    }
                }

                NavigationLink {
                    StrategyBreakdownViewer(breakdowns: coordinator.strategyBreakdowns, palette: palette)
                } label: {
                    HStack {
                        Label("Strategy Win/Loss & Failures", systemImage: "chart.bar.doc.horizontal")
                        Spacer()
                        Text("\(coordinator.strategyBreakdowns.count) strategies")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(palette.secondaryInk)
                    }
                }

                NavigationLink {
                    TrapLifecycleLogViewer(traps: coordinator.trapLogs, palette: palette)
                } label: {
                    HStack {
                        Label("4-Stage Trap Lifecycle Logs", systemImage: "exclamationmark.triangle")
                        Spacer()
                        Text("\(coordinator.trapLogs.count) traps")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(palette.secondaryInk)
                    }
                }
            }

            // 4. Live Feed Health & Latency
            Section("Feed Health & Latency") {
                Button {
                    Task { await coordinator.runFeedHealthCheck() }
                } label: {
                    HStack {
                        Label("Run Feed Health Check", systemImage: "stethoscope")
                        Spacer()
                        if coordinator.isCheckingHealth {
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .disabled(coordinator.isCheckingHealth)

                ForEach(coordinator.feedHealthResults) { entry in
                    HStack {
                        Image(systemName: entry.healthy ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(entry.healthy ? palette.longEmerald : palette.shortCrimson)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.name).font(.caption.weight(.semibold))
                            Text(entry.detail).font(.caption2).foregroundStyle(palette.secondaryInk)
                        }
                        Spacer()
                        if entry.latencyMs > 0 {
                            Text("\(Int(entry.latencyMs.rounded()))ms")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(palette.tertiaryInk)
                        }
                    }
                }
            }

            // 5. Reset Controls
            Section("Maintenance") {
                Button(role: .destructive) {
                    showResetConfirmation = true
                } label: {
                    Label("Reset Calibration, Logs & Caches", systemImage: "trash")
                }
            }
        }
        .navigationTitle("Logs & Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Reset Calibration, Logs & Caches?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                coordinator.store.resetCalibrationAndHistory()
                coordinator.diagnosticLog.reload()
                coordinator.crashLogStore.reload()
                coordinator.loadPersistedState()
            }
        } message: {
            Text("Clears recorded signal history, calibration outcomes, trade ledger, trap logs, runtime logs, and cached COT/calendar files. Your Keychain API keys and Bell inbox remain untouched.")
        }
    }
}

// MARK: - Interactive Sub-Viewers

private struct RuntimeLogViewer: View {
    @Bindable var coordinator: MarketScannerCoordinator
    let palette: ConfluencePalette
    @State private var severityFilter: DiagnosticSeverity? = nil

    private var filtered: [DiagnosticLogSnapshot] {
        coordinator.diagnosticLog.entries.filter { e in
            severityFilter == nil || e.severity == severityFilter
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Severity", selection: $severityFilter) {
                Text("All").tag(DiagnosticSeverity?.none)
                ForEach(DiagnosticSeverity.allCases) { sev in
                    Text(sev.rawValue).tag(Optional(sev))
                }
            }
            .pickerStyle(.segmented)
            .padding(12)

            if filtered.isEmpty {
                ContentUnavailableView("No Logs", systemImage: "terminal", description: Text("Run a market scan or feed health check to populate redacted runtime logs."))
            } else {
                List(filtered) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.severity.rawValue)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(color(for: entry.severity))
                            Text(entry.category.rawValue)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(palette.macroIceBlue)
                            Spacer()
                            Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(palette.tertiaryInk)
                        }
                        Text(entry.message)
                            .font(.caption)
                            .foregroundStyle(palette.primaryInk)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Runtime Logs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !coordinator.diagnosticLog.entries.isEmpty {
                    Button("Clear", role: .destructive) {
                        coordinator.diagnosticLog.clear()
                    }
                    .font(.caption)
                }
            }
        }
    }

    private func color(for sev: DiagnosticSeverity) -> Color {
        switch sev {
        case .info: return palette.secondaryInk
        case .warn: return palette.trapAmber
        case .error: return palette.shortCrimson
        }
    }
}

private struct ErrorLogsViewer: View {
    @Bindable var coordinator: MarketScannerCoordinator
    let palette: ConfluencePalette

    @State private var includeWarnings: Bool = true
    @State private var copied: Bool = false

    private var filtered: [DiagnosticLogSnapshot] {
        includeWarnings ? coordinator.diagnosticLog.errorAndCriticalEntries : coordinator.diagnosticLog.errorOnlyEntries
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Scope", selection: $includeWarnings) {
                Text("Errors + Warnings").tag(true)
                Text("Errors Only").tag(false)
            }
            .pickerStyle(.segmented)
            .padding(12)

            if filtered.isEmpty {
                ContentUnavailableView(
                    "Zero Errors Recorded",
                    systemImage: "checkmark.shield",
                    description: Text("Runtime feed errors, parsing failures, and critical warnings appear here automatically with secrets scrubbed.")
                )
            } else {
                List(filtered) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.severity.rawValue)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(entry.severity == .error ? palette.shortCrimson : palette.trapAmber)
                            Text(entry.category.rawValue)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(palette.macroIceBlue)
                            Spacer()
                            Text(entry.timestamp.formatted(date: .abbreviated, time: .standard))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(palette.tertiaryInk)
                        }
                        Text(entry.message)
                            .font(.caption)
                            .foregroundStyle(palette.primaryInk)
                        if let detail = entry.detail, !detail.isEmpty {
                            Text(detail)
                                .font(.caption2)
                                .foregroundStyle(palette.secondaryInk)
                        }
                    }
                    .padding(.vertical, 3)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Error Logs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    let iso = ISO8601DateFormatter()
                    let text = filtered.map { e in
                        "[\(e.severity.rawValue)][\(e.category.rawValue)] \(iso.string(from: e.timestamp)): \(e.message)"
                    }.joined(separator: "\n")
                    UIPasteboard.general.string = SecretRedactor.redact(text)
                    copied = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.8))
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                }
                .disabled(filtered.isEmpty)
            }
        }
    }
}

private struct CrashLogsViewer: View {
    @Bindable var coordinator: MarketScannerCoordinator
    let palette: ConfluencePalette

    @State private var expandedCrashIDs: Set<String> = []
    @State private var copied: Bool = false

    var body: some View {
        Group {
            if coordinator.crashLogStore.entries.isEmpty {
                ContentUnavailableView(
                    "No Crash Logs Recorded",
                    systemImage: "checkmark.seal",
                    description: Text("Apple MetricKit crash/hang payloads, uncaught exceptions, and POSIX fatal signal breadcrumbs are captured automatically on-device and scrubbed before storage.")
                )
            } else {
                List(coordinator.crashLogStore.entries) { crash in
                    let isExpanded = expandedCrashIDs.contains(crash.id)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(crash.source.rawValue.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(palette.shortCrimson)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(palette.shortCrimson.opacity(0.14), in: Capsule())
                            Text("v\(crash.appVersion) (\(crash.appBuild))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(palette.secondaryInk)
                            Spacer()
                            Text(crash.timestamp.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(palette.tertiaryInk)
                        }

                        Text(crash.crashType)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(palette.primaryInk)

                        Text(crash.summary)
                            .font(.caption)
                            .foregroundStyle(palette.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if isExpanded {
                                    expandedCrashIDs.remove(crash.id)
                                } else {
                                    expandedCrashIDs.insert(crash.id)
                                }
                            }
                        } label: {
                            Label(isExpanded ? "Hide Stack Trace" : "Inspect Stack Trace", systemImage: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(palette.macroIceBlue)
                        }
                        .buttonStyle(.plain)

                        if isExpanded {
                            ScrollView(.horizontal, showsIndicators: true) {
                                Text(crash.stackTrace)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(palette.secondaryInk)
                                    .textSelection(.enabled)
                            }
                            .padding(8)
                            .background(palette.elevatedSurface.opacity(0.75), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Crash & Hang Logs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    let iso = ISO8601DateFormatter()
                    let text = coordinator.crashLogStore.entries.map { c in
                        """
                        [\(c.source.rawValue)] \(iso.string(from: c.timestamp)) | v\(c.appVersion) (\(c.appBuild))
                        Type: \(c.crashType)
                        Summary: \(c.summary)
                        Stack:
                        \(c.stackTrace)
                        """
                    }.joined(separator: "\n\n---\n\n")
                    UIPasteboard.general.string = SecretRedactor.redact(text)
                    copied = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.8))
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                }
                .disabled(coordinator.crashLogStore.entries.isEmpty)
            }

            ToolbarItem(placement: .topBarTrailing) {
                if !coordinator.crashLogStore.entries.isEmpty {
                    Button("Clear", role: .destructive) {
                        coordinator.crashLogStore.clear()
                    }
                    .font(.caption)
                }
            }
        }
    }
}

private struct TradeLedgerViewer: View {
    let entries: [TradeLedgerSnapshot]
    let palette: ConfluencePalette
    @State private var statusFilter: String = "All"

    private let filters = ["All", "Wins", "Losses", "Open"]

    private var filtered: [TradeLedgerSnapshot] {
        entries.filter { t in
            switch statusFilter {
            case "Wins": return t.status == .tp1Win || t.status == .tp2Win
            case "Losses": return t.status == .slLoss
            case "Open": return t.status == .open
            default: return true
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Filter", selection: $statusFilter) {
                ForEach(filters, id: \.self) { f in Text(f).tag(f) }
            }
            .pickerStyle(.segmented)
            .padding(12)

            if filtered.isEmpty {
                ContentUnavailableView("No Trade Records", systemImage: "list.bullet.rectangle", description: Text("Strong Signals and Trap setups are recorded here automatically and evaluated passively against subsequent closed candles."))
            } else {
                List(filtered) { t in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("\(t.symbol) · \(t.timeframe.displayLabel)")
                                .font(.subheadline.weight(.bold))
                            Text(t.direction.rawValue.uppercased())
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(t.direction == .long ? palette.longEmerald : palette.shortCrimson)
                            Spacer()
                            Text(t.status.rawValue)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(statusColor(t.status))
                        }
                        HStack(spacing: 10) {
                            Text("Net: \(String(format: "%+.2fR", t.netRMultiple))")
                                .font(.caption.weight(.semibold).monospacedDigit())
                            Text("Conf: \(Int(t.confidencePercent.rounded()))%")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(palette.secondaryInk)
                            Text(t.regime.badgeLabel)
                                .font(.caption2)
                                .foregroundStyle(palette.secondaryInk)
                            Spacer()
                            Text(t.dataProvider)
                                .font(.caption2)
                                .foregroundStyle(palette.tertiaryInk)
                        }
                    }
                    .padding(.vertical, 3)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Trade Outcome Ledger")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statusColor(_ s: TradeLedgerStatus) -> Color {
        switch s {
        case .tp1Win, .tp2Win: return palette.longEmerald
        case .slLoss: return palette.shortCrimson
        case .open: return palette.champagneGold
        case .pending: return palette.macroIceBlue
        case .notFilled, .invalidated, .expired: return palette.tertiaryInk
        }
    }
}

private struct StrategyBreakdownViewer: View {
    let breakdowns: [StrategyDiagnosticBreakdown]
    let palette: ConfluencePalette

    var body: some View {
        Group {
            if breakdowns.isEmpty {
                ContentUnavailableView("No Resolved Strategies Yet", systemImage: "chart.bar.doc.horizontal", description: Text("Per-strategy win/loss rate, Brier contribution, and best/worst pairs & regimes populate once recorded signals resolve."))
            } else {
                List(breakdowns) { s in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(s.displayName)
                                .font(.subheadline.weight(.bold))
                            Spacer()
                            Text("\(s.wins)W / \(s.losses)L (\(Int((s.winRate * 100).rounded()))%)")
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(s.winRate >= 0.5 ? palette.longEmerald : palette.shortCrimson)
                        }
                        HStack {
                            Text("Expectancy: \(String(format: "%+.2fR", s.expectancyR))")
                            Spacer()
                            Text("Brier: \(String(format: "%.3f", s.brierContribution))")
                        }
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(palette.secondaryInk)

                        if !s.bestPairs.isEmpty || !s.worstPairs.isEmpty {
                            Text("Best: \(s.bestPairs.joined(separator: ", ")) · Worst: \(s.worstPairs.joined(separator: ", "))")
                                .font(.caption2)
                                .foregroundStyle(palette.tertiaryInk)
                        }
                        if !s.bestRegimes.isEmpty || !s.worstRegimes.isEmpty {
                            Text("Regimes — Best: \(s.bestRegimes.joined(separator: ", ")) · Worst: \(s.worstRegimes.joined(separator: ", "))")
                                .font(.caption2)
                                .foregroundStyle(palette.tertiaryInk)
                        }
                    }
                    .padding(.vertical, 3)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Strategy Breakdown")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TrapLifecycleLogViewer: View {
    let traps: [TrapLogSnapshot]
    let palette: ConfluencePalette

    var body: some View {
        Group {
            if traps.isEmpty {
                ContentUnavailableView("No Trap Logs Yet", systemImage: "exclamationmark.triangle", description: Text("4-stage behavioral traps (Trigger -> Active -> Returned -> Invalid) and post-trap respect accuracy are logged here automatically."))
            } else {
                List(traps) { tr in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("\(tr.symbol) · \(tr.timeframe.displayLabel)")
                                .font(.subheadline.weight(.bold))
                            Text(tr.direction.rawValue)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(palette.trapAmber)
                            Spacer()
                            Text(tr.currentState.rawValue.uppercased())
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(palette.macroIceBlue)
                        }
                        HStack {
                            Text("\(tr.triggerKind.rawValue) @ \(String(format: "%.2f", tr.priceLevel))")
                            Spacer()
                            Text(tr.postTrapOutcome.rawValue)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(tr.postTrapOutcome == .respected ? palette.longEmerald : (tr.postTrapOutcome == .invalidated ? palette.shortCrimson : palette.secondaryInk))
                        }
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(palette.secondaryInk)

                        Text(tr.positioningContext)
                            .font(.caption2)
                            .foregroundStyle(palette.tertiaryInk)
                    }
                    .padding(.vertical, 3)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Trap Lifecycle Logs")
        .navigationBarTitleDisplayMode(.inline)
    }
}
