import Foundation

// MARK: - Automatic 3-Section Journal Types

public enum JournalSection: String, Codable, Sendable, CaseIterable, Hashable, Identifiable {
    case strongSignals = "strong_signals"
    case weakAndFiltered = "weak_and_filtered"
    case trapAlerts = "trap_alerts"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .strongSignals: return "Strong Signals"
        case .weakAndFiltered: return "Weak & Filtered"
        case .trapAlerts: return "Trap Alerts"
        }
    }
}

public enum JournalTradeStatus: String, Codable, Sendable, CaseIterable, Hashable {
    case pending = "pending"
    case live = "live"
    case winTrackingTP2 = "win_tracking_tp2"
    case winTP1 = "win_tp1"
    case winTP2 = "win_tp2"
    case loss = "loss"
    case expired = "expired"

    public var isOpen: Bool {
        self == .pending || self == .live || self == .winTrackingTP2
    }

    public var isClosed: Bool {
        !isOpen
    }

    public var isCountedWin: Bool {
        self == .winTrackingTP2 || self == .winTP1 || self == .winTP2
    }

    public var isCountedLoss: Bool {
        self == .loss
    }

    public var isExcludedFromWinRate: Bool {
        self == .pending || self == .live || self == .expired
    }

    public var badgeLabel: String {
        switch self {
        case .pending: return "PENDING"
        case .live: return "LIVE"
        case .winTrackingTP2: return "WIN · TP1 → TP2"
        case .winTP1: return "WIN (TP1)"
        case .winTP2: return "WIN (TP2)"
        case .loss: return "LOSS"
        case .expired: return "EXPIRED"
        }
    }
}

public struct TrackedJournalTrade: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var symbol: String
    public var assetClass: MarketClass
    public var timeframe: Timeframe
    public var direction: TradeDirection
    public var section: JournalSection
    public var status: JournalTradeStatus
    public var score: Double
    public var signalBarTimestamp: TimeInterval
    public var entryZoneLow: Double
    public var entryZoneHigh: Double
    public var entryPrice: Double
    public var fillPrice: Double?
    public var stopLoss: Double
    public var target1: Double
    public var target2: Double
    public var isTP2Enabled: Bool
    public var currentPrice: Double
    public var livePnLPercent: Double
    public var liveRMultiple: Double
    public var realizedR: Double?
    public var isWinLocked: Bool
    public var activeStrategyProfileKey: String
    public var orderFlowStatus: String
    public var orderFlowSummary: ChartOrderFlowSummary?
    public var orderFlowCapturedAt: TimeInterval?
    public var createdAt: TimeInterval
    public var filledAt: TimeInterval?
    public var tp1HitAt: TimeInterval?
    public var closedAt: TimeInterval?
    public var lastEvaluatedAt: TimeInterval
    public var filterReason: String?
    public var matchedStrategyIDs: [String]

    public init(
        id: String = UUID().uuidString,
        symbol: String,
        assetClass: MarketClass,
        timeframe: Timeframe,
        direction: TradeDirection,
        section: JournalSection,
        status: JournalTradeStatus,
        score: Double,
        signalBarTimestamp: TimeInterval,
        entryZoneLow: Double,
        entryZoneHigh: Double,
        entryPrice: Double,
        fillPrice: Double? = nil,
        stopLoss: Double,
        target1: Double,
        target2: Double,
        isTP2Enabled: Bool = true,
        currentPrice: Double,
        livePnLPercent: Double = 0.0,
        liveRMultiple: Double = 0.0,
        realizedR: Double? = nil,
        isWinLocked: Bool = false,
        activeStrategyProfileKey: String = "",
        orderFlowStatus: String = "off",
        orderFlowSummary: ChartOrderFlowSummary? = nil,
        orderFlowCapturedAt: TimeInterval? = nil,
        createdAt: TimeInterval,
        filledAt: TimeInterval? = nil,
        tp1HitAt: TimeInterval? = nil,
        closedAt: TimeInterval? = nil,
        lastEvaluatedAt: TimeInterval? = nil,
        filterReason: String? = nil,
        matchedStrategyIDs: [String] = []
    ) {
        self.id = id
        self.symbol = symbol
        self.assetClass = assetClass
        self.timeframe = timeframe
        self.direction = direction
        self.section = section
        self.status = status
        self.score = score
        self.signalBarTimestamp = signalBarTimestamp
        self.entryZoneLow = min(entryZoneLow, entryZoneHigh)
        self.entryZoneHigh = max(entryZoneLow, entryZoneHigh)
        self.entryPrice = entryPrice
        self.fillPrice = fillPrice
        self.stopLoss = stopLoss
        self.target1 = target1
        self.target2 = target2
        self.isTP2Enabled = isTP2Enabled
        self.currentPrice = currentPrice
        self.livePnLPercent = livePnLPercent
        self.liveRMultiple = liveRMultiple
        self.realizedR = realizedR
        self.isWinLocked = isWinLocked
        self.activeStrategyProfileKey = activeStrategyProfileKey
        self.orderFlowStatus = orderFlowStatus
        self.orderFlowSummary = (assetClass == .crypto) ? orderFlowSummary : nil
        self.orderFlowCapturedAt = (assetClass == .crypto) ? orderFlowCapturedAt : nil
        self.createdAt = createdAt
        self.filledAt = filledAt
        self.tp1HitAt = tp1HitAt
        self.closedAt = closedAt
        self.lastEvaluatedAt = lastEvaluatedAt ?? createdAt
        self.filterReason = filterReason
        self.matchedStrategyIDs = matchedStrategyIDs
    }

    public var anchorEntryPrice: Double {
        if let fp = fillPrice, fp.isFinite, fp > 0 { return fp }
        return entryPrice
    }

    public var hasDistinctTP2: Bool {
        guard isTP2Enabled, target2.isFinite, target1.isFinite else { return false }
        let tol = max(abs(entryPrice) * 1e-9, Double.leastNormalMagnitude)
        if direction == .long {
            return target2 > target1 + tol
        } else if direction == .short {
            return target2 < target1 - tol
        }
        return false
    }

    public var effectiveStrategyProfileKey: String {
        ActiveStrategyProfile.normalizedKey(activeStrategyProfileKey)
    }

    /// Best known R-multiple for stats aggregation (realized R when locked/closed, else -1 for loss or live R).
    public var effectiveRMultiple: Double {
        if let r = realizedR, r.isFinite { return r }
        if status == .loss { return -1.0 }
        return liveRMultiple.isFinite ? liveRMultiple : 0.0
    }
}

