import Foundation
import SwiftData
import SignalEngine

// MARK: - Domain Enums & Sendable Snapshots

public enum NotificationItemType: String, Codable, Sendable, CaseIterable, Identifiable {
    case strongSignal = "STRONG_SIGNAL"
    case trapAlert = "TRAP_ALERT"
    case preNewsCountdown = "PRE_NEWS"
    case newsReleaseImpact = "NEWS_RELEASE"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .strongSignal: return "Signal"
        case .trapAlert: return "Trap"
        case .preNewsCountdown: return "Pre-News"
        case .newsReleaseImpact: return "Macro Release"
        }
    }

    public var isNewsCategory: Bool {
        self == .preNewsCountdown || self == .newsReleaseImpact
    }
}

public struct NotificationItemSnapshot: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let id: String
    public let createdAt: Date
    public let type: NotificationItemType
    public let title: String
    public let subtitle: String
    public let symbol: String?
    public let marketClass: MarketClass?
    public let timeframe: Timeframe?
    public let direction: TradeDirection?
    public let confidence: Double?
    public let signalFingerprint: String?
    public let eventID: String?
    public let isRead: Bool

    public init(
        id: String,
        createdAt: Date = Date(),
        type: NotificationItemType,
        title: String,
        subtitle: String,
        symbol: String? = nil,
        marketClass: MarketClass? = nil,
        timeframe: Timeframe? = nil,
        direction: TradeDirection? = nil,
        confidence: Double? = nil,
        signalFingerprint: String? = nil,
        eventID: String? = nil,
        isRead: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.marketClass = marketClass
        self.timeframe = timeframe
        self.direction = direction
        self.confidence = confidence
        self.signalFingerprint = signalFingerprint
        self.eventID = eventID
        self.isRead = isRead
    }
}

public enum DiagnosticSeverity: String, Codable, Sendable, CaseIterable, Identifiable {
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"

    public var id: String { rawValue }
}

public enum DiagnosticCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case feed = "Feed"
    case fallback = "Fallback"
    case engine = "Engine"
    case notification = "Notification"
    case chart = "Chart"
    case ai = "AI"
    case background = "Background"

    public var id: String { rawValue }
}

public struct DiagnosticLogSnapshot: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let timestamp: Date
    public let severity: DiagnosticSeverity
    public let category: DiagnosticCategory
    public let message: String
    public let detail: String?

    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        severity: DiagnosticSeverity,
        category: DiagnosticCategory,
        message: String,
        detail: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.severity = severity
        self.category = category
        self.message = message
        self.detail = detail
    }
}

public struct TrapLogSnapshot: Codable, Sendable, Equatable, Identifiable {
    public var id: String { trapKey }
    public let trapKey: String
    public let symbol: String
    public let timeframe: Timeframe
    public let direction: TrapDirection
    public let triggerKind: TrapTriggerKind
    public let priceLevel: Double
    public let positioningContext: String
    public let triggeredAt: Date
    public let activatedAt: Date?
    public let returnedAt: Date?
    public let invalidatedAt: Date?
    public let currentState: TrapLifecycleState
    public let postTrapOutcome: TrapRespectOutcome

    public init(
        trapKey: String,
        symbol: String,
        timeframe: Timeframe,
        direction: TrapDirection,
        triggerKind: TrapTriggerKind,
        priceLevel: Double,
        positioningContext: String,
        triggeredAt: Date,
        activatedAt: Date? = nil,
        returnedAt: Date? = nil,
        invalidatedAt: Date? = nil,
        currentState: TrapLifecycleState,
        postTrapOutcome: TrapRespectOutcome = .pending
    ) {
        self.trapKey = trapKey
        self.symbol = symbol
        self.timeframe = timeframe
        self.direction = direction
        self.triggerKind = triggerKind
        self.priceLevel = priceLevel
        self.positioningContext = positioningContext
        self.triggeredAt = triggeredAt
        self.activatedAt = activatedAt
        self.returnedAt = returnedAt
        self.invalidatedAt = invalidatedAt
        self.currentState = currentState
        self.postTrapOutcome = postTrapOutcome
    }
}

public enum TradeLedgerStatus: String, Codable, Sendable, CaseIterable, Identifiable {
    case pending = "PENDING"
    case open = "OPEN"
    case tp1Win = "TP1 WIN"
    case tp2Win = "TP2 WIN"
    case slLoss = "SL LOSS"
    case expired = "EXPIRED"
    case notFilled = "NOT FILLED"
    case invalidated = "INVALIDATED"

    public var id: String { rawValue }

    public var isWin: Bool { self == .tp1Win || self == .tp2Win }
    public var isLoss: Bool { self == .slLoss }
    public var isActive: Bool { self == .pending || self == .open }
}

