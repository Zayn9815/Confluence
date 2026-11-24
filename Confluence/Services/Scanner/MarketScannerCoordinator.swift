import Foundation
import BackgroundTasks
import SwiftUI
import SignalEngine

public enum AlertBannerKind: Sendable, Equatable {
    case strongSignal(TradeDirection)
    case trapAlert
    case macroRelease
}

public struct FloatingAlertBanner: Identifiable, Sendable, Equatable {
    public let id = UUID()
    public let kind: AlertBannerKind
    public let title: String
    public let subtitle: String
    public let targetSignalId: String?
}

public struct FeedHealthEntry: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let healthy: Bool
    public let latencyMs: Double
    public let detail: String
}

@MainActor
@Observable
public final class MarketScannerCoordinator {
    public static let backgroundTaskIdentifier = "com.bilal.confluence.refresh"

    public var settings: AppSettingsStore
    public let store: ConfluenceDataStore

    private let http: URLSessionHTTPClient
    private let cryptoRouter: CryptoOHLCVRouter
    private let tradFiRouter: TradFiOHLCVRouter
    private let okxPositioning: OKXPositioningAdapter
    private let cftcCOT: CFTCCOTAdapter
    private let calendarService: EconomicCalendarService
    private let newsService: BreakingNewsService
    private let geminiClient: GeminiJudgeClient

    // Live terminal state (strictly real fetched / computed data — zero mock signals or prints)
    public var signals: [TradeSignal] = []
    public var activeTraps: [BehavioralTrap] = []
    public var calendarEvents: [EconomicEvent] = []
    public var calendarClusters: [MacroClusterImpulse] = []
    public var calendarSourceLabel: String = "Not Scanned Yet"
    public var breakingNews: [BreakingNewsItem] = []
    public var fearGreed: FearGreedSnapshot?
    public var calibrationSummary: CalibrationSummary = PassiveOutcomeEvaluator.summarize(records: [])
    public var outcomeRecords: [SignalOutcomeRecord] = []

    // Scanning & Diagnostics state
    public var isScanning: Bool = false
    public var scanProgressByMarket: [MarketClass: String] = [:]
    public var lastScanDate: Date?
    public var lastScanError: String?
    public var scheduledPreNewsCount: Int = 0
    public var notificationStatusDescription: String = "Checking..."
    public var activeBanner: FloatingAlertBanner?
    public var newlyArrivedSignalIds: Set<String> = []
    public var feedHealthResults: [FeedHealthEntry] = []
    public var isCheckingHealth: Bool = false
    public var geminiDailyCallsUsed: Int = 0

    public init(settings: AppSettingsStore, store: ConfluenceDataStore) {
        self.settings = settings
        self.store = store
        let client = URLSessionHTTPClient()
        self.http = client
        self.cryptoRouter = CryptoOHLCVRouter(http: client)
        self.tradFiRouter = TradFiOHLCVRouter(http: client)
        self.okxPositioning = OKXPositioningAdapter(http: client)
        self.cftcCOT = CFTCCOTAdapter(http: client)
        self.calendarService = EconomicCalendarService(http: client)
        self.newsService = BreakingNewsService(http: client)
        self.geminiClient = GeminiJudgeClient(http: client)

        loadPersistedState()
    }

    public func loadPersistedState() {
        self.signals = store.fetchSignals(limit: 150)
        self.outcomeRecords = store.fetchOutcomeRecords()
        self.calibrationSummary = PassiveOutcomeEvaluator.summarize(records: outcomeRecords)
        Task {
            self.geminiDailyCallsUsed = await geminiClient.dailyUsageCount()
            await refreshNotificationStatus()
        }
    }

