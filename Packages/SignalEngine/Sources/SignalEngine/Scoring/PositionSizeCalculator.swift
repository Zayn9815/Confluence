import Foundation

public enum AccountCurrency: String, Codable, Sendable, CaseIterable, Identifiable {
    case usd = "USD"
    case eur = "EUR"
    case gbp = "GBP"
    case jpy = "JPY"
    case aud = "AUD"
    case cad = "CAD"
    case chf = "CHF"
    case other = "Other"

    public var id: String { rawValue }

    public var symbolPrefix: String {
        switch self {
        case .usd: return "$"
        case .eur: return "€"
        case .gbp: return "£"
        case .jpy: return "¥"
        case .aud: return "A$"
        case .cad: return "C$"
        case .chf: return "CHF "
        case .other: return ""
        }
    }
}

public struct InstrumentContractSpec: Codable, Sendable, Equatable, Hashable {
    public var contractSize: Double
    public var pointValue: Double

    public init(contractSize: Double = 1.0, pointValue: Double = 1.0) {
        self.contractSize = contractSize
        self.pointValue = pointValue
    }

    public static func defaultSpec(for symbol: String, marketClass: MarketClass) -> InstrumentContractSpec {
        let upper = symbol.uppercased()
        switch marketClass {
        case .metals:
            return InstrumentContractSpec(contractSize: 100.0, pointValue: 1.0) // 100 troy oz per standard gold lot
        case .forex:
            return InstrumentContractSpec(contractSize: 100_000.0, pointValue: 1.0) // 100k standard FX lot
        case .indices:
            if upper == "SPY" || upper == "QQQ" {
                return InstrumentContractSpec(contractSize: 1.0, pointValue: 1.0)
            }
            return InstrumentContractSpec(contractSize: 1.0, pointValue: 1.0) // 1 CFD contract = $1/pt default, editable
        case .crypto, .stocks:
            return InstrumentContractSpec(contractSize: 1.0, pointValue: 1.0)
        }
    }
}

public struct PositionSizeInput: Codable, Sendable, Equatable {
    public let symbol: String
    public let marketClass: MarketClass
    public let entryPrice: Double
    public let stopLossPrice: Double
    public let tp1Price: Double?
    public let accountBalance: Double
    public let riskPercent: Double
    public let accountCurrency: AccountCurrency
    /// Manual conversion rate: `1 USD = usdToAccountRate <AccountCurrency>` (always `1.0` when `accountCurrency == .usd`).
    public let usdToAccountRate: Double
    public let quoteToUSDRate: Double?
    public let contractSpec: InstrumentContractSpec

    public init(
        symbol: String,
        marketClass: MarketClass,
        entryPrice: Double,
        stopLossPrice: Double,
        tp1Price: Double? = nil,
        accountBalance: Double,
        riskPercent: Double,
        accountCurrency: AccountCurrency = .usd,
        usdToAccountRate: Double = 1.0,
        quoteToUSDRate: Double? = nil,
        contractSpec: InstrumentContractSpec? = nil
    ) {
        self.symbol = symbol
        self.marketClass = marketClass
        self.entryPrice = entryPrice
        self.stopLossPrice = stopLossPrice
        self.tp1Price = tp1Price
        self.accountBalance = accountBalance
        self.riskPercent = riskPercent
        self.accountCurrency = accountCurrency
        self.usdToAccountRate = usdToAccountRate
        self.quoteToUSDRate = quoteToUSDRate
        self.contractSpec = contractSpec ?? InstrumentContractSpec.defaultSpec(for: symbol, marketClass: marketClass)
    }
}

public struct PositionSizeResult: Codable, Sendable, Equatable {
    public let riskAmountAccount: Double
    public let riskAmountUSD: Double
    public let stopDistancePrice: Double
    public let stopDistancePips: Double?
    public let primaryQuantity: Double
    public let primaryUnitLabel: String
    public let secondaryQuantity: Double?
    public let secondaryUnitLabel: String?
    public let estimatedNotionalUSD: Double
    public let estimatedReward1Account: Double?
    public let formulaSummary: String
    public let disclaimer: String

