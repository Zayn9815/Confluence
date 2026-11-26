import Foundation
import SignalEngine

public struct ManualTradeLevelSuggestion: Codable, Sendable, Equatable, Identifiable {
    public var id: String { journalEntryId }
    public let journalEntryId: String
    public let symbol: String
    public let suggestedOutcome: JournalTradeOutcome
    public let suggestedExitPrice: Double
    public let suggestedRMultiple: Double
    public let message: String

    public init(
        journalEntryId: String,
        symbol: String,
        suggestedOutcome: JournalTradeOutcome,
        suggestedExitPrice: Double,
        suggestedRMultiple: Double,
        message: String
    ) {
        self.journalEntryId = journalEntryId
        self.symbol = symbol
        self.suggestedOutcome = suggestedOutcome
        self.suggestedExitPrice = suggestedExitPrice
        self.suggestedRMultiple = suggestedRMultiple
        self.message = message
    }
}

/// Deterministic helper for legacy journal outcome derivation and manual level notifications.
public enum TradeMonitor {
    /// Derives a consistent `JournalTradeOutcome` whenever an `exitPrice` is supplied while outcome is `.open`.
    public static func deriveJournalOutcome(
        direction: TradeDirection,
        entryPrice: Double,
        exitPrice: Double?,
        stopLoss: Double,
        currentOutcome: JournalTradeOutcome
    ) -> JournalTradeOutcome {
        guard let exit = exitPrice, exit.isFinite, exit > 0 else {
            return currentOutcome
        }
        guard currentOutcome == .open else {
            return currentOutcome
        }
        let risk = abs(entryPrice - stopLoss)
        let pnl = (direction == .long) ? (exit - entryPrice) : (entryPrice - exit)
        let breakevenTolerance = max(risk * 0.05, entryPrice * 0.0002)
        if abs(pnl) <= breakevenTolerance {
            return .breakeven
        }
        return pnl > 0 ? .win : .loss
    }

    /// Evaluates open manual journal entries against a live price quote without auto-closing them.
    public static func evaluateManualJournalAlerts(
        entries: [JournalEntrySnapshot],
        quote: LivePriceQuote,
        dismissedIds: Set<String>
    ) -> [ManualTradeLevelSuggestion] {
        var alerts: [ManualTradeLevelSuggestion] = []
        for entry in entries where entry.symbol == quote.symbol && entry.outcome == .open && !dismissedIds.contains(entry.id) {
            let entryPrice = entry.actualFillPrice ?? entry.plannedEntry
            let risk = max(abs(entryPrice - entry.stopLoss), 1e-9)

            let slHit = (entry.direction == .long) ? (quote.price <= entry.stopLoss) : (quote.price >= entry.stopLoss)
            if slHit {
                alerts.append(ManualTradeLevelSuggestion(
                    journalEntryId: entry.id,
                    symbol: entry.symbol,
                    suggestedOutcome: .loss,
                    suggestedExitPrice: entry.stopLoss,
                    suggestedRMultiple: -1.0,
                    message: "\(entry.symbol) touched Stop loss"
                ))
                continue
            }

            if let t2 = entry.tp2 {
                let t2Hit = (entry.direction == .long) ? (quote.price >= t2) : (quote.price <= t2)
                if t2Hit {
                    let r = abs(t2 - entryPrice) / risk
                    alerts.append(ManualTradeLevelSuggestion(
                        journalEntryId: entry.id,
                        symbol: entry.symbol,
                        suggestedOutcome: .win,
                        suggestedExitPrice: t2,
                        suggestedRMultiple: r,
                        message: "\(entry.symbol) reached Target 2"
                    ))
                    continue
                }
            }

            let t1Hit = (entry.direction == .long) ? (quote.price >= entry.tp1) : (quote.price <= entry.tp1)
            if t1Hit {
                let r = abs(entry.tp1 - entryPrice) / risk
                alerts.append(ManualTradeLevelSuggestion(
                    journalEntryId: entry.id,
                    symbol: entry.symbol,
                    suggestedOutcome: .win,
                    suggestedExitPrice: entry.tp1,
                    suggestedRMultiple: r,
                    message: "\(entry.symbol) reached Target 1"
                ))
            }
        }
        return alerts
    }
}
