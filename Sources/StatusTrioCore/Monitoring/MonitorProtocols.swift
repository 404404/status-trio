import Foundation

@MainActor
protocol BatteryMonitoring: AnyObject {
    var updates: AsyncStream<BatteryStatus> { get }
    func start()
    func stop()
    func refresh()
    func recover()
}

@MainActor
protocol WiFiMonitoring: AnyObject {
    var updates: AsyncStream<WiFiStatus> { get }
    func start()
    func stop()
    func refresh()
    func recover()
}

@MainActor
protocol VolumeMonitoring: AnyObject {
    var updates: AsyncStream<VolumeStatus> { get }
    func start()
    func stop()
    func refresh()
    func recover()
}
