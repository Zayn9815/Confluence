import Foundation

// MARK: - Plain-English Order Flow Narrative Models

public enum OrderFlowEventTone: String, Codable, Sendable, Equatable, Hashable {
    case bullish
    case bearish
    case neutral
    case warning
    case unavailable
}

public struct OrderFlowEventCard: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let statusLabel: String
    public let detail: String
    public let tone: OrderFlowEventTone
    public let isEvaluated: Bool

    public init(
        id: String,
        title: String,
        statusLabel: String,
        detail: String,
        tone: OrderFlowEventTone,
        isEvaluated: Bool
    ) {
        self.id = id
        self.title = title
        self.statusLabel = statusLabel
        self.detail = detail
        self.tone = tone
        self.isEvaluated = isEvaluated
    }
}

public struct OrderFlowWallComparison: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let side: String
    public let price: Double
    public let formattedPrice: String
    public let distanceBps: Double?
    public let sizeMultiple: Double?
    public let isConfirmed: Bool
    public let statusBadge: String
    public let levelRelation: String
    public let isBlockingTarget: Bool

    public init(
        id: String,
        side: String,
        price: Double,
        formattedPrice: String,
        distanceBps: Double?,
        sizeMultiple: Double?,
        isConfirmed: Bool,
        statusBadge: String,
        levelRelation: String,
        isBlockingTarget: Bool
    ) {
        self.id = id
        self.side = side
        self.price = price
        self.formattedPrice = formattedPrice
        self.distanceBps = distanceBps
        self.sizeMultiple = sizeMultiple
        self.isConfirmed = isConfirmed
        self.statusBadge = statusBadge
        self.levelRelation = levelRelation
        self.isBlockingTarget = isBlockingTarget
    }
}

public struct OrderFlowNarrative: Codable, Sendable, Equatable, Hashable {
    public let heroVerdict: String
    public let alignment: String
    public let venue: String
    public let isLiveStream: Bool
    public let spreadBps: Double?
    public let obiWeighted: Double
    public let cvdRatio: Double
    public let bidPressureFraction: Double
    public let aggressiveBuyFraction: Double
    public let restingBookSummary: String
    public let aggressiveFlowSummary: String
    public let eventCards: [OrderFlowEventCard]
    public let wallLevelComparisons: [OrderFlowWallComparison]
    public let actionableTakeaway: String
    public let capturedAtEpochSeconds: TimeInterval?

    public init(
        heroVerdict: String,
        alignment: String,
        venue: String,
        isLiveStream: Bool,
        spreadBps: Double?,
        obiWeighted: Double,
        cvdRatio: Double,
        bidPressureFraction: Double,
        aggressiveBuyFraction: Double,
        restingBookSummary: String,
        aggressiveFlowSummary: String,
        eventCards: [OrderFlowEventCard],
        wallLevelComparisons: [OrderFlowWallComparison],
        actionableTakeaway: String,
        capturedAtEpochSeconds: TimeInterval?
    ) {
        self.heroVerdict = heroVerdict
        self.alignment = alignment
        self.venue = venue
        self.isLiveStream = isLiveStream
        self.spreadBps = spreadBps
        self.obiWeighted = obiWeighted
        self.cvdRatio = cvdRatio
        self.bidPressureFraction = bidPressureFraction
        self.aggressiveBuyFraction = aggressiveBuyFraction
        self.restingBookSummary = restingBookSummary
        self.aggressiveFlowSummary = aggressiveFlowSummary
        self.eventCards = eventCards
        self.wallLevelComparisons = wallLevelComparisons
        self.actionableTakeaway = actionableTakeaway
        self.capturedAtEpochSeconds = capturedAtEpochSeconds
    }
}

// MARK: - Pure-Swift Plain-English Order Flow Narrative Builder

public enum OrderFlowNarrativeBuilder {
    public static let restWindowRequiredMessage = "Needs live stream window (batch REST scan)"

