import Foundation
import XCTest
@testable import SignalEngine

final class V15EngineTests: XCTestCase {
    // MARK: - Helpers

    private func makeBar(
        openTime: TimeInterval,
        step: TimeInterval = 3_600,
        open: Double,
        high: Double,
        low: Double,
        close: Double,
        volume: Double? = 500,
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

    private func makeOutcome(
        id: String,
        category: SignalCategory = .strongSignal,
        origin: SignalOrigin = .scanner,
        score: Double = 75.0,
        status: SignalOutcomeStatus = .hitTP1,
        isLegacy: Bool = false
    ) -> SignalOutcomeRecord {
        SignalOutcomeRecord(
            signalId: id,
            symbol: "BTC/USDT",
            marketClass: .crypto,
            category: category,
            direction: .long,
            predictedProbability: score / 100.0,
            status: status,
            netReturnPercent: status == .hitSL ? -1.0 : 2.0,
            rMultiple: status == .hitSL ? -1.0 : 2.0,
            strategyIds: ["ict_fvg"],
            hadMacroCatalyst: origin == .news,
            resolvedAtEpochSeconds: 1_760_100_000,
            lifecycleStatus: isLegacy ? nil : .resolved,
            isLegacyImmediateFill: isLegacy,
            origin: origin
        )
    }

    // MARK: - LiveCandleAggregatorTests

    func testLiveCandleAggregatorRolloverAndBadTickGuard() {
        let base: TimeInterval = 1_760_000_400 // aligned to 1H (divisible by 3600)
        let seed = makeBar(openTime: base - 3_600, open: 100, high: 102, low: 99, close: 100, isClosed: true)
        var agg = LiveCandleAggregator(timeframe: .h1, seed: seed, marketClass: .crypto)

        // First tick starts forming bar
        let u1 = agg.ingest(LiveTick(price: 101.0, epochSeconds: base + 10, volume: 10))
        if case .formingUpdated(let c) = u1 {
            XCTAssertFalse(c.isClosed)
            XCTAssertEqual(c.open, 101.0)
            XCTAssertEqual(c.high, 101.0)
            XCTAssertEqual(c.low, 101.0)
            XCTAssertEqual(c.close, 101.0)
            XCTAssertEqual(c.volume, 10)
        } else {
            XCTFail("Expected formingUpdated")
        }

        // Bad tick (>8% jump on crypto) rejected without mutating forming bar
        let bad = agg.ingest(LiveTick(price: 120.0, epochSeconds: base + 20, volume: 5))
        if case .rejected = bad {
            XCTAssertEqual(agg.formingCandle?.high, 101.0)
        } else {
            XCTFail("Expected bad tick rejection")
        }

        // Valid updates inside same bucket
        _ = agg.ingest(LiveTick(price: 103.0, epochSeconds: base + 60, volume: 4))
        _ = agg.ingest(LiveTick(price: 99.5, epochSeconds: base + 120, volume: 6))
        XCTAssertEqual(agg.formingCandle?.high, 103.0)
        XCTAssertEqual(agg.formingCandle?.low, 99.5)
        XCTAssertEqual(agg.formingCandle?.close, 99.5)
        XCTAssertEqual(agg.formingCandle?.volume, 20)

        // Rollover into next 1H bucket
        let roll = agg.ingest(LiveTick(price: 100.5, epochSeconds: base + 3_605, volume: 3))
        if case .rolledOver(let closed, let forming) = roll {
            XCTAssertTrue(closed.isClosed)
            XCTAssertEqual(closed.openTimeEpochSeconds, base)
            XCTAssertEqual(closed.close, 99.5)
            XCTAssertFalse(forming.isClosed)
            XCTAssertEqual(forming.openTimeEpochSeconds, base + 3_600)
            XCTAssertEqual(forming.open, 100.5)
        } else {
            XCTFail("Expected rolledOver")
        }
    }

    func testLiveCandleAggregatorOTCNilVolumeHonesty() {
        let base: TimeInterval = 1_760_000_400
        var agg = LiveCandleAggregator(timeframe: .h1, seed: nil, marketClass: .forex)
        let u = agg.ingest(LiveTick(price: 1.31002, epochSeconds: base + 15, volume: 0))
        if case .formingUpdated(let c) = u {
            XCTAssertNil(c.volume)
        } else {
            XCTFail("Expected formingUpdated")
        }
        // >2% jump on FX rejected
        let spike = agg.ingest(LiveTick(price: 1.36, epochSeconds: base + 30, volume: 0))
        if case .rejected = spike {
            XCTAssertEqual(agg.formingCandle?.close, 1.31002)
        } else {
            XCTFail("Expected FX >2% spike rejection")
        }
    }

    // MARK: - HistoryMergeTests

    func testHistoryMergeDedupeCapAndFormingDrop() {
        let step: TimeInterval = 3_600
        let base: TimeInterval = 1_760_000_000
        let now: TimeInterval = base + 10 * step

        let older = (0..<5).map { i in
            makeBar(openTime: base + Double(i) * step, open: 100, high: 105, low: 98, close: 102)
        }
        // Overlap at index 4 + newer + one forming bar closing after `now`
        var existing = (4..<9).map { i in
            makeBar(openTime: base + Double(i) * step, open: 100, high: 106, low: 97, close: 104)
        }
        existing.append(makeBar(openTime: base + 10 * step, open: 104, high: 108, low: 103, close: 107, isClosed: false))

        let merged = HistoryMerge.merge(existing: existing, older: older, serverNowEpochSeconds: now, cap: 6)
        XCTAssertEqual(merged.count, 6)
        XCTAssertTrue(merged.allSatisfy { $0.isClosed && $0.closeTimeEpochSeconds <= now })
        // Existing won on overlapping timestamp index 4 (close 104 vs older 102)
        let bar4 = merged.first { $0.openTimeEpochSeconds == base + 4 * step }
        XCTAssertEqual(bar4?.close, 104)
        // Sorted ascending and capped to newest 6 (indices 3..8)
        XCTAssertEqual(merged.first?.openTimeEpochSeconds, base + 3 * step)
        XCTAssertEqual(merged.last?.openTimeEpochSeconds, base + 8 * step)
    }

    // MARK: - ChartScaleRangeTests

    func testChartScaleRangeFlagsExtremeOffScaleWithoutStretchingAxis() {
        let base: TimeInterval = 1_760_000_000
        let candles = (0..<20).map { i in
            makeBar(openTime: base + Double(i) * 3_600, open: 59_000, high: 60_000, low: 58_000, close: 59_200)
        }
        let levels = TradeLevels(
            entryLow: 59_000,
            entryHigh: 59_300,
            entryMid: 59_150,
            stopLoss: 58_000,
            tp1: 61_500,
            tp2: 80_000, // Extreme >20% off-scale
            riskPercent: 1.94,
            reward1Percent: 3.97,
            reward2Percent: 35.2,
            riskRewardRatio: 2.04,
            tp2RiskRewardRatio: 18.1,
            isTP2Enabled: true
        )
        let result = ChartScaleRange.compute(candles: candles, levels: levels, traps: [])
        XCTAssertNotNil(result)
        // Scale must stay tightly around 58k-61.5k, NOT stretched to 80k
        XCTAssertLessThan(result!.maxPrice, 65_000)
        XCTAssertGreaterThan(result!.minPrice, 55_000)
        XCTAssertEqual(result!.offScaleOverlays.count, 1)
        XCTAssertEqual(result!.offScaleOverlays.first?.label, "Target 2")
    }

    // MARK: - DemoWalletEngineTests

    func testDemoWalletMarketSafeguardsStaleQuoteAndClosedMarket() {
        let wallet = DemoWallet(startingBalanceUSD: 1_000)
        // Saturday 12:00 UTC -> Forex market closed
        let saturdayUTC: TimeInterval = 1_776_513_600 // 2026-04-18 12:00 UTC (Saturday)
        let fxReq = DemoOrderRequest(
            symbol: "EUR/USD",
            marketClass: .forex,
            direction: .long,
            orderType: .market,
            entryPrice: 1.1000,
            stopLoss: 1.0950,
            target1: 1.1100
        )
        let closedRes = DemoWalletEngine.placeOrder(
            wallet: wallet,
            request: fxReq,
            liveQuotePrice: 1.1000,
            liveQuoteEpochSeconds: saturdayUTC - 5,
            nowEpochSeconds: saturdayUTC
        )
        if case .failure(.marketClosed(_, let suggestLimit)) = closedRes {
            XCTAssertTrue(suggestLimit)
        } else {
            XCTFail("Expected marketClosed rejection on Saturday FX market order")
        }

        // Crypto is 24/7, but quote older than 60s must be rejected unless allowStalePriceFill == true
        let btcReq = DemoOrderRequest(
            symbol: "BTC/USDT",
            marketClass: .crypto,
            direction: .long,
            orderType: .market,
            entryPrice: 60_000,
            stopLoss: 59_000,
            target1: 62_000,
            allowStalePriceFill: false
        )
        let staleRes = DemoWalletEngine.placeOrder(
            wallet: wallet,
            request: btcReq,
            liveQuotePrice: 60_000,
            liveQuoteEpochSeconds: saturdayUTC - 75,
            nowEpochSeconds: saturdayUTC
        )
        if case .failure(.staleLiveQuote(let age)) = staleRes {
            XCTAssertEqual(age, 75, accuracy: 0.1)
        } else {
            XCTFail("Expected staleLiveQuote rejection when quote age > 60s")
        }

        // Explicit confirmation overrides stale check
        let confirmedReq = DemoOrderRequest(
            symbol: "BTC/USDT",
            marketClass: .crypto,
            direction: .long,
            orderType: .market,
            entryPrice: 60_000,
            stopLoss: 59_000,
            target1: 62_000,
            allowStalePriceFill: true
        )
        let okRes = DemoWalletEngine.placeOrder(
            wallet: wallet,
            request: confirmedReq,
            liveQuotePrice: 60_100,
            liveQuoteEpochSeconds: saturdayUTC - 75,
            nowEpochSeconds: saturdayUTC
        )
        if case .success((_, let pos)) = okRes {
            // Fills cleanly at observed live price with zero synthetic spread
            XCTAssertEqual(pos.filledPrice, 60_100)
        } else {
            XCTFail("Expected confirmed stale fill to succeed")
        }
    }

    func testDemoWalletMarginReserveClampAndPerAssetPnL() {
        let now: TimeInterval = 1_776_175_200 // Tuesday 14:00 UTC (all markets open)
        let wallet = DemoWallet(startingBalanceUSD: 1_000)

        // Crypto 1x with 5% risk on tight stop requires > $1,000 notional -> must clamp to free margin ($1,000)
        let btcReq = DemoOrderRequest(
            symbol: "BTC/USDT",
            marketClass: .crypto,
            direction: .long,
            orderType: .market,
            entryPrice: 60_000,
            stopLoss: 59_700, // 0.5% stop -> 5% risk needs $10,000 notional -> clamped to $1,000 at 1x
            target1: 60_600,
            riskPercent: 5.0
        )
        let res = DemoWalletEngine.placeOrder(
            wallet: wallet,
            request: btcReq,
            liveQuotePrice: 60_000,
            liveQuoteEpochSeconds: now - 2,
            nowEpochSeconds: now
        )
        guard case .success((let w1, let pos)) = res else {
            XCTFail("Expected clamped BTC trade to open")
            return
        }
        XCTAssertTrue(pos.wasClampedToFreeMargin)
        XCTAssertEqual(pos.marginReservedUSD, 1_000, accuracy: 0.01)
        XCTAssertEqual(w1.freeMarginUSD, 0, accuracy: 0.01)

        // Close manually at +1% (+$10 on $1,000 notional)
        guard let (w2, closed) = DemoWalletEngine.closePositionManually(
            wallet: w1,
            positionId: pos.id,
            exitPrice: 60_600,
            nowEpochSeconds: now + 60
        ) else {
            XCTFail("Expected manual close to succeed")
            return
        }
        XCTAssertEqual(closed.realizedPnLUSD, 10.0, accuracy: 0.05)
        XCTAssertEqual(w2.reservedMarginUSD, 0, accuracy: 0.01)
        XCTAssertEqual(w2.cashBalanceUSD, 1_010.0, accuracy: 0.05)

        // Gold (Metals, 20x, 100 oz/lot) P&L check
        let goldReq = DemoOrderRequest(
            symbol: "XAU/USD",
            marketClass: .metals,
            direction: .long,
            orderType: .market,
            entryPrice: 2_500,
            stopLoss: 2_490, // $10/oz stop
            target1: 2_520,  // $20/oz target (+2R)
            riskPercent: 1.0 // $10.10 risk -> 1.01 oz -> 0.0101 lots
        )
        guard case .success((_, let goldPos)) = DemoWalletEngine.placeOrder(
            wallet: w2,
            request: goldReq,
            liveQuotePrice: 2_500,
            liveQuoteEpochSeconds: now + 65,
            nowEpochSeconds: now + 70
        ) else {
            XCTFail("Expected gold order to open")
            return
        }
        let goldTargetPnL = DemoWalletEngine.pnlUSD(for: goldPos, markPrice: 2_520)
        XCTAssertEqual(goldTargetPnL, 20.20, accuracy: 0.1)
    }

    func testDemoWalletLimitFillBarSLOnlyAndSameBarSLFirst() {
        let base: TimeInterval = 1_776_175_200
        let wallet = DemoWallet(startingBalanceUSD: 1_000)

        let limitReq = DemoOrderRequest(
            symbol: "BTC/USDT",
            marketClass: .crypto,
            direction: .long,
            orderType: .limit,
            entryPrice: 60_000,
            entryLow: 59_900,
            entryHigh: 60_100,
            stopLoss: 59_000,
            target1: 62_000,
            target2: 64_000,
            exitTarget: .target1,
            riskPercent: 1.0,
            limitExpiryEpochSeconds: base + 4 * 3_600
        )
        guard case .success((let w1, let pos)) = DemoWalletEngine.placeOrder(
            wallet: wallet,
            request: limitReq,
            liveQuotePrice: 60_500,
            liveQuoteEpochSeconds: base,
            nowEpochSeconds: base
        ) else {
            XCTFail("Expected limit order to be placed")
            return
        }
        XCTAssertEqual(pos.status, .pendingLimit)

        // Fill bar touches BOTH entry and target1 (not SL) -> must remain OPEN (TP ignored on fill bar!)
        let fillBar = makeBar(openTime: base + 3_600, open: 60_200, high: 62_500, low: 59_950, close: 61_000)
        let r1 = DemoWalletEngine.evaluateClosedBar(wallet: w1, positionId: pos.id, bar: fillBar)
        XCTAssertEqual(r1.position?.status, .open)

        // Next bar touches BOTH SL (59_000) and Target 1 (62_000) -> Pessimistic Same-Bar SL-First!
        let whipsawBar = makeBar(openTime: base + 2 * 3_600, open: 61_000, high: 62_500, low: 58_800, close: 61_800)
        let r2 = DemoWalletEngine.evaluateClosedBar(wallet: r1.wallet, positionId: pos.id, bar: whipsawBar)
        XCTAssertEqual(r2.position?.status, .closedStopLoss)
        XCTAssertEqual(r2.position?.exitPrice, 59_000)

        // Test limit expiry
        let expReq = DemoOrderRequest(
            symbol: "BTC/USDT",
            marketClass: .crypto,
            direction: .long,
            orderType: .limit,
            entryPrice: 55_000,
            stopLoss: 54_000,
            target1: 57_000,
            limitExpiryEpochSeconds: base + 3_600
        )
        guard case .success((let wExp, let pExp)) = DemoWalletEngine.placeOrder(
            wallet: wallet,
            request: expReq,
            liveQuotePrice: 60_000,
            liveQuoteEpochSeconds: base,
            nowEpochSeconds: base
        ) else {
            XCTFail("Expected second limit order")
            return
        }
        let lateBar = makeBar(openTime: base + 3_600, open: 60_000, high: 60_500, low: 59_500, close: 60_100)
        let rExp = DemoWalletEngine.evaluateClosedBar(wallet: wExp, positionId: pExp.id, bar: lateBar)
        XCTAssertEqual(rExp.position?.status, .expired)
        XCTAssertEqual(rExp.wallet.reservedMarginUSD, 0, accuracy: 0.01)
    }

    func testDemoWalletEditSLTargetsAndBreakevenValidation() {
        let now: TimeInterval = 1_776_175_200
        let wallet = DemoWallet(startingBalanceUSD: 1_000)
        let req = DemoOrderRequest(
            symbol: "BTC/USDT",
            marketClass: .crypto,
            direction: .long,
            orderType: .market,
            entryPrice: 60_000,
            stopLoss: 59_000,
            target1: 62_000,
            target2: 64_000
        )
        guard case .success((let w1, let pos)) = DemoWalletEngine.placeOrder(
            wallet: wallet,
            request: req,
            liveQuotePrice: 60_000,
            liveQuoteEpochSeconds: now,
            nowEpochSeconds: now
        ) else {
            XCTFail("Expected open trade")
            return
        }

        // Invalid SL above entry for Long -> rejected
        if case .success = DemoWalletEngine.updateStopLoss(wallet: w1, positionId: pos.id, newStopLoss: 60_500) {
            XCTFail("SL above entry for Long must fail")
        }

        // Move SL to breakeven -> succeeds
        guard case .success((let w2, let pBE)) = DemoWalletEngine.moveStopLossToBreakeven(wallet: w1, positionId: pos.id) else {
            XCTFail("Expected breakeven SL to succeed")
            return
        }
        XCTAssertEqual(pBE.stopLoss, 60_000)
        XCTAssertTrue(pBE.isStopLossAtBreakeven)

        // Invalid Target 2 <= Target 1 -> rejected
        if case .success = DemoWalletEngine.updateTargets(wallet: w2, positionId: pos.id, newTarget1: 62_500, newTarget2: 62_000) {
            XCTFail("Target 2 <= Target 1 for Long must fail")
        }

        // Valid targets update
        guard case .success((_, let pT)) = DemoWalletEngine.updateTargets(
            wallet: w2,
            positionId: pos.id,
            newTarget1: 62_500,
            newTarget2: 65_000,
            newExitTarget: .target2
        ) else {
            XCTFail("Expected valid targets update")
            return
        }
        XCTAssertEqual(pT.target1, 62_500)
        XCTAssertEqual(pT.target2, 65_000)
        XCTAssertEqual(pT.exitTarget, .target2)
    }

    // MARK: - ScanSchedulePolicyTests

    func testScanSchedulePolicyLowPowerAndUsageMath() {
        XCTAssertEqual(ScanSchedulePolicy.effectiveIntervalMinutes(configuredMinutes: 5, isLowPowerMode: false), 5)
        XCTAssertEqual(ScanSchedulePolicy.effectiveIntervalMinutes(configuredMinutes: 5, isLowPowerMode: true), 30)
        XCTAssertEqual(ScanSchedulePolicy.effectiveIntervalMinutes(configuredMinutes: 60, isLowPowerMode: true), 60)
        XCTAssertEqual(ScanSchedulePolicy.effectiveIntervalMinutes(configuredMinutes: 0, isLowPowerMode: true), 0)

        XCTAssertTrue(ScanSchedulePolicy.shouldScanOnOpen(enabled: true, lastScanEpochSeconds: nil, nowEpochSeconds: 1_000))
        XCTAssertFalse(ScanSchedulePolicy.shouldScanOnOpen(enabled: true, lastScanEpochSeconds: 950, nowEpochSeconds: 1_000))
        XCTAssertTrue(ScanSchedulePolicy.shouldScanOnOpen(enabled: true, lastScanEpochSeconds: 800, nowEpochSeconds: 1_000))
        XCTAssertFalse(ScanSchedulePolicy.shouldScanOnOpen(enabled: false, lastScanEpochSeconds: nil, nowEpochSeconds: 1_000))

        let usage = ScanSchedulePolicy.estimateDailyUsage(symbolCount: 10, configuredMinutes: 30, isLowPowerMode: false)
        XCTAssertEqual(usage.scansPerDay, 24) // 12h * 60 / 30
        XCTAssertEqual(usage.estimatedRequestsPerDay, 480) // 24 * 10 * 2
        XCTAssertFalse(usage.lowPowerClamped)

        let lpUsage = ScanSchedulePolicy.estimateDailyUsage(symbolCount: 10, configuredMinutes: 5, isLowPowerMode: true)
        XCTAssertEqual(lpUsage.effectiveIntervalMinutes, 30)
        XCTAssertTrue(lpUsage.lowPowerClamped)
    }

    // MARK: - WinRateBreakdownTests & LegacyOriginDecodeTests

    func testWinRateBreakdownByOriginAndStrengthBucketBoundaries() {
        let records: [SignalOutcomeRecord] = [
            makeOutcome(id: "s1", category: .strongSignal, origin: .scanner, score: 59.99, status: .hitTP1),
            makeOutcome(id: "s2", category: .strongSignal, origin: .scanner, score: 60.00, status: .hitSL),
            makeOutcome(id: "s3", category: .strongSignal, origin: .scanner, score: 69.99, status: .hitTP2),
            makeOutcome(id: "s4", category: .strongSignal, origin: .scanner, score: 70.00, status: .hitTP1),
            makeOutcome(id: "s5", category: .strongSignal, origin: .scanner, score: 79.99, status: .hitSL),
            makeOutcome(id: "s6", category: .strongSignal, origin: .scanner, score: 80.00, status: .hitTP2),
            makeOutcome(id: "w1", category: .weakSignal, origin: .scanner, score: 62.00, status: .hitSL),
            makeOutcome(id: "n1", category: .strongSignal, origin: .news, score: 74.00, status: .hitTP1)
        ]
        let trapItems: [TrapOutcomeSummaryItem] = [
            TrapOutcomeSummaryItem(id: "trap_1", outcome: .respected),
            TrapOutcomeSummaryItem(id: "trap_2", outcome: .invalidated)
        ]

        let byOrigin = WinRateBreakdown.byOrigin(records: records, trapOutcomes: trapItems)
        XCTAssertEqual(byOrigin.count, 3)

        let strong = byOrigin[0]
        XCTAssertEqual(strong.group, .strongSignals)
        XCTAssertEqual(strong.wins, 4)
        XCTAssertEqual(strong.losses, 2)
        XCTAssertEqual(strong.totalResolved, 6)
        XCTAssertNotNil(strong.winRateCI)

        let traps = byOrigin[1]
        XCTAssertEqual(traps.group, .trapsAndFiltered)
        XCTAssertEqual(traps.positiveCountLabel, "Worked")
        XCTAssertEqual(traps.negativeCountLabel, "Failed")
        XCTAssertEqual(traps.wins, 1)   // trap_1 respected
        XCTAssertEqual(traps.losses, 2) // w1 hitSL + trap_2 invalidated
        XCTAssertEqual(traps.totalResolved, 3)

        let news = byOrigin[2]
        XCTAssertEqual(news.group, .newsSetups)
        XCTAssertEqual(news.wins, 1)
        XCTAssertEqual(news.losses, 0)

        // Exact bucket boundaries: 59.99 -> 50-59; 60 & 69.99 -> 60-69; 70 & 79.99 -> 70-79; 80 -> 80+
        let strongOnly = records.filter { $0.origin == .scanner && $0.category == .strongSignal }
        let buckets = WinRateBreakdown.byStrengthBucket(records: strongOnly)
        XCTAssertEqual(buckets.count, 4)
        XCTAssertEqual(buckets[0].totalResolved, 1) // 59.99
        XCTAssertEqual(buckets[1].totalResolved, 2) // 60.00, 69.99
        XCTAssertEqual(buckets[2].totalResolved, 2) // 70.00, 79.99
        XCTAssertEqual(buckets[3].totalResolved, 1) // 80.00

        // Empty buckets return "No trades yet"
        let emptyBuckets = WinRateBreakdown.byStrengthBucket(records: [])
        XCTAssertTrue(emptyBuckets.allSatisfy { $0.summaryText == "No trades yet" })
    }

    func testLegacyOriginDecodeDefaultsToScanner() throws {
        // Legacy JSON missing `origin` key MUST decode cleanly with `.scanner`
        let json = """
        {
          "signalId": "legacy-1",
          "symbol": "EUR/USD",
          "marketClass": "forex",
          "category": "STRONG_SIGNAL",
          "direction": "long",
          "predictedProbability": 0.72,
          "status": "hitTP1",
          "netReturnPercent": 1.4,
          "rMultiple": 2.0,
          "strategyIds": ["ict_fvg"],
          "hadMacroCatalyst": false,
          "resolvedAtEpochSeconds": 1760000000
        }
        """
        let decoded = try JSONDecoder().decode(SignalOutcomeRecord.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.origin, .scanner)
        XCTAssertTrue(decoded.effectiveIsLegacyImmediateFill)
    }

    // MARK: - FormingCandleNeverReachesEngineTests

    func testFormingCandleNeverReachesSignalEngineHygieneOrEvaluator() {
        let base: TimeInterval = 1_760_000_400
        let step: TimeInterval = 3_600
        let now: TimeInterval = base + 60 * step
        let closedBars = (0..<60).map { i in
            let p = 60_000.0 + Double(i) * 40.0
            return makeBar(openTime: base + Double(i) * step, open: p, high: p + 80, low: p - 50, close: p + 30)
        }

        // Produce a live forming bar from LiveCandleAggregator with an extreme move
        var agg = LiveCandleAggregator(timeframe: .h1, seed: closedBars.last, marketClass: .crypto)
        let update = agg.ingest(LiveTick(price: 65_000, epochSeconds: now + 120, volume: 10))
        guard case .formingUpdated(let formingBar) = update else {
            XCTFail("Expected forming bar")
            return
        }
        XCTAssertFalse(formingBar.isClosed)

        let btc = WatchlistDefaults.descriptor(for: "BTC/USDT")!
        let outWithoutForming = SignalEngine.analyze(
            asset: btc,
            rawEntryCandles: closedBars,
            rawHTFCandles: [],
            timeframe: .h1,
            dataProvider: "Test",
            serverNowEpochSeconds: now + 120
        )
        let outWithForming = SignalEngine.analyze(
            asset: btc,
            rawEntryCandles: closedBars + [formingBar],
            rawHTFCandles: [],
            timeframe: .h1,
            dataProvider: "Test",
            serverNowEpochSeconds: now + 120
        )

        // Forming bar MUST be dropped by hygiene and produce bit-for-bit identical SignalEngine output
        XCTAssertEqual(outWithForming.hygieneReport.droppedOpenBars, 1)
        XCTAssertEqual(outWithoutForming.hygieneReport.closedCount, outWithForming.hygieneReport.closedCount)
        XCTAssertEqual(outWithoutForming.signal, outWithForming.signal)

        // Forming bar MUST also be ignored by PassiveOutcomeEvaluator
        if let sig = outWithoutForming.signal {
            let evalWithout = PassiveOutcomeEvaluator.evaluate(signal: sig, subsequentClosedCandles: [])
            let evalWith = PassiveOutcomeEvaluator.evaluate(signal: sig, subsequentClosedCandles: [formingBar])
            XCTAssertEqual(evalWithout.status, evalWith.status)
        }
    }
}
