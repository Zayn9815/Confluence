import Foundation

public enum MarketClass: String, Codable, Sendable, CaseIterable, Hashable {
    case crypto
    case forex
    case metals
    case indices
    case stocks

    public var displayName: String {
        switch self {
        case .crypto: return "Crypto"
        case .forex: return "Forex"
        case .metals: return "Gold"
        case .indices: return "Indices"
        case .stocks: return "Stocks"
        }
    }

    public var is24x7: Bool {
        self == .crypto
    }

    /// Typical round-trip fee + slippage estimate in basis points for walk-forward realism.
    public var defaultRoundTripCostBps: Double {
        switch self {
        case .crypto: return 15.0
        case .forex: return 2.5
        case .metals: return 4.0
        case .indices: return 3.0
        case .stocks: return 3.0
        }
    }

    public var defaultMaxStopLossPercent: Double {
        switch self {
        case .crypto, .stocks: return 3.0
        case .forex, .metals, .indices: return 1.5
        }
    }

    /// True for OTC feeds where reliable centralized exchange volume is unavailable.
    public var isOTCVolumeUnavailable: Bool {
        switch self {
        case .forex, .metals: return true
        case .crypto, .indices, .stocks: return false
        }
    }
}

public enum Timeframe: String, Codable, Sendable, CaseIterable, Hashable {
    case m15 = "15m"
    case h1 = "1h"
    case h4 = "4h"
    case d1 = "1d"

    public var seconds: TimeInterval {
        switch self {
        case .m15: return 900
        case .h1: return 3_600
        case .h4: return 14_400
        case .d1: return 86_400
        }
    }

    public var displayLabel: String {
        switch self {
        case .m15: return "15m"
        case .h1: return "1H"
        case .h4: return "4H"
        case .d1: return "1D"
        }
    }
}

public enum TradeDirection: String, Codable, Sendable, Hashable {
    case long
    case short
    case neutral

    public var opposite: TradeDirection {
        switch self {
        case .long: return .short
        case .short: return .long
        case .neutral: return .neutral
        }
    }
}

public enum SignalCategory: String, Codable, Sendable, Hashable {
    case strongSignal = "STRONG_SIGNAL"
    case weakSignal = "WEAK_SIGNAL"
    case trapAlert = "TRAP_ALERT"
}

public enum SignalTier: String, Codable, Sendable, Hashable {
    case aPlusInstitutional
    case highConviction
    case aligned
    case weakFiltered
    case trapWarning

    public var displayName: String {
        switch self {
        case .aPlusInstitutional: return "A+ Institutional"
        case .highConviction: return "High Conviction"
        case .aligned: return "Aligned"
        case .weakFiltered: return "Weak / Filtered"
        case .trapWarning: return "Trap Warning"
        }
    }
}

public enum MarketRegime: String, Codable, Sendable, Hashable {
    case trending
    case meanReverting
    case highVol
    case crisis

    public var badgeLabel: String {
        switch self {
        case .trending: return "TRENDING"
        case .meanReverting: return "MEAN REVERT"
        case .highVol: return "HIGH VOL"
        case .crisis: return "CRISIS"
        }
    }
}

public enum RiskState: String, Codable, Sendable, Hashable {
    case safe
    case nearLimit = "near_limit"
    case reduce
}

public enum KillzoneSession: String, Codable, Sendable, Hashable {
    case london
    case newYork
    case londonClose
    case asian
    case offSession

    public var displayName: String {
        switch self {
        case .london: return "London KZ"
        case .newYork: return "NY KZ"
        case .londonClose: return "London Close"
        case .asian: return "Asian"
        case .offSession: return "Off-Session"
        }
    }

    public var isPrimeLiquidity: Bool {
        self == .london || self == .newYork || self == .londonClose
    }
}

public enum StrategyGroup: String, Codable, Sendable, CaseIterable, Hashable {
    case ictSmc
    case candlestick
    case trendMomentum
    case behavioralTrap
    case macroCatalyst

    public var displayName: String {
        switch self {
        case .ictSmc: return "ICT / Smart Money"
        case .candlestick: return "Candlestick Action"
        case .trendMomentum: return "EMA / RSI / ATR"
        case .behavioralTrap: return "Behavioral Trap"
        case .macroCatalyst: return "Macro Catalyst"
        }
    }
}

