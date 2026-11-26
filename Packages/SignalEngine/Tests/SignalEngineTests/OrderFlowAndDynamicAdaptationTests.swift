import XCTest
@testable import SignalEngine

final class OrderFlowAndDynamicAdaptationTests: XCTestCase {

    // MARK: - 1. Dynamic Weight Re-Normalization & All-Disabled Zero-NaN Safety

    func testDynamicWeightRenormalizationSumsStrictlyToOneAcrossSubsets() {
        let subsets: [Set<StrategyID>] = [
            [.ictFvg],
            [.ictBos, .ictFvg, .momentumEmaPullback],
            StrategyID.provenWinners,
            StrategyID.allSet
        ]
        let now: TimeInterval = 1_760_000_000
        let snap = makeHealthyCryptoOrderFlowSnapshot(now: now, bidHeavy: true, withConfirmedWalls: true)
        let eval = OrderFlowAnalyzer.evaluate(
            snapshot: snap,
            marketClass: .crypto,
            isOrderFlowEnabled: true,
            isLiveEvaluation: true,
            candidateDirection: .long,
            nowEpochSeconds: now
        )

        for subset in subsets {
            for ofOn in [false, true] {
                for market in [MarketClass.crypto, MarketClass.forex] {
                    let profile = ActiveStrategyProfile(enabledStrategies: subset, isOrderFlowEnabled: ofOn)
                    let weights = ConfluenceScorer.computeNormalizedModuleWeights(
                        profile: profile,
                        marketClass: market,
                        timeframe: .m15,
                        isLiveEvaluation: true,
                        orderFlowAssessment: market == .crypto ? eval : nil
                    )
                    let active = weights.filter(\.isActive)
                    XCTAssertFalse(active.isEmpty)
                    let sum = active.reduce(0.0) { $0 + $1.effectiveWeight }
                    XCTAssertEqual(sum, 1.0, accuracy: 1e-9, "Active weights must sum strictly to 1.0")
                    for skipped in weights where !skipped.isActive {
                        XCTAssertEqual(skipped.effectiveWeight, 0.0, accuracy: 1e-12)
                        XCTAssertNotNil(skipped.skippedReason)
                    }
                    // Order Flow must NEVER be active on Forex
                    if market == .forex {
                        let ofEntry = weights.first { $0.id == "crypto_order_flow" }
                        XCTAssertEqual(ofEntry?.isActive, false)
                        XCTAssertEqual(ofEntry?.effectiveWeight, 0.0)
                    }
                }
            }
        }

        // All-disabled edge case: zero NaN / Inf, all effective weights == 0
        let emptyProfile = ActiveStrategyProfile(enabledStrategies: [], isOrderFlowEnabled: false)
        let emptyWeights = ConfluenceScorer.computeNormalizedModuleWeights(
            profile: emptyProfile,
            marketClass: .crypto,
            timeframe: .h1,
            isLiveEvaluation: true,
            orderFlowAssessment: nil
        )
        for entry in emptyWeights {
            XCTAssertTrue(entry.effectiveWeight.isFinite)
            XCTAssertEqual(entry.effectiveWeight, 0.0)
            XCTAssertFalse(entry.isActive)
        }
    }

    // MARK: - 2. Timeframe-Aware Order Flow Scaling & Crypto-Only / Anti-Repainting Gates

