import Foundation

public enum DemoOrderType: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case market
    case limit
}

public enum DemoExitTarget: String, Codable, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case target1
    case target2

    public var id: String { rawValue }

    public var displayLabel: String {
        switch self {
        case .target1: return "Target 1"
        case .target2: return "Target 2"
        }
    }
}

public enum DemoPositionStatus: String, Codable, Sendable, Equatable, Hashable {
    case pendingLimit
    case open
    case closedTarget1
    case closedTarget2
    case closedStopLoss
    case closedManual
    case expired
    case cancelled

    public var isActive: Bool {
        self == .pendingLimit || self == .open
    }

    public var isClosed: Bool {
        !isActive
    }
}

public enum DemoTransactionKind: String, Codable, Sendable, Equatable, Hashable {
    case initialDeposit
    case balanceAdjustment
    case marginReserved
    case marginReleased
    case realizedPnL
    case fee
}

public enum DemoOrderRejectionReason: Error, Sendable, Equatable {
    case invalidDirection
    case invalidPrices(String)
    case staleLiveQuote(ageSeconds: Double)
    case marketClosed(reason: String, suggestLimit: Bool)
    case insufficientFreeMargin
    case invalidQuantity
    case positionNotFound
    case invalidState(String)

    public var userMessage: String {
        switch self {
        case .invalidDirection:
            return "Direction must be Long or Short."
        case .invalidPrices(let detail):
            return detail
        case .staleLiveQuote(let age):
            return "Live price is \(Int(age.rounded()))s old (over 60s). Refresh or confirm stale-price fill."
        case .marketClosed(let reason, let suggestLimit):
            if suggestLimit {
                return "\(reason) Market orders are blocked while closed — place a Limit order instead."
            }
            return reason
        case .insufficientFreeMargin:
            return "Not enough free demo margin available."
        case .invalidQuantity:
            return "Calculated position size is zero or invalid."
        case .positionNotFound:
            return "Demo position not found."
        case .invalidState(let msg):
            return msg
        }
    }
}

public enum DemoMarginSpec {
    /// Conservative default paper-trading leverage by market class.
    public static func defaultLeverage(for marketClass: MarketClass) -> Double {
        switch marketClass {
        case .crypto: return 1.0
        case .stocks: return 1.0
        case .forex: return 30.0
        case .metals: return 20.0
        case .indices: return 20.0
        }
    }
}

public struct DemoOrderRequest: Codable, Sendable, Equatable {
    public let id: String
    public let signalId: String?
    public let symbol: String
    public let marketClass: MarketClass
    public let timeframe: Timeframe
    public let direction: TradeDirection
    public let orderType: DemoOrderType
    public let entryPrice: Double
    public let entryLow: Double
    public let entryHigh: Double
    public let stopLoss: Double
    public let target1: Double
    public let target2: Double?
    public let exitTarget: DemoExitTarget
    public let riskPercent: Double
    public let leverage: Double?
    public let contractSpec: InstrumentContractSpec?
    public let limitExpiryEpochSeconds: TimeInterval?
    public let allowStalePriceFill: Bool
    public let feesEnabled: Bool

    public init(
        id: String = UUID().uuidString,
        signalId: String? = nil,
        symbol: String,
        marketClass: MarketClass,
        timeframe: Timeframe = .h1,
        direction: TradeDirection,
        orderType: DemoOrderType,
        entryPrice: Double,
        entryLow: Double? = nil,
        entryHigh: Double? = nil,
        stopLoss: Double,
        target1: Double,
        target2: Double? = nil,
        exitTarget: DemoExitTarget = .target1,
        riskPercent: Double = 1.0,
        leverage: Double? = nil,
        contractSpec: InstrumentContractSpec? = nil,
        limitExpiryEpochSeconds: TimeInterval? = nil,
        allowStalePriceFill: Bool = false,
        feesEnabled: Bool = false
    ) {
        self.id = id
        self.signalId = signalId
        self.symbol = symbol
        self.marketClass = marketClass
        self.timeframe = timeframe
        self.direction = direction
        self.orderType = orderType
        self.entryPrice = entryPrice
        self.entryLow = entryLow ?? entryPrice
        self.entryHigh = entryHigh ?? entryPrice
        self.stopLoss = stopLoss
        self.target1 = target1
        self.target2 = target2
        self.exitTarget = exitTarget
        self.riskPercent = riskPercent
        self.leverage = leverage
        self.contractSpec = contractSpec
        self.limitExpiryEpochSeconds = limitExpiryEpochSeconds
        self.allowStalePriceFill = allowStalePriceFill
        self.feesEnabled = feesEnabled
    }
}

