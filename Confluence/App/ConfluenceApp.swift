import SwiftUI

@main
public struct ConfluenceApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var coordinator: MarketScannerCoordinator

    public init() {
        NotificationCenterRouter.shared.registerAsDelegate()
        let settings = AppSettingsStore()
        let store = ConfluenceDataStore()
        let coord = MarketScannerCoordinator(settings: settings, store: store)
        coord.crashLogStore.startMonitoring()
        coord.registerBackgroundTask()
        _coordinator = State(initialValue: coord)
    }

    public var body: some Scene {
        WindowGroup {
            ConfluenceRootView(coordinator: coordinator)
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        SignalSoundEngine.shared.prepareHaptics()
                        coordinator.handleScenePhaseActive(true)
                    case .background:
                        coordinator.handleScenePhaseActive(false)
                        coordinator.scheduleNextBackgroundRefresh()
                    case .inactive:
                        coordinator.handleScenePhaseActive(false)
                    @unknown default:
                        break
                    }
                }
        }
    }
}
