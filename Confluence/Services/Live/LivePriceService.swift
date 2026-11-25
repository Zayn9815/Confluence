import Foundation
import Observation
import SignalEngine

// MARK: - User-Selectable Live Feed & Chart Mode Settings

public enum TradFiLiveFeedMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case autoStreamWithBackup = "auto_stream_with_backup"
    case liveStreamOnly = "live_stream_only"
    case poll10s = "poll_10s"
    case off = "off"

    public var id: String { rawValue }

    public var displayLabel: String {
        switch self {
        case .autoStreamWithBackup: return "Auto — live stream with backup (Recommended)"
        case .liveStreamOnly: return "Live stream only"
        case .poll10s: return "Every 10 seconds (Battery saver)"
        case .off: return "Off (manual refresh only)"
        }
    }
}

public enum CryptoLiveFeedMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case liveStream = "live_stream"
    case poll3s = "poll_3s"
    case off = "off"

    public var id: String { rawValue }

    public var displayLabel: String {
        switch self {
        case .liveStream: return "Live stream (Recommended)"
        case .poll3s: return "Every 3 seconds (Battery saver)"
        case .off: return "Off"
        }
    }
}

public enum DefaultChartViewMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case confluence = "confluence"
    case tradingView = "tradingview"

    public var id: String { rawValue }

    public var displayLabel: String {
        switch self {
        case .confluence: return "Confluence chart (Recommended)"
        case .tradingView: return "TradingView chart"
        }
    }
}

public enum LivePriceFreshness: String, Codable, Sendable, Equatable {
    case live = "LIVE"
    case delayed = "DELAYED"
    case offline = "OFFLINE"
}

public struct LivePriceQuote: Codable, Sendable, Equatable {
    public let symbol: String
    public let price: Double
    public let asOfEpochSeconds: TimeInterval
    public let sourceLabel: String
    public let isStreaming: Bool
    public let changePercent: Double?

    public init(
        symbol: String,
        price: Double,
        asOfEpochSeconds: TimeInterval,
        sourceLabel: String,
        isStreaming: Bool,
        changePercent: Double? = nil
    ) {
        self.symbol = symbol
        self.price = price
        self.asOfEpochSeconds = asOfEpochSeconds
        self.sourceLabel = sourceLabel
        self.isStreaming = isStreaming
        self.changePercent = changePercent
    }

    public func freshness(nowEpochSeconds: TimeInterval = Date().timeIntervalSince1970) -> LivePriceFreshness {
        let age = max(0, nowEpochSeconds - asOfEpochSeconds)
        let liveWindow: TimeInterval = isStreaming ? 15.0 : 20.0
        if age <= liveWindow { return .live }
        if age <= 60.0 { return .delayed }
        return .offline
    }

    public func statusBadgeText(nowEpochSeconds: TimeInterval = Date().timeIntervalSince1970) -> String {
        switch freshness(nowEpochSeconds: nowEpochSeconds) {
        case .live:
            return isStreaming ? "Live" : "Updates every ~10s"
        case .delayed:
            return "Delayed"
        case .offline:
            return "OFFLINE"
        }
    }
}

// MARK: - Pure Binance Vision WS Message Parser (Testable)

public struct BinanceKlineStreamTick: Sendable, Equatable {
    public let binanceSymbol: String
    public let price: Double
    public let epochSeconds: TimeInterval
    public let volume: Double?
    public let isCandleClosed: Bool
}

public enum BinanceLiveStreamParser {
    /// Parses a Binance combined stream `/stream?streams=...` or raw `/ws/...` kline JSON frame.
    public static func parseKlineFrame(_ text: String) -> BinanceKlineStreamTick? {
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let payload = (root["data"] as? [String: Any]) ?? root
        guard let k = payload["k"] as? [String: Any],
              let sym = (k["s"] as? String) ?? (payload["s"] as? String),
              let closeStr = k["c"] as? String,
              let closePrice = Double(closeStr),
              closePrice.isFinite, closePrice > 0
        else { return nil }

        let eventTimeMs = (payload["E"] as? Double) ?? (k["T"] as? Double)
        let epochSec = eventTimeMs.map { $0 / 1000.0 } ?? Date().timeIntervalSince1970
        let vol = (k["v"] as? String).flatMap(Double.init)
        let isClosed = (k["x"] as? Bool) ?? false

        return BinanceKlineStreamTick(
            binanceSymbol: sym.uppercased(),
            price: closePrice,
            epochSeconds: epochSec,
            volume: vol,
            isCandleClosed: isClosed
        )
    }
}

