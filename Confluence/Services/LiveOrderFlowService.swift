import Foundation
import Observation
import SignalEngine

/// Foreground-only, focused single-symbol Crypto-Only live Order Flow WebSocket service.
/// - **Hard Crypto-Only Gate:** Never opens sockets or network requests for non-crypto markets or when OFF.
/// - **3-Venue Failover:** OKX v5 (`wss://ws.okx.com:8443/ws/v5/public`, 20s literal `"ping"` + 14s `sz=100` deep-book refresh)
///   → Bybit v5 (`wss://stream.bybit.com/v5/public/linear`, 20s `{"op":"ping"}` + delta seq-gap resync)
///   → Binance USD-M Futures (`wss://fstream.binance.com/...`).
/// - **Anti-Spoofing Wall Persistence:** Tracks first-seen timestamps per wall level; marks confirmed ONLY after surviving `>= 6.0s`.
/// - **Battery Discipline:** Coalesces `@Observable` updates to `<= 4 Hz` normally and `<= 1.5 Hz` in iOS Low Power Mode.
///   Disconnects immediately on background (`scenePhase != .active`), screen exit, non-crypto switch, or toggle OFF.
@MainActor
@Observable
public final class LiveOrderFlowService {
    public private(set) var latestSnapshot: OrderFlowSnapshot?
    public private(set) var latestAssessment: OrderFlowAssessment?
    public private(set) var activeSymbol: String?
    public private(set) var activeVenue: String?
    public private(set) var isStreaming: Bool = false

    private let adapter: CryptoOrderFlowAdapter
    private var isForegroundActive: Bool = true
    private var isEnabled: Bool = false
    private var focusedSymbol: String?
    private var focusedAssetClass: MarketClass?
    private var focusedDirection: TradeDirection = .neutral
    private var focusedEntryPrice: Double?
    private var focusedTP1: Double?

    private struct WallBucketKey: Hashable, Sendable {
        let isBid: Bool
        let logBucket: Int64

        init(isBid: Bool, price: Double) {
            self.isBid = isBid
            // 2 bps log-scale buckets so sub-cent coins (e.g. PEPE) and BTC never collide or overflow
            let safePrice = max(price, 1e-12)
            self.logBucket = Int64((log(safePrice) / log(1.0002)).rounded())
        }
    }

    private var streamTask: Task<Void, Never>?
    @ObservationIgnored private nonisolated(unsafe) var powerModeObserver: NSObjectProtocol?
    private var isLowPowerMode: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled
    private var lastPublishTime: TimeInterval = 0
    private var sessionGeneration: UInt64 = 0

    // Rolling in-memory live state for the single focused crypto symbol
    private var liveBids: [Double: Double] = [:]
    private var liveAsks: [Double: Double] = [:]
    private var liveTrades: [OrderFlowTrade] = []
    private var liveLiquidations: [OrderFlowLiquidation] = []
    private var wallFirstSeen: [WallBucketKey: TimeInterval] = [:]
    private var bybitLastSeq: Int64?

    private static let wallConfirmationSeconds: TimeInterval = 6.0
    private static let maxRollingTrades = 120
    private static let maxRollingLiquidations = 40

    public init(adapter: CryptoOrderFlowAdapter) {
        self.adapter = adapter
        self.powerModeObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
    }

    deinit {
        if let observer = powerModeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    public func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        if !enabled {
            stopStream(clearState: true)
        } else {
            restartStreamIfEligible()
        }
    }

    public func setForegroundActive(_ active: Bool) {
        guard isForegroundActive != active else { return }
        isForegroundActive = active
        if active {
            restartStreamIfEligible()
        } else {
            stopStream(clearState: false)
        }
    }

    /// Focuses the single live WebSocket session on a crypto symbol (e.g. while `FullScreenChartSheet` is open).
    /// Immediately disconnects if `assetClass != .crypto` or `isEnabled == false`.
    public func focus(
        symbol: String,
        assetClass: MarketClass,
        direction: TradeDirection = .neutral,
        entryPrice: Double? = nil,
        takeProfit1: Double? = nil
    ) {
        self.focusedDirection = direction
        self.focusedEntryPrice = entryPrice
        self.focusedTP1 = takeProfit1

        // Hard Crypto-Only gate
        guard assetClass == .crypto else {
            self.focusedSymbol = nil
            self.focusedAssetClass = nil
            stopStream(clearState: true)
            return
        }

        let symbolChanged = (focusedSymbol != symbol)
        self.focusedSymbol = symbol
        self.focusedAssetClass = assetClass

        if symbolChanged {
            stopStream(clearState: true)
            restartStreamIfEligible()
        } else if streamTask == nil {
            restartStreamIfEligible()
        } else if let snap = latestSnapshot {
            publishEvaluation(from: snap, force: true)
        }
    }

