import Foundation
import XCTest
@testable import Confluence
import SignalEngine

private actor MockAIHTTPTransport: HTTPTransport {
    private var handlers: [@Sendable (URLRequest) throws -> HTTPResponseData]
    private(set) var recordedRequests: [URLRequest] = []

    init(handlers: [@Sendable (URLRequest) throws -> HTTPResponseData]) {
        self.handlers = handlers
    }

    func send(_ request: URLRequest, maxRetries: Int) async throws -> HTTPResponseData {
        recordedRequests.append(request)
        guard !handlers.isEmpty else {
            throw NetworkAdapterError.httpStatus(500, "No mock response left")
        }
        let next = handlers.removeFirst()
        return try next(request)
    }

    func estimatedClockSkewSeconds() async -> TimeInterval { 0 }
}

final class V15M5AIProvidersTests: XCTestCase {
    private func sampleSignal() -> TradeSignal {
        TradeSignal(
            id: "sig-ai-1",
            fingerprint: "fp-ai-1",
            symbol: "BTC/USDT",
            displayName: "Bitcoin",
            marketClass: .crypto,
            timeframe: .h1,
            htfTimeframe: .h4,
            category: .strongSignal,
            direction: .long,
            tier: .highConviction,
            confidencePercent: 81,
            regime: .trending,
            riskState: .safe,
            killzone: .newYork,
            htfBias: .long,
            generatedAtEpochSeconds: 1_776_175_200,
            barCloseEpochSeconds: 1_776_175_200,
            levels: TradeLevels(
                entryLow: 59_900,
                entryHigh: 60_100,
                entryMid: 60_000,
                stopLoss: 59_000,
                tp1: 62_000,
                tp2: 64_000,
                riskPercent: 1.67,
                reward1Percent: 3.33,
                reward2Percent: 6.67,
                riskRewardRatio: 2.0,
                tp2RiskRewardRatio: 4.0,
                isTP2Enabled: true
            ),
            alignedStrategies: [],
            rejectionReasons: [],
            psychologyReport: PsychologyReport(
                headline: "Clean sweep",
                whatHappened: "Sweep held",
                retailCrowdDirection: .short,
                proDirection: .long,
                retailTrapRisk: .low,
                provenanceBadge: "Price Action Only",
                trappedLevelsSummary: "None",
                positioningSummary: "Neutral"
            ),
            dataProvider: "Binance Vision"
        )
    }

    func testGeminiListModelsPaginationHeaderAuthAndFilter() async throws {
        let page1 = """
        {
          "models": [
            {"name":"models/gemini-4-hydrogen","displayName":"Gemini 4 Hydrogen","supportedGenerationMethods":["generateContent"]},
            {"name":"models/embedding-001","displayName":"Embedding","supportedGenerationMethods":["embedContent"]}
          ],
          "nextPageToken": "tok2"
        }
        """
        let page2 = """
        {
          "models": [
            {"name":"models/gemini-4-pro","displayName":"Gemini 4 Pro","supportedGenerationMethods":["generateContent","countTokens"]}
          ]
        }
        """
        let transport = MockAIHTTPTransport(handlers: [
            { _ in HTTPResponseData(data: Data(page1.utf8), statusCode: 200, headers: [:], serverDate: Date(), latencyMs: 12) },
            { _ in HTTPResponseData(data: Data(page2.utf8), statusCode: 200, headers: [:], serverDate: Date(), latencyMs: 12) }
        ])

        let client = GeminiJudgeClient(http: transport)
        let models = try await client.listModels(apiKey: "AIzaTestSecretKey12345678901234567890")
        XCTAssertEqual(models.map(\.id), ["gemini-4-hydrogen", "gemini-4-pro"])

        let reqs = await transport.recordedRequests
        XCTAssertEqual(reqs.count, 2)
        // Key MUST ONLY be in x-goog-api-key header, NEVER in URL query string
        XCTAssertEqual(reqs[0].value(forHTTPHeaderField: "x-goog-api-key"), "AIzaTestSecretKey12345678901234567890")
        XCTAssertFalse(reqs[0].url?.absoluteString.contains("AIza") ?? true)
        XCTAssertTrue(reqs[1].url?.absoluteString.contains("pageToken=tok2") ?? false)
    }

