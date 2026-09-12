import Combine
import XCTest
@testable import StatusTrioCore

@MainActor
final class SystemStatusStoreTests: XCTestCase {
    func testStoreMergesIndependentMonitorUpdates() async {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let store = SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: wifi,
            volumeMonitor: volume,
            refreshInterval: .seconds(60)
        )

        let updatesApplied = expectation(description: "independent monitor updates applied")
        var cancellables = Set<AnyCancellable>()
        store.$snapshot
            .dropFirst()
            .sink { snapshot in
                guard snapshot.battery.percentage == 42,
                      snapshot.wifi.state == .connected,
                      snapshot.volume.scalar == 0.6 else { return }
                updatesApplied.fulfill()
            }
            .store(in: &cancellables)

        store.start()
        battery.send(makeBattery(percentage: 42))
        wifi.send(WiFiStatus(state: .connected, rssi: -60))
        volume.send(VolumeStatus(scalar: 0.6, isMuted: false, deviceName: "Speaker"))
        await fulfillment(of: [updatesApplied], timeout: 1)

        XCTAssertEqual(store.snapshot.battery.percentage, 42)
        XCTAssertEqual(store.snapshot.wifi.state, .connected)
        XCTAssertEqual(store.snapshot.volume.scalar, 0.6)
        cancellables.removeAll()
        store.stop()
    }

    func testEqualSnapshotsDoNotPublishTwice() async {
        let battery = FakeBatteryMonitor()
        let store = SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: FakeVolumeMonitor(),
            refreshInterval: .seconds(60)
        )

        let barrierPublished = expectation(description: "barrier snapshot published")
        var placeholderPublishCount = 0
        var cancellables = Set<AnyCancellable>()
        store.$snapshot
            .dropFirst()
            .sink { snapshot in
                if snapshot.battery == .placeholder {
                    placeholderPublishCount += 1
                }
                if snapshot.battery.percentage == 42 {
                    barrierPublished.fulfill()
                }
            }
            .store(in: &cancellables)

        store.start()
        battery.send(.placeholder)
        battery.send(.placeholder)
        battery.send(makeBattery(percentage: 42))
        await fulfillment(of: [barrierPublished], timeout: 1)

        XCTAssertEqual(placeholderPublishCount, 1)
        cancellables.removeAll()
        store.stop()
    }

    func testMakeStoreUsesInjectedMonitors() async {
        let battery = FakeBatteryMonitor()
        let store = AppEnvironment.makeStore(
            batteryMonitor: battery,
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: FakeVolumeMonitor()
        )

        let updateApplied = expectation(description: "injected monitor update applied")
        var cancellables = Set<AnyCancellable>()
        store.$snapshot
            .dropFirst()
            .sink { snapshot in
                guard snapshot.battery.percentage == 55 else { return }
                updateApplied.fulfill()
            }
            .store(in: &cancellables)

        store.start()
        battery.send(makeBattery(percentage: 55))
        await fulfillment(of: [updateApplied], timeout: 1)

        XCTAssertEqual(store.snapshot.battery.percentage, 55)
        cancellables.removeAll()
        store.stop()
    }

    func testStartTwiceStartsEachMonitorExactlyOnce() {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let store = makeStore(battery: battery, wifi: wifi, volume: volume)

        store.start()
        store.start()

        XCTAssertEqual(battery.startCount, 1)
        XCTAssertEqual(wifi.startCount, 1)
        XCTAssertEqual(volume.startCount, 1)
        store.stop()
    }

    func testStopTwiceStopsEachMonitorExactlyOnce() {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let store = makeStore(battery: battery, wifi: wifi, volume: volume)

        store.start()
        store.stop()
        store.stop()

        XCTAssertEqual(battery.stopCount, 1)
        XCTAssertEqual(wifi.stopCount, 1)
        XCTAssertEqual(volume.stopCount, 1)
    }

    func testStartAfterStopDoesNotStartMonitorsAgain() {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let store = makeStore(battery: battery, wifi: wifi, volume: volume)

        store.start()
        store.stop()
        store.start()

        XCTAssertEqual(battery.startCount, 1)
        XCTAssertEqual(wifi.startCount, 1)
        XCTAssertEqual(volume.startCount, 1)
        XCTAssertEqual(battery.stopCount, 1)
        XCTAssertEqual(wifi.stopCount, 1)
        XCTAssertEqual(volume.stopCount, 1)
    }

    func testPeriodicRefreshUsesInjectedSleep() async {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let sleeper = ManualSleeper()
        let store = SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: wifi,
            volumeMonitor: volume,
            refreshInterval: .seconds(60),
            sleep: { _ in await sleeper.sleep() }
        )

        store.start()
        await sleeper.waitForCallCount(1)
        sleeper.releaseNext()
        await sleeper.waitForCallCount(2)

        XCTAssertEqual(battery.refreshCount, 1)
        XCTAssertEqual(wifi.refreshCount, 1)
        XCTAssertEqual(volume.refreshCount, 1)

        store.stop()
        sleeper.releaseAll()
        await sleeper.waitForCompletionCount(2)
    }

    func testStopPreventsFurtherPeriodicRefresh() async {
        let battery = FakeBatteryMonitor()
        let wifi = FakeWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let sleeper = ManualSleeper()
        let store = SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: wifi,
            volumeMonitor: volume,
            refreshInterval: .seconds(60),
            sleep: { _ in await sleeper.sleep() }
        )

        store.start()
        await sleeper.waitForCallCount(1)
        sleeper.releaseNext()
        await sleeper.waitForCallCount(2)

        store.stop()
        sleeper.releaseAll()
        await sleeper.waitForCompletionCount(2)
        store.refreshAll()

        XCTAssertEqual(battery.refreshCount, 1)
        XCTAssertEqual(wifi.refreshCount, 1)
        XCTAssertEqual(volume.refreshCount, 1)
    }

    private func makeStore(
        battery: FakeBatteryMonitor,
        wifi: FakeWiFiMonitor,
        volume: FakeVolumeMonitor
    ) -> SystemStatusStore {
        SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: wifi,
            volumeMonitor: volume,
            refreshInterval: .seconds(60)
        )
    }

    private func makeBattery(percentage: Int) -> BatteryStatus {
        BatteryStatus(
            rawPercentage: percentage,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: false
        )
    }
}

