import Foundation
import XCTest
@testable import SignalEngine

final class MasterUpgrade30mAndJournalTests: XCTestCase {

    // MARK: - Helpers

    private func makeBar(
        openTime: TimeInterval,
        step: TimeInterval,
        open: Double,
        high: Double,
        low: Double,
        close: Double,
        volume: Double? = 250,
        isClosed: Bool = true
    ) -> Candle {
        Candle(
            openTimeEpochSeconds: openTime,
            closeTimeEpochSeconds: openTime + step,
            open: open,
            high: high,
            low: low,
            close: close,
            volume: volume,
            isClosed: isClosed
        )
    }

    private func makeSignal(
        id: String = "sig-30m-1",
        symbol: String = "BTC/USDT",
        marketClass: MarketClass = .crypto,
        timeframe: Timeframe = .m30,
        category: SignalCategory = .strongSignal,
        direction: TradeDirection = .long,
        score: Double = 78.0,
        barOpen: TimeInterval = 1_760_001_600,
        entryLow: Double = 99.8,
        entryHigh: Double = 100.2,
        entryMid: Double = 100.0,
        stopLoss: Double = 98.0,
        tp1: Double = 104.0,
        tp2: Double = 107.0,
        isTP2Enabled: Bool = true,
        orderFlowStatus: String = "aligned",
        orderFlowSummary: ChartOrderFlowSummary? = nil
    ) -> TradeSignal {
        let levels = TradeLevels(
            entryLow: entryLow,
            entryHigh: entryHigh,
            entryMid: entryMid,
            stopLoss: stopLoss,
            tp1: tp1,
            tp2: tp2,
            riskPercent: abs(entryMid - stopLoss) / entryMid * 100.0,
            reward1Percent: abs(tp1 - entryMid) / entryMid * 100.0,
            reward2Percent: abs(tp2 - entryMid) / entryMid * 100.0,
            riskRewardRatio: abs(tp1 - entryMid) / max(abs(entryMid - stopLoss), 1e-9),
            tp2RiskRewardRatio: abs(tp2 - entryMid) / max(abs(entryMid - stopLoss), 1e-9),
            isTP2Enabled: isTP2Enabled
        )
        let bar = makeBar(
            openTime: barOpen,
            step: timeframe.seconds,
            open: entryMid - 0.5,
            high: entryMid + 0.6,
            low: entryMid - 0.7,
            close: entryMid
        )
        let psych = PsychologyReport(
            signalCategory: category,
            proDirection: direction,
            retailCrowdDirection: direction.opposite,
            provenanceBadge: "Test",
            whatHappened: "Test setup",
            beginnerPsychology: "Beginner",
            proPsychology: "Pro",
            behavioralBadges: [],
            evidence: []
        )
        return TradeSignal(
            id: id,
            fingerprint: id,
            symbol: symbol,
            displayName: symbol,
            marketClass: marketClass,
            timeframe: timeframe,
            htfTimeframe: .h4,
            category: category,
            direction: direction,
            tier: category == .strongSignal ? .highConviction : .weakFiltered,
            confidencePercent: score,
            regime: .trending,
            riskState: .safe,
            killzone: .newYork,
            htfBias: direction,
            generatedAtEpochSeconds: barOpen + timeframe.seconds,
            barCloseEpochSeconds: barOpen + timeframe.seconds,
            levels: levels,
            alignedStrategies: [],
            rejectionReasons: category == .weakSignal ? ["Score 58 < 70"] : [],
            psychologyReport: psych,
            recentCandles: [bar],
            dataProvider: "Test",
            matchedStrategyIDs: [.ictBos, .ictFvg],
            activeStrategyProfileKey: "ict_bos+ict_fvg",
            orderFlowStatus: orderFlowStatus,
            orderFlowSummary: orderFlowSummary
        )
    }

    // MARK: - 1. 30m Timeframe Resampler, Scoring, ATR Levels, Order Flow Cap & Psychology