    public func unfocus(symbol: String? = nil) {
        if let symbol, focusedSymbol != symbol { return }
        focusedSymbol = nil
        focusedAssetClass = nil
        stopStream(clearState: true)
    }

    public func stopStream(clearState: Bool) {
        sessionGeneration &+= 1
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        if clearState {
            activeSymbol = nil
            activeVenue = nil
            latestSnapshot = nil
            latestAssessment = nil
            resetBookBuffers()
        }
    }

    private func resetBookBuffers() {
        liveBids.removeAll(keepingCapacity: true)
        liveAsks.removeAll(keepingCapacity: true)
        liveTrades.removeAll(keepingCapacity: true)
        liveLiquidations.removeAll(keepingCapacity: true)
        wallFirstSeen.removeAll(keepingCapacity: true)
        bybitLastSeq = nil
    }

    private func restartStreamIfEligible() {
        stopStream(clearState: false)
        guard isEnabled,
              isForegroundActive,
              focusedAssetClass == .crypto,
              let symbol = focusedSymbol
        else {
            return
        }

        sessionGeneration &+= 1
        let myGen = sessionGeneration
        activeSymbol = symbol
        let syms = CryptoOrderFlowVenueSymbols.resolve(symbol: symbol)

        streamTask = Task { [weak self] in
            guard let self else { return }

            // 1. Seed immediately with a fast REST snapshot so HUD appears within < 1s
            if let initial = await self.adapter.fetchSnapshot(symbol: symbol, assetClass: .crypto) {
                guard !Task.isCancelled, self.sessionGeneration == myGen else { return }
                self.seedBuffers(from: initial)
                self.publishEvaluation(from: initial, force: true)
            }

            // 2. Live WebSocket loop with bounded exponential backoff + 3-venue failover
            let venues = ["OKX", "Bybit", "Binance"]
            var venueIndex = 0
            var backoffSeconds: Double = 1.5

            while !Task.isCancelled && self.sessionGeneration == myGen {
                let venue = venues[venueIndex % venues.count]
                self.activeVenue = venue
                let didReceiveMessages = await self.runVenueWebSocketSession(
                    venue: venue,
                    symbol: symbol,
                    venueSymbols: syms,
                    generation: myGen
                )
                if Task.isCancelled || self.sessionGeneration != myGen { break }
                self.isStreaming = false

                if didReceiveMessages {
                    backoffSeconds = 1.5
                } else {
                    venueIndex += 1
                    backoffSeconds = min(20.0, backoffSeconds * 1.8)
                }
                try? await Task.sleep(for: .seconds(backoffSeconds))
            }
        }
    }

    // MARK: - 3-Venue Live WebSocket Runners

    private func receiveMessage(
        from ws: URLSessionWebSocketTask,
        session: URLSession
    ) async throws -> URLSessionWebSocketTask.Message {
        try await withTaskCancellationHandler {
            try await ws.receive()
        } onCancel: {
            ws.cancel(with: .normalClosure, reason: nil)
            session.invalidateAndCancel()
        }
    }

    private func runVenueWebSocketSession(
        venue: String,
        symbol: String,
        venueSymbols: CryptoOrderFlowVenueSymbols,
        generation: UInt64
    ) async -> Bool {
        switch venue {
        case "OKX":
            return await runOKXSession(symbol: symbol, venueSymbols: venueSymbols, generation: generation)
        case "Bybit":
            return await runBybitSession(symbol: symbol, venueSymbols: venueSymbols, generation: generation)
        case "Binance":
            return await runBinanceSession(symbol: symbol, venueSymbols: venueSymbols, generation: generation)
        default:
            return false
        }
    }

