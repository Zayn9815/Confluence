import Foundation
import SignalEngine

/// Keyless OKX public v5 derivatives positioning adapter (funding rate, funding history, live OI,
/// and UTC-aligned OI history using `1Dutc` for daily bars and respecting the 1,440-bar cap).
public actor OKXPositioningAdapter {
    private let http: any HTTPTransport
    private var cache: [String: (fetchedAt: Date, snapshot: OKXDerivativesSnapshot)] = [:]
    private let cacheTTLSeconds: TimeInterval = 300.0

    public init(http: any HTTPTransport) {
        self.http = http
    }

    public func fetchSnapshot(instId: String, period: String = "1H", forceRefresh: Bool = false) async throws -> OKXDerivativesSnapshot {
        // Guard against OKX UTC+8 offset bug: coerce "1D" -> "1Dutc"
        let safePeriod = (period == "1D") ? "1Dutc" : period
        let cacheKey = "\(instId)|\(safePeriod)"
        if !forceRefresh, let entry = cache[cacheKey], Date().timeIntervalSince(entry.fetchedAt) < cacheTTLSeconds {
            return entry.snapshot
        }

        async let liveFundingTask = fetchCurrentFunding(instId: instId)
        async let fundingHistTask = fetchFundingHistory(instId: instId)
        async let liveOITask = fetchLiveOI(instId: instId)
        async let oiHistTask = fetchOIHistory(instId: instId, period: safePeriod)

        let (liveFunding, fundingHist, liveOI, oiHist) = try await (liveFundingTask, fundingHistTask, liveOITask, oiHistTask)
        let snap = OKXDerivativesSnapshot(
            instId: instId,
            currentFundingRate: liveFunding.rate,
            nextFundingTimeEpochSeconds: liveFunding.nextTime,
            liveOpenInterestUSD: liveOI,
            fundingHistory: fundingHist,
            openInterestHistory: oiHist,
            fetchedAtEpochSeconds: Date().timeIntervalSince1970
        )
        cache[cacheKey] = (Date(), snap)
        return snap
    }

    private func makeOKXURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "www.okx.com"
        comps.path = path
        comps.queryItems = queryItems
        guard let url = comps.url else {
            throw NetworkAdapterError.invalidURL("OKX \(path)")
        }
        return url
    }

    private func fetchCurrentFunding(instId: String) async throws -> (rate: Double, nextTime: TimeInterval?) {
        let url = try makeOKXURL(path: "/api/v5/public/funding-rate", queryItems: [
            URLQueryItem(name: "instId", value: instId)
        ])
        let res = try await http.send(URLRequest(url: url), maxRetries: 1)
        struct Resp: Decodable {
            struct Item: Decodable {
                let fundingRate: String
                let nextFundingTime: String?
            }
            let code: String?
            let msg: String?
            let data: [Item]?
        }
        let decoded = try JSONDecoder().decode(Resp.self, from: res.data)
        if let code = decoded.code, code != "0" {
            throw NetworkAdapterError.decodingFailed("OKX funding-rate code=\(code) \(decoded.msg ?? "")")
        }
        guard let item = decoded.data?.first, let rate = Double(item.fundingRate), rate.isFinite else {
            throw NetworkAdapterError.decodingFailed("OKX funding-rate empty")
        }
        let nextSec = item.nextFundingTime.flatMap(Double.init).flatMap { $0.isFinite ? $0 / 1000.0 : nil }
        return (rate, nextSec)
    }

    private func fetchFundingHistory(instId: String) async throws -> [OKXFundingPoint] {
        let url = try makeOKXURL(path: "/api/v5/public/funding-rate-history", queryItems: [
            URLQueryItem(name: "instId", value: instId),
            URLQueryItem(name: "limit", value: "100")
        ])
        let res = try await http.send(URLRequest(url: url), maxRetries: 1)
        struct Resp: Decodable {
            struct Item: Decodable {
                let fundingTime: String
                let fundingRate: String
                let realizedRate: String?
            }
            let code: String?
            let msg: String?
            let data: [Item]?
        }
        let decoded = try JSONDecoder().decode(Resp.self, from: res.data)
        if let code = decoded.code, code != "0" {
            throw NetworkAdapterError.decodingFailed("OKX funding-rate-history code=\(code) \(decoded.msg ?? "")")
        }
        return (decoded.data ?? []).compactMap { item in
            guard let ms = Double(item.fundingTime), ms.isFinite,
                  let rate = Double(item.fundingRate), rate.isFinite
            else { return nil }
            let realized = item.realizedRate.flatMap(Double.init).flatMap { $0.isFinite ? $0 : nil }
            return OKXFundingPoint(
                fundingTimeEpochSeconds: ms / 1000.0,
                fundingRate: rate,
                realizedRate: realized
            )
        }.sorted { $0.fundingTimeEpochSeconds < $1.fundingTimeEpochSeconds }
    }

    private func fetchLiveOI(instId: String) async throws -> Double? {
        let url = try makeOKXURL(path: "/api/v5/public/open-interest", queryItems: [
            URLQueryItem(name: "instType", value: "SWAP"),
            URLQueryItem(name: "instId", value: instId)
        ])
        let res = try await http.send(URLRequest(url: url), maxRetries: 1)
        struct Resp: Decodable {
            struct Item: Decodable { let oiUsd: String? }
            let code: String?
            let msg: String?
            let data: [Item]?
        }
        let decoded = try JSONDecoder().decode(Resp.self, from: res.data)
        if let code = decoded.code, code != "0" {
            throw NetworkAdapterError.decodingFailed("OKX open-interest code=\(code) \(decoded.msg ?? "")")
        }
        return decoded.data?.first?.oiUsd.flatMap(Double.init).flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    }

    private func fetchOIHistory(instId: String, period: String) async throws -> [OKXOpenInterestPoint] {
        // Respect OKX 100 rows/call and 1,440 max history cap
        let url = try makeOKXURL(path: "/api/v5/rubik/stat/contracts/open-interest-history", queryItems: [
            URLQueryItem(name: "instId", value: instId),
            URLQueryItem(name: "period", value: period),
            URLQueryItem(name: "limit", value: "100")
        ])
        let res = try await http.send(URLRequest(url: url), maxRetries: 1)
        struct Resp: Decodable {
            let code: String?
            let msg: String?
            let data: [[String]]?
        }
        let decoded = try JSONDecoder().decode(Resp.self, from: res.data)
        if let code = decoded.code, code != "0" {
            throw NetworkAdapterError.decodingFailed("OKX open-interest-history code=\(code) \(decoded.msg ?? "")")
        }
        return (decoded.data ?? []).prefix(1_440).compactMap { row in
            guard row.count >= 4,
                  let ms = Double(row[0]), ms.isFinite,
                  let oi = Double(row[1]), oi.isFinite, oi >= 0,
                  let oiCcy = Double(row[2]), oiCcy.isFinite, oiCcy >= 0,
                  let oiUsd = Double(row[3]), oiUsd.isFinite, oiUsd >= 0
            else { return nil }
            return OKXOpenInterestPoint(
                timestampEpochSeconds: ms / 1000.0,
                openInterestContracts: oi,
                openInterestCoin: oiCcy,
                openInterestUSD: oiUsd,
                period: period
            )
        }.sorted { $0.timestampEpochSeconds < $1.timestampEpochSeconds }
    }
}

