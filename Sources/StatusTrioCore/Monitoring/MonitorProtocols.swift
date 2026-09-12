import Foundation

@MainActor
protocol BatteryMonitoring: AnyObject {
    var updates: AsyncStream<BatteryStatus> { get }
    func start()
    func stop()
    func refresh()
}

@MainActor
protocol WiFiMonitoring: AnyObject {
    var updates: AsyncStream<WiFiStatus> { get }
    func start()
    func stop()
    func refresh()
}

@MainActor
protocol VolumeMonitoring: AnyObject {
    var updates: AsyncStream<VolumeStatus> { get }
    func start()
    func stop()
    func refresh()
}

@MainActor
final class UnavailableBatteryMonitor: BatteryMonitoring {
    let updates: AsyncStream<BatteryStatus>
    private let continuation: AsyncStream<BatteryStatus>.Continuation

    init() {
        (updates, continuation) = AsyncStream.makeStream()
    }

    func start() {}
    func stop() { continuation.finish() }
    func refresh() {
        continuation.yield(.placeholder)
    }
}

@MainActor
final class UnavailableWiFiMonitor: WiFiMonitoring {
    let updates: AsyncStream<WiFiStatus>
    private let continuation: AsyncStream<WiFiStatus>.Continuation

    init() {
        (updates, continuation) = AsyncStream.makeStream()
    }

    func start() {}
    func stop() { continuation.finish() }
    func refresh() {
        continuation.yield(.placeholder)
    }
}

@MainActor
final class UnavailableVolumeMonitor: VolumeMonitoring {
    let updates: AsyncStream<VolumeStatus>
    private let continuation: AsyncStream<VolumeStatus>.Continuation

    init() {
        (updates, continuation) = AsyncStream.makeStream()
    }

    func start() {}
    func stop() { continuation.finish() }
    func refresh() {
        continuation.yield(.placeholder)
    }
}
