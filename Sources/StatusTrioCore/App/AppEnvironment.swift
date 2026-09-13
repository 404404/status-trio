import AppKit

@MainActor
final class AppEnvironment {
    let store: SystemStatusStore
    let settings: SettingsStore
    let statusBarController: StatusBarController
    let settingsWindowController: SettingsWindowController

    init(
        store: SystemStatusStore,
        settings: SettingsStore,
        statusBarController: StatusBarController,
        settingsWindowController: SettingsWindowController
    ) {
        self.store = store
        self.settings = settings
        self.statusBarController = statusBarController
        self.settingsWindowController = settingsWindowController
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
        let settings = SettingsStore()
        let settingsWindowController = SettingsWindowController(store: settings)
        let controller = StatusBarController(
            store: store,
            settings: settings,
            openSettings: { settingsWindowController.show() },
            quitAction: { NSApplication.shared.terminate(nil) }
        )
        return AppEnvironment(
            store: store,
            settings: settings,
            statusBarController: controller,
            settingsWindowController: settingsWindowController
        )
    }
}