public struct DemoPosition: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let signalId: String?
    public let symbol: String
    public let marketClass: MarketClass
    public let timeframe: Timeframe
    public let direction: TradeDirection
    public let orderType: DemoOrderType
    public let createdAtEpochSeconds: TimeInterval
    /// Planned entry (or exact filled entry once opened).
    public var entryPrice: Double
    public let entryLow: Double
    public let entryHigh: Double
    /// Immutable once filled (no synthetic spread invented).
    public var filledPrice: Double?
    public var filledAtEpochSeconds: TimeInterval?
    /// Open time of the closed bar on which a limit filled (enforces fill-bar SL-only rule).
    public var fillBarOpenEpochSeconds: TimeInterval?
    public let limitExpiryEpochSeconds: TimeInterval?
    public var stopLoss: Double
    public let initialStopLoss: Double
    public var target1: Double
    public var target2: Double?
    public var exitTarget: DemoExitTarget
    public var isStopLossAtBreakeven: Bool
    /// Primary quantity (lots for FX/Metals, contracts for Indices, units/shares for Crypto/Stocks).
    public let quantity: Double
    public let unitLabel: String
    public let contractSpec: InstrumentContractSpec
    public let leverage: Double
    public let marginReservedUSD: Double
    public let wasClampedToFreeMargin: Bool
    public let feesEnabled: Bool
    public var status: DemoPositionStatus
    /// Immutable once closed.
    public var exitPrice: Double?
    public var closedAtEpochSeconds: TimeInterval?
    public var realizedPnLUSD: Double
    public var feesPaidUSD: Double
    public var rMultiple: Double

    public init(
        id: String,
        signalId: String?,
        symbol: String,
        marketClass: MarketClass,
        timeframe: Timeframe,
        direction: TradeDirection,
        orderType: DemoOrderType,
        createdAtEpochSeconds: TimeInterval,
        entryPrice: Double,
        entryLow: Double,
        entryHigh: Double,
        filledPrice: Double?,
        filledAtEpochSeconds: TimeInterval?,
        fillBarOpenEpochSeconds: TimeInterval?,
        limitExpiryEpochSeconds: TimeInterval?,
        stopLoss: Double,
        initialStopLoss: Double,
        target1: Double,
        target2: Double?,
        exitTarget: DemoExitTarget,
        isStopLossAtBreakeven: Bool,
        quantity: Double,
        unitLabel: String,
        contractSpec: InstrumentContractSpec,
        leverage: Double,
        marginReservedUSD: Double,
        wasClampedToFreeMargin: Bool,
        feesEnabled: Bool,
        status: DemoPositionStatus,
        exitPrice: Double? = nil,
        closedAtEpochSeconds: TimeInterval? = nil,
        realizedPnLUSD: Double = 0,
        feesPaidUSD: Double = 0,
        rMultiple: Double = 0
    ) {
        self.id = id
        self.signalId = signalId
        self.symbol = symbol
        self.marketClass = marketClass
        self.timeframe = timeframe
        self.direction = direction
        self.orderType = orderType
        self.createdAtEpochSeconds = createdAtEpochSeconds
        self.entryPrice = entryPrice
        self.entryLow = entryLow
        self.entryHigh = entryHigh
        self.filledPrice = filledPrice
        self.filledAtEpochSeconds = filledAtEpochSeconds
        self.fillBarOpenEpochSeconds = fillBarOpenEpochSeconds
        self.limitExpiryEpochSeconds = limitExpiryEpochSeconds
        self.stopLoss = stopLoss
        self.initialStopLoss = initialStopLoss
        self.target1 = target1
        self.target2 = target2
        self.exitTarget = exitTarget
        self.isStopLossAtBreakeven = isStopLossAtBreakeven
        self.quantity = quantity
        self.unitLabel = unitLabel
        self.contractSpec = contractSpec
        self.leverage = leverage
        self.marginReservedUSD = marginReservedUSD
        self.wasClampedToFreeMargin = wasClampedToFreeMargin
        self.feesEnabled = feesEnabled
        self.status = status
        self.exitPrice = exitPrice
        self.closedAtEpochSeconds = closedAtEpochSeconds
        self.realizedPnLUSD = realizedPnLUSD
        self.feesPaidUSD = feesPaidUSD
        self.rMultiple = rMultiple
    }

    public var activeTargetPrice: Double {
        switch exitTarget {
        case .target1: return target1
        case .target2: return target2 ?? target1
        }
    }

    public var initialRiskDistance: Double {
        abs((filledPrice ?? entryPrice) - initialStopLoss)
    }
}

public struct DemoWalletTransaction: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let timestampEpochSeconds: TimeInterval
    public let kind: DemoTransactionKind
    public let symbol: String?
    public let positionId: String?
    public let amountUSD: Double
    public let balanceAfterUSD: Double
    public let note: String

    public init(
        id: String = UUID().uuidString,
        timestampEpochSeconds: TimeInterval,
        kind: DemoTransactionKind,
        symbol: String? = nil,
        positionId: String? = nil,
        amountUSD: Double,
        balanceAfterUSD: Double,
        note: String
    ) {
        self.id = id
        self.timestampEpochSeconds = timestampEpochSeconds
        self.kind = kind
        self.symbol = symbol
        self.positionId = positionId
        self.amountUSD = amountUSD
        self.balanceAfterUSD = balanceAfterUSD
        self.note = note
    }
}

