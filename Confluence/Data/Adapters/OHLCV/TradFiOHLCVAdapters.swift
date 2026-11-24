import Foundation
import SignalEngine

public struct TradFiOHLCVRouter: Sendable {
    private let http: any HTTPTransport
    private let twelveDataPacer: ProviderRatePacer

    public init(
        http: any HTTPTransport,
        twelveDataPacer: ProviderRatePacer = ProviderRatePacer(providerKey: "twelvedata", maxPerMinute: 7, maxPerUTCDay: 760)
    ) {
        self.http = http
        self.twelveDataPacer = twelveDataPacer
    }

    public func fetchCandles(
        asset: AssetDescriptor,
        timeframe: Timeframe,
        twelveDataKey: String?
    ) async throws -> OHLCVFetchResult {
        var errors: [String] = []

        // 1. Optional Twelve Data REST adapter when user supplies their free key (paced at <=7/min, <=760/day)
        if let key = twelveDataKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            do {
                return try await fetchTwelveData(asset: asset, timeframe: timeframe, apiKey: key)
            } catch {
                errors.append("Twelve Data: \(error.localizedDescription)")
            }
        }

        // 2. Keyless Yahoo Finance v8/finance/chart (minimal User-Agent: Mozilla/5.0 + query1->query2 + causal 1h->4h resample)
        do {
            return try await fetchYahooFinance(asset: asset, timeframe: timeframe)
        } catch {
            errors.append("Yahoo Finance: \(error.localizedDescription)")
        }

        // 3. Keyless biquote.io OHLC fallback (strong for EURUSD, GBPUSD, USDJPY, XAUUSD, US500)
        if asset.biquoteSymbol != nil {
            do {
                return try await fetchBiquoteOHLC(asset: asset, timeframe: timeframe)
            } catch {
                errors.append("biquote OHLC: \(error.localizedDescription)")
            }
        }