// MARK: - Deterministic Automatic Signal Journal State Machine

public enum SignalJournalEngine {
    /// Timeframe-aware entry-zone pending expiration window.
    public static func pendingExpirySeconds(for timeframe: Timeframe) -> TimeInterval {
        switch timeframe {
        case .m15: return 3 * 3_600
        case .m30: return 6 * 3_600
        case .h1: return 12 * 3_600
        case .h4: return 32 * 3_600
        case .d1: return 5 * 86_400
        }
    }

    /// Runner expiration window after TP1 is locked (2× the pending expiry window).
    public static func tp2RunnerExpirySeconds(for timeframe: Timeframe) -> TimeInterval {
        2.0 * pendingExpirySeconds(for: timeframe)
    }

    /// Creates a tracked automatic journal entry from a `TradeSignal`.
    /// - Rejects `.neutral` direction and signals lacking valid finite `TradeLevels` (never logs neutral scans).
    /// - **Standard Limit-Order Fill:** When `currentPrice` is at or behind the entry zone on the stop-loss side
    ///   (`stopLoss < currentPrice <= entryZoneHigh` for LONG; `entryZoneLow <= currentPrice < stopLoss` for SHORT),
    ///   fills immediately at the actual live price (`fillPrice = currentPrice`) and initializes directly as `.live`.
    ///   If `currentPrice` is already at/beyond `stopLoss`, fills at `entryMid` and resolves conservatively as `.loss`.
    ///   If `currentPrice` is ahead of entry toward TP1, initializes as `.pending` waiting for a pullback.
    public static func createEntry(
        from signal: TradeSignal,
        section: JournalSection,
        currentPrice: Double,
        now: TimeInterval,
        filterReason: String? = nil
    ) -> TrackedJournalTrade? {
        guard signal.direction == .long || signal.direction == .short,
              let lv = signal.levels,
              lv.entryLow.isFinite, lv.entryHigh.isFinite, lv.entryMid.isFinite,
              lv.stopLoss.isFinite, lv.tp1.isFinite, lv.tp2.isFinite,
              lv.entryMid > 0, lv.stopLoss > 0, lv.tp1 > 0
        else { return nil }

        let orderedLow = min(lv.entryLow, lv.entryHigh)
        let orderedHigh = max(lv.entryLow, lv.entryHigh)
        let riskDist = abs(lv.entryMid - lv.stopLoss)
        guard riskDist.isFinite, riskDist > max(lv.entryMid * 1e-12, Double.leastNormalMagnitude) else {
            return nil
        }

        let safeCurrent = (currentPrice.isFinite && currentPrice > 0)
            ? currentPrice
            : (signal.recentCandles.last?.close ?? lv.entryMid)

        let signalBarTs: TimeInterval = {
            if let lastOpen = signal.recentCandles.last?.openTimeEpochSeconds, lastOpen.isFinite, lastOpen > 0 {
                return lastOpen
            }
            return max(0, signal.barCloseEpochSeconds - signal.timeframe.seconds)
        }()

        let immediateFill = isPriceEligibleForImmediateLimitFill(
            price: safeCurrent,
            direction: signal.direction,
            entryZoneLow: orderedLow,
            entryZoneHigh: orderedHigh,
            stopLoss: lv.stopLoss
        )
        let alreadyStoppedOut = isStopLossHit(
            price: safeCurrent,
            stopLoss: lv.stopLoss,
            direction: signal.direction
        )
        let initialStatus: JournalTradeStatus = immediateFill ? .live : .pending
        let fillPrice: Double? = immediateFill ? safeCurrent : (alreadyStoppedOut ? lv.entryMid : nil)
        let filledAt: TimeInterval? = (immediateFill || alreadyStoppedOut) ? now : nil

        let entryID = "\(signal.symbol)|\(signal.timeframe.rawValue)|\(section.rawValue)|\(Int(signalBarTs))"
        let ofCaptured: TimeInterval? = (signal.marketClass == .crypto && signal.orderFlowSummary != nil)
            ? (signal.orderFlowSummary?.capturedAtEpochSeconds ?? now)
            : nil

        let resolvedFilterReason: String? = {
            if let explicit = filterReason, !explicit.isEmpty { return explicit }
            if section == .weakAndFiltered {
                return signal.rejectionReasons.first
            }
            return nil
        }()

        var trade = TrackedJournalTrade(
            id: entryID,
            symbol: signal.symbol,
            assetClass: signal.marketClass,
            timeframe: signal.timeframe,
            direction: signal.direction,
            section: section,
            status: initialStatus,
            score: signal.confidencePercent,
            signalBarTimestamp: signalBarTs,
            entryZoneLow: orderedLow,
            entryZoneHigh: orderedHigh,
            entryPrice: lv.entryMid,
            fillPrice: fillPrice,
            stopLoss: lv.stopLoss,
            target1: lv.tp1,
            target2: lv.isTP2Enabled ? lv.tp2 : lv.tp1,
            isTP2Enabled: lv.isTP2Enabled,
            currentPrice: safeCurrent,
            livePnLPercent: 0.0,
            liveRMultiple: 0.0,
            realizedR: nil,
            isWinLocked: false,
            activeStrategyProfileKey: signal.activeStrategyProfileKey,
            orderFlowStatus: signal.orderFlowStatus,
            orderFlowSummary: signal.orderFlowSummary,
            orderFlowCapturedAt: ofCaptured,
            createdAt: now,
            filledAt: filledAt,
            tp1HitAt: nil,
            closedAt: nil,
            lastEvaluatedAt: now,
            filterReason: resolvedFilterReason,
            matchedStrategyIDs: signal.matchedStrategyIDs.map(\.rawValue)
        )
        if alreadyStoppedOut {
            applyLoss(&trade, closedAt: now)
        }
        return trade
    }

