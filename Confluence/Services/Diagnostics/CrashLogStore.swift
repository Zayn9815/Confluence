import Foundation
import MetricKit
import Darwin

// MARK: - Async-Signal-Safe POSIX Crash Breadcrumb State

private nonisolated(unsafe) var confluencePOSIXBreadcrumbPath: UnsafeMutablePointer<CChar>? = nil
private nonisolated(unsafe) var confluenceExceptionBreadcrumbPath: String? = nil

/// Strictly async-signal-safe POSIX signal handler (ZERO Swift allocations or Foundation calls).
private func confluencePOSIXSignalHandler(_ sig: Int32) {
    if let path = confluencePOSIXBreadcrumbPath {
        let fd = Darwin.creat(path, 0o600)
        if fd >= 0 {
            let payload: StaticString
            switch sig {
            case SIGABRT: payload = "POSIX_SIGNAL:SIGABRT\n"
            case SIGSEGV: payload = "POSIX_SIGNAL:SIGSEGV\n"
            case SIGBUS:  payload = "POSIX_SIGNAL:SIGBUS\n"
            case SIGILL:  payload = "POSIX_SIGNAL:SIGILL\n"
            case SIGTRAP: payload = "POSIX_SIGNAL:SIGTRAP\n"
            default:      payload = "POSIX_SIGNAL:UNKNOWN\n"
            }
            payload.withUTF8Buffer { buf in
                if let base = buf.baseAddress {
                    _ = Darwin.write(fd, base, buf.count)
                }
            }
            _ = Darwin.close(fd)
        }
    }
    Darwin.signal(sig, SIG_DFL)
    Darwin.raise(sig)
}

private func confluenceUncaughtExceptionHandler(_ exception: NSException) {
    guard let path = confluenceExceptionBreadcrumbPath else { return }
    let name = exception.name.rawValue
    let reason = exception.reason ?? "No reason provided"
    let stack = exception.callStackSymbols.prefix(40).joined(separator: "\n")
    let raw = """
    EXCEPTION_NAME:\(name)
    REASON:\(reason)
    STACK:
    \(stack)
    """
    let scrubbed = SecretRedactor.redact(raw)
    try? Data(scrubbed.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
}

// MARK: - MetricKit Subscriber Bridge (Swift 6 Strict Concurrency Safe)

private final class MetricKitSubscriberBridge: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    private let onPayloads: @Sendable ([Data]) -> Void

    init(onPayloads: @escaping @Sendable ([Data]) -> Void) {
        self.onPayloads = onPayloads
        super.init()
    }

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let jsonPayloads = payloads.map { $0.jsonRepresentation() }
        if !jsonPayloads.isEmpty {
            onPayloads(jsonPayloads)
        }
    }
}

// MARK: - Native Crash Log Store

@MainActor
@Observable
public final class CrashLogStore {
    public static let posixBreadcrumbFilename = "confluence_posix_crash.txt"
    public static let exceptionBreadcrumbFilename = "confluence_exception_crash.txt"

    private let store: ConfluenceDataStore
    private var metricKitBridge: MetricKitSubscriberBridge?
    private var isMonitoring: Bool = false

    public private(set) var entries: [CrashLogSnapshot] = []

    public init(store: ConfluenceDataStore) {
        self.store = store
        self.entries = store.fetchCrashLogs()
    }

