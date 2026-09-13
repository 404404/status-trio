import AppKit
import XCTest
@testable import StatusTrioCore

@MainActor
final class StatusMenuBuilderTests: XCTestCase {
    func testMenuContainsVersionSettingsAndQuit() {
        let menu = StatusMenuBuilder.makeMenu(
            version: "1.0.0",
            settingsTarget: nil,
            settingsAction: nil
        )
        let versionItem = menu.items[0]
        let settingsItem = menu.items[1]
        let quitItem = menu.items[3]

        XCTAssertEqual(menu.items.map(\.title), [
            "Status Trio 1.0.0",
            "设置…",
            "",
            "退出 Status Trio"
        ])
        XCTAssertFalse(versionItem.isEnabled)
        XCTAssertFalse(settingsItem.isEnabled)
        XCTAssertTrue(quitItem.isEnabled)
        XCTAssertEqual(quitItem.keyEquivalent, "q")
        XCTAssertEqual(quitItem.keyEquivalentModifierMask, .command)
        XCTAssertTrue(quitItem.target === NSApplication.shared)
        XCTAssertEqual(quitItem.action, #selector(NSApplication.terminate(_:)))
    }

    func testSettingsItemUsesProvidedTargetAndAction() {
        let target = SettingsTarget()
        let menu = StatusMenuBuilder.makeMenu(
            version: "1.0.0",
            settingsTarget: target,
            settingsAction: #selector(SettingsTarget.openSettings)
        )
        let settingsItem = menu.items[1]

        XCTAssertTrue(settingsItem.isEnabled)
        XCTAssertTrue(settingsItem.target === target)
        XCTAssertEqual(settingsItem.action, #selector(SettingsTarget.openSettings))
    }

    private final class SettingsTarget: NSObject {
        @objc func openSettings() {}
    }

    func testStatusBarUpdateCadence() {
        XCTAssertEqual(StatusBarController.iconSnapshotDebounceInterval, 1)
        XCTAssertEqual(StatusBarController.iconFallbackRefreshInterval, 5)
    }

    func testClickClassification() {
        XCTAssertEqual(StatusBarController.clickKind(eventType: .leftMouseUp, modifiers: []), .left)
        XCTAssertEqual(StatusBarController.clickKind(eventType: .rightMouseUp, modifiers: []), .right)
        XCTAssertEqual(StatusBarController.clickKind(eventType: .leftMouseUp, modifiers: [.control]), .right)
        XCTAssertNil(StatusBarController.clickKind(eventType: .leftMouseDown, modifiers: []))
        XCTAssertNil(StatusBarController.clickKind(eventType: .flagsChanged, modifiers: []))
    }

    func testSystemSettingsURLFallbackOrder() {
        XCTAssertEqual(
            StatusBarController.wifiSettingsURLs.map(\.absoluteString),
            [
                "x-apple.systempreferences:com.apple.Network-Settings.extension",
                "x-apple.systempreferences:com.apple.preference.network"
            ]
        )
        XCTAssertEqual(
            StatusBarController.locationSettingsURLs.map(\.absoluteString),
            [
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocationServices",
                "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
            ]
        )
        XCTAssertEqual(
            StatusBarController.batterySettingsURLs.map(\.absoluteString),
            [
                "x-apple.systempreferences:com.apple.Battery-Settings.extension",
                "x-apple.systempreferences:com.apple.preference.battery"
            ]
        )
    }
}
