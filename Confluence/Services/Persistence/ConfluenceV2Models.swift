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

// MARK: - SwiftData VersionedSchema Chain (v1.0..v1.6 -> v2.0) & Staged Migration Plan

/// Top-level alias pointing the active app & tests at the v2.0 `PersistedSignalRecord` schema.
public typealias PersistedSignalRecord = ConfluenceSchemaV20.PersistedSignalRecord

/// Legacy v1.0 (1-table) schema snapshot for crash-free over-the-top staged migration.
public enum ConfluenceSchemaV10: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [
            ConfluenceSchemaV16.PersistedSignalRecord.self
        ]
    }
}

/// Legacy v1.1 (5-table) schema snapshot for crash-free over-the-top staged migration.
public enum ConfluenceSchemaV11: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 1, 0) }
    public static var models: [any PersistentModel.Type] {
        [
            ConfluenceSchemaV16.PersistedSignalRecord.self,
            StoredNotificationItem.self,
            DiagnosticLogEntry.self,
            TrapLogEntry.self,
            TradeLedgerEntry.self
        ]
    }
}

/// Legacy v1.2 (6-table) schema snapshot for crash-free over-the-top staged migration.
public enum ConfluenceSchemaV12: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 2, 0) }
    public static var models: [any PersistentModel.Type] {
        [
            ConfluenceSchemaV16.PersistedSignalRecord.self,
            StoredNotificationItem.self,
            DiagnosticLogEntry.self,
            TrapLogEntry.self,
            TradeLedgerEntry.self,
            TradeReplayCandleCache.self
        ]
    }
}

/// Legacy v1.3 (8-table) schema snapshot for crash-free over-the-top staged migration.
public enum ConfluenceSchemaV13: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 3, 0) }
    public static var models: [any PersistentModel.Type] {
        [
            ConfluenceSchemaV16.PersistedSignalRecord.self,
            StoredNotificationItem.self,
            DiagnosticLogEntry.self,
            TrapLogEntry.self,
            TradeLedgerEntry.self,
            TradeReplayCandleCache.self,
            PersistedOutcomeRecord.self,
            CrashLogEntry.self
        ]
    }
}

/// Legacy v1.4 (9-table) schema snapshot for crash-free over-the-top staged migration.
public enum ConfluenceSchemaV14: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 4, 0) }
    public static var models: [any PersistentModel.Type] {
        [
            ConfluenceSchemaV16.PersistedSignalRecord.self,
            StoredNotificationItem.self,
            DiagnosticLogEntry.self,
            TrapLogEntry.self,
            TradeLedgerEntry.self,
            TradeReplayCandleCache.self,
            PersistedOutcomeRecord.self,
            CrashLogEntry.self,
            ConfluenceSchemaV16.JournalEntry.self
        ]
    }
}

/// Legacy v1.5 (12-table) schema snapshot for crash-free over-the-top staged migration.
public enum ConfluenceSchemaV15: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 5, 0) }
    public static var models: [any PersistentModel.Type] {
        [
            ConfluenceSchemaV16.PersistedSignalRecord.self,
            StoredNotificationItem.self,
            DiagnosticLogEntry.self,
            TrapLogEntry.self,
            TradeLedgerEntry.self,
            TradeReplayCandleCache.self,
            PersistedOutcomeRecord.self,
            CrashLogEntry.self,
            ConfluenceSchemaV16.JournalEntry.self,
            ConfluenceSchemaV16.DemoWalletRecord.self,
            ConfluenceSchemaV16.DemoPositionRecord.self,
            ConfluenceSchemaV16.DemoWalletTransactionRecord.self
        ]
    }
}