public struct AssetDescriptor: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String { symbol }
    public let symbol: String
    public let displayName: String
    public let marketClass: MarketClass
    public let baseCurrency: String
    public let quoteCurrency: String
    public let binanceSymbol: String?
    public let okxSwapInstId: String?
    public let krakenPair: String?
    public let yahooSymbol: String?
    public let biquoteSymbol: String?
    public let twelveDataSymbol: String?
    public let cftcContractCode: String?
    public let cftcDataset: String?
    public let roundNumberStep: Double
    public let priceDecimals: Int

    public init(
        symbol: String,
        displayName: String,
        marketClass: MarketClass,
        baseCurrency: String,
        quoteCurrency: String,
        binanceSymbol: String? = nil,
        okxSwapInstId: String? = nil,
        krakenPair: String? = nil,
        yahooSymbol: String? = nil,
        biquoteSymbol: String? = nil,
        twelveDataSymbol: String? = nil,
        cftcContractCode: String? = nil,
        cftcDataset: String? = nil,
        roundNumberStep: Double,
        priceDecimals: Int
    ) {
        self.symbol = symbol
        self.displayName = displayName
        self.marketClass = marketClass
        self.baseCurrency = baseCurrency
        self.quoteCurrency = quoteCurrency
        self.binanceSymbol = binanceSymbol
        self.okxSwapInstId = okxSwapInstId
        self.krakenPair = krakenPair
        self.yahooSymbol = yahooSymbol
        self.biquoteSymbol = biquoteSymbol
        self.twelveDataSymbol = twelveDataSymbol
        self.cftcContractCode = cftcContractCode
        self.cftcDataset = cftcDataset
        self.roundNumberStep = roundNumberStep
        self.priceDecimals = priceDecimals
    }

    public var exposedMacroCurrencies: Set<String> {
        switch marketClass {
        case .crypto:
            return ["USD"]
        case .forex:
            return [baseCurrency, quoteCurrency]
        case .metals:
            return ["USD", "XAU"]
        case .indices, .stocks:
            return ["USD"]
        }
    }
}

