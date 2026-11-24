import Foundation
import SignalEngine

/// Optional Gemini 4 Hydrogen (`gemini-4-hydrogen`) second-opinion & breaking-news catalyst judge.
/// - Sends API key ONLY via `x-goog-api-key` header (never query strings or logs).
/// - Uses `thinkingLevel: "LOW"` and `maxOutputTokens: 2048` (thought tokens count toward maxOutputTokens).
/// - Enforces strict JSON schema and user-configured daily call limit persisted locally.
/// - Never overrides deterministic code risk/confluence gates.
public actor GeminiJudgeClient {
    public static let modelID = "gemini-4-hydrogen"
    private let http: any HTTPTransport

    public init(http: any HTTPTransport) {
        self.http = http
    }

    public func dailyUsageCount() -> Int {
        UserDefaults.standard.integer(forKey: todayUsageKey())
    }

    public func judgeSignal(
        _ signal: TradeSignal,
        apiKey: String,
        dailyLimit: Int
    ) async throws -> ReflexJudgment {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            throw NetworkAdapterError.missingAPIKey("Gemini 4 Hydrogen")
        }
        let used = dailyUsageCount()
        guard used < dailyLimit else {
            throw NetworkAdapterError.dailyLimitReached("Gemini 4 Hydrogen (\(used)/\(dailyLimit))")
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

        let body: [String: Any] = [
            "contents": [
                ["role": "user", "parts": [["text": prompt]]]
            ],
            "generationConfig": [
                "temperature": 0.1,
                "maxOutputTokens": 2048,
                "responseMimeType": "application/json",
                "responseJsonSchema": schema,
                "thinkingConfig": [
                    "thinkingLevel": "LOW"
                ]
            ]
        ]

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(Self.modelID):generateContent")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(cleanKey, forHTTPHeaderField: "x-goog-api-key")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let res = try await http.send(req, maxRetries: 1)
        incrementDailyUsage()

        let text = try extractCandidateText(from: res.data)
        guard let jsonData = text.data(using: .utf8) else {
            throw NetworkAdapterError.decodingFailed("Gemini returned non-UTF8 text")
        }
        return try JSONDecoder().decode(ReflexJudgment.self, from: jsonData)
    }

    public func summarizeBreakingImpact(
        headline: String,
        affectedAssets: [String],
        apiKey: String,
        dailyLimit: Int
    ) async throws -> String {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else { throw NetworkAdapterError.missingAPIKey("Gemini 4 Hydrogen") }
        guard dailyUsageCount() < dailyLimit else { throw NetworkAdapterError.dailyLimitReached("Gemini 4 Hydrogen") }

        let prompt = "In 1 crisp sentence (<=22 words), state immediate market impact and whipsaw risk for \(affectedAssets.joined(separator: ", ")): \"\(headline)\""
        let body: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": prompt]]]],
            "generationConfig": [
                "temperature": 0.1,
                "maxOutputTokens": 1024,
                "thinkingConfig": ["thinkingLevel": "LOW"]
            ]
        ]
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(Self.modelID):generateContent")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(cleanKey, forHTTPHeaderField: "x-goog-api-key")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let res = try await http.send(req, maxRetries: 1)
        incrementDailyUsage()
        return try extractCandidateText(from: res.data).trimmingCharacters(in: .whitespacesAndNewlines)
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
            // Skip any thought summary part if returned
            if let isThought = part["thought"] as? Bool, isThought { continue }
            if let text = part["text"] as? String, !text.isEmpty {
                return text
            }
        }
        throw NetworkAdapterError.decodingFailed("Gemini text part empty")
    }

    private func todayUsageKey() -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"
        return "confluence.gemini.calls.\(df.string(from: Date()))"
    }

    private func incrementDailyUsage() {
        let key = todayUsageKey()
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: key) + 1, forKey: key)
    }
}
