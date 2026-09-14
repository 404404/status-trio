import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?
    private var singleInstanceGuard: SingleInstanceGuard?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        guard let singleInstanceGuard = SingleInstanceGuard() else {
            NSApplication.shared.terminate(nil)
            return
        }
        self.singleInstanceGuard = singleInstanceGuard

        NSApplication.shared.setActivationPolicy(.accessory)
        if UpdaterManager.isEnabled {
            UpdaterManager.shared.start()
        }
        let environment = AppEnvironment.live()
        self.environment = environment
        environment.store.start()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        environment?.store.stop()
    }
}