    /// Builds a complete plain-English Order Flow narrative from a `ChartOrderFlowSummary`
    /// (works identically on live `TradeSignal` cards and persisted `TrackedJournalTrade` entries).
    public static func build(
        summary: ChartOrderFlowSummary,
        direction: TradeDirection,
        entry: Double?,
        stopLoss: Double?,
        target1: Double?,
        target2: Double?,
        precision: ChartPricePrecision
    ) -> OrderFlowNarrative {
        let divergence = resolveDivergence(from: summary)
        let absorption = resolveAbsorption(from: summary)
        let wallBlocksTP1 = resolveWallBlocksTP1(
            summary: summary,
            direction: direction,
            entry: entry,
            target1: target1
        )

        let bidPct = Int((summary.bidPressureFraction * 100.0).rounded())
        let askPct = 100 - bidPct
        let aggressiveBuyFrac = min(0.95, max(0.05, (summary.cvdRatio + 1.0) * 0.5))

        // 1. Hero Verdict
        let heroVerdict = buildHeroVerdict(
            summary: summary,
            direction: direction,
            divergence: divergence,
            absorption: absorption,
            wallBlocksTP1: wallBlocksTP1
        )

        // 2. Resting Book & Aggressive Flow plain-English summaries
        let restingBookSummary: String
        if summary.obiWeighted >= 0.25 {
            restingBookSummary = "Heavy bid support stacked below price (\(bidPct)% Bid vs \(askPct)% Ask) — passive buyers are defending downside."
        } else if summary.obiWeighted <= -0.25 {
            restingBookSummary = "Heavy ask supply stacked above price (\(askPct)% Ask vs \(bidPct)% Bid) — passive sellers are capping upside."
        } else {
            restingBookSummary = "Balanced resting book around the spread (\(bidPct)% Bid vs \(askPct)% Ask) with no extreme liquidity skew."
        }

        let hasTradeWindow = summary.isLiveStream && (summary.tradeSampleCount ?? OrderFlowAnalyzer.minTradesForCVDAndAbsorption) >= OrderFlowAnalyzer.minTradesForCVDAndAbsorption
        let aggressiveFlowSummary: String
        if !summary.isLiveStream && abs(summary.cvdRatio) < 0.001 {
            aggressiveFlowSummary = "Batch REST snapshot — \(restWindowRequiredMessage.lowercased()) for full aggressive trade delta."
        } else if summary.cvdRatio >= 0.25 {
            aggressiveFlowSummary = "Aggressive market buyers are lifting offers (\(String(format: "CVD %+.0f%%", summary.cvdRatio * 100))), pushing upside momentum."
        } else if summary.cvdRatio <= -0.25 {
            aggressiveFlowSummary = "Aggressive market sellers are hitting bids (\(String(format: "CVD %+.0f%%", summary.cvdRatio * 100))), driving downside pressure."
        } else if hasTradeWindow {
            aggressiveFlowSummary = "Two-way aggressive market orders with balanced tape delta (\(String(format: "CVD %+.0f%%", summary.cvdRatio * 100)))."
        } else {
            aggressiveFlowSummary = "Light trade sample (\(String(format: "CVD %+.0f%%", summary.cvdRatio * 100))) — wait for a fuller live stream window for strong delta conviction."
        }

        // 3. "What Happened & How" Event Cards
        let divergenceCard = buildDivergenceCard(divergence: divergence)
        let absorptionCard = buildAbsorptionCard(absorption: absorption, cvdRatio: summary.cvdRatio)
        let liquidationCard = buildLiquidationCard(summary: summary)
        let eventCards = [divergenceCard, absorptionCard, liquidationCard]

        // 4. "Liquidity Walls vs. Your Levels" comparisons
        let wallComparisons = buildWallComparisons(
            summary: summary,
            direction: direction,
            entry: entry,
            stopLoss: stopLoss,
            target1: target1,
            target2: target2,
            precision: precision
        )

        // 5. Concise 2-line Actionable Takeaway
        let actionableTakeaway = buildActionableTakeaway(
            summary: summary,
            direction: direction,
            divergence: divergence,
            absorption: absorption,
            wallBlocksTP1: wallBlocksTP1,
            precision: precision
        )

        return OrderFlowNarrative(
            heroVerdict: heroVerdict,
            alignment: summary.alignment,
            venue: summary.venue.isEmpty ? "Crypto Venue" : summary.venue,
            isLiveStream: summary.isLiveStream,
            spreadBps: summary.spreadBps,
            obiWeighted: summary.obiWeighted,
            cvdRatio: summary.cvdRatio,
            bidPressureFraction: summary.bidPressureFraction,
            aggressiveBuyFraction: aggressiveBuyFrac,
            restingBookSummary: restingBookSummary,
            aggressiveFlowSummary: aggressiveFlowSummary,
            eventCards: eventCards,
            wallLevelComparisons: wallComparisons,
            actionableTakeaway: actionableTakeaway,
            capturedAtEpochSeconds: summary.capturedAtEpochSeconds
        )
    }