public enum WatchlistDefaults {
    public static let assets: [AssetDescriptor] = [
        // Crypto
        AssetDescriptor(
            symbol: "BTC/USDT",
            displayName: "Bitcoin",
            marketClass: .crypto,
            baseCurrency: "BTC",
            quoteCurrency: "USDT",
            binanceSymbol: "BTCUSDT",
            okxSwapInstId: "BTC-USDT-SWAP",
            krakenPair: "XBTUSDT",
            yahooSymbol: "BTC-USD",
            biquoteSymbol: "BTCUSD",
            twelveDataSymbol: "BTC/USD",
            cftcContractCode: "133741",
            cftcDataset: "gpe5-46if",
            roundNumberStep: 1_000.0,
            priceDecimals: 2
        ),
        AssetDescriptor(
            symbol: "ETH/USDT",
            displayName: "Ethereum",
            marketClass: .crypto,
            baseCurrency: "ETH",
            quoteCurrency: "USDT",
            binanceSymbol: "ETHUSDT",
            okxSwapInstId: "ETH-USDT-SWAP",
            krakenPair: "ETHUSDT",
            yahooSymbol: "ETH-USD",
            biquoteSymbol: "ETHUSD",
            twelveDataSymbol: "ETH/USD",
            cftcContractCode: nil,
            cftcDataset: nil,
            roundNumberStep: 50.0,
            priceDecimals: 2
        ),
        AssetDescriptor(
            symbol: "SOL/USDT",
            displayName: "Solana",
            marketClass: .crypto,
            baseCurrency: "SOL",
            quoteCurrency: "USDT",
            binanceSymbol: "SOLUSDT",
            okxSwapInstId: "SOL-USDT-SWAP",
            krakenPair: "SOLUSDT",
            yahooSymbol: "SOL-USD",
            biquoteSymbol: "SOLUSD",
            twelveDataSymbol: "SOL/USD",
            cftcContractCode: nil,
            cftcDataset: nil,
            roundNumberStep: 5.0,
            priceDecimals: 2
        ),
        // Forex
        AssetDescriptor(
            symbol: "EUR/USD",
            displayName: "Euro / US Dollar",
            marketClass: .forex,
            baseCurrency: "EUR",
            quoteCurrency: "USD",
            yahooSymbol: "EURUSD=X",
            biquoteSymbol: "EURUSD",
            twelveDataSymbol: "EUR/USD",
            cftcContractCode: "099741",
            cftcDataset: "gpe5-46if",
            roundNumberStep: 0.0050,
            priceDecimals: 5
        ),
        AssetDescriptor(
            symbol: "GBP/USD",
            displayName: "British Pound / US Dollar",
            marketClass: .forex,
            baseCurrency: "GBP",
            quoteCurrency: "USD",
            yahooSymbol: "GBPUSD=X",
            biquoteSymbol: "GBPUSD",
            twelveDataSymbol: "GBP/USD",
            cftcContractCode: "096742",
            cftcDataset: "gpe5-46if",
            roundNumberStep: 0.0050,
            priceDecimals: 5
        ),
        AssetDescriptor(
            symbol: "USD/JPY",
            displayName: "US Dollar / Japanese Yen",
            marketClass: .forex,
            baseCurrency: "USD",
            quoteCurrency: "JPY",
            yahooSymbol: "USDJPY=X",
            biquoteSymbol: "USDJPY",
            twelveDataSymbol: "USD/JPY",
            cftcContractCode: "097741",
            cftcDataset: "gpe5-46if",
            roundNumberStep: 0.50,
            priceDecimals: 3
        ),
        // Gold / Metals
        AssetDescriptor(
            symbol: "XAU/USD",
            displayName: "Gold Spot / USD",
            marketClass: .metals,
            baseCurrency: "XAU",
            quoteCurrency: "USD",
            yahooSymbol: "GC=F",
            biquoteSymbol: "XAUUSD",
            twelveDataSymbol: "XAU/USD",
            cftcContractCode: "088691",
            cftcDataset: "72hh-3qpy",
            roundNumberStep: 10.0,
            priceDecimals: 2
        ),
        // Indices
        AssetDescriptor(
            symbol: "US500",
            displayName: "S&P 500 Index",
            marketClass: .indices,
            baseCurrency: "SPX",
            quoteCurrency: "USD",
            yahooSymbol: "^GSPC",
            biquoteSymbol: "US500",
            twelveDataSymbol: "SPX",
            cftcContractCode: "13874A",
            cftcDataset: "gpe5-46if",
            roundNumberStep: 50.0,
            priceDecimals: 2
        ),
        AssetDescriptor(
            symbol: "NAS100",
            displayName: "Nasdaq 100 Index",
            marketClass: .indices,
            baseCurrency: "NDX",
            quoteCurrency: "USD",
            yahooSymbol: "^NDX",
            biquoteSymbol: "USTEC",
            twelveDataSymbol: "NDX",
            cftcContractCode: "209742",
            cftcDataset: "gpe5-46if",
            roundNumberStep: 100.0,
            priceDecimals: 2
        ),
        // US Stocks
        AssetDescriptor(
            symbol: "AAPL",
            displayName: "Apple Inc.",
            marketClass: .stocks,
            baseCurrency: "AAPL",
            quoteCurrency: "USD",
            yahooSymbol: "AAPL",
            biquoteSymbol: "AAPL",
            twelveDataSymbol: "AAPL",
            roundNumberStep: 5.0,
            priceDecimals: 2
        ),
        AssetDescriptor(
            symbol: "NVDA",
            displayName: "NVIDIA Corp.",
            marketClass: .stocks,
            baseCurrency: "NVDA",
            quoteCurrency: "USD",
            yahooSymbol: "NVDA",
            biquoteSymbol: "NVDA",
            twelveDataSymbol: "NVDA",
            roundNumberStep: 5.0,
            priceDecimals: 2
        ),
        AssetDescriptor(
            symbol: "MSFT",
            displayName: "Microsoft Corp.",
            marketClass: .stocks,
            baseCurrency: "MSFT",
            quoteCurrency: "USD",
            yahooSymbol: "MSFT",
            biquoteSymbol: "MSFT",
            twelveDataSymbol: "MSFT",
            roundNumberStep: 5.0,
            priceDecimals: 2
        )
    ]

    public static func descriptor(for symbol: String) -> AssetDescriptor? {
        assets.first { $0.symbol.caseInsensitiveCompare(symbol) == .orderedSame }
    }
}
