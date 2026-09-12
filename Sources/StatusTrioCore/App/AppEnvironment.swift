import AppKit

@MainActor
final class AppEnvironment {
    let store: SystemStatusStore
    let statusBarController: StatusBarController

    init(
        store: SystemStatusStore,
        statusBarController: StatusBarController
    ) {
        self.store = store
        self.statusBarController = statusBarController
    }

    static func makeStore(
        batteryMonitor: any BatteryMonitoring,
        wifiMonitor: any WiFiMonitoring,
        volumeMonitor: any VolumeMonitoring
    ) -> SystemStatusStore {
        SystemStatusStore(
            batteryMonitor: batteryMonitor,
            wifiMonitor: wifiMonitor,
            volumeMonitor: volumeMonitor
        )
    }

    static func live() -> AppEnvironment {
        let store = makeStore(
            batteryMonitor: BatteryMonitor(),
            wifiMonitor: WiFiMonitor(),
            volumeMonitor: VolumeMonitor()
        )
        let controller = StatusBarController(store: store) {
            NSApplication.shared.terminate(nil)
        }
        return AppEnvironment(store: store, statusBarController: controller)
    }
}
