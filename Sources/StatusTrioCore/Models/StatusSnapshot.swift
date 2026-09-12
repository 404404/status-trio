import Foundation

struct BatteryStatus: Equatable, Sendable {
    let rawPercentage: Int?
    let isPresent: Bool
    let isCharging: Bool
    let isLowPowerMode: Bool
    let isConnectedToPower: Bool

    var percentage: Int {
        guard isPresent else { return 100 }
        let value = rawPercentage ?? 100
        return min(100, max(0, value))
    }

    static let placeholder = BatteryStatus(
        rawPercentage: 100,
        isPresent: true,
        isCharging: false,
        isLowPowerMode: false,
        isConnectedToPower: false
    )
}

enum WiFiState: Equatable, Sendable {
    case connected
    case notAssociated
    case off
    case noInternet
    case hotspot
    case temporary
    case shared
    case unavailable
}

struct WiFiStatus: Equatable, Sendable {
    let state: WiFiState
    let rssi: Int?

    static let placeholder = WiFiStatus(state: .unavailable, rssi: nil)
}

struct VolumeStatus: Equatable, Sendable {
    let scalar: Double?
    let isMuted: Bool
    let deviceName: String?

    static let placeholder = VolumeStatus(
        scalar: nil,
        isMuted: false,
        deviceName: nil
    )
}

struct StatusSnapshot: Equatable, Sendable {
    let battery: BatteryStatus
    let wifi: WiFiStatus
    let volume: VolumeStatus

    static let placeholder = StatusSnapshot(
        battery: .placeholder,
        wifi: .placeholder,
        volume: .placeholder
    )
}
