import AppKit

@MainActor
enum StatusMenuBuilder {
    static func makeMenu(
        version: String,
        settingsTarget: AnyObject?,
        settingsAction: Selector?,
        localization: Localization
    ) -> NSMenu {
        let menu = NSMenu()
        menu.userInterfaceLayoutDirection =
            localization.resolvedLanguage.nsLayoutDirection

        let versionItem = NSMenuItem(
            title: localization.format(.menuVersion, version),
            action: nil,
            keyEquivalent: ""
        )
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        let settingsItem = NSMenuItem(
            title: localization.string(.menuSettings),
            action: settingsAction,
            keyEquivalent: ""
        )
        settingsItem.target = settingsTarget
        settingsItem.isEnabled = settingsAction != nil
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: localization.string(.menuQuit),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApplication.shared
        menu.addItem(quitItem)

        return menu
    }
}