        throw NetworkAdapterError.allProvidersFailed(errors)
    }

    private func fetchYahooFinance(asset: AssetDescriptor, timeframe: Timeframe) async throws -> OHLCVFetchResult {
        guard let rawSym = asset.yahooSymbol,
              let encoded = rawSym.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else {
            throw NetworkAdapterError.invalidURL("Missing Yahoo symbol for \(asset.symbol)")
        }

        // Yahoo has no native 4h interval; fetch 1h over 60d and causally resample to UTC 4h
        let yahooInterval: String
        let yahooRange: String
        let needs4HResample: Bool
        switch timeframe {
        case .m15:
            yahooInterval = "15m"; yahooRange = "10d"; needs4HResample = false
        case .h1:
            yahooInterval = "1h"; yahooRange = "30d"; needs4HResample = false
        case .h4:
            yahooInterval = "1h"; yahooRange = "60d"; needs4HResample = true
        case .d1:
            yahooInterval = "1d"; yahooRange = "1y"; needs4HResample = false
        }

        let hosts = ["query1.finance.yahoo.com", "query2.finance.yahoo.com"]
        var lastErr: Error = NetworkAdapterError.httpStatus(0, "Yahoo failed")

        for host in hosts {
            let urlStr = "https://\(host)/v8/finance/chart/\(encoded)?interval=\(yahooInterval)&range=\(yahooRange)&includePrePost=false"
            guard let url = URL(string: urlStr) else { continue }
            var req = URLRequest(url: url)
            // Verified Oct 2026 fix: minimal Mozilla/5.0 avoids Yahoo ATS desktop-UA 429 false blocks
            req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            req.setValue("application/json", forHTTPHeaderField: "Accept")

            do {
                let res = try await http.send(req, maxRetries: 1)
                let candles = try Self.parseYahooChartJSON(
                    data: res.data,
                    timeframe: needs4HResample ? .h1 : timeframe,
                    marketClass: asset.marketClass,
                    serverNowEpochSeconds: (res.serverDate ?? Date()).timeIntervalSince1970
                )
                let finalBars = needs4HResample
                    ? CandleHygieneEngine.resample1HTo4H(hourlyCandles: candles, serverNowEpochSeconds: (res.serverDate ?? Date()).timeIntervalSince1970)
                    : candles
                return OHLCVFetchResult(candles: finalBars, providerName: "Yahoo Finance", latencyMs: res.latencyMs)
            } catch {
                lastErr = error
            }
        }
        throw lastErr
    }

    public static func parseYahooChartJSON(
        data: Data,
        timeframe: Timeframe,
        marketClass: MarketClass,
        serverNowEpochSeconds: TimeInterval
    ) throws -> [Candle] {
        struct YahooRoot: Decodable {
            struct Chart: Decodable {
                struct Result: Decodable {
                    struct Indicators: Decodable {
                        struct Quote: Decodable {
                            let open: [Double?]?
                            let high: [Double?]?
                            let low: [Double?]?
                            let close: [Double?]?
                            let volume: [Double?]?
                        }
                        let quote: [Quote]?
                    }
                    let timestamp: [TimeInterval]?
                    let indicators: Indicators?
                }
                let result: [Result]?
            }
            let chart: Chart
        }

        let decoded = try JSONDecoder().decode(YahooRoot.self, from: data)
        guard let first = decoded.chart.result?.first,
              let timestamps = first.timestamp,
              let quote = first.indicators?.quote?.first,
              let opens = quote.open,
              let highs = quote.high,
              let lows = quote.low,
              let closes = quote.close
        else {
            throw NetworkAdapterError.decodingFailed("Yahoo chart missing OHLC arrays")
        }

        let volumes = quote.volume
        let count = min(timestamps.count, opens.count, highs.count, lows.count, closes.count)
        var out: [Candle] = []
        out.reserveCapacity(count)

        for i in 0..<count {
            guard let o = opens[i], let h = highs[i], let l = lows[i], let c = closes[i] else {
                continue
            }
            let openSec = timestamps[i]
            let closeSec = openSec + timeframe.seconds
            let rawVol: Double? = (volumes != nil && i < volumes!.count) ? volumes![i] : nil
            let cleanVol: Double? = (marketClass.isOTCVolumeUnavailable && (rawVol ?? 0) <= 0) ? nil : rawVol
            out.append(Candle(
                openTimeEpochSeconds: openSec,
                closeTimeEpochSeconds: closeSec,
                open: o, high: h, low: l, close: c,
                volume: cleanVol,
                isClosed: closeSec <= serverNowEpochSeconds
            ))
        }
        return out
    }

    private func fetchBiquoteOHLC(asset: AssetDescriptor, timeframe: Timeframe) async throws -> OHLCVFetchResult {
        guard let sym = asset.biquoteSymbol else {
            throw NetworkAdapterError.invalidURL("Missing biquote symbol")
        }
        let urlStr = "https://biquote.io/api/\(sym)/ohlc?interval=\(timeframe.rawValue)&limit=200"
        guard let url = URL(string: urlStr) else { throw NetworkAdapterError.invalidURL(urlStr) }

        let res = try await http.send(URLRequest(url: url), maxRetries: 1)
        struct BiquoteOHLCRoot: Decodable {
            struct Bar: Decodable {
                let openTime: String
                let open: Double
                let high: Double
                let low: Double
                let close: Double
                let volume: Double?
                let isOpen: Bool?
            }
            let bars: [Bar]
        }

        let decoded = try JSONDecoder().decode(BiquoteOHLCRoot.self, from: res.data)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()

        var out: [Candle] = []
        for b in decoded.bars {
            guard let date = iso.date(from: b.openTime) ?? isoPlain.date(from: b.openTime) else { continue }
            let openSec = date.timeIntervalSince1970
            let isClosed = !(b.isOpen ?? false)
            let vol: Double? = (asset.marketClass.isOTCVolumeUnavailable && (b.volume ?? 0) <= 0) ? nil : b.volume
            out.append(Candle(
                openTimeEpochSeconds: openSec,
                closeTimeEpochSeconds: openSec + timeframe.seconds,
                open: b.open, high: b.high, low: b.low, close: b.close,
                volume: vol,
                isClosed: isClosed
            ))
        }
        return OHLCVFetchResult(candles: out.sorted { $0.openTimeEpochSeconds < $1.openTimeEpochSeconds }, providerName: "biquote.io", latencyMs: res.latencyMs)
    }

    private func fetchTwelveData(asset: AssetDescriptor, timeframe: Timeframe, apiKey: String) async throws -> OHLCVFetchResult {
        guard let sym = asset.twelveDataSymbol else {
            throw NetworkAdapterError.invalidURL("Missing Twelve Data symbol")
        }
        try await twelveDataPacer.acquireSlot()

        let interval: String
        switch timeframe {
        case .m15: interval = "15min"
        case .h1: interval = "1h"
        case .h4: interval = "4h"
        case .d1: interval = "1day"
        }

        var comps = URLComponents(string: "https://api.twelvedata.com/time_series")!
        comps.queryItems = [
            URLQueryItem(name: "symbol", value: sym),
            URLQueryItem(name: "interval", value: interval),
            URLQueryItem(name: "outputsize", value: "200"),
            URLQueryItem(name: "timezone", value: "UTC"),
            URLQueryItem(name: "apikey", value: apiKey)
        ]
        guard let url = comps.url else { throw NetworkAdapterError.invalidURL("Twelve Data") }

        let res = try await http.send(URLRequest(url: url), maxRetries: 1)
        struct TDResp: Decodable {
            struct Bar: Decodable {
                let datetime: String
                let open: String
                let high: String
                let low: String
                let close: String
                let volume: String?
            }
            let status: String?
            let message: String?
            let values: [Bar]?
        }
        let decoded = try JSONDecoder().decode(TDResp.self, from: res.data)
        guard let values = decoded.values else {
            throw NetworkAdapterError.decodingFailed(decoded.message ?? "Twelve Data returned no values")
        }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let dfDate = DateFormatter()
        dfDate.locale = Locale(identifier: "en_US_POSIX")
        dfDate.timeZone = TimeZone(secondsFromGMT: 0)
        dfDate.dateFormat = "yyyy-MM-dd"

        let nowSec = (res.serverDate ?? Date()).timeIntervalSince1970
        var out: [Candle] = []
        for v in values.reversed() {
            guard let date = df.date(from: v.datetime) ?? dfDate.date(from: v.datetime),
                  let o = Double(v.open), let h = Double(v.high),
                  let l = Double(v.low), let c = Double(v.close)
            else { continue }
            let openSec = date.timeIntervalSince1970
            let closeSec = openSec + timeframe.seconds
            let volRaw = v.volume.flatMap(Double.init)
            let cleanVol = (asset.marketClass.isOTCVolumeUnavailable && (volRaw ?? 0) <= 0) ? nil : volRaw
            out.append(Candle(
                openTimeEpochSeconds: openSec,
                closeTimeEpochSeconds: closeSec,
                open: o, high: h, low: l, close: c,
                volume: cleanVol,
                isClosed: closeSec <= nowSec
            ))
        }
        return OHLCVFetchResult(candles: out, providerName: "Twelve Data", latencyMs: res.latencyMs)
    }
}
