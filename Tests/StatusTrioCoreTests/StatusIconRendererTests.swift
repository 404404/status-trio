import AppKit
import CoreGraphics
import XCTest
@testable import StatusTrioCore

final class StatusIconRendererTests: XCTestCase {
    func testRendererProducesExpectedPixelSize() throws {
        let image = try XCTUnwrap(StatusIconRenderer.render(
            snapshot: .placeholder,
            size: 20,
            scale: 2,
            foreground: CGColor(gray: 1, alpha: 1)
        ))

        XCTAssertEqual(image.width, 40)
        XCTAssertEqual(image.height, 40)
    }

    func testRendererRejectsNonPositiveSizeOrScale() {
        let snapshot = StatusSnapshot.placeholder
        let foreground = CGColor(gray: 1, alpha: 1)

        XCTAssertNil(StatusIconRenderer.render(
            snapshot: snapshot,
            size: 0,
            scale: 2,
            foreground: foreground
        ))
        XCTAssertNil(StatusIconRenderer.render(
            snapshot: snapshot,
            size: -1,
            scale: 2,
            foreground: foreground
        ))
        XCTAssertNil(StatusIconRenderer.render(
            snapshot: snapshot,
            size: 20,
            scale: 0,
            foreground: foreground
        ))
        XCTAssertNil(StatusIconRenderer.render(
            snapshot: snapshot,
            size: 20,
            scale: -1,
            foreground: foreground
        ))
    }

    func testForegroundStateDrawsRedPixels() throws {
        let red = try XCTUnwrap(CGColor(
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            components: [1, 0, 0, 1]
        ))
        let pixels = try PixelBuffer(
            image: try XCTUnwrap(StatusIconRenderer.render(
                snapshot: .placeholder,
                size: 20,
                scale: 2,
                foreground: red
            ))
        )

        XCTAssertTrue(pixels.containsColor(
            red: 1,
            green: 0,
            blue: 0,
            tolerance: 0.02,
            minimumAlpha: 0.9
        ))
    }

    func testChargingStateDrawsGreenPixels() throws {
        let snapshot = StatusSnapshot(
            battery: BatteryStatus(
                rawPercentage: 50,
                isPresent: true,
                isCharging: true,
                isLowPowerMode: false,
                isConnectedToPower: true
            ),
            wifi: .placeholder,
            volume: .placeholder
        )

        let pixels = try PixelBuffer(
            image: try XCTUnwrap(StatusIconRenderer.render(
                snapshot: snapshot,
                size: 20,
                scale: 2,
                foreground: CGColor(gray: 1, alpha: 1)
            ))
        )

        XCTAssertTrue(pixels.containsColor(
            red: 0.20,
            green: 0.78,
            blue: 0.35,
            tolerance: 0.08,
            minimumAlpha: 0.9
        ))
    }

