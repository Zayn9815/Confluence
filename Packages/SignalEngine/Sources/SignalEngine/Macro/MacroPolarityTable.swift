import Foundation

public enum MacroPolarityTable {
    /// Maps raw multi-source indicator names (e.g., `mql5` "CPI y/y" or `fxempire` "Inflation Rate YoY")
    /// to a canonical indicator key for deterministic polarity lookup.
    public static func canonicalIndicator(for rawName: String) -> CanonicalMacroIndicator? {
        let lower = rawName.lowercased()

        if lower.contains("core cpi") || (lower.contains("core") && lower.contains("inflation")) {
            return .coreCpi
        }
        if lower.contains("cpi") || lower.contains("consumer price index") || lower.contains("inflation rate") {
            return .cpi
        }
        if lower.contains("core pce") {
            return .corePce
        }
        if lower.contains("pce price") || lower.contains("personal consumption expenditures") {
            return .pce
        }
        if lower.contains("nonfarm payroll") || lower.contains("non-farm payroll") || lower.contains("non-farm employment") {
            return .nfp
        }
        if lower.contains("unemployment rate") || lower.contains("jobless rate") {
            return .unemploymentRate
        }
        if lower.contains("initial jobless") || lower.contains("unemployment claims") {
            return .initialJoblessClaims
        }
        if lower.contains("interest rate") || lower.contains("fed funds") || lower.contains("rate decision") || lower.contains("fomc") || lower.contains("ecb rate") || lower.contains("boe rate") || lower.contains("boj rate") {
            return .centralBankRate
        }
        if lower.contains("gdp") || lower.contains("gross domestic product") {
            return .gdp
        }
        if lower.contains("retail sales") {
            return .retailSales
        }
        if lower.contains("ism") || lower.contains("pmi") {
            return .ismPmi
        }
        if lower.contains("ppi") || lower.contains("producer price") {
            return .ppi
        }
        if lower.contains("average hourly earnings") || lower.contains("wage growth") {
            return .averageHourlyEarnings
        }
        return nil
    }

    /// True if a HIGHER-than-forecast reading is hawkish / bullish for the publishing currency.
    /// False if a HIGHER-than-forecast reading is dovish / bearish (e.g. Unemployment Rate, Jobless Claims).
    public static func isHigherHawkish(for indicator: CanonicalMacroIndicator) -> Bool {
        switch indicator {
        case .unemploymentRate, .initialJoblessClaims:
            return false
        case .cpi, .coreCpi, .pce, .corePce, .nfp, .centralBankRate,
             .gdp, .retailSales, .ismPmi, .ppi, .averageHourlyEarnings:
            return true
        }
    }

    /// Relative macro market-moving weight for simultaneous release cluster resolution.
    public static func clusterWeight(for indicator: CanonicalMacroIndicator?) -> Double {
        switch indicator {
        case .centralBankRate: return 3.0
        case .cpi, .coreCpi, .nfp: return 2.5
        case .pce, .corePce, .unemploymentRate: return 2.0
        case .gdp, .retailSales, .ismPmi, .ppi, .averageHourlyEarnings: return 1.3
        case .initialJoblessClaims: return 1.0
        case nil: return 0.8
        }
    }

    /// Maps a publishing currency's hawkish/dovish stance into concrete cross-market directional impacts.
    public static func directionalImpacts(currency: String, stance: MacroStance) -> [AssetMacroImpact] {
        let ccy = currency.uppercased()
        guard stance == .hawkish || stance == .dovish else {
            return [AssetMacroImpact(assetLabel: ccy, direction: .neutral)]
        }

        let isHawkish = (stance == .hawkish)
        switch ccy {
        case "USD":
            return [
                AssetMacroImpact(assetLabel: "USD", direction: isHawkish ? .long : .short),
                AssetMacroImpact(assetLabel: "XAU/USD", direction: isHawkish ? .short : .long),
                AssetMacroImpact(assetLabel: "BTC/USDT", direction: isHawkish ? .short : .long),
                AssetMacroImpact(assetLabel: "US500", direction: isHawkish ? .short : .long),
                AssetMacroImpact(assetLabel: "EUR/USD", direction: isHawkish ? .short : .long),
                AssetMacroImpact(assetLabel: "USD/JPY", direction: isHawkish ? .long : .short)
            ]
        case "EUR":
            return [
                AssetMacroImpact(assetLabel: "EUR/USD", direction: isHawkish ? .long : .short)
            ]
        case "GBP":
            return [
                AssetMacroImpact(assetLabel: "GBP/USD", direction: isHawkish ? .long : .short)
            ]
        case "JPY":
            return [
                AssetMacroImpact(assetLabel: "USD/JPY", direction: isHawkish ? .short : .long)
            ]
        default:
            return [AssetMacroImpact(assetLabel: ccy, direction: isHawkish ? .long : .short)]
        }
    }

    /// Computes directional impact for a specific AssetDescriptor given a currency stance.
    public static func impactDirection(for asset: AssetDescriptor, currency: String, stance: MacroStance) -> TradeDirection {
        guard stance == .hawkish || stance == .dovish else { return .neutral }
        let ccy = currency.uppercased()
        let isHawkish = (stance == .hawkish)

        switch asset.marketClass {
        case .forex:
            if asset.baseCurrency.uppercased() == ccy {
                return isHawkish ? .long : .short
            }
            if asset.quoteCurrency.uppercased() == ccy {
                return isHawkish ? .short : .long
            }
            return .neutral
        case .metals, .crypto, .indices, .stocks:
            if ccy == "USD" {
                return isHawkish ? .short : .long
            }
            return .neutral
        }
    }
}
