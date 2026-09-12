import AppKit
import Combine

@MainActor
final class StatusBarController: NSObject {
    enum ClickKind: Equatable {
        case left
        case right
    }

    private let statusItem: NSStatusItem
    private let store: SystemStatusStore
    private var cancellable: AnyCancellable?
    private let quitAction: () -> Void
    private var appearanceObservation: NSKeyValueObservation?

    init(store: SystemStatusStore, quitAction: @escaping () -> Void) {
        self.store = store
        self.quitAction = quitAction
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureButton()
        render(snapshot: store.snapshot)

        cancellable = store.$snapshot
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] snapshot in
                self?.render(snapshot: snapshot)
            }

        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                self.render(snapshot: self.store.snapshot)
            }
        }
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

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard
            let event = NSApp.currentEvent,
            let click = Self.clickKind(eventType: event.type, modifiers: event.modifierFlags)
        else { return }

        switch click {
        case .left:
            break
        case .right:
            showMenu()
        }
    }

    private func render(snapshot: StatusSnapshot) {
        guard let button = statusItem.button else { return }
        button.image = StatusIconRenderer.image(
            snapshot: snapshot,
            appearance: button.effectiveAppearance
        )
    }

    private func showMenu() {
        let menu = StatusMenuBuilder.makeMenu(version: "1.0.0")
        guard let button = statusItem.button else { return }
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.maxY + 4),
            in: button
        )
    }
}
