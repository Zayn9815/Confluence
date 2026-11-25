import Foundation
import SignalEngine

public struct TwelveDataQuotaStatus: Codable, Sendable, Equatable {
    public let currentMinuteUsage: Int
    public let planMinuteLimit: Int
    public let dailyUsage: Int?
    public let planDailyLimit: Int?
    public let planCategory: String
    public let checkedAt: Date

    public init(
        currentMinuteUsage: Int,
        planMinuteLimit: Int,
        dailyUsage: Int?,
        planDailyLimit: Int?,
        planCategory: String,
        checkedAt: Date = Date()
    ) {
        self.currentMinuteUsage = currentMinuteUsage
        self.planMinuteLimit = planMinuteLimit
        self.dailyUsage = dailyUsage
        self.planDailyLimit = planDailyLimit
        self.planCategory = planCategory
        self.checkedAt = checkedAt
    }

    public var remainingDailyCredits: Int? {
        guard let used = dailyUsage, let cap = planDailyLimit else { return nil }
        return max(0, cap - used)
    }

    public var summaryText: String {
        if let used = dailyUsage, let cap = planDailyLimit {
            let rem = max(0, cap - used)
            return "\(planCategory) · \(rem)/\(cap) daily left (\(currentMinuteUsage)/\(planMinuteLimit)/min)"
        }
        return "\(planCategory) · \(currentMinuteUsage)/\(planMinuteLimit) req/min"
    }
}

public enum TwelveDataError: Error, LocalizedError, Sendable {
    case planRestrictedSymbol(String, String)
    case invalidAPIKey(String)
    case symbolNotFound(String)
    case apiRateLimited(String)

    public var errorDescription: String? {
        switch self {
        case .planRestrictedSymbol(let sym, let msg):
            return "Twelve Data plan restriction for \(sym): \(msg)"
        case .invalidAPIKey(let msg):
            return "Twelve Data invalid API key: \(msg)"
        case .symbolNotFound(let sym):
            return "Twelve Data symbol unavailable: \(sym)"
        case .apiRateLimited(let msg):
            return "Twelve Data rate limit: \(msg)"
        }
    }
}