/// Byte-for-byte v1.6 (13-table) SwiftData schema snapshot capturing all legacy tables
/// and `PersistedSignalRecord.outcomeJSON` prior to v2.0 retirement.
public enum ConfluenceSchemaV16: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 6, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            ConfluenceSchemaV16.PersistedSignalRecord.self,
            StoredNotificationItem.self,
            DiagnosticLogEntry.self,
            TrapLogEntry.self,
            TradeLedgerEntry.self,
            TradeReplayCandleCache.self,
            PersistedOutcomeRecord.self,
            CrashLogEntry.self,
            ConfluenceSchemaV16.JournalEntry.self,
            ConfluenceSchemaV16.DemoWalletRecord.self,
            ConfluenceSchemaV16.DemoPositionRecord.self,
            ConfluenceSchemaV16.DemoWalletTransactionRecord.self,
            TrackedSignalJournalEntry.self
        ]
    }

    /// v1.0–v1.6 persisted signal model carrying legacy `outcomeJSON: Data?`.
    @Model
    public final class PersistedSignalRecord {
        @Attribute(.unique) public var fingerprint: String
        public var symbol: String
        public var directionRaw: String
        public var categoryRaw: String
        public var createdAt: Date
        public var signalJSON: Data
        public var outcomeJSON: Data?
        public var activeStrategyProfileKey: String = ""
        public var enabledStrategyIDsCSV: String = ""
        public var orderFlowStatus: String = "off"

        public init(
            fingerprint: String,
            symbol: String,
            directionRaw: String,
            categoryRaw: String,
            createdAt: Date,
            signalJSON: Data,
            outcomeJSON: Data? = nil,
            activeStrategyProfileKey: String = "",
            enabledStrategyIDsCSV: String = "",
            orderFlowStatus: String = "off"
        ) {
            self.fingerprint = fingerprint
            self.symbol = symbol
            self.directionRaw = directionRaw
            self.categoryRaw = categoryRaw
            self.createdAt = createdAt
            self.signalJSON = signalJSON
            self.outcomeJSON = outcomeJSON
            self.activeStrategyProfileKey = activeStrategyProfileKey
            self.enabledStrategyIDsCSV = enabledStrategyIDsCSV
            self.orderFlowStatus = orderFlowStatus
        }
    }

    /// Legacy v1.4 manual trade journal table (retired in v2.0).
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
            outcomeRaw: String = "OPEN",
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
    }

    /// Legacy v1.5 Demo Wallet summary table (retired in v2.0).
    @Model
    public final class DemoWalletRecord {
        @Attribute(.unique) public var id: String = "primary"
        public var startingBalanceUSD: Double = 1_000.0
        public var cashBalanceUSD: Double = 1_000.0
        public var reservedMarginUSD: Double = 0
        public var realizedPnLUSD: Double = 0
        public var totalFeesPaidUSD: Double = 0
        public var updatedAt: Date = Date()

        public init(
            id: String = "primary",
            startingBalanceUSD: Double = 1_000.0,
            cashBalanceUSD: Double = 1_000.0,
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

    /// Legacy v1.5 Demo Wallet position table (retired in v2.0).
    @Model
    public final class DemoPositionRecord {
        @Attribute(.unique) public var id: String = ""
        public var symbol: String = ""
        public var statusRaw: String = ""
        public var positionJSON: Data = Data()
        public var createdAt: Date = Date()
        public var closedAt: Date? = nil
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
    }

    /// Legacy v1.5 Demo Wallet transaction ledger table (retired in v2.0).
    @Model
    public final class DemoWalletTransactionRecord {
        @Attribute(.unique) public var id: String = ""
        public var timestamp: Date = Date()
        public var kindRaw: String = ""
        public var symbol: String? = nil
        public var positionId: String? = nil
        public var amountUSD: Double = 0
        public var balanceAfterUSD: Double = 0
        public var note: String = ""

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
    }
}

/// Active v2.0 (9-table) SwiftData schema retiring `JournalEntry`, `DemoWalletRecord`,
/// `DemoPositionRecord`, `DemoWalletTransactionRecord`, and `PersistedSignalRecord.outcomeJSON`.
public enum ConfluenceSchemaV20: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            ConfluenceSchemaV20.PersistedSignalRecord.self,
            StoredNotificationItem.self,
            DiagnosticLogEntry.self,
            TrapLogEntry.self,
            TradeLedgerEntry.self,
            TradeReplayCandleCache.self,
            PersistedOutcomeRecord.self,
            CrashLogEntry.self,
            TrackedSignalJournalEntry.self
        ]
    }

    /// v2.0 persisted signal model (decoupled outcomes live exclusively in `PersistedOutcomeRecord`).
    @Model
    public final class PersistedSignalRecord {
        @Attribute(.unique) public var fingerprint: String
        public var symbol: String
        public var directionRaw: String
        public var categoryRaw: String
        public var createdAt: Date
        public var signalJSON: Data
        public var activeStrategyProfileKey: String = ""
        public var enabledStrategyIDsCSV: String = ""
        public var orderFlowStatus: String = "off"

        public init(
            fingerprint: String,
            symbol: String,
            directionRaw: String,
            categoryRaw: String,
            createdAt: Date,
            signalJSON: Data,
            activeStrategyProfileKey: String = "",
            enabledStrategyIDsCSV: String = "",
            orderFlowStatus: String = "off"
        ) {
            self.fingerprint = fingerprint
            self.symbol = symbol
            self.directionRaw = directionRaw
            self.categoryRaw = categoryRaw
            self.createdAt = createdAt
            self.signalJSON = signalJSON
            self.activeStrategyProfileKey = activeStrategyProfileKey
            self.enabledStrategyIDsCSV = enabledStrategyIDsCSV
            self.orderFlowStatus = orderFlowStatus
        }
    }
}

