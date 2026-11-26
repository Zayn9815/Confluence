import Foundation
import SignalEngine

/// Normalizes canonical Confluence crypto symbols (e.g. `BTC/USDT`, `PEPE/USDT`, `SHIB-USD`)
/// into exact venue-specific perpetual swap and spot symbols, including 1000-multiplier meme contracts.
public struct CryptoOrderFlowVenueSymbols: Sendable, Equatable {
    public let base: String
    public let okxSwapInstId: String
    public let okxSpotInstId: String
    public let okxUnderlying: String
    public let bybitLinearSymbol: String
    public let bybitSpotSymbol: String
    public let binanceFuturesSymbol: String
    public let binanceSpotSymbol: String

    private static let thousandMultiplierBases: Set<String> = [
        "PEPE", "SHIB", "FLOKI", "BONK", "LUNC", "XEC", "SATS", "RATS", "CAT", "WHY"
    ]

    public static func resolve(symbol: String) -> CryptoOrderFlowVenueSymbols {
        let upper = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cleaned = upper
            .replacingOccurrences(of: "-SWAP", with: "")
            .replacingOccurrences(of: "PERP", with: "")

        let base: String
        if let slashIdx = cleaned.firstIndex(of: "/") {
            base = String(cleaned[..<slashIdx])
        } else if let dashIdx = cleaned.firstIndex(of: "-") {
            base = String(cleaned[..<dashIdx])
        } else if cleaned.hasSuffix("USDT") && cleaned.count > 4 {
            base = String(cleaned.dropLast(4))
        } else if cleaned.hasSuffix("USD") && cleaned.count > 3 {
            base = String(cleaned.dropLast(3))
        } else {
            base = cleaned
        }

        let normalizedBase = base.hasPrefix("1000") ? String(base.dropFirst(4)) : base
        let uses1000Perp = thousandMultiplierBases.contains(normalizedBase)
        let perpBase = uses1000Perp ? "1000\(normalizedBase)" : normalizedBase

        return CryptoOrderFlowVenueSymbols(
            base: normalizedBase,
            okxSwapInstId: "\(normalizedBase)-USDT-SWAP",
            okxSpotInstId: "\(normalizedBase)-USDT",
            okxUnderlying: "\(normalizedBase)-USDT",
            bybitLinearSymbol: "\(perpBase)USDT",
            bybitSpotSymbol: "\(normalizedBase)USDT",
            binanceFuturesSymbol: "\(perpBase)USDT",
            binanceSpotSymbol: "\(normalizedBase)USDT"
        )
    }
}