    private func runOKXSession(
        symbol: String,
        venueSymbols: CryptoOrderFlowVenueSymbols,
        generation: UInt64
    ) async -> Bool {
        guard let url = URL(string: "wss://ws.okx.com:8443/ws/v5/public") else { return false }
        let session = URLSession(configuration: .ephemeral)
        let ws = session.webSocketTask(with: url)
        ws.resume()
        defer {
            ws.cancel(with: .normalClosure, reason: nil)
            session.invalidateAndCancel()
        }

        let subPayload: [String: Any] = [
            "op": "subscribe",
            "args": [
                ["channel": "books5", "instId": venueSymbols.okxSwapInstId],
                ["channel": "trades", "instId": venueSymbols.okxSwapInstId],
                ["channel": "liquidation-orders", "instType": "SWAP"]
            ]
        ]
        guard let subData = try? JSONSerialization.data(withJSONObject: subPayload),
              let subText = String(data: subData, encoding: .utf8)
        else { return false }

        do {
            try await ws.send(.string(subText))
        } catch {
            return false
        }

        // CRITICAL: OKX literal "ping" text heartbeat every 20 seconds so connection never silently drops at 30s
        let heartbeatTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                if Task.isCancelled { break }
                do {
                    try await ws.send(.string("ping"))
                } catch {
                    break
                }
            }
        }

        // Periodic 14s sz=100 REST deep-book refresh (prevents books5 narrow-range blindness & delta drift)
        let deepBookTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(14))
                if Task.isCancelled { break }
                guard let self, self.sessionGeneration == generation else { break }
                if let deep = await self.adapter.fetchDeepBook(symbol: symbol, assetClass: .crypto, venue: "OKX") {
                    guard !Task.isCancelled, self.sessionGeneration == generation else { break }
                    self.replaceDeepBook(bids: deep.bids, asks: deep.asks)
                }
            }
        }
        defer {
            heartbeatTask.cancel()
            deepBookTask.cancel()
        }

        var receivedAny = false
        while !Task.isCancelled && sessionGeneration == generation {
            do {
                let message = try await receiveMessage(from: ws, session: session)
                guard sessionGeneration == generation else { break }
                let text: String
                switch message {
                case .string(let s): text = s
                case .data(let d): text = String(data: d, encoding: .utf8) ?? ""
                @unknown default: continue
                }
                if text == "pong" { continue }
                if handleOKXMessage(text, underlying: venueSymbols.okxUnderlying) {
                    receivedAny = true
                    isStreaming = true
                    emitLiveSnapshotIfDue(venue: "OKX")
                }
            } catch {
                break
            }
        }
        return receivedAny
    }

    private func runBybitSession(
        symbol: String,
        venueSymbols: CryptoOrderFlowVenueSymbols,
        generation: UInt64
    ) async -> Bool {
        guard let url = URL(string: "wss://stream.bybit.com/v5/public/linear") else { return false }
        let session = URLSession(configuration: .ephemeral)
        let ws = session.webSocketTask(with: url)
        ws.resume()
        defer {
            ws.cancel(with: .normalClosure, reason: nil)
            session.invalidateAndCancel()
        }

        let sym = venueSymbols.bybitLinearSymbol
        let subPayload: [String: Any] = [
            "op": "subscribe",
            "args": [
                "orderbook.50.\(sym)",
                "publicTrade.\(sym)",
                "allLiquidation.\(sym)"
            ]
        ]
        guard let subData = try? JSONSerialization.data(withJSONObject: subPayload),
              let subText = String(data: subData, encoding: .utf8)
        else { return false }

        do {
            try await ws.send(.string(subText))
        } catch {
            return false
        }

        let heartbeatTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                if Task.isCancelled { break }
                do {
                    try await ws.send(.string("{\"op\":\"ping\"}"))
                } catch {
                    break
                }
            }
        }
        defer { heartbeatTask.cancel() }

        bybitLastSeq = nil
        var receivedAny = false
        while !Task.isCancelled && sessionGeneration == generation {
            do {
                let message = try await receiveMessage(from: ws, session: session)
                guard sessionGeneration == generation else { break }
                let text: String
                switch message {
                case .string(let s): text = s
                case .data(let d): text = String(data: d, encoding: .utf8) ?? ""
                @unknown default: continue
                }
                let result = handleBybitMessage(text)
                if result.needsResync {
                    if let deep = await adapter.fetchDeepBook(symbol: symbol, assetClass: .crypto, venue: "Bybit") {
                        guard !Task.isCancelled, sessionGeneration == generation else { break }
                        replaceDeepBook(bids: deep.bids, asks: deep.asks)
                    }
                    bybitLastSeq = nil
                }
                if result.didUpdate {
                    receivedAny = true
                    isStreaming = true
                    emitLiveSnapshotIfDue(venue: "Bybit")
                }
            } catch {
                break
            }
        }
        return receivedAny
    }

    private func runBinanceSession(
        symbol: String,
        venueSymbols: CryptoOrderFlowVenueSymbols,
        generation: UInt64
    ) async -> Bool {
        let lowerSym = venueSymbols.binanceFuturesSymbol.lowercased()
        guard let url = URL(string: "wss://fstream.binance.com/stream?streams=\(lowerSym)@depth20@500ms/\(lowerSym)@aggTrade/!forceOrder@arr") else {
            return false
        }
        let session = URLSession(configuration: .ephemeral)
        let ws = session.webSocketTask(with: url)
        ws.resume()
        defer {
            ws.cancel(with: .normalClosure, reason: nil)
            session.invalidateAndCancel()
        }

        let deepBookTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(14))
                if Task.isCancelled { break }
                guard let self, self.sessionGeneration == generation else { break }
                // Refresh limit=100 if top-20 span < 25 bps
                if self.currentBookSpanBps() < 25.0,
                   let deep = await self.adapter.fetchDeepBook(symbol: symbol, assetClass: .crypto, venue: "Binance") {
                    guard !Task.isCancelled, self.sessionGeneration == generation else { break }
                    self.replaceDeepBook(bids: deep.bids, asks: deep.asks)
                }
            }
        }
        defer { deepBookTask.cancel() }

        var receivedAny = false
        while !Task.isCancelled && sessionGeneration == generation {
            do {
                let message = try await receiveMessage(from: ws, session: session)
                guard sessionGeneration == generation else { break }
                let text: String
                switch message {
                case .string(let s): text = s
                case .data(let d): text = String(data: d, encoding: .utf8) ?? ""
                @unknown default: continue
                }
                if handleBinanceMessage(text, expectedSymbol: venueSymbols.binanceFuturesSymbol) {
                    receivedAny = true
                    isStreaming = true
                    emitLiveSnapshotIfDue(venue: "Binance")
                }
            } catch {
                break
            }
        }
        return receivedAny
    }

    // MARK: - Message Parsers

    private func handleOKXMessage(_ text: String, underlying: String) -> Bool {
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arg = root["arg"] as? [String: Any],
              let channel = arg["channel"] as? String,
              let rows = root["data"] as? [[String: Any]],
              !rows.isEmpty
        else { return false }

        switch channel {
        case "books5":
            guard let first = rows.first else { return false }
            let bids = CryptoOrderFlowAdapter.parseStringTupleLevels(first["bids"] as? [[Any]])
            let asks = CryptoOrderFlowAdapter.parseStringTupleLevels(first["asks"] as? [[Any]])
            mergeTopOfBook(bids: bids, asks: asks)
            return true
        case "trades":
            for row in rows {
                guard let px = CryptoOrderFlowAdapter.parsePositiveDouble(row["px"]),
                      let sz = CryptoOrderFlowAdapter.parsePositiveDouble(row["sz"]),
                      let side = (row["side"] as? String)?.lowercased()
                else { continue }
                let tsMs = CryptoOrderFlowAdapter.parsePositiveDouble(row["ts"]) ?? (Date().timeIntervalSince1970 * 1000.0)
                appendTrade(OrderFlowTrade(
                    price: px,
                    quantity: sz,
                    isBuyerMaker: (side == "sell"),
                    timestampEpochSeconds: tsMs / 1000.0
                ))
            }
            return true
        case "liquidation-orders":
            var matched = false
            for row in rows {
                guard (row["uly"] as? String) == underlying,
                      let details = row["details"] as? [[String: Any]]
                else { continue }
                for d in details {
                    guard let px = CryptoOrderFlowAdapter.parsePositiveDouble(d["bkPx"]),
                          let sz = CryptoOrderFlowAdapter.parsePositiveDouble(d["sz"])
                    else { continue }
                    let tsMs = CryptoOrderFlowAdapter.parsePositiveDouble(d["ts"]) ?? (Date().timeIntervalSince1970 * 1000.0)
                    let posSide = (d["posSide"] as? String)?.lowercased() ?? ""
                    let side = (d["side"] as? String)?.lowercased() ?? ""
                    let isLongLiq = (posSide == "long") || (posSide.isEmpty && side == "sell")
                    appendLiquidation(OrderFlowLiquidation(
                        price: px,
                        sizeInSameUnits: sz,
                        isLongLiquidation: isLongLiq,
                        timestampEpochSeconds: tsMs / 1000.0
                    ))
                    matched = true
                }
            }
            return matched
        default:
            return false
        }
    }

    private func handleBybitMessage(_ text: String) -> (didUpdate: Bool, needsResync: Bool) {
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let topic = root["topic"] as? String
        else { return (false, false) }

        if topic.hasPrefix("orderbook."), let payload = root["data"] as? [String: Any] {
            let msgType = (root["type"] as? String)?.lowercased() ?? "delta"
            let seq = (payload["seq"] as? Int64) ?? (payload["seq"] as? Int).map(Int64.init)
            var needsResync = false
            if msgType == "snapshot" {
                liveBids.removeAll(keepingCapacity: true)
                liveAsks.removeAll(keepingCapacity: true)
                bybitLastSeq = seq
            } else if let prev = bybitLastSeq, let curr = seq, curr <= prev {
                return (false, false)
            } else if let prev = bybitLastSeq, let curr = seq, curr > prev + 100 {
                needsResync = true
            } else if let curr = seq {
                bybitLastSeq = curr
            }

            if let bRows = payload["b"] as? [[Any]] {
                for row in bRows where row.count >= 2 {
                    guard let px = CryptoOrderFlowAdapter.parsePositiveDouble(row[0]) else { continue }
                    let qty = (row[1] as? String).flatMap(Double.init) ?? (row[1] as? Double) ?? 0
                    if qty > 0 && qty.isFinite { liveBids[px] = qty } else { liveBids.removeValue(forKey: px) }
                }
            }
            if let aRows = payload["a"] as? [[Any]] {
                for row in aRows where row.count >= 2 {
                    guard let px = CryptoOrderFlowAdapter.parsePositiveDouble(row[0]) else { continue }
                    let qty = (row[1] as? String).flatMap(Double.init) ?? (row[1] as? Double) ?? 0
                    if qty > 0 && qty.isFinite { liveAsks[px] = qty } else { liveAsks.removeValue(forKey: px) }
                }
            }
            return (true, needsResync)
        }

        if topic.hasPrefix("publicTrade."), let rows = root["data"] as? [[String: Any]] {
            for row in rows {
                guard let px = CryptoOrderFlowAdapter.parsePositiveDouble(row["p"]),
                      let sz = CryptoOrderFlowAdapter.parsePositiveDouble(row["v"]),
                      let side = (row["S"] as? String)?.lowercased()
                else { continue }
                let tsMs = CryptoOrderFlowAdapter.parsePositiveDouble(row["T"]) ?? (Date().timeIntervalSince1970 * 1000.0)
                appendTrade(OrderFlowTrade(
                    price: px,
                    quantity: sz,
                    isBuyerMaker: (side == "sell"),
                    timestampEpochSeconds: tsMs / 1000.0
                ))
            }
            return (true, false)
        }

        if topic.hasPrefix("allLiquidation."), let rows = root["data"] as? [[String: Any]] {
            for row in rows {
                guard let px = CryptoOrderFlowAdapter.parsePositiveDouble(row["p"]),
                      let sz = CryptoOrderFlowAdapter.parsePositiveDouble(row["v"]),
                      let side = (row["S"] as? String)?.lowercased()
                else { continue }
                let tsMs = CryptoOrderFlowAdapter.parsePositiveDouble(row["T"]) ?? (Date().timeIntervalSince1970 * 1000.0)
                appendLiquidation(OrderFlowLiquidation(
                    price: px,
                    sizeInSameUnits: sz,
                    isLongLiquidation: (side == "sell"),
                    timestampEpochSeconds: tsMs / 1000.0
                ))
            }
            return (true, false)
        }

        return (false, false)
    }

    private func handleBinanceMessage(_ text: String, expectedSymbol: String) -> Bool {
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stream = root["stream"] as? String,
              let payload = root["data"] as? [String: Any]
        else { return false }

        if stream.contains("@depth") {
            let bids = CryptoOrderFlowAdapter.parseStringTupleLevels(payload["b"] as? [[Any]])
            let asks = CryptoOrderFlowAdapter.parseStringTupleLevels(payload["a"] as? [[Any]])
            mergeTopOfBook(bids: bids, asks: asks)
            return true
        }
        if stream.contains("@aggTrade") {
            guard let px = CryptoOrderFlowAdapter.parsePositiveDouble(payload["p"]),
                  let qty = CryptoOrderFlowAdapter.parsePositiveDouble(payload["q"]),
                  let isBuyerMaker = payload["m"] as? Bool
            else { return false }
            let tsMs = CryptoOrderFlowAdapter.parsePositiveDouble(payload["T"]) ?? (Date().timeIntervalSince1970 * 1000.0)
            appendTrade(OrderFlowTrade(
                price: px,
                quantity: qty,
                isBuyerMaker: isBuyerMaker,
                timestampEpochSeconds: tsMs / 1000.0
            ))
            return true
        }
        if stream.contains("forceOrder"), let o = payload["o"] as? [String: Any] {
            guard (o["s"] as? String)?.uppercased() == expectedSymbol.uppercased(),
                  let px = CryptoOrderFlowAdapter.parsePositiveDouble(o["p"]),
                  let qty = CryptoOrderFlowAdapter.parsePositiveDouble(o["q"]),
                  let side = (o["S"] as? String)?.uppercased()
            else { return false }
            let tsMs = CryptoOrderFlowAdapter.parsePositiveDouble(o["T"]) ?? (Date().timeIntervalSince1970 * 1000.0)
            appendLiquidation(OrderFlowLiquidation(
                price: px,
                sizeInSameUnits: qty,
                isLongLiquidation: (side == "SELL"),
                timestampEpochSeconds: tsMs / 1000.0
            ))
            return true
        }
        return false
    }

    // MARK: - Buffer, Wall Persistence & Battery-Safe Coalescing

    private func seedBuffers(from snapshot: OrderFlowSnapshot) {
        replaceDeepBook(bids: snapshot.bids, asks: snapshot.asks)
        liveTrades = Array(snapshot.recentTrades.suffix(Self.maxRollingTrades))
        liveLiquidations = Array(snapshot.recentLiquidations.suffix(Self.maxRollingLiquidations))
    }

    private func replaceDeepBook(bids: [OrderBookLevel], asks: [OrderBookLevel]) {
        liveBids.removeAll(keepingCapacity: true)
        liveAsks.removeAll(keepingCapacity: true)
        for b in bids { liveBids[b.price] = b.quantity }
        for a in asks { liveAsks[a.price] = a.quantity }
    }

    private func mergeTopOfBook(bids: [OrderBookLevel], asks: [OrderBookLevel]) {
        guard let minNewBid = bids.map(\.price).min(),
              let maxNewBid = bids.map(\.price).max(),
              let minNewAsk = asks.map(\.price).min(),
              let maxNewAsk = asks.map(\.price).max(),
              maxNewBid < minNewAsk
        else { return }
        // Refresh top-of-book window while preserving deeper resting levels and pruning any stale crossed levels
        liveBids = liveBids.filter { $0.key < minNewBid && $0.key < minNewAsk }
        for b in bids { liveBids[b.price] = b.quantity }
        liveAsks = liveAsks.filter { $0.key > maxNewAsk && $0.key > maxNewBid }
        for a in asks { liveAsks[a.price] = a.quantity }
    }

    private func appendTrade(_ trade: OrderFlowTrade) {
        liveTrades.append(trade)
        if liveTrades.count > Self.maxRollingTrades {
            liveTrades.removeFirst(liveTrades.count - Self.maxRollingTrades)
        }
    }

    private func appendLiquidation(_ liq: OrderFlowLiquidation) {
        liveLiquidations.append(liq)
        if liveLiquidations.count > Self.maxRollingLiquidations {
            liveLiquidations.removeFirst(liveLiquidations.count - Self.maxRollingLiquidations)
        }
    }

    private func currentBookSpanBps() -> Double {
        let sortedBids = liveBids.keys.sorted(by: >)
        let sortedAsks = liveAsks.keys.sorted(by: <)
        guard let bestBid = sortedBids.first, let deepestBid = sortedBids.last,
              let bestAsk = sortedAsks.first, let deepestAsk = sortedAsks.last,
              bestBid > 0, bestAsk > 0
        else { return 0 }
        let bidSpan = ((bestBid - deepestBid) / bestBid) * 10_000.0
        let askSpan = ((deepestAsk - bestAsk) / bestAsk) * 10_000.0
        return min(bidSpan, askSpan)
    }

    private func emitLiveSnapshotIfDue(venue: String) {
        let now = Date().timeIntervalSince1970
        // Coalesce <= 4 Hz normally, <= 1.5 Hz in Low Power Mode
        let minInterval: TimeInterval = isLowPowerMode ? (1.0 / 1.5) : 0.25
        guard (now - lastPublishTime) >= minInterval else { return }

        let bidLevels = liveBids.map { OrderBookLevel(price: $0.key, quantity: $0.value) }.sorted { $0.price > $1.price }
        let askLevels = liveAsks.map { OrderBookLevel(price: $0.key, quantity: $0.value) }.sorted { $0.price < $1.price }

        let confirmedWalls = updateWallPersistenceAndConfirmedPrices(bids: bidLevels, asks: askLevels, now: now)
        let recentLiqCutoff = now - 300.0
        let activeLiqs = liveLiquidations.filter { $0.timestampEpochSeconds >= recentLiqCutoff }

        guard let snapshot = CryptoOrderFlowAdapter.buildValidatedSnapshot(
            venue: venue,
            isLiveWebSocket: true,
            bids: bidLevels,
            asks: askLevels,
            trades: liveTrades,
            liquidations: activeLiqs,
            confirmedWallPrices: confirmedWalls,
            nowEpochSeconds: now
        ) else { return }

        publishEvaluation(from: snapshot, force: false)
    }

    private func updateWallPersistenceAndConfirmedPrices(
        bids: [OrderBookLevel],
        asks: [OrderBookLevel],
        now: TimeInterval
    ) -> [Double] {
        var currentWallBuckets: [WallBucketKey: Double] = [:]

        func scanSide(_ levels: [OrderBookLevel], isBid: Bool) {
            guard levels.count >= 3 else { return }
            let sizes = levels.map(\.quantity).sorted()
            let midIdx = sizes.count / 2
            let median = (sizes.count % 2 == 0) ? ((sizes[midIdx - 1] + sizes[midIdx]) * 0.5) : sizes[midIdx]
            guard median > 0 else { return }
            let threshold = median * OrderFlowAnalyzer.wallMedianMultipleThreshold
            for lv in levels where lv.quantity >= threshold {
                let bucket = WallBucketKey(isBid: isBid, price: lv.price)
                currentWallBuckets[bucket] = lv.price
            }
        }

        scanSide(bids, isBid: true)
        scanSide(asks, isBid: false)

        // Drop disappeared walls immediately (anti-spoofing flash-wall filter)
        wallFirstSeen = wallFirstSeen.filter { currentWallBuckets[$0.key] != nil }

        var confirmed: [Double] = []
        for (bucket, price) in currentWallBuckets {
            if let first = wallFirstSeen[bucket] {
                if (now - first) >= Self.wallConfirmationSeconds {
                    confirmed.append(price)
                }
            } else {
                wallFirstSeen[bucket] = now
            }
        }
        return confirmed
    }

    private func publishEvaluation(from snapshot: OrderFlowSnapshot, force: Bool) {
        let now = Date().timeIntervalSince1970
        let minInterval: TimeInterval = isLowPowerMode ? (1.0 / 1.5) : 0.25
        if !force && (now - lastPublishTime) < minInterval { return }
        lastPublishTime = now

        let assessment = OrderFlowAnalyzer.evaluate(
            snapshot: snapshot,
            marketClass: focusedAssetClass ?? .crypto,
            isOrderFlowEnabled: isEnabled,
            isLiveEvaluation: true,
            candidateDirection: focusedDirection,
            entryPrice: focusedEntryPrice,
            takeProfit1: focusedTP1,
            nowEpochSeconds: now
        )
        self.latestSnapshot = snapshot
        self.latestAssessment = assessment
    }
}