    func testDeepSeekThinkingDisabled400RetryAndBlankContentRetry() async throws {
        let suiteName = "confluence.test.ai.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        let validJudgment = """
        {"choices":[{"message":{"content":"{\\"regime\\":\\"trending\\",\\"direction\\":\\"long\\",\\"setup_quality\\":3,\\"confidence\\":0.86,\\"risk_state\\":\\"safe\\",\\"agree\\":true,\\"catalyst_bias\\":\\"bullish\\",\\"invalidation_check\\":\\"Invalid below 59000.\\"}"}}]}
        """
        let blankResponse = #"{"choices":[{"message":{"content":"   "}}]}"#

        // 1st call returns HTTP 400 (tests relaxed retry), 2nd returns blank content (tests DeepSeek blank retry), 3rd succeeds!
        let transport = MockAIHTTPTransport(handlers: [
            { _ in throw NetworkAdapterError.httpStatus(400, "Unsupported param") },
            { _ in HTTPResponseData(data: Data(blankResponse.utf8), statusCode: 200, headers: [:], serverDate: Date(), latencyMs: 10) },
            { _ in HTTPResponseData(data: Data(validJudgment.utf8), statusCode: 200, headers: [:], serverDate: Date(), latencyMs: 10) }
        ])

        let client = OpenAICompatibleJudgeClient(provider: .deepseek, http: transport, suiteName: suiteName)
        let res = try await client.judgeSignal(sampleSignal(), apiKey: "sk-deepseek-test-1234567890abcdef", dailyLimit: 5, modelID: "deepseek-flash")
        XCTAssertTrue(res.agree)
        XCTAssertEqual(res.setupQuality, 3)

        let reqs = await transport.recordedRequests
        XCTAssertEqual(reqs.count, 3)
        // First request must include Bearer header and top-level thinking disabled + response_format json_object
        XCTAssertEqual(reqs[0].value(forHTTPHeaderField: "Authorization"), "Bearer sk-deepseek-test-1234567890abcdef")
        let firstBody = String(data: reqs[0].httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(firstBody.contains("\"disabled\""))
        XCTAssertTrue(firstBody.contains("\"json_object\""))
        // Shared daily cap incremented by 1
        XCTAssertEqual(AIDailyUsageTracker.currentCount(suiteName: suiteName), 1)
    }

    func testOpenRouterFreeTagging429FriendlyErrorAndSharedDailyCap() async throws {
        let suiteName = "confluence.test.or.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        let modelsJSON = """
        {
          "data": [
            {"id":"openai/gpt-4o","name":"GPT-4o","pricing":{"prompt":"0.000005","completion":"0.000015"}},
            {"id":"google/gemma-3-27b-it:free","name":"Gemma 3 27B","pricing":{"prompt":"0","completion":"0"}}
          ]
        }
        """
        let transport = MockAIHTTPTransport(handlers: [
            { _ in HTTPResponseData(data: Data(modelsJSON.utf8), statusCode: 200, headers: [:], serverDate: Date(), latencyMs: 8) },
            { _ in throw NetworkAdapterError.httpStatus(429, "Too Many Requests") }
        ])

        let client = OpenAICompatibleJudgeClient(provider: .openrouter, http: transport, suiteName: suiteName)
        let models = try await client.listModels(apiKey: "sk-or-v1-test1234567890abcdef")
        XCTAssertEqual(models.first?.id, "google/gemma-3-27b-it:free")
        XCTAssertEqual(models.first?.isFree, true)
        XCTAssertEqual(models.last?.isFree, false)

        // 429 maps to friendly AIProviderError.rateLimited
        do {
            _ = try await client.summarizeBreakingImpact(
                headline: "CPI beats expectations",
                affectedAssets: ["XAU/USD"],
                apiKey: "sk-or-v1-test1234567890abcdef",
                dailyLimit: 5,
                modelID: "google/gemma-3-27b-it:free"
            )
            XCTFail("Expected rateLimited error")
        } catch let err as AIProviderError {
            XCTAssertTrue(err.localizedDescription.contains("429"))
        }

        // Shared daily cap blocks when used >= limit across providers
        AIDailyUsageTracker.increment(suiteName: suiteName)
        let gemini = GeminiJudgeClient(http: transport, suiteName: suiteName)
        do {
            _ = try await gemini.judgeSignal(sampleSignal(), apiKey: "AIzaTest12345678901234567890", dailyLimit: 1)
            XCTFail("Expected dailyLimitReached")
        } catch NetworkAdapterError.dailyLimitReached {
            // Expected
        }
    }

    func testAISettingsMigrationFromLegacyGeminiModel() throws {
        let legacyJSON = """
        {
          "geminiEnabled": true,
          "geminiModel": "gemini-4-neon",
          "geminiDailyCallLimit": 40
        }
        """
        let decoded = try JSONDecoder().decode(PersistedSettingsPayload.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(decoded.aiProvider, .gemini)
        XCTAssertEqual(decoded.aiModelID, "gemini-4-neon")
        XCTAssertEqual(decoded.geminiDailyCallLimit, 40)
    }
}