    /// Creates a tracked automatic `.trapAlerts` journal entry from an actionable `BehavioralTrap`,
    /// synthesizing deterministic ATR-anchored levels via `TradeLevelCalculator.synthesizeTrapLevels`.
    public static func createTrapEntry(
        from trap: BehavioralTrap,
        asset: AssetDescriptor,
        timeframe: Timeframe,
        candles: [Candle],
        atr: Double,
        currentPrice: Double,
        now: TimeInterval,
        score: Double = 65.0,
        activeStrategyProfileKey: String = "",
        orderFlowStatus: String = "off",
        orderFlowSummary: ChartOrderFlowSummary? = nil
    ) -> TrackedJournalTrade? {
        guard trap.isActionable else { return nil }
        guard let lv = TradeLevelCalculator.synthesizeTrapLevels(
            trap: trap,
            candles: candles,
            atr: atr,
            marketClass: asset.marketClass,
            timeframe: timeframe
        ) else { return nil }

        let dir = trap.direction.institutionalDirection
        guard dir == .long || dir == .short else { return nil }

        let orderedLow = min(lv.entryLow, lv.entryHigh)
        let orderedHigh = max(lv.entryLow, lv.entryHigh)
        let safeCurrent = (currentPrice.isFinite && currentPrice > 0)
            ? currentPrice
            : (candles.last?.close ?? lv.entryMid)

        let signalBarTs: TimeInterval = {
            if trap.triggerBarIndex >= 0 && trap.triggerBarIndex < candles.count {
                return candles[trap.triggerBarIndex].openTimeEpochSeconds
            }
            if let lastOpen = candles.last?.openTimeEpochSeconds {
                return lastOpen
            }
            return max(0, trap.triggerEpochSeconds - timeframe.seconds)
        }()

        let immediateFill = isPriceEligibleForImmediateLimitFill(
            price: safeCurrent,
            direction: dir,
            entryZoneLow: orderedLow,
            entryZoneHigh: orderedHigh,
            stopLoss: lv.stopLoss
        )
        let alreadyStoppedOut = isStopLossHit(
            price: safeCurrent,
            stopLoss: lv.stopLoss,
            direction: dir
        )
        let entryID = "\(asset.symbol)|\(timeframe.rawValue)|\(JournalSection.trapAlerts.rawValue)|\(Int(signalBarTs))"
        let strategyTag = StrategyID.forTrapKind(trap.triggerKind)?.rawValue
        let ofCaptured: TimeInterval? = (asset.marketClass == .crypto && orderFlowSummary != nil)
            ? (orderFlowSummary?.capturedAtEpochSeconds ?? now)
            : nil

        var trade = TrackedJournalTrade(
            id: entryID,
            symbol: asset.symbol,
            assetClass: asset.marketClass,
            timeframe: timeframe,
            direction: dir,
            section: .trapAlerts,
            status: immediateFill ? .live : .pending,
            score: score,
            signalBarTimestamp: signalBarTs,
            entryZoneLow: orderedLow,
            entryZoneHigh: orderedHigh,
            entryPrice: lv.entryMid,
            fillPrice: immediateFill ? safeCurrent : (alreadyStoppedOut ? lv.entryMid : nil),
            stopLoss: lv.stopLoss,
            target1: lv.tp1,
            target2: lv.tp2,
            isTP2Enabled: lv.isTP2Enabled,
            currentPrice: safeCurrent,
            livePnLPercent: 0.0,
            liveRMultiple: 0.0,
            realizedR: nil,
            isWinLocked: false,
            activeStrategyProfileKey: activeStrategyProfileKey,
            orderFlowStatus: orderFlowStatus,
            orderFlowSummary: orderFlowSummary,
            orderFlowCapturedAt: ofCaptured,
            createdAt: now,
            filledAt: (immediateFill || alreadyStoppedOut) ? now : nil,
            tp1HitAt: nil,
            closedAt: nil,
            lastEvaluatedAt: now,
            filterReason: "\(trap.direction.rawValue) · \(trap.triggerKind.rawValue)",
            matchedStrategyIDs: strategyTag.map { [$0] } ?? []
        )
        if alreadyStoppedOut {
            applyLoss(&trade, closedAt: now)
        }
        return trade
    }

