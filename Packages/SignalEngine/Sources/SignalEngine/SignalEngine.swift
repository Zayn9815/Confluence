import Foundation

public struct EngineAnalysisOutput: Codable, Sendable, Equatable {
    public let signal: TradeSignal?
    public let hygieneReport: HygieneReport
    public let regimeAssessment: RegimeAssessment
    public let activeTraps: [BehavioralTrap]
    public let preNewsShield: PreNewsShieldStatus?
    public let macroImpulse: MacroClusterImpulse?

    public init(
        signal: TradeSignal?,
        hygieneReport: HygieneReport,
        regimeAssessment: RegimeAssessment,
        activeTraps: [BehavioralTrap],
        preNewsShield: PreNewsShieldStatus?,
        macroImpulse: MacroClusterImpulse?
    ) {
        self.signal = signal
        self.hygieneReport = hygieneReport
        self.regimeAssessment = regimeAssessment
        self.activeTraps = activeTraps
        self.preNewsShield = preNewsShield
        self.macroImpulse = macroImpulse
    }
}

public enum SignalEngine {
    /// Complete end-to-end deterministic analysis for a single asset.
    /// Sanitizes raw candles (dropping forming bars, enforcing OTC nil volume, clock-skew & staleness guards),
    /// computes HTF bias, ICT/SMC, Candlestick, Trend/Momentum, Behavioral Trap Lifecycle, Positioning,
    /// Pre-News Shield, Macro Surprise Impulse, Calibrated Confidence %, and exact numeric levels.
    public static func analyze(
        asset: AssetDescriptor,
        rawEntryCandles: [Candle],
        rawHTFCandles: [Candle],
        timeframe: Timeframe,
        htfTimeframe: Timeframe = .h4,
        okxDerivatives: OKXDerivativesSnapshot? = nil,
        cftcCOTRecords: [CFTCCOTRecord] = [],
        calendarEvents: [EconomicEvent] = [],
        breakingNews: [BreakingNewsItem] = [],
        fearGreed: FearGreedSnapshot? = nil,
        config: EngineConfig = EngineConfig(),
        dataProvider: String,
        serverNowEpochSeconds: TimeInterval,
        clockSkewSeconds: TimeInterval = 0.0
    ) -> EngineAnalysisOutput {
        let entrySeries = CandleHygieneEngine.sanitize(
            rawCandles: rawEntryCandles,
            symbol: asset.symbol,
            marketClass: asset.marketClass,
            timeframe: timeframe,
            providerName: dataProvider,
            serverNowEpochSeconds: serverNowEpochSeconds,
            clockSkewSeconds: clockSkewSeconds,
            asset: asset
        )

        let htfSeries = CandleHygieneEngine.sanitize(
            rawCandles: rawHTFCandles,
            symbol: asset.symbol,
            marketClass: asset.marketClass,
            timeframe: htfTimeframe,
            providerName: dataProvider,
            serverNowEpochSeconds: serverNowEpochSeconds,
            clockSkewSeconds: clockSkewSeconds,
            enforceMinimumBars: false,
            asset: asset
        )

        guard entrySeries.report.isUsable else {
            let fallbackRegime = MarketRegimeClassifier.classify(
                candles: entrySeries.candles,
                marketClass: asset.marketClass
            )
            return EngineAnalysisOutput(
                signal: nil,
                hygieneReport: entrySeries.report,
                regimeAssessment: fallbackRegime,
                activeTraps: [],
                preNewsShield: MacroSurpriseEngine.preNewsShield(
                    for: asset,
                    events: calendarEvents,
                    nowEpochSeconds: serverNowEpochSeconds,
                    blackoutMinutesBefore: config.preNewsBlackoutMinutesBefore
                ),
                macroImpulse: nil
            )
        }

        // Compute causal positioning assessment (OKX for Crypto, CFTC COT for FX/Gold/Indices/CME BTC)
        var positioning: PositioningAssessment? = nil
        if let okx = okxDerivatives, config.enabledStrategies.contains(.positioningOkx) {
            positioning = PositioningAnalyzer.analyzeOKX(snapshot: okx, candles: entrySeries.candles)
        }
        if positioning == nil, !cftcCOTRecords.isEmpty, config.enabledStrategies.contains(.positioningCot) {
            positioning = PositioningAnalyzer.analyzeCFTCCOT(records: cftcCOTRecords, asOfEpochSeconds: serverNowEpochSeconds)
        }

        // Single unified evaluation pass (zero duplicate ICT / Macro / Trap computation)
        let eval = evaluateSanitizedDetailed(
            asset: asset,
            entryCandles: entrySeries.candles,
            htfCandles: htfSeries.candles,
            timeframe: timeframe,
            htfTimeframe: htfTimeframe,
            positioning: positioning,
            calendarEvents: calendarEvents,
            breakingNews: breakingNews,
            fearGreed: fearGreed,
            config: config,
            dataProvider: dataProvider,
            isMarketClosed: entrySeries.report.isMarketClosed,
            marketClosedReason: entrySeries.report.marketClosedReason,
            nowEpochSeconds: serverNowEpochSeconds
        )

        return EngineAnalysisOutput(
            signal: eval.signal,
            hygieneReport: entrySeries.report,
            regimeAssessment: eval.regime,
            activeTraps: eval.traps.filter(\.isActionable),
            preNewsShield: eval.preShield,
            macroImpulse: eval.latestMacro
        )
    }

