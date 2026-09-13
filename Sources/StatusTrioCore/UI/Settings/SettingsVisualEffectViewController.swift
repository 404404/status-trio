import AppKit
import SwiftUI

@MainActor
final class SettingsVisualEffectViewController<Content: View>: NSViewController {
    private let localization: Localization
    private let content: Content

    init(
        localization: Localization,
        @ViewBuilder content: () -> Content
    ) {
        self.localization = localization
        self.content = content()
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let effectView = NSVisualEffectView()
        effectView.material = .toolTip
        effectView.blendingMode = .behindWindow
        effectView.state = .followsWindowActiveState

        let rootView = LocalizedRootView(localization: localization) {
            content
        }
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        effectView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: effectView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
        ])

        view = effectView
    }
}