public struct DemoWallet: Codable, Sendable, Equatable {
    public static let defaultStartingBalanceUSD: Double = 1_000.0

    public var startingBalanceUSD: Double
    public var cashBalanceUSD: Double
    public var reservedMarginUSD: Double
    public var realizedPnLUSD: Double
    public var totalFeesPaidUSD: Double
    public var positions: [DemoPosition]
    public var transactions: [DemoWalletTransaction]

    public init(
        startingBalanceUSD: Double = defaultStartingBalanceUSD,
        cashBalanceUSD: Double? = nil,
        reservedMarginUSD: Double = 0,
        realizedPnLUSD: Double = 0,
        totalFeesPaidUSD: Double = 0,
        positions: [DemoPosition] = [],
        transactions: [DemoWalletTransaction] = []
    ) {
        self.startingBalanceUSD = startingBalanceUSD
        self.cashBalanceUSD = cashBalanceUSD ?? startingBalanceUSD
        self.reservedMarginUSD = reservedMarginUSD
        self.realizedPnLUSD = realizedPnLUSD
        self.totalFeesPaidUSD = totalFeesPaidUSD
        self.positions = positions
        self.transactions = transactions
    }

    public var freeMarginUSD: Double {
        max(0.0, cashBalanceUSD - reservedMarginUSD)
    }

    public var activePositions: [DemoPosition] {
        positions.filter { $0.status.isActive }
    }

    public var closedPositions: [DemoPosition] {
        positions.filter { $0.status.isClosed }
    }

    public func totalUnrealizedPnLUSD(livePrices: [String: Double]) -> Double {
        positions
            .filter { $0.status == .open }
            .reduce(0.0) { acc, pos in
                guard let price = livePrices[pos.symbol], price.isFinite, price > 0 else { return acc }
                return acc + DemoWalletEngine.pnlUSD(for: pos, markPrice: price)
            }
    }

    public func totalEquityUSD(livePrices: [String: Double]) -> Double {
        cashBalanceUSD + totalUnrealizedPnLUSD(livePrices: livePrices)
    }
}

/// Pure-Swift paper-trading wallet engine.
/// Strictly simulated — never executes brokerage orders, never invents synthetic spreads,
/// enforces market-open & live-quote staleness guards on Market fills, and applies the
/// same pessimistic fill-bar SL-only / same-bar SL-first rules as `PassiveOutcomeEvaluator`.
public enum DemoWalletEngine {
    public static let maxMarketQuoteAgeSeconds: TimeInterval = 60.0

    // MARK: - Asset-Class Exact Notional & P&L Math

    public static func notionalUSD(
        symbol: String,
        marketClass: MarketClass,
        price: Double,
        quantity: Double,
        contractSpec: InstrumentContractSpec
    ) -> Double {
        guard price.isFinite, price > 0, quantity.isFinite, quantity > 0 else { return 0 }
        let upper = symbol.uppercased()
        switch marketClass {
        case .forex:
            let units = quantity * max(contractSpec.contractSize, 1.0)
            if upper.hasPrefix("USD/") || (upper.hasPrefix("USD") && !upper.hasSuffix("USD")) {
                return units
            }
            return units * price
        case .metals:
            let ounces = quantity * max(contractSpec.contractSize, 1.0)
            return ounces * price
        case .indices:
            if upper == "SPY" || upper == "QQQ" {
                return quantity * price
            }
            let dollarPerPoint = max(contractSpec.contractSize, 1e-6) * max(contractSpec.pointValue, 1e-6)
            return quantity * price * dollarPerPoint
        case .crypto, .stocks:
            return quantity * price
        }
    }

    /// Exact simulated USD P&L between a position's fill/entry price and a mark or exit price.
    public static func pnlUSD(for position: DemoPosition, markPrice: Double) -> Double {
        let entry = position.filledPrice ?? position.entryPrice
        guard entry.isFinite, entry > 0, markPrice.isFinite, markPrice > 0 else { return 0 }
        let signedDelta: Double = (position.direction == .long)
            ? (markPrice - entry)
            : (entry - markPrice)
        let upper = position.symbol.uppercased()
        let spec = position.contractSpec

        switch position.marketClass {
        case .forex:
            let units = position.quantity * max(spec.contractSize, 1.0)
            if upper.hasPrefix("USD/") || (upper.hasPrefix("USD") && !upper.hasSuffix("USD")) {
                return (units * signedDelta) / max(markPrice, 1e-9)
            }
            return units * signedDelta
        case .metals:
            let ounces = position.quantity * max(spec.contractSize, 1.0)
            return ounces * signedDelta
        case .indices:
            if upper == "SPY" || upper == "QQQ" {
                return position.quantity * signedDelta
            }
            let dollarPerPoint = max(spec.contractSize, 1e-6) * max(spec.pointValue, 1e-6)
            return position.quantity * signedDelta * dollarPerPoint
        case .crypto, .stocks:
            return position.quantity * signedDelta
        }
    }