    public func refreshNotificationStatus() async {
        let status = await PreNewsNotificationScheduler.shared.authorizationStatus()
        switch status {
        case .authorized: notificationStatusDescription = "Authorized"
        case .provisional: notificationStatusDescription = "Provisional"
        case .denied: notificationStatusDescription = "Denied (Enable in iOS Settings)"
        case .notDetermined: notificationStatusDescription = "Not Requested"
        case .ephemeral: notificationStatusDescription = "Ephemeral"
        @unknown default: notificationStatusDescription = "Unknown"
        }
    }

    public func requestNotifications() async {
        _ = await PreNewsNotificationScheduler.shared.requestAuthorizationIfNeeded()
        await refreshNotificationStatus()
    }

    /// Nearest upcoming exact-clock high-impact event within 60 minutes (for sticky Signals header strip).
    public var imminentPreNewsEvent: PreNewsShieldStatus? {
        let now = Date().timeIntervalSince1970
        let allActive = settings.activeWatchlistAssets
        for asset in allActive {
            if let shield = MacroSurpriseEngine.preNewsShield(
                for: asset,
                events: calendarEvents,
                nowEpochSeconds: now,
                blackoutMinutesBefore: 15,
                bannerHorizonMinutes: 60,
                minimumImportance: .high
            ) {
                return shield
            }
        }
        return nil
    }

