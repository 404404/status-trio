import AppKit
import Combine
import Sparkle
import SwiftUI

@MainActor
final class UpdaterManager: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = UpdaterManager()

    /// Release-only fork builds set this key to false while they do not have a
    /// Sparkle key pair. A missing key keeps source/test builds usable.
    static var isEnabled: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "StatusTrioEnableSparkle") as? Bool) ?? true
    }

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false

    private var controller: SPUStandardUpdaterController?
    private var isShowingManualUpdateUI = false

    var automaticallyChecksForUpdatesBinding: Binding<Bool> {
        Binding(
            get: { self.automaticallyChecksForUpdates },
            set: { enabled in
                guard let controller = self.controller else { return }
                controller.updater.automaticallyChecksForUpdates = enabled
            }
        )
    }

    private override init() {
        super.init()
        guard Self.isEnabled else { return }

        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .assign(to: &$automaticallyChecksForUpdates)
    }

    func start() {
        #if DEBUG
        return
        #else
        guard Self.isEnabled, let controller else { return }
        controller.startUpdater()
        #endif
    }

    func checkForUpdates() {
        #if DEBUG
        return
        #else
        guard Self.isEnabled, let controller, canCheckForUpdates else { return }

        isShowingManualUpdateUI = true
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
        #endif
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        guard isShowingManualUpdateUI else { return }
        isShowingManualUpdateUI = false
        NSApp.setActivationPolicy(.accessory)
    }
}
