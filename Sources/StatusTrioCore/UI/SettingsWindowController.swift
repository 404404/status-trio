import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let windowTitle = "设置"

    private let store: SettingsStore
    private(set) var window: NSWindow?

    init(store: SettingsStore) {
        self.store = store
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let hostingController = NSHostingController(rootView: SettingsView(store: store))
        let window = NSWindow(contentViewController: hostingController)
        window.title = Self.windowTitle
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