    func testOffAndUnavailableStatesDrawSlashOutsideWiFiArcs() throws {
        let offSnapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .off, rssi: nil),
            volume: .placeholder
        )
        let unavailableSnapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .unavailable, rssi: nil),
            volume: .placeholder
        )
        let notAssociatedSnapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .notAssociated, rssi: nil),
            volume: .placeholder
        )
        let offPixels = try PixelBuffer(
            image: try XCTUnwrap(StatusIconRenderer.render(
                snapshot: offSnapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1)
            ))
        )
        let unavailablePixels = try PixelBuffer(
            image: try XCTUnwrap(StatusIconRenderer.render(
                snapshot: unavailableSnapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1)
            ))
        )
        let notAssociatedPixels = try PixelBuffer(
            image: try XCTUnwrap(StatusIconRenderer.render(
                snapshot: notAssociatedSnapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1)
            ))
        )
        let slashPoint = CGPoint(x: 75, y: 73)

        XCTAssertGreaterThan(
            offPixels.alpha(atSVGPoint: slashPoint, size: 20, scale: 8),
            0
        )
        XCTAssertGreaterThan(
            unavailablePixels.alpha(atSVGPoint: slashPoint, size: 20, scale: 8),
            0
        )
        XCTAssertEqual(
            notAssociatedPixels.alpha(atSVGPoint: slashPoint, size: 20, scale: 8),
            0
        )
    }

    func testNoInternetOmitsNormalWiFiDotWhileKeepingOverlay() throws {
        let snapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .noInternet, rssi: nil),
            volume: .placeholder
        )
        let pixels = try PixelBuffer(
            image: try XCTUnwrap(StatusIconRenderer.render(
                snapshot: snapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1)
            ))
        )

        // The exclamation dot overlaps the full normal-dot centroid, so sample
        // the centroid of the normal dot's uncovered lower region.
        let uncoveredNormalDotCentroid = CGPoint(x: 59.5, y: 79.17)
        let overlayStem = CGPoint(x: 59.5, y: 60)

        XCTAssertEqual(
            pixels.alpha(atSVGPoint: uncoveredNormalDotCentroid, size: 20, scale: 8),
            0
        )
        XCTAssertGreaterThan(
            pixels.alpha(atSVGPoint: overlayStem, size: 20, scale: 8),
            0
        )
    }

    func testLowPowerStateDrawsYellowPixels() throws {
        let snapshot = StatusSnapshot(
            battery: BatteryStatus(
                rawPercentage: 50,
                isPresent: true,
                isCharging: false,
                isLowPowerMode: true,
                isConnectedToPower: false
            ),
            wifi: .placeholder,
            volume: .placeholder
        )

        let pixels = try PixelBuffer(
            image: try XCTUnwrap(StatusIconRenderer.render(
                snapshot: snapshot,
                size: 20,
                scale: 2,
                foreground: CGColor(gray: 1, alpha: 1)
            ))
        )

        XCTAssertTrue(pixels.containsColor(
            red: 0.95,
            green: 0.73,
            blue: 0.0,
            tolerance: 0.08,
            minimumAlpha: 0.9
        ))
    }

    func testAppKitWrapperProducesBitmapRepresentation() throws {
        let appearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let image = StatusIconRenderer.image(
            snapshot: .placeholder,
            size: 20,
            appearance: appearance
        )

        XCTAssertEqual(image.size.width, 20, accuracy: 0.01)
        XCTAssertEqual(image.size.height, 20, accuracy: 0.01)

        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
    }

    func testConnectedZeroBarsMatchesFullMutedSignalAndDiffersFromHigherBars() throws {
        let zeroBars = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .connected, rssi: nil),
            volume: .placeholder
        )
        let notAssociated = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .notAssociated, rssi: nil),
            volume: .placeholder
        )
        let oneBar = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .connected, rssi: -85),
            volume: .placeholder
        )
        let twoBars = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .connected, rssi: -70),
            volume: .placeholder
        )
        let threeBars = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .connected, rssi: -55),
            volume: .placeholder
        )

        let zeroPixels = try renderPixels(zeroBars)
        XCTAssertEqual(zeroPixels.bytes, try renderPixels(notAssociated).bytes)
        XCTAssertNotEqual(zeroPixels.bytes, try renderPixels(oneBar).bytes)
        XCTAssertNotEqual(zeroPixels.bytes, try renderPixels(twoBars).bytes)
        XCTAssertNotEqual(zeroPixels.bytes, try renderPixels(threeBars).bytes)
    }

    func testConnectedNonzeroSignalAlphaSumIncreasesWithBars() throws {
        let rssiValues: [Int?] = [-85, -70, -55]
        let signalRegion = CGRect(x: 35, y: 43, width: 50, height: 43)
        var alphaSums: [Int] = []

        for rssi in rssiValues {
            let snapshot = StatusSnapshot(
                battery: .placeholder,
                wifi: WiFiStatus(state: .connected, rssi: rssi),
                volume: .placeholder
            )
            let pixels = try renderPixels(snapshot)
            alphaSums.append(pixels.alphaSum(
                inSVGRect: signalRegion,
                size: 20,
                scale: 8
            ))
        }

        for index in 0..<(alphaSums.count - 1) {
            XCTAssertLessThan(alphaSums[index], alphaSums[index + 1])
        }
    }

    func testRendererResolvesForegroundForAquaAndDarkAqua() throws {
        let snapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .connected, rssi: -55),
            volume: .placeholder
        )
        let aqua = try XCTUnwrap(NSAppearance(named: .aqua))
        let darkAqua = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let aquaPixels = try renderPixels(image: StatusIconRenderer.image(
            snapshot: snapshot,
            size: 20,
            appearance: aqua
        ))
        let darkAquaPixels = try renderPixels(image: StatusIconRenderer.image(
            snapshot: snapshot,
            size: 20,
            appearance: darkAqua
        ))
        let aquaLuminance = try XCTUnwrap(aquaPixels.averageOpaqueLuminance())
        let darkAquaLuminance = try XCTUnwrap(darkAquaPixels.averageOpaqueLuminance())

        XCTAssertLessThan(aquaLuminance, 0.2)
        XCTAssertGreaterThan(darkAquaLuminance, 0.8)
        XCTAssertGreaterThan(darkAquaLuminance - aquaLuminance, 0.6)
    }

    func testHotspotOverlayPointIsUnique() throws {
        let hotspotSnapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .hotspot, rssi: nil),
            volume: .placeholder
        )
        let connectedSnapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .connected, rssi: -55),
            volume: .placeholder
        )
        let hotspotPixels = try PixelBuffer(
            image: try XCTUnwrap(StatusIconRenderer.render(
                snapshot: hotspotSnapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1)
            ))
        )
        let connectedPixels = try PixelBuffer(
            image: try XCTUnwrap(StatusIconRenderer.render(
                snapshot: connectedSnapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1)
            ))
        )
        let hotspotOnlyPoint = CGPoint(x: 41.5, y: 58)

        XCTAssertGreaterThan(
            hotspotPixels.alpha(atSVGPoint: hotspotOnlyPoint, size: 20, scale: 8),
            0
        )
        XCTAssertEqual(
            connectedPixels.alpha(atSVGPoint: hotspotOnlyPoint, size: 20, scale: 8),
            0
        )
    }

    func testTemporaryAndSharedStatesRenderExpectedSizeAndMasks() throws {
        let temporarySnapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .temporary, rssi: -50),
            volume: .placeholder
        )
        let sharedSnapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .shared, rssi: -50),
            volume: .placeholder
        )
        let connectedSnapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .connected, rssi: -50),
            volume: .placeholder
        )

        let temporaryImage = try XCTUnwrap(StatusIconRenderer.render(
            snapshot: temporarySnapshot,
            size: 20,
            scale: 2,
            foreground: CGColor(gray: 1, alpha: 1)
        ))
        let sharedImage = try XCTUnwrap(StatusIconRenderer.render(
            snapshot: sharedSnapshot,
            size: 20,
            scale: 2,
            foreground: CGColor(gray: 1, alpha: 1)
        ))

        XCTAssertEqual(temporaryImage.width, 40)
        XCTAssertEqual(temporaryImage.height, 40)
        XCTAssertEqual(sharedImage.width, 40)
        XCTAssertEqual(sharedImage.height, 40)

        let pixelScale: CGFloat = 16
        let temporaryPixels = try PixelBuffer(
            image: try XCTUnwrap(StatusIconRenderer.render(
                snapshot: temporarySnapshot,
                size: 20,
                scale: pixelScale,
                foreground: CGColor(gray: 1, alpha: 1)
            ))
        )
        let sharedPixels = try PixelBuffer(
            image: try XCTUnwrap(StatusIconRenderer.render(
                snapshot: sharedSnapshot,
                size: 20,
                scale: pixelScale,
                foreground: CGColor(gray: 1, alpha: 1)
            ))
        )
        let connectedPixels = try PixelBuffer(
            image: try XCTUnwrap(StatusIconRenderer.render(
                snapshot: connectedSnapshot,
                size: 20,
                scale: pixelScale,
                foreground: CGColor(gray: 1, alpha: 1)
            ))
        )
        let outerEdgePoint = CGPoint(x: 59.5, y: 50.5)

        XCTAssertGreaterThan(
            temporaryPixels.alpha(atSVGPoint: outerEdgePoint, size: 20, scale: pixelScale),
            0
        )
        XCTAssertGreaterThan(
            sharedPixels.alpha(atSVGPoint: outerEdgePoint, size: 20, scale: pixelScale),
            0
        )
        XCTAssertGreaterThan(
            temporaryPixels.alpha(
                atSVGPoint: CGPoint(x: 59.5, y: 59.5),
                size: 20,
                scale: pixelScale
            ),
            0
        )
        XCTAssertEqual(
            temporaryPixels.alpha(
                atSVGPoint: CGPoint(x: 59.5, y: 53.5),
                size: 20,
                scale: pixelScale
            ),
            0
        )
        XCTAssertEqual(
            temporaryPixels.alpha(
                atSVGPoint: CGPoint(x: 59.5, y: 68.5),
                size: 20,
                scale: pixelScale
            ),
            0
        )
        XCTAssertEqual(
            sharedPixels.alpha(
                atSVGPoint: CGPoint(x: 59.5, y: 72),
                size: 20,
                scale: pixelScale
            ),
            0
        )

        let volumeRegion = CGRect(x: 25, y: 92, width: 75, height: 28)
        let connectedVolumeAlpha = connectedPixels.alphaSum(
            inSVGRect: volumeRegion,
            size: 20,
            scale: pixelScale
        )
        XCTAssertEqual(
            temporaryPixels.alphaSum(
                inSVGRect: volumeRegion,
                size: 20,
                scale: pixelScale
            ),
            connectedVolumeAlpha
        )
        XCTAssertEqual(
            sharedPixels.alphaSum(
                inSVGRect: volumeRegion,
                size: 20,
                scale: pixelScale
            ),
            connectedVolumeAlpha
        )
        XCTAssertNotEqual(temporaryPixels.bytes, sharedPixels.bytes)
    }

    func testVolumeAlphaSumIncreasesWithVisibleDots() throws {
        let scalars = [0.0, 0.25, 0.50, 0.75, 1.0]
        let volumeRegion = CGRect(x: 25, y: 92, width: 75, height: 28)
        var alphaSums: [Int] = []

        for scalar in scalars {
            let snapshot = StatusSnapshot(
                battery: .placeholder,
                wifi: .placeholder,
                volume: VolumeStatus(
                    scalar: scalar,
                    isMuted: false,
                    deviceName: nil
                )
            )
            let pixels = try PixelBuffer(
                image: try XCTUnwrap(StatusIconRenderer.render(
                    snapshot: snapshot,
                    size: 20,
                    scale: 8,
                    foreground: CGColor(gray: 1, alpha: 1)
                ))
            )
            alphaSums.append(pixels.alphaSum(
                inSVGRect: volumeRegion,
                size: 20,
                scale: 8
            ))
        }

        for index in 0..<(alphaSums.count - 1) {
            XCTAssertLessThan(alphaSums[index], alphaSums[index + 1])
        }
    }

    func testMutedVolumeMatchesZeroVolume() throws {
        let zeroSnapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: .placeholder,
            volume: VolumeStatus(scalar: 0, isMuted: false, deviceName: nil)
        )
        let mutedSnapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: .placeholder,
            volume: VolumeStatus(scalar: 0.8, isMuted: true, deviceName: nil)
        )
        let zeroPixels = try PixelBuffer(
            image: try XCTUnwrap(StatusIconRenderer.render(
                snapshot: zeroSnapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1)
            ))
        )
        let mutedPixels = try PixelBuffer(
            image: try XCTUnwrap(StatusIconRenderer.render(
                snapshot: mutedSnapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1)
            ))
        )

        XCTAssertEqual(mutedPixels.bytes, zeroPixels.bytes)
    }

    func testZeroVolumeDrawsFourHiddenDots() throws {
        let snapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: .placeholder,
            volume: VolumeStatus(scalar: 0, isMuted: false, deviceName: nil)
        )
        let pixels = try PixelBuffer(
            image: try XCTUnwrap(StatusIconRenderer.render(
                snapshot: snapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1)
            ))
        )
        let expectedAlpha = 0.22 * 255.0

        for point in StatusIconGeometry.volumeDots() {
            let alpha = Double(pixels.alpha(atSVGPoint: point, size: 20, scale: 8))
            XCTAssertEqual(alpha, expectedAlpha, accuracy: 2)
        }
    }

    private func renderPixels(_ snapshot: StatusSnapshot) throws -> PixelBuffer {
        try PixelBuffer(
            image: try XCTUnwrap(StatusIconRenderer.render(
                snapshot: snapshot,
                size: 20,
                scale: 8,
                foreground: CGColor(gray: 1, alpha: 1)
            ))
        )
    }

    private func renderPixels(image: NSImage) throws -> PixelBuffer {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            data: try XCTUnwrap(image.tiffRepresentation)
        ))
        return try PixelBuffer(
            image: try XCTUnwrap(bitmap.cgImage)
        )
    }
}

