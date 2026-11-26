import Foundation
import OSLog
import SignalEngine

/// Mandatory secret scrubber applied before ANY diagnostic log is persisted or exported.
public enum SecretRedactor {
    private struct CompiledRule: @unchecked Sendable {
        let regex: NSRegularExpression
        let replacement: String
    }

    private static let compiledRules: [CompiledRule] = {
        let rawPatterns: [(String, String)] = [
            (#"(?i)(apikey|api_key|token|key)\s*=\s*[^&\s"'`]+"#, "$1=[REDACTED]"),
            (#"(?i)(x-goog-api-key|authorization)\s*:\s*[^\r\n,;"{}\[\]]+"#, "$1: [REDACTED]"),
            (#"(?i)bearer\s+[A-Za-z0-9\-_\.=]+"#, "Bearer [REDACTED]"),
            (#"AIza[0-9A-Za-z\-_]{20,}"#, "[REDACTED_GEMINI_KEY]"),
            (#"sk-or-[A-Za-z0-9\-_]{16,}"#, "[REDACTED_OPENROUTER_KEY]"),
            (#"sk-[A-Za-z0-9\-_]{16,}"#, "[REDACTED_API_KEY]"),
            (#"\b[a-fA-F0-9]{32,64}\b"#, "[REDACTED_HEX_TOKEN]")
        ]
        return rawPatterns.compactMap { pattern, replacement in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
            return CompiledRule(regex: regex, replacement: replacement)
        }
    }()

    public static func redact(_ input: String) -> String {
        guard !input.isEmpty else { return input }
        var result = input
        for rule in compiledRules {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = rule.regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: rule.replacement)
        }
        return result
    }
}

public struct AntigravityDiagnosticBundle: Codable, Sendable {
    public let exportedAtISO8601: String
    public let appVersion: String
    public let appBuild: String
    public let bundleId: String
    public let twelveDataQuota: TwelveDataQuotaStatus?
    public let feedHealth: [FeedHealthSnapshot]
    public let calibrationSummary: CalibrationSummary
    public let strategyBreakdowns: [StrategyDiagnosticBreakdown]
    public let tradeLedger: [TradeLedgerSnapshot]
    public let trapLogs: [TrapLogSnapshot]
    public let recentRuntimeLogs: [DiagnosticLogSnapshot]
    public let errorLogs: [DiagnosticLogSnapshot]
    public let crashLogs: [CrashLogSnapshot]

    public struct FeedHealthSnapshot: Codable, Sendable {
        public let name: String
        public let healthy: Bool
        public let latencyMs: Double
        public let detail: String
    }
}

@MainActor
@Observable
public final class DiagnosticLogStore {
    private let store: ConfluenceDataStore
    private let osLogger = Logger(subsystem: "com.bilal.confluence", category: "diagnostics")

    public private(set) var entries: [DiagnosticLogSnapshot] = []

    public init(store: ConfluenceDataStore) {
        self.store = store
        self.entries = store.fetchDiagnosticLogs()
        if store.didQuarantineCorruptStore {
            log(.warn, category: .engine, message: "Recovered from incompatible SQLite store via quarantine backup.")
        }
    }

    public func log(
        _ severity: DiagnosticSeverity,
        category: DiagnosticCategory,
        message: String,
        detail: String? = nil
    ) {
        let safeMsg = SecretRedactor.redact(message)
        let safeDetail = detail.map(SecretRedactor.redact)
        let entry = DiagnosticLogSnapshot(
            severity: severity,
            category: category,
            message: safeMsg,
            detail: safeDetail
        )
        store.appendDiagnosticLog(entry)
        entries.insert(entry, at: 0)
        if entries.count > ConfluenceDataStore.maxStoredLogs {
            entries = Array(entries.prefix(ConfluenceDataStore.maxStoredLogs))
        }

        switch severity {
        case .info:
            osLogger.info("[\(category.rawValue, privacy: .public)] \(safeMsg, privacy: .public)")
        case .warn:
            osLogger.warning("[\(category.rawValue, privacy: .public)] \(safeMsg, privacy: .public)")
        case .error:
            osLogger.error("[\(category.rawValue, privacy: .public)] \(safeMsg, privacy: .public)")
        }
    }

    public func reload() {
        entries = store.fetchDiagnosticLogs()
    }

    public func clear() {
        store.clearDiagnosticLogs()
        entries = []
    }

    public var errorAndCriticalEntries: [DiagnosticLogSnapshot] {
        entries.filter { $0.severity == .error || $0.severity == .warn }
    }

    public var errorOnlyEntries: [DiagnosticLogSnapshot] {
        entries.filter { $0.severity == .error }
    }

    public var errorOnlyCount: Int {
        errorOnlyEntries.count
    }

    public var warnAndErrorCount: Int {
        errorAndCriticalEntries.count
    }

    // MARK: - 1-Tap Antigravity Diagnostic Exports (Strictly Scrubbed)

    public func buildAntigravityMarkdownReport(
        appVersion: String,
        appBuild: String,
        twelveDataQuota: TwelveDataQuotaStatus?,
        twelveDataLocalDailyUsed: Int,
        feedHealth: [FeedHealthEntry],
        calibration: CalibrationSummary,
        strategyBreakdowns: [StrategyDiagnosticBreakdown],
        tradeLedger: [TradeLedgerSnapshot],
        trapLogs: [TrapLogSnapshot],
        crashLogs: [CrashLogSnapshot] = []
    ) -> String {
        let iso = ISO8601DateFormatter().string(from: Date())
        var lines: [String] = []
        lines.append("# Confluence Antigravity Diagnostic Report")
        lines.append("- **Generated:** \(iso)")
        lines.append("- **App:** Confluence \(appVersion) (\(appBuild)) · `com.bilal.confluence`")
        if let q = twelveDataQuota {
            lines.append("- **Twelve Data Quota:** \(q.summaryText)")
        } else {
            lines.append("- **Twelve Data Local Calls Today:** \(twelveDataLocalDailyUsed)/780")
        }

        lines.append("\n## Feed Health")
        if feedHealth.isEmpty {
            lines.append("- Not checked in this session.")
        } else {
            for f in feedHealth {
                let icon = f.healthy ? "OK" : "FAIL"
                lines.append("- [\(icon)] \(f.name): \(SecretRedactor.redact(f.detail)) (\(Int(f.latencyMs.rounded()))ms)")
            }
        }

        lines.append("\n## Calibration & Trade Ledger")
        lines.append("- Resolved: \(calibration.resolvedSignals) (\(calibration.tp2Hits) TP2, \(calibration.tp1Hits) TP1, \(calibration.slHits) SL) · Win Rate: \(Int((calibration.winRate * 100).rounded()))% · Net Expectancy: \(String(format: "%+.2fR", calibration.expectancyR)) · Brier: \(String(format: "%.3f", calibration.brierScore))")
        let recentTrades = tradeLedger.prefix(10)
        for t in recentTrades {
            lines.append("  - \(t.symbol) \(t.timeframe.displayLabel) \(t.direction.rawValue.uppercased()) [\(t.status.rawValue)] \(String(format: "%+.2fR", t.netRMultiple)) · \(Int(t.confidencePercent.rounded()))% · \(t.regime.badgeLabel) · \(t.dataProvider)")
        }

        lines.append("\n## Per-Strategy Performance & Failures")
        if strategyBreakdowns.isEmpty {
            lines.append("- No resolved strategy outcomes yet.")
        } else {
            for s in strategyBreakdowns {
                let best = s.bestPairs.isEmpty ? "none" : s.bestPairs.joined(separator: ",")
                let worst = s.worstPairs.isEmpty ? "none" : s.worstPairs.joined(separator: ",")
                let bestReg = s.bestRegimes.isEmpty ? "none" : s.bestRegimes.joined(separator: ",")
                let worstReg = s.worstRegimes.isEmpty ? "none" : s.worstRegimes.joined(separator: ",")
                lines.append("- **\(s.displayName):** \(s.wins)W/\(s.losses)L (\(Int((s.winRate * 100).rounded()))%, \(String(format: "%+.2fR", s.expectancyR)), Brier \(String(format: "%.3f", s.brierContribution))) | Best: \(best) [\(bestReg)] | Worst: \(worst) [\(worstReg)]")
            }
        }

        lines.append("\n## Recent Trap Lifecycle Logs")
        if trapLogs.isEmpty {
            lines.append("- No behavioral traps recorded yet.")
        } else {
            for tr in trapLogs.prefix(12) {
                lines.append("- \(tr.symbol) \(tr.timeframe.displayLabel) \(tr.direction.rawValue) (\(tr.triggerKind.rawValue)) @ \(String(format: "%.2f", tr.priceLevel)) · State: \(tr.currentState.rawValue.uppercased()) · Outcome: \(tr.postTrapOutcome.rawValue)")
            }
        }

        lines.append("\n## Crash & Hang Logs (\(crashLogs.count))")
        if crashLogs.isEmpty {
            lines.append("- Zero crashes or MetricKit hangs recorded.")
        } else {
            for c in crashLogs.prefix(10) {
                let ts = ISO8601DateFormatter().string(from: c.timestamp)
                lines.append("- [\(c.source.rawValue)] \(ts) · v\(c.appVersion) (\(c.appBuild)) · **\(c.crashType)**: \(c.summary)")
                let previewFrames = c.stackTrace.components(separatedBy: .newlines).prefix(6).joined(separator: " | ")
                if !previewFrames.isEmpty {
                    lines.append("  - Stack: `\(previewFrames)`")
                }
            }
        }

        lines.append("\n## Error & Warning Logs (\(errorAndCriticalEntries.count))")
        let issues = errorAndCriticalEntries.prefix(30)
        if issues.isEmpty {
            lines.append("- Zero warnings or errors recorded.")
        } else {
            for e in issues {
                let ts = ISO8601DateFormatter().string(from: e.timestamp)
                lines.append("- [\(e.severity.rawValue)][\(e.category.rawValue)] \(ts): \(e.message)")
            }
        }

        return SecretRedactor.redact(lines.joined(separator: "\n"))
    }

    public func exportAntigravityJSONFile(
        appVersion: String,
        appBuild: String,
        twelveDataQuota: TwelveDataQuotaStatus?,
        feedHealth: [FeedHealthEntry],
        calibration: CalibrationSummary,
        strategyBreakdowns: [StrategyDiagnosticBreakdown],
        tradeLedger: [TradeLedgerSnapshot],
        trapLogs: [TrapLogSnapshot],
        crashLogs: [CrashLogSnapshot] = []
    ) -> URL? {
        let bundle = AntigravityDiagnosticBundle(
            exportedAtISO8601: ISO8601DateFormatter().string(from: Date()),
            appVersion: appVersion,
            appBuild: appBuild,
            bundleId: "com.bilal.confluence",
            twelveDataQuota: twelveDataQuota,
            feedHealth: feedHealth.map {
                .init(name: $0.name, healthy: $0.healthy, latencyMs: $0.latencyMs, detail: SecretRedactor.redact($0.detail))
            },
            calibrationSummary: calibration,
            strategyBreakdowns: strategyBreakdowns,
            tradeLedger: tradeLedger,
            trapLogs: trapLogs,
            recentRuntimeLogs: Array(entries.prefix(250)),
            errorLogs: Array(errorAndCriticalEntries.prefix(100)),
            crashLogs: Array(crashLogs.prefix(50))
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let rawData = try? encoder.encode(bundle),
              let rawString = String(data: rawData, encoding: .utf8)
        else { return nil }

        let scrubbed = SecretRedactor.redact(rawString)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Confluence_Antigravity_Diagnostics.json")
        try? Data(scrubbed.utf8).write(to: url, options: .atomic)
        return url
    }
}