    public static func rMultiple(for position: DemoPosition, markPrice: Double) -> Double {
        let entry = position.filledPrice ?? position.entryPrice
        let riskDist = abs(entry - position.initialStopLoss)
        guard riskDist > 1e-12 else { return 0 }
        let signedDelta = (position.direction == .long) ? (markPrice - entry) : (entry - markPrice)
        return signedDelta / riskDist
    }

    public static func returnPercentOnMargin(for position: DemoPosition, markPrice: Double) -> Double {
        guard position.marginReservedUSD > 1e-9 else { return 0 }
        return (pnlUSD(for: position, markPrice: markPrice) / position.marginReservedUSD) * 100.0
    }

    // MARK: - Order Placement & Validation

    public static func validateLevels(
        direction: TradeDirection,
        entryPrice: Double,
        stopLoss: Double,
        target1: Double,
        target2: Double?,
        allowBreakevenStop: Bool = false
    ) -> Result<Void, DemoOrderRejectionReason> {
        guard direction == .long || direction == .short else {
            return .failure(.invalidDirection)
        }
        guard entryPrice.isFinite, entryPrice > 0,
              stopLoss.isFinite, stopLoss > 0,
              target1.isFinite, target1 > 0
        else {
            return .failure(.invalidPrices("Entry, stop loss, and target 1 must be positive numbers."))
        }
        if let t2 = target2, (!t2.isFinite || t2 <= 0) {
            return .failure(.invalidPrices("Target 2 must be a positive number."))
        }

        if direction == .long {
            let slValid = allowBreakevenStop ? (stopLoss <= entryPrice) : (stopLoss < entryPrice)
            guard slValid else {
                return .failure(.invalidPrices("Stop loss must be below entry for a Long trade."))
            }
            guard target1 > entryPrice else {
                return .failure(.invalidPrices("Target 1 must be above entry for a Long trade."))
            }
            if let t2 = target2, t2 <= target1 {
                return .failure(.invalidPrices("Target 2 must be above Target 1 for a Long trade."))
            }
        } else {
            let slValid = allowBreakevenStop ? (stopLoss >= entryPrice) : (stopLoss > entryPrice)
            guard slValid else {
                return .failure(.invalidPrices("Stop loss must be above entry for a Short trade."))
            }
            guard target1 < entryPrice else {
                return .failure(.invalidPrices("Target 1 must be below entry for a Short trade."))
            }
            if let t2 = target2, t2 >= target1 {
                return .failure(.invalidPrices("Target 2 must be below Target 1 for a Short trade."))
            }
        }
        return .success(())
    }

