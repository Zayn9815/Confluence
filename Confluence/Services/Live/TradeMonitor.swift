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

public struct DemoPositionCloseEvent: Sendable, Equatable {
    public let position: DemoPosition
    public let title: String
    public let body: String
}

/// Deterministic trade reconciliation monitor for both Demo Wallet positions and manual Journal entries.
/// - Demo positions reconcile strictly using `DemoWalletEngine` (pessimistic fill-bar SL-only & same-bar SL-first rules)
///   and write exact trigger levels (`Stop loss`, `Target 1`, `Target 2`) as exit price.
/// - Manual Journal entries NEVER auto-close; instead, level hits produce Apply/Dismiss suggestions.
public enum TradeMonitor {
    /// Derives a consistent `JournalTradeOutcome` whenever the user enters an `exitPrice` while outcome is still `.open`,
    /// eliminating the impossible "OPEN + Exit + R" state in `JournalEntryEditorSheet`.
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

    /// Reconciles active demo wallet positions for `symbol` against subsequent closed candles.
    public static func reconcileDemoWallet(
        wallet: DemoWallet,
        symbol: String,
        closedCandles: [Candle]
    ) -> (wallet: DemoWallet, closedEvents: [DemoPositionCloseEvent]) {
        let sortedClosed = closedCandles
            .filter(\.isClosed)
            .sorted { $0.openTimeEpochSeconds < $1.openTimeEpochSeconds }
        guard !sortedClosed.isEmpty else { return (wallet, []) }

        var current = wallet
        var events: [DemoPositionCloseEvent] = []
        let activeIds = current.positions
            .filter { $0.symbol == symbol && $0.status.isActive }
            .map(\.id)

        for posId in activeIds {
            guard let posSnapshot = current.positions.first(where: { $0.id == posId }) else { continue }
            let relevantBars = sortedClosed.filter { $0.closeTimeEpochSeconds >= posSnapshot.createdAtEpochSeconds }
            for bar in relevantBars {
                let beforeStatus = current.positions.first(where: { $0.id == posId })?.status
                let step = DemoWalletEngine.evaluateClosedBar(wallet: current, positionId: posId, bar: bar)
                current = step.wallet
                if let updatedPos = step.position,
                   beforeStatus?.isActive == true,
                   updatedPos.status.isClosed {
                    events.append(makeCloseEvent(for: updatedPos))
                    break
                }
            }
        }
        return (current, events)
    }

    /// Reconciles active demo wallet positions against a live price tick.
    public static func reconcileDemoWalletOnTick(
        wallet: DemoWallet,
        quote: LivePriceQuote
    ) -> (wallet: DemoWallet, closedEvents: [DemoPositionCloseEvent]) {
        var current = wallet
        var events: [DemoPositionCloseEvent] = []
        let activeIds = current.positions
            .filter { $0.symbol == quote.symbol && $0.status.isActive }
            .map(\.id)

        for posId in activeIds {
            let beforeStatus = current.positions.first(where: { $0.id == posId })?.status
            let step = DemoWalletEngine.evaluateLiveTick(
                wallet: current,
                positionId: posId,
                tickPrice: quote.price,
                tickEpochSeconds: quote.asOfEpochSeconds
            )
            current = step.wallet
            if let updatedPos = step.position,
               beforeStatus?.isActive == true,
               updatedPos.status.isClosed {
                events.append(makeCloseEvent(for: updatedPos))
            }
        }
        return (current, events)
    }

    /// Evaluates open manual journal entries against a live price quote without auto-closing them.
    /// Returns Apply/Dismiss suggestions when live price reaches Stop loss or Target 1/Target 2.
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

    private static func makeCloseEvent(for pos: DemoPosition) -> DemoPositionCloseEvent {
        let pnlSign = pos.realizedPnLUSD >= 0 ? "+" : ""
        let pnlText = "\(pnlSign)$\(String(format: "%.2f", pos.realizedPnLUSD))"
        let reason: String
        switch pos.status {
        case .closedTarget1: reason = "Target 1 reached"
        case .closedTarget2: reason = "Target 2 reached"
        case .closedStopLoss: reason = "Stop loss hit"
        case .closedManual: reason = "Closed manually"
        case .expired: reason = "Limit expired"
        case .cancelled: reason = "Order cancelled"
        case .pendingLimit, .open: reason = "Updated"
        }
        let exitStr = pos.exitPrice.map { String(format: "%.5g", $0) } ?? "—"
        return DemoPositionCloseEvent(
            position: pos,
            title: "Demo \(pos.symbol): \(reason)",
            body: "Exit \(exitStr) · \(pnlText) (\(String(format: "%+.2f", pos.rMultiple))R)"
        )
    }
}