    public func scanAllMarkets(isBackground: Bool = false) async {
        guard !isScanning else { return }
        isScanning = true
        lastScanError = nil
        newlyArrivedSignalIds = []
        scanProgressByMarket = [:]

        defer {
            isScanning = false
            lastScanDate = Date()
        }

        let assets = settings.activeWatchlistAssets
        let twelveKey = await KeychainStore.shared.read(.twelveDataAPIKey)
        let finnhubKey = await KeychainStore.shared.read(.finnhubAPIKey)
        let geminiKey = await KeychainStore.shared.read(.geminiAPIKey)

        // 1. Refresh Economic Calendar & Breaking News Radar concurrently
        if settings.payload.economicCalendarEnabled {
            let calResult = await calendarService.fetchCalendarEvents(minimumImportance: .medium)
            self.calendarEvents = calResult.events
            self.calendarSourceLabel = calResult.sourceLabel
            let nowEpoch = Date().timeIntervalSince1970
            self.calendarClusters = MacroSurpriseEngine.buildClusters(events: calResult.events, nowEpochSeconds: nowEpoch)
            self.scheduledPreNewsCount = await PreNewsNotificationScheduler.shared.reschedulePreNewsCountdowns(
                events: calResult.events,
                settings: settings.payload,
                nowEpochSeconds: nowEpoch
            )
        }

        if settings.payload.breakingNewsRadarEnabled {
            let newsRes = await newsService.fetchNewsAndSentiment(finnhubAPIKey: finnhubKey)
            self.breakingNews = newsRes.items
            self.fearGreed = newsRes.fearGreed
        }

        // 2. Build out-of-sample reliability weights from passive calibration history
        var weights: [String: Double] = [:]
        for stat in calibrationSummary.strategyRankings where stat.totalResolved >= 5 {
            weights[stat.strategyId] = max(0.65, min(1.40, 0.5 + stat.winRate))
        }
        let engineConfig = settings.buildEngineConfig(reliabilityWeights: weights)
        let dedupHistory = store.recentDeduplicationHistory()
        let entryTF = settings.payload.entryTimeframe
        let htfTF = settings.payload.htfTimeframe
        let cryptoPrimary = settings.payload.cryptoPrimaryExchange
        let positioningOn = settings.payload.positioningFeedsEnabled

        // 3. Scan each enabled asset & update passive outcomes against latest closed candles
        var scannedSignals: [TradeSignal] = []
        var scannedTraps: [BehavioralTrap] = []
        var latestClosedCandlesBySymbol: [String: [Candle]] = [:]
        var errors: [String] = []

        for market in MarketClass.allCases where settings.payload.enabledMarkets.contains(market) {
            let marketAssets = assets.filter { $0.marketClass == market }
            guard !marketAssets.isEmpty else { continue }
            scanProgressByMarket[market] = "Scanning 0/\(marketAssets.count)..."

            var done = 0
            for asset in marketAssets {
                do {
                    let entryRes: OHLCVFetchResult
                    let htfRes: OHLCVFetchResult

                    if asset.marketClass == .crypto {
                        async let eTask = cryptoRouter.fetchCandles(asset: asset, timeframe: entryTF, primary: cryptoPrimary)
                        async let hTask = cryptoRouter.fetchCandles(asset: asset, timeframe: htfTF, primary: cryptoPrimary)
                        (entryRes, htfRes) = try await (eTask, hTask)
                    } else {
                        async let eTask = tradFiRouter.fetchCandles(asset: asset, timeframe: entryTF, twelveDataKey: twelveKey)
                        async let hTask = tradFiRouter.fetchCandles(asset: asset, timeframe: htfTF, twelveDataKey: twelveKey)
                        (entryRes, htfRes) = try await (eTask, hTask)
                    }

                    // Positioning feeds (keyless OKX v5 or weekly cached CFTC COT)
                    var okxSnap: OKXDerivativesSnapshot? = nil
                    var cotRecords: [CFTCCOTRecord] = []
                    if positioningOn {
                        if let swapId = asset.okxSwapInstId {
                            let oiPeriod = (entryTF == .d1) ? "1Dutc" : (entryTF == .h4 ? "4H" : "1H")
                            okxSnap = try? await okxPositioning.fetchSnapshot(instId: swapId, period: oiPeriod)
                        } else if let code = asset.cftcContractCode,
                                  let dsRaw = asset.cftcDataset,
                                  let ds = CFTCDatasetKind(rawValue: dsRaw) {
                            cotRecords = (try? await cftcCOT.records(for: code, dataset: ds)) ?? []
                        }
                    }

                    let clockSkew = await http.estimatedClockSkewSeconds()
                    let serverNow = Date().timeIntervalSince1970 + clockSkew
                    latestClosedCandlesBySymbol[asset.symbol] = entryRes.candles

                    let output = SignalEngine.analyze(
                        asset: asset,
                        rawEntryCandles: entryRes.candles,
                        rawHTFCandles: htfRes.candles,
                        timeframe: entryTF,
                        htfTimeframe: htfTF,
                        okxDerivatives: okxSnap,
                        cftcCOTRecords: cotRecords,
                        calendarEvents: calendarEvents,
                        config: engineConfig,
                        dataProvider: entryRes.providerName,
                        serverNowEpochSeconds: serverNow,
                        clockSkewSeconds: clockSkew
                    )

                    scannedTraps.append(contentsOf: output.activeTraps)

                    if var signal = output.signal {
                        let isNew = !ConfluenceScorer.shouldSuppressDuplicate(
                            fingerprint: signal.fingerprint,
                            symbol: signal.symbol,
                            direction: signal.direction,
                            nowEpochSeconds: serverNow,
                            recentHistory: dedupHistory,
                            cooldownSeconds: engineConfig.signalCooldownSeconds
                        )

                        // Optional Gemini 4 Hydrogen second-opinion ONLY on new Strong Signals or Trap Alerts when enabled
                        if isNew,
                           settings.payload.geminiEnabled,
                           let key = geminiKey, !key.isEmpty,
                           (signal.category == .strongSignal || signal.category == .trapAlert) {
                            if let judgment = try? await geminiClient.judgeSignal(
                                signal,
                                apiKey: key,
                                dailyLimit: settings.payload.geminiDailyCallLimit
                            ) {
                                signal = signal.withAIJudgment(judgment, threshold: settings.payload.geminiConfirmationThreshold)
                                self.geminiDailyCallsUsed = await geminiClient.dailyUsageCount()
                            }
                        }

                        store.upsertSignal(signal)
                        scannedSignals.append(signal)

                        if isNew && (signal.category == .strongSignal || signal.category == .trapAlert) {
                            newlyArrivedSignalIds.insert(signal.id)
                            await dispatchArrivalFeedback(for: signal, isBackground: isBackground)
                        }
                    }
                } catch {
                    errors.append("\(asset.symbol): \(error.localizedDescription)")
                }

                done += 1
                scanProgressByMarket[market] = "\(done)/\(marketAssets.count) done"
            }
        }

        // 4. Passively evaluate prior signals against newly fetched closed candles (zero lookahead)
        let persisted = store.fetchSignals(limit: 200)
        for prior in persisted where prior.category == .strongSignal || prior.category == .trapAlert {
            guard let freshBars = latestClosedCandlesBySymbol[prior.symbol], !freshBars.isEmpty else { continue }
            let outcome = PassiveOutcomeEvaluator.evaluate(signal: prior, subsequentClosedCandles: freshBars)
            if outcome.status != .pending {
                store.updateOutcome(outcome)
            }
        }

        self.activeTraps = scannedTraps
        self.signals = store.fetchSignals(limit: 150)
        self.outcomeRecords = store.fetchOutcomeRecords()
        self.calibrationSummary = PassiveOutcomeEvaluator.summarize(records: outcomeRecords)
        if !errors.isEmpty {
            self.lastScanError = errors.prefix(2).joined(separator: " • ")
        }
    }