/// First-class Swift 6 `twelvedata.com` REST adapter shared across TradFi (Forex, Gold, Stocks, Indices/ETFs)
/// and Crypto. Enforces `timezone=UTC`, native `15min`/`1h`/`4h`/`1day` intervals, ascending UTC candle order,
/// closed-candle anti-repainting, header authentication (`Authorization: apikey`), HTTP-200 JSON error handling,
/// persistent 7/min & 780/day token-bucket pacing, and `/api_usage` live quota inspection.
public actor TwelveDataAdapter {
    private let http: any HTTPTransport
    private let pacer: ProviderRatePacer
    private var planRestrictedSymbols: Set<String> = []
    private var latestQuota: TwelveDataQuotaStatus?

    public init(
        http: any HTTPTransport,
        pacer: ProviderRatePacer = ProviderRatePacer(providerKey: "twelvedata", maxPerMinute: 7, maxPerUTCDay: 780)
    ) {
        self.http = http
        self.pacer = pacer
    }

    public func localDailyUsage() async -> Int {
        await pacer.dailyUsageCount()
    }

    public func cachedQuotaStatus() -> TwelveDataQuotaStatus? {
        latestQuota
    }

    public func isPlanRestricted(_ rawSymbol: String) -> Bool {
        planRestrictedSymbols.contains(rawSymbol.uppercased())
    }

    public func fetchCandles(
        asset: AssetDescriptor,
        timeframe: Timeframe,
        apiKey: String,
        allowProxySymbol: Bool = false
    ) async throws -> OHLCVFetchResult {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            throw NetworkAdapterError.missingAPIKey("Twelve Data")
        }

        let primarySym = asset.twelveDataSymbol
        let proxySym = allowProxySymbol ? asset.twelveDataProxySymbol : nil

        guard let targetSymbol = primarySym ?? proxySym else {
            throw TwelveDataError.symbolNotFound(asset.symbol)
        }

        // If primary symbol was already flagged as Grow/Pro-only on Basic plan this session:
        if planRestrictedSymbols.contains(targetSymbol.uppercased()) {
            if let proxy = proxySym, proxy.uppercased() != targetSymbol.uppercased() {
                return try await requestTimeSeries(
                    querySymbol: proxy,
                    asset: asset,
                    timeframe: timeframe,
                    apiKey: cleanKey,
                    providerBadge: "Twelve Data (\(proxy) Proxy)",
                    usedProxySymbol: proxy
                )
            }
            throw TwelveDataError.planRestrictedSymbol(targetSymbol, "Requires Grow/Pro plan (cached)")
        }

        do {
            return try await requestTimeSeries(
                querySymbol: targetSymbol,
                asset: asset,
                timeframe: timeframe,
                apiKey: cleanKey,
                providerBadge: "Twelve Data",
                usedProxySymbol: nil
            )
        } catch TwelveDataError.planRestrictedSymbol(let restrictedSym, let message) {
            planRestrictedSymbols.insert(restrictedSym.uppercased())
            if let proxy = proxySym, proxy.uppercased() != restrictedSym.uppercased() {
                return try await requestTimeSeries(
                    querySymbol: proxy,
                    asset: asset,
                    timeframe: timeframe,
                    apiKey: cleanKey,
                    providerBadge: "Twelve Data (\(proxy) Proxy)",
                    usedProxySymbol: proxy
                )
            }
            throw TwelveDataError.planRestrictedSymbol(restrictedSym, message)
        }
    }

    public func testKeyAndQuota(apiKey: String) async throws -> TwelveDataQuotaStatus {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            throw NetworkAdapterError.missingAPIKey("Twelve Data")
        }

        guard let url = URL(string: "https://api.twelvedata.com/api_usage") else {
            throw NetworkAdapterError.invalidURL("https://api.twelvedata.com/api_usage")
        }
        var req = URLRequest(url: url)
        req.setValue("apikey \(cleanKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let res = try await http.send(req, maxRetries: 1)
        let parsed = try Self.parseQuotaUsageJSON(data: res.data)
        self.latestQuota = parsed
        return parsed
    }

    private func requestTimeSeries(
        querySymbol: String,
        asset: AssetDescriptor,
        timeframe: Timeframe,
        apiKey: String,
        providerBadge: String,
        usedProxySymbol: String?
    ) async throws -> OHLCVFetchResult {
        try await pacer.acquireSlot()

        let interval: String
        switch timeframe {
        case .m15: interval = "15min"
        case .h1: interval = "1h"
        case .h4: interval = "4h"
        case .d1: interval = "1day"
        }

        var comps = URLComponents(string: "https://api.twelvedata.com/time_series")!
        comps.queryItems = [
            URLQueryItem(name: "symbol", value: querySymbol),
            URLQueryItem(name: "interval", value: interval),
            URLQueryItem(name: "outputsize", value: "200"),
            URLQueryItem(name: "timezone", value: "UTC")
        ]
        guard let url = comps.url else {
            throw NetworkAdapterError.invalidURL("Twelve Data time_series")
        }

        var req = URLRequest(url: url)
        req.setValue("apikey \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let res = try await http.send(req, maxRetries: 1)
        let serverNow = (res.serverDate ?? Date()).timeIntervalSince1970
        let candles = try Self.parseTimeSeriesJSON(
            data: res.data,
            querySymbol: querySymbol,
            timeframe: timeframe,
            marketClass: asset.marketClass,
            serverNowEpochSeconds: serverNow
        )
        return OHLCVFetchResult(
            candles: candles,
            providerName: providerBadge,
            latencyMs: res.latencyMs,
            proxySymbolUsed: usedProxySymbol
        )
    }

    public static func parseTimeSeriesJSON(
        data: Data,
        querySymbol: String,
        timeframe: Timeframe,
        marketClass: MarketClass,
        serverNowEpochSeconds: TimeInterval
    ) throws -> [Candle] {
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
            let code: Int?
            let message: String?
            let values: [Bar]?
        }

        let decoded = try JSONDecoder().decode(TDResp.self, from: data)
        if decoded.status?.lowercased() == "error" || decoded.values == nil {
            let msg = decoded.message ?? "Twelve Data returned no values"
            let code = decoded.code ?? 0
            if code == 401 {
                throw TwelveDataError.invalidAPIKey(msg)
            }
            if code == 403 || msg.lowercased().contains("grow") || msg.lowercased().contains("pro") || msg.lowercased().contains("plan") {
                throw TwelveDataError.planRestrictedSymbol(querySymbol, msg)
            }
            if code == 429 || msg.lowercased().contains("credits") {
                throw TwelveDataError.apiRateLimited(msg)
            }
            if code == 404 {
                throw TwelveDataError.symbolNotFound(querySymbol)
            }
            throw NetworkAdapterError.decodingFailed(msg)
        }

        guard let values = decoded.values, !values.isEmpty else {
            throw NetworkAdapterError.decodingFailed("Twelve Data returned empty series")
        }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let dfDate = DateFormatter()
        dfDate.locale = Locale(identifier: "en_US_POSIX")
        dfDate.timeZone = TimeZone(secondsFromGMT: 0)
        dfDate.dateFormat = "yyyy-MM-dd"

        var out: [Candle] = []
        out.reserveCapacity(values.count)

        for v in values {
            guard let date = df.date(from: v.datetime) ?? dfDate.date(from: v.datetime),
                  let o = Double(v.open), let h = Double(v.high),
                  let l = Double(v.low), let c = Double(v.close)
            else { continue }
            let openSec = date.timeIntervalSince1970
            let closeSec = openSec + timeframe.seconds
            let volRaw = v.volume.flatMap(Double.init)
            let cleanVol = (marketClass.isOTCVolumeUnavailable && (volRaw ?? 0) <= 0) ? nil : volRaw
            out.append(Candle(
                openTimeEpochSeconds: openSec,
                closeTimeEpochSeconds: closeSec,
                open: o, high: h, low: l, close: c,
                volume: cleanVol,
                isClosed: closeSec <= serverNowEpochSeconds
            ))
        }

        return out.sorted { $0.openTimeEpochSeconds < $1.openTimeEpochSeconds }
    }

    public static func parseQuotaUsageJSON(data: Data) throws -> TwelveDataQuotaStatus {
        struct UsageResp: Decodable {
            let status: String?
            let code: Int?
            let message: String?
            let current_usage: Int?
            let plan_limit: Int?
            let daily_usage: Int?
            let plan_daily_limit: Int?
            let plan_category: String?
        }

        let decoded = try JSONDecoder().decode(UsageResp.self, from: data)
        if decoded.status?.lowercased() == "error" {
            let msg = decoded.message ?? "API usage check failed"
            if decoded.code == 401 {
                throw TwelveDataError.invalidAPIKey(msg)
            }
            throw NetworkAdapterError.decodingFailed(msg)
        }
        guard let current = decoded.current_usage, let limit = decoded.plan_limit else {
            throw NetworkAdapterError.decodingFailed("Missing current_usage / plan_limit in /api_usage")
        }
        return TwelveDataQuotaStatus(
            currentMinuteUsage: current,
            planMinuteLimit: limit,
            dailyUsage: decoded.daily_usage,
            planDailyLimit: decoded.plan_daily_limit,
            planCategory: decoded.plan_category ?? "Basic"
        )
    }
}