    public static func placeOrder(
        wallet: DemoWallet,
        request: DemoOrderRequest,
        liveQuotePrice: Double?,
        liveQuoteEpochSeconds: TimeInterval?,
        nowEpochSeconds: TimeInterval,
        asset: AssetDescriptor? = nil
    ) -> Result<(DemoWallet, DemoPosition), DemoOrderRejectionReason> {
        guard request.direction == .long || request.direction == .short else {
            return .failure(.invalidDirection)
        }

        let effectiveEntry: Double
        if request.orderType == .market {
            // Safeguard 1: Block Market fills while market is closed; offer Limit order instead.
            let resolvedAsset = asset ?? WatchlistDefaults.descriptor(for: request.symbol)
            let sessionStatus: MarketSessionStatus
            if let resolvedAsset {
                sessionStatus = SessionCalendar.sessionStatus(asset: resolvedAsset, at: nowEpochSeconds)
            } else {
                sessionStatus = SessionCalendar.sessionStatus(marketClass: request.marketClass, at: nowEpochSeconds)
            }
            if !sessionStatus.isOpen {
                return .failure(.marketClosed(
                    reason: sessionStatus.closedReason ?? "Market is closed.",
                    suggestLimit: true
                ))
            }

            // Safeguard 2: Reject Market fills if live quote is older than 60s unless user explicitly confirms.
            guard let livePrice = liveQuotePrice, livePrice.isFinite, livePrice > 0 else {
                return .failure(.staleLiveQuote(ageSeconds: maxMarketQuoteAgeSeconds + 1))
            }
            let age = liveQuoteEpochSeconds.map { max(0, nowEpochSeconds - $0) } ?? (maxMarketQuoteAgeSeconds + 1)
            if age > maxMarketQuoteAgeSeconds && !request.allowStalePriceFill {
                return .failure(.staleLiveQuote(ageSeconds: age))
            }
            // Clean fill at observed live price — never invent synthetic bid/ask spreads.
            effectiveEntry = livePrice
        } else {
            effectiveEntry = request.entryPrice
        }

        if case .failure(let err) = validateLevels(
            direction: request.direction,
            entryPrice: effectiveEntry,
            stopLoss: request.stopLoss,
            target1: request.target1,
            target2: request.target2
        ) {
            return .failure(err)
        }

        guard wallet.freeMarginUSD > 1e-6 else {
            return .failure(.insufficientFreeMargin)
        }

        let spec = request.contractSpec ?? InstrumentContractSpec.defaultSpec(
            for: request.symbol,
            marketClass: request.marketClass
        )
        let leverage = max(1.0, request.leverage ?? DemoMarginSpec.defaultLeverage(for: request.marketClass))

        let sizeInput = PositionSizeInput(
            symbol: request.symbol,
            marketClass: request.marketClass,
            entryPrice: effectiveEntry,
            stopLossPrice: request.stopLoss,
            tp1Price: request.target1,
            accountBalance: max(wallet.cashBalanceUSD, 1.0),
            riskPercent: max(0.1, min(request.riskPercent, 25.0)),
            accountCurrency: .usd,
            usdToAccountRate: 1.0,
            contractSpec: spec
        )
        guard let sizing = PositionSizeCalculator.calculate(sizeInput),
              sizing.primaryQuantity.isFinite, sizing.primaryQuantity > 0
        else {
            return .failure(.invalidQuantity)
        }

        var quantity = sizing.primaryQuantity
        let rawNotional = notionalUSD(
            symbol: request.symbol,
            marketClass: request.marketClass,
            price: effectiveEntry,
            quantity: quantity,
            contractSpec: spec
        )
        var requiredMargin = rawNotional / leverage
        var wasClamped = false

        if requiredMargin > wallet.freeMarginUSD {
            let scale = wallet.freeMarginUSD / max(requiredMargin, 1e-9)
            quantity *= scale
            requiredMargin = wallet.freeMarginUSD
            wasClamped = true
        }
        guard quantity > 1e-10, requiredMargin > 1e-6 else {
            return .failure(.insufficientFreeMargin)
        }

        let isMarket = request.orderType == .market
        let position = DemoPosition(
            id: request.id,
            signalId: request.signalId,
            symbol: request.symbol,
            marketClass: request.marketClass,
            timeframe: request.timeframe,
            direction: request.direction,
            orderType: request.orderType,
            createdAtEpochSeconds: nowEpochSeconds,
            entryPrice: effectiveEntry,
            entryLow: min(request.entryLow, request.entryHigh),
            entryHigh: max(request.entryLow, request.entryHigh),
            filledPrice: isMarket ? effectiveEntry : nil,
            filledAtEpochSeconds: isMarket ? nowEpochSeconds : nil,
            fillBarOpenEpochSeconds: nil,
            limitExpiryEpochSeconds: isMarket ? nil : request.limitExpiryEpochSeconds,
            stopLoss: request.stopLoss,
            initialStopLoss: request.stopLoss,
            target1: request.target1,
            target2: request.target2,
            exitTarget: request.exitTarget,
            isStopLossAtBreakeven: false,
            quantity: quantity,
            unitLabel: sizing.primaryUnitLabel,
            contractSpec: spec,
            leverage: leverage,
            marginReservedUSD: requiredMargin,
            wasClampedToFreeMargin: wasClamped,
            feesEnabled: request.feesEnabled,
            status: isMarket ? .open : .pendingLimit
        )

        var updated = wallet
        updated.reservedMarginUSD += requiredMargin
        updated.positions.insert(position, at: 0)
        updated.transactions.append(
            DemoWalletTransaction(
                timestampEpochSeconds: nowEpochSeconds,
                kind: .marginReserved,
                symbol: position.symbol,
                positionId: position.id,
                amountUSD: -requiredMargin,
                balanceAfterUSD: updated.cashBalanceUSD,
                note: "\(isMarket ? "Market" : "Limit") \(position.direction.rawValue.uppercased()) \(position.symbol) (\(String(format: "%.0f", leverage))x)"
            )
        )
        return .success((updated, position))
    }

    // MARK: - Closed-Bar & Live-Tick Evaluation (Pessimistic Rules)