    /// Convenience overload accepting a full `OrderFlowAssessment`.
    public static func build(
        assessment: OrderFlowAssessment,
        direction: TradeDirection,
        entry: Double?,
        stopLoss: Double?,
        target1: Double?,
        target2: Double?,
        precision: ChartPricePrecision
    ) -> OrderFlowNarrative {
        if let summary = assessment.chartSummary {
            return build(
                summary: summary,
                direction: direction,
                entry: entry,
                stopLoss: stopLoss,
                target1: target1,
                target2: target2,
                precision: precision
            )
        }
        let fallback = ChartOrderFlowSummary(
            obiWeighted: assessment.obiWeighted,
            cvdRatio: assessment.cvdRatio,
            divergenceTag: assessment.divergence.shortTag,
            absorptionTag: assessment.absorptionState.shortTag,
            alignment: assessment.alignment.rawValue,
            venue: assessment.venue,
            isLiveStream: assessment.isLiveWebSocket,
            spreadBps: assessment.spreadBps,
            compositeScore: assessment.compositeScore,
            confirmedWallBlocksTP1: assessment.confirmedWallBlocksTP1,
            tradeSampleCount: assessment.tradeSampleCount,
            capturedAtEpochSeconds: assessment.timestampEpochSeconds,
            divergenceRaw: assessment.divergence.rawValue,
            absorptionRaw: assessment.absorptionState.rawValue,
            isLowLiquidity: assessment.isLowLiquidity
        )
        return build(
            summary: fallback,
            direction: direction,
            entry: entry,
            stopLoss: stopLoss,
            target1: target1,
            target2: target2,
            precision: precision
        )
    }

    // MARK: - Private Builders

    private static func resolveDivergence(from summary: ChartOrderFlowSummary) -> OrderFlowDivergence {
        if let raw = summary.divergenceRaw, let parsed = OrderFlowDivergence(rawValue: raw) {
            return parsed
        }
        if let tag = summary.divergenceTag {
            if tag == "DIV+" { return .bullish }
            if tag == "DIV-" { return .bearish }
        }
        if !summary.isLiveStream {
            return .notEvaluated
        }
        if let count = summary.tradeSampleCount, count < OrderFlowAnalyzer.minTradesForCVDAndAbsorption {
            return .notEvaluated
        }
        return .none
    }

    private static func resolveAbsorption(from summary: ChartOrderFlowSummary) -> OrderFlowAbsorptionState {
        if let raw = summary.absorptionRaw, let parsed = OrderFlowAbsorptionState(rawValue: raw) {
            return parsed
        }
        if let tag = summary.absorptionTag {
            if tag == "ABSORB+" { return .bullishAbsorption }
            if tag == "ABSORB-" { return .bearishAbsorption }
        }
        if !summary.isLiveStream {
            return .notEvaluated
        }
        if let count = summary.tradeSampleCount, count < OrderFlowAnalyzer.minTradesForCVDAndAbsorption {
            return .notEvaluated
        }
        return .none
    }

