import AppKit
import CoreGraphics

enum StatusIconRenderer {
    static func image(
        snapshot: StatusSnapshot,
        size: CGFloat,
        appearance: NSAppearance
    ) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))

        appearance.performAsCurrentDrawingAppearance {
            let foreground = NSColor.labelColor.usingColorSpace(.deviceRGB)?.cgColor
                ?? CGColor(gray: 1, alpha: 1)
            image.lockFocus()
            defer { image.unlockFocus() }

            guard let context = NSGraphicsContext.current?.cgContext else { return }
            draw(snapshot: snapshot, in: context, size: size, foreground: foreground)
        }

        return image
    }

    static func render(
        snapshot: StatusSnapshot,
        size: CGFloat,
        scale: CGFloat,
        foreground: CGColor
    ) -> CGImage? {
        guard size.isFinite, scale.isFinite, size > 0, scale > 0 else { return nil }

        let pixelLength = (size * scale).rounded(.up)
        guard pixelLength.isFinite,
              let pixelDimension = Int(exactly: pixelLength),
              pixelDimension > 0,
              pixelDimension <= Int.max / 4
        else {
            return nil
        }

        guard let context = CGContext(
            data: nil,
            width: pixelDimension,
            height: pixelDimension,
            bitsPerComponent: 8,
            bytesPerRow: pixelDimension * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.scaleBy(x: scale, y: scale)
        draw(snapshot: snapshot, in: context, size: size, foreground: foreground)
        return context.makeImage()
    }

    private static func draw(
        snapshot: StatusSnapshot,
        in context: CGContext,
        size: CGFloat,
        foreground: CGColor
    ) {
        context.saveGState()
        defer { context.restoreGState() }

        let scale = size / StatusIconGeometry.canvas.width
        context.translateBy(x: 0, y: size)
        context.scaleBy(x: scale, y: -scale)

        context.setLineCap(.round)
        context.setLineJoin(.round)

        drawBattery(snapshot.battery, in: context, foreground: foreground)
        drawWiFi(snapshot.wifi, in: context, foreground: foreground)
        drawVolume(snapshot.volume, in: context, foreground: foreground)
    }

    private static func drawBattery(
        _ battery: BatteryStatus,
        in context: CGContext,
        foreground: CGColor
    ) {
        context.setLineWidth(8)
        context.setStrokeColor(foreground.copy(alpha: 0.22) ?? foreground)
        context.addPath(StatusIconGeometry.batteryTrack())
        context.strokePath()

        let fillColor: CGColor
        switch StatusMappings.batteryColorRole(battery) {
        case .foreground:
            fillColor = foreground
        case .charging:
            fillColor = CGColor(red: 52.0 / 255.0, green: 199.0 / 255.0, blue: 89.0 / 255.0, alpha: 1)
        case .lowPower:
            fillColor = CGColor(red: 242.0 / 255.0, green: 185.0 / 255.0, blue: 0, alpha: 1)
        }

        context.setStrokeColor(fillColor)
        context.addPath(StatusIconGeometry.batteryFill(progress: StatusMappings.batteryProgress(battery)))
        context.strokePath()
    }

    private static func drawWiFi(
        _ wifi: WiFiStatus,
        in context: CGContext,
        foreground: CGColor
    ) {
        let mutedColor = foreground.copy(alpha: 0.30) ?? foreground
        let bars = StatusMappings.wifiBars(rssi: wifi.rssi)

        context.setLineWidth(7)

        switch wifi.state {
        case .connected:
            if bars == 0 {
                drawWiFiSignal(level: 3, color: mutedColor, in: context)
            } else {
                drawWiFiSignal(level: bars, color: foreground, in: context)
            }
        case .notAssociated, .off, .unavailable:
            drawWiFiSignal(level: 3, color: mutedColor, in: context)

            if wifi.state == .off || wifi.state == .unavailable {
                context.setStrokeColor(mutedColor)
                context.setLineWidth(6)
                context.addPath(StatusIconGeometry.wifiOffSlash())
                context.strokePath()
            }
        case .noInternet:
            drawWiFiSignal(level: 3, color: mutedColor, includeDot: false, in: context)

            let overlay = StatusIconGeometry.noInternetOverlay()
            context.setStrokeColor(mutedColor)
            context.setLineWidth(5)
            context.addPath(overlay.stem)
            context.strokePath()

            context.setFillColor(mutedColor)
            context.addPath(overlay.dot)
            context.fillPath()
        case .hotspot:
            context.setStrokeColor(foreground)
            context.setLineWidth(5)
            for path in StatusIconGeometry.hotspotOverlay() {
                context.addPath(path)
                context.strokePath()
            }
        case .temporary:
            context.setFillColor(foreground)
            context.setStrokeColor(foreground)
            context.setLineWidth(7)
            context.addPath(StatusIconGeometry.temporaryWedge())
            context.drawPath(using: .fillStroke)

            context.saveGState()
            context.setBlendMode(.clear)
            context.setLineWidth(2.5)
            context.addPath(StatusIconGeometry.temporaryScreenOutline())
            context.strokePath()
            context.addPath(StatusIconGeometry.temporaryScreenStand())
            context.fillPath()
            context.restoreGState()
        case .shared:
            context.setFillColor(foreground)
            context.setStrokeColor(foreground)
            context.setLineWidth(7)
            context.addPath(StatusIconGeometry.sharedWedge())
            context.drawPath(using: .fillStroke)

            context.saveGState()
            context.setBlendMode(.clear)
            context.addPath(StatusIconGeometry.sharedArrowCutout())
            context.fillPath()
            context.restoreGState()
        }
    }

    private static func drawWiFiSignal(
        level: Int,
        color: CGColor,
        includeDot: Bool = true,
        in context: CGContext
    ) {
        context.setStrokeColor(color)
        for path in StatusIconGeometry.wifiArcs(level: level) {
            context.addPath(path)
            context.strokePath()
        }

        guard includeDot else { return }
        context.setFillColor(color)
        context.addPath(StatusIconGeometry.wifiDot())
        context.fillPath()
    }

    private static func drawVolume(
        _ volume: VolumeStatus,
        in context: CGContext,
        foreground: CGColor
    ) {
        let level = StatusMappings.volumeSteps(scalar: volume.scalar, isMuted: volume.isMuted) ?? 0
        let hiddenColor = foreground.copy(alpha: 0.22) ?? foreground

        for (index, point) in StatusIconGeometry.volumeDots().enumerated() {
            context.setFillColor(index < level ? foreground : hiddenColor)
            let radius = StatusIconGeometry.volumeDotRadius
            context.fillEllipse(
                in: CGRect(
                    x: point.x - radius,
                    y: point.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            )
        }
    }
}
