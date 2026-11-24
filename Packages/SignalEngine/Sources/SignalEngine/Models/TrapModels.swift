import Foundation

public enum TrapDirection: String, Codable, Sendable, Equatable {
    /// Retail trapped LONG (bull trap) -> institutional play is SHORT.
    case bullTrap = "BULL TRAP"
    /// Retail trapped SHORT (bear trap) -> institutional play is LONG.
    case bearTrap = "BEAR TRAP"

    public var institutionalDirection: TradeDirection {
        switch self {
        case .bullTrap: return .short
        case .bearTrap: return .long
        }
    }

    public var trappedRetailDirection: TradeDirection {
        switch self {
        case .bullTrap: return .long
        case .bearTrap: return .short
        }
    }
}

public enum TrapLifecycleState: String, Codable, Sendable, Equatable {
    /// Formed on the current newly-closed trigger bar.
    case trigger
    /// Confirmed active trap level; horizontal zone extends forward until price returns or invalidates.
    case active
    /// Price retested the trap level without closing through it (disposition breakeven wall activated).
    case returned
    /// Invalidated ONLY when a subsequent closed candle CLOSES strictly through the trap level (or lifetime expires).
    case invalid
}

public enum TrapTriggerKind: String, Codable, Sendable, Equatable {
    case oslerRoundNumberSweep = "Osler Round-Number Sweep"
    case liquiditySwingSweep = "Liquidity Swing Sweep"
    case attentionFOMOSpike = "Attention FOMO Spike"
    case postNewsWhipsawTrap = "News Whipsaw Trap"
    case shortSqueezeTrap = "Short Squeeze"
    case longSqueezeTrap = "Long Squeeze"
}

public struct BehavioralTrap: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let symbol: String
    public let direction: TrapDirection
    public let triggerKind: TrapTriggerKind
    public let level: Double
    public let extremePrice: Double
    public let triggerBarIndex: Int
    public let triggerEpochSeconds: TimeInterval
    public let state: TrapLifecycleState
    public let returnedAtBarIndex: Int?
    public let invalidatedAtBarIndex: Int?
    public let expiresAtEpochSeconds: TimeInterval
    public let pierceATRMultiple: Double
    public let rvolMultiple: Double?
    public let detail: String

    public init(
        id: String,
        symbol: String,
        direction: TrapDirection,
        triggerKind: TrapTriggerKind,
        level: Double,
        extremePrice: Double,
        triggerBarIndex: Int,
        triggerEpochSeconds: TimeInterval,
        state: TrapLifecycleState,
        returnedAtBarIndex: Int? = nil,
        invalidatedAtBarIndex: Int? = nil,
        expiresAtEpochSeconds: TimeInterval,
        pierceATRMultiple: Double,
        rvolMultiple: Double? = nil,
        detail: String
    ) {
        self.id = id
        self.symbol = symbol
        self.direction = direction
        self.triggerKind = triggerKind
        self.level = level
        self.extremePrice = extremePrice
        self.triggerBarIndex = triggerBarIndex
        self.triggerEpochSeconds = triggerEpochSeconds
        self.state = state
        self.returnedAtBarIndex = returnedAtBarIndex
        self.invalidatedAtBarIndex = invalidatedAtBarIndex
        self.expiresAtEpochSeconds = expiresAtEpochSeconds
        self.pierceATRMultiple = pierceATRMultiple
        self.rvolMultiple = rvolMultiple
        self.detail = detail
    }

    public var isActionable: Bool {
        state == .trigger || state == .active || state == .returned
    }
}