    func testTimeframeAwareOrderFlowWeightingAndHistoricalAntiRepaintingGate() {
        XCTAssertGreaterThan(
            OrderFlowAnalyzer.timeframeBaseWeight(for: .m15),
            OrderFlowAnalyzer.timeframeBaseWeight(for: .h1)
        )
        XCTAssertGreaterThan(
            OrderFlowAnalyzer.timeframeBaseWeight(for: .h1),
            OrderFlowAnalyzer.timeframeBaseWeight(for: .h4)
        )
        XCTAssertGreaterThan(
            OrderFlowAnalyzer.timeframeBaseWeight(for: .h4),
            OrderFlowAnalyzer.timeframeBaseWeight(for: .d1)
        )

        let now: TimeInterval = 1_760_000_000
        let snap = makeHealthyCryptoOrderFlowSnapshot(now: now, bidHeavy: true, withConfirmedWalls: true)

        // Live Crypto ON -> active & aligned
        let liveCrypto = OrderFlowAnalyzer.evaluate(
            snapshot: snap,
            marketClass: .crypto,
            isOrderFlowEnabled: true,
            isLiveEvaluation: true,
            candidateDirection: .long,
            nowEpochSeconds: now
        )
        XCTAssertEqual(liveCrypto.alignment, .aligned)
        XCTAssertGreaterThan(liveCrypto.compositeScore, 0.0)

        // Forex with Order Flow ON -> strictly unavailable (zero penalty)
        let forexEval = OrderFlowAnalyzer.evaluate(
            snapshot: snap,
            marketClass: .forex,
            isOrderFlowEnabled: true,
            isLiveEvaluation: true,
            candidateDirection: .long,
            nowEpochSeconds: now
        )
        XCTAssertEqual(forexEval.alignment, .unavailable)
        XCTAssertEqual(forexEval.compositeScore, 0.0)
        XCTAssertNil(forexEval.chartSummary)

        // Historical replay (`isLiveEvaluation == false`) -> strictly unavailable (anti-repainting)
        let replayEval = OrderFlowAnalyzer.evaluate(
            snapshot: snap,
            marketClass: .crypto,
            isOrderFlowEnabled: true,
            isLiveEvaluation: false,
            candidateDirection: .long,
            nowEpochSeconds: now
        )
        XCTAssertEqual(replayEval.alignment, .unavailable)
        XCTAssertEqual(replayEval.compositeScore, 0.0)

        // Stale snapshot (> 20s) -> strictly rejected
        let staleEval = OrderFlowAnalyzer.evaluate(
            snapshot: snap,
            marketClass: .crypto,
            isOrderFlowEnabled: true,
            isLiveEvaluation: true,
            candidateDirection: .long,
            nowEpochSeconds: now + 25.0
        )
        XCTAssertEqual(staleEval.alignment, .unavailable)
    }

    // MARK: - 3. Contract-Multiplier Invariance, Wide-Spread Damping, Absorption, CVD Div & Walls