    /// Evaluates a single closed bar against a demo position using the v1.4 pessimistic lifecycle rules:
    /// - Pending limit fills if bar intersects `[entryLow, entryHigh]` (or expires if past `limitExpiryEpochSeconds`).
    /// - **Fill-Bar Rule:** On the fill bar itself, check Stop loss ONLY; target checks start on the NEXT closed bar.
    /// - **Same-Bar Rule:** On post-fill bars, if both Stop loss and Target are touched, resolve pessimistically as Stop loss first.
    public static func evaluateClosedBar(
        wallet: DemoWallet,
        positionId: String,
        bar: Candle
    ) -> (wallet: DemoWallet, position: DemoPosition?, didChange: Bool) {
        guard bar.isClosed,
              let idx = wallet.positions.firstIndex(where: { $0.id == positionId })
        else {
            return (wallet, nil, false)
        }

        var updated = wallet
        var pos = updated.positions[idx]
        guard pos.status.isActive else { return (wallet, pos, false) }

        if pos.status == .pendingLimit {
            if let expiry = pos.limitExpiryEpochSeconds, bar.openTimeEpochSeconds >= expiry {
                pos.status = .expired
                pos.closedAtEpochSeconds = bar.closeTimeEpochSeconds
                updated.reservedMarginUSD = max(0, updated.reservedMarginUSD - pos.marginReservedUSD)
                updated.positions[idx] = pos
                updated.transactions.append(
                    DemoWalletTransaction(
                        timestampEpochSeconds: bar.closeTimeEpochSeconds,
                        kind: .marginReleased,
                        symbol: pos.symbol,
                        positionId: pos.id,
                        amountUSD: pos.marginReservedUSD,
                        balanceAfterUSD: updated.cashBalanceUSD,
                        note: "Limit order expired without fill (\(pos.symbol))"
                    )
                )
                return (updated, pos, true)
            }

            let touchedZone = (bar.low <= pos.entryHigh && bar.high >= pos.entryLow)
            guard touchedZone else { return (wallet, pos, false) }

            pos.status = .open
            pos.filledPrice = pos.entryPrice
            pos.filledAtEpochSeconds = bar.closeTimeEpochSeconds
            pos.fillBarOpenEpochSeconds = bar.openTimeEpochSeconds

            // Fill-Bar Rule: check Stop loss ONLY on the fill bar (pessimistic).
            let slHitOnFillBar = (pos.direction == .long)
                ? (bar.low <= pos.stopLoss)
                : (bar.high >= pos.stopLoss)
            if slHitOnFillBar {
                let (w2, closed) = settleClose(
                    wallet: updated,
                    positionIndex: idx,
                    position: pos,
                    exitPrice: pos.stopLoss,
                    status: .closedStopLoss,
                    closedAt: bar.closeTimeEpochSeconds
                )
                return (w2, closed, true)
            }

            updated.positions[idx] = pos
            return (updated, pos, true)
        }

        // Open position: strictly skip target checks if still evaluating the fill bar
        if let fillBarOpen = pos.fillBarOpenEpochSeconds, bar.openTimeEpochSeconds <= fillBarOpen {
            let slHit = (pos.direction == .long) ? (bar.low <= pos.stopLoss) : (bar.high >= pos.stopLoss)
            if slHit {
                let (w2, closed) = settleClose(
                    wallet: updated,
                    positionIndex: idx,
                    position: pos,
                    exitPrice: pos.stopLoss,
                    status: .closedStopLoss,
                    closedAt: bar.closeTimeEpochSeconds
                )
                return (w2, closed, true)
            }
            return (wallet, pos, false)
        }

        // Post-fill bar: Pessimistic Same-Bar SL-First Resolution
        let slTouched = (pos.direction == .long)
            ? (bar.low <= pos.stopLoss)
            : (bar.high >= pos.stopLoss)
        if slTouched {
            let (w2, closed) = settleClose(
                wallet: updated,
                positionIndex: idx,
                position: pos,
                exitPrice: pos.stopLoss,
                status: .closedStopLoss,
                closedAt: bar.closeTimeEpochSeconds
            )
            return (w2, closed, true)
        }

        let targetPrice = pos.activeTargetPrice
        let targetTouched = (pos.direction == .long)
            ? (bar.high >= targetPrice)
            : (bar.low <= targetPrice)
        if targetTouched {
            let closeStatus: DemoPositionStatus = (pos.exitTarget == .target2 && pos.target2 != nil)
                ? .closedTarget2
                : .closedTarget1
            let (w2, closed) = settleClose(
                wallet: updated,
                positionIndex: idx,
                position: pos,
                exitPrice: targetPrice,
                status: closeStatus,
                closedAt: bar.closeTimeEpochSeconds
            )
            return (w2, closed, true)
        }

        return (wallet, pos, false)
    }

