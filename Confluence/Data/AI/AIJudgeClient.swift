import Foundation
import SignalEngine

public enum AIProviderOption: String, Codable, Sendable, CaseIterable, Identifiable {
    case gemini = "gemini"
    case deepseek = "deepseek"
    case openrouter = "openrouter"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .gemini: return "Google Gemini"
        case .deepseek: return "DeepSeek"
        case .openrouter: return "OpenRouter"
        }
    }

    public var shortLabel: String {
        switch self {
        case .gemini: return "Gemini"
        case .deepseek: return "DeepSeek"
        case .openrouter: return "OpenRouter"
        }
    }

    public var keychainKey: SecretKey {
        switch self {
        case .gemini: return .geminiAPIKey
        case .deepseek: return .deepseekAPIKey
        case .openrouter: return .openrouterAPIKey
        }
    }

    public var defaultModelID: String {
        switch self {
        case .gemini: return GeminiModelOption.hydrogen.rawValue
        case .deepseek: return "deepseek-flash"
        case .openrouter: return "google/gemma-3-27b-it:free"
        }
    }

    public var fallbackModels: [AIModelInfo] {
        switch self {
        case .gemini:
            return GeminiModelOption.allCases.map {
                AIModelInfo(id: $0.rawValue, displayName: $0.displayName, provider: .gemini, isFree: false)
            }
        case .deepseek:
            return [
                AIModelInfo(id: "deepseek-flash", displayName: "DeepSeek-V4.1-Flash (Fast · Default)", provider: .deepseek, isFree: false),
                AIModelInfo(id: "deepseek-v4-pro", displayName: "DeepSeek-V4-Pro", provider: .deepseek, isFree: false)
            ]
        case .openrouter:
            return [
                AIModelInfo(id: "google/gemma-3-27b-it:free", displayName: "Gemma 3 27B (Free)", provider: .openrouter, isFree: true),
                AIModelInfo(id: "meta-llama/llama-3.3-70b-instruct:free", displayName: "Llama 3.3 70B (Free)", provider: .openrouter, isFree: true),
                AIModelInfo(id: "deepseek/deepseek-r1:free", displayName: "DeepSeek R1 (Free)", provider: .openrouter, isFree: true)
            ]
        }
    }

    public var rateLimitNote: String? {
        switch self {
        case .openrouter:
            return "OpenRouter free models: 20 requests/min, 50/day (or 1,000/day with $10+ lifetime credits)."
        case .deepseek:
            return "DeepSeek-V4.1-Flash (deepseek-flash) is the lowest-cost default with thinking disabled for crisp JSON."
        case .gemini:
            return "API key is sent strictly via the x-goog-api-key header (never in URLs or logs)."
        }
    }
}

public struct AIModelInfo: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let displayName: String
    public let provider: AIProviderOption
    public let isFree: Bool
    public let contextWindow: Int?

    public init(
        id: String,
        displayName: String,
        provider: AIProviderOption,
        isFree: Bool = false,
        contextWindow: Int? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.provider = provider
        self.isFree = isFree
        self.contextWindow = contextWindow
    }
}

public enum AIProviderError: Error, LocalizedError, Sendable {
    case rateLimited(provider: String)
    case blankResponse(provider: String)

    public var errorDescription: String? {
        switch self {
        case .rateLimited(let provider):
            return "\(provider) rate limit reached (HTTP 429). Wait a moment or switch to another model/provider."
        case .blankResponse(let provider):
            return "\(provider) returned an empty response after retry."
        }
    }
}

/// Shared UTC-day AI call counter enforced atomically across ALL AI providers (Gemini, DeepSeek, OpenRouter).
public enum AIDailyUsageTracker {
    private static let lock = NSLock()

    private static func todayKey(prefix: String = "confluence.ai.calls") -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let comps = cal.dateComponents([.year, .month, .day], from: Date())
        let y = comps.year ?? 1970
        let m = comps.month ?? 1
        let d = comps.day ?? 1
        return String(format: "%@.%04d-%02d-%02d", prefix, y, m, d)
    }

    private static func resolveDefaults(suiteName: String?) -> UserDefaults {
        if let suiteName, let suite = UserDefaults(suiteName: suiteName) {
            return suite
        }
        return .standard
    }

    public static func currentCount(suiteName: String? = nil) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return resolveDefaults(suiteName: suiteName).integer(forKey: todayKey())
    }

    public static func increment(suiteName: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
        let defaults = resolveDefaults(suiteName: suiteName)
        let key = todayKey()
        defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
    }

    public static func resetToday(suiteName: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
        resolveDefaults(suiteName: suiteName).removeObject(forKey: todayKey())
    }
}

