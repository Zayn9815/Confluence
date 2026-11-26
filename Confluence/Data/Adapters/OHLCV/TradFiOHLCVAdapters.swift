import Foundation
import SignalEngine

public enum TradFiProviderPreference: String, Codable, Sendable, CaseIterable, Identifiable {
    case auto = "Auto (Recommended)"
    case twelveData = "Twelve Data"
    case biquote = "biquote.io"
    case yahooFinance = "Yahoo Finance"

    public var id: String { rawValue }

    public var shortLabel: String {
        switch self {
        case .auto: return "Auto"
        case .twelveData: return "Twelve Data"
        case .biquote: return "biquote.io"
        case .yahooFinance: return "Yahoo Finance"
        }
    }
}

public enum ChartProviderChoice: String, Codable, Sendable, CaseIterable, Identifiable {
    case auto = "Auto"
    case twelveData = "Twelve Data"
    case biquote = "biquote.io"
    case yahooFinance = "Yahoo Finance"
    case binanceVision = "Binance Vision"
    case okx = "OKX"
    case kraken = "Kraken"

    public var id: String { rawValue }

    public static func choices(for marketClass: MarketClass) -> [ChartProviderChoice] {
        if marketClass == .crypto {
            return [.auto, .binanceVision, .okx, .kraken, .twelveData]
        }
        return [.auto, .twelveData, .biquote, .yahooFinance]
    }
}

private actor BiquoteAvailabilityCache {
    private var unsupportedSymbols: Set<String> = []

    func isUnsupported(_ symbol: String) -> Bool {
        unsupportedSymbols.contains(symbol.uppercased())
    }

    func markUnsupported(_ symbol: String) {
        unsupportedSymbols.insert(symbol.uppercased())
    }
}

public struct TradFiOHLCVRouter: Sendable {
    private let http: any HTTPTransport
    private let twelveData: TwelveDataAdapter
    private let biquoteCache = BiquoteAvailabilityCache()

    public init(
        http: any HTTPTransport,
        twelveData: TwelveDataAdapter? = nil
    ) {
        self.http = http
        self.twelveData = twelveData ?? TwelveDataAdapter(http: http)
    }