    /// Evaluates a live tick against an open/pending demo position (foreground monitor).
    /// Always checks Stop loss before Target, never invents spread, and writes exact trigger level as exit price.
    public static func evaluateLiveTick(
        wallet: DemoWallet,
        positionId: String,
        tickPrice: Double,
        tickEpochSeconds: TimeInterval
    ) -> (wallet: DemoWallet, position: DemoPosition?, didChange: Bool) {
        guard tickPrice.isFinite, tickPrice > 0,
              let idx = wallet.positions.firstIndex(where: { $0.id == positionId })
        else {
            return (wallet, nil, false)
        }

        var updated = wallet
        var pos = updated.positions[idx]
        guard pos.status.isActive else { return (wallet, pos, false) }

        if pos.status == .pendingLimit {
            if let expiry = pos.limitExpiryEpochSeconds, tickEpochSeconds >= expiry {
                pos.status = .expired
                pos.closedAtEpochSeconds = tickEpochSeconds
                updated.reservedMarginUSD = max(0, updated.reservedMarginUSD - pos.marginReservedUSD)
                updated.positions[idx] = pos
                updated.transactions.append(
                    DemoWalletTransaction(
                        timestampEpochSeconds: tickEpochSeconds,
                        kind: .marginReleased,
                        symbol: pos.symbol,
                        positionId: pos.id,
                        amountUSD: pos.marginReservedUSD,
                        balanceAfterUSD: updated.cashBalanceUSD,
                        note: "Limit order expired without fill (\(pos.symbol))"
                    )
                )
                return (updated, pos, true)
            }
            if tickPrice >= pos.entryLow && tickPrice <= pos.entryHigh {
                pos.status = .open
                pos.filledPrice = pos.entryPrice
                pos.filledAtEpochSeconds = tickEpochSeconds
                updated.positions[idx] = pos
                return (updated, pos, true)
            }
            return (wallet, pos, false)
        }

        let slHit = (pos.direction == .long) ? (tickPrice <= pos.stopLoss) : (tickPrice >= pos.stopLoss)
        if slHit {
            let (w2, closed) = settleClose(
                wallet: updated,
                positionIndex: idx,
                position: pos,
                exitPrice: pos.stopLoss,
                status: .closedStopLoss,
                closedAt: tickEpochSeconds
            )
            return (w2, closed, true)
        }

        let targetPrice = pos.activeTargetPrice
        let targetHit = (pos.direction == .long) ? (tickPrice >= targetPrice) : (tickPrice <= targetPrice)
        if targetHit {
            let closeStatus: DemoPositionStatus = (pos.exitTarget == .target2 && pos.target2 != nil)
                ? .closedTarget2
                : .closedTarget1
            let (w2, closed) = settleClose(
                wallet: updated,
                positionIndex: idx,
                position: pos,
                exitPrice: targetPrice,
                status: closeStatus,
                closedAt: tickEpochSeconds
            )
            return (w2, closed, true)
        }

        return (wallet, pos, false)
    }

    // MARK: - Position Management (Close, Edit SL/Targets, Breakeven, Balance)

    public static func closePositionManually(
        wallet: DemoWallet,
        positionId: String,
        exitPrice: Double,
        nowEpochSeconds: TimeInterval
    ) -> (wallet: DemoWallet, position: DemoPosition)? {
        guard exitPrice.isFinite, exitPrice > 0,
              let idx = wallet.positions.firstIndex(where: { $0.id == positionId })
        else { return nil }

        var updated = wallet
        var pos = updated.positions[idx]
        guard pos.status.isActive else { return nil }

        if pos.status == .pendingLimit {
            pos.status = .cancelled
            pos.closedAtEpochSeconds = nowEpochSeconds
            updated.reservedMarginUSD = max(0, updated.reservedMarginUSD - pos.marginReservedUSD)
            updated.positions[idx] = pos
            updated.transactions.append(
                DemoWalletTransaction(
                    timestampEpochSeconds: nowEpochSeconds,
                    kind: .marginReleased,
                    symbol: pos.symbol,
                    positionId: pos.id,
                    amountUSD: pos.marginReservedUSD,
                    balanceAfterUSD: updated.cashBalanceUSD,
                    note: "Cancelled pending limit (\(pos.symbol))"
                )
            )
            return (updated, pos)
        }

        return settleClose(
            wallet: updated,
            positionIndex: idx,
            position: pos,
            exitPrice: exitPrice,
            status: .closedManual,
            closedAt: nowEpochSeconds
        )
    }

    public static func updateStopLoss(
        wallet: DemoWallet,
        positionId: String,
        newStopLoss: Double
    ) -> Result<(DemoWallet, DemoPosition), DemoOrderRejectionReason> {
        guard let idx = wallet.positions.firstIndex(where: { $0.id == positionId }) else {
            return .failure(.positionNotFound)
        }
        var updated = wallet
        var pos = updated.positions[idx]
        guard pos.status.isActive else {
            return .failure(.invalidState("Cannot edit stop loss on a closed position."))
        }
        let refEntry = pos.filledPrice ?? pos.entryPrice
        if case .failure(let err) = validateLevels(
            direction: pos.direction,
            entryPrice: refEntry,
            stopLoss: newStopLoss,
            target1: pos.target1,
            target2: pos.target2,
            allowBreakevenStop: true
        ) {
            return .failure(err)
        }

        pos.stopLoss = newStopLoss
        pos.isStopLossAtBreakeven = abs(newStopLoss - refEntry) <= max(1e-9, refEntry * 1e-7)
        updated.positions[idx] = pos
        return .success((updated, pos))
    }