/// Weekly disk-cached CFTC Commitments of Traders Socrata JSON adapter (`72hh-3qpy` Disaggregated
/// & `gpe5-46if` Traders in Financial Futures). Handles Socrata's string-encoded numbers and stamps
/// Friday 20:30 UTC publication time so historical replay has zero Tuesday-to-Friday lookahead bias.
public actor CFTCCOTAdapter {
    private let http: any HTTPTransport
    private let cacheURL: URL
    private var memoryCache: [String: [CFTCCOTRecord]] = [:]
    private var lastFetchedAt: Date?
    private var didLoadDiskCache: Bool = false

    public init(http: any HTTPTransport, cacheDirectory: URL? = nil) {
        self.http = http
        let dir = cacheDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheURL = dir.appendingPathComponent("confluence_cftc_cot_cache.json")
    }

    private func ensureDiskCacheLoaded() {
        guard !didLoadDiskCache else { return }
        didLoadDiskCache = true
        if let disk = Self.loadDiskCache(from: self.cacheURL) {
            self.memoryCache = disk.recordsByContract
            self.lastFetchedAt = disk.fetchedAt
        }
    }

    public func records(for contractCode: String, forceRefresh: Bool = false) async throws -> [CFTCCOTRecord] {
        ensureDiskCacheLoaded()
        let shouldRefresh: Bool
        if forceRefresh || memoryCache[contractCode] == nil {
            shouldRefresh = true
        } else if let fetched = lastFetchedAt {
            // Refresh at most once per 6 days (weekly Friday release) unless forced
            shouldRefresh = Date().timeIntervalSince(fetched) > 6 * 86_400
        } else {
            shouldRefresh = true
        }

        if shouldRefresh {
            try await refreshAllTrackedContracts()
        }
        return memoryCache[contractCode] ?? []
    }

    public func refreshAllTrackedContracts() async throws {
        let disaggCodes = ["088691"] // Gold COMEX
        let tffCodes = ["099741", "096742", "097741", "13874A", "209742", "133741"] // EUR, GBP, JPY, SPX, NDX, BTC

        async let disaggTask = fetchBatch(dataset: .disaggregatedFuturesOnly, contractCodes: disaggCodes)
        async let tffTask = fetchBatch(dataset: .tradersInFinancialFutures, contractCodes: tffCodes)

        ensureDiskCacheLoaded()
        var disagg: [CFTCCOTRecord] = []
        var tff: [CFTCCOTRecord] = []
        var firstError: Error? = nil
        do {
            disagg = try await disaggTask
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlErr as URLError where urlErr.code == .cancelled {
            throw urlErr
        } catch {
            firstError = error
        }
        do {
            tff = try await tffTask
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlErr as URLError where urlErr.code == .cancelled {
            throw urlErr
        } catch {
            if firstError == nil { firstError = error }
        }

        if disagg.isEmpty && tff.isEmpty {
            if let firstError { throw firstError }
            return
        }

        var grouped: [String: [CFTCCOTRecord]] = memoryCache
        for rec in (disagg + tff) {
            grouped[rec.contractCode, default: []].append(rec)
        }
        for (k, v) in grouped {
            var uniqueByDate: [TimeInterval: CFTCCOTRecord] = [:]
            for r in v { uniqueByDate[r.reportDateEpochSeconds] = r }
            grouped[k] = uniqueByDate.values.sorted { $0.reportDateEpochSeconds < $1.reportDateEpochSeconds }
        }

        self.memoryCache = grouped
        self.lastFetchedAt = Date()
        Self.saveDiskCache(DiskCache(fetchedAt: Date(), recordsByContract: grouped), to: cacheURL)
    }

    private func fetchBatch(dataset: CFTCDatasetKind, contractCodes: [String]) async throws -> [CFTCCOTRecord] {
        let quoted = contractCodes.map { "'\($0)'" }.joined(separator: ",")
        var comps = URLComponents(string: "https://publicreporting.cftc.gov/resource/\(dataset.rawValue).json")!
        comps.queryItems = [
            URLQueryItem(name: "$where", value: "cftc_contract_market_code in(\(quoted))"),
            URLQueryItem(name: "$order", value: "report_date_as_yyyy_mm_dd DESC"),
            URLQueryItem(name: "$limit", value: "\(contractCodes.count * 60)")
        ]
        guard let url = comps.url else { throw NetworkAdapterError.invalidURL("CFTC") }

        let res = try await http.send(URLRequest(url: url), maxRetries: 1)
        return try Self.parseSocrataJSON(data: res.data, dataset: dataset)
    }

    public static func parseSocrataJSON(data: Data, dataset: CFTCDatasetKind) throws -> [CFTCCOTRecord] {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkAdapterError.decodingFailed("CFTC Socrata JSON is not array")
        }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"

        var out: [CFTCCOTRecord] = []
        for row in rows {
            guard let code = row["cftc_contract_market_code"] as? String,
                  let dateRaw = row["report_date_as_yyyy_mm_dd"] as? String,
                  let date = df.date(from: String(dateRaw.prefix(10)))
            else { continue }

            let name = (row["market_and_exchange_names"] as? String) ?? code
            guard let oi = flexibleDouble(row["open_interest_all"]), oi.isFinite, oi > 0 else { continue }
            let nonReptLong = max(0.0, flexibleDouble(row["nonrept_positions_long_all"]) ?? 0)
            let nonReptShort = max(0.0, flexibleDouble(row["nonrept_positions_short_all"]) ?? 0)

            let instLong: Double
            let instShort: Double
            switch dataset {
            case .disaggregatedFuturesOnly:
                instLong = flexibleDouble(row["m_money_positions_long_all"]) ?? 0
                instShort = flexibleDouble(row["m_money_positions_short_all"]) ?? 0
            case .tradersInFinancialFutures:
                let amL = flexibleDouble(row["asset_mgr_positions_long"]) ?? flexibleDouble(row["asset_mgr_positions_long_all"]) ?? 0
                let amS = flexibleDouble(row["asset_mgr_positions_short"]) ?? flexibleDouble(row["asset_mgr_positions_short_all"]) ?? 0
                let lmL = flexibleDouble(row["lev_money_positions_long"]) ?? flexibleDouble(row["lev_money_positions_long_all"]) ?? 0
                let lmS = flexibleDouble(row["lev_money_positions_short"]) ?? flexibleDouble(row["lev_money_positions_short_all"]) ?? 0
                instLong = amL + lmL
                instShort = amS + lmS
            }

            let tuesdayEpoch = date.timeIntervalSince1970
            // Official CFTC publication is Friday 15:30 ET (~20:30 UTC), i.e., +3d 20.5h after Tuesday
            let fridayReleaseEpoch = tuesdayEpoch + (3 * 86_400) + (20.5 * 3_600)

            out.append(CFTCCOTRecord(
                contractCode: code,
                marketName: name,
                dataset: dataset,
                reportDateEpochSeconds: tuesdayEpoch,
                publishedAtEpochSeconds: fridayReleaseEpoch,
                openInterest: oi,
                institutionalLong: instLong,
                institutionalShort: instShort,
                nonReportableLong: nonReptLong,
                nonReportableShort: nonReptShort
            ))
        }
        return out
    }

    private static func flexibleDouble(_ any: Any?) -> Double? {
        guard let any else { return nil }
        if CFGetTypeID(any as AnyObject) == CFBooleanGetTypeID() { return nil }
        if let d = any as? Double { return d.isFinite ? d : nil }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String {
            let cleaned = s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "")
            guard let v = Double(cleaned), v.isFinite else { return nil }
            return v
        }
        return nil
    }

    private struct DiskCache: Codable {
        let fetchedAt: Date
        let recordsByContract: [String: [CFTCCOTRecord]]
    }

    private static func loadDiskCache(from url: URL) -> DiskCache? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DiskCache.self, from: data)
    }

    private static func saveDiskCache(_ cache: DiskCache, to url: URL) {
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