/// Staged SwiftData migration plan upgrading any legacy v1.0–v1.6 SQLite store cleanly into v2.0
/// with zero data loss and strict Swift 6 concurrency compliance (no mutable static state).
public enum ConfluenceMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [
            ConfluenceSchemaV10.self,
            ConfluenceSchemaV11.self,
            ConfluenceSchemaV12.self,
            ConfluenceSchemaV13.self,
            ConfluenceSchemaV14.self,
            ConfluenceSchemaV15.self,
            ConfluenceSchemaV16.self,
            ConfluenceSchemaV20.self
        ]
    }

    public static var stages: [MigrationStage] {
        [
            MigrationStage.lightweight(
                fromVersion: ConfluenceSchemaV10.self,
                toVersion: ConfluenceSchemaV11.self
            ),
            MigrationStage.lightweight(
                fromVersion: ConfluenceSchemaV11.self,
                toVersion: ConfluenceSchemaV12.self
            ),
            MigrationStage.lightweight(
                fromVersion: ConfluenceSchemaV12.self,
                toVersion: ConfluenceSchemaV13.self
            ),
            MigrationStage.lightweight(
                fromVersion: ConfluenceSchemaV13.self,
                toVersion: ConfluenceSchemaV14.self
            ),
            MigrationStage.lightweight(
                fromVersion: ConfluenceSchemaV14.self,
                toVersion: ConfluenceSchemaV15.self
            ),
            MigrationStage.lightweight(
                fromVersion: ConfluenceSchemaV15.self,
                toVersion: ConfluenceSchemaV16.self
            ),
            MigrationStage.custom(
                fromVersion: ConfluenceSchemaV16.self,
                toVersion: ConfluenceSchemaV20.self,
                willMigrate: { context in
                    try ConfluenceMigrationPlan.backfillPersistedOutcomesIfNeeded(in: context)
                },
                didMigrate: nil
            )
        ]
    }

    /// Backfills any embedded pre-v1.3 `PersistedSignalRecord.outcomeJSON` blobs into
    /// `PersistedOutcomeRecord` before Core Data drops the `outcomeJSON` column in v2.0.
    public static func backfillPersistedOutcomesIfNeeded(in context: ModelContext) throws {
        let legacyRows = try context.fetch(FetchDescriptor<ConfluenceSchemaV16.PersistedSignalRecord>())
        guard !legacyRows.isEmpty else { return }

        let existingOutcomes = try context.fetch(FetchDescriptor<PersistedOutcomeRecord>())
        var existingOutcomeIDs = Set(existingOutcomes.map(\.signalId))

        let decoder = JSONDecoder()
        var insertedAny = false
        for row in legacyRows {
            guard let data = row.outcomeJSON,
                  let decoded = try? decoder.decode(SignalOutcomeRecord.self, from: data),
                  !existingOutcomeIDs.contains(decoded.signalId)
            else { continue }
            let resolvedDate = decoded.resolvedAtEpochSeconds.map { Date(timeIntervalSince1970: $0) } ?? row.createdAt
            context.insert(
                PersistedOutcomeRecord(
                    signalId: decoded.signalId,
                    outcomeJSON: data,
                    resolvedAt: resolvedDate
                )
            )
            existingOutcomeIDs.insert(decoded.signalId)
            insertedAny = true
        }
        if insertedAny {
            try context.save()
        }
    }
}

