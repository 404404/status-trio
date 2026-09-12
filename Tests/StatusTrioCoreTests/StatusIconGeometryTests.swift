import CoreGraphics
import XCTest
@testable import StatusTrioCore

final class StatusIconGeometryTests: XCTestCase {
    private let wifiOuterBounds = CGRect(
        x: 38.496939589591584,
        y: 47.3,
        width: 42.00612082081681,
        height: 8.19931024296119
    )
    private let wifiMiddleBounds = CGRect(
        x: 47.00158115911029,
        y: 60.39,
        width: 24.996837681779425,
        height: 4.860369269012708
    )

    func testBatteryPathsStayInsideCanvas() {
        let track = StatusIconGeometry.batteryTrack()
        let fill = StatusIconGeometry.batteryFill(progress: 0.5)

        XCTAssertTrue(StatusIconGeometry.canvas.contains(track.boundingBox))
        XCTAssertTrue(StatusIconGeometry.canvas.contains(fill.boundingBox))
    }

    func testBatteryFullAndHalfProgressBounds() {
        let track = StatusIconGeometry.batteryTrack()
        let fill = StatusIconGeometry.batteryFill(progress: 0.5)

        assertPathBounds(
            track,
            equals: CGRect(
                x: 7.992512326287086,
                y: 9.979664944141817,
                width: 103.00748767371292,
                height: 78.27033505585817
            )
        )
        assertPathBounds(
            fill,
            equals: CGRect(
                x: 7.992512326287086,
                y: 9.987152617854733,
                width: 51.50748767371291,
                height: 78.26284738214525
            )
        )
        XCTAssertTrue(track.boundingBox.contains(fill.boundingBox))
        assertPoint(fill.currentPoint, equals: CGPoint(x: 59.5, y: 9.987152617854733))
    }

    func testZeroBatteryHasNoFillPath() {
        XCTAssertTrue(StatusIconGeometry.batteryFill(progress: 0).isEmpty)
    }

    func testWiFiLevelBoundaries() {
        for level in [-1, 0, 1] {
            XCTAssertTrue(
                StatusIconGeometry.wifiArcs(level: level).isEmpty,
                "Level \(level) should not draw Wi-Fi arcs"
            )
        }

        let level2 = StatusIconGeometry.wifiArcs(level: 2)
        XCTAssertEqual(level2.count, 1)
        assertPathBounds(level2[0], equals: wifiMiddleBounds)

        for level in [3, 4] {
            let arcs = StatusIconGeometry.wifiArcs(level: level)
            XCTAssertEqual(arcs.count, 2)
            assertPathBounds(arcs[0], equals: wifiOuterBounds)
            assertPathBounds(arcs[1], equals: wifiMiddleBounds)
        }
    }

    func testWiFiArcBounds() {
        assertPathBounds(StatusIconGeometry.wifiOuterArc(), equals: wifiOuterBounds)

        let middleArcs = StatusIconGeometry.wifiArcs(level: 2)
        XCTAssertEqual(middleArcs.count, 1)
        assertPathBounds(middleArcs[0], equals: wifiMiddleBounds)
    }

    func testWiFiDotBounds() {
        assertPathBounds(
            StatusIconGeometry.wifiDot(),
            equals: CGRect(x: 52.35, y: 69.9, width: 14.3, height: 11.05)
        )
    }

    func testWiFiOffSlashBounds() {
        assertPathBounds(
            StatusIconGeometry.wifiOffSlash(),
            equals: CGRect(x: 39, y: 46, width: 42, height: 33)
        )
    }

    func testNoInternetOverlayBounds() {
        let overlay = StatusIconGeometry.noInternetOverlay()

        assertPathBounds(
            overlay.stem,
            equals: CGRect(x: 59.5, y: 54.5, width: 0, height: 12.5)
        )
        assertPathBounds(
            overlay.dot,
            equals: CGRect(x: 56.9, y: 72.9, width: 5.2, height: 5.2)
        )
    }

    func testHotspotOverlayBounds() {
        let paths = StatusIconGeometry.hotspotOverlay()
        XCTAssertEqual(paths.count, 3)

        assertPathBounds(paths[0], equals: CGRect(x: 41, y: 50, width: 13, height: 16))
        assertPathBounds(paths[1], equals: CGRect(x: 65, y: 50, width: 13, height: 16))
        assertPathBounds(paths[2], equals: CGRect(x: 51, y: 58, width: 17, height: 0))
    }

    func testVolumeDots() {
        let dots = StatusIconGeometry.volumeDots()
        let expected = [
            CGPoint(x: 33, y: 104.2),
            CGPoint(x: 50.5, y: 111.2),
            CGPoint(x: 68.5, y: 111.7),
            CGPoint(x: 86, y: 105.8)
        ]

        XCTAssertEqual(dots.count, expected.count)
        for (dot, expectedDot) in zip(dots, expected) {
            assertPoint(dot, equals: expectedDot)
        }
        XCTAssertEqual(StatusIconGeometry.volumeDotRadius, 5.5, accuracy: 0.01)
    }

    private func assertPathBounds(
        _ path: CGPath,
        equals expected: CGRect,
        accuracy: CGFloat = 0.01,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertBounds(path.boundingBoxOfPath, equals: expected, accuracy: accuracy, file: file, line: line)
    }

    private func assertBounds(
        _ actual: CGRect,
        equals expected: CGRect,
        accuracy: CGFloat = 0.01,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: accuracy, file: file, line: line)
    }

    private func assertPoint(
        _ actual: CGPoint,
        equals expected: CGPoint,
        accuracy: CGFloat = 0.01,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.x, expected.x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: accuracy, file: file, line: line)
    }
}

private extension CGRect {
    func contains(_ other: CGRect) -> Bool {
        CGRectContainsRect(insetBy(dx: -0.01, dy: -0.01), other)
    }
}
