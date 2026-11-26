import Foundation

/// UI grouping for individual strategy toggles in Signal Rules & AI.
public enum StrategyCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case ictStructure = "ICT Structure & Levels"
    case behavioralTraps = "Behavioral Traps"
    case candlestickPatterns = "Candlestick Patterns"
    case momentumVolume = "Momentum & Volume"
    case positioningMacro = "Positioning & Macro"

    public var id: String { rawValue }
    public var displayName: String { rawValue }

    public var strategies: [StrategyID] {
        StrategyID.allCases.filter { $0.category == self }
    }
}

/// Canonical single source of truth for every individually toggleable detector.
/// Each case maps 1:1 to exactly one deterministic detector output (`StrategyContribution.id`
/// or `TrapTriggerKind`). Raw values are persisted — never rename them.
public enum StrategyID: String, CaseIterable, Identifiable, Codable, Sendable, Hashable {
    // ICT Structure & Levels
    case ictBos = "ict_bos"
    case ictMss = "ict_mss"
    case ictOrderBlock = "ict_order_block"
    case ictFvg = "ict_fvg"
    case ictLiquiditySweep = "ict_liquidity_sweep"
    case ictPremiumEq = "ict_premium_eq"
    case ictDiscountEq = "ict_discount_eq"
    // Behavioral Traps
    case trapOslerRoundNumber = "trap_osler_round-number_sweep"
    case trapNewsWhipsaw = "trap_news_whipsaw_trap"
    case trapLiquiditySwingSweep = "trap_liquidity_swing_sweep"
    case trapAttentionFomo = "trap_attention_fomo_spike"
    // Candlestick Patterns
    case candleShootingStar = "candle_shooting_star"
    case candleBearishEngulfing = "candle_bearish_engulfing"
    case candleBullishEngulfing = "candle_bullish_engulfing"
    case candleInsideBreakout = "candle_inside_breakout"
    case candleDisplacement = "candle_displacement"
    case candleHammerPinbar = "candle_hammer_pinbar"
    // Momentum & Volume
    case momentumAtrSqueeze = "momentum_atr_squeeze"
    case momentumEmaPullback = "momentum_ema_pullback"
    case momentumRvol = "momentum_rvol"
    case momentumRsiDivergence = "momentum_rsi_divergence"
    // Positioning & Macro
    case positioningOkx = "positioning_okx"
    case positioningCot = "positioning_cot"
    case macroSurpriseCatalyst = "macro_surprise_catalyst"

    public var id: String { rawValue }

    /// Preset of the historically strongest detectors (fresh-install default).
    public static let provenWinners: Set<StrategyID> = [.ictBos, .ictOrderBlock, .ictFvg, .ictPremiumEq, .trapOslerRoundNumber]
    public static let allSet: Set<StrategyID> = Set(StrategyID.allCases)

    public var displayName: String {
        switch self {
        case .ictBos: return "ICT BOS"
        case .ictMss: return "ICT MSS"
        case .ictOrderBlock: return "ICT Order Block (OB)"
        case .ictFvg: return "ICT Fair Value Gap (FVG)"
        case .ictLiquiditySweep: return "ICT Liquidity Sweep"
        case .ictPremiumEq: return "ICT Premium EQ"
        case .ictDiscountEq: return "ICT Discount EQ"
        case .trapOslerRoundNumber: return "Osler Round-Number Sweep"
        case .trapNewsWhipsaw: return "News Whipsaw Trap"
        case .trapLiquiditySwingSweep: return "Liquidity Swing Sweep"
        case .trapAttentionFomo: return "Attention FOMO Spike"
        case .candleShootingStar: return "Shooting Star"
        case .candleBearishEngulfing: return "Bearish Engulfing"
        case .candleBullishEngulfing: return "Bullish Engulfing"
        case .candleInsideBreakout: return "Inside Breakout"
        case .candleDisplacement: return "Displacement"
        case .candleHammerPinbar: return "Hammer / Pinbar"
        case .momentumAtrSqueeze: return "ATR Squeeze"
        case .momentumEmaPullback: return "EMA Pullback"
        case .momentumRvol: return "RVOL"
        case .momentumRsiDivergence: return "RSI Divergence"
        case .positioningOkx: return "OKX Positioning"
        case .positioningCot: return "COT Positioning"
        case .macroSurpriseCatalyst: return "Macro Surprise Catalyst"
        }
    }

    public var category: StrategyCategory {
        switch self {
        case .ictBos, .ictMss, .ictOrderBlock, .ictFvg, .ictLiquiditySweep, .ictPremiumEq, .ictDiscountEq:
            return .ictStructure
        case .trapOslerRoundNumber, .trapNewsWhipsaw, .trapLiquiditySwingSweep, .trapAttentionFomo:
            return .behavioralTraps
        case .candleShootingStar, .candleBearishEngulfing, .candleBullishEngulfing,
             .candleInsideBreakout, .candleDisplacement, .candleHammerPinbar:
            return .candlestickPatterns
        case .momentumAtrSqueeze, .momentumEmaPullback, .momentumRvol, .momentumRsiDivergence:
            return .momentumVolume
        case .positioningOkx, .positioningCot, .macroSurpriseCatalyst:
            return .positioningMacro
        }
    }

    /// Independence pillar used by the multi-group confluence check.
    public var group: StrategyGroup {
        switch category {
        case .ictStructure: return .ictSmc
        case .behavioralTraps: return .behavioralTrap
        case .candlestickPatterns: return .candlestick
        case .momentumVolume: return .trendMomentum
        case .positioningMacro: return self == .macroSurpriseCatalyst ? .macroCatalyst : .behavioralTrap
        }
    }

