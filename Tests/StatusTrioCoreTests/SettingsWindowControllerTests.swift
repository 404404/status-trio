import AppKit
import XCTest
@testable import StatusTrioCore

@MainActor
final class SettingsWindowControllerTests: XCTestCase {
    func testShowCreatesReusesAndLocalizesSingleWindow() throws {
        let suiteName = "StatusTrioCoreTests.SettingsWindow.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        localization.setPreference(.language(.simplifiedChinese))
        let controller = SettingsWindowController(
            store: SettingsStore(defaults: defaults),
            localization: localization
        )
        XCTAssertNil(controller.window)

        controller.show()
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }

        XCTAssertEqual(window.title, "设置")
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertTrue(window.isVisible)

        localization.setPreference(.language(.german))
        XCTAssertEqual(window.title, "Einstellungen")

        controller.show()
        XCTAssertTrue(controller.window === window)
    }
}