    func test30mTimeframeResamplerScoringATROrderFlowAndPsychology() {
        // Timeframe ordering & properties
        XCTAssertEqual(Timeframe.allCases, [.m15, .m30, .h1, .h4, .d1])
        XCTAssertEqual(Timeframe.m30.rawValue, "30m")
        XCTAssertEqual(Timeframe.m30.minutes, 30)
        XCTAssertEqual(Timeframe.m30.seconds, 1_800)
        XCTAssertEqual(Timeframe.m30.displayLabel, "30m")
        XCTAssertEqual(PassiveOutcomeEvaluator.defaultFillWindowBars(for: .m30), 12)
        XCTAssertEqual(OrderFlowAnalyzer.timeframeBaseWeight(for: .m30), 1.125, accuracy: 1e-9)
        XCTAssertGreaterThan(OrderFlowAnalyzer.timeframeBaseWeight(for: .m15), OrderFlowAnalyzer.timeframeBaseWeight(for: .m30))
        XCTAssertGreaterThan(OrderFlowAnalyzer.timeframeBaseWeight(for: .m30), OrderFlowAnalyzer.timeframeBaseWeight(for: .h1))

        // Exact :00 / :30 UTC resampling + OTC nil volume honesty + forming bar drop
        let boundary: TimeInterval = 1_760_000_400 // divisible by 1800 (1760000400 / 1800 = 977778)
        let m15Bars: [Candle] = [
            makeBar(openTime: boundary, step: 900, open: 100.0, high: 102.0, low: 99.0, close: 101.0, volume: nil),
            makeBar(openTime: boundary + 900, step: 900, open: 101.0, high: 104.0, low: 100.5, close: 103.5, volume: nil),
            makeBar(openTime: boundary + 1_800, step: 900, open: 103.5, high: 105.0, low: 102.0, close: 104.0, volume: nil) // 1st half of forming 30m bar
        ]
        // At boundary + 2700 (halfway through 2nd 30m bucket), only the 1st 30m bar is closed!
        let resampled = CandleHygieneEngine.resample15MTo30M(
            m15Candles: m15Bars,
            serverNowEpochSeconds: boundary + 2_700
        )
        XCTAssertEqual(resampled.count, 1)
        XCTAssertEqual(resampled[0].openTimeEpochSeconds, boundary)
        XCTAssertEqual(resampled[0].closeTimeEpochSeconds, boundary + 1_800)
        XCTAssertEqual(resampled[0].open, 100.0)
        XCTAssertEqual(resampled[0].high, 104.0)
        XCTAssertEqual(resampled[0].low, 99.0)
        XCTAssertEqual(resampled[0].close, 103.5)
        XCTAssertNil(resampled[0].volume, "OTC nil volume must remain nil")
        XCTAssertTrue(resampled[0].isClosed)

        // 30m SignalEngine scoring & compact reflex prompt emits "tf":"30m"
        let btc = WatchlistDefaults.descriptor(for: "BTC/USDT")!
        var m30Series: [Candle] = []
        var price = 60_000.0
        for i in 0..<60 {
            let drift = Double(i) * 30.0 + sin(Double(i) * 0.4) * 120.0
            let o = price
            let c = 60_000.0 + drift
            let h = max(o, c) + 90.0
            let l = min(o, c) - 90.0
            m30Series.append(makeBar(openTime: boundary + Double(i) * 1_800, step: 1_800, open: o, high: h, low: l, close: c, volume: 400 + Double(i * 10)))
            price = c
        }
        let now = boundary + 60 * 1_800
        let output = SignalEngine.analyze(
            asset: btc,
            rawEntryCandles: m30Series,
            rawHTFCandles: [],
            timeframe: .m30,
            htfTimeframe: .h4,
            dataProvider: "Test",
            serverNowEpochSeconds: now
        )
        XCTAssertTrue(output.hygieneReport.isUsable)
        if let sig = output.signal {
            XCTAssertEqual(sig.timeframe, .m30)
            let prompt = SignalEngine.buildCompactReflexPrompt(for: sig)
            XCTAssertTrue(prompt.contains("\"tf\":\"30m\""))
        }

        // 30m ATR levels & trap level synthesis
        let trap = BehavioralTrap(
            id: "trap-30m",
            symbol: "BTC/USDT",
            direction: .bullTrap,
            triggerKind: .oslerRoundNumberSweep,
            level: 62_000,
            extremePrice: 62_250,
            triggerBarIndex: 59,
            triggerEpochSeconds: now,
            state: .trigger,
            expiresAtEpochSeconds: now + 86_400,
            pierceATRMultiple: 0.7,
            detail: "Swept 62,000 round level"
        )
        let trapLevels = TradeLevelCalculator.synthesizeTrapLevels(
            trap: trap,
            candles: m30Series,
            atr: 180.0,
            marketClass: .crypto,
            timeframe: .m30
        )
        XCTAssertNotNil(trapLevels)
        if let lv = trapLevels {
            XCTAssertGreaterThan(lv.stopLoss, lv.entryMid)
            XCTAssertLessThan(lv.tp1, lv.entryMid)
            XCTAssertLessThan(lv.tp2, lv.tp1)
            XCTAssertGreaterThanOrEqual(lv.riskRewardRatio, 1.5)
        }

        // Psychology cadence threshold tuned smoothly for .m30 between .m15 and .h1
        XCTAssertEqual(PsychologyReportBuilder.healthyDailyCadenceLimit(for: .m30), 8)
        XCTAssertGreaterThan(PsychologyReportBuilder.healthyDailyCadenceLimit(for: .m15), PsychologyReportBuilder.healthyDailyCadenceLimit(for: .m30))
        XCTAssertGreaterThan(PsychologyReportBuilder.healthyDailyCadenceLimit(for: .m30), PsychologyReportBuilder.healthyDailyCadenceLimit(for: .h1))

        // StrategyID canonical displayName normalizer
        XCTAssertEqual(StrategyID.displayName(forRawKey: "ict_fvg"), "ICT Fair Value Gap (FVG)")
        XCTAssertEqual(StrategyID.displayName(forRawKey: "Ict Fvg"), "ICT Fair Value Gap (FVG)")
        XCTAssertEqual(StrategyID.displayName(forRawKey: "positioning_cot"), "COT Positioning")
        XCTAssertEqual(StrategyID.displayName(forRawKey: "Positioning Cot"), "COT Positioning")
    }

