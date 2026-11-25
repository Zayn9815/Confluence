import Foundation
import SignalEngine

public enum CryptoExchangePreference: String, Codable, Sendable, CaseIterable, Identifiable {
    case auto = "Auto (Binance -> OKX -> Kraken)"
    case binanceVision = "Binance Vision"
    case okx = "OKX"
    case kraken = "Kraken"
    case twelveData = "Twelve Data"

    public var id: String { rawValue }

    public var shortLabel: String {
        switch self {
        case .auto: return "Auto"
        case .binanceVision: return "Binance"
        case .okx: return "OKX"
        case .kraken: return "Kraken"
        case .twelveData: return "Twelve Data"
        }
    }
}

public struct OHLCVFetchResult: Sendable {
    public let candles: [Candle]
    public let providerName: String
    public let latencyMs: Double
    public let proxySymbolUsed: String?

    public init(candles: [Candle], providerName: String, latencyMs: Double, proxySymbolUsed: String? = nil) {
        self.candles = candles
        self.providerName = providerName
        self.latencyMs = latencyMs
        self.proxySymbolUsed = proxySymbolUsed
    }
}

public typealias ProviderLogHook = @Sendable (_ severity: String, _ category: String, _ message: String) -> Void

public struct CryptoOHLCVRouter: Sendable {
    private let http: any HTTPTransport
    private let twelveData: TwelveDataAdapter

    public init(http: any HTTPTransport, twelveData: TwelveDataAdapter? = nil) {
        self.http = http
        self.twelveData = twelveData ?? TwelveDataAdapter(http: http)
    }