    /// Evaluates a single live price tick against an open journal trade.
    /// **Hard Invariant:** Once `isWinLocked == true` (TP1 reached), the trade can NEVER transition to `.loss`.
    public static func evaluateLiveTick(
        entry: TrackedJournalTrade,
        livePrice: Double,
        now: TimeInterval
    ) -> TrackedJournalTrade {
        guard entry.status.isOpen,
              livePrice.isFinite, livePrice > 0,
              now.isFinite
        else { return entry }

        var updated = entry
        let previousPrice = entry.currentPrice
        updated.currentPrice = livePrice
        updated.lastEvaluatedAt = max(updated.lastEvaluatedAt, now)

        switch updated.status {
        case .pending:
            if (now - updated.createdAt) >= pendingExpirySeconds(for: updated.timeframe) {
                updated.status = .expired
                updated.closedAt = now
                updated.livePnLPercent = 0.0
                updated.liveRMultiple = 0.0
                return updated
            }

            let limitTriggered = isLimitFillTriggered(
                price: livePrice,
                direction: updated.direction,
                entryZoneLow: updated.entryZoneLow,
                entryZoneHigh: updated.entryZoneHigh
            )
            let crossedZone: Bool = {
                guard previousPrice.isFinite, previousPrice > 0 else { return false }
                let lo = min(previousPrice, livePrice)
                let hi = max(previousPrice, livePrice)
                return lo <= updated.entryZoneHigh && hi >= updated.entryZoneLow
            }()

            if limitTriggered || crossedZone {
                // If tick reached/crossed entry and simultaneously hit stop loss, fill and count as .loss
                if isStopLossHit(price: livePrice, stopLoss: updated.stopLoss, direction: updated.direction) {
                    let prevEligible = isPriceEligibleForImmediateLimitFill(
                        price: previousPrice,
                        direction: updated.direction,
                        entryZoneLow: updated.entryZoneLow,
                        entryZoneHigh: updated.entryZoneHigh,
                        stopLoss: updated.stopLoss
                    )
                    updated.fillPrice = prevEligible ? previousPrice : updated.entryPrice
                    updated.filledAt = now
                    applyLoss(&updated, closedAt: now)
                    return updated
                }

                let fill: Double
                if limitTriggered {
                    // Price is at or behind entry (between entry and SL): fill at actual live price
                    fill = livePrice
                } else {
                    // Price crossed the entry zone onto the TP side between ticks
                    let prevEligible = isPriceEligibleForImmediateLimitFill(
                        price: previousPrice,
                        direction: updated.direction,
                        entryZoneLow: updated.entryZoneLow,
                        entryZoneHigh: updated.entryZoneHigh,
                        stopLoss: updated.stopLoss
                    )
                    fill = prevEligible ? previousPrice : updated.entryPrice
                }
                updated.status = .live
                updated.fillPrice = fill
                updated.filledAt = now
                applyLiveMetrics(&updated, markPrice: livePrice)
                return updated
            }

            // Pre-fill miss on TP side: price hit TP1 without ever pulling back to entry -> .expired
            if isTargetHit(price: livePrice, target: updated.target1, direction: updated.direction) {
                updated.status = .expired
                updated.closedAt = now
                updated.realizedR = nil
                updated.livePnLPercent = 0.0
                updated.liveRMultiple = 0.0
                return updated
            }

            updated.livePnLPercent = 0.0
            updated.liveRMultiple = 0.0
            return updated

        case .live:
            applyLiveMetrics(&updated, markPrice: livePrice)

            // Pessimistic: check SL first
            if isStopLossHit(price: livePrice, stopLoss: updated.stopLoss, direction: updated.direction) {
                applyLoss(&updated, closedAt: now)
                return updated
            }

            // TP1 reached -> lock WIN!
            if isTargetHit(price: livePrice, target: updated.target1, direction: updated.direction) {
                updated.isWinLocked = true
                updated.tp1HitAt = updated.tp1HitAt ?? now
                let tp1R = computeR(price: updated.target1, entry: updated)

                if updated.hasDistinctTP2 && isTargetHit(price: livePrice, target: updated.target2, direction: updated.direction) {
                    let tp2R = computeR(price: updated.target2, entry: updated)
                    updated.status = .winTP2
                    updated.closedAt = now
                    updated.realizedR = tp2R
                    applyLiveMetrics(&updated, markPrice: updated.target2)
                } else if !updated.hasDistinctTP2 {
                    updated.status = .winTP1
                    updated.closedAt = now
                    updated.realizedR = tp1R
                    applyLiveMetrics(&updated, markPrice: updated.target1)
                } else {
                    updated.status = .winTrackingTP2
                    updated.realizedR = tp1R
                }
            }
            return updated

        case .winTrackingTP2:
            // Hard invariant: once isWinLocked == true, NEVER transition to .loss
            updated.isWinLocked = true
            applyLiveMetrics(&updated, markPrice: livePrice)

            let tp1R = computeR(price: updated.target1, entry: updated)

            // TP2 hit -> full WIN (TP2)
            if updated.hasDistinctTP2 && isTargetHit(price: livePrice, target: updated.target2, direction: updated.direction) {
                let tp2R = computeR(price: updated.target2, entry: updated)
                updated.status = .winTP2
                updated.closedAt = now
                updated.realizedR = tp2R
                applyLiveMetrics(&updated, markPrice: updated.target2)
                return updated
            }

            // Pullback to entry/breakeven or SL, OR runner expiry (2x pending window) -> lock WIN (TP1)
            let pulledBackToBreakeven = isPullbackToBreakevenOrSL(price: livePrice, entry: updated)
            let runnerOrigin = updated.tp1HitAt ?? updated.filledAt ?? updated.createdAt
            let runnerExpired = (now - runnerOrigin) >= tp2RunnerExpirySeconds(for: updated.timeframe)

            if pulledBackToBreakeven || runnerExpired {
                updated.status = .winTP1
                updated.closedAt = now
                updated.realizedR = tp1R
                applyLiveMetrics(&updated, markPrice: updated.target1)
            }
            return updated

        case .winTP1, .winTP2, .loss, .expired:
            return updated
        }
    }

