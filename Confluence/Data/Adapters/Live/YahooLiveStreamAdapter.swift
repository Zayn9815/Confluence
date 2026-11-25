import Foundation
import SignalEngine

public struct YahooPricingTick: Sendable, Equatable {
    public let id: String
    public let price: Double
    public let timestampEpochSeconds: TimeInterval
    public let changePercent: Double?
    public let marketHours: Int?

    public init(
        id: String,
        price: Double,
        timestampEpochSeconds: TimeInterval,
        changePercent: Double? = nil,
        marketHours: Int? = nil
    ) {
        self.id = id
        self.price = price
        self.timestampEpochSeconds = timestampEpochSeconds
        self.changePercent = changePercent
        self.marketHours = marketHours
    }
}

/// Zero-dependency pure-Swift decoder for Yahoo Finance WebSocket Base64-encoded `PricingData`
/// Protobuf frames (`wss://streamer.finance.yahoo.com/`), plus bad-tick and scale-mismatch guards.
public enum YahooPricingProtobufDecoder {
    /// Decodes a Base64-encoded Yahoo `PricingData` protobuf payload:
    /// - field 1: `id` (string, wireType 2)
    /// - field 2: `price` (float, wireType 5 fixed32)
    /// - field 3: `time` (sint64, wireType 0 ZigZag-encoded ms)
    /// - field 8: `changePercent` (float, wireType 5 fixed32)
    /// - field 12: `marketHours` (varint, wireType 0)
    public static func decodeBase64(_ base64String: String) -> YahooPricingTick? {
        guard let data = Data(base64Encoded: base64String.trimmingCharacters(in: .whitespacesAndNewlines)),
              !data.isEmpty
        else { return nil }
        return decode(data)
    }

    public static func decode(_ data: Data) -> YahooPricingTick? {
        let bytes = [UInt8](data)
        var idx = 0
        var id: String?
        var price: Double?
        var timeEpochSec: TimeInterval?
        var changePercent: Double?
        var marketHours: Int?

        func readVarint() -> UInt64? {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while idx < bytes.count && shift < 64 {
                let b = bytes[idx]
                idx += 1
                result |= UInt64(b & 0x7F) << shift
                if (b & 0x80) == 0 { return result }
                shift += 7
            }
            return nil
        }

        func readFloat32() -> Double? {
            guard idx + 4 <= bytes.count else { return nil }
            let bits = UInt32(bytes[idx])
                | (UInt32(bytes[idx + 1]) << 8)
                | (UInt32(bytes[idx + 2]) << 16)
                | (UInt32(bytes[idx + 3]) << 24)
            idx += 4
            let f = Float(bitPattern: bits)
            return f.isFinite ? Double(f) : nil
        }

        while idx < bytes.count {
            guard let tag = readVarint() else { break }
            let fieldNumber = Int(tag >> 3)
            let wireType = Int(tag & 0x07)

            switch (fieldNumber, wireType) {
            case (1, 2):
                guard let len = readVarint(), idx + Int(len) <= bytes.count else { return nil }
                let slice = bytes[idx..<(idx + Int(len))]
                idx += Int(len)
                id = String(bytes: slice, encoding: .utf8)
            case (2, 5):
                price = readFloat32()
            case (3, 0):
                guard let raw = readVarint() else { return nil }
                // Protobuf sint64 ZigZag decoding
                let signed = Int64(bitPattern: (raw >> 1) ^ (0 &- (raw & 1)))
                let absVal = abs(signed)
                if absVal > 100_000_000_000 {
                    timeEpochSec = TimeInterval(signed) / 1000.0
                } else {
                    timeEpochSec = TimeInterval(signed)
                }
            case (8, 5):
                changePercent = readFloat32()
            case (12, 0):
                if let mh = readVarint() {
                    marketHours = Int(mh)
                }
            default:
                // Skip unrecognized fields safely by wire type
                switch wireType {
                case 0:
                    guard readVarint() != nil else { return nil }
                case 1:
                    guard idx + 8 <= bytes.count else { return nil }
                    idx += 8
                case 2:
                    guard let len = readVarint(), idx + Int(len) <= bytes.count else { return nil }
                    idx += Int(len)
                case 5:
                    guard idx + 4 <= bytes.count else { return nil }
                    idx += 4
                default:
                    return nil
                }
            }
        }

        guard let symbolId = id, !symbolId.isEmpty,
              let validPrice = price, validPrice.isFinite, validPrice > 0
        else { return nil }

        return YahooPricingTick(
            id: symbolId,
            price: validPrice,
            timestampEpochSeconds: timeEpochSec ?? Date().timeIntervalSince1970,
            changePercent: changePercent,
            marketHours: marketHours
        )
    }