    public var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.3.0"
    }

    public var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "4"
    }

    /// Starts native MetricKit diagnostic ingestion, imports any pending crash breadcrumbs from
    /// a previous crash, and arms NSSetUncaughtExceptionHandler + async-signal-safe POSIX handlers.
    /// Automatically skips global handler registration when launched as an XCTest host.
    public func startMonitoring() {
        guard !isMonitoring else { return }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }
        isMonitoring = true

        // 1. Import any crash breadcrumbs written during a previous abnormal termination
        importPendingCrashBreadcrumbs()

        // 2. Register MetricKit diagnostic subscriber & ingest past diagnostic payloads (physical devices)
        #if !targetEnvironment(simulator)
        let bridge = MetricKitSubscriberBridge { [weak self] jsonPayloads in
            Task { @MainActor [weak self] in
                guard let self else { return }
                for data in jsonPayloads {
                    self.ingestMetricKitJSON(data)
                }
            }
        }
        self.metricKitBridge = bridge
        MXMetricManager.shared.add(bridge)

        let pastPayloads = MXMetricManager.shared.pastDiagnosticPayloads
        for payload in pastPayloads {
            ingestMetricKitJSON(payload.jsonRepresentation())
        }

        // 3. Arm exception & async-signal-safe POSIX crash breadcrumb writers
        installNativeCrashBreadcrumbs()
        #endif
    }

    public func reload() {
        entries = store.fetchCrashLogs()
    }

    public func clear() {
        store.clearCrashLogs()
        entries = []
    }

    @discardableResult
    public func recordCrash(_ snapshot: CrashLogSnapshot) -> Bool {
        let scrubbed = CrashLogSnapshot(
            id: snapshot.id,
            timestamp: snapshot.timestamp,
            source: snapshot.source,
            appVersion: snapshot.appVersion,
            appBuild: snapshot.appBuild,
            crashType: SecretRedactor.redact(snapshot.crashType),
            summary: SecretRedactor.redact(snapshot.summary),
            stackTrace: SecretRedactor.redact(snapshot.stackTrace)
        )
        let saved = store.saveCrashLog(scrubbed)
        if saved {
            reload()
        }
        return saved
    }

    @discardableResult
    public func ingestMetricKitJSON(_ data: Data) -> Int {
        let parsed = Self.parseMetricKitDiagnosticJSON(
            data,
            fallbackVersion: appVersion,
            fallbackBuild: appBuild
        )
        var added = 0
        for item in parsed {
            if recordCrash(item) {
                added += 1
            }
        }
        return added
    }

    /// Imports any pending uncaught-exception or POSIX fatal-signal breadcrumbs from `directory`
    /// (defaults to Application Support), scrubs them, persists to SwiftData, and deletes the temp breadcrumb files.
    @discardableResult
    public func importPendingCrashBreadcrumbs(from directory: URL? = nil) -> Int {
        guard let dir = directory ?? Self.defaultBreadcrumbDirectory() else { return 0 }
        let fm = FileManager.default
        var imported = 0

        let exceptionURL = dir.appendingPathComponent(Self.exceptionBreadcrumbFilename)
        if fm.fileExists(atPath: exceptionURL.path),
           let rawText = try? String(contentsOf: exceptionURL, encoding: .utf8),
           !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lines = rawText.components(separatedBy: .newlines)
            let exName = lines.first(where: { $0.hasPrefix("EXCEPTION_NAME:") })?
                .replacingOccurrences(of: "EXCEPTION_NAME:", with: "") ?? "NSException"
            let reason = lines.first(where: { $0.hasPrefix("REASON:") })?
                .replacingOccurrences(of: "REASON:", with: "") ?? "Uncaught Objective-C/Swift exception"
            let stackStart = lines.firstIndex(where: { $0 == "STACK:" }).map { $0 + 1 } ?? 0
            let stack = lines.dropFirst(stackStart).joined(separator: "\n")
            let modDate = (try? fm.attributesOfItem(atPath: exceptionURL.path)[.modificationDate] as? Date) ?? Date()

            let snap = CrashLogSnapshot(
                id: "exc-\(Int(modDate.timeIntervalSince1970))-\(exName)",
                timestamp: modDate,
                source: .uncaughtException,
                appVersion: appVersion,
                appBuild: appBuild,
                crashType: exName,
                summary: reason,
                stackTrace: stack.isEmpty ? rawText : stack
            )
            if recordCrash(snap) {
                imported += 1
            }
            try? fm.removeItem(at: exceptionURL)
        }

        let posixURL = dir.appendingPathComponent(Self.posixBreadcrumbFilename)
        if fm.fileExists(atPath: posixURL.path),
           let rawText = try? String(contentsOf: posixURL, encoding: .utf8),
           !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let sigName = rawText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "POSIX_SIGNAL:", with: "")
            let modDate = (try? fm.attributesOfItem(atPath: posixURL.path)[.modificationDate] as? Date) ?? Date()

            let snap = CrashLogSnapshot(
                id: "posix-\(Int(modDate.timeIntervalSince1970))-\(sigName)",
                timestamp: modDate,
                source: .posixFatalSignal,
                appVersion: appVersion,
                appBuild: appBuild,
                crashType: sigName.isEmpty ? "FATAL_SIGNAL" : sigName,
                summary: "Process terminated by fatal POSIX signal \(sigName.isEmpty ? "UNKNOWN" : sigName). Full symbolicated report may arrive via Apple MetricKit.",
                stackTrace: "Captured via async-signal-safe POSIX breadcrumb at \(ISO8601DateFormatter().string(from: modDate)).\nSignal: \(sigName)"
            )
            if recordCrash(snap) {
                imported += 1
            }
            try? fm.removeItem(at: posixURL)
        }

        return imported
    }

    private func installNativeCrashBreadcrumbs() {
        guard let dir = Self.defaultBreadcrumbDirectory() else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let exceptionPath = dir.appendingPathComponent(Self.exceptionBreadcrumbFilename).path
        confluenceExceptionBreadcrumbPath = exceptionPath
        NSSetUncaughtExceptionHandler(confluenceUncaughtExceptionHandler)

        let posixPath = dir.appendingPathComponent(Self.posixBreadcrumbFilename).path
        if let oldPtr = confluencePOSIXBreadcrumbPath {
            free(oldPtr)
        }
        confluencePOSIXBreadcrumbPath = strdup(posixPath)

        let signals: [Int32] = [SIGABRT, SIGSEGV, SIGBUS, SIGILL]
        for sig in signals {
            var action = sigaction()
            action.__sigaction_u.__sa_handler = confluencePOSIXSignalHandler
            sigemptyset(&action.sa_mask)
            action.sa_flags = SA_RESETHAND
            sigaction(sig, &action, nil)
        }
    }

    private static func defaultBreadcrumbDirectory() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }

    // MARK: - Pure Testable MetricKit Diagnostic JSON Parser

    public nonisolated static func parseMetricKitDiagnosticJSON(
        _ data: Data,
        fallbackVersion: String = "1.3.0",
        fallbackBuild: String = "4"
    ) -> [CrashLogSnapshot] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        let iso = ISO8601DateFormatter()
        let timeStampStr = (root["timeStampEnd"] ?? root["timeStampBegin"]) as? String
        let payloadDate = timeStampStr.flatMap { iso.date(from: $0) } ?? Date()

        var results: [CrashLogSnapshot] = []

        if let crashes = root["crashDiagnostics"] as? [[String: Any]] {
            for (idx, crash) in crashes.enumerated() {
                let meta = crash["diagnosticMetaData"] as? [String: Any]
                let version = (meta?["appVersion"] as? String) ?? (crash["version"] as? String) ?? fallbackVersion
                let build = (meta?["appBuildVersion"] as? String) ?? fallbackBuild
                let signalNum = meta?["signal"] as? Int
                let exceptionType = meta?["exceptionType"] as? Int
                let terminationReason = (meta?["terminationReason"] as? String)
                    ?? (crash["terminationReason"] as? String)
                    ?? "MetricKit Crash Diagnostic"

                let crashType: String
                if let sig = signalNum {
                    crashType = "Signal \(sig)" + (exceptionType.map { " / Exc \($0)" } ?? "")
                } else if let ex = exceptionType {
                    crashType = "Exception \(ex)"
                } else {
                    crashType = "Crash Diagnostic"
                }

                let stackLines = extractCallStackSummary(from: crash["callStackTree"])
                let stackTrace = stackLines.isEmpty ? "No call stack frames included in payload." : stackLines.joined(separator: "\n")
                let id = "mx-crash-\(Int(payloadDate.timeIntervalSince1970))-\(idx)-\(crashType.replacingOccurrences(of: " ", with: "_"))"

                results.append(
                    CrashLogSnapshot(
                        id: id,
                        timestamp: payloadDate,
                        source: .metricKitCrash,
                        appVersion: version,
                        appBuild: build,
                        crashType: crashType,
                        summary: SecretRedactor.redact(terminationReason),
                        stackTrace: SecretRedactor.redact(stackTrace)
                    )
                )
            }
        }

        if let hangs = root["hangDiagnostics"] as? [[String: Any]] {
            for (idx, hang) in hangs.enumerated() {
                let meta = hang["diagnosticMetaData"] as? [String: Any]
                let version = (meta?["appVersion"] as? String) ?? (hang["version"] as? String) ?? fallbackVersion
                let build = (meta?["appBuildVersion"] as? String) ?? fallbackBuild
                let duration = (meta?["hangDuration"] as? String) ?? "Main-thread hang"
                let stackLines = extractCallStackSummary(from: hang["callStackTree"])
                let stackTrace = stackLines.isEmpty ? "No hang call stack frames included." : stackLines.joined(separator: "\n")
                let id = "mx-hang-\(Int(payloadDate.timeIntervalSince1970))-\(idx)"

                results.append(
                    CrashLogSnapshot(
                        id: id,
                        timestamp: payloadDate,
                        source: .metricKitHang,
                        appVersion: version,
                        appBuild: build,
                        crashType: "Main Thread Hang",
                        summary: SecretRedactor.redact("Hang duration: \(duration)"),
                        stackTrace: SecretRedactor.redact(stackTrace)
                    )
                )
            }
        }

        return results
    }

    private nonisolated static func extractCallStackSummary(from rawTree: Any?) -> [String] {
        guard let tree = rawTree as? [String: Any],
              let callStacks = tree["callStacks"] as? [[String: Any]]
        else { return [] }

        var lines: [String] = []
        for (stackIdx, stack) in callStacks.prefix(3).enumerated() {
            let attributed = (stack["threadAttributed"] as? Bool) ?? false
            lines.append("Thread #\(stackIdx)\(attributed ? " [CRASHED]" : ""):")
            if let rootFrames = stack["callStackRootFrames"] as? [[String: Any]] {
                flattenFrames(rootFrames, depth: 0, into: &lines, maxFrames: 25)
            }
        }
        return lines
    }

    private nonisolated static func flattenFrames(
        _ frames: [[String: Any]],
        depth: Int,
        into out: inout [String],
        maxFrames: Int
    ) {
        guard depth < maxFrames else { return }
        for frame in frames {
            if out.count >= maxFrames * 3 { return }
            let binary = (frame["binaryName"] as? String) ?? "unknown"
            let offset = (frame["offsetIntoBinaryTextSegment"] as? Int).map { "+0x\(String($0, radix: 16))" } ?? ""
            let addr = (frame["address"] as? Int).map { "0x\(String($0, radix: 16))" } ?? ""
            out.append("  #\(depth) \(binary) \(offset) \(addr)".trimmingCharacters(in: .whitespaces))
            if let sub = frame["subFrames"] as? [[String: Any]] {
                flattenFrames(sub, depth: depth + 1, into: &out, maxFrames: maxFrames)
            }
        }
    }
}
