import AppKit

@MainActor
enum StatusMenuBuilder {
    static func makeMenu(version: String) -> NSMenu {
        let menu = NSMenu()

        let versionItem = NSMenuItem(
            title: "Status Trio \(version)",
            action: nil,
            keyEquivalent: ""
        )
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        let settingsItem = NSMenuItem(
            title: StatusPresentation.settingsPlaceholder,
            action: nil,
            keyEquivalent: ""
        )
        settingsItem.isEnabled = false
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出 Status Trio",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApplication.shared
        menu.addItem(quitItem)

        return menu
    }
}
