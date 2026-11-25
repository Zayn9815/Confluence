import Foundation

/// TradingView-style dynamic price precision & axis scale sizing shared across
/// `SignalEngine`, Signal Cards, Strategy Trades lists, and `LightweightCharts`.
public struct ChartPricePrecision: Codable, Sendable, Equatable, Hashable {
    public let precision: Int
    public let minMove: Double
    public let minimumPriceScaleWidth: Double

    public init(precision: Int, minMove: Double, minimumPriceScaleWidth: Double) {
        self.precision = precision
        self.minMove = minMove
        self.minimumPriceScaleWidth = minimumPriceScaleWidth
    }

    /// Resolves exact decimal precision & minMove from symbol, market class, and live reference price:
    /// - JPY pairs (e.g. `USD/JPY`): 3 decimals (`0.001`), e.g. `159.178`
    /// - Non-JPY Forex (e.g. `GBP/USD`, `EUR/USD`) or price `< 10.0`: 5 decimals (`0.00001`), e.g. `1.31002`
    /// - Sub-100 non-Forex instruments (`10.0 <= price < 100.0`): 4 decimals (`0.0001`)
    /// - Price `>= 100.0` (Gold, Crypto, Indices, Stocks): 2 decimals (`0.01`)
    public static func resolve(
        symbol: String,
        marketClass: MarketClass? = nil,
        referencePrice: Double? = nil
    ) -> ChartPricePrecision {
        let upper = symbol.uppercased()
        let descriptor = WatchlistDefaults.descriptor(for: symbol)
        let resolvedMarket = marketClass ?? descriptor?.marketClass

        if upper.contains("JPY") {
            return ChartPricePrecision(precision: 3, minMove: 0.001, minimumPriceScaleWidth: 68.0)
        }

        if resolvedMarket == .forex {
            return ChartPricePrecision(precision: 5, minMove: 0.00001, minimumPriceScaleWidth: 80.0)
        }

        if let price = referencePrice, price > 0 {
            if price < 10.0 {
                return ChartPricePrecision(precision: 5, minMove: 0.00001, minimumPriceScaleWidth: 80.0)
            }
            if price < 100.0 {
                return ChartPricePrecision(precision: 4, minMove: 0.0001, minimumPriceScaleWidth: 74.0)
            }
            return ChartPricePrecision(precision: 2, minMove: 0.01, minimumPriceScaleWidth: 66.0)
        }

        if let desc = descriptor {
            switch desc.priceDecimals {
            case 5: return ChartPricePrecision(precision: 5, minMove: 0.00001, minimumPriceScaleWidth: 80.0)
            case 4: return ChartPricePrecision(precision: 4, minMove: 0.0001, minimumPriceScaleWidth: 74.0)
            case 3: return ChartPricePrecision(precision: 3, minMove: 0.001, minimumPriceScaleWidth: 68.0)
            default: return ChartPricePrecision(precision: 2, minMove: 0.01, minimumPriceScaleWidth: 66.0)
            }
        }

        return ChartPricePrecision(precision: 2, minMove: 0.01, minimumPriceScaleWidth: 66.0)
    }

    public func format(_ price: Double) -> String {
        String(format: "%.\(precision)f", price)
    }
}