private struct PixelBuffer {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init(image: CGImage) throws {
        width = image.width
        height = image.height
        var storage = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &storage,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        bytes = storage
    }

    func alpha(atSVGPoint point: CGPoint, size: CGFloat, scale: CGFloat) -> UInt8 {
        guard let pixel = pixelPoint(forSVGPoint: point, size: size, scale: scale) else {
            return 0
        }
        return bytes[(pixel.y * width + pixel.x) * 4 + 3]
    }

    func alphaSum(inSVGRect rect: CGRect, size: CGFloat, scale: CGFloat) -> Int {
        let pixelsPerSVGUnit = pixelsPerSVGUnit(size: size, scale: scale)
        let minX = max(0, Int((rect.minX * pixelsPerSVGUnit).rounded(.down)))
        let maxX = min(width, Int((rect.maxX * pixelsPerSVGUnit).rounded(.up)))
        let minY = max(0, Int((rect.minY * pixelsPerSVGUnit).rounded(.down)))
        let maxY = min(height, Int((rect.maxY * pixelsPerSVGUnit).rounded(.up)))

        guard minX < maxX, minY < maxY else { return 0 }

        var sum = 0
        for y in minY..<maxY {
            for x in minX..<maxX {
                sum += Int(bytes[(y * width + x) * 4 + 3])
            }
        }
        return sum
    }

