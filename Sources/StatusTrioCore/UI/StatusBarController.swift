import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    enum ClickKind: Equatable {
        case left
        case right
    }

    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let store: SystemStatusStore
    private let settings: SettingsStore
    private var cancellable: AnyCancellable?
    private var iconSizeCancellable: AnyCancellable?
    private let openSettings: () -> Void
    private let quitAction: () -> Void
    private var appearanceObservations: [NSKeyValueObservation] = []

    init(
        store: SystemStatusStore,
        settings: SettingsStore,
        openSettings: @escaping () -> Void,
        quitAction: @escaping () -> Void
    ) {
        self.store = store
        self.settings = settings
        self.openSettings = openSettings
        self.quitAction = quitAction
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureButton()
        configurePopover()
        observeAppearanceChanges()
        scheduleInitialRender()

        cancellable = store.$snapshot
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] snapshot in
                self?.render(snapshot: snapshot)
            }

        iconSizeCancellable = settings.$iconSize
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.renderLatestSnapshot()
            }

        appearanceObservations.append(NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.renderLatestSnapshot()
            }
        })
    }

    static func clickKind(eventType: NSEvent.EventType, modifiers: NSEvent.ModifierFlags) -> ClickKind? {
        if eventType == .rightMouseUp || modifiers.contains(.control) {
            return .right
        }
        if eventType == .leftMouseUp {
            return .left
        }
        return nil
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func observeAppearanceChanges() {
        guard let button = statusItem.button else { return }
        appearanceObservations.append(button.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.renderLatestSnapshot()
            }
        })
    }

    private func scheduleInitialRender() {
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.renderLatestSnapshot()
        }
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard
            let event = NSApp.currentEvent,
            let click = Self.clickKind(eventType: event.type, modifiers: event.modifierFlags)
        else { return }

        switch click {
        case .left:
            togglePopover()
        case .right:
            popover.performClose(nil)
            showMenu()
        }
    }

    private func configurePopover() {
        popover.behavior = .transient
        let hostingController = NSHostingController(
            rootView: StatusPopoverView(
                store: store,
                openSettings: handleOpenSettings,
                openSoundSettings: handleOpenSoundSettings,
                quit: quitAction
            )
        )
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(
                relativeTo: button.bounds,
                of: button,
                preferredEdge: .minY
            )
        }
    }

    private func render(snapshot: StatusSnapshot) {
        guard let button = statusItem.button else { return }
        button.image = StatusIconRenderer.image(
            snapshot: snapshot,
            size: settings.iconSize,
            appearance: Self.resolvedAppearance(button: button)
        )
        button.setAccessibilityLabel(StatusPresentation.statusItemAccessibilityLabel)
        button.setAccessibilityValue(StatusPresentation.statusItemAccessibilityValue(snapshot))
    }

    private func renderLatestSnapshot() {
        render(snapshot: store.snapshot)
    }

    static func resolvedAppearance(
        button: NSStatusBarButton?,
        application: NSApplication = .shared
    ) -> NSAppearance {
        button?.window?.effectiveAppearance
            ?? button?.effectiveAppearance
            ?? application.effectiveAppearance
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    @objc private func handleOpenSettings() {
        popover.performClose(nil)
        openSettings()
    }

    @objc private func handleOpenSoundSettings() {
        popover.performClose(nil)
        Self.openSystemSoundSettings()
    }

    private static func openSystemSoundSettings() {
        let soundSettingsURLs = [
            "x-apple.systempreferences:com.apple.Sound-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.sound"
        ]
        .compactMap(URL.init(string:))

        for url in soundSettingsURLs where NSWorkspace.shared.open(url) {
            return
        }
    }

    private func showMenu() {
        let menu = StatusMenuBuilder.makeMenu(
            version: Self.appVersion,
            settingsTarget: self,
            settingsAction: #selector(handleOpenSettings)
        )
        guard let button = statusItem.button else { return }
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.maxY + 4),
            in: button
        )
    }
}