    func testOrderFlowContractMultiplierInvarianceAndWideSpreadDamping() {
        let now: TimeInterval = 1_760_000_000
        let baseSnap = makeHealthyCryptoOrderFlowSnapshot(now: now, bidHeavy: true, withConfirmedWalls: true)
        // Multiply ALL quantities by 1000x (simulating OKX SWAP contracts vs base coin units)
        let scaledSnap = OrderFlowSnapshot(
            timestampEpochSeconds: baseSnap.timestampEpochSeconds,
            venue: baseSnap.venue,
            isLiveWebSocket: baseSnap.isLiveWebSocket,
            midPrice: baseSnap.midPrice,
            bestBid: baseSnap.bestBid,
            bestAsk: baseSnap.bestAsk,
            spreadBps: baseSnap.spreadBps,
            bids: baseSnap.bids.map { OrderBookLevel(price: $0.price, quantity: $0.quantity * 1000.0) },
            asks: baseSnap.asks.map { OrderBookLevel(price: $0.price, quantity: $0.quantity * 1000.0) },
            recentTrades: baseSnap.recentTrades.map {
                OrderFlowTrade(price: $0.price, quantity: $0.quantity * 1000.0, isBuyerMaker: $0.isBuyerMaker, timestampEpochSeconds: $0.timestampEpochSeconds)
            },
            recentLiquidations: baseSnap.recentLiquidations.map {
                OrderFlowLiquidation(price: $0.price, sizeInSameUnits: $0.sizeInSameUnits * 1000.0, isLongLiquidation: $0.isLongLiquidation, timestampEpochSeconds: $0.timestampEpochSeconds)
            },
            confirmedWallPrices: baseSnap.confirmedWallPrices
        )

        let baseEval = OrderFlowAnalyzer.evaluate(
            snapshot: baseSnap, marketClass: .crypto, isOrderFlowEnabled: true, isLiveEvaluation: true,
            candidateDirection: .long, nowEpochSeconds: now
        )
        let scaledEval = OrderFlowAnalyzer.evaluate(
            snapshot: scaledSnap, marketClass: .crypto, isOrderFlowEnabled: true, isLiveEvaluation: true,
            candidateDirection: .long, nowEpochSeconds: now
        )

        XCTAssertEqual(baseEval.obiWeighted, scaledEval.obiWeighted, accuracy: 1e-9)
        XCTAssertEqual(baseEval.cvdRatio, scaledEval.cvdRatio, accuracy: 1e-9)
        XCTAssertEqual(baseEval.compositeScore, scaledEval.compositeScore, accuracy: 1e-9)
        XCTAssertTrue((-1.0...1.0).contains(baseEval.obiWeighted))
        XCTAssertTrue((-1.0...1.0).contains(baseEval.compositeScore))

        // Wide spread (> 60 bps) -> flagged lowLiquidity & safely damped to 0
        let wideSnap = OrderFlowSnapshot(
            timestampEpochSeconds: now,
            venue: "Bybit",
            isLiveWebSocket: false,
            midPrice: 100.0,
            bestBid: 99.5,
            bestAsk: 100.5, // 100 bps spread
            spreadBps: 100.0,
            bids: [OrderBookLevel(price: 99.5, quantity: 50), OrderBookLevel(price: 99.0, quantity: 40), OrderBookLevel(price: 98.5, quantity: 30)],
            asks: [OrderBookLevel(price: 100.5, quantity: 10), OrderBookLevel(price: 101.0, quantity: 10), OrderBookLevel(price: 101.5, quantity: 10)]
        )
        let wideEval = OrderFlowAnalyzer.evaluate(
            snapshot: wideSnap, marketClass: .crypto, isOrderFlowEnabled: true, isLiveEvaluation: true,
            candidateDirection: .long, nowEpochSeconds: now
        )
        XCTAssertTrue(wideEval.isLowLiquidity)
        XCTAssertEqual(wideEval.alignment, .unavailable)
        XCTAssertEqual(wideEval.compositeScore, 0.0)
    }

