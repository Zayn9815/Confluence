import Foundation

public struct BehavioralEvidence: Codable, Sendable, Equatable, Hashable {
    public let badge: String
    public let fact: String
    public let proBias: TradeDirection
    public let retailBias: TradeDirection

    public init(badge: String, fact: String, proBias: TradeDirection, retailBias: TradeDirection) {
        self.badge = badge
        self.fact = fact
        self.proBias = proBias
        self.retailBias = retailBias
    }
}

public struct PsychologyReport: Codable, Sendable, Equatable, Hashable {
    public let signalCategory: SignalCategory
    /// Intraday institutional flow direction (derived from structure, traps, and intraday perp flow).
    public let proDirection: TradeDirection
    public let retailCrowdDirection: TradeDirection
    public let provenanceBadge: String
    public let whatHappened: String
    public let beginnerPsychology: String
    public let proPsychology: String
    public let behavioralBadges: [String]
    public let evidence: [BehavioralEvidence]
    /// Separate higher-timeframe/weekly macro positioning bias (e.g., CFTC COT or OKX positioning) so counter-trend weekly COT never contradicts intraday pro flow.
    public let macroPositioningDirection: TradeDirection?
    public let macroPositioningLabel: String?
    public let macroAlignsWithSetup: Bool?

    public init(
        signalCategory: SignalCategory,
        proDirection: TradeDirection,
        retailCrowdDirection: TradeDirection,
        provenanceBadge: String,
        whatHappened: String,
        beginnerPsychology: String,
        proPsychology: String,
        behavioralBadges: [String],
        evidence: [BehavioralEvidence],
        macroPositioningDirection: TradeDirection? = nil,
        macroPositioningLabel: String? = nil,
        macroAlignsWithSetup: Bool? = nil
    ) {
        self.signalCategory = signalCategory
        self.proDirection = proDirection
        self.retailCrowdDirection = retailCrowdDirection
        self.provenanceBadge = provenanceBadge
        self.whatHappened = whatHappened
        self.beginnerPsychology = beginnerPsychology
        self.proPsychology = proPsychology
        self.behavioralBadges = behavioralBadges
        self.evidence = evidence
        self.macroPositioningDirection = macroPositioningDirection
        self.macroPositioningLabel = macroPositioningLabel
        self.macroAlignsWithSetup = macroAlignsWithSetup
    }
}