    public func fetchCandles(
        asset: AssetDescriptor,
        timeframe: Timeframe,
        limit: Int = 220,
        primary: CryptoExchangePreference = .auto,
        twelveDataKey: String? = nil,
        onLog: ProviderLogHook? = nil
    ) async throws -> OHLCVFetchResult {
        let order: [CryptoExchangePreference]
        switch primary {
        case .auto, .binanceVision:
            order = [.binanceVision, .okx, .kraken]
        case .okx:
            order = [.okx, .binanceVision, .kraken]
        case .kraken:
            order = [.kraken, .binanceVision, .okx]
        case .twelveData:
            order = [.twelveData, .binanceVision, .okx, .kraken]
        }

        var errors: [String] = []
        for (idx, venue) in order.enumerated() {
            do {
                let result: OHLCVFetchResult
                switch venue {
                case .auto, .binanceVision:
                    result = try await fetchBinanceVision(asset: asset, timeframe: timeframe, limit: limit)
                case .okx:
                    result = try await fetchOKX(asset: asset, timeframe: timeframe, limit: limit)
                case .kraken:
                    result = try await fetchKraken(asset: asset, timeframe: timeframe)
                case .twelveData:
                    guard let key = twelveDataKey, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw NetworkAdapterError.missingAPIKey("Twelve Data")
                    }
                    result = try await twelveData.fetchCandles(asset: asset, timeframe: timeframe, apiKey: key)
                }
                if idx > 0 {
                    onLog?("WARN", "Fallback", "\(asset.symbol) \(timeframe.displayLabel): fell back to \(result.providerName)")
                }
                return result
            } catch {
                let reason = "\(venue.shortLabel): \(error.localizedDescription)"
                errors.append(reason)
                onLog?("WARN", "Feed", "\(asset.symbol) \(timeframe.displayLabel) \(reason)")
            }
        }
        throw NetworkAdapterError.allProvidersFailed(errors)
    }

    private func fetchBinanceVision(asset: AssetDescriptor, timeframe: Timeframe, limit: Int) async throws -> OHLCVFetchResult {
        guard let sym = asset.binanceSymbol else {
            throw NetworkAdapterError.invalidURL("Missing Binance symbol for \(asset.symbol)")
        }
        let interval = timeframe.rawValue
        let urlStr = "https://data-api.binance.vision/api/v3/klines?symbol=\(sym)&interval=\(interval)&limit=\(min(limit, 500))"
        guard let url = URL(string: urlStr) else { throw NetworkAdapterError.invalidURL(urlStr) }

        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let res = try await http.send(req, maxRetries: 2)

        guard let rawRows = try JSONSerialization.jsonObject(with: res.data) as? [[Any]] else {
            throw NetworkAdapterError.decodingFailed("Binance klines root is not array")
        }

        let nowSec = (res.serverDate ?? Date()).timeIntervalSince1970
        var out: [Candle] = []
        out.reserveCapacity(rawRows.count)

        for row in rawRows where row.count >= 7 {
            guard let openMs = asDouble(row[0]),
                  let o = asDouble(row[1]),
                  let h = asDouble(row[2]),
                  let l = asDouble(row[3]),
                  let c = asDouble(row[4]),
                  let v = asDouble(row[5]),
                  let closeMs = asDouble(row[6])
            else { continue }

            let openSec = openMs / 1000.0
            let closeSec = (closeMs + 1.0) / 1000.0
            let isClosed = closeSec <= nowSec
            out.append(Candle(
                openTimeEpochSeconds: openSec,
                closeTimeEpochSeconds: closeSec,
                open: o, high: h, low: l, close: c,
                volume: v, isClosed: isClosed
            ))
        }
        return OHLCVFetchResult(candles: out, providerName: "Binance Vision", latencyMs: res.latencyMs)
    }

    private func fetchOKX(asset: AssetDescriptor, timeframe: Timeframe, limit: Int) async throws -> OHLCVFetchResult {
        let instId = "\(asset.baseCurrency)-\(asset.quoteCurrency)"
        let bar: String
        switch timeframe {
        case .m15: bar = "15m"
        case .h1: bar = "1H"
        case .h4: bar = "4H"
        case .d1: bar = "1Dutc"
        }
        let urlStr = "https://www.okx.com/api/v5/market/candles?instId=\(instId)&bar=\(bar)&limit=\(min(limit, 300))"
        guard let url = URL(string: urlStr) else { throw NetworkAdapterError.invalidURL(urlStr) }

        let res = try await http.send(URLRequest(url: url), maxRetries: 2)
        struct OKXResponse: Decodable {
            let code: String
            let data: [[String]]?
        }
        let decoded = try JSONDecoder().decode(OKXResponse.self, from: res.data)
        guard decoded.code == "0", let rows = decoded.data else {
            throw NetworkAdapterError.decodingFailed("OKX code=\(decoded.code)")
        }

        // OKX returns newest-first; normalize to ascending UTC and honor confirm=="1"
        var out: [Candle] = []
        for row in rows.reversed() where row.count >= 9 {
            guard let tsMs = Double(row[0]),
                  let o = Double(row[1]),
                  let h = Double(row[2]),
                  let l = Double(row[3]),
                  let c = Double(row[4]),
                  let v = Double(row[5])
            else { continue }
            let confirmed = (row[8] == "1")
            let openSec = tsMs / 1000.0
            out.append(Candle(
                openTimeEpochSeconds: openSec,
                closeTimeEpochSeconds: openSec + timeframe.seconds,
                open: o, high: h, low: l, close: c,
                volume: v, isClosed: confirmed
            ))
        }
        return OHLCVFetchResult(candles: out, providerName: "OKX", latencyMs: res.latencyMs)
    }

    private func fetchKraken(asset: AssetDescriptor, timeframe: Timeframe) async throws -> OHLCVFetchResult {
        guard let pair = asset.krakenPair else {
            throw NetworkAdapterError.invalidURL("Missing Kraken pair for \(asset.symbol)")
        }
        let intervalMins: Int
        switch timeframe {
        case .m15: intervalMins = 15
        case .h1: intervalMins = 60
        case .h4: intervalMins = 240
        case .d1: intervalMins = 1440
        }
        let urlStr = "https://api.kraken.com/0/public/OHLC?pair=\(pair)&interval=\(intervalMins)"
        guard let url = URL(string: urlStr) else { throw NetworkAdapterError.invalidURL(urlStr) }

        let res = try await http.send(URLRequest(url: url), maxRetries: 1)
        guard let root = try JSONSerialization.jsonObject(with: res.data) as? [String: Any],
              let resultObj = root["result"] as? [String: Any]
        else {
            throw NetworkAdapterError.decodingFailed("Kraken invalid payload")
        }

        let nowSec = (res.serverDate ?? Date()).timeIntervalSince1970
        var out: [Candle] = []
        for (key, val) in resultObj where key != "last" {
            guard let rows = val as? [[Any]] else { continue }
            for row in rows where row.count >= 7 {
                guard let openSec = asDouble(row[0]),
                      let o = asDouble(row[1]),
                      let h = asDouble(row[2]),
                      let l = asDouble(row[3]),
                      let c = asDouble(row[4]),
                      let v = asDouble(row[6])
                else { continue }
                let closeSec = openSec + timeframe.seconds
                out.append(Candle(
                    openTimeEpochSeconds: openSec,
                    closeTimeEpochSeconds: closeSec,
                    open: o, high: h, low: l, close: c,
                    volume: v, isClosed: closeSec <= nowSec
                ))
            }
            break
        }
        return OHLCVFetchResult(candles: out, providerName: "Kraken", latencyMs: res.latencyMs)
    }

    private func asDouble(_ any: Any) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String { return Double(s) }
        return nil
    }
}