    /// Gap-safe closed-candle reconciler executed on app foreground resume and after every scan.
    /// Walks strictly subsequent closed candles (`candle.openTimeEpochSeconds > entry.signalBarTimestamp`
    /// and `candle.closeTimeEpochSeconds >= entry.lastEvaluatedAt`) with pessimistic same-bar resolution:
    /// - Same-candle Entry + SL -> filled + `.loss` (TP ignored on fill bar).
    /// - Same-candle SL + TP1 while `.live` -> `.loss`.
    /// - Same-candle TP2 + breakeven/SL while `.winTrackingTP2` -> `.winTP1` (never `.loss`).
    public static func reconcile(
        entry: TrackedJournalTrade,
        againstClosedCandles candles: [Candle],
        livePrice: Double? = nil,
        now: TimeInterval
    ) -> TrackedJournalTrade {
        guard entry.status.isOpen else { return entry }
        var current = entry

        let eligible = candles
            .filter {
                $0.isClosed &&
                $0.openTimeEpochSeconds > current.signalBarTimestamp &&
                $0.closeTimeEpochSeconds >= current.lastEvaluatedAt &&
                $0.high.isFinite && $0.low.isFinite && $0.close.isFinite && $0.high >= $0.low
            }
            .sorted { $0.openTimeEpochSeconds < $1.openTimeEpochSeconds }

        for bar in eligible {
            guard current.status.isOpen else { break }
            let barClose = bar.closeTimeEpochSeconds
            current.currentPrice = bar.close
            current.lastEvaluatedAt = max(current.lastEvaluatedAt, barClose)

            switch current.status {
            case .pending:
                let expiryCutoff = current.createdAt + pendingExpirySeconds(for: current.timeframe)
                if bar.openTimeEpochSeconds >= expiryCutoff {
                    current.status = .expired
                    current.closedAt = expiryCutoff
                    current.livePnLPercent = 0.0
                    current.liveRMultiple = 0.0
                    continue
                }

                let limitFilled = isBarLimitFillTriggered(
                    bar: bar,
                    direction: current.direction,
                    entryZoneLow: current.entryZoneLow,
                    entryZoneHigh: current.entryZoneHigh
                )
                if limitFilled {
                    let barFillPrice: Double
                    if isPriceEligibleForImmediateLimitFill(
                        price: bar.open,
                        direction: current.direction,
                        entryZoneLow: current.entryZoneLow,
                        entryZoneHigh: current.entryZoneHigh,
                        stopLoss: current.stopLoss
                    ) {
                        barFillPrice = bar.open
                    } else if current.direction == .long {
                        barFillPrice = min(current.entryZoneHigh, max(bar.low, current.entryPrice))
                    } else {
                        barFillPrice = max(current.entryZoneLow, min(bar.high, current.entryPrice))
                    }
                    let slSafeFill = isStopLossHit(price: barFillPrice, stopLoss: current.stopLoss, direction: current.direction)
                        ? current.entryPrice
                        : barFillPrice
                    current.fillPrice = slSafeFill
                    current.filledAt = barClose
                    current.status = .live

                    // Conservative Fill-Bar Rule: check SL ONLY on the fill candle (never TP on the same bar)
                    let slHit = (current.direction == .long)
                        ? (bar.low <= current.stopLoss)
                        : (bar.high >= current.stopLoss)
                    if slHit {
                        applyLoss(&current, closedAt: barClose)
                    } else {
                        applyLiveMetrics(&current, markPrice: bar.close)
                    }
                    continue
                }

                // Pre-fill miss on TP side: TP1 hit without pulling back to entry, or timeout elapsed
                let tp1BeforeFill = (current.direction == .long)
                    ? (bar.high >= current.target1)
                    : (bar.low <= current.target1)
                let timedOut = (barClose >= expiryCutoff)

                if tp1BeforeFill || timedOut {
                    current.status = .expired
                    current.closedAt = barClose
                    current.realizedR = nil
                    current.livePnLPercent = 0.0
                    current.liveRMultiple = 0.0
                }

            case .live:
                let slHit = (current.direction == .long)
                    ? (bar.low <= current.stopLoss)
                    : (bar.high >= current.stopLoss)
                let tp1Hit = (current.direction == .long)
                    ? (bar.high >= current.target1)
                    : (bar.low <= current.target1)
                let tp2Hit = current.hasDistinctTP2 && ((current.direction == .long)
                    ? (bar.high >= current.target2)
                    : (bar.low <= current.target2))

                // Conservative same-bar SL + TP1 -> .loss
                if slHit {
                    applyLoss(&current, closedAt: barClose)
                } else if tp2Hit {
                    let tp2R = computeR(price: current.target2, entry: current)
                    current.isWinLocked = true
                    current.tp1HitAt = current.tp1HitAt ?? barClose
                    current.status = .winTP2
                    current.closedAt = barClose
                    current.realizedR = tp2R
                    applyLiveMetrics(&current, markPrice: current.target2)
                } else if tp1Hit {
                    let tp1R = computeR(price: current.target1, entry: current)
                    current.isWinLocked = true
                    current.tp1HitAt = barClose
                    if !current.hasDistinctTP2 {
                        current.status = .winTP1
                        current.closedAt = barClose
                        current.realizedR = tp1R
                        applyLiveMetrics(&current, markPrice: current.target1)
                    } else {
                        current.status = .winTrackingTP2
                        current.realizedR = tp1R
                        applyLiveMetrics(&current, markPrice: bar.close)
                    }
                } else {
                    applyLiveMetrics(&current, markPrice: bar.close)
                }

            case .winTrackingTP2:
                current.isWinLocked = true
                let tp1R = computeR(price: current.target1, entry: current)
                let pullbackHit = isBarPullbackToBreakevenOrSL(bar: bar, entry: current)
                let tp2Hit = current.hasDistinctTP2 && ((current.direction == .long)
                    ? (bar.high >= current.target2)
                    : (bar.low <= current.target2))
                let runnerOrigin = current.tp1HitAt ?? current.filledAt ?? current.createdAt
                let runnerExpired = (barClose - runnerOrigin) >= tp2RunnerExpirySeconds(for: current.timeframe)

                // Conservative same-bar TP2 + breakeven/SL -> lock WIN (TP1) (never .loss!)
                if pullbackHit {
                    current.status = .winTP1
                    current.closedAt = barClose
                    current.realizedR = tp1R
                    applyLiveMetrics(&current, markPrice: current.target1)
                } else if tp2Hit {
                    let tp2R = computeR(price: current.target2, entry: current)
                    current.status = .winTP2
                    current.closedAt = barClose
                    current.realizedR = tp2R
                    applyLiveMetrics(&current, markPrice: current.target2)
                } else if runnerExpired {
                    current.status = .winTP1
                    current.closedAt = barClose
                    current.realizedR = tp1R
                    applyLiveMetrics(&current, markPrice: current.target1)
                } else {
                    applyLiveMetrics(&current, markPrice: bar.close)
                }

            case .winTP1, .winTP2, .loss, .expired:
                break
            }
        }

        // Check elapsed-time expiries as of `now` even if no new closed bar arrived yet
        if current.status == .pending && (now - current.createdAt) >= pendingExpirySeconds(for: current.timeframe) {
            current.status = .expired
            current.closedAt = now
            current.lastEvaluatedAt = max(current.lastEvaluatedAt, now)
            current.livePnLPercent = 0.0
            current.liveRMultiple = 0.0
            return current
        }
        if current.status == .winTrackingTP2 {
            let runnerOrigin = current.tp1HitAt ?? current.filledAt ?? current.createdAt
            if (now - runnerOrigin) >= tp2RunnerExpirySeconds(for: current.timeframe) {
                let tp1R = computeR(price: current.target1, entry: current)
                current.status = .winTP1
                current.closedAt = now
                current.realizedR = tp1R
                current.lastEvaluatedAt = max(current.lastEvaluatedAt, now)
                applyLiveMetrics(&current, markPrice: current.target1)
                return current
            }
        }

        // Finally apply live price tick if trade is still open
        if let lp = livePrice, lp.isFinite, lp > 0, current.status.isOpen {
            current = evaluateLiveTick(entry: current, livePrice: lp, now: now)
        } else if current.status == .pending,
                  isLimitFillTriggered(
                      price: current.currentPrice,
                      direction: current.direction,
                      entryZoneLow: current.entryZoneLow,
                      entryZoneHigh: current.entryZoneHigh
                  ) {
            // Upgrade any pre-existing persisted .pending entry whose stored price is already at/behind entry
            current = evaluateLiveTick(entry: current, livePrice: current.currentPrice, now: now)
        } else if current.status.isOpen && current.status != .pending {
            applyLiveMetrics(&current, markPrice: current.currentPrice)
        }

        return current
    }