    /// Evaluates already-sanitized causal candle arrays (used by both live `analyze` and `WalkForwardReplayEngine`).
    public static func evaluateSanitized(
        asset: AssetDescriptor,
        entryCandles: [Candle],
        htfCandles: [Candle],
        timeframe: Timeframe,
        htfTimeframe: Timeframe,
        positioning: PositioningAssessment?,
        calendarEvents: [EconomicEvent],
        breakingNews: [BreakingNewsItem] = [],
        fearGreed: FearGreedSnapshot? = nil,
        config: EngineConfig,
        dataProvider: String,
        isMarketClosed: Bool,
        marketClosedReason: String? = nil,
        nowEpochSeconds: TimeInterval
    ) -> TradeSignal? {
        guard entryCandles.count >= CandleHygieneEngine.minimumRequiredBars else { return nil }
        return evaluateSanitizedDetailed(
            asset: asset,
            entryCandles: entryCandles,
            htfCandles: htfCandles,
            timeframe: timeframe,
            htfTimeframe: htfTimeframe,
            positioning: positioning,
            calendarEvents: calendarEvents,
            breakingNews: breakingNews,
            fearGreed: fearGreed,
            config: config,
            dataProvider: dataProvider,
            isMarketClosed: isMarketClosed,
            marketClosedReason: marketClosedReason,
            nowEpochSeconds: nowEpochSeconds
        ).signal
    }

    private struct DetailedSanitizedEvaluation: Sendable {
        let signal: TradeSignal?
        let regime: RegimeAssessment
        let traps: [BehavioralTrap]
        let preShield: PreNewsShieldStatus?
        let latestMacro: MacroClusterImpulse?
    }