// MARK: - Purely Additive v1.6 SwiftData @Model Class (Automatic 3-Section Signal Journal)

/// Purely additive v1.6 table storing 100% automatically tracked Signal Journal trades
/// across Strong Signals, Weak & Filtered, and Trap Alerts.
/// Every persisted property declares an inline default for lightweight over-the-top migration.
@Model
public final class TrackedSignalJournalEntry {
    @Attribute(.unique) public var id: String = UUID().uuidString
    public var symbol: String = ""
    public var assetClassRaw: String = ""
    public var timeframeRaw: String = ""
    public var directionRaw: String = ""
    public var sectionRaw: String = ""
    public var statusRaw: String = ""
    public var score: Double = 0
    public var signalBarTimestamp: Double = 0
    public var entryZoneLow: Double = 0
    public var entryZoneHigh: Double = 0
    public var entryPrice: Double = 0
    public var fillPrice: Double? = nil
    public var stopLoss: Double = 0
    public var target1: Double = 0
    public var target2: Double = 0
    public var isTP2Enabled: Bool = true
    public var currentPrice: Double = 0
    public var livePnLPercent: Double = 0
    public var liveRMultiple: Double = 0
    public var realizedR: Double? = nil
    public var isWinLocked: Bool = false
    public var activeStrategyProfileKey: String = ""
    public var orderFlowStatus: String = "off"
    public var orderFlowSummaryJSON: Data? = nil
    public var orderFlowCapturedAt: Date? = nil
    public var createdAt: Date = Date()
    public var filledAt: Date? = nil
    public var tp1HitAt: Date? = nil
    public var closedAt: Date? = nil
    public var lastEvaluatedAt: Date = Date()
    public var filterReason: String? = nil
    public var matchedStrategyIDsCSV: String = ""

    public init(from trade: TrackedJournalTrade) {
        self.id = trade.id
        self.symbol = trade.symbol
        self.assetClassRaw = trade.assetClass.rawValue
        self.timeframeRaw = trade.timeframe.rawValue
        self.directionRaw = trade.direction.rawValue
        self.sectionRaw = trade.section.rawValue
        self.statusRaw = trade.status.rawValue
        self.score = trade.score
        self.signalBarTimestamp = trade.signalBarTimestamp
        self.entryZoneLow = trade.entryZoneLow
        self.entryZoneHigh = trade.entryZoneHigh
        self.entryPrice = trade.entryPrice
        self.fillPrice = trade.fillPrice
        self.stopLoss = trade.stopLoss
        self.target1 = trade.target1
        self.target2 = trade.target2
        self.isTP2Enabled = trade.isTP2Enabled
        self.currentPrice = trade.currentPrice
        self.livePnLPercent = trade.livePnLPercent
        self.liveRMultiple = trade.liveRMultiple
        self.realizedR = trade.realizedR
        self.isWinLocked = trade.isWinLocked
        self.activeStrategyProfileKey = trade.activeStrategyProfileKey
        self.orderFlowStatus = trade.orderFlowStatus
        self.orderFlowSummaryJSON = trade.orderFlowSummary.flatMap { try? JSONEncoder().encode($0) }
        self.orderFlowCapturedAt = trade.orderFlowCapturedAt.map { Date(timeIntervalSince1970: $0) }
        self.createdAt = Date(timeIntervalSince1970: trade.createdAt)
        self.filledAt = trade.filledAt.map { Date(timeIntervalSince1970: $0) }
        self.tp1HitAt = trade.tp1HitAt.map { Date(timeIntervalSince1970: $0) }
        self.closedAt = trade.closedAt.map { Date(timeIntervalSince1970: $0) }
        self.lastEvaluatedAt = Date(timeIntervalSince1970: trade.lastEvaluatedAt)
        self.filterReason = trade.filterReason
        self.matchedStrategyIDsCSV = trade.matchedStrategyIDs.joined(separator: ",")
    }

