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
    case open = "OPEN"
    case tp1Win = "TP1 WIN"
    case tp2Win = "TP2 WIN"
    case slLoss = "SL LOSS"
    case expired = "EXPIRED"

    public var id: String { rawValue }

    public var isWin: Bool { self == .tp1Win || self == .tp2Win }
    public var isLoss: Bool { self == .slLoss }
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
        exitedAt: Date?
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
        exitedAt: Date? = nil
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
            exitedAt: exitedAt
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


