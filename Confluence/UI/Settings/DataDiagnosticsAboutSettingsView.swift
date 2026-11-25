import SwiftUI
import UniformTypeIdentifiers
import SignalEngine

/// Settings Category 5: Data, Diagnostics & About
/// Hosts Versioned Backup & Restore, CSV exports, Diagnostics Hub, Searchable Glossary, Risk Disclosure & About.
public struct DataDiagnosticsAboutSettingsView: View {
    @Bindable var coordinator: MarketScannerCoordinator
    let palette: ConfluencePalette

    @State private var importMode: BackupImportMode = .merge
    @State private var showFileImporter = false
    @State private var backupStatusMessage: String?
    @State private var backupStatusIsError = false

    public init(coordinator: MarketScannerCoordinator, palette: ConfluencePalette) {
        self.coordinator = coordinator
        self.palette = palette
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.3.0"
    }

    public var body: some View {
        Form {
            Section {
                if let backupURL = coordinator.exportBackupArchiveURL() {
                    ShareLink(item: backupURL) {
                        Label("Export Backup Archive (JSON)", systemImage: "externaldrive.badge.plus")
                    }
                }

                Picker("Restore Mode", selection: $importMode) {
                    ForEach(BackupImportMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }

                Button {
                    showFileImporter = true
                } label: {
                    Label("Restore Backup from JSON File", systemImage: "square.and.arrow.down")
                }

                if let ledgerCSV = coordinator.exportTradeLedgerCSVURL() {
                    ShareLink(item: ledgerCSV) {
                        Label("Export Trade Ledger (CSV)", systemImage: "tablecells")
                    }
                }

                if let journalCSV = coordinator.exportJournalCSVURL() {
                    ShareLink(item: journalCSV) {
                        Label("Export Trade Journal (CSV)", systemImage: "book.pages")
                    }
                }

                if let msg = backupStatusMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(backupStatusIsError ? palette.shortCrimson : palette.longEmerald)
                }
            } header: {
                Text("Backup, Restore & CSV Exports")
            } footer: {
                Text("Backups include settings, signals, outcomes, trade ledger, and journal entries (`schemaVersion = 1`). Keychain API keys are NEVER exported, and every file passes through SecretRedactor.")
            }

            Section("Diagnostics & Logs") {
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
                            Text("\(coordinator.diagnosticLog.entries.count) logs · \(coordinator.diagnosticLog.errorOnlyCount) err · \(coordinator.crashLogStore.entries.count) crashes")
                                .font(.caption)
                                .foregroundStyle(palette.secondaryInk)
                        }
                    }
                }
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
                            .foregroundStyle(palette.macroIceBlue)
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