// MARK: - LivePriceEngine (Actor)

/// Foreground-only, owner-scoped live price engine enforcing an 8-symbol LRU cap.
/// - Crypto: Binance Vision WebSocket (`wss://data-stream.binance.vision`), 3s REST fallback.
/// - TradFi: Yahoo Live WebSocket (`wss://streamer.finance.yahoo.com/`) with seamless fallback
///   to `biquote.io` -> Yahoo REST (~10s polling). Twelve Data is NEVER used for live prices.
public actor LivePriceEngine {
    public static let maxActiveSymbols: Int = 8
    private static let binanceReconnectMaxAgeSeconds: TimeInterval = 23 * 3_600

    private let http: any HTTPTransport
    private let session: URLSession
    private let yahooStream: YahooLiveStreamAdapter
    private let onQuote: @Sendable (LivePriceQuote) async -> Void

    private var owners: [String: [String]] = [:]
    private var ownerOrder: [String] = []
    private var activeSymbols: [String] = []
    private var referenceCloseBySymbol: [String: Double] = [:]
    private var lastQuoteBySymbol: [String: LivePriceQuote] = [:]
    /// Symbols whose Yahoo WS stream failed scale/bad-tick check (e.g. XAU/USD GC=F divergence) -> force biquote poll.
    private var forcePollTradFiSymbols: Set<String> = []

    private var tradFiMode: TradFiLiveFeedMode = .autoStreamWithBackup
    private var cryptoMode: CryptoLiveFeedMode = .liveStream
    private var isForegroundActive: Bool = true

    private var binanceWS: URLSessionWebSocketTask?
    private var binanceWSTask: Task<Void, Never>?
    private var binancePingTask: Task<Void, Never>?
    private var cryptoPollTask: Task<Void, Never>?
    private var tradFiPollTask: Task<Void, Never>?

    public init(
        http: any HTTPTransport = URLSessionHTTPClient(),
        session: URLSession = .shared,
        onQuote: @escaping @Sendable (LivePriceQuote) async -> Void
    ) {
        self.http = http
        self.session = session
        self.yahooStream = YahooLiveStreamAdapter(session: session)
        self.onQuote = onQuote
    }

    public func currentActiveSymbols() -> [String] {
        activeSymbols
    }

    public func seedReferenceClose(_ price: Double, for symbol: String) {
        guard price.isFinite, price > 0 else { return }
        referenceCloseBySymbol[symbol] = price
    }

    public func updateModes(tradFi: TradFiLiveFeedMode, crypto: CryptoLiveFeedMode) async {
        guard tradFi != tradFiMode || crypto != cryptoMode else { return }
        tradFiMode = tradFi
        cryptoMode = crypto
        await restartStreamsIfActive()
    }

    public func setForegroundActive(_ active: Bool) async {
        guard active != isForegroundActive else { return }
        isForegroundActive = active
        if active {
            await restartStreamsIfActive()
        } else {
            await stopAllConnections()
        }
    }

    public func acquire(owner: String, symbols: [String]) async -> [String] {
        let cleaned = symbols.filter { !$0.isEmpty }
        owners[owner] = cleaned
        ownerOrder.removeAll { $0 == owner }
        ownerOrder.append(owner)
        recomputeActiveSymbols()
        if isForegroundActive {
            await restartStreamsIfActive()
        }
        return activeSymbols
    }

    public func release(owner: String) async -> [String] {
        owners.removeValue(forKey: owner)
        ownerOrder.removeAll { $0 == owner }
        recomputeActiveSymbols()
        if activeSymbols.isEmpty {
            await stopAllConnections()
        } else if isForegroundActive {
            await restartStreamsIfActive()
        }
        return activeSymbols
    }

    /// Computes up to `maxActiveSymbols` (8) symbols prioritizing the most recently acquired owners (LRU drop).
    private func recomputeActiveSymbols() {
        var seen: Set<String> = []
        var prioritized: [String] = []
        for owner in ownerOrder.reversed() {
            for sym in owners[owner] ?? [] where !seen.contains(sym) {
                seen.insert(sym)
                prioritized.append(sym)
                if prioritized.count >= Self.maxActiveSymbols {
                    break
                }
            }
            if prioritized.count >= Self.maxActiveSymbols { break }
        }
        activeSymbols = prioritized
    }

    private func stopAllConnections() async {
        binanceWSTask?.cancel()
        binanceWSTask = nil
        binancePingTask?.cancel()
        binancePingTask = nil
        binanceWS?.cancel(with: .normalClosure, reason: nil)
        binanceWS = nil

        cryptoPollTask?.cancel()
        cryptoPollTask = nil
        tradFiPollTask?.cancel()
        tradFiPollTask = nil

        await yahooStream.disconnect()
    }

    private func restartStreamsIfActive() async {
        await stopAllConnections()
        guard isForegroundActive, !activeSymbols.isEmpty else { return }

        let descriptors = activeSymbols.compactMap { WatchlistDefaults.descriptor(for: $0) }
        let cryptoAssets = descriptors.filter { $0.marketClass == .crypto }
        let tradFiAssets = descriptors.filter { $0.marketClass != .crypto }

        if !cryptoAssets.isEmpty {
            switch cryptoMode {
            case .liveStream:
                startBinanceWebSocket(assets: cryptoAssets)
            case .poll3s:
                startCryptoPolling(assets: cryptoAssets, intervalSeconds: 3.0)
            case .off:
                break
            }
        }

        if !tradFiAssets.isEmpty {
            switch tradFiMode {
            case .autoStreamWithBackup:
                await startYahooStream(assets: tradFiAssets, allowPollBackup: true)
                startTradFiPolling(assets: tradFiAssets, backupOnly: true)
            case .liveStreamOnly:
                await startYahooStream(assets: tradFiAssets, allowPollBackup: false)
            case .poll10s:
                startTradFiPolling(assets: tradFiAssets, backupOnly: false)
            case .off:
                break
            }
        }
    }

    // MARK: - Crypto Binance Vision WebSocket & 3s REST Fallback

    private func startBinanceWebSocket(assets: [AssetDescriptor]) {
        let streams = assets.compactMap { $0.binanceSymbol?.lowercased() }.map { "\($0)@kline_1m" }
        guard !streams.isEmpty,
              let url = URL(string: "wss://data-stream.binance.vision/stream?streams=\(streams.joined(separator: "/"))")
        else { return }

        let binanceToCanonical: [String: AssetDescriptor] = Dictionary(
            uniqueKeysWithValues: assets.compactMap { asset in
                guard let b = asset.binanceSymbol?.uppercased() else { return nil }
                return (b, asset)
            }
        )

        binanceWSTask = Task { [weak self] in
            var backoff: Double = 2.0
            while !Task.isCancelled {
                guard let self else { return }
                let connectedAt = Date().timeIntervalSince1970
                let ws = await self.openBinanceSocket(url: url)
                await self.startBinancePingLoop(ws: ws)

                var failed = false
                while !Task.isCancelled {
                    if Date().timeIntervalSince1970 - connectedAt >= Self.binanceReconnectMaxAgeSeconds {
                        break
                    }
                    do {
                        let msg = try await ws.receive()
                        backoff = 2.0
                        if case .string(let text) = msg,
                           let tick = BinanceLiveStreamParser.parseKlineFrame(text),
                           let asset = binanceToCanonical[tick.binanceSymbol] {
                            await self.handleCandidateQuote(
                                asset: asset,
                                price: tick.price,
                                epochSeconds: tick.epochSeconds,
                                sourceLabel: "Binance Live",
                                isStreaming: true,
                                changePercent: nil
                            )
                        }
                    } catch {
                        failed = true
                        break
                    }
                }

                ws.cancel(with: .goingAway, reason: nil)
                if Task.isCancelled { return }
                if failed {
                    // Brief REST fallback poll during socket outage
                    await self.pollCryptoOnce(assets: assets)
                }
                try? await Task.sleep(for: .seconds(backoff))
                backoff = min(backoff * 2.0, 30.0)
            }
        }
    }

    private func openBinanceSocket(url: URL) -> URLSessionWebSocketTask {
        binanceWS?.cancel(with: .normalClosure, reason: nil)
        let ws = session.webSocketTask(with: url)
        binanceWS = ws
        ws.resume()
        return ws
    }

    private func startBinancePingLoop(ws: URLSessionWebSocketTask) {
        binancePingTask?.cancel()
        binancePingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                if Task.isCancelled { return }
                ws.sendPing { _ in }
            }
        }
    }

    private func startCryptoPolling(assets: [AssetDescriptor], intervalSeconds: TimeInterval) {
        cryptoPollTask?.cancel()
        cryptoPollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollCryptoOnce(assets: assets)
                try? await Task.sleep(for: .seconds(intervalSeconds))
            }
        }
    }

    private func pollCryptoOnce(assets: [AssetDescriptor]) async {
        for asset in assets {
            if Task.isCancelled { return }
            guard let sym = asset.binanceSymbol,
                  let url = URL(string: "https://data-api.binance.vision/api/v3/ticker/price?symbol=\(sym)")
            else { continue }
            do {
                let res = try await http.send(URLRequest(url: url), maxRetries: 0)
                struct TickerResp: Decodable { let price: String }
                let decoded = try JSONDecoder().decode(TickerResp.self, from: res.data)
                if let p = Double(decoded.price), p.isFinite, p > 0 {
                    await handleCandidateQuote(
                        asset: asset,
                        price: p,
                        epochSeconds: Date().timeIntervalSince1970,
                        sourceLabel: "Binance Poll",
                        isStreaming: false,
                        changePercent: nil
                    )
                }
            } catch {
                continue
            }
        }
    }

    // MARK: - TradFi Yahoo Live WebSocket + biquote.io / Yahoo REST Fallback (Zero Twelve Data)

    private func startYahooStream(assets: [AssetDescriptor], allowPollBackup: Bool) async {
        let yahooToCanonical: [String: AssetDescriptor] = Dictionary(
            uniqueKeysWithValues: assets.compactMap { asset in
                guard let y = asset.yahooSymbol, !y.isEmpty else { return nil }
                return (y.uppercased(), asset)
            }
        )
        let yahooSymbols = assets.compactMap(\.yahooSymbol)
        guard !yahooSymbols.isEmpty else { return }

        await yahooStream.connect(
            yahooSymbols: yahooSymbols,
            onTick: { [weak self] tick in
                guard let self, let asset = yahooToCanonical[tick.id.uppercased()] else { return }
                await self.handleYahooTick(asset: asset, tick: tick, allowPollBackup: allowPollBackup)
            },
            onDisconnect: { _ in
                // Backup polling loop handles recovery automatically when `allowPollBackup == true`
            }
        )
    }

    private func handleYahooTick(asset: AssetDescriptor, tick: YahooPricingTick, allowPollBackup: Bool) async {
        let ref = referenceCloseBySymbol[asset.symbol]
        guard YahooPricingProtobufDecoder.isAcceptableTick(
            marketClass: asset.marketClass,
            price: tick.price,
            referenceClose: ref
        ) else {
            // Scale/bad-tick mismatch (e.g. GC=F futures diverging from spot XAU/USD) -> fall back to biquote polling
            if allowPollBackup {
                forcePollTradFiSymbols.insert(asset.symbol)
            }
            return
        }
        forcePollTradFiSymbols.remove(asset.symbol)
        await handleCandidateQuote(
            asset: asset,
            price: tick.price,
            epochSeconds: Date().timeIntervalSince1970,
            sourceLabel: "Yahoo Live",
            isStreaming: true,
            changePercent: tick.changePercent
        )
    }

    private func startTradFiPolling(assets: [AssetDescriptor], backupOnly: Bool) {
        tradFiPollTask?.cancel()
        tradFiPollTask = Task { [weak self] in
            if backupOnly {
                // Give Yahoo WS a 6-second head start before polling symbols without a live stream tick
                try? await Task.sleep(for: .seconds(6))
            }
            while !Task.isCancelled {
                await self?.pollTradFiOnce(assets: assets, backupOnly: backupOnly)
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private func pollTradFiOnce(assets: [AssetDescriptor], backupOnly: Bool) async {
        let now = Date().timeIntervalSince1970
        for asset in assets {
            if Task.isCancelled { return }
            if backupOnly {
                let forced = forcePollTradFiSymbols.contains(asset.symbol)
                if !forced, let existing = lastQuoteBySymbol[asset.symbol],
                   existing.isStreaming, (now - existing.asOfEpochSeconds) < 12.0 {
                    continue
                }
            }
            // Strictly biquote.io first, then Yahoo REST — NEVER Twelve Data for live polling
            if let price = await fetchBiquoteLatestPrice(asset: asset) {
                await handleCandidateQuote(
                    asset: asset,
                    price: price,
                    epochSeconds: Date().timeIntervalSince1970,
                    sourceLabel: "biquote.io",
                    isStreaming: false,
                    changePercent: nil
                )
            } else if let price = await fetchYahooRestLatestPrice(asset: asset) {
                await handleCandidateQuote(
                    asset: asset,
                    price: price,
                    epochSeconds: Date().timeIntervalSince1970,
                    sourceLabel: "Yahoo Poll",
                    isStreaming: false,
                    changePercent: nil
                )
            }
        }
    }

    private func fetchBiquoteLatestPrice(asset: AssetDescriptor) async -> Double? {
        guard let sym = asset.biquoteSymbol,
              let url = URL(string: "https://biquote.io/api/\(sym)/ohlc?interval=15m&limit=2")
        else { return nil }
        do {
            let res = try await http.send(URLRequest(url: url), maxRetries: 0)
            struct BqResp: Decodable {
                struct Bar: Decodable { let close: Double }
                let bars: [Bar]
            }
            let decoded = try JSONDecoder().decode(BqResp.self, from: res.data)
            if let p = decoded.bars.last?.close, p.isFinite, p > 0 {
                return p
            }
        } catch {
            return nil
        }
        return nil
    }

    private func fetchYahooRestLatestPrice(asset: AssetDescriptor) async -> Double? {
        guard let rawSym = asset.yahooSymbol,
              let encoded = rawSym.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?interval=1m&range=1d")
        else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        do {
            let res = try await http.send(req, maxRetries: 0)
            struct MetaResp: Decodable {
                struct Chart: Decodable {
                    struct Res: Decodable {
                        struct Meta: Decodable { let regularMarketPrice: Double? }
                        let meta: Meta?
                    }
                    let result: [Res]?
                }
                let chart: Chart
            }
            let decoded = try JSONDecoder().decode(MetaResp.self, from: res.data)
            if let p = decoded.chart.result?.first?.meta?.regularMarketPrice, p.isFinite, p > 0 {
                return p
            }
        } catch {
            return nil
        }
        return nil
    }

    // MARK: - Guarded Dispatch

    private func handleCandidateQuote(
        asset: AssetDescriptor,
        price: Double,
        epochSeconds: TimeInterval,
        sourceLabel: String,
        isStreaming: Bool,
        changePercent: Double?
    ) async {
        let ref = referenceCloseBySymbol[asset.symbol] ?? lastQuoteBySymbol[asset.symbol]?.price
        if let ref, ref > 0 {
            let maxDev = LiveCandleAggregator.defaultMaxTickDeviation(for: asset.marketClass)
            if abs(price - ref) / ref > maxDev {
                return
            }
        }
        let quote = LivePriceQuote(
            symbol: asset.symbol,
            price: price,
            asOfEpochSeconds: epochSeconds,
            sourceLabel: sourceLabel,
            isStreaming: isStreaming,
            changePercent: changePercent
        )
        lastQuoteBySymbol[asset.symbol] = quote
        await onQuote(quote)
    }
}

// MARK: - MainActor Observable Facade

@MainActor
@Observable
public final class LivePriceService {
    public private(set) var quotes: [String: LivePriceQuote] = [:]
    public private(set) var activeSymbols: [String] = []
    public private(set) var isForegroundActive: Bool = true
    public var onQuoteReceived: ((LivePriceQuote) -> Void)?

    private var engine: LivePriceEngine?

    public init(http: any HTTPTransport = URLSessionHTTPClient()) {
        self.engine = LivePriceEngine(http: http) { [weak self] quote in
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.quotes[quote.symbol] = quote
                self.onQuoteReceived?(quote)
            }
        }
    }

    public func latest(for symbol: String) -> LivePriceQuote? {
        quotes[symbol]
    }

    public func livePriceMap() -> [String: Double] {
        var map: [String: Double] = [:]
        for (sym, q) in quotes {
            map[sym] = q.price
        }
        return map
    }

    public func acquire(owner: String, symbols: [String]) {
        guard let engine else { return }
        Task {
            let active = await engine.acquire(owner: owner, symbols: symbols)
            self.activeSymbols = active
        }
    }

    public func release(owner: String) {
        guard let engine else { return }
        Task {
            let active = await engine.release(owner: owner)
            self.activeSymbols = active
        }
    }

    public func setForegroundActive(_ active: Bool) {
        isForegroundActive = active
        guard let engine else { return }
        Task {
            await engine.setForegroundActive(active)
        }
    }

    public func updateModes(tradFi: TradFiLiveFeedMode, crypto: CryptoLiveFeedMode) {
        guard let engine else { return }
        Task {
            await engine.updateModes(tradFi: tradFi, crypto: crypto)
        }
    }

    public func seedReferenceClose(_ price: Double, for symbol: String) {
        guard let engine else { return }
        Task {
            await engine.seedReferenceClose(price, for: symbol)
        }
    }

    /// Direct injection helper for deterministic unit tests and manual quote refresh.
    public func ingestExternalQuote(_ quote: LivePriceQuote) {
        quotes[quote.symbol] = quote
        onQuoteReceived?(quote)
    }
}