    func containsColor(
        red: Double,
        green: Double,
        blue: Double,
        tolerance: Double,
        minimumAlpha: Double
    ) -> Bool {
        stride(from: 0, to: bytes.count - 3, by: 4).contains { index in
            let pixelRed = Double(bytes[index]) / 255.0
            let pixelGreen = Double(bytes[index + 1]) / 255.0
            let pixelBlue = Double(bytes[index + 2]) / 255.0
            let pixelAlpha = Double(bytes[index + 3]) / 255.0

            return pixelAlpha >= minimumAlpha
                && abs(pixelRed - red) <= tolerance
                && abs(pixelGreen - green) <= tolerance
                && abs(pixelBlue - blue) <= tolerance
        }
    }

    func averageOpaqueLuminance(minimumAlpha: UInt8 = 200) -> Double? {
        var luminanceSum = 0.0
        var pixelCount = 0

        for index in stride(from: 0, to: bytes.count - 3, by: 4) {
            guard bytes[index + 3] >= minimumAlpha else { continue }
            let red = Double(bytes[index]) / 255.0
            let green = Double(bytes[index + 1]) / 255.0
            let blue = Double(bytes[index + 2]) / 255.0
            luminanceSum += 0.2126 * red + 0.7152 * green + 0.0722 * blue
            pixelCount += 1
        }

        guard pixelCount > 0 else { return nil }
        return luminanceSum / Double(pixelCount)
    }

    private func pixelPoint(
        forSVGPoint point: CGPoint,
        size: CGFloat,
        scale: CGFloat
    ) -> (x: Int, y: Int)? {
        // PixelBuffer's normalized rows are top-down, so the renderer's
        // flipped SVG y-down coordinate maps directly to raster y.
        let pixelsPerSVGUnit = pixelsPerSVGUnit(size: size, scale: scale)
        let x = Int((point.x * pixelsPerSVGUnit).rounded(.down))
        let y = Int((point.y * pixelsPerSVGUnit).rounded(.down))

        guard x >= 0, x < width, y >= 0, y < height else { return nil }
        return (x, y)
    }

    private func pixelsPerSVGUnit(size: CGFloat, scale: CGFloat) -> CGFloat {
        size * scale / StatusIconGeometry.canvas.width
    }
}