    public func refreshCOTManually() async {
        try? await cftcCOT.refreshAllTrackedContracts()
    }

    public func runFeedHealthCheck() async {
        guard !isCheckingHealth else { return }
        isCheckingHealth = true
        defer { isCheckingHealth = false }

        var results: [FeedHealthEntry] = []
        let btc = WatchlistDefaults.descriptor(for: "BTC/USDT")!
        let gold = WatchlistDefaults.descriptor(for: "XAU/USD")!
        let twelveKey = await KeychainStore.shared.read(.twelveDataAPIKey)

        // 1. Crypto OHLCV
        do {
            let res = try await cryptoRouter.fetchCandles(asset: btc, timeframe: .h1, limit: 10, primary: settings.payload.cryptoPrimaryExchange)
            results.append(FeedHealthEntry(name: "Crypto OHLCV (\(res.providerName))", healthy: true, latencyMs: res.latencyMs, detail: "\(res.candles.count) bars"))
        } catch {
            results.append(FeedHealthEntry(name: "Crypto OHLCV", healthy: false, latencyMs: 0, detail: error.localizedDescription))
        }

        // 2. FX / Gold / Equities OHLCV
        do {
            let res = try await tradFiRouter.fetchCandles(asset: gold, timeframe: .h1, twelveDataKey: twelveKey)
            results.append(FeedHealthEntry(name: "Metals/FX/Stocks (\(res.providerName))", healthy: true, latencyMs: res.latencyMs, detail: "\(res.candles.count) bars"))
        } catch {
            results.append(FeedHealthEntry(name: "Metals/FX/Stocks OHLCV", healthy: false, latencyMs: 0, detail: error.localizedDescription))
        }

        // 3. OKX Derivatives Positioning
        let okxStart = Date()
        do {
            let snap = try await okxPositioning.fetchSnapshot(instId: "BTC-USDT-SWAP", period: "1H", forceRefresh: true)
            let ms = Date().timeIntervalSince(okxStart) * 1000
            results.append(FeedHealthEntry(name: "OKX Funding & OI", healthy: true, latencyMs: ms, detail: "Funding \(String(format: "%.4f%%", snap.currentFundingRate * 100))"))
        } catch {
            results.append(FeedHealthEntry(name: "OKX Funding & OI", healthy: false, latencyMs: 0, detail: error.localizedDescription))
        }

        // 4. CFTC COT Socrata JSON
        let cotStart = Date()
        do {
            let recs = try await cftcCOT.records(for: "088691", dataset: .disaggregatedFuturesOnly, forceRefresh: true)
            let ms = Date().timeIntervalSince(cotStart) * 1000
            results.append(FeedHealthEntry(name: "CFTC COT Socrata JSON", healthy: !recs.isEmpty, latencyMs: ms, detail: "\(recs.count) weekly reports"))
        } catch {
            results.append(FeedHealthEntry(name: "CFTC COT Socrata JSON", healthy: false, latencyMs: 0, detail: error.localizedDescription))
        }

        // 5. Economic Calendar
        let calStart = Date()
        let cal = await calendarService.fetchCalendarEvents(minimumImportance: .medium)
        let calMs = Date().timeIntervalSince(calStart) * 1000
        results.append(FeedHealthEntry(name: "Economic Calendar (\(cal.sourceLabel))", healthy: !cal.events.isEmpty, latencyMs: calMs, detail: "\(cal.events.count) events"))

        // 6. Breaking News Radar
        let newsStart = Date()
        let finnhubKey = await KeychainStore.shared.read(.finnhubAPIKey)
        let news = await newsService.fetchNewsAndSentiment(finnhubAPIKey: finnhubKey)
        let newsMs = Date().timeIntervalSince(newsStart) * 1000
        results.append(FeedHealthEntry(name: "Breaking News & Sentiment", healthy: !news.items.isEmpty, latencyMs: newsMs, detail: "\(news.items.count) headlines"))

        self.feedHealthResults = results
    }

