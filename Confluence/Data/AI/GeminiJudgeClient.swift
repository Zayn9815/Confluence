import Foundation
import SignalEngine

/// Optional Gemini second-opinion & breaking-news catalyst judge (`AIJudgeClient`).
/// - Sends API key ONLY via `x-goog-api-key` header (never query strings or logs).
/// - Uses `thinkingLevel: "LOW"` and `maxOutputTokens: 2048` (with 1 relaxed retry on HTTP 400 for non-thinking models).
/// - Enforces strict JSON schema and shared user-configured daily call limit across all AI providers.
/// - Never overrides deterministic code risk/confluence gates.
public enum GeminiModelOption: String, Codable, Sendable, CaseIterable, Identifiable {
    case hydrogen = "gemini-4-hydrogen"
    case neon = "gemini-4-neon"
    case carbon = "gemini-4-carbon"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .hydrogen: return "Gemini 4 Hydrogen (Fast · Default)"
        case .neon: return "Gemini 4 Neon (Balanced)"
        case .carbon: return "Gemini 4 Carbon (Deep)"
        }
    }

    public var shortLabel: String {
        switch self {
        case .hydrogen: return "Gemini 4 Hydrogen"
        case .neon: return "Gemini 4 Neon"
        case .carbon: return "Gemini 4 Carbon"
        }
    }
}

