import AppKit
import XCTest
@testable import StatusTrioCore

@MainActor
final class SettingsWindowControllerTests: XCTestCase {
    func testShowCreatesAndReusesSingleVisibleWindow() throws {
        let suiteName = "StatusTrioCoreTests.SettingsWindow.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let controller = SettingsWindowController(store: SettingsStore(defaults: defaults))
        XCTAssertNil(controller.window)

        controller.show()
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }

        XCTAssertEqual(window.title, "设置")
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertTrue(window.isVisible)

        controller.show()
        XCTAssertTrue(controller.window === window)
    }
}
