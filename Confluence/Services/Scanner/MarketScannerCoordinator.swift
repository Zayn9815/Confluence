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
    public let diagnosticLog: DiagnosticLogStore
    public let crashLogStore: CrashLogStore

    private let http: URLSessionHTTPClient
    private let twelveData: TwelveDataAdapter
    private let cryptoRouter: CryptoOHLCVRouter
    private let tradFiRouter: TradFiOHLCVRouter
    private let okxPositioning: OKXPositioningAdapter
    private let cftcCOT: CFTCCOTAdapter
    private let calendarService: EconomicCalendarService
    private let newsService: BreakingNewsService
    private let geminiClient: GeminiJudgeClient
    private let deepseekClient: OpenAICompatibleJudgeClient
    private let openRouterClient: OpenAICompatibleJudgeClient
    private var dismissedSignalFingerprints: Set<String> = []

    // Live terminal state (strictly real fetched / computed data — zero mock signals or prints)
    public var signals: [TradeSignal] = []
    public var activeTraps: [BehavioralTrap] = []
    public var calendarEvents: [EconomicEvent] = []
    public var calendarClusters: [MacroClusterImpulse] = []
    public var calendarSourceLabel: String = "Not Scanned Yet"
    public var breakingNews: [BreakingNewsItem] = []
    public var fearGreed: FearGreedSnapshot?
    public var headlineCalibrationSummary: CalibrationSummary = PassiveOutcomeEvaluator.summarize(records: [], filter: .headlineFixed)
    public var calibrationSummary: CalibrationSummary = PassiveOutcomeEvaluator.summarize(records: [])
    public var confidenceCalibrator: ConfidenceCalibrator = .inactive
    public var outcomeRecords: [SignalOutcomeRecord] = []
    public var outcomeBySignalId: [String: SignalOutcomeRecord] = [:]
    public var strategyBreakdowns: [StrategyDiagnosticBreakdown] = []
    public var tradeLedger: [TradeLedgerSnapshot] = []
    public var trapLogs: [TrapLogSnapshot] = []
    public var journalEntries: [JournalEntrySnapshot] = []
    public var journalSummary: JournalSummaryStats = JournalSummaryStats.compute(entries: [], totalSystemStrongSignals: 0)
    public var correlationWarningsByFingerprint: [String: [CorrelationPairWarning]] = [:]
    public var netExposureSummary: NetExposureSummary = NetExposureSummary(exposures: [], concentratedClusters: [], totalStrongSignals: 0)
    private var cachedClosedCandlesBySymbol: [String: [Candle]] = [:]

    // Notification Bell Inbox & Deep-Link Routing
    public var notifications: [NotificationItemSnapshot] = []
    public var unreadNotificationCount: Int = 0
    public var isNotificationInboxPresented: Bool = false
    public var pendingDeepLink: NavigationDeepLink?
    public var highlightedSignalFingerprint: String?

    // Scanning, Quota & Diagnostics state
    public var isScanning: Bool = false
    public var scanProgressByMarket: [MarketClass: String] = [:]
    public var lastScanDate: Date?
    public var lastScanError: String?
    /// Set when a foreground scan is aborted before any network call (e.g. zero strategies enabled).
    public var scanBlockedMessage: String?
    public static let noStrategiesEnabledMessage = "Enable at least 1 strategy in Signal Rules & AI before scanning."
    public var scheduledPreNewsCount: Int = 0
    public var notificationStatusDescription: String = "Checking..."
    public var activeBanner: FloatingAlertBanner?
    public var newlyArrivedSignalIds: Set<String> = []
    public var feedHealthResults: [FeedHealthEntry] = []
    public var isCheckingHealth: Bool = false
    public var geminiDailyCallsUsed: Int = 0
    public var discoveredAIModels: [AIProviderOption: [AIModelInfo]] = [:]
    public var isTestingAIKey: Bool = false
    public var aiKeyTestMessage: String? = nil
    public var twelveDataQuota: TwelveDataQuotaStatus?
    public var twelveDataLocalDailyUsed: Int = 0
    public var twelveDataTestMessage: String?
    public var isTestingTwelveData: Bool = false

    public let livePriceService: LivePriceService
    public var demoWallet: DemoWallet = DemoWallet()
    public var manualTradeSuggestions: [String: ManualTradeLevelSuggestion] = [:]
    public var originWinRates: [OriginWinRateStat] = WinRateBreakdown.byOrigin(records: [])
    public var strengthBuckets: [StrengthBucketStat] = WinRateBreakdown.byStrengthBucket(records: [])
    public var nextScheduledScanEpochSeconds: TimeInterval? = nil
    private var dismissedManualSuggestionIds: Set<String> = []
    private var autoScanTask: Task<Void, Never>?

    public var scanUsageEstimate: ScanUsageEstimate {
        ScanSchedulePolicy.estimateDailyUsage(
            symbolCount: max(1, settings.activeWatchlistAssets.count),
            configuredMinutes: settings.payload.autoScanIntervalMinutes,
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }

    public init(settings: AppSettingsStore, store: ConfluenceDataStore) {
        self.settings = settings
        self.store = store
        self.diagnosticLog = DiagnosticLogStore(store: store)
        self.crashLogStore = CrashLogStore(store: store)
        let client = URLSessionHTTPClient()
        self.http = client
        let td = TwelveDataAdapter(http: client)
        self.twelveData = td
        self.cryptoRouter = CryptoOHLCVRouter(http: client, twelveData: td)
        self.tradFiRouter = TradFiOHLCVRouter(http: client, twelveData: td)
        self.okxPositioning = OKXPositioningAdapter(http: client)
        self.cftcCOT = CFTCCOTAdapter(http: client)
        self.calendarService = EconomicCalendarService(http: client)
        self.newsService = BreakingNewsService(http: client)
        self.geminiClient = GeminiJudgeClient(http: client)
        self.deepseekClient = OpenAICompatibleJudgeClient(provider: .deepseek, http: client)
        self.openRouterClient = OpenAICompatibleJudgeClient(provider: .openrouter, http: client)
        self.livePriceService = LivePriceService(http: client)

        wireNotificationRouter()
        wireLivePriceMonitor()
        loadPersistedState()
    }

    public func availableModels(for provider: AIProviderOption) -> [AIModelInfo] {
        if let fetched = discoveredAIModels[provider], !fetched.isEmpty {
            return fetched
        }
        return provider.fallbackModels
    }

    private func aiClient(for provider: AIProviderOption) -> any AIJudgeClient {
        switch provider {
        case .gemini: return geminiClient
        case .deepseek: return deepseekClient
        case .openrouter: return openRouterClient
        }
    }

    public func testSelectedAIProviderKey() async {
        let provider = settings.payload.aiProvider
        isTestingAIKey = true
        aiKeyTestMessage = nil
        defer { isTestingAIKey = false }

        guard let key = await KeychainStore.shared.read(provider.keychainKey), !key.isEmpty else {
            aiKeyTestMessage = "Save a \(provider.shortLabel) API key first."
            return
        }
        do {
            let models = try await aiClient(for: provider).listModels(apiKey: key)
            discoveredAIModels[provider] = models
            if let first = models.first, !models.contains(where: { $0.id == settings.payload.aiModelID }) {
                settings.payload.aiModelID = first.id
            }
            aiKeyTestMessage = "Connected to \(provider.displayName) · \(models.count) models listed."
            diagnosticLog.log(.info, category: .ai, message: "AI discovery (\(provider.shortLabel)): \(models.count) models.")
        } catch {
            aiKeyTestMessage = "Failed: \(error.localizedDescription)"
            diagnosticLog.log(.warn, category: .ai, message: "AI key test failed (\(provider.shortLabel)): \(error.localizedDescription)")
        }
    }

    public func summarizeBreakingNewsImpact(headline: String, affectedAssets: [String]) async -> String? {
        guard settings.payload.geminiEnabled else { return nil }
        let provider = settings.payload.aiProvider
        guard let key = await KeychainStore.shared.read(provider.keychainKey), !key.isEmpty else { return nil }
        do {
            let summary = try await aiClient(for: provider).summarizeBreakingImpact(
                headline: headline,
                affectedAssets: affectedAssets,
                apiKey: key,
                dailyLimit: settings.payload.geminiDailyCallLimit,
                modelID: settings.payload.aiModelID
            )
            self.geminiDailyCallsUsed = AIDailyUsageTracker.currentCount()
            return summary
        } catch {
            diagnosticLog.log(.warn, category: .ai, message: "AI news summary (\(provider.shortLabel)) failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func wireLivePriceMonitor() {
        livePriceService.updateModes(
            tradFi: settings.payload.tradFiLiveFeedMode,
            crypto: settings.payload.cryptoLiveFeedMode
        )
        livePriceService.onQuoteReceived = { [weak self] quote in
            guard let self else { return }
            self.handleLivePriceTick(quote)
        }
    }

    public func syncLiveFeedModesFromSettings() {
        livePriceService.updateModes(
            tradFi: settings.payload.tradFiLiveFeedMode,
            crypto: settings.payload.cryptoLiveFeedMode
        )
    }

    public func handleScenePhaseActive(_ isActive: Bool) {
        livePriceService.setForegroundActive(isActive)
        if isActive {
            syncLiveFeedModesFromSettings()
            acquireActivePositionsLiveFeed()
            scanOnOpenIfDue()
            restartAutoScanLoop()
        } else {
            stopAutoScanLoop()
        }
    }

    public func scanOnOpenIfDue(nowEpochSeconds: TimeInterval = Date().timeIntervalSince1970) {
        guard !isScanning else { return }
        let due = ScanSchedulePolicy.shouldScanOnOpen(
            enabled: settings.payload.scanOnOpenEnabled,
            lastScanEpochSeconds: lastScanDate?.timeIntervalSince1970,
            nowEpochSeconds: nowEpochSeconds
        )
        guard due else { return }
        Task { [weak self] in
            await self?.scanAllMarkets(isBackground: false)
        }
    }

    public func restartAutoScanLoop() {
        stopAutoScanLoop()
        let effectiveMinutes = ScanSchedulePolicy.effectiveIntervalMinutes(
            configuredMinutes: settings.payload.autoScanIntervalMinutes,
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
        guard effectiveMinutes > 0 else {
            nextScheduledScanEpochSeconds = nil
            return
        }
        let now = Date().timeIntervalSince1970
        nextScheduledScanEpochSeconds = ScanSchedulePolicy.nextScanEpochSeconds(
            lastScanEpochSeconds: lastScanDate?.timeIntervalSince1970,
            configuredMinutes: settings.payload.autoScanIntervalMinutes,
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            nowEpochSeconds: now
        )
        autoScanTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let minutes = ScanSchedulePolicy.effectiveIntervalMinutes(
                    configuredMinutes: self.settings.payload.autoScanIntervalMinutes,
                    isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
                )
                guard minutes > 0 else {
                    self.nextScheduledScanEpochSeconds = nil
                    return
                }
                let nextEpoch = ScanSchedulePolicy.nextScanEpochSeconds(
                    lastScanEpochSeconds: self.lastScanDate?.timeIntervalSince1970,
                    configuredMinutes: self.settings.payload.autoScanIntervalMinutes,
                    isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                    nowEpochSeconds: Date().timeIntervalSince1970
                )
                self.nextScheduledScanEpochSeconds = nextEpoch
                let sleepSec = max(15.0, (nextEpoch ?? (Date().timeIntervalSince1970 + Double(minutes * 60))) - Date().timeIntervalSince1970)
                try? await Task.sleep(for: .seconds(sleepSec))
                if Task.isCancelled { return }
                if !self.isScanning {
                    await self.scanAllMarkets(isBackground: false)
                }
            }
        }
    }

    public func stopAutoScanLoop() {
        autoScanTask?.cancel()
        autoScanTask = nil
    }

    public func acquireActivePositionsLiveFeed() {
        let demoSyms = demoWallet.activePositions.map(\.symbol)
        let openJournalSyms = journalEntries.filter { $0.outcome == .open }.map(\.symbol)
        let combined = Array(Set(demoSyms + openJournalSyms)).sorted()
        if combined.isEmpty {
            livePriceService.release(owner: "positions_monitor")
        } else {
            livePriceService.acquire(owner: "positions_monitor", symbols: combined)
        }
    }

    public func handleLivePriceTick(_ quote: LivePriceQuote) {
        let (updatedWallet, events) = TradeMonitor.reconcileDemoWalletOnTick(
            wallet: demoWallet,
            quote: quote
        )
        if updatedWallet != demoWallet {
            demoWallet = updatedWallet
            store.saveDemoWallet(updatedWallet)
            acquireActivePositionsLiveFeed()
        }
        for event in events {
            diagnosticLog.log(.info, category: .engine, message: "\(event.title) — \(event.body)")
            let currentSettings = settings.payload
            Task {
                await PreNewsNotificationScheduler.shared.postDemoPositionClosedNotification(event, settings: currentSettings)
            }
        }

        let alerts = TradeMonitor.evaluateManualJournalAlerts(
            entries: journalEntries,
            quote: quote,
            dismissedIds: dismissedManualSuggestionIds
        )
        for alert in alerts {
            manualTradeSuggestions[alert.journalEntryId] = alert
        }
    }

    public func applyManualTradeSuggestion(_ suggestion: ManualTradeLevelSuggestion) {
        guard let existing = journalEntries.first(where: { $0.id == suggestion.journalEntryId }) else { return }
        let updated = JournalEntrySnapshot(
            id: existing.id,
            signalFingerprint: existing.signalFingerprint,
            symbol: existing.symbol,
            marketClass: existing.marketClass,
            timeframe: existing.timeframe,
            direction: existing.direction,
            plannedEntry: existing.plannedEntry,
            actualFillPrice: existing.actualFillPrice,
            stopLoss: existing.stopLoss,
            tp1: existing.tp1,
            tp2: existing.tp2,
            exitPrice: suggestion.suggestedExitPrice,
            positionSizeText: existing.positionSizeText,
            outcome: suggestion.suggestedOutcome,
            actualRMultiple: suggestion.suggestedRMultiple,
            systemRMultiple: existing.systemRMultiple,
            strategyIDs: existing.strategyIDs,
            tags: existing.tags,
            notes: existing.notes,
            takenAt: existing.takenAt,
            closedAt: Date()
        )
        manualTradeSuggestions.removeValue(forKey: suggestion.journalEntryId)
        saveJournalEntry(updated)
        acquireActivePositionsLiveFeed()
    }

    public func dismissManualTradeSuggestion(entryId: String) {
        dismissedManualSuggestionIds.insert(entryId)
        manualTradeSuggestions.removeValue(forKey: entryId)
    }

    private func wireNotificationRouter() {
        let router = NotificationCenterRouter.shared
        router.onForegroundSystemNotification = { [weak self] snapshot in
            guard let self else { return }
            self.recordNotification(snapshot)
        }
        router.onMarkReadById = { [weak self] id in
            guard let self else { return }
            self.markNotificationRead(id: id)
        }
        router.onDeepLink = { [weak self] link in
            guard let self else { return }
            self.pendingDeepLink = link
        }
    }

    public func loadPersistedState() {
        self.signals = store.fetchSignals(limit: 150)
        self.outcomeRecords = store.fetchOutcomeRecords()
        self.tradeLedger = store.fetchTradeLedger(limit: 300)
        self.trapLogs = store.fetchTrapLogs(limit: 300)
        self.journalEntries = store.fetchJournalEntries(limit: 500)
        self.demoWallet = store.loadDemoWallet()
        recomputeCalibration()
        recomputeCorrelations()
        reloadNotifications()
        for sig in signals {
            if let lastClose = sig.recentCandles.last?.close {
                livePriceService.seedReferenceClose(lastClose, for: sig.symbol)
            }
        }
        acquireActivePositionsLiveFeed()
        Task {
            self.geminiDailyCallsUsed = await geminiClient.dailyUsageCount()
            self.twelveDataLocalDailyUsed = await twelveData.localDailyUsage()
            self.twelveDataQuota = await twelveData.cachedQuotaStatus()
            await refreshNotificationStatus()
        }
    }

    // MARK: - Trade Journal, Correlation Awareness, Broker Offsets & Backup/CSV (v1.4)

    public func recomputeJournalSummary() {
        let strongCount = signals.filter { $0.category == .strongSignal }.count
        self.journalSummary = JournalSummaryStats.compute(
            entries: journalEntries,
            totalSystemStrongSignals: max(strongCount, tradeLedger.count)
        )
    }

    public func recomputeCorrelations() {
        let activeList: [TradeSignal]
        if settings.payload.oneSignalPerCorrelatedCluster {
            activeList = CorrelationAnalyzer.filterOnePerCorrelatedCluster(
                signals: signals,
                candlesBySymbol: cachedClosedCandlesBySymbol
            )
        } else {
            activeList = signals
        }
        self.correlationWarningsByFingerprint = CorrelationAnalyzer.analyzeActiveSignals(
            signals: activeList,
            candlesBySymbol: cachedClosedCandlesBySymbol
        )
        self.netExposureSummary = CorrelationAnalyzer.netExposureSummary(signals: activeList)
    }

    /// Signals displayed in the feed (honoring optional `oneSignalPerCorrelatedCluster` cap when enabled).
    public var displaySignals: [TradeSignal] {
        if settings.payload.oneSignalPerCorrelatedCluster {
            return CorrelationAnalyzer.filterOnePerCorrelatedCluster(
                signals: signals,
                candlesBySymbol: cachedClosedCandlesBySymbol
            )
        }
        return signals
    }

    public func lastKnownPrice(for symbol: String) -> Double? {
        if let bar = cachedClosedCandlesBySymbol[symbol]?.last {
            return bar.close
        }
        if let sig = signals.first(where: { $0.symbol == symbol }) {
            return sig.recentCandles.last?.close ?? sig.levels?.entryMid
        }
        return nil
    }

    public func journalEntry(forSignalFingerprint fingerprint: String) -> JournalEntrySnapshot? {
        journalEntries.first { $0.signalFingerprint == fingerprint }
    }

    public func makeJournalDraft(from signal: TradeSignal) -> JournalEntrySnapshot {
        if let existing = journalEntry(forSignalFingerprint: signal.fingerprint) {
            return existing
        }
        let lv = settings.displayLevels(for: signal) ?? signal.levels
        let outcomeRec = outcomeBySignalId[signal.fingerprint]
        return JournalEntrySnapshot(
            signalFingerprint: signal.fingerprint,
            symbol: signal.symbol,
            marketClass: signal.marketClass,
            timeframe: signal.timeframe,
            direction: signal.direction,
            plannedEntry: lv?.entryMid ?? signal.recentCandles.last?.close ?? 0,
            actualFillPrice: lv?.entryMid,
            stopLoss: lv?.stopLoss ?? 0,
            tp1: lv?.tp1 ?? 0,
            tp2: (lv?.isTP2Enabled == true) ? lv?.tp2 : nil,
            outcome: .open,
            systemRMultiple: outcomeRec?.isResolved == true ? outcomeRec?.rMultiple : nil,
            strategyIDs: signal.alignedStrategies.map(\.id),
            tags: [signal.regime.badgeLabel, signal.killzone.displayName],
            notes: "",
            takenAt: Date()
        )
    }

    public func saveJournalEntry(_ entry: JournalEntrySnapshot) {
        store.upsertJournalEntry(entry)
        self.journalEntries = store.fetchJournalEntries(limit: 500)
        recomputeJournalSummary()
    }

    public func deleteJournalEntry(id: String) {
        store.deleteJournalEntry(id: id)
        self.journalEntries = store.fetchJournalEntries(limit: 500)
        recomputeJournalSummary()
    }

    public func exportBackupArchiveURL() -> URL? {
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.3.0"
        return BackupArchiveService.exportBackupFile(settings: settings.payload, store: store, appVersion: ver)
    }

    public func importBackupArchive(from data: Data, mode: BackupImportMode) throws -> BackupImportSummary {
        let summary = try BackupArchiveService.restoreArchive(
            from: data,
            mode: mode,
            settingsStore: settings,
            dataStore: store
        )
        loadPersistedState()
        diagnosticLog.log(
            .info,
            category: .engine,
            message: "Restored backup (\(mode.rawValue)): \(summary.signalsImported) signals, \(summary.outcomesImported) outcomes, \(summary.journalImported) journal entries."
        )
        return summary
    }

    public func exportTradeLedgerCSVURL() -> URL? {
        let csv = BackupArchiveService.buildTradeLedgerCSV(entries: tradeLedger)
        return BackupArchiveService.writeCSVToTemporaryFile(content: csv, filename: "Confluence_Trade_Ledger.csv")
    }

    public func exportJournalCSVURL() -> URL? {
        let csv = BackupArchiveService.buildJournalCSV(entries: journalEntries)
        return BackupArchiveService.writeCSVToTemporaryFile(content: csv, filename: "Confluence_Trade_Journal.csv")
    }

    /// Recomputes Calibration KPIs (fixed headline + active custom filter), display-only Platt calibrator,
    /// and per-strategy rankings immediately.
    public func recomputeCalibration() {
        let filter = settings.buildCalibrationFilterConfig()
        let signalsByFP = store.fetchSignalsByFingerprint(limit: 500)
        let enriched: [SignalOutcomeRecord] = outcomeRecords.map { rec in
            if rec.riskRewardRatio != nil && rec.entryBarCloseEpochSeconds != nil {
                return rec
            }
            let sig = signalsByFP[rec.signalId]
            return SignalOutcomeRecord(
                signalId: rec.signalId,
                symbol: rec.symbol,
                marketClass: rec.marketClass,
                category: rec.category,
                direction: rec.direction,
                predictedProbability: rec.predictedProbability,
                status: rec.status,
                netReturnPercent: rec.netReturnPercent,
                rMultiple: rec.rMultiple,
                strategyIds: rec.strategyIds,
                hadMacroCatalyst: rec.hadMacroCatalyst,
                resolvedAtEpochSeconds: rec.resolvedAtEpochSeconds,
                regime: rec.regime ?? sig?.regime,
                killzone: rec.killzone ?? sig?.killzone,
                timeframe: rec.timeframe ?? sig?.timeframe,
                dataProvider: rec.dataProvider ?? sig?.dataProvider,
                riskRewardRatio: rec.riskRewardRatio ?? sig?.levels?.riskRewardRatio,
                entryBarCloseEpochSeconds: rec.entryBarCloseEpochSeconds ?? sig?.barCloseEpochSeconds,
                lifecycleStatus: rec.lifecycleStatus,
                filledAtEpochSeconds: rec.filledAtEpochSeconds,
                fillWindowBars: rec.fillWindowBars,
                isLegacyImmediateFill: rec.isLegacyImmediateFill,
                origin: sig?.origin ?? rec.origin
            )
        }
        self.confidenceCalibrator = ConfidenceCalibrator.fit(records: enriched, filter: .headlineFixed)
        self.headlineCalibrationSummary = PassiveOutcomeEvaluator.summarize(records: enriched, filter: .headlineFixed)
        self.calibrationSummary = PassiveOutcomeEvaluator.summarize(records: enriched, filter: filter)
        self.strategyBreakdowns = PassiveOutcomeEvaluator.analyzeStrategyPerformance(records: enriched, filter: filter)
        self.outcomeBySignalId = Dictionary(uniqueKeysWithValues: enriched.map { ($0.signalId, $0) })
        let trapSummaryItems = trapLogs.map {
            TrapOutcomeSummaryItem(id: $0.trapKey, outcome: $0.postTrapOutcome)
        }
        self.originWinRates = WinRateBreakdown.byOrigin(
            records: enriched,
            trapOutcomes: trapSummaryItems,
            filter: .headlineFixed
        )
        self.strengthBuckets = WinRateBreakdown.byStrengthBucket(
            records: enriched,
            filter: .headlineFixed
        )
        recomputeJournalSummary()
    }

    // MARK: - Notification Bell Inbox

    public func reloadNotifications() {
        self.notifications = store.fetchNotifications()
        self.unreadNotificationCount = store.unreadNotificationCount()
        NotificationCenterRouter.shared.syncAppBadgeCount(unreadNotificationCount)
    }

    @discardableResult
    public func recordNotification(_ item: NotificationItemSnapshot) -> Bool {
        let inserted = store.saveNotification(item)
        if inserted {
            reloadNotifications()
        }
        return inserted
    }

    public func markNotificationRead(id: String, read: Bool = true) {
        store.markNotificationRead(id: id, read: read)
        reloadNotifications()
    }

    public func markAllNotificationsRead() {
        store.markAllNotificationsRead()
        reloadNotifications()
    }

    public func deleteNotification(id: String) {
        store.deleteNotification(id: id)
        reloadNotifications()
    }

    public func clearAllNotifications() {
        store.clearAllNotifications()
        reloadNotifications()
    }

    public func handleNotificationTap(_ item: NotificationItemSnapshot) {
        markNotificationRead(id: item.id)
        isNotificationInboxPresented = false
        if let fp = item.signalFingerprint, !fp.isEmpty {
            let category: SignalCategory? = (item.type == .trapAlert) ? .trapAlert : .strongSignal
            pendingDeepLink = .signal(
                fingerprint: fp,
                category: category,
                market: item.marketClass,
                symbol: item.symbol
            )
        } else {
            pendingDeepLink = .news(eventID: item.eventID)
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

    // MARK: - Live Multi-Market Scan

    public func scanAllMarkets(isBackground: Bool = false) async {
        guard !isScanning else { return }
        // Zero-strategy guard: abort before any network call.
        guard !settings.payload.enabledStrategies.isEmpty else {
            lastScanError = Self.noStrategiesEnabledMessage
            if !isBackground { scanBlockedMessage = Self.noStrategiesEnabledMessage }
            diagnosticLog.log(.warn, category: isBackground ? .background : .engine, message: "Scan skipped: 0 strategies enabled.")
            return
        }
        isScanning = true
        lastScanError = nil
        newlyArrivedSignalIds = []
        scanProgressByMarket = [:]

        let scanStart = Date()
        diagnosticLog.log(
            .info,
            category: isBackground ? .background : .engine,
            message: "Started \(isBackground ? "background" : "foreground") scan (\(settings.activeWatchlistAssets.count) assets)."
        )

        defer {
            isScanning = false
            lastScanDate = Date()
        }

        let assets = settings.activeWatchlistAssets
        let twelveKey = await KeychainStore.shared.read(.twelveDataAPIKey)
        let finnhubKey = await KeychainStore.shared.read(.finnhubAPIKey)
        let activeAIProvider = settings.payload.aiProvider
        let aiAPIKey = await KeychainStore.shared.read(activeAIProvider.keychainKey)

        let logHook: ProviderLogHook = { [weak self] sev, cat, msg in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let severity = DiagnosticSeverity(rawValue: sev) ?? .info
                let category = DiagnosticCategory(rawValue: cat) ?? .feed
                self.diagnosticLog.log(severity, category: category, message: msg)
            }
        }

        // 1. Refresh Economic Calendar & Breaking News Radar
        if settings.payload.economicCalendarEnabled {
            let calResult = await calendarService.fetchCalendarEvents(minimumImportance: .medium)
            self.calendarEvents = calResult.events
            self.calendarSourceLabel = calResult.sourceLabel
            let nowEpoch = Date().timeIntervalSince1970
            let clusters = MacroSurpriseEngine.buildClusters(events: calResult.events, nowEpochSeconds: nowEpoch)
            self.calendarClusters = clusters
            self.scheduledPreNewsCount = await PreNewsNotificationScheduler.shared.reschedulePreNewsCountdowns(
                events: calResult.events,
                settings: settings.payload,
                nowEpochSeconds: nowEpoch
            )

            // Persist newly published macro release impulses into Bell Inbox (deduplicated by cluster ID)
            for cluster in clusters where abs(nowEpoch - cluster.clusterEpochSeconds) <= 3600 {
                let id = "confluence.macro.\(cluster.currency).\(Int(cluster.clusterEpochSeconds))"
                let item = NotificationItemSnapshot(
                    id: id,
                    createdAt: Date(timeIntervalSince1970: cluster.clusterEpochSeconds),
                    type: .newsReleaseImpact,
                    title: "Macro Release · \(cluster.currency)",
                    subtitle: cluster.headlineStrip,
                    symbol: cluster.currency,
                    eventID: cluster.results.first?.event.id ?? id,
                    isRead: false
                )
                if recordNotification(item), isBackground {
                    await PreNewsNotificationScheduler.shared.postMacroReleaseNotification(cluster, settings: settings.payload)
                }
            }

            // Persist imminent exact-clock high-impact pre-news warning into Bell Inbox (deduplicated)
            if let shield = imminentPreNewsEvent, shield.minutesUntilRelease <= 15 {
                let id = "confluence.prenews.imminent.\(shield.event.id)"
                let item = NotificationItemSnapshot(
                    id: id,
                    createdAt: Date(),
                    type: .preNewsCountdown,
                    title: "Pre-News Volatility Shield · \(shield.event.currency)",
                    subtitle: "\(shield.event.name) in \(max(1, shield.minutesUntilRelease))m",
                    symbol: shield.event.currency,
                    eventID: shield.event.id,
                    isRead: false
                )
                recordNotification(item)
            }
        }

        if settings.payload.breakingNewsRadarEnabled {
            let newsRes = await newsService.fetchNewsAndSentiment(finnhubAPIKey: finnhubKey)
            self.breakingNews = newsRes.items
            self.fearGreed = newsRes.fearGreed
        }

        // 2. Build out-of-sample reliability weights & engine config
        var weights: [String: Double] = [:]
        for stat in calibrationSummary.strategyRankings where stat.totalResolved >= 5 {
            weights[stat.strategyId] = max(0.65, min(1.40, 0.5 + stat.winRate))
        }

        let engineConfig = settings.buildEngineConfig(reliabilityWeights: weights)
        let dedupHistory = store.recentDeduplicationHistory()
        let entryTF = settings.payload.entryTimeframe
        let htfTF = settings.payload.htfTimeframe
        let cryptoPrimary = settings.payload.cryptoPrimaryExchange
        let tradFiPref = settings.payload.tradFiProviderPreference
        let positioningOn = settings.payload.positioningFeedsEnabled

        // 3. Scan each enabled asset & update passive outcomes against sanitized closed candles
        var scannedSignals: [TradeSignal] = []
        var scannedTraps: [BehavioralTrap] = []
        var sanitizedClosedBySymbol: [String: [Candle]] = [:]
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
                        async let eTask = cryptoRouter.fetchCandles(
                            asset: asset,
                            timeframe: entryTF,
                            primary: cryptoPrimary,
                            twelveDataKey: twelveKey,
                            onLog: logHook
                        )
                        async let hTask = cryptoRouter.fetchCandles(
                            asset: asset,
                            timeframe: htfTF,
                            primary: cryptoPrimary,
                            twelveDataKey: twelveKey,
                            onLog: logHook
                        )
                        (entryRes, htfRes) = try await (eTask, hTask)
                    } else {
                        async let eTask = tradFiRouter.fetchCandles(
                            asset: asset,
                            timeframe: entryTF,
                            twelveDataKey: twelveKey,
                            preference: tradFiPref,
                            allowProxyForChart: false,
                            onLog: logHook
                        )
                        async let hTask = tradFiRouter.fetchCandles(
                            asset: asset,
                            timeframe: htfTF,
                            twelveDataKey: twelveKey,
                            preference: tradFiPref,
                            allowProxyForChart: false,
                            onLog: logHook
                        )
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

                    try Task.checkCancellation()
                    let entryCandlesSnapshot = entryRes.candles
                    let htfCandlesSnapshot = htfRes.candles
                    let entryProviderSnapshot = entryRes.providerName
                    let calendarSnapshot = calendarEvents
                    let newsSnapshot = breakingNews
                    let fgSnapshot = asset.marketClass == .crypto ? fearGreed : nil
                    let okxSnapSnapshot = okxSnap
                    let cotRecordsSnapshot = cotRecords

                    let (sanitizedEntry, output) = await Task.detached(priority: .userInitiated) {
                        let sanitized = CandleHygieneEngine.sanitize(
                            rawCandles: entryCandlesSnapshot,
                            symbol: asset.symbol,
                            marketClass: asset.marketClass,
                            timeframe: entryTF,
                            providerName: entryProviderSnapshot,
                            serverNowEpochSeconds: serverNow,
                            clockSkewSeconds: clockSkew,
                            asset: asset
                        )
                        let analyzed = SignalEngine.analyze(
                            asset: asset,
                            rawEntryCandles: entryCandlesSnapshot,
                            rawHTFCandles: htfCandlesSnapshot,
                            timeframe: entryTF,
                            htfTimeframe: htfTF,
                            okxDerivatives: okxSnapSnapshot,
                            cftcCOTRecords: cotRecordsSnapshot,
                            calendarEvents: calendarSnapshot,
                            breakingNews: newsSnapshot,
                            fearGreed: fgSnapshot,
                            config: engineConfig,
                            dataProvider: entryProviderSnapshot,
                            serverNowEpochSeconds: serverNow,
                            clockSkewSeconds: clockSkew
                        )
                        return (sanitized, analyzed)
                    }.value
                    try Task.checkCancellation()
                    sanitizedClosedBySymbol[asset.symbol] = sanitizedEntry.candles

                    if sanitizedEntry.report.droppedOpenBars > 0 {
                        diagnosticLog.log(
                            .info,
                            category: .engine,
                            message: "\(asset.symbol) \(entryTF.displayLabel) (\(entryRes.providerName)): dropped \(sanitizedEntry.report.droppedOpenBars) forming bar(s)."
                        )
                    }

                    // Record 4-stage Behavioral Traps + evaluate post-trap respect
                    let atrApprox = sanitizedEntry.candles.suffix(14).map { $0.high - $0.low }.reduce(0, +) / Double(max(1, min(14, sanitizedEntry.candles.count)))
                    let posContext = okxSnap.map { "OKX Funding \(String(format: "%.4f%%", $0.currentFundingRate * 100))" }
                        ?? (!cotRecords.isEmpty ? "CFTC COT Active" : "Price-Action Only")
                    for trap in output.activeTraps {
                        let respect = TrapEvaluationHelper.evaluateTrapRespect(
                            trap: trap,
                            subsequentClosedCandles: sanitizedEntry.candles,
                            atrReference: atrApprox
                        )
                        store.upsertTrapLog(
                            trap: trap,
                            timeframe: entryTF,
                            positioningContext: posContext,
                            postTrapOutcome: respect
                        )
                    }
                    scannedTraps.append(contentsOf: output.activeTraps)

                    if var signal = output.signal {
                        if dismissedSignalFingerprints.contains(signal.fingerprint) {
                            continue
                        }

                        // Display-only Platt probability (never alters raw confidencePercent or gating!)
                        if confidenceCalibrator.isActive,
                           let calProb = confidenceCalibrator.calibratedProbability(forRawScore: signal.confidencePercent) {
                            signal = signal.withCalibratedProbability(calProb, sampleCount: confidenceCalibrator.sampleCount)
                        }

                        let isNew = !ConfluenceScorer.shouldSuppressDuplicate(
                            fingerprint: signal.fingerprint,
                            symbol: signal.symbol,
                            direction: signal.direction,
                            nowEpochSeconds: serverNow,
                            recentHistory: dedupHistory,
                            cooldownSeconds: engineConfig.signalCooldownSeconds
                        )

                        // Optional AI second-opinion ONLY on new Strong Signals or Trap Alerts when enabled
                        if isNew,
                           settings.payload.geminiEnabled,
                           let key = aiAPIKey, !key.isEmpty,
                           (signal.category == .strongSignal || signal.category == .trapAlert) {
                            let client = aiClient(for: activeAIProvider)
                            if let judgment = try? await client.judgeSignal(
                                signal,
                                apiKey: key,
                                dailyLimit: settings.payload.geminiDailyCallLimit,
                                modelID: settings.payload.aiModelID
                            ) {
                                signal = signal.withAIJudgment(judgment, threshold: settings.payload.geminiConfirmationThreshold)
                                self.geminiDailyCallsUsed = AIDailyUsageTracker.currentCount()
                            } else {
                                diagnosticLog.log(.warn, category: .ai, message: "\(activeAIProvider.shortLabel) second-opinion skipped or failed for \(signal.symbol).")
                            }
                        }

                        store.upsertSignal(signal)
                        scannedSignals.append(signal)

                        if isNew && (signal.category == .strongSignal || signal.category == .trapAlert) {
                            newlyArrivedSignalIds.insert(signal.id)
                            await dispatchArrivalFeedback(for: signal, isBackground: isBackground)
                        }
                    }
                } catch is CancellationError {
                    return
                } catch let urlErr as URLError where urlErr.code == .cancelled {
                    return
                } catch {
                    if Task.isCancelled { return }
                    let msg = "\(asset.symbol): \(error.localizedDescription)"
                    errors.append(msg)
                    diagnosticLog.log(.error, category: .feed, message: msg)
                }

                done += 1
                scanProgressByMarket[market] = "\(done)/\(marketAssets.count) done"
            }
        }

        // 4. Passively evaluate prior signals (strong, traps, weak/filtered for stats, and news setups)
        // strictly against sanitized closed candles (zero lookahead). Weak/filtered signals stay hidden from
        // the feed and never fire notifications when "Show Weak / Filtered" is OFF.
        let existingOutcomesById = Dictionary(uniqueKeysWithValues: store.fetchOutcomeRecords().map { ($0.signalId, $0) })
        let persisted = store.fetchSignals(limit: 250)
        for prior in persisted where prior.levels != nil {
            if let existing = existingOutcomesById[prior.fingerprint], existing.isTerminal {
                continue
            }
            guard prior.timeframe == entryTF,
                  let freshBars = sanitizedClosedBySymbol[prior.symbol], !freshBars.isEmpty
            else { continue }
            let outcome = PassiveOutcomeEvaluator.evaluate(signal: prior, subsequentClosedCandles: freshBars)
            if outcome.status != .pending {
                store.updateOutcome(outcome)
                let mergedWindow = Self.buildReplayWindow(
                    preEntryCandles: prior.recentCandles,
                    subsequentCandles: freshBars,
                    exitEpochSeconds: outcome.resolvedAtEpochSeconds,
                    timeframe: prior.timeframe
                )
                store.saveReplayCandles(
                    fingerprint: prior.fingerprint,
                    symbol: prior.symbol,
                    timeframe: prior.timeframe,
                    providerName: prior.dataProvider,
                    candles: mergedWindow
                )
            }
        }

        // Reconcile active Demo Wallet positions against closed bars (pessimistic same-bar SL-first)
        var reconciledWallet = demoWallet
        var closedDemoEvents: [DemoPositionCloseEvent] = []
        for (sym, bars) in sanitizedClosedBySymbol {
            let (nextW, evs) = TradeMonitor.reconcileDemoWallet(wallet: reconciledWallet, symbol: sym, closedCandles: bars)
            reconciledWallet = nextW
            closedDemoEvents.append(contentsOf: evs)
        }
        if reconciledWallet != demoWallet {
            demoWallet = reconciledWallet
            store.saveDemoWallet(reconciledWallet)
            acquireActivePositionsLiveFeed()
        }
        for ev in closedDemoEvents {
            diagnosticLog.log(.info, category: .engine, message: "\(ev.title) — \(ev.body)")
            await PreNewsNotificationScheduler.shared.postDemoPositionClosedNotification(ev, settings: settings.payload)
        }

        for (sym, bars) in sanitizedClosedBySymbol {
            if let lastClose = bars.last?.close, lastClose.isFinite, lastClose > 0 {
                livePriceService.seedReferenceClose(lastClose, for: sym)
            }
        }
        self.cachedClosedCandlesBySymbol = sanitizedClosedBySymbol
        self.activeTraps = scannedTraps
        self.signals = store.fetchSignals(limit: 150)
        self.outcomeRecords = store.fetchOutcomeRecords()
        self.tradeLedger = store.fetchTradeLedger(limit: 300)
        self.trapLogs = store.fetchTrapLogs(limit: 300)
        self.journalEntries = store.fetchJournalEntries(limit: 500)
        recomputeCalibration()
        recomputeCorrelations()
        self.twelveDataLocalDailyUsed = await twelveData.localDailyUsage()
        self.twelveDataQuota = await twelveData.cachedQuotaStatus()

        let elapsed = Date().timeIntervalSince(scanStart)
        diagnosticLog.log(
            errors.isEmpty ? .info : .warn,
            category: isBackground ? .background : .engine,
            message: "Scan finished in \(String(format: "%.1fs", elapsed)) · \(scannedSignals.count) setups, \(scannedTraps.count) traps, \(errors.count) errors."
        )

        if !errors.isEmpty {
            self.lastScanError = errors.prefix(2).joined(separator: " • ")
        }
    }

    // MARK: - Permanent Signal Feed Deletion (Calibration Stats & Trade Ledger Preserved)

    public func deleteSignal(fingerprint: String) {
        dismissedSignalFingerprints.insert(fingerprint)
        store.deleteSignal(fingerprint: fingerprint)
        signals.removeAll { $0.fingerprint == fingerprint }
        recomputeCorrelations()
        diagnosticLog.log(.info, category: .engine, message: "Deleted signal card \(fingerprint) (Calibration Stats preserved).")
    }

    public func deleteSignals(fingerprints: Set<String>) {
        guard !fingerprints.isEmpty else { return }
        dismissedSignalFingerprints.formUnion(fingerprints)
        store.deleteSignals(fingerprints: fingerprints)
        signals.removeAll { fingerprints.contains($0.fingerprint) }
        recomputeCorrelations()
        diagnosticLog.log(.info, category: .engine, message: "Deleted \(fingerprints.count) selected signal card(s) (Calibration Stats preserved).")
    }

    public func deleteSignals(in category: SignalCategory) {
        let matching = Set(signals.filter { $0.category == category }.map(\.fingerprint))
        dismissedSignalFingerprints.formUnion(matching)
        store.deleteSignals(category: category)
        signals.removeAll { $0.category == category }
        recomputeCorrelations()
        diagnosticLog.log(.info, category: .engine, message: "Cleared \(category.rawValue) tab (\(matching.count) cards; Calibration Stats preserved).")
    }

    public func deleteAllSignals() {
        dismissedSignalFingerprints.formUnion(signals.map(\.fingerprint))
        store.deleteAllSignals()
        signals = []
        recomputeCorrelations()
        diagnosticLog.log(.info, category: .engine, message: "Cleared all signal cards from Signals feed (Calibration Stats preserved).")
    }

    // MARK: - Interactive News + Math Trade Evaluation

    public func evaluateNewsTrade(
        summary: NewsMarketSummary,
        symbol: String
    ) async -> NewsTradeEvaluation {
        guard let asset = WatchlistDefaults.descriptor(for: symbol) else {
            return NewsTradeEvaluation(
                symbol: symbol,
                newsBias: summary.headlineBias,
                verdict: .waitNoTrade,
                signal: nil,
                headlineSummary: "Symbol \(symbol) is not configured in Confluence watchlist.",
                alignmentNotes: [],
                requiredConfirmations: ["Select a supported watchlist asset."]
            )
        }

        let entryTF = settings.payload.entryTimeframe
        let htfTF = settings.payload.htfTimeframe
        let twelveKey = await KeychainStore.shared.read(.twelveDataAPIKey)

        var entryCandles: [Candle] = []
        var htfCandles: [Candle] = []
        var providerName = "Cached Feed"

        do {
            if asset.marketClass == .crypto {
                async let eTask = cryptoRouter.fetchCandles(
                    asset: asset,
                    timeframe: entryTF,
                    primary: settings.payload.cryptoPrimaryExchange,
                    twelveDataKey: twelveKey
                )
                async let hTask = cryptoRouter.fetchCandles(
                    asset: asset,
                    timeframe: htfTF,
                    primary: settings.payload.cryptoPrimaryExchange,
                    twelveDataKey: twelveKey
                )
                let (eRes, hRes) = try await (eTask, hTask)
                entryCandles = eRes.candles
                htfCandles = hRes.candles
                providerName = eRes.providerName
            } else {
                async let eTask = tradFiRouter.fetchCandles(
                    asset: asset,
                    timeframe: entryTF,
                    twelveDataKey: twelveKey,
                    preference: settings.payload.tradFiProviderPreference,
                    allowProxyForChart: false
                )
                async let hTask = tradFiRouter.fetchCandles(
                    asset: asset,
                    timeframe: htfTF,
                    twelveDataKey: twelveKey,
                    preference: settings.payload.tradFiProviderPreference,
                    allowProxyForChart: false
                )
                let (eRes, hRes) = try await (eTask, hTask)
                entryCandles = eRes.candles
                htfCandles = hRes.candles
                providerName = eRes.providerName
            }
        } catch {
            // Honest fallback to last persisted signal candles if live feed rate-limits
            if let cachedSig = signals.first(where: { $0.symbol == asset.symbol && !$0.recentCandles.isEmpty }) {
                entryCandles = cachedSig.recentCandles
                providerName = "\(cachedSig.dataProvider) (Cached)"
            }
            diagnosticLog.log(.warn, category: .feed, message: "News analysis live candle fetch failed for \(symbol): \(error.localizedDescription)")
        }

        var okxSnap: OKXDerivativesSnapshot? = nil
        var cotRecords: [CFTCCOTRecord] = []
        if settings.payload.positioningFeedsEnabled {
            if let swapId = asset.okxSwapInstId {
                let oiPeriod = (entryTF == .d1) ? "1Dutc" : (entryTF == .h4 ? "4H" : "1H")
                okxSnap = try? await okxPositioning.fetchSnapshot(instId: swapId, period: oiPeriod)
            } else if let code = asset.cftcContractCode,
                      let dsRaw = asset.cftcDataset,
                      let ds = CFTCDatasetKind(rawValue: dsRaw) {
                cotRecords = (try? await cftcCOT.records(for: code, dataset: ds)) ?? []
            }
        }

        var weights: [String: Double] = [:]
        for stat in calibrationSummary.strategyRankings where stat.totalResolved >= 5 {
            weights[stat.strategyId] = max(0.65, min(1.40, 0.5 + stat.winRate))
        }
        let config = settings.buildEngineConfig(reliabilityWeights: weights)
        let clockSkew = await http.estimatedClockSkewSeconds()
        let serverNow = Date().timeIntervalSince1970 + clockSkew

        let eval = NewsTradeAnalyzer.evaluateTrade(
            summary: summary,
            asset: asset,
            rawEntryCandles: entryCandles,
            rawHTFCandles: htfCandles,
            timeframe: entryTF,
            htfTimeframe: htfTF,
            okxDerivatives: okxSnap,
            cftcCOTRecords: cotRecords,
            calendarEvents: calendarEvents,
            breakingNews: breakingNews,
            fearGreed: fearGreed,
            config: config,
            dataProvider: providerName,
            serverNowEpochSeconds: serverNow
        )

        if eval.verdict == .actionableSetup, let sig = eval.signal, sig.levels != nil {
            let newsSignal = sig.withOrigin(.news)
            store.upsertSignal(newsSignal)
            return NewsTradeEvaluation(
                symbol: eval.symbol,
                newsBias: eval.newsBias,
                verdict: eval.verdict,
                signal: newsSignal,
                headlineSummary: eval.headlineSummary,
                alignmentNotes: eval.alignmentNotes,
                requiredConfirmations: eval.requiredConfirmations
            )
        }
        return eval
    }

    // MARK: - Strategy Trade History & Trade Outcome Chart Replay

    public nonisolated static func buildReplayWindow(
        preEntryCandles: [Candle],
        subsequentCandles: [Candle],
        exitEpochSeconds: TimeInterval?,
        timeframe: Timeframe
    ) -> [Candle] {
        var byOpen: [Int: Candle] = [:]
        for bar in preEntryCandles where bar.isClosed {
            byOpen[Int(bar.openTimeEpochSeconds.rounded())] = bar
        }
        let maxClose: TimeInterval? = exitEpochSeconds.map { $0 + (timeframe.seconds * 12.0) }
        for bar in subsequentCandles where bar.isClosed {
            if let cap = maxClose, bar.closeTimeEpochSeconds > cap {
                continue
            }
            byOpen[Int(bar.openTimeEpochSeconds.rounded())] = bar
        }
        let sorted = byOpen.values.sorted { $0.openTimeEpochSeconds < $1.openTimeEpochSeconds }
        return Array(sorted.suffix(160))
    }

    /// Returns all recorded trades that included `strategyId`, merging `TradeLedgerSnapshot`,
    /// `SignalOutcomeRecord`, and persisted `TradeSignal` (so legacy v1.0 signals are included too).
    public func trades(forStrategyId strategyId: String) -> [StrategyTradeItem] {
        let signalsByFP = store.fetchSignalsByFingerprint(limit: 500)
        let outcomesByFP = Dictionary(uniqueKeysWithValues: outcomeRecords.map { ($0.signalId, $0) })
        let ledgerByFP = Dictionary(uniqueKeysWithValues: tradeLedger.map { ($0.fingerprint, $0) })

        var fingerprints = Set<String>()
        for entry in tradeLedger where entry.alignedStrategyIDs.contains(strategyId) {
            fingerprints.insert(entry.fingerprint)
        }
        for rec in outcomeRecords where rec.strategyIds.contains(strategyId) {
            fingerprints.insert(rec.signalId)
        }
        for (fp, sig) in signalsByFP where sig.alignedStrategies.contains(where: { $0.id == strategyId }) && sig.levels != nil {
            fingerprints.insert(fp)
        }

        var items: [StrategyTradeItem] = []
        for fp in fingerprints {
            let sig = signalsByFP[fp]
            let outcome = outcomesByFP[fp]
            let ledger = ledgerByFP[fp]

            let resolvedLevels: TradeLevels?
            if let sLevels = sig?.levels {
                resolvedLevels = sLevels
            } else if let l = ledger {
                let riskDist = abs(l.entryMid - l.stopLoss)
                let r1Dist = abs(l.tp1 - l.entryMid)
                let r2Dist = abs(l.tp2 - l.entryMid)
                let safeMid = max(l.entryMid, 1e-9)
                let safeRisk = max(riskDist, 1e-9)
                resolvedLevels = TradeLevels(
                    entryLow: l.entryLow,
                    entryHigh: l.entryHigh,
                    entryMid: l.entryMid,
                    stopLoss: l.stopLoss,
                    tp1: l.tp1,
                    tp2: l.tp2,
                    riskPercent: (riskDist / safeMid) * 100.0,
                    reward1Percent: (r1Dist / safeMid) * 100.0,
                    reward2Percent: (r2Dist / safeMid) * 100.0,
                    riskRewardRatio: r1Dist / safeRisk,
                    tp2RiskRewardRatio: r2Dist / safeRisk,
                    isTP2Enabled: abs(l.tp2 - l.tp1) > 1e-9
                )
            } else {
                resolvedLevels = nil
            }

            guard let levels = resolvedLevels else { continue }

            let status: TradeLedgerStatus
            if let out = outcome {
                switch out.status {
                case .hitTP2: status = .tp2Win
                case .hitTP1: status = .tp1Win
                case .hitSL: status = .slLoss
                case .expired: status = .expired
                case .notFilled: status = .notFilled
                case .invalidated: status = .invalidated
                case .open: status = .open
                case .pending: status = .pending
                }
            } else if let l = ledger {
                status = l.status
            } else {
                status = .pending
            }

            let symbol = sig?.symbol ?? ledger?.symbol ?? outcome?.symbol ?? ""
            guard !symbol.isEmpty else { continue }
            let marketClass = sig?.marketClass ?? ledger?.marketClass ?? outcome?.marketClass ?? .crypto
            let timeframe = sig?.timeframe ?? ledger?.timeframe ?? outcome?.timeframe ?? .h1
            let direction = sig?.direction ?? ledger?.direction ?? outcome?.direction ?? .neutral
            let category = sig?.category ?? outcome?.category ?? .strongSignal
            let conf = sig?.confidencePercent ?? ledger?.confidencePercent ?? ((outcome?.predictedProbability ?? 0.7) * 100.0)
            let netR = outcome?.rMultiple ?? ledger?.netRMultiple ?? 0.0
            let provider = sig?.dataProvider ?? ledger?.dataProvider ?? outcome?.dataProvider ?? "Live Feed"
            let entryEpoch = sig?.barCloseEpochSeconds
                ?? outcome?.entryBarCloseEpochSeconds
                ?? ledger?.createdAt.timeIntervalSince1970
                ?? Date().timeIntervalSince1970
            let exitEpoch = outcome?.resolvedAtEpochSeconds ?? ledger?.exitedAt?.timeIntervalSince1970
            let stratIDs = sig?.alignedStrategies.map(\.id) ?? ledger?.alignedStrategyIDs ?? outcome?.strategyIds ?? [strategyId]

            items.append(StrategyTradeItem(
                fingerprint: fp,
                symbol: symbol,
                displayName: sig?.displayName ?? WatchlistDefaults.descriptor(for: symbol)?.displayName ?? symbol,
                marketClass: marketClass,
                timeframe: timeframe,
                direction: direction,
                category: category,
                confidencePercent: conf,
                levels: levels,
                status: status,
                netRMultiple: netR,
                dataProvider: provider,
                entryEpochSeconds: entryEpoch,
                exitEpochSeconds: exitEpoch,
                alignedStrategyIDs: stratIDs,
                sourceSignal: sig
            ))
        }

        return items.sorted { $0.entryEpochSeconds > $1.entryEpochSeconds }
    }

    /// Loads cached replay candles (Entry -> Exit) or fetches & merges a live historical window on demand.
    public func loadTradeReplayContext(for trade: StrategyTradeItem) async -> TradeReplayContext {
        if let cached = store.fetchReplayCandles(fingerprint: trade.fingerprint) {
            let hasExitCoverage: Bool
            if let exitTS = trade.exitEpochSeconds {
                hasExitCoverage = cached.candles.contains { $0.closeTimeEpochSeconds >= exitTS - trade.timeframe.seconds }
            } else {
                hasExitCoverage = true
            }
            if hasExitCoverage && cached.candles.count >= 10 {
                return TradeReplayContext(trade: trade, initialCandles: cached.candles, providerName: cached.providerName)
            }
        }

        let preEntry = trade.sourceSignal?.recentCandles ?? []
        if let fetched = try? await fetchChartCandles(
            symbol: trade.symbol,
            timeframe: trade.timeframe,
            providerChoice: .auto
        ) {
            let merged = Self.buildReplayWindow(
                preEntryCandles: preEntry,
                subsequentCandles: fetched.candles,
                exitEpochSeconds: trade.exitEpochSeconds,
                timeframe: trade.timeframe
            )
            if !merged.isEmpty {
                store.saveReplayCandles(
                    fingerprint: trade.fingerprint,
                    symbol: trade.symbol,
                    timeframe: trade.timeframe,
                    providerName: fetched.providerName,
                    candles: merged
                )
                return TradeReplayContext(trade: trade, initialCandles: merged, providerName: fetched.providerName)
            }
        }

        return TradeReplayContext(
            trade: trade,
            initialCandles: ConfluenceDataStore.deduplicateAndSortCandles(preEntry),
            providerName: trade.dataProvider
        )
    }

    // MARK: - Live In-Chart Provider & Timeframe Switcher

    public func fetchChartCandles(
        symbol: String,
        timeframe: Timeframe,
        providerChoice: ChartProviderChoice,
        limit: Int = 500,
        endTimeEpochSeconds: TimeInterval? = nil
    ) async throws -> OHLCVFetchResult {
        guard let asset = WatchlistDefaults.descriptor(for: symbol) else {
            throw NetworkAdapterError.decodingFailed("Unknown symbol \(symbol)")
        }
        let twelveKey = await KeychainStore.shared.read(.twelveDataAPIKey)
        let logHook: ProviderLogHook = { [weak self] sev, cat, msg in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.diagnosticLog.log(
                    DiagnosticSeverity(rawValue: sev) ?? .info,
                    category: DiagnosticCategory(rawValue: cat) ?? .feed,
                    message: "[Chart] \(msg)"
                )
            }
        }

        let res: OHLCVFetchResult
        if asset.marketClass == .crypto {
            let pref: CryptoExchangePreference
            switch providerChoice {
            case .auto: pref = settings.payload.cryptoPrimaryExchange
            case .binanceVision: pref = .binanceVision
            case .okx: pref = .okx
            case .kraken: pref = .kraken
            case .twelveData: pref = .twelveData
            default: pref = .auto
            }
            res = try await cryptoRouter.fetchCandles(
                asset: asset,
                timeframe: timeframe,
                limit: limit,
                endTimeEpochSeconds: endTimeEpochSeconds,
                primary: pref,
                twelveDataKey: twelveKey,
                onLog: logHook
            )
        } else {
            let pref: TradFiProviderPreference
            switch providerChoice {
            case .auto: pref = settings.payload.tradFiProviderPreference
            case .twelveData: pref = .twelveData
            case .biquote: pref = .biquote
            case .yahooFinance: pref = .yahooFinance
            default: pref = .auto
            }
            res = try await tradFiRouter.fetchCandles(
                asset: asset,
                timeframe: timeframe,
                twelveDataKey: twelveKey,
                preference: pref,
                allowProxyForChart: (providerChoice == .twelveData),
                limit: limit,
                endTimeEpochSeconds: endTimeEpochSeconds,
                onLog: logHook
            )
        }

        try Task.checkCancellation()
        let clockSkew = await http.estimatedClockSkewSeconds()
        let serverNow = Date().timeIntervalSince1970 + clockSkew
        let rawChartCandles = res.candles
        let chartProvider = res.providerName
        let sanitized = await Task.detached(priority: .userInitiated) {
            CandleHygieneEngine.sanitize(
                rawCandles: rawChartCandles,
                symbol: asset.symbol,
                marketClass: asset.marketClass,
                timeframe: timeframe,
                providerName: chartProvider,
                serverNowEpochSeconds: serverNow,
                clockSkewSeconds: clockSkew,
                enforceMinimumBars: false
            )
        }.value
        try Task.checkCancellation()

        if let latestClose = sanitized.candles.last?.close, endTimeEpochSeconds == nil {
            livePriceService.seedReferenceClose(latestClose, for: asset.symbol)
        }

        self.twelveDataLocalDailyUsed = await twelveData.localDailyUsage()
        diagnosticLog.log(
            .info,
            category: .feed,
            message: "Chart loaded \(symbol) \(timeframe.displayLabel) via \(res.providerName) (\(sanitized.candles.count) closed bars)."
        )

        return OHLCVFetchResult(
            candles: sanitized.candles,
            providerName: res.providerName,
            latencyMs: res.latencyMs,
            proxySymbolUsed: res.proxySymbolUsed
        )
    }

    // MARK: - Demo Wallet Actions (Paper-Only)

    @discardableResult
    public func placeDemoOrder(_ request: DemoOrderRequest) -> Result<DemoPosition, DemoOrderRejectionReason> {
        let quote = livePriceService.latest(for: request.symbol)
        let now = Date().timeIntervalSince1970
        let asset = WatchlistDefaults.descriptor(for: request.symbol)
        let result = DemoWalletEngine.placeOrder(
            wallet: demoWallet,
            request: request,
            liveQuotePrice: quote?.price,
            liveQuoteEpochSeconds: quote?.asOfEpochSeconds,
            nowEpochSeconds: now,
            asset: asset
        )
        switch result {
        case .success(let (updatedWallet, pos)):
            demoWallet = updatedWallet
            store.saveDemoWallet(updatedWallet)
            acquireActivePositionsLiveFeed()
            return .success(pos)
        case .failure(let err):
            return .failure(err)
        }
    }

    public func closeDemoPositionManually(positionId: String, exitPrice: Double? = nil) -> Bool {
        guard let pos = demoWallet.positions.first(where: { $0.id == positionId }) else { return false }
        let price = exitPrice
            ?? livePriceService.latest(for: pos.symbol)?.price
            ?? signals.first(where: { $0.symbol == pos.symbol })?.recentCandles.last?.close
            ?? pos.filledPrice
            ?? pos.entryPrice
        guard let (updatedWallet, _) = DemoWalletEngine.closePositionManually(
            wallet: demoWallet,
            positionId: positionId,
            exitPrice: price,
            nowEpochSeconds: Date().timeIntervalSince1970
        ) else {
            return false
        }
        demoWallet = updatedWallet
        store.saveDemoWallet(updatedWallet)
        acquireActivePositionsLiveFeed()
        return true
    }

    public func moveDemoStopLossToBreakeven(positionId: String) -> Result<DemoPosition, DemoOrderRejectionReason> {
        let res = DemoWalletEngine.moveStopLossToBreakeven(wallet: demoWallet, positionId: positionId)
        switch res {
        case .success(let (updatedWallet, pos)):
            demoWallet = updatedWallet
            store.saveDemoWallet(updatedWallet)
            return .success(pos)
        case .failure(let err):
            return .failure(err)
        }
    }

    public func updateDemoStopLoss(positionId: String, newStopLoss: Double) -> Result<DemoPosition, DemoOrderRejectionReason> {
        let res = DemoWalletEngine.updateStopLoss(wallet: demoWallet, positionId: positionId, newStopLoss: newStopLoss)
        switch res {
        case .success(let (updatedWallet, pos)):
            demoWallet = updatedWallet
            store.saveDemoWallet(updatedWallet)
            return .success(pos)
        case .failure(let err):
            return .failure(err)
        }
    }

    public func updateDemoTargets(
        positionId: String,
        newTarget1: Double,
        newTarget2: Double?,
        newExitTarget: DemoExitTarget? = nil
    ) -> Result<DemoPosition, DemoOrderRejectionReason> {
        let res = DemoWalletEngine.updateTargets(
            wallet: demoWallet,
            positionId: positionId,
            newTarget1: newTarget1,
            newTarget2: newTarget2,
            newExitTarget: newExitTarget
        )
        switch res {
        case .success(let (updatedWallet, pos)):
            demoWallet = updatedWallet
            store.saveDemoWallet(updatedWallet)
            return .success(pos)
        case .failure(let err):
            return .failure(err)
        }
    }

    public func adjustDemoWalletBalance(to newBalanceUSD: Double) {
        let updated = DemoWalletEngine.adjustBalance(
            wallet: demoWallet,
            newBalanceUSD: newBalanceUSD,
            nowEpochSeconds: Date().timeIntervalSince1970
        )
        demoWallet = updated
        store.saveDemoWallet(updated)
    }

    public func exportDemoWalletTransactionsCSV() -> URL? {
        let csv = BackupArchiveService.buildDemoWalletTransactionsCSV(transactions: demoWallet.transactions)
        return BackupArchiveService.writeCSVToTemporaryFile(content: csv, filename: "Confluence_Demo_Wallet.csv")
    }

    // MARK: - Twelve Data Quota Check & Feed Health

    public func testTwelveDataKeyAndQuota() async {
        guard !isTestingTwelveData else { return }
        isTestingTwelveData = true
        twelveDataTestMessage = nil
        defer { isTestingTwelveData = false }

        guard let key = await KeychainStore.shared.read(.twelveDataAPIKey), !key.isEmpty else {
            twelveDataTestMessage = "No Twelve Data API key saved."
            return
        }
        do {
            let status = try await twelveData.testKeyAndQuota(apiKey: key)
            self.twelveDataQuota = status
            self.twelveDataLocalDailyUsed = await twelveData.localDailyUsage()
            self.twelveDataTestMessage = "Connected · \(status.summaryText)"
            diagnosticLog.log(.info, category: .feed, message: "Twelve Data /api_usage OK: \(status.summaryText)")
        } catch {
            self.twelveDataTestMessage = error.localizedDescription
            diagnosticLog.log(.error, category: .feed, message: "Twelve Data /api_usage failed: \(error.localizedDescription)")
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
            let res = try await cryptoRouter.fetchCandles(
                asset: btc,
                timeframe: .h1,
                limit: 10,
                primary: settings.payload.cryptoPrimaryExchange,
                twelveDataKey: twelveKey
            )
            results.append(FeedHealthEntry(name: "Crypto OHLCV (\(res.providerName))", healthy: true, latencyMs: res.latencyMs, detail: "\(res.candles.count) bars"))
        } catch {
            results.append(FeedHealthEntry(name: "Crypto OHLCV", healthy: false, latencyMs: 0, detail: error.localizedDescription))
        }

        // 2. FX / Gold / Equities OHLCV
        do {
            let res = try await tradFiRouter.fetchCandles(
                asset: gold,
                timeframe: .h1,
                twelveDataKey: twelveKey,
                preference: settings.payload.tradFiProviderPreference
            )
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
        diagnosticLog.log(.info, category: .feed, message: "Feed health check completed: \(results.filter(\.healthy).count)/\(results.count) healthy.")
    }

    // MARK: - Arrival Feedback & Persistent Notification Sync

    private func dispatchArrivalFeedback(for signal: TradeSignal, isBackground: Bool) async {
        let title: String
        if signal.category == .trapAlert, let td = signal.trapDirection {
            title = "\(td.rawValue) · \(signal.symbol)"
        } else {
            title = "\(signal.direction.rawValue.uppercased()) \(signal.symbol) · Score \(Int(signal.confidencePercent.rounded()))"
        }

        let item = NotificationItemSnapshot(
            id: "confluence.signal.\(signal.fingerprint)",
            createdAt: Date(timeIntervalSince1970: signal.generatedAtEpochSeconds),
            type: (signal.category == .trapAlert) ? .trapAlert : .strongSignal,
            title: title,
            subtitle: signal.psychologyReport.whatHappened,
            symbol: signal.symbol,
            marketClass: signal.marketClass,
            timeframe: signal.timeframe,
            direction: signal.direction,
            confidence: signal.confidencePercent,
            signalFingerprint: signal.fingerprint,
            isRead: false
        )
        recordNotification(item)

        let decision = AlertRuleEvaluator.evaluateSignalAlert(
            signal: signal,
            globalMinScore: settings.payload.minimumConfidencePercent,
            rules: settings.payload.alertRules
        )
        guard decision.allowAnyDelivery else {
            if let reason = decision.suppressedReason {
                diagnosticLog.log(.info, category: .notification, message: "Suppressed alert for \(signal.symbol): \(reason)")
            }
            return
        }

        if isBackground {
            if decision.allowPush {
                await PreNewsNotificationScheduler.shared.postSignalNotification(signal, settings: settings.payload)
            }
        } else {
            if decision.allowBanner {
                let bannerKind: AlertBannerKind = (signal.category == .trapAlert) ? .trapAlert : .strongSignal(signal.direction)
                self.activeBanner = FloatingAlertBanner(
                    kind: bannerKind,
                    title: title,
                    subtitle: signal.psychologyReport.whatHappened,
                    targetSignalId: signal.fingerprint
                )
            }

            if decision.allowSound {
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
    }

    // MARK: - BGAppRefreshTask Registration & Scheduling

    public func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.backgroundTaskIdentifier, using: nil) { [weak self] task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let guardBox = BGTaskCompletionGuard(task: refreshTask)
            let work = Task { @MainActor [weak self] in
                guard let self else {
                    guardBox.completeOnce(success: false)
                    return
                }
                self.scheduleNextBackgroundRefresh()
                await self.scanAllMarkets(isBackground: true)
                guardBox.completeOnce(success: !Task.isCancelled)
            }
            refreshTask.expirationHandler = {
                work.cancel()
                guardBox.completeOnce(success: false)
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

private final class BGTaskCompletionGuard: @unchecked Sendable {
    private let lock = NSLock()
    private let task: BGAppRefreshTask
    private var completed = false

    init(task: BGAppRefreshTask) {
        self.task = task
    }

    func completeOnce(success: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return }
        completed = true
        task.setTaskCompleted(success: success)
    }
}