    public func fetchCandles(
        asset: AssetDescriptor,
        timeframe: Timeframe,
        twelveDataKey: String?,
        preference: TradFiProviderPreference = .auto,
        allowProxyForChart: Bool = false,
        limit: Int = 200,
        endTimeEpochSeconds: TimeInterval? = nil,
        onLog: ProviderLogHook? = nil
    ) async throws -> OHLCVFetchResult {
        let trimmedKey = twelveDataKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasTwelveKey = !(trimmedKey ?? "").isEmpty

        let order: [TradFiProviderPreference]
        switch preference {
        case .auto:
            // Default Auto Failover:
            // 1. Twelve Data (if key saved & within daily quota)
            // 2. biquote.io (default keyless primary)
            // 3. Yahoo Finance (automatic fallback for unsupported biquote pairs like US equities)
            order = hasTwelveKey ? [.twelveData, .biquote, .yahooFinance] : [.biquote, .yahooFinance]
        case .twelveData:
            order = [.twelveData, .biquote, .yahooFinance]
        case .biquote:
            order = [.biquote, .yahooFinance, .twelveData]
        case .yahooFinance:
            order = [.yahooFinance, .biquote, .twelveData]
        }

        var errors: [String] = []
        var firstFailedProvider: String?

        for provider in order {
            do {
                switch provider {
                case .auto:
                    continue
                case .twelveData:
                    guard let key = trimmedKey, !key.isEmpty else {
                        if preference == .twelveData {
                            throw NetworkAdapterError.missingAPIKey("Twelve Data")
                        }
                        continue
                    }
                    let res = try await twelveData.fetchCandles(
                        asset: asset,
                        timeframe: timeframe,
                        apiKey: key,
                        allowProxySymbol: allowProxyForChart,
                        outputSize: limit,
                        endDateEpochSeconds: endTimeEpochSeconds
                    )
                    if let prior = firstFailedProvider {
                        onLog?("WARN", "Fallback", "\(asset.symbol) \(timeframe.displayLabel): \(prior) unavailable -> \(res.providerName)")
                    }
                    return res

                case .biquote:
                    if endTimeEpochSeconds != nil {
                        // biquote.io does not expose historical end-cursor paging; fall through to Yahoo/Twelve Data
                        continue
                    }
                    guard let bqSym = asset.biquoteSymbol else {
                        if firstFailedProvider == nil { firstFailedProvider = "biquote.io (no symbol)" }
                        continue
                    }
                    if await biquoteCache.isUnsupported(bqSym) {
                        if firstFailedProvider == nil { firstFailedProvider = "biquote.io (cached unsupported)" }
                        continue
                    }
                    do {
                        let res = try await fetchBiquoteOHLC(asset: asset, timeframe: timeframe, limit: limit)
                        if res.candles.isEmpty {
                            await biquoteCache.markUnsupported(bqSym)
                            throw NetworkAdapterError.decodingFailed("biquote.io returned 0 bars for \(bqSym)")
                        }
                        if let prior = firstFailedProvider {
                            onLog?("WARN", "Fallback", "\(asset.symbol) \(timeframe.displayLabel): \(prior) -> biquote.io")
                        }
                        return res
                    } catch NetworkAdapterError.httpStatus(let code, _) where code == 404 {
                        await biquoteCache.markUnsupported(bqSym)
                        throw NetworkAdapterError.httpStatus(404, "biquote.io unsupported symbol \(bqSym)")
                    }

                case .yahooFinance:
                    let res = try await fetchYahooFinance(asset: asset, timeframe: timeframe, endTimeEpochSeconds: endTimeEpochSeconds)
                    if let prior = firstFailedProvider {
                        onLog?("WARN", "Fallback", "\(asset.symbol) \(timeframe.displayLabel): \(prior) -> Yahoo Finance")
                    }
                    return res
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch let urlErr as URLError where urlErr.code == .cancelled {
                throw urlErr
            } catch {
                if firstFailedProvider == nil {
                    firstFailedProvider = provider.shortLabel
                }
                let reason = "\(provider.shortLabel): \(error.localizedDescription)"
                errors.append(reason)
                onLog?("WARN", "Feed", "\(asset.symbol) \(timeframe.displayLabel) \(reason)")
            }
        }

        throw NetworkAdapterError.allProvidersFailed(errors)
    }

    private func fetchYahooFinance(
        asset: AssetDescriptor,
        timeframe: Timeframe,
        endTimeEpochSeconds: TimeInterval? = nil
    ) async throws -> OHLCVFetchResult {
        guard let rawSym = asset.yahooSymbol,
              let encoded = rawSym.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else {
            throw NetworkAdapterError.invalidURL("Missing Yahoo symbol for \(asset.symbol)")
        }

        // Yahoo has no native 4h interval; fetch 1h over 60d and causally resample to UTC 4h.
        // For 30m, try native 30m first; if empty/failed, automatically fetch 15m and resample via CandleHygieneEngine.resample15MTo30M.
        let yahooInterval: String
        let yahooRange: String
        let windowSeconds: TimeInterval
        let needs4HResample: Bool
        switch timeframe {
        case .m15:
            yahooInterval = "15m"; yahooRange = "30d"; windowSeconds = 25 * 86_400; needs4HResample = false
        case .m30:
            yahooInterval = "30m"; yahooRange = "30d"; windowSeconds = 25 * 86_400; needs4HResample = false
        case .h1:
            yahooInterval = "1h"; yahooRange = "60d"; windowSeconds = 55 * 86_400; needs4HResample = false
        case .h4:
            yahooInterval = "1h"; yahooRange = "60d"; windowSeconds = 55 * 86_400; needs4HResample = true
        case .d1:
            yahooInterval = "1d"; yahooRange = "2y"; windowSeconds = 500 * 86_400; needs4HResample = false
        }

        let hosts = ["query1.finance.yahoo.com", "query2.finance.yahoo.com"]
        var lastErr: Error = NetworkAdapterError.httpStatus(0, "Yahoo failed")

        for host in hosts {
            let querySuffix: String
            if let endSec = endTimeEpochSeconds {
                let p2 = Int64(endSec)
                let p1 = max(0, Int64(endSec - windowSeconds))
                querySuffix = "interval=\(yahooInterval)&period1=\(p1)&period2=\(p2)&includePrePost=false"
            } else {
                querySuffix = "interval=\(yahooInterval)&range=\(yahooRange)&includePrePost=false"
            }
            let urlStr = "https://\(host)/v8/finance/chart/\(encoded)?\(querySuffix)"
            guard let url = URL(string: urlStr) else { continue }
            var req = URLRequest(url: url)
            req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            req.setValue("application/json", forHTTPHeaderField: "Accept")

            do {
                let res = try await http.send(req, maxRetries: 1)
                let serverNow = (res.serverDate ?? Date()).timeIntervalSince1970
                let candles = try Self.parseYahooChartJSON(
                    data: res.data,
                    timeframe: needs4HResample ? .h1 : timeframe,
                    marketClass: asset.marketClass,
                    serverNowEpochSeconds: serverNow
                )
                let finalBars = needs4HResample
                    ? CandleHygieneEngine.resample1HTo4H(hourlyCandles: candles, serverNowEpochSeconds: serverNow)
                    : candles
                guard !finalBars.isEmpty else {
                    throw NetworkAdapterError.decodingFailed("Yahoo Finance returned 0 valid candles")
                }
                return OHLCVFetchResult(candles: finalBars, providerName: "Yahoo Finance", latencyMs: res.latencyMs)
            } catch is CancellationError {
                throw CancellationError()
            } catch let urlErr as URLError where urlErr.code == .cancelled {
                throw urlErr
            } catch {
                lastErr = error
            }
        }

        // Automatic 15m -> 30m causal resampling fallback when Yahoo native 30m fails or returns empty
        if timeframe == .m30 {
            let m15Res = try await fetchYahooFinance(asset: asset, timeframe: .m15, endTimeEpochSeconds: endTimeEpochSeconds)
            let serverNow = Date().timeIntervalSince1970
            let resampled = CandleHygieneEngine.resample15MTo30M(
                m15Candles: m15Res.candles,
                serverNowEpochSeconds: serverNow
            )
            if !resampled.isEmpty {
                return OHLCVFetchResult(candles: resampled, providerName: "Yahoo Finance (15m→30m)", latencyMs: m15Res.latencyMs)
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
            guard let o = opens[i], let h = highs[i], let l = lows[i], let c = closes[i],
                  o.isFinite, h.isFinite, l.isFinite, c.isFinite,
                  o > 0, h > 0, l > 0, c > 0, h >= l
            else {
                continue
            }
            let openSec = timestamps[i]
            guard openSec.isFinite, openSec > 0 else { continue }
            let closeSec = openSec + timeframe.seconds
            let rawVol: Double? = (volumes != nil && i < volumes!.count) ? volumes![i] : nil
            let validVol: Double? = rawVol.flatMap { ($0.isFinite && $0 >= 0) ? $0 : nil }
            let cleanVol: Double? = (marketClass.isOTCVolumeUnavailable && (validVol ?? 0) <= 0) ? nil : validVol
            out.append(Candle(
                openTimeEpochSeconds: openSec,
                closeTimeEpochSeconds: closeSec,
                open: o, high: h, low: l, close: c,
                volume: cleanVol,
                isClosed: closeSec <= serverNowEpochSeconds
            ))
        }
        out.sort { $0.openTimeEpochSeconds < $1.openTimeEpochSeconds }
        return out
    }

    private func fetchBiquoteOHLC(asset: AssetDescriptor, timeframe: Timeframe, limit: Int = 200) async throws -> OHLCVFetchResult {
        guard let sym = asset.biquoteSymbol else {
            throw NetworkAdapterError.invalidURL("Missing biquote symbol")
        }
        let clampedLimit = min(max(limit, 1), 500)
        let urlStr = "https://biquote.io/api/\(sym)/ohlc?interval=\(timeframe.rawValue)&limit=\(clampedLimit)"
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
}