    private static func evaluateSanitizedDetailed(
        asset: AssetDescriptor,
        entryCandles: [Candle],
        htfCandles: [Candle],
        timeframe: Timeframe,
        htfTimeframe: Timeframe,
        positioning: PositioningAssessment?,
        calendarEvents: [EconomicEvent],
        breakingNews: [BreakingNewsItem],
        fearGreed: FearGreedSnapshot?,
        config: EngineConfig,
        dataProvider: String,
        isMarketClosed: Bool,
        marketClosedReason: String? = nil,
        nowEpochSeconds: TimeInterval
    ) -> DetailedSanitizedEvaluation {
        let regime = MarketRegimeClassifier.classify(candles: entryCandles, marketClass: asset.marketClass)
        let enabled = config.enabledStrategies
        let ict = CausalICTDetector.analyze(candles: entryCandles, weights: config.historicalReliabilityWeights, enabled: enabled)
        let candlestick = CandlestickPatternDetector.detect(candles: entryCandles, weights: config.historicalReliabilityWeights, enabled: enabled)
        let momentum = TrendMomentumDetector.analyze(candles: entryCandles, weights: config.historicalReliabilityWeights, enabled: enabled)

        let htfICT: ICTAnalysis?
        let htfBias: TradeDirection
        if htfCandles.count >= 25 {
            let hICT = CausalICTDetector.analyze(candles: htfCandles, weights: config.historicalReliabilityWeights)
            let hMom = TrendMomentumDetector.analyze(candles: htfCandles, weights: config.historicalReliabilityWeights)
            htfICT = hICT
            htfBias = hICT.currentStructureBias != .neutral ? hICT.currentStructureBias : hMom.htfTrendDirection
        } else {
            htfICT = nil
            htfBias = momentum.htfTrendDirection
        }

        let preShield = MacroSurpriseEngine.preNewsShield(
            for: asset,
            events: calendarEvents,
            nowEpochSeconds: nowEpochSeconds,
            blackoutMinutesBefore: config.preNewsBlackoutMinutesBefore
        )

        let recentEvents = calendarEvents.filter { ev in
            asset.exposedMacroCurrencies.contains(ev.currency) &&
            ev.isPublished &&
            nowEpochSeconds - ev.scheduledEpochSeconds >= 0 &&
            nowEpochSeconds - ev.scheduledEpochSeconds <= 4 * 3_600
        }
        let macroClusters = MacroSurpriseEngine.buildClusters(
            events: recentEvents,
            nowEpochSeconds: nowEpochSeconds,
            whipsawWindowMinutes: config.postNewsWhipsawMinutesAfter
        )
        let latestMacro = macroClusters.last

        let newsCatalyst = HeadlineSentimentClassifier.analyzeNewsCatalyst(
            for: asset,
            breakingNews: breakingNews,
            fearGreed: fearGreed,
            nowEpochSeconds: nowEpochSeconds
        )

        let traps = TrapLifecycleEngine.evaluate(
            symbol: asset.symbol,
            roundNumberStep: asset.roundNumberStep,
            candles: entryCandles,
            ict: ict,
            recentNewsImpulses: macroClusters,
            enabled: enabled
        )

        let signal = ConfluenceScorer.score(
            asset: asset,
            timeframe: timeframe,
            htfTimeframe: htfTimeframe,
            candles: entryCandles,
            htfBias: htfBias,
            ict: ict,
            htfICT: htfICT,
            candlestickContributions: candlestick,
            momentum: momentum,
            regimeAssessment: regime,
            traps: traps,
            positioning: positioning,
            preNewsShield: preShield,
            macroImpulse: latestMacro,
            config: config,
            dataProvider: dataProvider,
            isMarketClosed: isMarketClosed,
            nowEpochSeconds: nowEpochSeconds,
            newsCatalyst: newsCatalyst,
            marketClosedReason: marketClosedReason
        )

        return DetailedSanitizedEvaluation(
            signal: signal,
            regime: regime,
            traps: traps,
            preShield: preShield,
            latestMacro: latestMacro
        )
    }

    private struct CompactReflexSnapshot: Encodable, Sendable {
        let symbol: String
        let market: String
        let tf: String
        let htf_bias: String
        let category: String
        let dir: String
        let conf_pct: Int
        let regime: String
        let risk_state: String
        let killzone: String
        let aligned: [String]
        let pro_dir: String
        let retail_dir: String
        let psych_badges: [String]
        let rr: Double?
        let sl_pct: Double?
        let pre_news: String?
        let post_news: String?
    }

    /// Builds a compact (<400 token) causal JSON snapshot for the optional Gemini 4 Hydrogen judge.
    public static func buildCompactReflexPrompt(for signal: TradeSignal) -> String {
        let safeConf = signal.confidencePercent.isFinite ? Int(min(100.0, max(0.0, signal.confidencePercent)).rounded()) : 0
        let rrRounded: Double? = signal.levels.flatMap { lv in
            guard lv.riskRewardRatio.isFinite else { return nil }
            return (lv.riskRewardRatio * 100.0).rounded() / 100.0
        }
        let slRounded: Double? = signal.levels.flatMap { lv in
            guard lv.riskPercent.isFinite else { return nil }
            return (lv.riskPercent * 100.0).rounded() / 100.0
        }
        let snapshot = CompactReflexSnapshot(
            symbol: signal.symbol,
            market: signal.marketClass.rawValue,
            tf: signal.timeframe.rawValue,
            htf_bias: signal.htfBias.rawValue,
            category: signal.category.rawValue,
            dir: signal.direction.rawValue,
            conf_pct: safeConf,
            regime: signal.regime.rawValue,
            risk_state: signal.riskState.rawValue,
            killzone: signal.killzone.rawValue,
            aligned: signal.alignedStrategies.map(\.name),
            pro_dir: signal.psychologyReport.proDirection.rawValue,
            retail_dir: signal.psychologyReport.retailCrowdDirection.rawValue,
            psych_badges: signal.psychologyReport.behavioralBadges,
            rr: rrRounded,
            sl_pct: slRounded,
            pre_news: signal.preNewsBadge,
            post_news: signal.postNewsCatalystBadge
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(snapshot),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "{\"symbol\":\"\(signal.symbol)\",\"dir\":\"\(signal.direction.rawValue)\"}"
    }
}