    // MARK: - 2. SignalJournalEngine Full Lifecycle & Invariants

    func testSignalJournalEngineFullLifecycleAndLockedWinInvariant() {
        let barOpen: TimeInterval = 1_760_000_400
        let created: TimeInterval = barOpen + 1_800 // 30m bar close

        // 0. Neutral direction MUST be rejected
        let neutralSig = makeSignal(category: .weakSignal, direction: .neutral, barOpen: barOpen)
        XCTAssertNil(SignalJournalEngine.createEntry(from: neutralSig, section: .weakAndFiltered, currentPrice: 100.0, now: created))

        // 1. Immediate In-Zone Fill initializes directly as .live
        let longSig = makeSignal(barOpen: barOpen, entryLow: 99.8, entryHigh: 100.2, entryMid: 100.0, stopLoss: 98.0, tp1: 104.0, tp2: 107.0)
        let immediateLive = SignalJournalEngine.createEntry(from: longSig, section: .strongSignals, currentPrice: 100.1, now: created)
        XCTAssertEqual(immediateLive?.status, .live)
        XCTAssertEqual(immediateLive?.fillPrice, 100.1)
        XCTAssertEqual(immediateLive?.filledAt, created)

        // 2. PENDING -> LIVE -> WIN (TP1 tracking TP2) -> WIN (TP2)
        guard var t1 = SignalJournalEngine.createEntry(from: longSig, section: .strongSignals, currentPrice: 101.0, now: created) else {
            return XCTFail("Expected pending journal trade")
        }
        XCTAssertEqual(t1.status, .pending)

        // Touch entry zone -> LIVE
        t1 = SignalJournalEngine.evaluateLiveTick(entry: t1, livePrice: 100.0, now: created + 300)
        XCTAssertEqual(t1.status, .live)
        XCTAssertEqual(t1.fillPrice, 100.0)

        // Hit TP1 (104.0) -> WIN · TP1 -> TP2 (isWinLocked == true)
        t1 = SignalJournalEngine.evaluateLiveTick(entry: t1, livePrice: 104.2, now: created + 1_200)
        XCTAssertEqual(t1.status, .winTrackingTP2)
        XCTAssertTrue(t1.isWinLocked)
        XCTAssertTrue(t1.status.isCountedWin)

        // Hit TP2 (107.0) -> WIN (TP2)
        t1 = SignalJournalEngine.evaluateLiveTick(entry: t1, livePrice: 107.5, now: created + 2_400)
        XCTAssertEqual(t1.status, .winTP2)
        XCTAssertEqual(t1.realizedR ?? 0, 3.425, accuracy: 1e-6)

        // 3. Locked WIN pullback to SL/breakeven MUST lock as .winTP1 and NEVER flip to .loss
        guard var pullbackTrade = SignalJournalEngine.createEntry(from: longSig, section: .strongSignals, currentPrice: 100.0, now: created) else {
            return XCTFail("Expected live trade")
        }
        pullbackTrade = SignalJournalEngine.evaluateLiveTick(entry: pullbackTrade, livePrice: 104.5, now: created + 600)
        XCTAssertEqual(pullbackTrade.status, .winTrackingTP2)
        XCTAssertTrue(pullbackTrade.isWinLocked)

        // Price crashes all the way below stopLoss (96.0) -> MUST lock as .winTP1, NEVER .loss!
        pullbackTrade = SignalJournalEngine.evaluateLiveTick(entry: pullbackTrade, livePrice: 96.0, now: created + 1_200)
        XCTAssertEqual(pullbackTrade.status, .winTP1)
        XCTAssertNotEqual(pullbackTrade.status, .loss)
        XCTAssertEqual(pullbackTrade.realizedR ?? 0, 1.925, accuracy: 1e-6)

        // 4. Runner 2x-expiry lock (30m pending = 6h, runner = 12h)
        guard var runnerExp = SignalJournalEngine.createEntry(from: longSig, section: .strongSignals, currentPrice: 100.0, now: created) else {
            return XCTFail("Expected live trade")
        }
        runnerExp = SignalJournalEngine.evaluateLiveTick(entry: runnerExp, livePrice: 104.1, now: created + 600)
        XCTAssertEqual(runnerExp.status, .winTrackingTP2)
        let expiryDelay = SignalJournalEngine.tp2RunnerExpirySeconds(for: .m30) // 12h
        runnerExp = SignalJournalEngine.evaluateLiveTick(entry: runnerExp, livePrice: 105.0, now: created + 600 + expiryDelay + 1)
        XCTAssertEqual(runnerExp.status, .winTP1)
        XCTAssertTrue(runnerExp.status.isCountedWin)

        // 5. PENDING -> EXPIRED (missed TP1 before fill, SL before fill, and timeout)
        guard var missedTP1 = SignalJournalEngine.createEntry(from: longSig, section: .weakAndFiltered, currentPrice: 101.5, now: created) else {
            return XCTFail("Expected pending trade")
        }
        missedTP1 = SignalJournalEngine.evaluateLiveTick(entry: missedTP1, livePrice: 104.5, now: created + 300)
        XCTAssertEqual(missedTP1.status, .expired)
        XCTAssertTrue(missedTP1.status.isExcludedFromWinRate)

        guard var missedTimeout = SignalJournalEngine.createEntry(from: longSig, section: .weakAndFiltered, currentPrice: 101.5, now: created) else {
            return XCTFail("Expected pending trade")
        }
        missedTimeout = SignalJournalEngine.evaluateLiveTick(entry: missedTimeout, livePrice: 101.2, now: created + SignalJournalEngine.pendingExpirySeconds(for: .m30) + 1)
        XCTAssertEqual(missedTimeout.status, .expired)

        // 6. Gap-safe closed-candle reconciliation:
        //    - Ignores signal bar (openTime == signalBarTimestamp)
        //    - Same-candle Entry + SL -> conservative .loss
        guard let pendingReconcile = SignalJournalEngine.createEntry(from: longSig, section: .strongSignals, currentPrice: 101.0, now: created) else {
            return XCTFail("Expected pending trade")
        }
        let signalBarDuplicate = makeBar(openTime: barOpen, step: 1_800, open: 100, high: 108, low: 97, close: 105)
        let entryAndSLCandle = makeBar(openTime: barOpen + 1_800, step: 1_800, open: 101.0, high: 106.0, low: 97.5, close: 105.0)
        let reconciledLoss = SignalJournalEngine.reconcile(
            entry: pendingReconcile,
            againstClosedCandles: [signalBarDuplicate, entryAndSLCandle],
            livePrice: nil,
            now: barOpen + 3_600
        )
        XCTAssertEqual(reconciledLoss.status, .loss)
        XCTAssertEqual(reconciledLoss.realizedR ?? 0, -1.075, accuracy: 1e-6)

        //    - Same-candle TP2 + breakeven pullback while .winTrackingTP2 -> conservative .winTP1 (never .loss)
        guard var trackingReconcile = SignalJournalEngine.createEntry(from: longSig, section: .strongSignals, currentPrice: 100.0, now: created) else {
            return XCTFail("Expected live trade")
        }
        let tp1Candle = makeBar(openTime: barOpen + 1_800, step: 1_800, open: 100.5, high: 104.5, low: 100.2, close: 104.2)
        let tp2AndBEWhipsaw = makeBar(openTime: barOpen + 3_600, step: 1_800, open: 104.2, high: 108.0, low: 99.5, close: 107.2)
        trackingReconcile = SignalJournalEngine.reconcile(
            entry: trackingReconcile,
            againstClosedCandles: [tp1Candle, tp2AndBEWhipsaw],
            livePrice: nil,
            now: barOpen + 5_400
        )
        XCTAssertEqual(trackingReconcile.status, .winTP1)
        XCTAssertTrue(trackingReconcile.isWinLocked)

        // 7. 3-Section WinRateBreakdown & Crypto Order Flow Edge Delta
        let stats = WinRateBreakdown.byJournalSection(entries: [t1, reconciledLoss, missedTP1, trackingReconcile])
        XCTAssertEqual(stats.count, 3)
        let strongStat = stats.first { $0.section == .strongSignals }
        XCTAssertEqual(strongStat?.wins, 2) // t1 (.winTP2) + trackingReconcile (.winTP1)
        XCTAssertEqual(strongStat?.losses, 1) // reconciledLoss (.loss)
        XCTAssertEqual(strongStat?.totalResolved, 3)

        let weakStat = stats.first { $0.section == .weakAndFiltered }
        XCTAssertEqual(weakStat?.totalResolved, 0, "Expired entries must be excluded from Win Rate denominator")
        XCTAssertEqual(weakStat?.expiredCount, 1)

        let ofDelta = WinRateBreakdown.cryptoOrderFlowEdgeDelta(entries: [t1, reconciledLoss, trackingReconcile])
        XCTAssertEqual(ofDelta.aligned.totalResolved, 3)
        XCTAssertTrue(ofDelta.isLowConfidence)
    }