    func testWindowGuardedCVDDivergencePassiveAbsorptionAndConfirmedWallGuard() {
        let now: TimeInterval = 1_760_000_000
        let bids = [
            OrderBookLevel(price: 99.99, quantity: 10),
            OrderBookLevel(price: 99.95, quantity: 10),
            OrderBookLevel(price: 99.90, quantity: 45), // 4.5x median Bid Wall
            OrderBookLevel(price: 99.85, quantity: 10)
        ]
        let asks = [
            OrderBookLevel(price: 100.01, quantity: 10),
            OrderBookLevel(price: 100.05, quantity: 10),
            OrderBookLevel(price: 100.15, quantity: 50), // 5.0x median Ask Wall
            OrderBookLevel(price: 100.20, quantity: 10)
        ]

        // 1. Small trade sample (< 20 trades) must NOT trigger absorption or divergence
        let tinyTrades = (0..<6).map { i in
            OrderFlowTrade(price: 100.0, quantity: 5.0, isBuyerMaker: true, timestampEpochSeconds: now - Double(6 - i))
        }
        let tinySnap = OrderFlowSnapshot(
            timestampEpochSeconds: now, venue: "OKX", isLiveWebSocket: true,
            midPrice: 100.0, bestBid: 99.99, bestAsk: 100.01, spreadBps: 2.0,
            bids: bids, asks: asks, recentTrades: tinyTrades, confirmedWallPrices: [99.90]
        )
        let tinyEval = OrderFlowAnalyzer.evaluate(
            snapshot: tinySnap, marketClass: .crypto, isOrderFlowEnabled: true, isLiveEvaluation: true,
            candidateDirection: .long, nowEpochSeconds: now
        )
        XCTAssertEqual(tinyEval.divergence, .notEvaluated)
        XCTAssertEqual(tinyEval.absorptionState, .notEvaluated)
        XCTAssertFalse(tinyEval.isStrongConflict)

        // 2. Institutional Passive Bullish Absorption: 24 heavy aggressive sells (`isBuyerMaker == true`), price holds/rises near confirmed Bid Wall
        let absorptionTrades = (0..<24).map { i in
            OrderFlowTrade(
                price: 100.00 + Double(i) * 0.001,
                quantity: 10.0,
                isBuyerMaker: (i % 5 != 0), // 80% aggressive sells -> cvdRatio == -0.60
                timestampEpochSeconds: now - Double(24 - i)
            )
        }
        let absorbSnap = OrderFlowSnapshot(
            timestampEpochSeconds: now, venue: "OKX", isLiveWebSocket: true,
            midPrice: 100.0, bestBid: 99.99, bestAsk: 100.01, spreadBps: 2.0,
            bids: bids, asks: asks, recentTrades: absorptionTrades,
            confirmedWallPrices: [99.90, 100.15]
        )
        let absorbEval = OrderFlowAnalyzer.evaluate(
            snapshot: absorbSnap, marketClass: .crypto, isOrderFlowEnabled: true, isLiveEvaluation: true,
            candidateDirection: .long, entryPrice: 100.00, takeProfit1: 100.50, nowEpochSeconds: now
        )
        XCTAssertEqual(absorbEval.absorptionState, .bullishAbsorption)
        XCTAssertEqual(absorbEval.nearestBidWall?.isConfirmed, true)
        XCTAssertEqual(absorbEval.nearestAskWall?.isConfirmed, true)
        // Confirmed Ask Wall at 100.15 sits strictly between Entry (100.00) and TP1 (100.50)!
        XCTAssertTrue(absorbEval.confirmedWallBlocksTP1)
        XCTAssertEqual(absorbEval.alignment, .conflicting)
        XCTAssertNotNil(absorbEval.warningNote)

        // REST snapshot (not live WS) must NEVER mark a wall confirmed (anti-spoofing) and marks divergence/absorption .notEvaluated
        let restSnap = OrderFlowSnapshot(
            timestampEpochSeconds: now, venue: "OKX", isLiveWebSocket: false,
            midPrice: 100.0, bestBid: 99.99, bestAsk: 100.01, spreadBps: 2.0,
            bids: bids, asks: asks, recentTrades: absorptionTrades,
            confirmedWallPrices: [99.90, 100.15]
        )
        let restEval = OrderFlowAnalyzer.evaluate(
            snapshot: restSnap, marketClass: .crypto, isOrderFlowEnabled: true, isLiveEvaluation: true,
            candidateDirection: .long, entryPrice: 100.00, takeProfit1: 100.50, nowEpochSeconds: now
        )
        XCTAssertEqual(restEval.divergence, .notEvaluated)
        XCTAssertEqual(restEval.absorptionState, .notEvaluated)
        XCTAssertEqual(restEval.nearestBidWall?.isConfirmed, false)
        XCTAssertEqual(restEval.nearestAskWall?.isConfirmed, false)
        XCTAssertFalse(restEval.confirmedWallBlocksTP1)
    }

    // MARK: - 4. TradeLevelCalculator Graceful Fallback & AI Reflex Prompt Parity