public struct TradeLedgerSnapshot: Codable, Sendable, Equatable, Identifiable {
    public var id: String { fingerprint }
    public let fingerprint: String
    public let symbol: String
    public let marketClass: MarketClass
    public let timeframe: Timeframe
    public let direction: TradeDirection
    public let entryLow: Double
    public let entryHigh: Double
    public let entryMid: Double
    public let stopLoss: Double
    public let tp1: Double
    public let tp2: Double
    public let confidencePercent: Double
    public let regime: MarketRegime
    public let killzone: KillzoneSession
    public let dataProvider: String
    public let alignedStrategyIDs: [String]
    public let status: TradeLedgerStatus
    public let netRMultiple: Double
    public let createdAt: Date
    public let exitedAt: Date?
    public let activeStrategyProfileKey: String
    public let enabledStrategyIDsCSV: String
    public let orderFlowStatus: String

    public init(
        fingerprint: String,
        symbol: String,
        marketClass: MarketClass,
        timeframe: Timeframe,
        direction: TradeDirection,
        entryLow: Double,
        entryHigh: Double,
        entryMid: Double,
        stopLoss: Double,
        tp1: Double,
        tp2: Double,
        confidencePercent: Double,
        regime: MarketRegime,
        killzone: KillzoneSession,
        dataProvider: String,
        alignedStrategyIDs: [String],
        status: TradeLedgerStatus,
        netRMultiple: Double,
        createdAt: Date,
        exitedAt: Date?,
        activeStrategyProfileKey: String = "",
        enabledStrategyIDsCSV: String = "",
        orderFlowStatus: String = "off"
    ) {
        self.fingerprint = fingerprint
        self.symbol = symbol
        self.marketClass = marketClass
        self.timeframe = timeframe
        self.direction = direction
        self.entryLow = entryLow
        self.entryHigh = entryHigh
        self.entryMid = entryMid
        self.stopLoss = stopLoss
        self.tp1 = tp1
        self.tp2 = tp2
        self.confidencePercent = confidencePercent
        self.regime = regime
        self.killzone = killzone
        self.dataProvider = dataProvider
        self.alignedStrategyIDs = alignedStrategyIDs
        self.status = status
        self.netRMultiple = netRMultiple
        self.createdAt = createdAt
        self.exitedAt = exitedAt
        self.activeStrategyProfileKey = activeStrategyProfileKey
        self.enabledStrategyIDsCSV = enabledStrategyIDsCSV
        self.orderFlowStatus = orderFlowStatus
    }

    enum CodingKeys: String, CodingKey {
        case fingerprint, symbol, marketClass, timeframe, direction
        case entryLow, entryHigh, entryMid, stopLoss, tp1, tp2
        case confidencePercent, regime, killzone, dataProvider, alignedStrategyIDs
        case status, netRMultiple, createdAt, exitedAt
        case activeStrategyProfileKey, enabledStrategyIDsCSV, orderFlowStatus
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fingerprint = try c.decode(String.self, forKey: .fingerprint)
        symbol = try c.decode(String.self, forKey: .symbol)
        marketClass = try c.decode(MarketClass.self, forKey: .marketClass)
        timeframe = try c.decode(Timeframe.self, forKey: .timeframe)
        direction = try c.decode(TradeDirection.self, forKey: .direction)
        entryLow = try c.decode(Double.self, forKey: .entryLow)
        entryHigh = try c.decode(Double.self, forKey: .entryHigh)
        entryMid = try c.decode(Double.self, forKey: .entryMid)
        stopLoss = try c.decode(Double.self, forKey: .stopLoss)
        tp1 = try c.decode(Double.self, forKey: .tp1)
        tp2 = try c.decode(Double.self, forKey: .tp2)
        confidencePercent = try c.decode(Double.self, forKey: .confidencePercent)
        regime = try c.decode(MarketRegime.self, forKey: .regime)
        killzone = try c.decode(KillzoneSession.self, forKey: .killzone)
        dataProvider = try c.decode(String.self, forKey: .dataProvider)
        alignedStrategyIDs = (try? c.decodeIfPresent([String].self, forKey: .alignedStrategyIDs)) ?? []
        status = try c.decode(TradeLedgerStatus.self, forKey: .status)
        netRMultiple = try c.decode(Double.self, forKey: .netRMultiple)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        exitedAt = try c.decodeIfPresent(Date.self, forKey: .exitedAt)
        activeStrategyProfileKey = (try? c.decodeIfPresent(String.self, forKey: .activeStrategyProfileKey)) ?? ""
        enabledStrategyIDsCSV = (try? c.decodeIfPresent(String.self, forKey: .enabledStrategyIDsCSV)) ?? ""
        orderFlowStatus = (try? c.decodeIfPresent(String.self, forKey: .orderFlowStatus)) ?? "off"
    }
}

