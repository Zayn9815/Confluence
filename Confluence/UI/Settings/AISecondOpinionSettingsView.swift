import SwiftUI
import SignalEngine

public struct AISecondOpinionSettingsView: View {
    @Bindable var coordinator: MarketScannerCoordinator
    let palette: ConfluencePalette

    @State private var geminiKeyInput = ""
    @State private var hasGeminiKey = false

    public var body: some View {
        Form {
            Section {
                Toggle("Enable Gemini AI Judge", isOn: $coordinator.settings.payload.geminiEnabled)

                Picker("Gemini Model", selection: $coordinator.settings.payload.geminiModel) {
                    ForEach(GeminiModelOption.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
            } header: {
                Text("AI Second-Opinion Filter")
            } footer: {
                Text("Confluence works 100% natively with AI OFF. When enabled, Gemini reviews new Strong Signals & Trap Alerts using strict JSON schema, but can NEVER override deterministic SL/TP levels, risk limits, or Crisis suppression.")
            }

            Section("Encrypted Keychain API Key") {
                HStack {
                    SecureField(
                        hasGeminiKey ? "Gemini Key Encrypted in Keychain" : "Enter Gemini API Key",
                        text: $geminiKeyInput
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    Button("Save") {
                        Task {
                            try? await KeychainStore.shared.save(geminiKeyInput, for: .geminiAPIKey)
                            geminiKeyInput = ""
                            hasGeminiKey = await KeychainStore.shared.hasValue(for: .geminiAPIKey)
                        }
                    }
                    .disabled(geminiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if hasGeminiKey {
                    Button(role: .destructive) {
                        Task {
                            await KeychainStore.shared.delete(.geminiAPIKey)
                            hasGeminiKey = await KeychainStore.shared.hasValue(for: .geminiAPIKey)
                        }
                    } label: {
                        Label("Remove Saved Gemini Key", systemImage: "trash")
                    }
                }
            }

            Section("Daily Usage Cap") {
                Stepper(
                    "Daily AI Call Limit: \(coordinator.settings.payload.geminiDailyCallLimit)",
                    value: $coordinator.settings.payload.geminiDailyCallLimit,
                    in: 5...100,
                    step: 5
                )

                HStack {
                    Text("Today's AI Usage")
                    Spacer()
                    Text("\(coordinator.geminiDailyCallsUsed) / \(coordinator.settings.payload.geminiDailyCallLimit)")
                        .monospacedDigit()
                        .foregroundStyle(palette.secondaryInk)
                }
            }
        }
        .navigationTitle("AI Second-Opinion")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            hasGeminiKey = await KeychainStore.shared.hasValue(for: .geminiAPIKey)
        }
    }
}
