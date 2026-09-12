import Combine
import Foundation

@MainActor
final class SystemStatusStore: ObservableObject {
    @Published private(set) var snapshot: StatusSnapshot

    private let batteryMonitor: any BatteryMonitoring
    private let wifiMonitor: any WiFiMonitoring
    private let volumeMonitor: any VolumeMonitoring
    private let refreshInterval: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private var monitorTasks: [Task<Void, Never>] = []
    private var refreshTask: Task<Void, Never>?
    private var lastPublishedSnapshot: StatusSnapshot?
    private var hasStarted = false
    private var hasStopped = false

    init(
        batteryMonitor: any BatteryMonitoring,
        wifiMonitor: any WiFiMonitoring,
        volumeMonitor: any VolumeMonitoring,
        refreshInterval: Duration = .seconds(5),
        sleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        initialSnapshot: StatusSnapshot = .placeholder
    ) {
        self.batteryMonitor = batteryMonitor
        self.wifiMonitor = wifiMonitor
        self.volumeMonitor = volumeMonitor
        self.refreshInterval = refreshInterval
        self.sleep = sleep
        self.snapshot = initialSnapshot
    }

    func start() {
        guard !hasStarted, !hasStopped else { return }
        hasStarted = true

        batteryMonitor.start()
        wifiMonitor.start()
        volumeMonitor.start()

        monitorTasks = [
            Task { [weak self] in
                guard let self else { return }
                for await value in batteryMonitor.updates {
                    self.applyBattery(value)
                }
            },
            Task { [weak self] in
                guard let self else { return }
                for await value in wifiMonitor.updates {
                    self.applyWiFi(value)
                }
            },
            Task { [weak self] in
                guard let self else { return }
                for await value in volumeMonitor.updates {
                    self.applyVolume(value)
                }
            }
        ]

        refreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await sleep(refreshInterval)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self.refreshAll()
            }
        }
    }

    func stop() {
        guard !hasStopped else { return }
        hasStopped = true

        batteryMonitor.stop()
        wifiMonitor.stop()
        volumeMonitor.stop()
        monitorTasks.forEach { $0.cancel() }
        monitorTasks.removeAll()
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refreshAll() {
        guard !hasStopped else { return }
        batteryMonitor.refresh()
        wifiMonitor.refresh()
        volumeMonitor.refresh()
    }

    private func applyBattery(_ value: BatteryStatus) {
        publish(snapshot.replacingBattery(value))
    }

    private func applyWiFi(_ value: WiFiStatus) {
        publish(snapshot.replacingWiFi(value))
    }

    private func applyVolume(_ value: VolumeStatus) {
        publish(snapshot.replacingVolume(value))
    }

    private func publish(_ next: StatusSnapshot) {
        guard next != lastPublishedSnapshot else { return }
        lastPublishedSnapshot = next
        snapshot = next
    }
}

private extension StatusSnapshot {
    func replacingBattery(_ value: BatteryStatus) -> StatusSnapshot {
        StatusSnapshot(battery: value, wifi: wifi, volume: volume)
    }

    func replacingWiFi(_ value: WiFiStatus) -> StatusSnapshot {
        StatusSnapshot(battery: battery, wifi: value, volume: volume)
    }

    func replacingVolume(_ value: VolumeStatus) -> StatusSnapshot {
        StatusSnapshot(battery: battery, wifi: wifi, volume: value)
    }
}