/// Free public 3-venue Crypto-Only Order Flow REST adapter (OKX v5 -> Bybit v5 -> Binance USD-M Futures).
/// - **Hard Crypto-Only Gate:** Returns `nil` immediately for Forex, Metals, Indices, and Stocks (ZERO HTTP calls).
/// - Used for lightweight batch scans and periodic deep-book (`sz=100`) wall refreshes.
public actor CryptoOrderFlowAdapter {
    private let http: any HTTPTransport
    private let requestTimeout: TimeInterval = 5.0

    public init(http: any HTTPTransport) {
        self.http = http
    }

    /// Fetches a fresh Crypto-Only `OrderFlowSnapshot` across OKX -> Bybit -> Binance failover.
    /// Returns `nil` immediately on non-crypto markets or gracefully if all venues are unreachable.
    public func fetchSnapshot(
        symbol: String,
        assetClass: MarketClass,
        preferredVenue: String? = nil
    ) async -> OrderFlowSnapshot? {
        // HARD CRYPTO-ONLY GATE: zero network traffic on Forex/Metals/Indices/Stocks
        guard assetClass == .crypto else { return nil }
        guard !Task.isCancelled else { return nil }

        let syms = CryptoOrderFlowVenueSymbols.resolve(symbol: symbol)
        var order: [String] = ["OKX", "Bybit", "Binance"]
        if let pref = preferredVenue, let idx = order.firstIndex(of: pref) {
            order.remove(at: idx)
            order.insert(pref, at: 0)
        }

        for venue in order {
            if Task.isCancelled { return nil }
            switch venue {
            case "OKX":
                if let snap = await fetchOKXSnapshot(symbols: syms) {
                    return snap
                }
            case "Bybit":
                if let snap = await fetchBybitSnapshot(symbols: syms) {
                    return snap
                }
            case "Binance":
                if let snap = await fetchBinanceSnapshot(symbols: syms) {
                    return snap
                }
            default:
                continue
            }
        }
        return nil
    }

    /// Deep-book only refresh (OKX `sz=100` / Bybit `limit=50` / Binance `limit=100`) used by `LiveOrderFlowService`
    /// every 12–15s to prevent narrow-range `books5` blindness and delta drift.
    public func fetchDeepBook(
        symbol: String,
        assetClass: MarketClass,
        venue: String
    ) async -> (bids: [OrderBookLevel], asks: [OrderBookLevel])? {
        guard assetClass == .crypto else { return nil }
        let syms = CryptoOrderFlowVenueSymbols.resolve(symbol: symbol)
        switch venue {
        case "OKX":
            if let swap = await fetchOKXOrderBook(instId: syms.okxSwapInstId) {
                return swap
            }
            return await fetchOKXOrderBook(instId: syms.okxSpotInstId)
        case "Bybit":
            if let linear = await fetchBybitOrderBook(category: "linear", symbol: syms.bybitLinearSymbol) {
                return linear
            }
            return await fetchBybitOrderBook(category: "spot", symbol: syms.bybitSpotSymbol)
        case "Binance":
            return await fetchBinanceFuturesOrderBook(symbol: syms.binanceFuturesSymbol)
        default:
            return nil
        }
    }

    // MARK: - Venue 1: OKX v5 Public

    private func fetchOKXSnapshot(symbols: CryptoOrderFlowVenueSymbols) async -> OrderFlowSnapshot? {
        var instId = symbols.okxSwapInstId
        var book = await fetchOKXOrderBook(instId: instId)
        var isSwap = true
        if book == nil {
            instId = symbols.okxSpotInstId
            book = await fetchOKXOrderBook(instId: instId)
            isSwap = false
        }
        guard let validBook = book else { return nil }

        async let tradesTask = fetchOKXTrades(instId: instId)
        async let liqsTask: [OrderFlowLiquidation] = isSwap
            ? fetchOKXLiquidations(underlying: symbols.okxUnderlying)
            : []

        let (trades, liqs) = await (tradesTask, liqsTask)
        return Self.buildValidatedSnapshot(
            venue: "OKX",
            isLiveWebSocket: false,
            bids: validBook.bids,
            asks: validBook.asks,
            trades: trades,
            liquidations: liqs
        )
    }

    private func fetchOKXOrderBook(instId: String) async -> (bids: [OrderBookLevel], asks: [OrderBookLevel])? {
        guard let url = URL(string: "https://www.okx.com/api/v5/market/books?instId=\(instId)&sz=100") else { return nil }
        guard let data = await sendFastGET(url: url) else { return nil }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["code"] as? String) == "0",
              let rows = root["data"] as? [[String: Any]],
              let first = rows.first
        else { return nil }

        let bids = Self.parseStringTupleLevels(first["bids"] as? [[Any]])
        let asks = Self.parseStringTupleLevels(first["asks"] as? [[Any]])
        guard !bids.isEmpty, !asks.isEmpty else { return nil }
        return (bids, asks)
    }

    private func fetchOKXTrades(instId: String) async -> [OrderFlowTrade] {
        guard let url = URL(string: "https://www.okx.com/api/v5/market/trades?instId=\(instId)&limit=100") else { return [] }
        guard let data = await sendFastGET(url: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["code"] as? String) == "0",
              let rows = root["data"] as? [[String: Any]]
        else { return [] }

        var out: [OrderFlowTrade] = []
        out.reserveCapacity(rows.count)
        for row in rows {
            guard let px = Self.parsePositiveDouble(row["px"]),
                  let sz = Self.parsePositiveDouble(row["sz"]),
                  let side = (row["side"] as? String)?.lowercased()
            else { continue }
            let tsMs = Self.parsePositiveDouble(row["ts"]) ?? (Date().timeIntervalSince1970 * 1000.0)
            out.append(OrderFlowTrade(
                price: px,
                quantity: sz,
                isBuyerMaker: (side == "sell"),
                timestampEpochSeconds: tsMs / 1000.0
            ))
        }
        return out
    }

    private func fetchOKXLiquidations(underlying: String) async -> [OrderFlowLiquidation] {
        guard let url = URL(string: "https://www.okx.com/api/v5/public/liquidation-orders?instType=SWAP&uly=\(underlying)&state=filled&limit=20") else { return [] }
        guard let data = await sendFastGET(url: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["code"] as? String) == "0",
              let rows = root["data"] as? [[String: Any]]
        else { return [] }

        let cutoff = Date().timeIntervalSince1970 - 300.0
        var out: [OrderFlowLiquidation] = []
        for row in rows {
            guard let details = row["details"] as? [[String: Any]] else { continue }
            for d in details {
                guard let px = Self.parsePositiveDouble(d["bkPx"]),
                      let sz = Self.parsePositiveDouble(d["sz"])
                else { continue }
                let tsMs = Self.parsePositiveDouble(d["ts"]) ?? (Date().timeIntervalSince1970 * 1000.0)
                let tsSec = tsMs / 1000.0
                guard tsSec >= cutoff else { continue }
                let posSide = (d["posSide"] as? String)?.lowercased() ?? ""
                let side = (d["side"] as? String)?.lowercased() ?? ""
                let isLongLiq = (posSide == "long") || (posSide.isEmpty && side == "sell")
                out.append(OrderFlowLiquidation(
                    price: px,
                    sizeInSameUnits: sz,
                    isLongLiquidation: isLongLiq,
                    timestampEpochSeconds: tsSec
                ))
            }
        }
        return out
    }

    // MARK: - Venue 2: Bybit v5 Public

    private func fetchBybitSnapshot(symbols: CryptoOrderFlowVenueSymbols) async -> OrderFlowSnapshot? {
        var category = "linear"
        var sym = symbols.bybitLinearSymbol
        var book = await fetchBybitOrderBook(category: category, symbol: sym)
        if book == nil {
            category = "spot"
            sym = symbols.bybitSpotSymbol
            book = await fetchBybitOrderBook(category: category, symbol: sym)
        }
        guard let validBook = book else { return nil }

        let trades = await fetchBybitTrades(category: category, symbol: sym)
        return Self.buildValidatedSnapshot(
            venue: "Bybit",
            isLiveWebSocket: false,
            bids: validBook.bids,
            asks: validBook.asks,
            trades: trades,
            liquidations: []
        )
    }

    private func fetchBybitOrderBook(category: String, symbol: String) async -> (bids: [OrderBookLevel], asks: [OrderBookLevel])? {
        guard let url = URL(string: "https://api.bybit.com/v5/market/orderbook?category=\(category)&symbol=\(symbol)&limit=50") else { return nil }
        guard let data = await sendFastGET(url: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["retCode"] as? Int) == 0,
              let result = root["result"] as? [String: Any]
        else { return nil }

        let bids = Self.parseStringTupleLevels(result["b"] as? [[Any]])
        let asks = Self.parseStringTupleLevels(result["a"] as? [[Any]])
        guard !bids.isEmpty, !asks.isEmpty else { return nil }
        return (bids, asks)
    }

    private func fetchBybitTrades(category: String, symbol: String) async -> [OrderFlowTrade] {
        guard let url = URL(string: "https://api.bybit.com/v5/market/recent-trade?category=\(category)&symbol=\(symbol)&limit=100") else { return [] }
        guard let data = await sendFastGET(url: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["retCode"] as? Int) == 0,
              let result = root["result"] as? [String: Any],
              let list = result["list"] as? [[String: Any]]
        else { return [] }

        var out: [OrderFlowTrade] = []
        out.reserveCapacity(list.count)
        for row in list {
            guard let px = Self.parsePositiveDouble(row["price"]),
                  let sz = Self.parsePositiveDouble(row["size"]),
                  let side = (row["side"] as? String)?.lowercased()
            else { continue }
            let tsMs = Self.parsePositiveDouble(row["time"]) ?? (Date().timeIntervalSince1970 * 1000.0)
            out.append(OrderFlowTrade(
                price: px,
                quantity: sz,
                isBuyerMaker: (side == "sell"),
                timestampEpochSeconds: tsMs / 1000.0
            ))
        }
        return out
    }

    // MARK: - Venue 3: Binance USD-M Futures Public (Instant Failover on HTTP 451/403)

    private func fetchBinanceSnapshot(symbols: CryptoOrderFlowVenueSymbols) async -> OrderFlowSnapshot? {
        guard let book = await fetchBinanceFuturesOrderBook(symbol: symbols.binanceFuturesSymbol) else {
            return nil
        }
        let trades = await fetchBinanceFuturesAggTrades(symbol: symbols.binanceFuturesSymbol)
        return Self.buildValidatedSnapshot(
            venue: "Binance",
            isLiveWebSocket: false,
            bids: book.bids,
            asks: book.asks,
            trades: trades,
            liquidations: []
        )
    }

    private func fetchBinanceFuturesOrderBook(symbol: String) async -> (bids: [OrderBookLevel], asks: [OrderBookLevel])? {
        guard let url = URL(string: "https://fapi.binance.com/fapi/v1/depth?symbol=\(symbol)&limit=100") else { return nil }
        guard let data = await sendFastGET(url: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let bids = Self.parseStringTupleLevels(root["bids"] as? [[Any]])
        let asks = Self.parseStringTupleLevels(root["asks"] as? [[Any]])
        guard !bids.isEmpty, !asks.isEmpty else { return nil }
        return (bids, asks)
    }

    private func fetchBinanceFuturesAggTrades(symbol: String) async -> [OrderFlowTrade] {
        guard let url = URL(string: "https://fapi.binance.com/fapi/v1/aggTrades?symbol=\(symbol)&limit=100") else { return [] }
        guard let data = await sendFastGET(url: url),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }

        var out: [OrderFlowTrade] = []
        out.reserveCapacity(rows.count)
        for row in rows {
            guard let px = Self.parsePositiveDouble(row["p"]),
                  let qty = Self.parsePositiveDouble(row["q"]),
                  let isBuyerMaker = row["m"] as? Bool
            else { continue }
            let tsMs = Self.parsePositiveDouble(row["T"]) ?? (Date().timeIntervalSince1970 * 1000.0)
            out.append(OrderFlowTrade(
                price: px,
                quantity: qty,
                isBuyerMaker: isBuyerMaker,
                timestampEpochSeconds: tsMs / 1000.0
            ))
        }
        return out
    }

    // MARK: - Networking & Validation Helpers

    private func sendFastGET(url: URL) async -> Data? {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = requestTimeout
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let res = try await http.send(req, maxRetries: 0)
            return res.data
        } catch {
            // Immediate failover on HTTP 451 / 403 / timeout / network error
            return nil
        }
    }

    public static func parsePositiveDouble(_ any: Any?) -> Double? {
        let val: Double?
        if let d = any as? Double {
            val = d
        } else if let i = any as? Int {
            val = Double(i)
        } else if let s = any as? String {
            val = Double(s)
        } else {
            val = nil
        }
        guard let v = val, v.isFinite, v > 0 else { return nil }
        return v
    }

    public static func parseStringTupleLevels(_ raw: [[Any]]?) -> [OrderBookLevel] {
        guard let raw else { return [] }
        var out: [OrderBookLevel] = []
        out.reserveCapacity(raw.count)
        for entry in raw {
            guard entry.count >= 2,
                  let px = parsePositiveDouble(entry[0]),
                  let qty = parsePositiveDouble(entry[1])
            else { continue }
            out.append(OrderBookLevel(price: px, quantity: qty))
        }
        return out
    }

    public static func buildValidatedSnapshot(
        venue: String,
        isLiveWebSocket: Bool,
        bids: [OrderBookLevel],
        asks: [OrderBookLevel],
        trades: [OrderFlowTrade],
        liquidations: [OrderFlowLiquidation],
        confirmedWallPrices: [Double] = [],
        nowEpochSeconds: TimeInterval = Date().timeIntervalSince1970
    ) -> OrderFlowSnapshot? {
        let sortedBids = bids
            .filter { $0.price.isFinite && $0.price > 0 && $0.quantity.isFinite && $0.quantity > 0 }
            .sorted { $0.price > $1.price }
        let sortedAsks = asks
            .filter { $0.price.isFinite && $0.price > 0 && $0.quantity.isFinite && $0.quantity > 0 }
            .sorted { $0.price < $1.price }

        guard let bestBid = sortedBids.first?.price,
              let bestAsk = sortedAsks.first?.price,
              bestAsk > bestBid
        else { return nil }

        let mid = (bestBid + bestAsk) * 0.5
        guard mid.isFinite, mid > 0 else { return nil }
        let spreadBps = ((bestAsk - bestBid) / mid) * 10_000.0
        guard spreadBps.isFinite, spreadBps >= 0 else { return nil }

        return OrderFlowSnapshot(
            timestampEpochSeconds: nowEpochSeconds,
            venue: venue,
            isLiveWebSocket: isLiveWebSocket,
            midPrice: mid,
            bestBid: bestBid,
            bestAsk: bestAsk,
            spreadBps: spreadBps,
            bids: sortedBids,
            asks: sortedAsks,
            recentTrades: trades,
            recentLiquidations: liquidations,
            confirmedWallPrices: confirmedWallPrices
        )
    }
}