    private static func resolveWallBlocksTP1(
        summary: ChartOrderFlowSummary,
        direction: TradeDirection,
        entry: Double?,
        target1: Double?
    ) -> Bool {
        if let explicit = summary.confirmedWallBlocksTP1 {
            return explicit
        }
        guard let e = entry, let t1 = target1, e.isFinite, t1.isFinite else { return false }
        if direction == .long, let aw = summary.askWallPrice, summary.askWallConfirmed {
            return aw > e && aw < t1
        }
        if direction == .short, let bw = summary.bidWallPrice, summary.bidWallConfirmed {
            return bw < e && bw > t1
        }
        return false
    }

    private static func buildHeroVerdict(
        summary: ChartOrderFlowSummary,
        direction: TradeDirection,
        divergence: OrderFlowDivergence,
        absorption: OrderFlowAbsorptionState,
        wallBlocksTP1: Bool
    ) -> String {
        if summary.isLowLiquidity == true || summary.alignment == OrderFlowAlignment.unavailable.rawValue {
            return "Thin Order Book — Order Flow Unavailable for Confirmation"
        }
        if wallBlocksTP1 {
            if direction == .long {
                return "Caution: Confirmed Ask Wall Blocking Target 1"
            } else if direction == .short {
                return "Caution: Confirmed Bid Wall Blocking Target 1"
            }
            return "Caution: Confirmed Liquidity Wall Blocking Target 1"
        }
        if absorption == .bullishAbsorption {
            return direction == .short
                ? "Caution: Institutional Buyers Absorbing Sells Against Short"
                : "Institutional Buyers Absorbing Sells — Upward Pressure Building"
        }
        if absorption == .bearishAbsorption {
            return direction == .long
                ? "Caution: Institutional Sellers Absorbing Buys Against Long"
                : "Institutional Sellers Absorbing Buys — Downward Pressure Building"
        }
        if divergence == .bullish {
            return direction == .short
                ? "Caution: Bullish CVD Divergence Fighting Short Setup"
                : "Bullish Order Flow Divergence — Buyers Stepping In on Dips"
        }
        if divergence == .bearish {
            return direction == .long
                ? "Caution: Bearish CVD Divergence Fighting Long Setup"
                : "Bearish Order Flow Divergence — Upside Momentum Fading"
        }

        switch summary.alignment {
        case OrderFlowAlignment.aligned.rawValue:
            if direction == .long {
                return "Aggressive Buyers Confirming Long — Clear Path Toward TP1"
            } else if direction == .short {
                return "Aggressive Sellers Confirming Short — Clear Path Toward TP1"
            }
            return "Order Flow Skewed in Setup Direction"
        case OrderFlowAlignment.conflicting.rawValue:
            if direction == .long {
                return "Caution: Order Flow Leaning Bearish Against Long Setup"
            } else if direction == .short {
                return "Caution: Order Flow Leaning Bullish Against Short Setup"
            }
            return "Order Flow Conflicting With Setup Direction"
        default:
            return "Balanced Order Book — No Dominant Institutional Tilt Yet"
        }
    }

    private static func buildDivergenceCard(divergence: OrderFlowDivergence) -> OrderFlowEventCard {
        switch divergence {
        case .notEvaluated:
            return OrderFlowEventCard(
                id: "divergence",
                title: "CVD Price Divergence",
                statusLabel: "Not Evaluated",
                detail: restWindowRequiredMessage,
                tone: .unavailable,
                isEvaluated: false
            )
        case .bullish:
            return OrderFlowEventCard(
                id: "divergence",
                title: "CVD Price Divergence",
                statusLabel: "Bullish Divergence",
                detail: "Price dipped while aggressive buying delta shifted higher — sellers are losing follow-through.",
                tone: .bullish,
                isEvaluated: true
            )
        case .bearish:
            return OrderFlowEventCard(
                id: "divergence",
                title: "CVD Price Divergence",
                statusLabel: "Bearish Divergence",
                detail: "Price pushed higher while aggressive selling delta rose — upside breakout lacks real tape demand.",
                tone: .bearish,
                isEvaluated: true
            )
        case .none:
            return OrderFlowEventCard(
                id: "divergence",
                title: "CVD Price Divergence",
                statusLabel: "None Detected",
                detail: "Price movement and aggressive market delta are tracking together without hidden divergence.",
                tone: .neutral,
                isEvaluated: true
            )
        }
    }