    func testSignalJournalLimitFillWhenPriceBehindEntryAndSLCountsAsLoss() {
        let barOpen: TimeInterval = 1_760_000_400
        let created: TimeInterval = barOpen + 1_800

        // SHORT setup: Entry 71.30..71.36 (mid 71.33), SL 71.51, TP1 70.90, TP2 70.50
        let shortSig = makeSignal(
            id: "sig-short-limit",
            symbol: "USO/USD",
            marketClass: .stocks,
            timeframe: .h1,
            direction: .short,
            barOpen: barOpen,
            entryLow: 71.30,
            entryHigh: 71.36,
            entryMid: 71.33,
            stopLoss: 71.51,
            tp1: 70.90,
            tp2: 70.50
        )

        // 1. SHORT created when live price is HIGHER than entry (71.41, between entry 71.36 and SL 71.51)
        //    -> fills immediately at actual live price 71.41 (.live, 0.00R)
        guard var shortBehind = SignalJournalEngine.createEntry(
            from: shortSig,
            section: .weakAndFiltered,
            currentPrice: 71.41,
            now: created
        ) else {
            return XCTFail("Expected immediate live short entry when price is behind entry")
        }
        XCTAssertEqual(shortBehind.status, .live)
        XCTAssertEqual(shortBehind.fillPrice ?? 0, 71.41, accuracy: 1e-9)
        XCTAssertEqual(shortBehind.anchorEntryPrice, 71.41, accuracy: 1e-9)
        XCTAssertEqual(shortBehind.liveRMultiple, 0.0, accuracy: 1e-9)

        // Halfway to SL (71.46): riskDistance = |71.41 - 71.51| = 0.10 -> exactly -0.50R
        shortBehind = SignalJournalEngine.evaluateLiveTick(entry: shortBehind, livePrice: 71.46, now: created + 120)
        XCTAssertEqual(shortBehind.status, .live)
        XCTAssertEqual(shortBehind.liveRMultiple, -0.50, accuracy: 1e-6)

        // Reaching SL (71.51) MUST count as .loss (-1.0R net of stocks defaultRoundTripCostBps)
        let shortBehindCostR = (MarketClass.stocks.defaultRoundTripCostBps / 100.0) / ((0.10 / 71.41) * 100.0)
        shortBehind = SignalJournalEngine.evaluateLiveTick(entry: shortBehind, livePrice: 71.51, now: created + 240)
        XCTAssertEqual(shortBehind.status, .loss)
        XCTAssertEqual(shortBehind.realizedR ?? 0, -1.0 - shortBehindCostR, accuracy: 1e-6)
        XCTAssertTrue(shortBehind.status.isCountedLoss)

        // 2. SHORT filled behind entry at 71.41 -> hits TP1 (70.90) -> exact R anchored to 71.41 (5.10R)
        //    and breakeven pullback triggers at actual fill (71.41), NOT prematurely at planned entryMid (71.33)
        guard var shortWin = SignalJournalEngine.createEntry(
            from: shortSig,
            section: .strongSignals,
            currentPrice: 71.41,
            now: created
        ) else {
            return XCTFail("Expected live short entry")
        }
        shortWin = SignalJournalEngine.evaluateLiveTick(entry: shortWin, livePrice: 70.90, now: created + 600)
        XCTAssertEqual(shortWin.status, .winTrackingTP2)
        XCTAssertEqual(shortWin.realizedR ?? 0, 5.10 - shortBehindCostR, accuracy: 1e-6)
        shortWin = SignalJournalEngine.evaluateLiveTick(entry: shortWin, livePrice: 71.35, now: created + 900)
        XCTAssertEqual(shortWin.status, .winTrackingTP2, "Pullback above entryMid 71.33 but below actual fill 71.41 must keep runner open")
        shortWin = SignalJournalEngine.evaluateLiveTick(entry: shortWin, livePrice: 71.41, now: created + 1_200)
        XCTAssertEqual(shortWin.status, .winTP1)

        // 3. LONG created when live price is LOWER than entry (99.0, between SL 98.0 and entry 99.8)
        //    -> fills immediately at 99.0 (.live, 0.00R) and counts as .loss if SL 98.0 is hit
        let longSig = makeSignal(
            id: "sig-long-limit",
            barOpen: barOpen,
            entryLow: 99.8,
            entryHigh: 100.2,
            entryMid: 100.0,
            stopLoss: 98.0,
            tp1: 104.0,
            tp2: 107.0
        )
        guard var longBehind = SignalJournalEngine.createEntry(
            from: longSig,
            section: .strongSignals,
            currentPrice: 99.0,
            now: created
        ) else {
            return XCTFail("Expected immediate live long entry when price is behind entry")
        }
        XCTAssertEqual(longBehind.status, .live)
        XCTAssertEqual(longBehind.fillPrice ?? 0, 99.0, accuracy: 1e-9)
        XCTAssertEqual(longBehind.liveRMultiple, 0.0, accuracy: 1e-9)
        let longBehindCostR = (MarketClass.crypto.defaultRoundTripCostBps / 100.0) / ((1.0 / 99.0) * 100.0)
        longBehind = SignalJournalEngine.evaluateLiveTick(entry: longBehind, livePrice: 98.0, now: created + 300)
        XCTAssertEqual(longBehind.status, .loss)
        XCTAssertEqual(longBehind.realizedR ?? 0, -1.0 - longBehindCostR, accuracy: 1e-6)

        // 4. SHORT .pending (price ahead of entry toward TP1 at 71.15):
        //    - Stays .pending while below entry (71.25)
        //    - Expires if TP1 (70.85) hit without pulling back
        //    - Fills at actual live price (71.41) if tick jumps behind entry
        //    - Counts as .loss (NEVER .expired) if tick jumps straight past SL (71.55)
        guard let shortPendingBase = SignalJournalEngine.createEntry(
            from: shortSig,
            section: .strongSignals,
            currentPrice: 71.15,
            now: created
        ) else {
            return XCTFail("Expected pending short entry")
        }
        XCTAssertEqual(shortPendingBase.status, .pending)

        let stillPending = SignalJournalEngine.evaluateLiveTick(entry: shortPendingBase, livePrice: 71.25, now: created + 60)
        XCTAssertEqual(stillPending.status, .pending)

        let missedShortTP1 = SignalJournalEngine.evaluateLiveTick(entry: shortPendingBase, livePrice: 70.85, now: created + 120)
        XCTAssertEqual(missedShortTP1.status, .expired)

        let filledBehindTick = SignalJournalEngine.evaluateLiveTick(entry: shortPendingBase, livePrice: 71.41, now: created + 120)
        XCTAssertEqual(filledBehindTick.status, .live)
        XCTAssertEqual(filledBehindTick.fillPrice ?? 0, 71.41, accuracy: 1e-9)
        XCTAssertEqual(filledBehindTick.liveRMultiple, 0.0, accuracy: 1e-9)

        let shortMidCostR = (MarketClass.stocks.defaultRoundTripCostBps / 100.0) / ((0.18 / 71.33) * 100.0)
        let gappedPastSLTick = SignalJournalEngine.evaluateLiveTick(entry: shortPendingBase, livePrice: 71.55, now: created + 120)
        XCTAssertEqual(gappedPastSLTick.status, .loss, "Jumping from pending past SL must fill and count as .loss, not .expired")
        XCTAssertEqual(gappedPastSLTick.realizedR ?? 0, -1.0 - shortMidCostR, accuracy: 1e-6)

        // 5. LONG .pending (price ahead at 101.0) dropping straight behind entry (99.0) or past SL (97.5)
        guard let longPendingBase = SignalJournalEngine.createEntry(
            from: longSig,
            section: .strongSignals,
            currentPrice: 101.0,
            now: created
        ) else {
            return XCTFail("Expected pending long entry")
        }
        XCTAssertEqual(longPendingBase.status, .pending)
        let longBehindFill = SignalJournalEngine.evaluateLiveTick(entry: longPendingBase, livePrice: 99.0, now: created + 120)
        XCTAssertEqual(longBehindFill.status, .live)
        XCTAssertEqual(longBehindFill.fillPrice ?? 0, 99.0, accuracy: 1e-9)
        let longGappedSL = SignalJournalEngine.evaluateLiveTick(entry: longPendingBase, livePrice: 97.5, now: created + 120)
        XCTAssertEqual(longGappedSL.status, .loss)

        // 6. Closed-candle reconcile: SHORT bar entirely above entryZoneHigh (71.36) fills at bar.open (71.41)
        //    and counts as .loss if SL is hit on that bar or the next bar
        let behindBarClean = makeBar(openTime: barOpen + 3_600, step: 3_600, open: 71.41, high: 71.46, low: 71.38, close: 71.40)
        let slNextBar = makeBar(openTime: barOpen + 7_200, step: 3_600, open: 71.40, high: 71.55, low: 71.39, close: 71.52)
        let reconciledLive = SignalJournalEngine.reconcile(
            entry: shortPendingBase,
            againstClosedCandles: [behindBarClean],
            livePrice: nil,
            now: barOpen + 7_200
        )
        XCTAssertEqual(reconciledLive.status, .live)
        XCTAssertEqual(reconciledLive.fillPrice ?? 0, 71.41, accuracy: 1e-9)
        XCTAssertEqual(reconciledLive.liveRMultiple, 0.10, accuracy: 1e-6)

        let reconciledLossAfterBehindFill = SignalJournalEngine.reconcile(
            entry: shortPendingBase,
            againstClosedCandles: [behindBarClean, slNextBar],
            livePrice: nil,
            now: barOpen + 10_800
        )
        XCTAssertEqual(reconciledLossAfterBehindFill.status, .loss)
        XCTAssertEqual(reconciledLossAfterBehindFill.realizedR ?? 0, -1.0 - shortBehindCostR, accuracy: 1e-6)

        let behindBarImmediateSL = makeBar(openTime: barOpen + 3_600, step: 3_600, open: 71.41, high: 71.55, low: 71.38, close: 71.52)
        let reconciledImmediateSL = SignalJournalEngine.reconcile(
            entry: shortPendingBase,
            againstClosedCandles: [behindBarImmediateSL],
            livePrice: nil,
            now: barOpen + 7_200
        )
        XCTAssertEqual(reconciledImmediateSL.status, .loss, "Bar completely behind entry hitting SL must count as .loss")

        // 7. Pre-existing persisted .pending entry whose stored currentPrice is already behind entry
        //    heals immediately to .live on reconcile even when livePrice is nil
        let legacyPersistedPending = TrackedJournalTrade(
            id: "legacy-pending-short",
            symbol: "USO/USD",
            assetClass: .stocks,
            timeframe: .h1,
            direction: .short,
            section: .weakAndFiltered,
            status: .pending,
            score: 52.0,
            signalBarTimestamp: barOpen,
            entryZoneLow: 71.30,
            entryZoneHigh: 71.36,
            entryPrice: 71.33,
            fillPrice: nil,
            stopLoss: 71.51,
            target1: 70.90,
            target2: 70.50,
            currentPrice: 71.41,
            createdAt: created
        )
        let healed = SignalJournalEngine.reconcile(
            entry: legacyPersistedPending,
            againstClosedCandles: [],
            livePrice: nil,
            now: created + 300
        )
        XCTAssertEqual(healed.status, .live)
        XCTAssertEqual(healed.fillPrice ?? 0, 71.41, accuracy: 1e-9)

        // 8. Creation when live price is already at/beyond SL resolves conservatively as .loss
        let alreadyBreached = SignalJournalEngine.createEntry(
            from: shortSig,
            section: .strongSignals,
            currentPrice: 71.60,
            now: created
        )
        XCTAssertEqual(alreadyBreached?.status, .loss)
        XCTAssertEqual(alreadyBreached?.realizedR ?? 0, -1.0 - shortMidCostR, accuracy: 1e-6)
    }