// MARK: - Purely Additive SwiftData @Model Classes (v1.0 -> v1.1 Lightweight Migration Safe)

@Model
public final class StoredNotificationItem {
    @Attribute(.unique) public var id: String
    public var createdAt: Date
    public var typeRaw: String
    public var title: String
    public var subtitle: String
    public var symbol: String?
    public var marketRaw: String?
    public var timeframeRaw: String?
    public var directionRaw: String?
    public var confidence: Double?
    public var signalFingerprint: String?
    public var eventID: String?
    public var isRead: Bool

    public init(
        id: String,
        createdAt: Date,
        typeRaw: String,
        title: String,
        subtitle: String,
        symbol: String? = nil,
        marketRaw: String? = nil,
        timeframeRaw: String? = nil,
        directionRaw: String? = nil,
        confidence: Double? = nil,
        signalFingerprint: String? = nil,
        eventID: String? = nil,
        isRead: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.typeRaw = typeRaw
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.marketRaw = marketRaw
        self.timeframeRaw = timeframeRaw
        self.directionRaw = directionRaw
        self.confidence = confidence
        self.signalFingerprint = signalFingerprint
        self.eventID = eventID
        self.isRead = isRead
    }

    public func toSnapshot() -> NotificationItemSnapshot {
        NotificationItemSnapshot(
            id: id,
            createdAt: createdAt,
            type: NotificationItemType(rawValue: typeRaw) ?? .strongSignal,
            title: title,
            subtitle: subtitle,
            symbol: symbol,
            marketClass: marketRaw.flatMap(MarketClass.init(rawValue:)),
            timeframe: timeframeRaw.flatMap(Timeframe.init(rawValue:)),
            direction: directionRaw.flatMap(TradeDirection.init(rawValue:)),
            confidence: confidence,
            signalFingerprint: signalFingerprint,
            eventID: eventID,
            isRead: isRead
        )
    }
}

@Model
public final class DiagnosticLogEntry {
    @Attribute(.unique) public var id: String
    public var timestamp: Date
    public var severityRaw: String
    public var categoryRaw: String
    public var message: String
    public var detail: String?

    public init(
        id: String,
        timestamp: Date,
        severityRaw: String,
        categoryRaw: String,
        message: String,
        detail: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.severityRaw = severityRaw
        self.categoryRaw = categoryRaw
        self.message = message
        self.detail = detail
    }

    public func toSnapshot() -> DiagnosticLogSnapshot {
        DiagnosticLogSnapshot(
            id: id,
            timestamp: timestamp,
            severity: DiagnosticSeverity(rawValue: severityRaw) ?? .info,
            category: DiagnosticCategory(rawValue: categoryRaw) ?? .feed,
            message: message,
            detail: detail
        )
    }
}

@Model
public final class TrapLogEntry {
    @Attribute(.unique) public var trapKey: String
    public var symbol: String
    public var timeframeRaw: String
    public var directionRaw: String
    public var triggerKindRaw: String
    public var priceLevel: Double
    public var positioningContext: String
    public var triggeredAt: Date
    public var activatedAt: Date?
    public var returnedAt: Date?
    public var invalidatedAt: Date?
    public var currentStateRaw: String
    public var postTrapOutcomeRaw: String

    public init(
        trapKey: String,
        symbol: String,
        timeframeRaw: String,
        directionRaw: String,
        triggerKindRaw: String,
        priceLevel: Double,
        positioningContext: String,
        triggeredAt: Date,
        activatedAt: Date? = nil,
        returnedAt: Date? = nil,
        invalidatedAt: Date? = nil,
        currentStateRaw: String,
        postTrapOutcomeRaw: String = TrapRespectOutcome.pending.rawValue
    ) {
        self.trapKey = trapKey
        self.symbol = symbol
        self.timeframeRaw = timeframeRaw
        self.directionRaw = directionRaw
        self.triggerKindRaw = triggerKindRaw
        self.priceLevel = priceLevel
        self.positioningContext = positioningContext
        self.triggeredAt = triggeredAt
        self.activatedAt = activatedAt
        self.returnedAt = returnedAt
        self.invalidatedAt = invalidatedAt
        self.currentStateRaw = currentStateRaw
        self.postTrapOutcomeRaw = postTrapOutcomeRaw
    }