    private static func buildAbsorptionCard(
        absorption: OrderFlowAbsorptionState,
        cvdRatio: Double
    ) -> OrderFlowEventCard {
        switch absorption {
        case .notEvaluated:
            return OrderFlowEventCard(
                id: "absorption",
                title: "Passive Absorption",
                statusLabel: "Not Evaluated",
                detail: restWindowRequiredMessage,
                tone: .unavailable,
                isEvaluated: false
            )
        case .bullishAbsorption:
            return OrderFlowEventCard(
                id: "absorption",
                title: "Passive Absorption",
                statusLabel: "Buyers Absorbing",
                detail: "Aggressive sellers attacked bids (\(String(format: "CVD %+.0f%%", cvdRatio * 100))), but passive institutional limit buyers soaked up the selling and held price firm.",
                tone: .bullish,
                isEvaluated: true
            )
        case .bearishAbsorption:
            return OrderFlowEventCard(
                id: "absorption",
                title: "Passive Absorption",
                statusLabel: "Sellers Absorbing",
                detail: "Aggressive buyers lifted offers (\(String(format: "CVD %+.0f%%", cvdRatio * 100))), but passive institutional limit sellers soaked up the buying and capped price.",
                tone: .bearish,
                isEvaluated: true
            )
        case .none:
            return OrderFlowEventCard(
                id: "absorption",
                title: "Passive Absorption",
                statusLabel: "None Detected",
                detail: "No heavy one-sided market aggression is stalling against a passive limit wall right now.",
                tone: .neutral,
                isEvaluated: true
            )
        }
    }

    private static func buildLiquidationCard(summary: ChartOrderFlowSummary) -> OrderFlowEventCard {
        let longRatio = summary.longLiquidationRatio ?? 0.0
        let shortRatio = summary.shortLiquidationRatio ?? 0.0
        let exhaustDir = summary.liquidationExhaustionDirectionRaw ?? TradeDirection.neutral.rawValue

        if !summary.isLiveStream && longRatio == 0 && shortRatio == 0 {
            return OrderFlowEventCard(
                id: "liquidations",
                title: "Liquidation Flush",
                statusLabel: "Not Evaluated",
                detail: restWindowRequiredMessage,
                tone: .unavailable,
                isEvaluated: false
            )
        }

        if exhaustDir == TradeDirection.long.rawValue || (longRatio >= 0.15 && longRatio > shortRatio * 1.5) {
            return OrderFlowEventCard(
                id: "liquidations",
                title: "Liquidation Flush",
                statusLabel: "Long Flush Exhaustion",
                detail: "Forced long liquidations flushed leveraged buyers (\(String(format: "%.0f%%", longRatio * 100)) of rolling tape), often exhausting downside momentum.",
                tone: .bullish,
                isEvaluated: true
            )
        }
        if exhaustDir == TradeDirection.short.rawValue || (shortRatio >= 0.15 && shortRatio > longRatio * 1.5) {
            return OrderFlowEventCard(
                id: "liquidations",
                title: "Liquidation Flush",
                statusLabel: "Short Squeeze Flush",
                detail: "Forced short liquidations squeezed bears (\(String(format: "%.0f%%", shortRatio * 100)) of rolling tape), raising near-term upside exhaustion risk.",
                tone: .bearish,
                isEvaluated: true
            )
        }
        return OrderFlowEventCard(
            id: "liquidations",
            title: "Liquidation Flush",
            statusLabel: "Calm Tape",
            detail: "No abnormal forced liquidation cascade detected in the current window.",
            tone: .neutral,
            isEvaluated: true
        )
    }

