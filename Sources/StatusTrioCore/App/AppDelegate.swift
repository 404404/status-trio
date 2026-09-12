import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let environment = AppEnvironment.live()
        self.environment = environment
        environment.store.start()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        environment?.store.stop()
    }
}
