import Foundation

/// Single source of truth representing every individual strategy toggle in Settings
/// plus the Crypto-Only live Order Flow module.
public struct ActiveStrategyProfile: Codable, Sendable, Equatable, Hashable {
    public static let legacyBaselineKey = "legacy_baseline"

    public let enabledStrategies: Set<StrategyID>
    public let isOrderFlowEnabled: Bool

    public init(
        enabledStrategies: Set<StrategyID> = StrategyID.provenWinners,
        isOrderFlowEnabled: Bool = false
    ) {
        self.enabledStrategies = enabledStrategies
        self.isOrderFlowEnabled = isOrderFlowEnabled
    }

    enum CodingKeys: String, CodingKey {
        case enabledStrategies
        case isOrderFlowEnabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let raw = try? c.decodeIfPresent([String].self, forKey: .enabledStrategies) {
            self.enabledStrategies = Set(raw.compactMap(StrategyID.init(rawValue:)))
        } else {
            self.enabledStrategies = StrategyID.provenWinners
        }
        self.isOrderFlowEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .isOrderFlowEnabled)) ?? false
    }

    /// Stable sorted canonical key identifying the active strategy configuration
    /// (e.g., `"ict_bos+ict_fvg+ict_order_block+orderflow"`).
    public var profileKey: String {
        var tokens = enabledStrategies.map(\.rawValue).sorted()
        if isOrderFlowEnabled {
            tokens.append("orderflow")
        }
        if tokens.isEmpty {
            return "none"
        }
        return tokens.joined(separator: "+")
    }

    /// Sorted CSV of enabled strategy IDs (including `"orderflow"` when enabled) for persistence tagging.
    public var enabledStrategyIDsCSV: String {
        var tokens = enabledStrategies.map(\.rawValue).sorted()
        if isOrderFlowEnabled {
            tokens.append("orderflow")
        }
        return tokens.joined(separator: ",")
    }

    /// Core OHLC / candle strategies currently enabled (excludes optional live-only crypto add-ons and positioning/macro).
    public var enabledCoreStrategies: Set<StrategyID> {
        enabledStrategies.filter(\.isCoreOHLC)
    }

    /// Count of enabled core OHLC strategies (excluding optional live-only crypto add-ons).
    public var enabledCoreCount: Int {
        enabledCoreStrategies.count
    }

    /// Enabled `StrategyID`s applicable to the specified market class.
    public func applicableStrategies(for marketClass: MarketClass) -> Set<StrategyID> {
        enabledStrategies.filter { $0.isApplicable(to: marketClass) }
    }

    /// Whether live Order Flow is applicable for the given market class & profile.
    public func isOrderFlowApplicable(for marketClass: MarketClass) -> Bool {
        isOrderFlowEnabled && marketClass == .crypto
    }

    /// Total count of enabled modules actually applicable to `marketClass`
    /// (applicable `StrategyID`s + 1 for live Crypto Order Flow when ON on Crypto).
    public func enabledTotalCount(for marketClass: MarketClass) -> Int {
        let base = applicableStrategies(for: marketClass).count
        return base + (isOrderFlowApplicable(for: marketClass) ? 1 : 0)
    }

    /// Disabled `StrategyID`s (for transparency & AI Judge prompt parity).
    public var disabledStrategies: Set<StrategyID> {
        StrategyID.allSet.subtracting(enabledStrategies)
    }

    /// Normalizes a persisted profile key, treating empty pre-upgrade keys as `"legacy_baseline"`.
    public static func normalizedKey(_ rawKey: String?) -> String {
        let trimmed = rawKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? legacyBaselineKey : trimmed
    }

    /// Convenience default profile matching all strategies enabled (Order Flow OFF by default).
    public static let allStrategies = ActiveStrategyProfile(
        enabledStrategies: StrategyID.allSet,
        isOrderFlowEnabled: false
    )
}