    // MARK: - 3. OrderFlowNarrativeBuilder Plain-English Verdict, Wall Map & REST Honesty

    func testOrderFlowNarrativeBuilderWallBlockingAndRESTNotEvaluatedHonesty() {
        let precision = ChartPricePrecision.resolve(symbol: "BTC/USDT", marketClass: .crypto, referencePrice: 60_000)

        // Case A: Live WS confirmed Ask Wall blocking TP1 on Long
        let blockingSummary = ChartOrderFlowSummary(
            obiWeighted: -0.32,
            cvdRatio: 0.45,
            divergenceTag: nil,
            absorptionTag: "ABSORB-",
            alignment: OrderFlowAlignment.conflicting.rawValue,
            venue: "OKX",
            isLiveStream: true,
            bidWallPrice: 59_500,
            bidWallConfirmed: true,
            askWallPrice: 60_800,
            askWallConfirmed: true,
            spreadBps: 0.8,
            bidWallDistanceBps: 83.0,
            askWallDistanceBps: 133.0,
            bidWallSizeMultiple: 4.2,
            askWallSizeMultiple: 6.5,
            compositeScore: -0.45,
            confirmedWallBlocksTP1: true,
            tradeSampleCount: 48,
            capturedAtEpochSeconds: 1_760_000_000,
            divergenceRaw: OrderFlowDivergence.none.rawValue,
            absorptionRaw: OrderFlowAbsorptionState.bearishAbsorption.rawValue,
            isLowLiquidity: false
        )
        let blockingNarrative = OrderFlowNarrativeBuilder.build(
            summary: blockingSummary,
            direction: .long,
            entry: 60_000,
            stopLoss: 59_000,
            target1: 62_000,
            target2: 64_000,
            precision: precision
        )
        XCTAssertTrue(blockingNarrative.heroVerdict.contains("Blocking Target 1"))
        let askComp = blockingNarrative.wallLevelComparisons.first { $0.side == "Ask Wall" }
        XCTAssertNotNil(askComp)
        XCTAssertTrue(askComp?.isBlockingTarget == true)
        XCTAssertEqual(askComp?.statusBadge, "Confirmed 6s+")
        XCTAssertTrue(blockingNarrative.actionableTakeaway.contains("60800.00"))

        // Case B: Batch REST scan -> .notEvaluated MUST clearly explain "Needs live stream window (batch REST scan)"
        let restSummary = ChartOrderFlowSummary(
            obiWeighted: 0.35,
            cvdRatio: 0.0,
            divergenceTag: nil,
            absorptionTag: nil,
            alignment: OrderFlowAlignment.aligned.rawValue,
            venue: "Bybit",
            isLiveStream: false,
            bidWallPrice: 59_800,
            bidWallConfirmed: false,
            askWallPrice: nil,
            askWallConfirmed: false,
            spreadBps: 1.2,
            tradeSampleCount: 0,
            divergenceRaw: OrderFlowDivergence.notEvaluated.rawValue,
            absorptionRaw: OrderFlowAbsorptionState.notEvaluated.rawValue
        )
        let restNarrative = OrderFlowNarrativeBuilder.build(
            summary: restSummary,
            direction: .long,
            entry: 60_000,
            stopLoss: 59_000,
            target1: 62_000,
            target2: 64_000,
            precision: precision
        )
        let divCard = restNarrative.eventCards.first { $0.id == "divergence" }
        let absCard = restNarrative.eventCards.first { $0.id == "absorption" }
        XCTAssertEqual(divCard?.isEvaluated, false)
        XCTAssertEqual(divCard?.detail, OrderFlowNarrativeBuilder.restWindowRequiredMessage)
        XCTAssertEqual(absCard?.isEvaluated, false)
        XCTAssertEqual(absCard?.detail, OrderFlowNarrativeBuilder.restWindowRequiredMessage)
        let bidComp = restNarrative.wallLevelComparisons.first { $0.side == "Bid Wall" }
        XCTAssertEqual(bidComp?.statusBadge, "Unconfirmed Flash")
    }
}