    public func apply(from trade: TrackedJournalTrade) {
        self.symbol = trade.symbol
        self.assetClassRaw = trade.assetClass.rawValue
        self.timeframeRaw = trade.timeframe.rawValue
        self.directionRaw = trade.direction.rawValue
        self.sectionRaw = trade.section.rawValue
        self.statusRaw = trade.status.rawValue
        self.score = trade.score
        self.signalBarTimestamp = trade.signalBarTimestamp
        self.entryZoneLow = trade.entryZoneLow
        self.entryZoneHigh = trade.entryZoneHigh
        self.entryPrice = trade.entryPrice
        self.fillPrice = trade.fillPrice
        self.stopLoss = trade.stopLoss
        self.target1 = trade.target1
        self.target2 = trade.target2
        self.isTP2Enabled = trade.isTP2Enabled
        self.currentPrice = trade.currentPrice
        self.livePnLPercent = trade.livePnLPercent
        self.liveRMultiple = trade.liveRMultiple
        self.realizedR = trade.realizedR
        self.isWinLocked = trade.isWinLocked
        self.activeStrategyProfileKey = trade.activeStrategyProfileKey
        self.orderFlowStatus = trade.orderFlowStatus
        if let summary = trade.orderFlowSummary, let data = try? JSONEncoder().encode(summary) {
            self.orderFlowSummaryJSON = data
        }
        self.orderFlowCapturedAt = trade.orderFlowCapturedAt.map { Date(timeIntervalSince1970: $0) }
        self.filledAt = trade.filledAt.map { Date(timeIntervalSince1970: $0) }
        self.tp1HitAt = trade.tp1HitAt.map { Date(timeIntervalSince1970: $0) }
        self.closedAt = trade.closedAt.map { Date(timeIntervalSince1970: $0) }
        self.lastEvaluatedAt = Date(timeIntervalSince1970: trade.lastEvaluatedAt)
        self.filterReason = trade.filterReason
        self.matchedStrategyIDsCSV = trade.matchedStrategyIDs.joined(separator: ",")
    }

    public func toTrackedTrade() -> TrackedJournalTrade {
        let decodedOF: ChartOrderFlowSummary? = orderFlowSummaryJSON.flatMap {
            try? JSONDecoder().decode(ChartOrderFlowSummary.self, from: $0)
        }
        let strategyIDs = matchedStrategyIDsCSV
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return TrackedJournalTrade(
            id: id,
            symbol: symbol,
            assetClass: MarketClass(rawValue: assetClassRaw) ?? .crypto,
            timeframe: Timeframe(rawValue: timeframeRaw) ?? .h1,
            direction: TradeDirection(rawValue: directionRaw) ?? .long,
            section: JournalSection(rawValue: sectionRaw) ?? .strongSignals,
            status: JournalTradeStatus(rawValue: statusRaw) ?? .pending,
            score: score,
            signalBarTimestamp: signalBarTimestamp,
            entryZoneLow: entryZoneLow,
            entryZoneHigh: entryZoneHigh,
            entryPrice: entryPrice,
            fillPrice: fillPrice,
            stopLoss: stopLoss,
            target1: target1,
            target2: target2,
            isTP2Enabled: isTP2Enabled,
            currentPrice: currentPrice,
            livePnLPercent: livePnLPercent,
            liveRMultiple: liveRMultiple,
            realizedR: realizedR,
            isWinLocked: isWinLocked,
            activeStrategyProfileKey: activeStrategyProfileKey,
            orderFlowStatus: orderFlowStatus,
            orderFlowSummary: decodedOF,
            orderFlowCapturedAt: orderFlowCapturedAt?.timeIntervalSince1970,
            createdAt: createdAt.timeIntervalSince1970,
            filledAt: filledAt?.timeIntervalSince1970,
            tp1HitAt: tp1HitAt?.timeIntervalSince1970,
            closedAt: closedAt?.timeIntervalSince1970,
            lastEvaluatedAt: lastEvaluatedAt.timeIntervalSince1970,
            filterReason: filterReason,
            matchedStrategyIDs: strategyIDs
        )
    }
}




