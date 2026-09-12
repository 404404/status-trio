import CoreGraphics
import Foundation

enum StatusIconGeometry {
    static let canvas = CGRect(x: 0, y: 0, width: 120, height: 120)

    // Derived from the SVG battery endpoints and radius.
    private static let batteryRadius: CGFloat = 51.5
    private static let batteryCenter = CGPoint(x: 59.5, y: 61.48715261785473)
    private static let batteryStart: CGFloat = 148.69008689281117 * .pi / 180
    private static let batterySweep: CGFloat = 242.6198262143777 * .pi / 180

    private static let wifiOuterCenter = CGPoint(x: 59.5, y: 78.3)
    private static let wifiOuterRadius: CGFloat = 31
    private static let wifiOuterStart: CGFloat = 227.35 * .pi / 180
    private static let wifiOuterEnd: CGFloat = 312.65 * .pi / 180

    static func batteryTrack() -> CGPath {
        batteryArc(progress: 1)
    }

    static func batteryFill(progress: Double) -> CGPath {
        let clamped = min(1, max(0, progress))
        guard clamped > 0 else { return CGMutablePath() }
        return batteryArc(progress: clamped)
    }

    static func wifiArcs(level: Int) -> [CGPath] {
        let bars = min(3, max(0, level))
        let middle = arc(
            center: CGPoint(x: 59.5, y: 78.89),
            radius: 18.5,
            start: 227.5 * .pi / 180,
            end: 312.5 * .pi / 180
        )

        switch bars {
        case 3:
            return [wifiOuterArc(), middle]
        case 2:
            return [middle]
        case 1:
            // Level 1 intentionally returns no arcs because the dot is drawn separately.
            return []
        default:
            return []
        }
    }

    static func wifiOuterArc() -> CGPath {
        arc(
            center: wifiOuterCenter,
            radius: wifiOuterRadius,
            start: wifiOuterStart,
            end: wifiOuterEnd
        )
    }

    static func wifiDot() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 59.5, y: 69.9))
        path.addCurve(to: CGPoint(x: 66.5, y: 73), control1: CGPoint(x: 61.0, y: 69.9), control2: CGPoint(x: 65.2, y: 70.8))
        path.addCurve(to: CGPoint(x: 66.5, y: 75), control1: CGPoint(x: 66.7, y: 73.8), control2: CGPoint(x: 66.7, y: 74.3))
        path.addCurve(to: CGPoint(x: 59.5, y: 80.95), control1: CGPoint(x: 63.8, y: 78.8), control2: CGPoint(x: 61.15, y: 80.95))
        path.addCurve(to: CGPoint(x: 52.5, y: 75), control1: CGPoint(x: 57.85, y: 80.95), control2: CGPoint(x: 55.2, y: 78.8))
        path.addCurve(to: CGPoint(x: 52.5, y: 73), control1: CGPoint(x: 52.3, y: 74.3), control2: CGPoint(x: 52.3, y: 73.8))
        path.addCurve(to: CGPoint(x: 59.5, y: 69.9), control1: CGPoint(x: 53.8, y: 70.8), control2: CGPoint(x: 58.0, y: 69.9))
        path.closeSubpath()
        return path
    }

    static func wifiOffSlash() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 39, y: 46))
        path.addLine(to: CGPoint(x: 81, y: 79))
        return path
    }

    static func noInternetOverlay() -> (stem: CGPath, dot: CGPath) {
        let stem = CGMutablePath()
        stem.move(to: CGPoint(x: 59.5, y: 54.5))
        stem.addLine(to: CGPoint(x: 59.5, y: 67))

        let dot = CGMutablePath()
        dot.addEllipse(in: CGRect(x: 56.9, y: 72.9, width: 5.2, height: 5.2))
        return (stem, dot)
    }

    static func hotspotOverlay() -> [CGPath] {
        let left = CGMutablePath()
        left.move(to: CGPoint(x: 53, y: 66))
        left.addLine(to: CGPoint(x: 49, y: 66))
        left.addArc(center: CGPoint(x: 49, y: 58), radius: 8, startAngle: .pi / 2, endAngle: 3 * .pi / 2, clockwise: false)
        left.addLine(to: CGPoint(x: 54, y: 50))

        let right = CGMutablePath()
        right.move(to: CGPoint(x: 66, y: 50))
        right.addLine(to: CGPoint(x: 70, y: 50))
        right.addArc(center: CGPoint(x: 70, y: 58), radius: 8, startAngle: 3 * .pi / 2, endAngle: 5 * .pi / 2, clockwise: false)
        right.addLine(to: CGPoint(x: 65, y: 66))

        let bridge = CGMutablePath()
        bridge.move(to: CGPoint(x: 51, y: 58))
        bridge.addLine(to: CGPoint(x: 68, y: 58))
        return [left, right, bridge]
    }

    static func volumeDots() -> [CGPoint] {
        [
            CGPoint(x: 33, y: 104.2),
            CGPoint(x: 50.5, y: 111.2),
            CGPoint(x: 68.5, y: 111.7),
            CGPoint(x: 86, y: 105.8)
        ]
    }

    static let volumeDotRadius: CGFloat = 5.5

    private static func batteryArc(progress: Double) -> CGPath {
        let end = batteryStart + batterySweep * CGFloat(progress)
        return arc(center: batteryCenter, radius: batteryRadius, start: batteryStart, end: end)
    }

    private static func arc(
        center: CGPoint,
        radius: CGFloat,
        start: CGFloat,
        end: CGFloat
    ) -> CGPath {
        let path = CGMutablePath()
        path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        return path
    }
}