    public func toSnapshot() -> TrapLogSnapshot {
        TrapLogSnapshot(
            trapKey: trapKey,
            symbol: symbol,
            timeframe: Timeframe(rawValue: timeframeRaw) ?? .h1,
            direction: TrapDirection(rawValue: directionRaw) ?? .bullTrap,
            triggerKind: TrapTriggerKind(rawValue: triggerKindRaw) ?? .liquiditySwingSweep,
            priceLevel: priceLevel,
            positioningContext: positioningContext,
            triggeredAt: triggeredAt,
            activatedAt: activatedAt,
            returnedAt: returnedAt,
            invalidatedAt: invalidatedAt,
            currentState: TrapLifecycleState(rawValue: currentStateRaw) ?? .trigger,
            postTrapOutcome: TrapRespectOutcome(rawValue: postTrapOutcomeRaw) ?? .pending
        )
    }
}

@Model
public final class TradeLedgerEntry {
    @Attribute(.unique) public var fingerprint: String
    public var symbol: String
    public var marketRaw: String
    public var timeframeRaw: String
    public var directionRaw: String
    public var entryLow: Double
    public var entryHigh: Double
    public var entryMid: Double
    public var stopLoss: Double
    public var tp1: Double
    public var tp2: Double
    public var confidencePercent: Double
    public var regimeRaw: String
    public var killzoneRaw: String
    public var dataProvider: String
    public var alignedStrategyIDsJSON: Data
    public var statusRaw: String
    public var netRMultiple: Double
    public var createdAt: Date
    public var exitedAt: Date?
    public var activeStrategyProfileKey: String = ""
    public var enabledStrategyIDsCSV: String = ""
    public var orderFlowStatus: String = "off"

    public init(
        fingerprint: String,
        symbol: String,
        marketRaw: String,
        timeframeRaw: String,
        directionRaw: String,
        entryLow: Double,
        entryHigh: Double,
        entryMid: Double,
        stopLoss: Double,
        tp1: Double,
        tp2: Double,
        confidencePercent: Double,
        regimeRaw: String,
        killzoneRaw: String,
        dataProvider: String,
        alignedStrategyIDsJSON: Data,
        statusRaw: String,
        netRMultiple: Double,
        createdAt: Date,
        exitedAt: Date? = nil,
        activeStrategyProfileKey: String = "",
        enabledStrategyIDsCSV: String = "",
        orderFlowStatus: String = "off"
    ) {
        self.fingerprint = fingerprint
        self.symbol = symbol
        self.marketRaw = marketRaw
        self.timeframeRaw = timeframeRaw
        self.directionRaw = directionRaw
        self.entryLow = entryLow
        self.entryHigh = entryHigh
        self.entryMid = entryMid
        self.stopLoss = stopLoss
        self.tp1 = tp1
        self.tp2 = tp2
        self.confidencePercent = confidencePercent
        self.regimeRaw = regimeRaw
        self.killzoneRaw = killzoneRaw
        self.dataProvider = dataProvider
        self.alignedStrategyIDsJSON = alignedStrategyIDsJSON
        self.statusRaw = statusRaw
        self.netRMultiple = netRMultiple
        self.createdAt = createdAt
        self.exitedAt = exitedAt
        self.activeStrategyProfileKey = activeStrategyProfileKey
        self.enabledStrategyIDsCSV = enabledStrategyIDsCSV
        self.orderFlowStatus = orderFlowStatus
    }

    public func toSnapshot() -> TradeLedgerSnapshot {
        let ids = (try? JSONDecoder().decode([String].self, from: alignedStrategyIDsJSON)) ?? []
        return TradeLedgerSnapshot(
            fingerprint: fingerprint,
            symbol: symbol,
            marketClass: MarketClass(rawValue: marketRaw) ?? .crypto,
            timeframe: Timeframe(rawValue: timeframeRaw) ?? .h1,
            direction: TradeDirection(rawValue: directionRaw) ?? .neutral,
            entryLow: entryLow,
            entryHigh: entryHigh,
            entryMid: entryMid,
            stopLoss: stopLoss,
            tp1: tp1,
            tp2: tp2,
            confidencePercent: confidencePercent,
            regime: MarketRegime(rawValue: regimeRaw) ?? .meanReverting,
            killzone: KillzoneSession(rawValue: killzoneRaw) ?? .offSession,
            dataProvider: dataProvider,
            alignedStrategyIDs: ids,
            status: TradeLedgerStatus(rawValue: statusRaw) ?? .open,
            netRMultiple: netRMultiple,
            createdAt: createdAt,
            exitedAt: exitedAt,
            activeStrategyProfileKey: activeStrategyProfileKey,
            enabledStrategyIDsCSV: enabledStrategyIDsCSV,
            orderFlowStatus: orderFlowStatus
        )
    }
}