    func testTradeLevelCalculatorGracefulFallbackAndAIReflexPromptParity() {
        let base: TimeInterval = 1_760_000_000
        let bar = Candle(openTimeEpochSeconds: base - 3600, closeTimeEpochSeconds: base, open: 50000, high: 50300, low: 49800, close: 50150, volume: 250, isClosed: true)
        let emptyICT = ICTAnalysis(
            swings: [], structureBreaks: [], fvgs: [], orderBlocks: [], liquiditySweeps: [],
            currentStructureBias: .neutral, equilibriumPrice: nil, dealingRangeHigh: nil,
            dealingRangeLow: nil, dealingZone: nil, contributions: []
        )

        // Even with ALL ICT swings/FVGs/OBs disabled, TradeLevelCalculator falls back cleanly to ATR levels
        let lv = TradeLevelCalculator.calculate(
            direction: .long, candles: [bar], ict: emptyICT, htfICT: nil,
            atr: 250.0, marketClass: .crypto, minimumRiskReward: 2.0,
            mode: .structureATR, enableTP2Target: true, timeframe: .h1
        )
        XCTAssertNotNil(lv)
        if let lv {
            XCTAssertTrue(lv.stopLoss < lv.entryLow)
            XCTAssertTrue(lv.tp1 > lv.entryHigh)
            XCTAssertTrue(lv.tp2 > lv.tp1)
            XCTAssertGreaterThanOrEqual(lv.riskRewardRatio, 1.99)
        }

        // AI Reflex Prompt includes active strategy profile, judge rule, and Crypto-only orderflow
        let btc = WatchlistDefaults.descriptor(for: "BTC/USDT")!
        let snap = makeHealthyCryptoOrderFlowSnapshot(now: base, bidHeavy: true, withConfirmedWalls: true)
        let momContrib = StrategyContribution(id: "momentum_ema_pullback", name: "EMA Pullback", group: .trendMomentum, direction: .long, weight: 1.1, historicalWinRate: 0.62, detail: "EMA")
        let mom = TrendMomentumSnapshot(ema20: 50050, ema50: 49800, ema200: 48500, rsi14: 58, atr14: 250, rvol: 1.4, htfTrendDirection: .long, contributions: [momContrib])
        let regime = RegimeAssessment(regime: .trending, riskState: .safe, atrPercent: 0.5, atrZScore: 0.2, efficiencyRatio: 0.7, rollingDrawdownPercent: 0.5, summary: "Trending")
        let cfg = EngineConfig(minimumConfidencePercent: 55.0, minimumRiskReward: 2.0, minimumAlignedStrategies: 1, enabledStrategies: [.momentumEmaPullback], isOrderFlowEnabled: true)

        let cryptoSig = ConfluenceScorer.score(
            asset: btc, timeframe: .m15, htfTimeframe: .h4, candles: [bar], htfBias: .long,
            ict: emptyICT, htfICT: nil, candlestickContributions: [], momentum: mom, regimeAssessment: regime,
            traps: [], positioning: nil, preNewsShield: nil, macroImpulse: nil,
            config: cfg, dataProvider: "OKX", isMarketClosed: false, nowEpochSeconds: base,
            orderFlowSnapshot: snap, isLiveEvaluation: true
        )
        XCTAssertNotNil(cryptoSig)
        if let cryptoSig {
            let prompt = SignalEngine.buildCompactReflexPrompt(for: cryptoSig, activeProfile: cfg.activeStrategyProfile)
            XCTAssertTrue(prompt.contains("strategy_profile"))
            XCTAssertTrue(prompt.contains("Never penalize user-disabled strategies"))
            XCTAssertTrue(prompt.contains("order_flow"))
            XCTAssertTrue(prompt.contains("\"venue\":\"OKX\""))
        }

        // Forex signal omits order_flow cleanly
        let eur = WatchlistDefaults.descriptor(for: "EUR/USD")!
        let fxBar = Candle(openTimeEpochSeconds: base - 3600, closeTimeEpochSeconds: base, open: 1.1000, high: 1.1020, low: 1.0990, close: 1.1010, volume: nil, isClosed: true)
        let fxMom = TrendMomentumSnapshot(ema20: 1.1005, ema50: 1.0990, ema200: 1.0950, rsi14: 57, atr14: 0.0015, rvol: nil, htfTrendDirection: .long, contributions: [momContrib])
        let fxSig = ConfluenceScorer.score(
            asset: eur, timeframe: .h1, htfTimeframe: .h4, candles: [fxBar], htfBias: .long,
            ict: emptyICT, htfICT: nil, candlestickContributions: [], momentum: fxMom, regimeAssessment: regime,
            traps: [], positioning: nil, preNewsShield: nil, macroImpulse: nil,
            config: cfg, dataProvider: "Twelve Data", isMarketClosed: false, nowEpochSeconds: base,
            orderFlowSnapshot: snap, isLiveEvaluation: true
        )
        XCTAssertNotNil(fxSig)
        if let fxSig {
            XCTAssertEqual(fxSig.orderFlowStatus, "non_crypto")
            XCTAssertNil(fxSig.orderFlowSummary)
            let fxPrompt = SignalEngine.buildCompactReflexPrompt(for: fxSig, activeProfile: cfg.activeStrategyProfile)
            XCTAssertFalse(fxPrompt.contains("\"venue\":\"OKX\""))
        }
    }

