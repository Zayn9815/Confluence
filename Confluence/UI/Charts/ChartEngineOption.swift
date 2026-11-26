import Foundation
import SwiftUI
import SignalEngine

/// Persisted chart rendering engine selection (wired in Settings & `ConfluenceChartContainerView`).
public enum ChartEngineOption: String, Codable, Sendable, CaseIterable, Identifiable {
    case candleKit = "candleKit"
    case dgCharts = "dgCharts"
    case swiftTradingView = "swiftTradingView"
    case tradingViewWeb = "tradingViewWeb"

    public static let appStorageKey = "com.bilal.confluence.chartEngine"

    public var id: String { rawValue }

    /// Resolves any persisted UserDefaults/JSON raw value safely, migrating removed legacy engines
    /// (such as `"lightweightCharts"`) cleanly to `.candleKit`.
    public static func fromStoredRawValue(_ raw: String) -> ChartEngineOption {
        ChartEngineOption(rawValue: raw) ?? .candleKit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self)) ?? ""
        self = Self.fromStoredRawValue(raw)
    }

    /// Plain-English title shown in Settings pickers (free of restricted technical acronyms).
    public var displayLabel: String {
        switch self {
        case .candleKit:
            return "CandleKit (Native SwiftUI Canvas)"
        case .dgCharts:
            return "DGCharts (Native CoreGraphics)"
        case .swiftTradingView:
            return "Swift Trading View (Multi-Pane)"
        case .tradingViewWeb:
            return "TradingView Full Web (Persistent)"
        }
    }

    public var shortBadge: String {
        switch self {
        case .candleKit: return "CandleKit"
        case .dgCharts: return "DGCharts"
        case .swiftTradingView: return "Swift Trading View"
        case .tradingViewWeb: return "TradingView Web"
        }
    }

    public var subtitle: String {
        switch self {
        case .candleKit:
            return "Native 120Hz SwiftUI Canvas candlestick engine with momentum scroll, order lines, and volume."
        case .dgCharts:
            return "Native CoreGraphics candlestick engine with smooth pan/pinch, axis drag-to-scale, and limit lines."
        case .swiftTradingView:
            return "Multi-pane native SwiftUI Canvas chart with moving averages, volume pane, and inertia scroll."
        case .tradingViewWeb:
            return "Full persistent TradingView web workspace with saved login, Clean Mode, and 1-tap pair sync."
        }
    }

    public var attributionLabel: String {
        switch self {
        case .candleKit:
            return "CandleKit (Native SwiftUI)"
        case .dgCharts:
            return "DGCharts (Native CoreGraphics)"
        case .swiftTradingView:
            return "Swift Trading View (Multi-Pane)"
        case .tradingViewWeb:
            return "TradingView Full Web"
        }
    }

    /// Indicates whether this engine natively draws horizontal price lines on its own price scale.
    public var supportsNativeOverlayLines: Bool {
        switch self {
        case .candleKit, .dgCharts, .swiftTradingView:
            return true
        case .tradingViewWeb:
            return false
        }
    }
}

/// Pure-Swift replay marker replacing removed third-party chart marker types.
public enum ChartReplayMarkerPosition: String, Sendable, Equatable, Codable {
    case aboveBar
    case belowBar
}

public enum ChartReplayMarkerShape: String, Sendable, Equatable, Codable {
    case arrowUp
    case arrowDown
    case circle
    case square
}

public struct ChartReplayMarker: Sendable, Equatable, Identifiable, Codable {
    public let id: String
    public let timeEpochSeconds: TimeInterval
    public let position: ChartReplayMarkerPosition
    public let shape: ChartReplayMarkerShape
    public let colorHex: UInt32
    public let text: String
    public let size: Double

    public init(
        id: String,
        timeEpochSeconds: TimeInterval,
        position: ChartReplayMarkerPosition,
        shape: ChartReplayMarkerShape,
        colorHex: UInt32,
        text: String,
        size: Double = 1.4
    ) {
        self.id = id
        self.timeEpochSeconds = timeEpochSeconds
        self.position = position
        self.shape = shape
        self.colorHex = colorHex
        self.text = text
        self.size = size
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

/// Shared chart adapter contract implemented by `CandleKitAdapterView`, `DGChartsAdapterView`,
/// and `SwiftTradingViewAdapterView`.
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
    var resetTrigger: Int { get }
    var onCrosshairChange: (ChartCrosshairReadout?) -> Void { get }
}