    // MARK: - Private Math & Limit-Fill Helpers

    /// True when `price` is at or behind the entry zone on the stop-loss side, strictly before stop loss,
    /// meaning a resting limit order fills immediately at the actual live price.
    /// - LONG (Buy Limit): `stopLoss < price <= entryZoneHigh`
    /// - SHORT (Sell Limit): `entryZoneLow <= price < stopLoss`
    private static func isPriceEligibleForImmediateLimitFill(
        price: Double,
        direction: TradeDirection,
        entryZoneLow: Double,
        entryZoneHigh: Double,
        stopLoss: Double
    ) -> Bool {
        guard price.isFinite, price > 0 else { return false }
        let orderedLow = min(entryZoneLow, entryZoneHigh)
        let orderedHigh = max(entryZoneLow, entryZoneHigh)
        switch direction {
        case .long:
            return price <= orderedHigh && price > stopLoss
        case .short:
            return price >= orderedLow && price < stopLoss
        case .neutral:
            return false
        }
    }

    /// True when a live tick has reached or passed the entry limit price (including through to stop loss).
    /// - LONG (Buy Limit): `price <= entryZoneHigh`
    /// - SHORT (Sell Limit): `price >= entryZoneLow`
    private static func isLimitFillTriggered(
        price: Double,
        direction: TradeDirection,
        entryZoneLow: Double,
        entryZoneHigh: Double
    ) -> Bool {
        guard price.isFinite, price > 0 else { return false }
        let orderedLow = min(entryZoneLow, entryZoneHigh)
        let orderedHigh = max(entryZoneLow, entryZoneHigh)
        switch direction {
        case .long:
            return price <= orderedHigh
        case .short:
            return price >= orderedLow
        case .neutral:
            return false
        }
    }

