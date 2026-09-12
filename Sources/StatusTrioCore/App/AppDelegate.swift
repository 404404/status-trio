import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: SystemStatusStore?
    private var statusBarController: StatusBarController?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        let store = SystemStatusStore(
            batteryMonitor: UnavailableBatteryMonitor(),
            wifiMonitor: UnavailableWiFiMonitor(),
            volumeMonitor: UnavailableVolumeMonitor()
        )
        let controller = StatusBarController(store: store) {
            NSApplication.shared.terminate(nil)
        }

        self.store = store
        self.statusBarController = controller
        store.start()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        store?.stop()
    }
}
