import SwiftUI

public struct AboutDeveloperSettingsView: View {
    let palette: ConfluencePalette

    @State private var showLicensesSheet = false

    private let developerProfileURL = URL(string: "https://github.com/Zayn9815")!
    private let projectRepositoryURL = URL(string: "https://github.com/Zayn9815/Confluence")!

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.5.0"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "5"
    }

    public var body: some View {
        Form {
            Section("Application") {
                HStack {
                    Text("App Name")
                    Spacer()
                    Text("Confluence").foregroundStyle(palette.secondaryInk)
                }
                HStack {
                    Text("Subtitle")
                    Spacer()
                    Text("Confluence Terminal").foregroundStyle(palette.secondaryInk)
                }
                HStack {
                    Text("Bundle ID")
                    Spacer()
                    Text("com.bilal.confluence")
                        .font(.caption.monospaced())
                        .foregroundStyle(palette.secondaryInk)
                }
                HStack {
                    Text("Version")
                    Spacer()
                    Text("\(appVersion) (\(appBuild))")
                        .monospacedDigit()
                        .foregroundStyle(palette.secondaryInk)
                }
            }

            Section("Developer") {
                HStack {
                    Text("Developer : Bilal")
                        .fontWeight(.semibold)
                        .foregroundStyle(palette.primaryInk)
                    Spacer()
                }

                Link(destination: developerProfileURL) {
                    HStack {
                        Label("GitHub Profile (@Zayn9815)", systemImage: "person.crop.circle")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(palette.tertiaryInk)
                    }
                }

                Link(destination: projectRepositoryURL) {
                    HStack {
                        Label("Project Repository (Confluence)", systemImage: "chevron.left.forwardslash.chevron.right")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(palette.tertiaryInk)
                    }
                }
            }

            Section("Attribution & Legal") {
                Button {
                    showLicensesSheet = true
                } label: {
                    Label("Open-Source Licenses & Attribution", systemImage: "doc.plaintext")
                }

                Text("Confluence is strictly a read-only analytical terminal with automatic Signal Journal tracking. It never executes real orders, connects brokerage accounts, or stores trading private keys.")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryInk)
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.canvas)
        .navigationTitle("About & Developer")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLicensesSheet) {
            OpenSourceAttributionSheet(palette: palette)
        }
    }
}

private struct OpenSourceAttributionSheet: View {
    let palette: ConfluencePalette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Interactive Charting Engines") {
                    licenseRow("LalanaChami/CandleKit", "MIT License — Native SwiftUI Canvas candlestick rendering engine")
                    licenseRow("ChartsOrg/Charts (DGCharts)", "Apache License 2.0 — Native CoreGraphics candlestick engine")
                    licenseRow("TradingView Advanced Chart", "Optional embedded TradingView web widget and persistent TradingView web view")
                }
                Section("SwiftUI Packages (MIT)") {
                    licenseRow("EmergeTools/Pow", "MIT License — Restrained arrival micro-interactions")
                    licenseRow("exyte/PopupView", "MIT License — Translucent floating live alert banners")
                }
                Section("Public Data & Research Attribution") {
                    licenseRow("CFTC Commitments of Traders", "Public Domain Socrata JSON (publicreporting.cftc.gov)")
                    licenseRow("Behavioral Finance Foundations", "Carol Osler (Stop-Loss Clustering), Barber & Odean (Attention FOMO), Kahneman & Tversky / Shefrin & Statman (Disposition Effect)")
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.canvas)
            .navigationTitle("Licenses & Attribution")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func licenseRow(_ title: String, _ desc: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(desc).font(.caption).foregroundStyle(palette.secondaryInk)
        }
    }
}