/// Purely additive v1.2 SwiftData table storing merged pre-entry + post-entry/exit candles
/// for resolved trade chart replay (zero schema mutations on v1.0/v1.1 tables).
@Model
public final class TradeReplayCandleCache {
    @Attribute(.unique) public var fingerprint: String
    public var symbol: String
    public var timeframeRaw: String
    public var providerName: String
    public var candlesJSON: Data
    public var updatedAt: Date

    public init(
        fingerprint: String,
        symbol: String,
        timeframeRaw: String,
        providerName: String,
        candlesJSON: Data,
        updatedAt: Date = Date()
    ) {
        self.fingerprint = fingerprint
        self.symbol = symbol
        self.timeframeRaw = timeframeRaw
        self.providerName = providerName
        self.candlesJSON = candlesJSON
        self.updatedAt = updatedAt
    }
}

/// Unified trade item surfaced inside Strategy Reliability Ranking -> Strategy Trades list
/// and passed directly into `FullScreenChartSheet` Trade Replay Mode.
public struct StrategyTradeItem: Identifiable, Sendable, Equatable, Hashable {
    public var id: String { fingerprint }
    public let fingerprint: String
    public let symbol: String
    public let displayName: String
    public let marketClass: MarketClass
    public let timeframe: Timeframe
    public let direction: TradeDirection
    public let category: SignalCategory
    public let confidencePercent: Double
    public let levels: TradeLevels
    public let status: TradeLedgerStatus
    public let netRMultiple: Double
    public let dataProvider: String
    public let entryEpochSeconds: TimeInterval
    public let exitEpochSeconds: TimeInterval?
    public let alignedStrategyIDs: [String]
    public let sourceSignal: TradeSignal?

    public init(
        fingerprint: String,
        symbol: String,
        displayName: String,
        marketClass: MarketClass,
        timeframe: Timeframe,
        direction: TradeDirection,
        category: SignalCategory,
        confidencePercent: Double,
        levels: TradeLevels,
        status: TradeLedgerStatus,
        netRMultiple: Double,
        dataProvider: String,
        entryEpochSeconds: TimeInterval,
        exitEpochSeconds: TimeInterval?,
        alignedStrategyIDs: [String],
        sourceSignal: TradeSignal?
    ) {
        self.fingerprint = fingerprint
        self.symbol = symbol
        self.displayName = displayName
        self.marketClass = marketClass
        self.timeframe = timeframe
        self.direction = direction
        self.category = category
        self.confidencePercent = confidencePercent
        self.levels = levels
        self.status = status
        self.netRMultiple = netRMultiple
        self.dataProvider = dataProvider
        self.entryEpochSeconds = entryEpochSeconds
        self.exitEpochSeconds = exitEpochSeconds
        self.alignedStrategyIDs = alignedStrategyIDs
        self.sourceSignal = sourceSignal
    }
}

/// Context passed into `FullScreenChartSheet` when opened in Trade Outcome Chart Replay Mode.
public struct TradeReplayContext: Sendable, Equatable, Hashable {
    public let trade: StrategyTradeItem
    public let initialCandles: [Candle]
    public let providerName: String

    public init(trade: StrategyTradeItem, initialCandles: [Candle], providerName: String) {
        self.trade = trade
        self.initialCandles = initialCandles
        self.providerName = providerName
    }
}

// MARK: - v1.3 Purely Additive Crash Logging & Decoupled Outcome Persistence

public enum CrashLogSource: String, Codable, Sendable, CaseIterable, Identifiable {
    case metricKitCrash = "MetricKit Crash"
    case metricKitHang = "MetricKit Hang"
    case uncaughtException = "Uncaught Exception"
    case posixFatalSignal = "POSIX Fatal Signal"

    public var id: String { rawValue }
}

public struct CrashLogSnapshot: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let id: String
    public let timestamp: Date
    public let source: CrashLogSource
    public let appVersion: String
    public let appBuild: String
    public let crashType: String
    public let summary: String
    public let stackTrace: String

    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        source: CrashLogSource,
        appVersion: String,
        appBuild: String,
        crashType: String,
        summary: String,
        stackTrace: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.crashType = crashType
        self.summary = summary
        self.stackTrace = stackTrace
    }
}

/// Purely additive v1.3 SwiftData table decoupling resolved Calibration outcomes from
/// user-deletable `PersistedSignalRecord` cards (zero mutation to v1.0/v1.1/v1.2 schemas).
@Model
public final class PersistedOutcomeRecord {
    @Attribute(.unique) public var signalId: String
    public var outcomeJSON: Data
    public var resolvedAt: Date

    public init(
        signalId: String,
        outcomeJSON: Data,
        resolvedAt: Date = Date()
    ) {
        self.signalId = signalId
        self.outcomeJSON = outcomeJSON
        self.resolvedAt = resolvedAt
    }
}

