import Foundation

public struct HTTPResponseData: Sendable {
    public let data: Data
    public let statusCode: Int
    public let headers: [String: String]
    public let serverDate: Date?
    public let latencyMs: Double

    public init(data: Data, statusCode: Int, headers: [String: String], serverDate: Date?, latencyMs: Double) {
        self.data = data
        self.statusCode = statusCode
        self.headers = headers
        self.serverDate = serverDate
        self.latencyMs = latencyMs
    }
}

public enum NetworkAdapterError: Error, LocalizedError, Sendable {
    case invalidURL(String)
    case httpStatus(Int, String)
    case rateLimited(retryAfterSeconds: Double?)
    case decodingFailed(String)
    case htmlRateLimitPage(String)
    case missingAPIKey(String)
    case dailyLimitReached(String)
    case allProvidersFailed([String])

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url): return "Invalid URL: \(url)"
        case .httpStatus(let code, let msg): return "HTTP \(code): \(msg)"
        case .rateLimited(let after): return "Rate limited (retry after \(Int(after ?? 60))s)"
        case .decodingFailed(let detail): return "Decode failed: \(detail)"
        case .htmlRateLimitPage(let host): return "\(host) returned HTML rate-limit page"
        case .missingAPIKey(let name): return "Missing optional API key for \(name)"
        case .dailyLimitReached(let name): return "Daily request budget reached for \(name)"
        case .allProvidersFailed(let errs): return "All feeds failed: \(errs.joined(separator: " | "))"
        }
    }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest, maxRetries: Int) async throws -> HTTPResponseData
    func estimatedClockSkewSeconds() async -> TimeInterval
}

public actor URLSessionHTTPClient: HTTPTransport {
    private let session: URLSession
    private var latestClockSkewSeconds: TimeInterval = 0.0

    public init(timeoutSeconds: TimeInterval = 15.0) {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeoutSeconds
        cfg.timeoutIntervalForResource = timeoutSeconds * 1.5
        cfg.waitsForConnectivity = false
        self.session = URLSession(configuration: cfg)
    }

    public func estimatedClockSkewSeconds() async -> TimeInterval {
        latestClockSkewSeconds
    }

    public func send(_ request: URLRequest, maxRetries: Int = 2) async throws -> HTTPResponseData {
        var attempt = 0
        var lastError: Error = NetworkAdapterError.httpStatus(0, "No attempt executed")

        while attempt <= maxRetries {
            let start = Date()
            do {
                let (data, response) = try await session.data(for: request)
                let latencyMs = Date().timeIntervalSince(start) * 1000.0
                guard let http = response as? HTTPURLResponse else {
                    throw NetworkAdapterError.httpStatus(0, "Non-HTTP response")
                }

                var lowerHeaders: [String: String] = [:]
                for (k, v) in http.allHeaderFields {
                    lowerHeaders["\(k)".lowercased()] = "\(v)"
                }

                let serverDate = lowerHeaders["date"].flatMap(Self.parseHTTPDate)
                if let sDate = serverDate {
                    latestClockSkewSeconds = sDate.timeIntervalSince(Date())
                }

                if http.statusCode == 429 || http.statusCode == 503 {
                    let retryAfter = lowerHeaders["retry-after"].flatMap(Double.init)
                    if attempt < maxRetries {
                        let backoff = min(retryAfter ?? pow(2.0, Double(attempt)), 8.0)
                        try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                        attempt += 1
                        continue
                    }
                    throw NetworkAdapterError.rateLimited(retryAfterSeconds: retryAfter)
                }

                if !(200...299).contains(http.statusCode) {
                    let snippet = String(data: data.prefix(160), encoding: .utf8) ?? ""
                    throw NetworkAdapterError.httpStatus(http.statusCode, snippet)
                }

                return HTTPResponseData(
                    data: data,
                    statusCode: http.statusCode,
                    headers: lowerHeaders,
                    serverDate: serverDate,
                    latencyMs: latencyMs
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch let urlErr as URLError where urlErr.code == .cancelled {
                throw urlErr
            } catch let netErr as NetworkAdapterError {
                if case .httpStatus(let code, _) = netErr, (400..<500).contains(code), code != 408, code != 429 {
                    throw netErr
                }
                lastError = netErr
                if attempt < maxRetries {
                    let backoff = min(pow(2.0, Double(attempt)) * 0.6, 5.0)
                    try await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                    attempt += 1
                    continue
                }
                throw lastError
            } catch {
                lastError = error
                if attempt < maxRetries {
                    let backoff = min(pow(2.0, Double(attempt)) * 0.6, 5.0)
                    try await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                    attempt += 1
                    continue
                }
                throw lastError
            }
        }
        throw lastError
    }

    private static func parseHTTPDate(_ header: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: header)
    }
}

/// Persistent per-minute and per-UTC-day token bucket pacer (e.g., Twelve Data 7/min & 760/day).
public actor ProviderRatePacer {
    private let providerKey: String
    private let maxPerMinute: Int
    private let maxPerUTCDay: Int?
    private var minuteTimestamps: [Date] = []

    public init(providerKey: String, maxPerMinute: Int, maxPerUTCDay: Int? = nil) {
        self.providerKey = providerKey
        self.maxPerMinute = maxPerMinute
        self.maxPerUTCDay = maxPerUTCDay
    }

    public func acquireSlot() async throws {
        while true {
            let now = Date()
            if let dailyLimit = maxPerUTCDay {
                let count = currentDailyCount(for: now)
                if count >= dailyLimit {
                    throw NetworkAdapterError.dailyLimitReached(providerKey)
                }
            }

            minuteTimestamps.removeAll { now.timeIntervalSince($0) >= 60.0 }
            if minuteTimestamps.count >= maxPerMinute, let oldest = minuteTimestamps.first {
                let waitSec = max(0.2, 60.5 - now.timeIntervalSince(oldest))
                if waitSec > 10.0 {
                    throw NetworkAdapterError.rateLimited(retryAfterSeconds: waitSec)
                }
                try await Task.sleep(nanoseconds: UInt64(waitSec * 1_000_000_000))
                continue
            }

            minuteTimestamps.append(now)
            if maxPerUTCDay != nil {
                incrementDailyCount(for: now)
            }
            return
        }
    }

    public func dailyUsageCount() -> Int {
        currentDailyCount(for: Date())
    }

    private func dayBucketKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return "confluence.pacer.\(providerKey).\(formatter.string(from: date))"
    }

    private func currentDailyCount(for date: Date) -> Int {
        UserDefaults.standard.integer(forKey: dayBucketKey(for: date))
    }

    private func incrementDailyCount(for date: Date) {
        let key = dayBucketKey(for: date)
        let next = UserDefaults.standard.integer(forKey: key) + 1
        UserDefaults.standard.set(next, forKey: key)
    }
}
