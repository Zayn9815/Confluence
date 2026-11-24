import Foundation

public struct OKXFundingPoint: Codable, Sendable, Equatable {
    public let fundingTimeEpochSeconds: TimeInterval
    public let fundingRate: Double
    public let realizedRate: Double?

    public init(fundingTimeEpochSeconds: TimeInterval, fundingRate: Double, realizedRate: Double?) {
        self.fundingTimeEpochSeconds = fundingTimeEpochSeconds
        self.fundingRate = fundingRate
        self.realizedRate = realizedRate
    }
}

public struct OKXOpenInterestPoint: Codable, Sendable, Equatable {
    public let timestampEpochSeconds: TimeInterval
    public let openInterestContracts: Double
    public let openInterestCoin: Double
    public let openInterestUSD: Double
    /// Confirmed UTC-aligned period label (e.g., "1H", "4H", "1Dutc" — never "1D").
    public let period: String

    public init(
        timestampEpochSeconds: TimeInterval,
        openInterestContracts: Double,
        openInterestCoin: Double,
        openInterestUSD: Double,
        period: String
    ) {
        self.timestampEpochSeconds = timestampEpochSeconds
        self.openInterestContracts = openInterestContracts
        self.openInterestCoin = openInterestCoin
        self.openInterestUSD = openInterestUSD
        self.period = period
    }
}

public struct OKXDerivativesSnapshot: Codable, Sendable, Equatable {
    public let instId: String
    public let currentFundingRate: Double
    public let nextFundingTimeEpochSeconds: TimeInterval?
    public let liveOpenInterestUSD: Double?
    public let fundingHistory: [OKXFundingPoint]
    public let openInterestHistory: [OKXOpenInterestPoint]
    public let fetchedAtEpochSeconds: TimeInterval

    public init(
        instId: String,
        currentFundingRate: Double,
        nextFundingTimeEpochSeconds: TimeInterval?,
        liveOpenInterestUSD: Double?,
        fundingHistory: [OKXFundingPoint],
        openInterestHistory: [OKXOpenInterestPoint],
        fetchedAtEpochSeconds: TimeInterval
    ) {
        self.instId = instId
        self.currentFundingRate = currentFundingRate
        self.nextFundingTimeEpochSeconds = nextFundingTimeEpochSeconds
        self.liveOpenInterestUSD = liveOpenInterestUSD
        self.fundingHistory = fundingHistory
        self.openInterestHistory = openInterestHistory
        self.fetchedAtEpochSeconds = fetchedAtEpochSeconds
    }
}

public enum CFTCDatasetKind: String, Codable, Sendable, Equatable {
    case disaggregatedFuturesOnly = "72hh-3qpy"
    case tradersInFinancialFutures = "gpe5-46if"
}

public struct CFTCCOTRecord: Codable, Sendable, Equatable {
    public let contractCode: String
    public let marketName: String
    public let dataset: CFTCDatasetKind
    /// Tuesday as-of date in UTC epoch seconds.
    public let reportDateEpochSeconds: TimeInterval
    /// Friday 20:30 UTC publication timestamp (strictly causal availability boundary).
    public let publishedAtEpochSeconds: TimeInterval
    public let openInterest: Double
    /// Institutional smart-money group: Managed Money (Disaggregated) or Asset Mgr + Leveraged Funds (TFF).
    public let institutionalLong: Double
    public let institutionalShort: Double
    /// Small speculators: Non-Reportables.
    public let nonReportableLong: Double
    public let nonReportableShort: Double

    public init(
        contractCode: String,
        marketName: String,
        dataset: CFTCDatasetKind,
        reportDateEpochSeconds: TimeInterval,
        publishedAtEpochSeconds: TimeInterval,
        openInterest: Double,
        institutionalLong: Double,
        institutionalShort: Double,
        nonReportableLong: Double,
        nonReportableShort: Double
    ) {
        self.contractCode = contractCode
        self.marketName = marketName
        self.dataset = dataset
        self.reportDateEpochSeconds = reportDateEpochSeconds
        self.publishedAtEpochSeconds = publishedAtEpochSeconds
        self.openInterest = openInterest
        self.institutionalLong = institutionalLong
        self.institutionalShort = institutionalShort
        self.nonReportableLong = nonReportableLong
        self.nonReportableShort = nonReportableShort
    }

    public var institutionalNet: Double { institutionalLong - institutionalShort }
    public var nonReportableNet: Double { nonReportableLong - nonReportableShort }
    public var institutionalNetPercentOI: Double {
        guard openInterest > 0 else { return 0 }
        return (institutionalNet / openInterest) * 100.0
    }
    public var nonReportableNetPercentOI: Double {
        guard openInterest > 0 else { return 0 }
        return (nonReportableNet / openInterest) * 100.0
    }
}

public enum PriceOIDivergence: String, Codable, Sendable, Equatable {
    case freshLongs
    case shortSqueeze
    case freshShorts
    case longLiquidation
    case neutral

    public var label: String {
        switch self {
        case .freshLongs: return "Fresh Longs (Price ↑ · OI ↑)"
        case .shortSqueeze: return "Short Squeeze (Price ↑ · OI ↓)"
        case .freshShorts: return "Fresh Shorts (Price ↓ · OI ↑)"
        case .longLiquidation: return "Long Liquidation (Price ↓ · OI ↓)"
        case .neutral: return "Balanced OI Flow"
        }
    }
}

public enum PositioningProvenance: String, Codable, Sendable, Equatable {
    case okxFundingOI = "Structure + OKX Funding/OI"
    case cftcCOT = "Structure + CFTC COT"
    case macroSurpriseStructure = "Macro Surprise + Structure"
    case structureVolumeWickProxy = "Structure + Volume/Wick Proxy"
}

public struct PositioningAssessment: Codable, Sendable, Equatable {
    public let provenance: PositioningProvenance
    public let proDirection: TradeDirection
    public let retailCrowdDirection: TradeDirection
    public let priceOIDivergence: PriceOIDivergence
    public let fundingRate: Double?
    public let fundingPercentile: Double?
    public let oiChangePercent: Double?
    public let cotInstitutionalPercentile: Double?
    public let cotRetailPercentile: Double?
    public let summary: String
    public let badges: [String]

    public init(
        provenance: PositioningProvenance,
        proDirection: TradeDirection,
        retailCrowdDirection: TradeDirection,
        priceOIDivergence: PriceOIDivergence,
        fundingRate: Double? = nil,
        fundingPercentile: Double? = nil,
        oiChangePercent: Double? = nil,
        cotInstitutionalPercentile: Double? = nil,
        cotRetailPercentile: Double? = nil,
        summary: String,
        badges: [String]
    ) {
        self.provenance = provenance
        self.proDirection = proDirection
        self.retailCrowdDirection = retailCrowdDirection
        self.priceOIDivergence = priceOIDivergence
        self.fundingRate = fundingRate
        self.fundingPercentile = fundingPercentile
        self.oiChangePercent = oiChangePercent
        self.cotInstitutionalPercentile = cotInstitutionalPercentile
        self.cotRetailPercentile = cotRetailPercentile
        self.summary = summary
        self.badges = badges
    }
}