/// Purely additive v1.3 SwiftData table persisting scrubbed MetricKit crashes/hangs,
/// uncaught NSExceptions, and POSIX fatal signal breadcrumbs.
@Model
public final class CrashLogEntry {
    @Attribute(.unique) public var id: String
    public var timestamp: Date
    public var sourceRaw: String
    public var appVersion: String
    public var appBuild: String
    public var crashType: String
    public var summary: String
    public var stackTrace: String

    public init(
        id: String,
        timestamp: Date,
        sourceRaw: String,
        appVersion: String,
        appBuild: String,
        crashType: String,
        summary: String,
        stackTrace: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.sourceRaw = sourceRaw
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.crashType = crashType
        self.summary = summary
        self.stackTrace = stackTrace
    }

    public func toSnapshot() -> CrashLogSnapshot {
        CrashLogSnapshot(
            id: id,
            timestamp: timestamp,
            source: CrashLogSource(rawValue: sourceRaw) ?? .metricKitCrash,
            appVersion: appVersion,
            appBuild: appBuild,
            crashType: crashType,
            summary: summary,
            stackTrace: stackTrace
        )
    }
}

// MARK: - v1.4 Purely Additive Trade Journal (9th SwiftData Table — Zero Mutation to v1.0-v1.3 Tables)

public enum JournalTradeOutcome: String, Codable, Sendable, CaseIterable, Identifiable {
    case open = "OPEN"
    case win = "WIN"
    case loss = "LOSS"
    case breakeven = "BREAKEVEN"
    case scratched = "SCRATCHED"

    public var id: String { rawValue }
}

public struct JournalEntrySnapshot: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let id: String
    public let signalFingerprint: String?
    public let symbol: String
    public let marketClass: MarketClass
    public let timeframe: Timeframe
    public let direction: TradeDirection
    public let plannedEntry: Double
    public let actualFillPrice: Double?
    public let stopLoss: Double
    public let tp1: Double
    public let tp2: Double?
    public let exitPrice: Double?
    public let positionSizeText: String?
    public let outcome: JournalTradeOutcome
    public let actualRMultiple: Double?
    public let systemRMultiple: Double?
    public let strategyIDs: [String]
    public let tags: [String]
    public let notes: String
    public let takenAt: Date
    public let closedAt: Date?

    public init(
        id: String = UUID().uuidString,
        signalFingerprint: String? = nil,
        symbol: String,
        marketClass: MarketClass,
        timeframe: Timeframe,
        direction: TradeDirection,
        plannedEntry: Double,
        actualFillPrice: Double? = nil,
        stopLoss: Double,
        tp1: Double,
        tp2: Double? = nil,
        exitPrice: Double? = nil,
        positionSizeText: String? = nil,
        outcome: JournalTradeOutcome = .open,
        actualRMultiple: Double? = nil,
        systemRMultiple: Double? = nil,
        strategyIDs: [String] = [],
        tags: [String] = [],
        notes: String = "",
        takenAt: Date = Date(),
        closedAt: Date? = nil
    ) {
        self.id = id
        self.signalFingerprint = signalFingerprint
        self.symbol = symbol
        self.marketClass = marketClass
        self.timeframe = timeframe
        self.direction = direction
        self.plannedEntry = plannedEntry
        self.actualFillPrice = actualFillPrice
        self.stopLoss = stopLoss
        self.tp1 = tp1
        self.tp2 = tp2
        self.exitPrice = exitPrice
        self.positionSizeText = positionSizeText
        self.outcome = outcome
        self.actualRMultiple = actualRMultiple
        self.systemRMultiple = systemRMultiple
        self.strategyIDs = strategyIDs
        self.tags = tags
        self.notes = notes
        self.takenAt = takenAt
        self.closedAt = closedAt
    }

    public var effectiveRMultiple: Double? {
        if let explicit = actualRMultiple { return explicit }
        guard let exit = exitPrice else { return nil }
        let entry = actualFillPrice ?? plannedEntry
        let risk = abs(entry - stopLoss)
        guard risk > 1e-12 else { return nil }
        let pnl = (direction == .long) ? (exit - entry) : (entry - exit)
        return pnl / risk
    }
}

public struct JournalSummaryStats: Sendable, Equatable {
    public let totalTaken: Int
    public let closedCount: Int
    public let winsCount: Int
    public let lossesCount: Int
    public let myWinRate: Double?
    public let myWinRateCI: WilsonInterval?
    public let myAvgR: Double?
    public let systemAvgR: Double?
    public let takenRatio: Double?