    private func dispatchArrivalFeedback(for signal: TradeSignal, isBackground: Bool) async {
        if isBackground {
            await PreNewsNotificationScheduler.shared.postSignalNotification(signal, settings: settings.payload)
        } else {
            let bannerKind: AlertBannerKind = (signal.category == .trapAlert) ? .trapAlert : .strongSignal(signal.direction)
            let title: String
            if signal.category == .trapAlert, let td = signal.trapDirection {
                title = "\(td.rawValue) · \(signal.symbol)"
            } else {
                title = "\(signal.direction.rawValue.uppercased()) \(signal.symbol) · \(Int(signal.confidencePercent.rounded()))%"
            }
            self.activeBanner = FloatingAlertBanner(
                kind: bannerKind,
                title: title,
                subtitle: signal.psychologyReport.whatHappened,
                targetSignalId: signal.id
            )

            let audioKind: AlertAudioKind = (signal.category == .trapAlert)
                ? .trapWarning
                : .tradeSignal(settings.payload.soundPreset)
            let soundAllowed = (signal.category == .trapAlert)
                ? (settings.payload.inAppSignalSoundEnabled && settings.payload.trapAlertSoundEnabled)
                : settings.payload.inAppSignalSoundEnabled

            SignalSoundEngine.shared.playAlert(
                kind: audioKind,
                soundEnabled: soundAllowed,
                hapticsEnabled: settings.payload.hapticsEnabled
            )
        }
    }

    // MARK: - BGAppRefreshTask Registration & Scheduling

    public func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.backgroundTaskIdentifier, using: nil) { [weak self] task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            nonisolated(unsafe) let boxedTask = refreshTask
            let work = Task { @MainActor [weak self] in
                guard let self else {
                    boxedTask.setTaskCompleted(success: false)
                    return
                }
                self.scheduleNextBackgroundRefresh()
                await self.scanAllMarkets(isBackground: true)
                boxedTask.setTaskCompleted(success: true)
            }
            refreshTask.expirationHandler = {
                work.cancel()
            }
        }
    }

    public func scheduleNextBackgroundRefresh() {
        guard settings.payload.backgroundRefreshEnabled else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundTaskIdentifier)
            return
        }
        let req = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        let interval = TimeInterval(max(15, settings.payload.backgroundRefreshIntervalMinutes) * 60)
        req.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        try? BGTaskScheduler.shared.submit(req)
    }
}
