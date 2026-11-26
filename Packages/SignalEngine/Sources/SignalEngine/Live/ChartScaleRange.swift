import Foundation

public struct OffScaleOverlayNotice: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let label: String
    public let price: Double
    public let deviationPercent: Double

    public init(id: String, label: String, price: Double, deviationPercent: Double) {
        self.id = id
        self.label = label
        self.price = price
        self.deviationPercent = deviationPercent
    }
}

public struct ChartScaleResult: Codable, Sendable, Equatable {
    public let minPrice: Double
    public let maxPrice: Double
    public let offScaleOverlays: [OffScaleOverlayNotice]

    public init(minPrice: Double, maxPrice: Double, offScaleOverlays: [OffScaleOverlayNotice]) {
        self.minPrice = minPrice
        self.maxPrice = maxPrice
        self.offScaleOverlays = offScaleOverlays
    }
}

/// Computes a clean visible Y-axis range from visible candles + Entry/Stop loss/Target 1
/// plus any Trap or Target 2 lines within ±20% of current price, padding top/bottom by ~10-12%.
/// Extreme (>20%) overlays are NEVER deleted from the chart; instead they are surfaced as
/// `offScaleOverlays` chips in the collapsible Risk strip so the price axis does not stretch.
public enum ChartScaleRange {
    public static func compute(
        candles: [Candle],
        levels: TradeLevels?,
        traps: [BehavioralTrap] = [],
        maxOverlayDeviationFraction: Double = 0.20,
        marginFraction: Double = 0.11
    ) -> ChartScaleResult? {
        let validCandles = candles.filter {
            $0.low.isFinite && $0.high.isFinite && $0.close.isFinite && $0.low > 0 && $0.high >= $0.low
        }
        guard let lastClose = validCandles.last?.close, lastClose > 0 else { return nil }

        var minY = validCandles.map(\.low).min() ?? lastClose
        var maxY = validCandles.map(\.high).max() ?? lastClose
        var offScale: [OffScaleOverlayNotice] = []

        func considerOverlay(id: String, label: String, price: Double, alwaysIncludeCore: Bool) {
            guard price.isFinite, price > 0 else { return }
            let deviation = abs(price - lastClose) / lastClose
            let effectiveLimit = alwaysIncludeCore
                ? maxOverlayDeviationFraction * 1.5
                : maxOverlayDeviationFraction
            if deviation <= effectiveLimit {
                minY = min(minY, price)
                maxY = max(maxY, price)
            } else {
                offScale.append(
                    OffScaleOverlayNotice(
                        id: id,
                        label: label,
                        price: price,
                        deviationPercent: deviation * 100.0
                    )
                )
            }
        }

        if let lv = levels {
            considerOverlay(id: "entry", label: "Entry", price: lv.entryMid, alwaysIncludeCore: true)
            considerOverlay(id: "sl", label: "Stop loss", price: lv.stopLoss, alwaysIncludeCore: true)
            considerOverlay(id: "t1", label: "Target 1", price: lv.tp1, alwaysIncludeCore: true)
            if lv.isTP2Enabled {
                considerOverlay(id: "t2", label: "Target 2", price: lv.tp2, alwaysIncludeCore: false)
            }
        }

        for trap in traps where trap.isActionable {
            considerOverlay(
                id: "trap_\(trap.id)",
                label: trap.direction.rawValue,
                price: trap.level,
                alwaysIncludeCore: false
            )
        }

        let span = max(maxY - minY, lastClose * 0.002)
        let pad = span * max(0.02, min(marginFraction, 0.30))
        let paddedMin = max(1e-8, minY - pad)
        let paddedMax = maxY + pad

        return ChartScaleResult(
            minPrice: paddedMin,
            maxPrice: paddedMax,
            offScaleOverlays: offScale
        )
    }
}