public actor GeminiJudgeClient: AIJudgeClient {
    public nonisolated let provider: AIProviderOption = .gemini
    public static let modelID = "gemini-4-hydrogen"

    private let http: any HTTPTransport
    private let suiteName: String?

    public init(http: any HTTPTransport, suiteName: String? = nil) {
        self.http = http
        self.suiteName = suiteName
    }

    public func dailyUsageCount() -> Int {
        AIDailyUsageTracker.currentCount(suiteName: suiteName)
    }

    /// Verified `aistudio.google.com/api-reference/models/list-models`:
    /// `GET https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000` with `x-goog-api-key` header,
    /// filtering `supportedGenerationMethods.contains("generateContent")`, stripping `"models/"` prefix,
    /// and following `nextPageToken`.
    public func listModels(apiKey: String) async throws -> [AIModelInfo] {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            throw NetworkAdapterError.missingAPIKey("Gemini")
        }

        struct ModelsResponse: Decodable {
            struct ModelItem: Decodable {
                let name: String
                let displayName: String?
                let supportedGenerationMethods: [String]?
            }
            let models: [ModelItem]?
            let nextPageToken: String?
        }

        var collected: [AIModelInfo] = []
        var pageToken: String? = nil
        var pagesFetched = 0

        repeat {
            var comps = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models")!
            var items = [URLQueryItem(name: "pageSize", value: "1000")]
            if let token = pageToken, !token.isEmpty {
                items.append(URLQueryItem(name: "pageToken", value: token))
            }
            comps.queryItems = items
            guard let url = comps.url else {
                throw NetworkAdapterError.invalidURL("Gemini models.list")
            }

            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue(cleanKey, forHTTPHeaderField: "x-goog-api-key")

            let res = try await sendHandling429(req)
            let decoded = try JSONDecoder().decode(ModelsResponse.self, from: res.data)

            for item in decoded.models ?? [] {
                let methods = item.supportedGenerationMethods ?? []
                guard methods.contains("generateContent") else { continue }
                let cleanID = item.name.hasPrefix("models/")
                    ? String(item.name.dropFirst("models/".count))
                    : item.name
                guard !cleanID.isEmpty else { continue }
                let label = (item.displayName?.isEmpty == false) ? item.displayName! : cleanID
                collected.append(AIModelInfo(
                    id: cleanID,
                    displayName: label,
                    provider: .gemini,
                    isFree: false
                ))
            }

            pageToken = decoded.nextPageToken
            pagesFetched += 1
        } while (pageToken?.isEmpty == false) && pagesFetched < 5

        return collected
    }

    public func judgeSignal(
        _ signal: TradeSignal,
        apiKey: String,
        dailyLimit: Int,
        modelID: String = GeminiJudgeClient.modelID
    ) async throws -> ReflexJudgment {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            throw NetworkAdapterError.missingAPIKey("Gemini")
        }
        let used = AIDailyUsageTracker.currentCount(suiteName: suiteName)
        guard used < dailyLimit else {
            throw NetworkAdapterError.dailyLimitReached("AI (\(used)/\(dailyLimit))")
        }

        let compactSnapshot = SignalEngine.buildCompactReflexPrompt(for: signal)
        let prompt = """
        You are an institutional risk reviewer evaluating a deterministic trade setup snapshot.
        Never invent prices. Return ONLY strict JSON matching the schema with a concise 1-sentence bear/invalidation check.
        Snapshot: \(compactSnapshot)
        """

        let schema: [String: Any] = [
            "type": "OBJECT",
            "required": ["regime", "direction", "setup_quality", "confidence", "risk_state", "agree", "catalyst_bias", "invalidation_check"],
            "properties": [
                "regime": ["type": "STRING", "enum": ["trending", "mean_reverting", "high_vol", "crisis"]],
                "direction": ["type": "STRING", "enum": ["long", "short", "neutral"]],
                "setup_quality": ["type": "INTEGER"],
                "confidence": ["type": "NUMBER"],
                "risk_state": ["type": "STRING", "enum": ["safe", "near_limit", "reduce"]],
                "agree": ["type": "BOOLEAN"],
                "catalyst_bias": ["type": "STRING", "enum": ["bullish", "bearish", "neutral", "none"]],
                "invalidation_check": ["type": "STRING"]
            ]
        ]

        func makeRequest(includeThinking: Bool) throws -> URLRequest {
            var genConfig: [String: Any] = [
                "temperature": 0.1,
                "maxOutputTokens": 2048,
                "responseMimeType": "application/json",
                "responseJsonSchema": schema
            ]
            if includeThinking {
                genConfig["thinkingConfig"] = ["thinkingLevel": "LOW"]
            }
            let body: [String: Any] = [
                "contents": [
                    ["role": "user", "parts": [["text": prompt]]]
                ],
                "generationConfig": genConfig
            ]
            let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelID):generateContent")!
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(cleanKey, forHTTPHeaderField: "x-goog-api-key")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            return req
        }

        let res: HTTPResponseData
        do {
            res = try await sendHandling429(try makeRequest(includeThinking: true))
        } catch NetworkAdapterError.httpStatus(let code, _) where code == 400 {
            res = try await sendHandling429(try makeRequest(includeThinking: false))
        }
        AIDailyUsageTracker.increment(suiteName: suiteName)

        let text = try extractCandidateText(from: res.data)
        let cleaned = OpenAICompatibleJudgeClient.extractJSONObjectString(from: text)
        guard let jsonData = cleaned.data(using: .utf8) else {
            throw NetworkAdapterError.decodingFailed("Gemini returned non-UTF8 text")
        }
        return try JSONDecoder().decode(ReflexJudgment.self, from: jsonData)
    }

    public func summarizeBreakingImpact(
        headline: String,
        affectedAssets: [String],
        apiKey: String,
        dailyLimit: Int,
        modelID: String = GeminiJudgeClient.modelID
    ) async throws -> String {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else { throw NetworkAdapterError.missingAPIKey("Gemini") }
        let used = AIDailyUsageTracker.currentCount(suiteName: suiteName)
        guard used < dailyLimit else { throw NetworkAdapterError.dailyLimitReached("AI (\(used)/\(dailyLimit))") }

        let prompt = "In 1 crisp sentence (<=22 words), state immediate market impact and whipsaw risk for \(affectedAssets.joined(separator: ", ")): \"\(headline)\""

        func makeRequest(includeThinking: Bool) throws -> URLRequest {
            var genConfig: [String: Any] = [
                "temperature": 0.1,
                "maxOutputTokens": 1024
            ]
            if includeThinking {
                genConfig["thinkingConfig"] = ["thinkingLevel": "LOW"]
            }
            let body: [String: Any] = [
                "contents": [["role": "user", "parts": [["text": prompt]]]],
                "generationConfig": genConfig
            ]
            let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelID):generateContent")!
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(cleanKey, forHTTPHeaderField: "x-goog-api-key")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            return req
        }

        let res: HTTPResponseData
        do {
            res = try await sendHandling429(try makeRequest(includeThinking: true))
        } catch NetworkAdapterError.httpStatus(let code, _) where code == 400 {
            res = try await sendHandling429(try makeRequest(includeThinking: false))
        }
        AIDailyUsageTracker.increment(suiteName: suiteName)
        return try extractCandidateText(from: res.data).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sendHandling429(_ req: URLRequest) async throws -> HTTPResponseData {
        do {
            return try await http.send(req, maxRetries: 1)
        } catch NetworkAdapterError.rateLimited {
            throw AIProviderError.rateLimited(provider: "Google Gemini")
        } catch NetworkAdapterError.httpStatus(let code, _) where code == 429 {
            throw AIProviderError.rateLimited(provider: "Google Gemini")
        }
    }

    private func extractCandidateText(from data: Data) throws -> String {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = root["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]]
        else {
            throw NetworkAdapterError.decodingFailed("Gemini candidate content missing")
        }
        for part in parts {
            if let isThought = part["thought"] as? Bool, isThought { continue }
            if let text = part["text"] as? String, !text.isEmpty {
                return text
            }
        }
        throw NetworkAdapterError.decodingFailed("Gemini text part empty")
    }
}
