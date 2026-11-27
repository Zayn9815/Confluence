import SwiftUI

@main
public struct ConfluenceApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var coordinator: MarketScannerCoordinator
    private let isRunningTests: Bool

    public init() {
        let runningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        self.isRunningTests = runningTests
        let settings = runningTests ? AppSettingsStore(defaults: UserDefaults(suiteName: "com.bilal.confluence.testhost") ?? .standard) : AppSettingsStore()
        let store = ConfluenceDataStore(inMemory: runningTests)
        let coord = MarketScannerCoordinator(settings: settings, store: store)
        if !runningTests {
            NotificationCenterRouter.shared.registerAsDelegate()
            coord.crashLogStore.startMonitoring()
            coord.registerBackgroundTask()
        }
        _coordinator = State(initialValue: coord)
    }

    public var body: some Scene {
        WindowGroup {
            ConfluenceRootView(coordinator: coordinator)
                .onChange(of: scenePhase, initial: true) { _, newPhase in
                    guard !isRunningTests else { return }
                    switch newPhase {
                    case .active:
                        SignalSoundEngine.shared.prepareHaptics()
                        coordinator.handleScenePhaseActive(true)
                    case .background:
                        coordinator.handleScenePhaseActive(false)
                        coordinator.scheduleNextBackgroundRefresh()
                    case .inactive:
                        // Avoid tearing down live WebSockets during transient Control Center / Notification Center pull-downs
                        break
                    @unknown default:
                        break
                    }
                }
        }
    }
}