    /// True when a closed candle traded at or behind the entry limit price.
    /// - LONG (Buy Limit): `bar.low <= entryZoneHigh`
    /// - SHORT (Sell Limit): `bar.high >= entryZoneLow`
    private static func isBarLimitFillTriggered(
        bar: Candle,
        direction: TradeDirection,
        entryZoneLow: Double,
        entryZoneHigh: Double
    ) -> Bool {
        let orderedLow = min(entryZoneLow, entryZoneHigh)
        let orderedHigh = max(entryZoneLow, entryZoneHigh)
        switch direction {
        case .long:
            return bar.low <= orderedHigh
        case .short:
            return bar.high >= orderedLow
        case .neutral:
            return false
        }
    }

    private static func riskDistance(for entry: TrackedJournalTrade) -> Double {
        let anchor = entry.anchorEntryPrice
        let minEps = max(anchor * 1e-9, Double.leastNormalMagnitude)
        let dist = abs(anchor - entry.stopLoss)
        if dist.isFinite && dist > minEps {
            return dist
        }
        let fallback = abs(entry.entryPrice - entry.stopLoss)
        return max(fallback, minEps)
    }

    private static func computeR(price: Double, entry: TrackedJournalTrade) -> Double {
        let anchor = entry.anchorEntryPrice
        let risk = riskDistance(for: entry)
        let delta = (entry.direction == .long) ? (price - anchor) : (anchor - price)
        let r = delta / risk
        return r.isFinite ? r : 0.0
    }