    public init(
        riskAmountAccount: Double,
        riskAmountUSD: Double,
        stopDistancePrice: Double,
        stopDistancePips: Double?,
        primaryQuantity: Double,
        primaryUnitLabel: String,
        secondaryQuantity: Double?,
        secondaryUnitLabel: String?,
        estimatedNotionalUSD: Double,
        estimatedReward1Account: Double?,
        formulaSummary: String,
        disclaimer: String
    ) {
        self.riskAmountAccount = riskAmountAccount
        self.riskAmountUSD = riskAmountUSD
        self.stopDistancePrice = stopDistancePrice
        self.stopDistancePips = stopDistancePips
        self.primaryQuantity = primaryQuantity
        self.primaryUnitLabel = primaryUnitLabel
        self.secondaryQuantity = secondaryQuantity
        self.secondaryUnitLabel = secondaryUnitLabel
        self.estimatedNotionalUSD = estimatedNotionalUSD
        self.estimatedReward1Account = estimatedReward1Account
        self.formulaSummary = formulaSummary
        self.disclaimer = disclaimer
    }
}

/// Pure-Swift deterministic position sizing engine supporting USD natively plus manual conversion rate
/// for non-USD accounts across FX (pip-based), Metals (`100 oz/lot`), Crypto, US Stocks/ETFs, and editable Index CFDs.
public enum PositionSizeCalculator {
    public static let standardDisclaimer = "Estimate only — verify contract specifications, pip value, margin, and fees with your broker before placing any order."