    private static func buildWallComparisons(
        summary: ChartOrderFlowSummary,
        direction: TradeDirection,
        entry: Double?,
        stopLoss: Double?,
        target1: Double?,
        target2: Double?,
        precision: ChartPricePrecision
    ) -> [OrderFlowWallComparison] {
        var list: [OrderFlowWallComparison] = []

        if let bidPrice = summary.bidWallPrice, bidPrice.isFinite, bidPrice > 0 {
            let distBps = summary.bidWallDistanceBps ?? entry.map { abs($0 - bidPrice) / max($0, Double.leastNormalMagnitude) * 10_000.0 }
            let blocksShortTP1 = (direction == .short && entry != nil && target1 != nil && bidPrice < entry! && bidPrice > target1!)
            let relation = describeWallRelation(
                wallPrice: bidPrice,
                isBidWall: true,
                isConfirmed: summary.bidWallConfirmed,
                direction: direction,
                entry: entry,
                stopLoss: stopLoss,
                target1: target1,
                target2: target2,
                precision: precision
            )
            list.append(OrderFlowWallComparison(
                id: "bid_wall",
                side: "Bid Wall",
                price: bidPrice,
                formattedPrice: precision.format(bidPrice),
                distanceBps: distBps,
                sizeMultiple: summary.bidWallSizeMultiple,
                isConfirmed: summary.bidWallConfirmed,
                statusBadge: summary.bidWallConfirmed ? "Confirmed 6s+" : "Unconfirmed Flash",
                levelRelation: relation,
                isBlockingTarget: blocksShortTP1 && summary.bidWallConfirmed
            ))
        }

        if let askPrice = summary.askWallPrice, askPrice.isFinite, askPrice > 0 {
            let distBps = summary.askWallDistanceBps ?? entry.map { abs(askPrice - $0) / max($0, Double.leastNormalMagnitude) * 10_000.0 }
            let blocksLongTP1 = (direction == .long && entry != nil && target1 != nil && askPrice > entry! && askPrice < target1!)
            let relation = describeWallRelation(
                wallPrice: askPrice,
                isBidWall: false,
                isConfirmed: summary.askWallConfirmed,
                direction: direction,
                entry: entry,
                stopLoss: stopLoss,
                target1: target1,
                target2: target2,
                precision: precision
            )
            list.append(OrderFlowWallComparison(
                id: "ask_wall",
                side: "Ask Wall",
                price: askPrice,
                formattedPrice: precision.format(askPrice),
                distanceBps: distBps,
                sizeMultiple: summary.askWallSizeMultiple,
                isConfirmed: summary.askWallConfirmed,
                statusBadge: summary.askWallConfirmed ? "Confirmed 6s+" : "Unconfirmed Flash",
                levelRelation: relation,
                isBlockingTarget: blocksLongTP1 && summary.askWallConfirmed
            ))
        }

        return list
    }