/// Unified optional second-opinion protocol implemented by Gemini, DeepSeek, and OpenRouter.
/// **Hard Invariant:** AI can NEVER override deterministic code risk limits, `crisis` suppression,
/// confluence gates, or numeric Entry / Stop loss / Target levels.
public protocol AIJudgeClient: Sendable {
    var provider: AIProviderOption { get }

    func judgeSignal(
        _ signal: TradeSignal,
        apiKey: String,
        dailyLimit: Int,
        modelID: String
    ) async throws -> ReflexJudgment

    func summarizeBreakingImpact(
        headline: String,
        affectedAssets: [String],
        apiKey: String,
        dailyLimit: Int,
        modelID: String
    ) async throws -> String

    func listModels(apiKey: String) async throws -> [AIModelInfo]
}

// MARK: - OpenAI-Compatible Client (DeepSeek & OpenRouter)

public actor OpenAICompatibleJudgeClient: AIJudgeClient {
    public nonisolated let provider: AIProviderOption
    private let baseURLString: String
    private let http: any HTTPTransport
    private let suiteName: String?

    public init(
        provider: AIProviderOption,
        http: any HTTPTransport,
        suiteName: String? = nil
    ) {
        self.provider = provider
        self.http = http
        self.suiteName = suiteName
        switch provider {
        case .deepseek:
            self.baseURLString = "https://api.deepseek.com"
        case .openrouter:
            self.baseURLString = "https://openrouter.ai/api/v1"
        case .gemini:
            self.baseURLString = "https://generativelanguage.googleapis.com/v1beta"
        }
    }

    public func listModels(apiKey: String) async throws -> [AIModelInfo] {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            throw NetworkAdapterError.missingAPIKey(provider.displayName)
        }
        guard let url = URL(string: "\(baseURLString)/models") else {
            throw NetworkAdapterError.invalidURL("\(baseURLString)/models")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(cleanKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if provider == .openrouter {
            req.setValue("https://github.com/Zayn9815/Confluence", forHTTPHeaderField: "HTTP-Referer")
            req.setValue("Confluence", forHTTPHeaderField: "X-Title")
        }

        let res = try await sendHandling429(req)
        return try Self.parseModelsJSON(data: res.data, provider: provider)
    }

    public static func parseModelsJSON(data: Data, provider: AIProviderOption) throws -> [AIModelInfo] {
        struct ModelsRoot: Decodable {
            struct Pricing: Decodable {
                let prompt: String?
                let completion: String?
            }
            struct Item: Decodable {
                let id: String
                let name: String?
                let context_window: Int?
                let context_length: Int?
                let pricing: Pricing?
            }
            let data: [Item]
        }
        let decoded = try JSONDecoder().decode(ModelsRoot.self, from: data)
        var models: [AIModelInfo] = decoded.data.map { item in
            let isZeroPrice = (item.pricing?.prompt == "0" && item.pricing?.completion == "0")
            let isFree = (provider == .openrouter) && (item.id.hasSuffix(":free") || isZeroPrice)
            let baseName = (item.name?.isEmpty == false) ? item.name! : item.id
            let label = isFree && !baseName.lowercased().contains("free") ? "\(baseName) (Free)" : baseName
            return AIModelInfo(
                id: item.id,
                displayName: label,
                provider: provider,
                isFree: isFree,
                contextWindow: item.context_window ?? item.context_length
            )
        }

        if provider == .deepseek {
            models.sort { a, b in
                let aDefault = (a.id == "deepseek-flash")
                let bDefault = (b.id == "deepseek-flash")
                if aDefault != bDefault { return aDefault }
                return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
            }
        } else if provider == .openrouter {
            models.sort { a, b in
                if a.isFree != b.isFree { return a.isFree }
                return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
            }
        }
        return models
    }

    public func judgeSignal(
        _ signal: TradeSignal,
        apiKey: String,
        dailyLimit: Int,
        modelID: String
    ) async throws -> ReflexJudgment {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            throw NetworkAdapterError.missingAPIKey(provider.displayName)
        }
        let used = AIDailyUsageTracker.currentCount(suiteName: suiteName)
        guard used < dailyLimit else {
            throw NetworkAdapterError.dailyLimitReached("AI (\(used)/\(dailyLimit))")
        }

        let compactSnapshot = SignalEngine.buildCompactReflexPrompt(for: signal)
        let prompt = """
        You are an institutional risk reviewer evaluating a deterministic trade setup snapshot.
        Never invent prices. Return ONLY a strict json object matching this exact example format:
        {"regime":"trending","direction":"long","setup_quality":2,"confidence":0.82,"risk_state":"safe","agree":true,"catalyst_bias":"neutral","invalidation_check":"One crisp invalidation sentence."}
        Allowed enums: regime in [trending, mean_reverting, high_vol, crisis]; direction in [long, short, neutral]; risk_state in [safe, near_limit, reduce]; catalyst_bias in [bullish, bearish, neutral, none].
        Snapshot: \(compactSnapshot)
        """

        let text = try await requestChatCompletion(
            prompt: prompt,
            apiKey: cleanKey,
            modelID: modelID,
            expectJSON: true,
            maxTokens: 1024
        )
        AIDailyUsageTracker.increment(suiteName: suiteName)

        let cleanedJSON = Self.extractJSONObjectString(from: text)
        guard let jsonData = cleanedJSON.data(using: .utf8) else {
            throw NetworkAdapterError.decodingFailed("\(provider.displayName) returned non-UTF8 text")
        }
        let judgment = try JSONDecoder().decode(ReflexJudgment.self, from: jsonData)
        guard judgment.isSchemaValid() else {
            throw NetworkAdapterError.decodingFailed("\(provider.displayName) judgment failed bounds validation")
        }
        return judgment
    }

    public func summarizeBreakingImpact(
        headline: String,
        affectedAssets: [String],
        apiKey: String,
        dailyLimit: Int,
        modelID: String
    ) async throws -> String {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            throw NetworkAdapterError.missingAPIKey(provider.displayName)
        }
        let used = AIDailyUsageTracker.currentCount(suiteName: suiteName)
        guard used < dailyLimit else {
            throw NetworkAdapterError.dailyLimitReached("AI (\(used)/\(dailyLimit))")
        }

        let prompt = "In 1 crisp sentence (<=22 words), state immediate market impact and whipsaw risk for \(affectedAssets.joined(separator: ", ")): \"\(headline)\""
        let text = try await requestChatCompletion(
            prompt: prompt,
            apiKey: cleanKey,
            modelID: modelID,
            expectJSON: false,
            maxTokens: 256
        )
        AIDailyUsageTracker.increment(suiteName: suiteName)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func requestChatCompletion(
        prompt: String,
        apiKey: String,
        modelID: String,
        expectJSON: Bool,
        maxTokens: Int
    ) async throws -> String {
        guard let url = URL(string: "\(baseURLString)/chat/completions") else {
            throw NetworkAdapterError.invalidURL("\(baseURLString)/chat/completions")
        }

        func buildRequest(relaxed: Bool) throws -> URLRequest {
            var body: [String: Any] = [
                "model": modelID,
                "messages": [
                    ["role": "user", "content": prompt]
                ],
                "max_tokens": maxTokens,
                "temperature": 0.1
            ]
            if !relaxed {
                if provider == .deepseek {
                    // Verified api-docs.deepseek.com: disable default thinking mode via top-level parameter
                    body["thinking"] = ["type": "disabled"]
                }
                if expectJSON {
                    body["response_format"] = ["type": "json_object"]
                }
            }

            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            if provider == .openrouter {
                req.setValue("https://github.com/Zayn9815/Confluence", forHTTPHeaderField: "HTTP-Referer")
                req.setValue("Confluence", forHTTPHeaderField: "X-Title")
            }
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            return req
        }

        // Attempt 1 (full structured params); on HTTP 400 retry once with relaxed params
        let firstResponse: HTTPResponseData
        do {
            firstResponse = try await sendHandling429(try buildRequest(relaxed: false))
        } catch NetworkAdapterError.httpStatus(let code, _) where code == 400 {
            firstResponse = try await sendHandling429(try buildRequest(relaxed: true))
        }

        if let text = Self.extractOpenAIContent(from: firstResponse.data),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }

        // Verified DeepSeek edge case: JSON mode can occasionally return blank/whitespace-only content -> retry once
        let retryResponse = try await sendHandling429(try buildRequest(relaxed: true))
        if let retryText = Self.extractOpenAIContent(from: retryResponse.data),
           !retryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return retryText
        }
        throw AIProviderError.blankResponse(provider: provider.displayName)
    }

    private func sendHandling429(_ req: URLRequest) async throws -> HTTPResponseData {
        do {
            return try await http.send(req, maxRetries: 1)
        } catch NetworkAdapterError.rateLimited {
            throw AIProviderError.rateLimited(provider: provider.displayName)
        } catch NetworkAdapterError.httpStatus(let code, _) where code == 429 {
            throw AIProviderError.rateLimited(provider: provider.displayName)
        }
    }

    public static func extractOpenAIContent(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String
        else { return nil }
        return content
    }

    public static func extractJSONObjectString(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") {
            return String(trimmed[start...end])
        }
        return trimmed
    }
}