    private static func applyLiveMetrics(_ entry: inout TrackedJournalTrade, markPrice: Double) {
        let anchor = entry.anchorEntryPrice
        guard anchor.isFinite, anchor > 0, markPrice.isFinite, markPrice > 0 else {
            entry.livePnLPercent = 0.0
            entry.liveRMultiple = 0.0
            return
        }
        let delta = (entry.direction == .long) ? (markPrice - anchor) : (anchor - markPrice)
        let pct = (delta / anchor) * 100.0
        let r = delta / riskDistance(for: entry)
        entry.livePnLPercent = pct.isFinite ? pct : 0.0
        entry.liveRMultiple = r.isFinite ? r : 0.0
    }

    private static func applyLoss(_ entry: inout TrackedJournalTrade, closedAt: TimeInterval) {
        // Defense in depth: locked winners can NEVER become .loss
        guard !entry.isWinLocked else {
            entry.status = .winTP1
            entry.closedAt = closedAt
            entry.realizedR = computeR(price: entry.target1, entry: entry)
            applyLiveMetrics(&entry, markPrice: entry.target1)
            return
        }
        entry.status = .loss
        entry.closedAt = closedAt
        entry.realizedR = -1.0
        let anchor = entry.anchorEntryPrice
        let slPct = (abs(anchor - entry.stopLoss) / max(anchor, Double.leastNormalMagnitude)) * 100.0
        entry.livePnLPercent = slPct.isFinite ? -slPct : 0.0
        entry.liveRMultiple = -1.0
    }

    private static func isStopLossHit(price: Double, stopLoss: Double, direction: TradeDirection) -> Bool {
        switch direction {
        case .long: return price <= stopLoss
        case .short: return price >= stopLoss
        case .neutral: return false
        }
    }

    private static func isTargetHit(price: Double, target: Double, direction: TradeDirection) -> Bool {
        switch direction {
        case .long: return price >= target
        case .short: return price <= target
        case .neutral: return false
        }
    }

    private static func isPullbackToBreakevenOrSL(price: Double, entry: TrackedJournalTrade) -> Bool {
        let beFloor: Double
        switch entry.direction {
        case .long:
            beFloor = max(entry.anchorEntryPrice, entry.stopLoss)
            return price <= beFloor
        case .short:
            beFloor = min(entry.anchorEntryPrice, entry.stopLoss)
            return price >= beFloor
        case .neutral:
            return false
        }
    }

    private static func isBarPullbackToBreakevenOrSL(bar: Candle, entry: TrackedJournalTrade) -> Bool {
        switch entry.direction {
        case .long:
            let beLevel = max(entry.anchorEntryPrice, entry.stopLoss)
            return bar.low <= beLevel
        case .short:
            let beLevel = min(entry.anchorEntryPrice, entry.stopLoss)
            return bar.high >= beLevel
        case .neutral:
            return false
        }
    }
}