    private static func describeWallRelation(
        wallPrice: Double,
        isBidWall: Bool,
        isConfirmed: Bool,
        direction: TradeDirection,
        entry: Double?,
        stopLoss: Double?,
        target1: Double?,
        target2: Double?,
        precision: ChartPricePrecision
    ) -> String {
        let wallQuality = isConfirmed ? "persistent resting liquidity" : "unconfirmed flash liquidity"
        guard let e = entry, let sl = stopLoss, let t1 = target1 else {
            return isBidWall
                ? "Resting bid support (\(wallQuality)) near \(precision.format(wallPrice))."
                : "Resting ask resistance (\(wallQuality)) near \(precision.format(wallPrice))."
        }

        if direction == .long {
            if !isBidWall {
                if wallPrice > e && wallPrice < t1 {
                    return isConfirmed
                        ? "Sits directly between Entry and TP1 (\(precision.format(t1))) — heavy sell wall may block Target 1."
                        : "Appears between Entry and TP1 (\(precision.format(t1))) — watch if it persists past 6s."
                }
                if let t2 = target2, wallPrice >= t1 && wallPrice <= t2 {
                    return "Sits between TP1 (\(precision.format(t1))) and TP2 (\(precision.format(t2))) — expect resistance after TP1."
                }
                return "Overhead ask liquidity above targets (\(wallQuality))."
            } else {
                if wallPrice <= e && wallPrice >= sl {
                    return "Cushions between Entry and Stop Loss (\(precision.format(sl))) — supports your downside protection."
                }
                if wallPrice < sl {
                    return "Sits below Stop Loss (\(precision.format(sl))) — secondary support outside trade invalidation."
                }
                return "Bid liquidity stepping up above Entry (\(wallQuality))."
            }
        } else if direction == .short {
            if isBidWall {
                if wallPrice < e && wallPrice > t1 {
                    return isConfirmed
                        ? "Sits directly between Entry and TP1 (\(precision.format(t1))) — heavy buy wall may block Target 1."
                        : "Appears between Entry and TP1 (\(precision.format(t1))) — watch if it persists past 6s."
                }
                if let t2 = target2, wallPrice <= t1 && wallPrice >= t2 {
                    return "Sits between TP1 (\(precision.format(t1))) and TP2 (\(precision.format(t2))) — expect demand after TP1."
                }
                return "Lower bid liquidity beyond targets (\(wallQuality))."
            } else {
                if wallPrice >= e && wallPrice <= sl {
                    return "Caps price between Entry and Stop Loss (\(precision.format(sl))) — reinforces your invalidation wall."
                }
                if wallPrice > sl {
                    return "Sits above Stop Loss (\(precision.format(sl))) — secondary supply outside trade invalidation."
                }
                return "Ask liquidity pressing down below Entry (\(wallQuality))."
            }
        }

        return isBidWall
            ? "Bid wall (\(wallQuality)) anchored at \(precision.format(wallPrice))."
            : "Ask wall (\(wallQuality)) anchored at \(precision.format(wallPrice))."
    }

    private static func buildActionableTakeaway(
        summary: ChartOrderFlowSummary,
        direction: TradeDirection,
        divergence: OrderFlowDivergence,
        absorption: OrderFlowAbsorptionState,
        wallBlocksTP1: Bool,
        precision: ChartPricePrecision
    ) -> String {
        let dirLabel = direction == .neutral ? "setup" : direction.rawValue.uppercased()
        if wallBlocksTP1 {
            let wallPrice = (direction == .long ? summary.askWallPrice : summary.bidWallPrice).map { precision.format($0) } ?? "nearby"
            return "A confirmed liquidity wall at \(wallPrice) stands in front of TP1 for this \(dirLabel).\nWait for the wall to pull or absorb before expecting clean follow-through."
        }
        if summary.alignment == OrderFlowAlignment.aligned.rawValue {
            if absorption.isDetected {
                return "Live passive absorption backs your \(dirLabel) bias on \(summary.venue.isEmpty ? "the tape" : summary.venue).\nStructure and order flow point the same way — stick to your planned Entry and Stop Loss."
            }
            return "Resting book depth and market aggression confirm this \(dirLabel) bias.\nRespect your structural Entry zone and manage size strictly inside your stop distance."
        }
        if summary.alignment == OrderFlowAlignment.conflicting.rawValue {
            if divergence.isDetected || absorption.isDetected {
                return "Live tape shows opposing absorption/divergence fighting this \(dirLabel) setup.\nConsider waiting for tape pressure to flip or reducing conviction until flow clears."
            }
            return "Order book skew currently leans against this \(dirLabel) direction.\nLet closed-candle structure prove itself and avoid chasing into opposing resting depth."
        }
        if !summary.isLiveStream {
            return "Resting order book is balanced on this REST snapshot, with live tape events not yet evaluated.\nTreat chart structure as primary until a live WebSocket window confirms aggressive flow."
        }
        return "Order flow is neutral for this \(dirLabel) with no confirmed wall blocking your target path.\nRely on your closed-bar confluence rules and respect the defined invalidation level."
    }
}
