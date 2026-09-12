import AppKit
import XCTest
@testable import StatusTrioCore

@MainActor
final class StatusMenuBuilderTests: XCTestCase {
    func testMenuContainsVersionPlaceholderAndQuit() {
        let menu = StatusMenuBuilder.makeMenu(version: "1.0.0")
        let versionItem = menu.items[0]
        let settingsItem = menu.items[1]
        let quitItem = menu.items[3]

        XCTAssertEqual(menu.items.map(\.title), [
            "Status Trio 1.0.0",
            "设置… · 即将推出",
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

    func testClickClassification() {
        XCTAssertEqual(StatusBarController.clickKind(eventType: .leftMouseUp, modifiers: []), .left)
        XCTAssertEqual(StatusBarController.clickKind(eventType: .rightMouseUp, modifiers: []), .right)
        XCTAssertEqual(StatusBarController.clickKind(eventType: .leftMouseUp, modifiers: [.control]), .right)
        XCTAssertNil(StatusBarController.clickKind(eventType: .leftMouseDown, modifiers: []))
        XCTAssertNil(StatusBarController.clickKind(eventType: .flagsChanged, modifiers: []))
    }
}
