import SwiftUI

@main
public struct ConfluenceApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var coordinator: MarketScannerCoordinator

    public init() {
        let settings = AppSettingsStore()
        let store = ConfluenceDataStore()
        let coord = MarketScannerCoordinator(settings: settings, store: store)
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
                    case .background:
                        coordinator.scheduleNextBackgroundRefresh()
                    default:
                        break
                    }
                }
        }
    }
}