    // MARK: - 5. Adaptive PsychologyReportBuilder Audit & WinRateBreakdown Order Flow Edge Delta

    func testPsychologyBehavioralAuditFilterHoppingLegacyBaselineAndOrderFlowCoaching() {
        let base: TimeInterval = 1_760_000_000

        // One-time upgrade transition from "" (legacy_baseline) to "ict_bos+ict_fvg" after a loss MUST NOT trigger filter-hopping
        let legacyTransitionRecords: [SignalOutcomeRecord] = [
            makeOutcome(id: "1", market: .crypto, status: .hitSL, r: -1.0, ts: base + 100, profileKey: "", ofStatus: "off"),
            makeOutcome(id: "2", market: .crypto, status: .hitTP1, r: 2.0, ts: base + 200, profileKey: "ict_bos+ict_fvg", ofStatus: "aligned")
        ]
        let singleProfile = ActiveStrategyProfile(enabledStrategies: [.ictFvg], isOrderFlowEnabled: true)
        let legacyAudit = PsychologyReportBuilder.buildBehavioralAudit(
            outcomes: legacyTransitionRecords,
            activeProfile: singleProfile
        )
        XCTAssertFalse(legacyAudit.filterHoppingDetected, "One-time upgrade from legacy_baseline must not flag filter-hopping")
        XCTAssertTrue(legacyAudit.insights.contains { $0.id == "breadth_single_core" })

        // Repeated switches of non-empty profiles after losses + Crypto conflicting Order Flow entries
        let hoppingRecords: [SignalOutcomeRecord] = [
            makeOutcome(id: "a", market: .crypto, status: .hitSL, r: -1.0, ts: base + 100, profileKey: "ict_bos+ict_fvg", ofStatus: "conflicting"),
            makeOutcome(id: "b", market: .crypto, status: .hitSL, r: -1.0, ts: base + 200, profileKey: "candle_displacement", ofStatus: "conflicting"),
            makeOutcome(id: "c", market: .crypto, status: .hitTP1, r: 2.5, ts: base + 300, profileKey: "momentum_ema_pullback", ofStatus: "aligned")
        ]
        let multiProfile = ActiveStrategyProfile(enabledStrategies: StrategyID.provenWinners, isOrderFlowEnabled: true)
        let audit = PsychologyReportBuilder.buildBehavioralAudit(
            outcomes: hoppingRecords,
            activeProfile: multiProfile
        )
        XCTAssertTrue(audit.filterHoppingDetected)
        XCTAssertEqual(audit.filterHopSwitchCount, 2)
        XCTAssertEqual(audit.conflictingOrderFlowTrades, 2)
        XCTAssertEqual(audit.conflictingOrderFlowAvgR ?? 0, -1.0, accuracy: 1e-6)
        XCTAssertEqual(audit.alignedOrderFlowAvgR ?? 0, 2.5, accuracy: 1e-6)
        XCTAssertTrue(audit.insights.contains { $0.id == "filter_hopping" })
        XCTAssertTrue(audit.insights.contains { $0.id == "orderflow_conflict_coaching" })

        // Forex-scoped audit must NOT lecture about Order Flow
        let fxAudit = PsychologyReportBuilder.buildBehavioralAudit(
            outcomes: hoppingRecords,
            activeProfile: multiProfile,
            marketClass: .forex
        )
        XCTAssertFalse(fxAudit.insights.contains { $0.id == "orderflow_conflict_coaching" })

        // WinRateBreakdown Crypto Order Flow Edge Delta
        let edge = WinRateBreakdown.cryptoOrderFlowEdgeDelta(records: hoppingRecords)
        XCTAssertEqual(edge.aligned.totalResolved, 1)
        XCTAssertEqual(edge.conflicting.totalResolved, 2)
        XCTAssertEqual(edge.avgRDeltaAlignedVsConflicting ?? 0, 3.5, accuracy: 1e-6)
    }