    public init(
        totalTaken: Int,
        closedCount: Int,
        winsCount: Int,
        lossesCount: Int,
        myWinRate: Double?,
        myWinRateCI: WilsonInterval?,
        myAvgR: Double?,
        systemAvgR: Double?,
        takenRatio: Double?
    ) {
        self.totalTaken = totalTaken
        self.closedCount = closedCount
        self.winsCount = winsCount
        self.lossesCount = lossesCount
        self.myWinRate = myWinRate
        self.myWinRateCI = myWinRateCI
        self.myAvgR = myAvgR
        self.systemAvgR = systemAvgR
        self.takenRatio = takenRatio
    }

    public static func compute(entries: [JournalEntrySnapshot], totalSystemStrongSignals: Int) -> JournalSummaryStats {
        let closed = entries.filter { $0.outcome == .win || $0.outcome == .loss || $0.outcome == .breakeven }
        let wins = closed.filter { $0.outcome == .win }.count
        let losses = closed.filter { $0.outcome == .loss }.count
        let decided = wins + losses
        let wr: Double? = decided > 0 ? Double(wins) / Double(decided) : nil
        let ci = WilsonInterval.compute(wins: wins, total: decided)
        let rVals = closed.compactMap(\.effectiveRMultiple)
        let myAvgR: Double? = rVals.isEmpty ? nil : rVals.reduce(0, +) / Double(rVals.count)
        let sysRVals = entries.compactMap(\.systemRMultiple)
        let sysAvgR: Double? = sysRVals.isEmpty ? nil : sysRVals.reduce(0, +) / Double(sysRVals.count)
        let ratio: Double? = totalSystemStrongSignals > 0
            ? min(1.0, Double(entries.count) / Double(totalSystemStrongSignals))
            : nil
        return JournalSummaryStats(
            totalTaken: entries.count,
            closedCount: closed.count,
            winsCount: wins,
            lossesCount: losses,
            myWinRate: wr,
            myWinRateCI: ci,
            myAvgR: myAvgR,
            systemAvgR: sysAvgR,
            takenRatio: ratio
        )
    }
}

/// Purely additive v1.4 SwiftData table for user's personal Trade Journal.
@Model
public final class JournalEntry {
    @Attribute(.unique) public var id: String
    public var signalFingerprint: String?
    public var symbol: String
    public var marketRaw: String
    public var timeframeRaw: String
    public var directionRaw: String
    public var plannedEntry: Double
    public var actualFillPrice: Double?
    public var stopLoss: Double
    public var tp1: Double
    public var tp2: Double?
    public var exitPrice: Double?
    public var positionSizeText: String?
    public var outcomeRaw: String
    public var actualRMultiple: Double?
    public var systemRMultiple: Double?
    public var strategyIDsJSON: Data
    public var tagsJSON: Data
    public var notes: String
    public var takenAt: Date
    public var closedAt: Date?

    public init(
        id: String,
        signalFingerprint: String? = nil,
        symbol: String,
        marketRaw: String,
        timeframeRaw: String,
        directionRaw: String,
        plannedEntry: Double,
        actualFillPrice: Double? = nil,
        stopLoss: Double,
        tp1: Double,
        tp2: Double? = nil,
        exitPrice: Double? = nil,
        positionSizeText: String? = nil,
        outcomeRaw: String = JournalTradeOutcome.open.rawValue,
        actualRMultiple: Double? = nil,
        systemRMultiple: Double? = nil,
        strategyIDsJSON: Data = Data(),
        tagsJSON: Data = Data(),
        notes: String = "",
        takenAt: Date = Date(),
        closedAt: Date? = nil
    ) {
        self.id = id
        self.signalFingerprint = signalFingerprint
        self.symbol = symbol
        self.marketRaw = marketRaw
        self.timeframeRaw = timeframeRaw
        self.directionRaw = directionRaw
        self.plannedEntry = plannedEntry
        self.actualFillPrice = actualFillPrice
        self.stopLoss = stopLoss
        self.tp1 = tp1
        self.tp2 = tp2
        self.exitPrice = exitPrice
        self.positionSizeText = positionSizeText
        self.outcomeRaw = outcomeRaw
        self.actualRMultiple = actualRMultiple
        self.systemRMultiple = systemRMultiple
        self.strategyIDsJSON = strategyIDsJSON
        self.tagsJSON = tagsJSON
        self.notes = notes
        self.takenAt = takenAt
        self.closedAt = closedAt
    }