    public static func updateTargets(
        wallet: DemoWallet,
        positionId: String,
        newTarget1: Double,
        newTarget2: Double?,
        newExitTarget: DemoExitTarget? = nil
    ) -> Result<(DemoWallet, DemoPosition), DemoOrderRejectionReason> {
        guard let idx = wallet.positions.firstIndex(where: { $0.id == positionId }) else {
            return .failure(.positionNotFound)
        }
        var updated = wallet
        var pos = updated.positions[idx]
        guard pos.status.isActive else {
            return .failure(.invalidState("Cannot edit targets on a closed position."))
        }
        let refEntry = pos.filledPrice ?? pos.entryPrice
        if case .failure(let err) = validateLevels(
            direction: pos.direction,
            entryPrice: refEntry,
            stopLoss: pos.stopLoss,
            target1: newTarget1,
            target2: newTarget2,
            allowBreakevenStop: true
        ) {
            return .failure(err)
        }

        pos.target1 = newTarget1
        pos.target2 = newTarget2
        if let choice = newExitTarget {
            pos.exitTarget = (choice == .target2 && newTarget2 == nil) ? .target1 : choice
        }
        updated.positions[idx] = pos
        return .success((updated, pos))
    }

    public static func moveStopLossToBreakeven(
        wallet: DemoWallet,
        positionId: String
    ) -> Result<(DemoWallet, DemoPosition), DemoOrderRejectionReason> {
        guard let idx = wallet.positions.firstIndex(where: { $0.id == positionId }) else {
            return .failure(.positionNotFound)
        }
        let pos = wallet.positions[idx]
        guard pos.status == .open, let fill = pos.filledPrice else {
            return .failure(.invalidState("Breakeven stop loss is only available for open filled positions."))
        }
        return updateStopLoss(wallet: wallet, positionId: positionId, newStopLoss: fill)
    }

    public static func adjustBalance(
        wallet: DemoWallet,
        newBalanceUSD: Double,
        nowEpochSeconds: TimeInterval
    ) -> DemoWallet {
        guard newBalanceUSD.isFinite, newBalanceUSD >= wallet.reservedMarginUSD else { return wallet }
        var updated = wallet
        let delta = newBalanceUSD - updated.cashBalanceUSD
        updated.cashBalanceUSD = newBalanceUSD
        updated.transactions.append(
            DemoWalletTransaction(
                timestampEpochSeconds: nowEpochSeconds,
                kind: .balanceAdjustment,
                symbol: nil,
                positionId: nil,
                amountUSD: delta,
                balanceAfterUSD: newBalanceUSD,
                note: "Manual demo balance adjustment"
            )
        )
        return updated
    }

    // MARK: - Internal Settlement

    private static func settleClose(
        wallet: DemoWallet,
        positionIndex: Int,
        position: DemoPosition,
        exitPrice: Double,
        status: DemoPositionStatus,
        closedAt: TimeInterval
    ) -> (DemoWallet, DemoPosition) {
        var updated = wallet
        var pos = position

        let grossPnL = pnlUSD(for: pos, markPrice: exitPrice)
        let notional = notionalUSD(
            symbol: pos.symbol,
            marketClass: pos.marketClass,
            price: pos.filledPrice ?? pos.entryPrice,
            quantity: pos.quantity,
            contractSpec: pos.contractSpec
        )
        let feeUSD: Double = pos.feesEnabled
            ? notional * (pos.marketClass.defaultRoundTripCostBps / 10_000.0)
            : 0.0
        let netPnL = grossPnL - feeUSD

        pos.status = status
        pos.exitPrice = exitPrice
        pos.closedAtEpochSeconds = closedAt
        pos.realizedPnLUSD = netPnL
        pos.feesPaidUSD = feeUSD
        pos.rMultiple = rMultiple(for: pos, markPrice: exitPrice)

        updated.reservedMarginUSD = max(0.0, updated.reservedMarginUSD - pos.marginReservedUSD)
        updated.cashBalanceUSD += netPnL
        updated.realizedPnLUSD += netPnL
        updated.totalFeesPaidUSD += feeUSD
        updated.positions[positionIndex] = pos

        updated.transactions.append(
            DemoWalletTransaction(
                timestampEpochSeconds: closedAt,
                kind: .marginReleased,
                symbol: pos.symbol,
                positionId: pos.id,
                amountUSD: pos.marginReservedUSD,
                balanceAfterUSD: updated.cashBalanceUSD,
                note: "Margin released on \(status.rawValue) (\(pos.symbol))"
            )
        )
        updated.transactions.append(
            DemoWalletTransaction(
                timestampEpochSeconds: closedAt,
                kind: .realizedPnL,
                symbol: pos.symbol,
                positionId: pos.id,
                amountUSD: grossPnL,
                balanceAfterUSD: updated.cashBalanceUSD,
                note: "Closed \(pos.symbol) @ \(String(format: "%.5g", exitPrice)) (\(status.rawValue))"
            )
        )
        if feeUSD > 0 {
            updated.transactions.append(
                DemoWalletTransaction(
                    timestampEpochSeconds: closedAt,
                    kind: .fee,
                    symbol: pos.symbol,
                    positionId: pos.id,
                    amountUSD: -feeUSD,
                    balanceAfterUSD: updated.cashBalanceUSD,
                    note: "Simulated fee (\(pos.marketClass.displayName))"
                )
            )
        }
        return (updated, pos)
    }
}