    /// True for OHLC / candle-driven core strategies (excludes external live-only/positioning add-ons).
    public var isCoreOHLC: Bool {
        switch category {
        case .ictStructure, .behavioralTraps, .candlestickPatterns, .momentumVolume:
            return true
        case .positioningMacro:
            return false
        }
    }

    public static let coreOHLCStrategies: Set<StrategyID> = Set(allCases.filter(\.isCoreOHLC))

    /// True if this strategy detector can legitimately fire on the given market class.
    public func isApplicable(to marketClass: MarketClass) -> Bool {
        switch self {
        case .positioningOkx:
            return marketClass == .crypto
        case .positioningCot:
            return marketClass == .forex || marketClass == .metals || marketClass == .indices || marketClass == .crypto
        case .momentumRvol:
            return !marketClass.isOTCVolumeUnavailable
        default:
            return true
        }
    }

    /// Trap trigger kind gated by this toggle (nil for non-trap strategies).
    public var trapKind: TrapTriggerKind? {
        switch self {
        case .trapOslerRoundNumber: return .oslerRoundNumberSweep
        case .trapNewsWhipsaw: return .postNewsWhipsawTrap
        case .trapLiquiditySwingSweep: return .liquiditySwingSweep
        case .trapAttentionFomo: return .attentionFOMOSpike
        default: return nil
        }
    }

    /// Resolves the strategy that produced a given `StrategyContribution.id`.
    public init?(contributionId: String) {
        let lower = contributionId.lowercased()
        if let exact = StrategyID(rawValue: lower) {
            self = exact
            return
        }
        return nil
    }

    /// Strategy toggle controlling a detected trap kind (nil if the kind is not individually detectable).
    public static func forTrapKind(_ kind: TrapTriggerKind) -> StrategyID? {
        allCases.first { $0.trapKind == kind }
    }

    /// One-time migration of legacy v1.2–v1.5 grouped selections into individual strategy IDs.
    public static func migrate(fromGroups groups: Set<StrategyGroup>) -> Set<StrategyID> {
        Set(allCases.filter { id in
            switch id {
            case .positioningOkx, .positioningCot:
                return groups.contains(.behavioralTrap)
            default:
                return groups.contains(id.group)
            }
        })
    }

    public static func migrate(fromConcepts concepts: Set<StrategyConcept>) -> Set<StrategyID> {
        Set(allCases.filter { id in
            concepts.contains { $0.matches(contributionId: id.rawValue) }
        })
    }
}

/// Convenience lookup for UI provenance chips.
extension StrategyContribution {
    public var strategyID: StrategyID? { StrategyID(contributionId: id) }
}

extension StrategyID {
    /// Computes the exact deduplicated list of strategies that fired for a signal or trap alert.
    public static func resolveMatched(
        alignedStrategies: [StrategyContribution],
        category: SignalCategory,
        trapDirection: TrapDirection?,
        traps: [BehavioralTrap]
    ) -> [StrategyID] {
        var out: [StrategyID] = []
        for c in alignedStrategies {
            if let sid = c.strategyID, !out.contains(sid) {
                out.append(sid)
            }
        }
        if category == .trapAlert,
           let trapDir = trapDirection,
           let trap = traps.last(where: { $0.direction == trapDir && $0.isActionable }),
           let sid = StrategyID.forTrapKind(trap.triggerKind),
           !out.contains(sid) {
            out.append(sid)
        }
        return out
    }

    /// Normalizes raw persisted strategy keys (e.g. `"ict_fvg"`, `"Ict Fvg"`, `"positioning_cot"`, `"Positioning Cot"`)
    /// into canonical human-readable display names so Calibration & Diagnostics views never render ugly snake-case.
    public static func displayName(forRawKey raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Unknown Strategy" }

        let snake = trimmed
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")

        if let exact = StrategyID(rawValue: snake) {
            return exact.displayName
        }

        let normalized = snake
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: "__", with: "_")

        for sid in StrategyID.allCases {
            let sidNorm = sid.rawValue.replacingOccurrences(of: "-", with: "_")
            if sidNorm == normalized || sid.displayName.lowercased() == trimmed.lowercased() {
                return sid.displayName
            }
        }

        switch normalized {
        case "ict_sweep", "ict_liquidity_sweeps":
            return StrategyID.ictLiquiditySweep.displayName
        case "ict_bos_mss", "ict_structure":
            return "ICT BOS / MSS Structure"
        case "ict_premium_discount":
            return "Premium / Discount EQ"
        case "trap_osler", "trap_osler_round_number", "trap_osler_round_number_sweep":
            return StrategyID.trapOslerRoundNumber.displayName
        case "trap_news", "trap_post_news_whipsaw", "trap_post_news_whipsaw_trap":
            return StrategyID.trapNewsWhipsaw.displayName
        case "trap_swing", "trap_liquidity_sweep":
            return StrategyID.trapLiquiditySwingSweep.displayName
        case "trap_fomo", "trap_attention_fomo":
            return StrategyID.trapAttentionFomo.displayName
        case "crypto_order_flow", "order_flow":
            return "Order Flow (Crypto Only)"
        case "positioning_flow":
            return "Positioning (OKX / COT)"
        case "candlestick_patterns":
            return "Candlestick Patterns"
        case "behavioral_traps":
            return "Behavioral Traps"
        default:
            break
        }

        let acronyms: Set<String> = ["ict", "fvg", "ob", "bos", "mss", "eq", "ema", "rsi", "atr", "rvol", "okx", "cot", "fomo", "smc"]
        let words = trimmed
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { token -> String in
                let lower = token.lowercased()
                if acronyms.contains(lower) {
                    return lower.uppercased()
                }
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }
        return words.isEmpty ? trimmed : words.joined(separator: " ")
    }
}