    public func toSnapshot() -> JournalEntrySnapshot {
        let stratIDs = (try? JSONDecoder().decode([String].self, from: strategyIDsJSON)) ?? []
        let tags = (try? JSONDecoder().decode([String].self, from: tagsJSON)) ?? []
        return JournalEntrySnapshot(
            id: id,
            signalFingerprint: signalFingerprint,
            symbol: symbol,
            marketClass: MarketClass(rawValue: marketRaw) ?? .crypto,
            timeframe: Timeframe(rawValue: timeframeRaw) ?? .h1,
            direction: TradeDirection(rawValue: directionRaw) ?? .long,
            plannedEntry: plannedEntry,
            actualFillPrice: actualFillPrice,
            stopLoss: stopLoss,
            tp1: tp1,
            tp2: tp2,
            exitPrice: exitPrice,
            positionSizeText: positionSizeText,
            outcome: JournalTradeOutcome(rawValue: outcomeRaw) ?? .open,
            actualRMultiple: actualRMultiple,
            systemRMultiple: systemRMultiple,
            strategyIDs: stratIDs,
            tags: tags,
            notes: notes,
            takenAt: takenAt,
            closedAt: closedAt
        )
    }
}

// MARK: - Purely Additive v1.5 SwiftData @Model Classes (Demo Paper Wallet)

/// Purely additive v1.5 table storing the simulated paper-trading wallet summary.
@Model
public final class DemoWalletRecord {
    @Attribute(.unique) public var id: String
    public var startingBalanceUSD: Double
    public var cashBalanceUSD: Double
    public var reservedMarginUSD: Double
    public var realizedPnLUSD: Double
    public var totalFeesPaidUSD: Double
    public var updatedAt: Date

    public init(
        id: String = "primary",
        startingBalanceUSD: Double = DemoWallet.defaultStartingBalanceUSD,
        cashBalanceUSD: Double = DemoWallet.defaultStartingBalanceUSD,
        reservedMarginUSD: Double = 0,
        realizedPnLUSD: Double = 0,
        totalFeesPaidUSD: Double = 0,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.startingBalanceUSD = startingBalanceUSD
        self.cashBalanceUSD = cashBalanceUSD
        self.reservedMarginUSD = reservedMarginUSD
        self.realizedPnLUSD = realizedPnLUSD
        self.totalFeesPaidUSD = totalFeesPaidUSD
        self.updatedAt = updatedAt
    }
}

/// Purely additive v1.5 table storing simulated demo positions (JSON-encoded `DemoPosition` payload).
@Model
public final class DemoPositionRecord {
    @Attribute(.unique) public var id: String
    public var symbol: String
    public var statusRaw: String
    public var positionJSON: Data
    public var createdAt: Date
    public var closedAt: Date?
    public var activeStrategyProfileKey: String = ""
    public var enabledStrategyIDsCSV: String = ""
    public var orderFlowStatus: String = "off"

    public init(
        id: String,
        symbol: String,
        statusRaw: String,
        positionJSON: Data,
        createdAt: Date,
        closedAt: Date? = nil,
        activeStrategyProfileKey: String = "",
        enabledStrategyIDsCSV: String = "",
        orderFlowStatus: String = "off"
    ) {
        self.id = id
        self.symbol = symbol
        self.statusRaw = statusRaw
        self.positionJSON = positionJSON
        self.createdAt = createdAt
        self.closedAt = closedAt
        self.activeStrategyProfileKey = activeStrategyProfileKey
        self.enabledStrategyIDsCSV = enabledStrategyIDsCSV
        self.orderFlowStatus = orderFlowStatus
    }

    public func toPosition() -> DemoPosition? {
        try? JSONDecoder().decode(DemoPosition.self, from: positionJSON)
    }
}

/// Purely additive v1.5 table storing simulated demo wallet transactions.
@Model
public final class DemoWalletTransactionRecord {
    @Attribute(.unique) public var id: String
    public var timestamp: Date
    public var kindRaw: String
    public var symbol: String?
    public var positionId: String?
    public var amountUSD: Double
    public var balanceAfterUSD: Double
    public var note: String

    public init(
        id: String,
        timestamp: Date,
        kindRaw: String,
        symbol: String? = nil,
        positionId: String? = nil,
        amountUSD: Double,
        balanceAfterUSD: Double,
        note: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kindRaw = kindRaw
        self.symbol = symbol
        self.positionId = positionId
        self.amountUSD = amountUSD
        self.balanceAfterUSD = balanceAfterUSD
        self.note = note
    }

    public func toTransaction() -> DemoWalletTransaction {
        DemoWalletTransaction(
            id: id,
            timestampEpochSeconds: timestamp.timeIntervalSince1970,
            kind: DemoTransactionKind(rawValue: kindRaw) ?? .balanceAdjustment,
            symbol: symbol,
            positionId: positionId,
            amountUSD: amountUSD,
            balanceAfterUSD: balanceAfterUSD,
            note: note
        )
    }
}