    public static func calculate(_ input: PositionSizeInput) -> PositionSizeResult? {
        guard input.accountBalance.isFinite, input.accountBalance > 0,
              input.riskPercent.isFinite, input.riskPercent > 0,
              input.entryPrice.isFinite, input.entryPrice > 0,
              input.stopLossPrice.isFinite, input.stopLossPrice > 0,
              input.contractSpec.contractSize.isFinite, input.contractSpec.contractSize > 0,
              input.contractSpec.pointValue.isFinite, input.contractSpec.pointValue > 0,
              (input.accountCurrency == .usd || (input.usdToAccountRate.isFinite && input.usdToAccountRate > 0))
        else { return nil }

        let stopDist = abs(input.entryPrice - input.stopLossPrice)
        guard stopDist > 1e-12 else { return nil }

        let riskAccount = input.accountBalance * (input.riskPercent / 100.0)
        let fxRate: Double = (input.accountCurrency == .usd) ? 1.0 : input.usdToAccountRate
        let riskUSD = riskAccount / fxRate

        let isLong = input.entryPrice > input.stopLossPrice
        let reward1Account: Double? = input.tp1Price.flatMap { tp1 in
            guard tp1.isFinite, tp1 > 0, isLong ? (tp1 > input.entryPrice) : (tp1 < input.entryPrice) else { return nil }
            let rr = abs(tp1 - input.entryPrice) / stopDist
            return riskAccount * rr
        }

        let upper = input.symbol.uppercased()
        let spec = input.contractSpec

        switch input.marketClass {
        case .forex:
            let pipSize = upper.contains("JPY") ? 0.01 : 0.0001
            let stopPips = stopDist / pipSize
            let lotUnits = max(spec.contractSize, 1.0)
            let pipValueUSD: Double
            let note: String
            if upper.hasSuffix("/USD") || upper.hasSuffix("USD") && !upper.hasPrefix("USD") {
                pipValueUSD = lotUnits * pipSize
                note = "Quote USD (\(String(format: "$%.2f", pipValueUSD))/pip per lot)"
            } else if upper.hasPrefix("USD/") || upper.hasPrefix("USD") {
                pipValueUSD = (lotUnits * pipSize) / input.entryPrice
                note = "Base USD (\(String(format: "$%.2f", pipValueUSD))/pip per lot @ entry)"
            } else {
                let quoteToUSD = input.quoteToUSDRate.flatMap { ($0.isFinite && $0 > 0) ? $0 : nil }
                    ?? (upper.contains("JPY") ? (1.0 / 150.0) : 1.0)
                pipValueUSD = (lotUnits * pipSize) * quoteToUSD
                note = "Cross pair approx. (\(String(format: "$%.2f", pipValueUSD))/pip per lot — verify quote/USD)"
            }
            let lots = riskUSD / max(stopPips * pipValueUSD, 1e-12)
            let units = lots * lotUnits
            let notionalUSD: Double
            if upper.hasPrefix("USD") {
                notionalUSD = units
            } else if upper.hasSuffix("/USD") || (upper.hasSuffix("USD") && !upper.hasPrefix("USD")) {
                notionalUSD = units * input.entryPrice
            } else {
                let quoteToUSD = input.quoteToUSDRate.flatMap { ($0.isFinite && $0 > 0) ? $0 : nil }
                    ?? (upper.contains("JPY") ? (1.0 / 150.0) : 1.0)
                notionalUSD = units * input.entryPrice * quoteToUSD
            }
            return PositionSizeResult(
                riskAmountAccount: riskAccount,
                riskAmountUSD: riskUSD,
                stopDistancePrice: stopDist,
                stopDistancePips: stopPips,
                primaryQuantity: lots,
                primaryUnitLabel: "Standard Lots",
                secondaryQuantity: units,
                secondaryUnitLabel: "Units",
                estimatedNotionalUSD: notionalUSD,
                estimatedReward1Account: reward1Account,
                formulaSummary: "\(String(format: "%.1f", stopPips)) pips · \(note)",
                disclaimer: standardDisclaimer
            )

        case .metals:
            let ozPerLot = max(spec.contractSize, 1.0)
            let ounces = riskUSD / stopDist
            let lots = ounces / ozPerLot
            let notionalUSD = ounces * input.entryPrice
            return PositionSizeResult(
                riskAmountAccount: riskAccount,
                riskAmountUSD: riskUSD,
                stopDistancePrice: stopDist,
                stopDistancePips: nil,
                primaryQuantity: lots,
                primaryUnitLabel: "Lots (\(Int(ozPerLot.rounded())) oz)",
                secondaryQuantity: ounces,
                secondaryUnitLabel: "Troy Oz",
                estimatedNotionalUSD: notionalUSD,
                estimatedReward1Account: reward1Account,
                formulaSummary: "Risk $\(String(format: "%.2f", riskUSD)) ÷ $\(String(format: "%.2f", stopDist))/oz · \(Int(ozPerLot.rounded())) oz/lot",
                disclaimer: standardDisclaimer
            )

        case .indices:
            if upper == "SPY" || upper == "QQQ" {
                let shares = riskUSD / stopDist
                return PositionSizeResult(
                    riskAmountAccount: riskAccount,
                    riskAmountUSD: riskUSD,
                    stopDistancePrice: stopDist,
                    stopDistancePips: nil,
                    primaryQuantity: shares,
                    primaryUnitLabel: "Shares",
                    secondaryQuantity: nil,
                    secondaryUnitLabel: nil,
                    estimatedNotionalUSD: shares * input.entryPrice,
                    estimatedReward1Account: reward1Account,
                    formulaSummary: "Risk $\(String(format: "%.2f", riskUSD)) ÷ $\(String(format: "%.2f", stopDist))/share",
                    disclaimer: standardDisclaimer
                )
            }
            let dollarPerPoint = max(spec.contractSize, 1e-6) * max(spec.pointValue, 1e-6)
            let contracts = riskUSD / max(stopDist * dollarPerPoint, 1e-12)
            let notionalUSD = contracts * input.entryPrice * dollarPerPoint
            return PositionSizeResult(
                riskAmountAccount: riskAccount,
                riskAmountUSD: riskUSD,
                stopDistancePrice: stopDist,
                stopDistancePips: nil,
                primaryQuantity: contracts,
                primaryUnitLabel: "Contracts",
                secondaryQuantity: nil,
                secondaryUnitLabel: nil,
                estimatedNotionalUSD: notionalUSD,
                estimatedReward1Account: reward1Account,
                formulaSummary: "\(String(format: "%.1f", stopDist)) pts × $\(String(format: "%.2f", dollarPerPoint))/pt/contract",
                disclaimer: standardDisclaimer
            )

        case .crypto:
            let units = riskUSD / stopDist
            let baseTicker = upper.split(separator: "/").first.map(String.init) ?? upper
            return PositionSizeResult(
                riskAmountAccount: riskAccount,
                riskAmountUSD: riskUSD,
                stopDistancePrice: stopDist,
                stopDistancePips: nil,
                primaryQuantity: units,
                primaryUnitLabel: baseTicker,
                secondaryQuantity: nil,
                secondaryUnitLabel: nil,
                estimatedNotionalUSD: units * input.entryPrice,
                estimatedReward1Account: reward1Account,
                formulaSummary: "Risk $\(String(format: "%.2f", riskUSD)) ÷ $\(String(format: "%.4f", stopDist))/\(baseTicker)",
                disclaimer: standardDisclaimer
            )

        case .stocks:
            let shares = riskUSD / stopDist
            return PositionSizeResult(
                riskAmountAccount: riskAccount,
                riskAmountUSD: riskUSD,
                stopDistancePrice: stopDist,
                stopDistancePips: nil,
                primaryQuantity: shares,
                primaryUnitLabel: "Shares",
                secondaryQuantity: nil,
                secondaryUnitLabel: nil,
                estimatedNotionalUSD: shares * input.entryPrice,
                estimatedReward1Account: reward1Account,
                formulaSummary: "Risk $\(String(format: "%.2f", riskUSD)) ÷ $\(String(format: "%.2f", stopDist))/share",
                disclaimer: standardDisclaimer
            )
        }
    }
}
