import Foundation
import SwiftUI
import SignalEngine

/// Persisted chart rendering engine selection (wired in Settings & `ConfluenceChartContainerView`).
public enum ChartEngineOption: String, Codable, Sendable, CaseIterable, Identifiable {
    case lightweightCharts = "lightweightCharts"
    case dgCharts = "dgCharts"
    case swiftTradingView = "swiftTradingView"
    case candleKit = "candleKit"
    case tradingViewWeb = "tradingViewWeb"

    public static let appStorageKey = "com.bilal.confluence.chartEngine"

    public var id: String { rawValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self)) ?? ""
        self = ChartEngineOption(rawValue: raw) ?? .lightweightCharts
    }

    /// Plain-English title shown in Settings pickers (free of restricted technical acronyms).
    public var displayLabel: String {
        switch self {
        case .lightweightCharts:
            return "TradingView LightweightCharts"
        case .dgCharts:
            return "DGCharts (Native CoreGraphics)"
        case .swiftTradingView:
            return "Swift Trading View (Multi-Pane)"
        case .candleKit:
            return "CandleKit (Native SwiftUI Canvas)"
        case .tradingViewWeb:
            return "TradingView Full Web (Persistent)"
        }
    }

    public var shortBadge: String {
        switch self {
        case .lightweightCharts: return "LightweightCharts"
        case .dgCharts: return "DGCharts"
        case .swiftTradingView: return "Swift Trading View"
        case .candleKit: return "CandleKit"
        case .tradingViewWeb: return "TradingView Web"
        }
    }

    public var subtitle: String {
        switch self {
        case .lightweightCharts:
            return "Default interactive candlestick chart with live price lines, markers, and crosshair readout."
        case .dgCharts:
            return "Native CoreGraphics candlestick engine with smooth pan/pinch, limit lines, and crosshair."
        case .swiftTradingView:
            return "Multi-pane SwiftUI chart with moving averages, volume pane, and floating signal levels."
        case .candleKit:
            return "Native 120Hz SwiftUI Canvas candlestick engine with momentum scroll, order lines, and volume."
        case .tradingViewWeb:
            return "Full persistent TradingView web workspace with saved login, Clean Mode, and 1-tap pair sync."
        }
    }

    public var attributionLabel: String {
        switch self {
        case .lightweightCharts:
            return "TradingView Lightweight Charts"
        case .dgCharts:
            return "DGCharts (Native CoreGraphics)"
        case .swiftTradingView:
            return "Swift Trading View"
        case .candleKit:
            return "CandleKit (Native SwiftUI)"
        case .tradingViewWeb:
            return "TradingView Full Web"
        }
    }

    /// Indicates whether this engine natively draws horizontal price lines on its own price scale.
    public var supportsNativeOverlayLines: Bool {
        switch self {
        case .lightweightCharts, .dgCharts, .candleKit:
            return true
        case .swiftTradingView, .tradingViewWeb:
            return false
        }
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

/// Unambiguous alias to SignalEngine's `Candle` model (avoids module/type name collision with `CandleKitCore.Candle`).
public typealias EngineCandle = Candle

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