    // MARK: - Helpers

    private func makeHealthyCryptoOrderFlowSnapshot(
        now: TimeInterval,
        bidHeavy: Bool,
        withConfirmedWalls: Bool
    ) -> OrderFlowSnapshot {
        let bidQty = bidHeavy ? 40.0 : 10.0
        let askQty = bidHeavy ? 10.0 : 40.0
        let bids = [
            OrderBookLevel(price: 49999.0, quantity: bidQty),
            OrderBookLevel(price: 49990.0, quantity: bidQty),
            OrderBookLevel(price: 49975.0, quantity: bidQty * 4.0),
            OrderBookLevel(price: 49950.0, quantity: bidQty)
        ]
        let asks = [
            OrderBookLevel(price: 50001.0, quantity: askQty),
            OrderBookLevel(price: 50010.0, quantity: askQty),
            OrderBookLevel(price: 50030.0, quantity: askQty),
            OrderBookLevel(price: 50060.0, quantity: askQty)
        ]
        let trades = (0..<24).map { i in
            OrderFlowTrade(
                price: 50000.0 + Double(i) * (bidHeavy ? 0.5 : -0.5),
                quantity: 3.0,
                isBuyerMaker: !bidHeavy,
                timestampEpochSeconds: now - Double(24 - i)
            )
        }
        return OrderFlowSnapshot(
            timestampEpochSeconds: now - 1.0,
            venue: "OKX",
            isLiveWebSocket: true,
            midPrice: 50000.0,
            bestBid: 49999.0,
            bestAsk: 50001.0,
            spreadBps: 0.4,
            bids: bids,
            asks: asks,
            recentTrades: trades,
            recentLiquidations: [],
            confirmedWallPrices: withConfirmedWalls ? [49975.0] : []
        )
    }

    private func makeOutcome(
        id: String,
        market: MarketClass,
        status: SignalOutcomeStatus,
        r: Double,
        ts: TimeInterval,
        profileKey: String,
        ofStatus: String
    ) -> SignalOutcomeRecord {
        SignalOutcomeRecord(
            signalId: id,
            symbol: market == .crypto ? "BTC/USDT" : "EUR/USD",
            marketClass: market,
            category: .strongSignal,
            direction: .long,
            predictedProbability: 0.78,
            status: status,
            netReturnPercent: r * 1.0,
            rMultiple: r,
            strategyIds: ["ict_bos"],
            hadMacroCatalyst: false,
            resolvedAtEpochSeconds: ts,
            lifecycleStatus: .resolved,
            isLegacyImmediateFill: false,
            origin: .scanner,
            activeStrategyProfileKey: profileKey,
            enabledStrategyIDsCSV: profileKey.replacingOccurrences(of: "+", with: ","),
            orderFlowStatus: ofStatus
        )
    }
}