    /// Bad-tick & scale-mismatch guard for TradFi WebSocket ticks.
    /// Rejects >2% FX/gold/indices or >5% stocks deviation from `referenceClose` so proxy/futures
    /// scale mismatches (e.g. SPY vs US500 or GC=F diverging from spot XAU/USD) automatically
    /// fall back to `biquote.io` polling instead of corrupting the price.
    public static func isAcceptableTick(
        marketClass: MarketClass,
        price: Double,
        referenceClose: Double?
    ) -> Bool {
        guard price.isFinite, price > 0 else { return false }
        guard let ref = referenceClose, ref.isFinite, ref > 0 else { return true }
        let deviation = abs(price - ref) / ref
        let limit: Double = (marketClass == .stocks) ? 0.05 : 0.02
        return deviation <= limit
    }
}

/// Lightweight foreground-only `URLSessionWebSocketTask` client for `wss://streamer.finance.yahoo.com/`.
public actor YahooLiveStreamAdapter {
    public static let endpointURL = URL(string: "wss://streamer.finance.yahoo.com/")!

    private let session: URLSession
    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveLoopTask: Task<Void, Never>?
    private var subscribedYahooSymbols: [String] = []
    private var isConnectedFlag: Bool = false

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public var isConnected: Bool {
        isConnectedFlag
    }

    public func connect(
        yahooSymbols: [String],
        onTick: @escaping @Sendable (YahooPricingTick) async -> Void,
        onDisconnect: @escaping @Sendable (String) async -> Void
    ) {
        disconnect()
        let cleaned = Array(Set(yahooSymbols.filter { !$0.isEmpty })).sorted()
        guard !cleaned.isEmpty else { return }
        subscribedYahooSymbols = cleaned

        var request = URLRequest(url: Self.endpointURL)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let ws = session.webSocketTask(with: request)
        self.webSocketTask = ws
        ws.resume()
        self.isConnectedFlag = true

        let subPayload: [String: Any] = ["subscribe": cleaned]
        if let data = try? JSONSerialization.data(withJSONObject: subPayload),
           let json = String(data: data, encoding: .utf8) {
            ws.send(.string(json)) { _ in }
        }

        receiveLoopTask = Task { [weak self] in
            await self?.runReceiveLoop(ws: ws, onTick: onTick, onDisconnect: onDisconnect)
        }
    }

    public func disconnect() {
        receiveLoopTask?.cancel()
        receiveLoopTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isConnectedFlag = false
        subscribedYahooSymbols = []
    }

    private func runReceiveLoop(
        ws: URLSessionWebSocketTask,
        onTick: @escaping @Sendable (YahooPricingTick) async -> Void,
        onDisconnect: @escaping @Sendable (String) async -> Void
    ) async {
        while !Task.isCancelled {
            do {
                let message = try await ws.receive()
                switch message {
                case .string(let text):
                    if let tick = YahooPricingProtobufDecoder.decodeBase64(text) {
                        await onTick(tick)
                    }
                case .data(let raw):
                    if let tick = YahooPricingProtobufDecoder.decode(raw) {
                        await onTick(tick)
                    }
                @unknown default:
                    break
                }
            } catch {
                if !Task.isCancelled {
                    isConnectedFlag = false
                    await onDisconnect(error.localizedDescription)
                }
                return
            }
        }
    }
}
