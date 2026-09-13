import AppKit
import Combine
import XCTest
@testable import StatusTrioCore

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testDefaultsMatchSpecifiedRange() {
        XCTAssertEqual(SettingsStore.iconSizeRange, 20...32)

        let store = SettingsStore(defaults: makeSuite().defaults)
        XCTAssertEqual(store.iconSize, 28, accuracy: 0.001)
    }

    func testIconSizeAboveRangeIsClampedToUpperBound() {
        let store = SettingsStore(defaults: makeSuite().defaults)

        store.iconSize = 120

        XCTAssertEqual(store.iconSize, 32, accuracy: 0.001)
    }

    func testIconSizeBelowRangeIsClampedToLowerBound() {
        let store = SettingsStore(defaults: makeSuite().defaults)

        store.iconSize = 3

        XCTAssertEqual(store.iconSize, 20, accuracy: 0.001)
    }

    func testIconSizePersistsAcrossStoreInstances() {
        let suite = makeSuite()
        defer { clear(suite) }

        SettingsStore(defaults: suite.defaults).iconSize = 22

        XCTAssertEqual(SettingsStore(defaults: suite.defaults).iconSize, 22, accuracy: 0.001)
    }

    func testStoredValueOutsideRangeIsClampedOnLoad() {
        let suite = makeSuite()
        defer { clear(suite) }
        suite.defaults.set(120, forKey: SettingsStore.iconSizeDefaultsKey)

        XCTAssertEqual(SettingsStore(defaults: suite.defaults).iconSize, 32, accuracy: 0.001)
    }

    func testStoredNonNumericValueFallsBackToDefault() {
        let suite = makeSuite()
        defer { clear(suite) }
        suite.defaults.set("huge", forKey: SettingsStore.iconSizeDefaultsKey)

        XCTAssertEqual(SettingsStore(defaults: suite.defaults).iconSize, 28, accuracy: 0.001)
    }

    func testClampHelperRejectsNonFiniteValues() {
        XCTAssertEqual(SettingsStore.clampedIconSize(.nan), 28, accuracy: 0.001)
        XCTAssertEqual(SettingsStore.clampedIconSize(.infinity), 28, accuracy: 0.001)
        XCTAssertEqual(SettingsStore.clampedIconSize(-.infinity), 28, accuracy: 0.001)
    }

    func testIconSizeChangeNotifiesSubscribers() {
        let store = SettingsStore(defaults: makeSuite().defaults)
        var received: [Double] = []
        let cancellable = store.$iconSize.sink { received.append($0) }

        store.iconSize = 21

        withExtendedLifetime(cancellable) {
            XCTAssertEqual(received, [28, 21])
        }
    }

    func testEveryConfigurableSizeRendersAtThatSize() throws {
        let appearance = try XCTUnwrap(NSAppearance(named: .aqua))

        for value in stride(
            from: SettingsStore.iconSizeRange.lowerBound,
            through: SettingsStore.iconSizeRange.upperBound,
            by: 1
        ) {
            let image = StatusIconRenderer.image(
                snapshot: .placeholder,
                size: value,
                appearance: appearance
            )

            XCTAssertEqual(image.size.width, value, accuracy: 0.01, "width at \(value) pt")
            XCTAssertEqual(image.size.height, value, accuracy: 0.01, "height at \(value) pt")
        }
    }

    private func makeSuite() -> (defaults: UserDefaults, name: String) {
        let name = "StatusTrioCoreTests.SettingsStore.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            fatalError("could not create isolated user defaults suite")
        }
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }

    private func clear(_ suite: (defaults: UserDefaults, name: String)) {
        suite.defaults.removePersistentDomain(forName: suite.name)
    }
}
