import SwiftUI
import SignalEngine

/// Editor sheet for logging or updating a personal trade in the Trade Journal.
public struct JournalEntryEditorSheet: View {
    public let initialEntry: JournalEntrySnapshot
    public let isExisting: Bool
    @Bindable public var coordinator: MarketScannerCoordinator
    public let palette: ConfluencePalette

    @Environment(\.dismiss) private var dismiss

    @State private var actualFillText: String
    @State private var exitPriceText: String
    @State private var positionSizeText: String
    @State private var outcome: JournalTradeOutcome
    @State private var manualRText: String
    @State private var tagsText: String
    @State private var notes: String

    public init(
        entry: JournalEntrySnapshot,
        isExisting: Bool,
        coordinator: MarketScannerCoordinator,
        palette: ConfluencePalette
    ) {
        self.initialEntry = entry
        self.isExisting = isExisting
        self.coordinator = coordinator
        self.palette = palette

        let dec = PriceFormatHelper.decimals(for: entry.symbol, marketClass: entry.marketClass, referencePrice: entry.plannedEntry)
        _actualFillText = State(initialValue: entry.actualFillPrice.map { PriceFormatHelper.format($0, decimals: dec) } ?? PriceFormatHelper.format(entry.plannedEntry, decimals: dec))
        _exitPriceText = State(initialValue: entry.exitPrice.map { PriceFormatHelper.format($0, decimals: dec) } ?? "")
        _positionSizeText = State(initialValue: entry.positionSizeText ?? "")
        _outcome = State(initialValue: entry.outcome)
        _manualRText = State(initialValue: entry.actualRMultiple.map { String(format: "%.2f", $0) } ?? "")
        _tagsText = State(initialValue: entry.tags.joined(separator: ", "))
        _notes = State(initialValue: entry.notes)
    }

    private var autoComputedR: Double? {
        guard let exit = Double(exitPriceText) else { return nil }
        let entry = Double(actualFillText) ?? initialEntry.plannedEntry
        let risk = abs(entry - initialEntry.stopLoss)
        guard risk > 1e-12 else { return nil }
        let pnl = (initialEntry.direction == .long) ? (exit - entry) : (entry - exit)
        return pnl / risk
    }

    public var body: some View {
        let dec = PriceFormatHelper.decimals(for: initialEntry.symbol, marketClass: initialEntry.marketClass, referencePrice: initialEntry.plannedEntry)

        NavigationStack {
            Form {
                Section("Setup Summary") {
                    HStack {
                        Text("\(initialEntry.symbol) · \(initialEntry.timeframe.displayLabel)")
                            .fontWeight(.bold)
                        Spacer()
                        Text(initialEntry.direction.rawValue.uppercased())
                            .fontWeight(.bold)
                            .foregroundStyle(palette.color(for: initialEntry.direction))
                    }
                    HStack {
                        Text("Planned Entry / SL / TP1")
                            .font(.caption)
                            .foregroundStyle(palette.secondaryInk)
                        Spacer()
                        Text("\(PriceFormatHelper.format(initialEntry.plannedEntry, decimals: dec)) / \(PriceFormatHelper.format(initialEntry.stopLoss, decimals: dec)) / \(PriceFormatHelper.format(initialEntry.tp1, decimals: dec))")
                            .font(.caption.monospacedDigit())
                    }
                    if let sysR = initialEntry.systemRMultiple {
                        HStack {
                            Text("System Passive Outcome")
                                .font(.caption)
                                .foregroundStyle(palette.secondaryInk)
                            Spacer()
                            Text(String(format: "%+.2fR", sysR))
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(sysR >= 0 ? palette.longEmerald : palette.shortCrimson)
                        }
                    }
                }

                Section("Execution & Outcome") {
                    Picker("Trade Outcome", selection: $outcome) {
                        ForEach(JournalTradeOutcome.allCases) { o in
                            Text(o.rawValue).tag(o)
                        }
                    }

                    HStack {
                        Text("Actual Fill Price")
                        Spacer()
                        TextField("Fill price", text: $actualFillText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }

                    HStack {
                        Text("Exit Price (Optional)")
                        Spacer()
                        TextField("Closed price", text: $exitPriceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }

                    HStack {
                        Text("Position Size")
                        Spacer()
                        TextField("e.g. 0.50 lots", text: $positionSizeText)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text("Realized R-Multiple")
                        Spacer()
                        TextField(autoComputedR.map { String(format: "Auto: %+.2f", $0) } ?? "e.g. +1.8", text: $manualRText)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }
                }

                Section("Tags & Review Notes") {
                    TextField("Tags (comma separated, e.g. A+, London, FOMO)", text: $tagsText)
                        .font(.caption)
                    TextEditor(text: $notes)
                        .frame(minHeight: 90)
                        .font(.caption)
                }

                if isExisting {
                    Section {
                        Button(role: .destructive) {
                            coordinator.deleteJournalEntry(id: initialEntry.id)
                            dismiss()
                        } label: {
                            Label("Delete Journal Entry", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(isExisting ? "Edit Journal Entry" : "Mark Trade as Taken")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveEntry()
                        dismiss()
                    }
                }
            }
        }
    }

    private func saveEntry() {
        let parsedFill = Double(actualFillText)
        let parsedExit = Double(exitPriceText)
        let parsedR = Double(manualRText) ?? autoComputedR
        let entryRef = parsedFill ?? initialEntry.plannedEntry
        let resolvedOutcome = TradeMonitor.deriveJournalOutcome(
            direction: initialEntry.direction,
            entryPrice: entryRef,
            exitPrice: parsedExit,
            stopLoss: initialEntry.stopLoss,
            currentOutcome: outcome
        )
        let parsedTags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let closedAt: Date? = (resolvedOutcome == .open) ? nil : (initialEntry.closedAt ?? Date())

        let updated = JournalEntrySnapshot(
            id: initialEntry.id,
            signalFingerprint: initialEntry.signalFingerprint,
            symbol: initialEntry.symbol,
            marketClass: initialEntry.marketClass,
            timeframe: initialEntry.timeframe,
            direction: initialEntry.direction,
            plannedEntry: initialEntry.plannedEntry,
            actualFillPrice: parsedFill,
            stopLoss: initialEntry.stopLoss,
            tp1: initialEntry.tp1,
            tp2: initialEntry.tp2,
            exitPrice: parsedExit,
            positionSizeText: positionSizeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : positionSizeText.trimmingCharacters(in: .whitespacesAndNewlines),
            outcome: resolvedOutcome,
            actualRMultiple: parsedR,
            systemRMultiple: initialEntry.systemRMultiple,
            strategyIDs: initialEntry.strategyIDs,
            tags: parsedTags,
            notes: notes,
            takenAt: initialEntry.takenAt,
            closedAt: closedAt
        )
        coordinator.saveJournalEntry(updated)
    }
}
