import Foundation

enum BatteryColorRole: Equatable, Sendable {
    case foreground
    case charging
    case lowPower
}

enum StatusMappings {
    static func wifiBars(rssi: Int?) -> Int {
        guard let rssi else { return 0 }
        switch rssi {
        // Parentheses are required for this negative partial range in Swift 6.
        case (-55)...:
            return 3
        case -70 ... -56:
            return 2
        case -85 ... -71:
            return 1
        default:
            return 0
        }
    }

    static func volumeSteps(scalar: Double?, isMuted: Bool) -> Int? {
        guard let scalar else { return nil }
        let clamped = min(1, max(0, scalar))
        if isMuted || clamped == 0 { return 0 }
        if clamped <= 0.25 { return 1 }
        if clamped <= 0.50 { return 2 }
        if clamped <= 0.75 { return 3 }
        return 4
    }

    static func batteryColorRole(_ battery: BatteryStatus) -> BatteryColorRole {
        if battery.isCharging { return .charging }
        if battery.isLowPowerMode { return .lowPower }
        return .foreground
    }

    static func batteryProgress(_ battery: BatteryStatus) -> Double {
        Double(battery.percentage) / 100.0
    }
}
