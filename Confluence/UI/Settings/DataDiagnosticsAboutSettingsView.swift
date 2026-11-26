import SwiftUI
import UIKit
import UniformTypeIdentifiers
import SignalEngine

/// Settings Category 5: Data, Diagnostics & About
/// Hosts Versioned Backup & Restore (with 1-tap Clipboard JSON fallback for LiveContainer), CSV exports, Diagnostics Hub, Searchable Glossary, Risk Disclosure & About.
public struct DataDiagnosticsAboutSettingsView: View {
    @Bindable var coordinator: MarketScannerCoordinator
    let palette: ConfluencePalette

    @State private var importMode: BackupImportMode = .merge
    @State private var showFileImporter = false
    @State private var backupStatusMessage: String?
    @State private var backupStatusIsError = false
    @State private var preparedBackupURL: URL?
    @State private var preparedLedgerCSVURL: URL?
    @State private var preparedJournalCSVURL: URL?

    public init(coordinator: MarketScannerCoordinator, palette: ConfluencePalette) {
        self.coordinator = coordinator
        self.palette = palette
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.5.0"
    }

    public var body: some View {
        Form {
            Section {
                if let backupURL = preparedBackupURL {
                    ShareLink(item: backupURL) {
                        Label("Share Backup File", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button {
                        preparedBackupURL = coordinator.exportBackupArchiveURL()
                    } label: {
                        Label("Prepare Backup File", systemImage: "externaldrive.badge.plus")
                    }
                }

                Button {
                    if let json = coordinator.exportBackupJSONString() {
                        UIPasteboard.general.string = json
                        backupStatusIsError = false
                        backupStatusMessage = "Copied redacted backup JSON to clipboard (\(json.count) chars)."
                    } else {
                        backupStatusIsError = true
                        backupStatusMessage = "Could not serialize backup JSON."
                    }
                } label: {
                    Label("Copy Backup JSON to Clipboard", systemImage: "doc.on.doc")
                }

                Picker("Restore Mode", selection: $importMode) {
                    ForEach(BackupImportMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }

                Button {
                    showFileImporter = true
                } label: {
                    Label("Restore Backup From File", systemImage: "square.and.arrow.down")
                }

                Button {
                    guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !text.isEmpty
                    else {
                        backupStatusIsError = true
                        backupStatusMessage = "Clipboard is empty — copy a Confluence backup JSON first."
                        return
                    }
                    do {
                        let summary = try coordinator.importBackupArchive(from: Data(text.utf8), mode: importMode)
                        backupStatusIsError = false
                        backupStatusMessage = "Restored clipboard v\(summary.schemaVersion) backup: \(summary.signalsImported) signals, \(summary.outcomesImported) outcomes, \(summary.journalImported) journal entries."
                    } catch {
                        backupStatusIsError = true
                        backupStatusMessage = error.localizedDescription
                    }
                } label: {
                    Label("Restore Backup From Clipboard JSON", systemImage: "doc.on.clipboard")
                }

                if let ledgerCSV = preparedLedgerCSVURL {
                    ShareLink(item: ledgerCSV) {
                        Label("Share Trade Ledger (Spreadsheet)", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button {
                        preparedLedgerCSVURL = coordinator.exportTradeLedgerCSVURL()
                    } label: {
                        Label("Export Trade Ledger (Spreadsheet)", systemImage: "tablecells")
                    }
                }

                if let journalCSV = preparedJournalCSVURL {
                    ShareLink(item: journalCSV) {
                        Label("Share Signal Journal (Spreadsheet)", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button {
                        preparedJournalCSVURL = coordinator.exportJournalCSVURL()
                    } label: {
                        Label("Export Signal Journal (Spreadsheet)", systemImage: "book.pages")
                    }
                }

                if let msg = backupStatusMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(backupStatusIsError ? palette.shortCrimson : palette.longEmerald)
                }
            } header: {
                SettingsSectionHeader(SettingHelpKey.backupAndRestore.copy.label, helpKey: .backupAndRestore)
            } footer: {
                Text("Backups include settings, signals, outcomes, trade ledger, and automatic Signal Journal entries (`schemaVersion = 2`, previous v1 files remain importable). Keychain keys are NEVER exported, and every file passes through SecretRedactor.")
            }

            Section {
                NavigationLink {
                    DiagnosticsHubView(coordinator: coordinator, palette: palette)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "stethoscope")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(palette.trapAmber)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Logs, Feed Health & Trade Ledger")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(palette.primaryInk)
                            Text("\(coordinator.diagnosticLog.entries.count) logs · \(coordinator.diagnosticLog.errorOnlyCount) errors · \(coordinator.crashLogStore.entries.count) crashes")
                                .font(.caption)
                                .foregroundStyle(palette.secondaryInk)
                        }
                    }
                }
            } header: {
                SettingsSectionHeader(SettingHelpKey.diagnosticsAndLogs.copy.label, helpKey: .diagnosticsAndLogs)
            }

            Section("Learning, Legal & About") {
                NavigationLink {
                    GlossaryView(palette: palette)
                } label: {
                    Label("Quant & Trading Glossary (\(GlossaryView.allTerms.count) Terms)", systemImage: "book.closed")
                }

                NavigationLink {
                    RiskDisclosureView(palette: palette)
                } label: {
                    Label("Risk Disclosure & Methodology", systemImage: "exclamationmark.shield")
                }

                Button {
                    coordinator.settings.payload.hasCompletedOnboarding = false
                } label: {
                    Label("Replay First-Run Onboarding", systemImage: "arrow.counterclockwise")
                }

                NavigationLink {
                    AboutDeveloperSettingsView(palette: palette)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(palette.champagneGold)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("About Confluence & Developer")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(palette.primaryInk)
                            Text("v\(appVersion) · Developer : Bilal")
                                .font(.caption)
                                .foregroundStyle(palette.secondaryInk)
                        }
                    }
                }
            }
        }
        .navigationTitle("Data, Diagnostics & About")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    let summary = try coordinator.importBackupArchive(from: data, mode: importMode)
                    backupStatusIsError = false
                    backupStatusMessage = "Restored v\(summary.schemaVersion) backup: \(summary.signalsImported) signals, \(summary.outcomesImported) outcomes, \(summary.journalImported) journal entries."
                } catch {
                    backupStatusIsError = true
                    backupStatusMessage = error.localizedDescription
                }
            case .failure(let err):
                backupStatusIsError = true
                backupStatusMessage = err.localizedDescription
            }
        }
    }
}
