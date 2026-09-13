import AppKit
import Combine
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let store: SettingsStore
    private let localization: Localization
    private var localizationCancellable: AnyCancellable?
    private(set) var window: NSWindow?

    init(store: SettingsStore, localization: Localization) {
        self.store = store
        self.localization = localization

        localizationCancellable = localization.$resolvedLanguage
            .removeDuplicates()
            .sink { [weak self] language in
                self?.applyLocalization(language: language)
            }
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        applyLocalization()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let rootView = LocalizedRootView(localization: localization) {
            SettingsView(store: store)
        }
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func applyLocalization(language: AppLanguage? = nil) {
        let language = language ?? localization.resolvedLanguage
        window?.title = localization.string(.settingsTitle, language: language)
        window?.contentView?.userInterfaceLayoutDirection = language.nsLayoutDirection
    }
}