@MainActor
private final class ManualSleeper {
    private(set) var callCount = 0
    private(set) var completionCount = 0

    private var sleepContinuations: [CheckedContinuation<Void, Never>] = []
    private var callWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var completionWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func sleep() async {
        callCount += 1
        resumeCallWaiters()

        await withCheckedContinuation { continuation in
            sleepContinuations.append(continuation)
        }

        completionCount += 1
        resumeCompletionWaiters()
    }

    func waitForCallCount(_ count: Int) async {
        guard callCount < count else { return }
        await withCheckedContinuation { continuation in
            callWaiters.append((count, continuation))
        }
    }

    func waitForCompletionCount(_ count: Int) async {
        guard completionCount < count else { return }
        await withCheckedContinuation { continuation in
            completionWaiters.append((count, continuation))
        }
    }

    func releaseNext() {
        guard !sleepContinuations.isEmpty else { return }
        sleepContinuations.removeFirst().resume()
    }

    func releaseAll() {
        let continuations = sleepContinuations
        sleepContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }

    private func resumeCallWaiters() {
        var remaining: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
        for waiter in callWaiters {
            if callCount >= waiter.count {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        callWaiters = remaining
    }

    private func resumeCompletionWaiters() {
        var remaining: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
        for waiter in completionWaiters {
            if completionCount >= waiter.count {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        completionWaiters = remaining
    }
}

@MainActor
private final class FakeBatteryMonitor: BatteryMonitoring {
    let updates: AsyncStream<BatteryStatus>
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var refreshCount = 0
    private let continuation: AsyncStream<BatteryStatus>.Continuation

    init() {
        (updates, continuation) = AsyncStream.makeStream()
    }

    func start() { startCount += 1 }
    func stop() {
        stopCount += 1
        continuation.finish()
    }
    func refresh() { refreshCount += 1 }
    func send(_ value: BatteryStatus) { continuation.yield(value) }
}

@MainActor
private final class FakeWiFiMonitor: WiFiMonitoring {
    let updates: AsyncStream<WiFiStatus>
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var refreshCount = 0
    private let continuation: AsyncStream<WiFiStatus>.Continuation

    init() { (updates, continuation) = AsyncStream.makeStream() }
    func start() { startCount += 1 }
    func stop() {
        stopCount += 1
        continuation.finish()
    }
    func refresh() { refreshCount += 1 }
    func send(_ value: WiFiStatus) { continuation.yield(value) }
}

@MainActor
private final class FakeVolumeMonitor: VolumeMonitoring {
    let updates: AsyncStream<VolumeStatus>
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var refreshCount = 0
    private let continuation: AsyncStream<VolumeStatus>.Continuation

    init() { (updates, continuation) = AsyncStream.makeStream() }
    func start() { startCount += 1 }
    func stop() {
        stopCount += 1
        continuation.finish()
    }
    func refresh() { refreshCount += 1 }
    func send(_ value: VolumeStatus) { continuation.yield(value) }
}
