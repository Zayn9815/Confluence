import Foundation
import SwiftUI
import SignalEngine

/// Persisted chart rendering engine selection (wired in Settings & `ConfluenceChartContainerView`).
public enum ChartEngineOption: String, Codable, Sendable, CaseIterable, Identifiable {
    case lightweightCharts = "lightweightCharts"
    case dgCharts = "dgCharts"
    case swiftTradingView = "swiftTradingView"
    case candleKit = "candleKit"

    public static let appStorageKey = "com.bilal.confluence.chartEngine"

    public var id: String { rawValue }

    /// Plain-English title shown in Settings pickers (free of restricted technical acronyms).
    public var displayLabel: String {
        switch self {
        case .lightweightCharts:
            return "TradingView LightweightCharts"
        case .dgCharts:
            return "DGCharts (Native CoreGraphics)"
        case .swiftTradingView:
            return "Swift Trading View (Multi-Pane SwiftUI)"
        case .candleKit:
            return "CandleKit (Native SwiftUI Canvas)"
        }
    }

    public var shortBadge: String {
        switch self {
        case .lightweightCharts: return "LightweightCharts"
        case .dgCharts: return "DGCharts"
        case .swiftTradingView: return "Swift Trading View"
        case .candleKit: return "CandleKit"
        }
    }

    public var subtitle: String {
        switch self {
        case .lightweightCharts:
            return "Default interactive candlestick chart with live price lines, markers, and crosshair readout."
        case .dgCharts:
            return "Native CoreGraphics engine slot (uses native SwiftUI Canvas fallback in Step 1)."
        case .swiftTradingView:
            return "Multi-pane SwiftUI engine slot (uses native SwiftUI Canvas fallback in Step 1)."
        case .candleKit:
            return "Native SwiftUI Canvas engine slot (uses native SwiftUI Canvas fallback in Step 1)."
        }
    }

    public var attributionLabel: String {
        switch self {
        case .lightweightCharts:
            return "TradingView Lightweight Charts"
        case .dgCharts:
            return "DGCharts (Canvas Preview)"
        case .swiftTradingView:
            return "Swift Trading View (Canvas Preview)"
        case .candleKit:
            return "CandleKit (Canvas Preview)"
        }
    }

    /// Indicates whether this engine natively renders price lines and candle markers in Step 1.
    /// Engines returning `false` automatically display the universal SwiftUI Signal Level HUD overlay.
    public var supportsNativeOverlayLines: Bool {
        self == .lightweightCharts
    }
}

/// Lightweight OHLCV snapshot emitted by chart crosshair movement for the top native SwiftUI HUD.
public struct ChartCrosshairReadout: Sendable, Equatable {
    public let epochSeconds: TimeInterval?
    public let open: Double
    public let high: Double
    public let low: Double
    public let close: Double
    public let isForming: Bool

    public init(
        epochSeconds: TimeInterval?,
        open: Double,
        high: Double,
        low: Double,
        close: Double,
        isForming: Bool = false
    ) {
        self.epochSeconds = epochSeconds
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.isForming = isForming
    }

    public var isBullish: Bool {
        close >= open
    }

    public var changePercent: Double? {
        guard open.isFinite, open > 0, close.isFinite else { return nil }
        let pct = ((close - open) / open) * 100.0
        return pct.isFinite ? pct : nil
    }
}

/// Shared chart adapter contract implemented by `LightweightChartsAdapterView` and Step-2 adapter slots
/// (`DGChartsAdapterView`, `SwiftTradingViewAdapterView`, `CandleKitAdapterView`).
@MainActor
public protocol ConfluenceChartAdapter: View {
    var candles: [Candle] { get }
    var formingCandle: Candle? { get }
    var liveTick: LiveTick? { get }
    var overlayModel: ChartSignalOverlayModel { get }
    var timeframe: Timeframe { get }
    var pricePrecision: ChartPricePrecision { get }
    var palette: ConfluencePalette { get }
    var isDark: Bool { get }
    var onCrosshairChange: (ChartCrosshairReadout?) -> Void { get }
}
