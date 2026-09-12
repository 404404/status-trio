import Foundation
import XCTest
@testable import StatusTrioCore

@MainActor
final class BatteryMonitorTests: XCTestCase {
    func testParserConvertsValidInternalBatteryDescription() {
        let description: [String: Any] = [
            kIOPSTypeKey: kIOPSInternalBatteryType,
            kIOPSCurrentCapacityKey: 73,
            kIOPSMaxCapacityKey: 100,
            kIOPSIsChargingKey: true,
            kIOPSPowerSourceStateKey: kIOPSACPowerValue,
            kIOPSIsPresentKey: true
        ]

        XCTAssertEqual(
            IOPSBatteryReader.parse(description),
            BatteryReading(
                currentCapacity: 73,
                maxCapacity: 100,
                isCharging: true,
                isConnectedToPower: true,
                isPresent: true
            )
        )
    }

    func testParserRejectsInvalidInternalBatteryDescription() {
        let description: [String: Any] = [
            kIOPSTypeKey: kIOPSInternalBatteryType,
            kIOPSCurrentCapacityKey: "73",
            kIOPSMaxCapacityKey: 100
        ]

        XCTAssertNil(IOPSBatteryReader.parse(description))
    }

    func testParserRejectsNonBatteryDescription() {
        let description: [String: Any] = [
            kIOPSTypeKey: "UPS",
            kIOPSCurrentCapacityKey: 73,
            kIOPSMaxCapacityKey: 100
        ]

        XCTAssertNil(IOPSBatteryReader.parse(description))
    }

    func testMonitorConvertsReaderOutput() async {
        let reader = FakeBatteryReader(result: BatteryReading(
            currentCapacity: 2,
            maxCapacity: 3,
            isCharging: true,
            isConnectedToPower: true,
            isPresent: true
        ))
        let monitor = BatteryMonitor(
            reader: reader,
            lowPowerModeProvider: { true }
        )

        monitor.refresh()
        var iterator = monitor.updates.makeAsyncIterator()
        let value = await iterator.next()

        XCTAssertEqual(value?.percentage, 67)
        XCTAssertTrue(value?.isCharging == true)
        XCTAssertTrue(value?.isConnectedToPower == true)
        XCTAssertTrue(value?.isLowPowerMode == true)
        monitor.stop()
    }

    func testMissingReaderResultUsesFullValue() async {
        let monitor = BatteryMonitor(
            reader: FakeBatteryReader(result: nil),
            lowPowerModeProvider: { false }
        )

        monitor.refresh()
        var iterator = monitor.updates.makeAsyncIterator()
        let value = await iterator.next()

        XCTAssertTrue(value?.isPresent == false)
        XCTAssertEqual(value?.percentage, 100)
        XCTAssertFalse(value?.isCharging == true)
        XCTAssertFalse(value?.isConnectedToPower == true)
        monitor.stop()
    }

    func testNonPresentReadingUsesFullValue() async {
        let monitor = BatteryMonitor(
            reader: FakeBatteryReader(result: BatteryReading(
                currentCapacity: 42,
                maxCapacity: 100,
                isCharging: true,
                isConnectedToPower: true,
                isPresent: false
            )),
            lowPowerModeProvider: { false }
        )

        monitor.refresh()
        var iterator = monitor.updates.makeAsyncIterator()
        let value = await iterator.next()

        XCTAssertTrue(value?.isPresent == false)
        XCTAssertEqual(value?.percentage, 100)
        XCTAssertFalse(value?.isCharging == true)
        XCTAssertFalse(value?.isConnectedToPower == true)
        monitor.stop()
    }

    func testZeroMaxCapacityFallsBackToCurrentCapacity() async {
        let monitor = BatteryMonitor(
            reader: FakeBatteryReader(result: BatteryReading(
                currentCapacity: 73,
                maxCapacity: 0,
                isCharging: false,
                isConnectedToPower: false,
                isPresent: true
            )),
            lowPowerModeProvider: { false }
        )

        monitor.refresh()
        var iterator = monitor.updates.makeAsyncIterator()
        let value = await iterator.next()

        XCTAssertEqual(value?.percentage, 73)
        monitor.stop()
    }

    func testStartImmediatelyEmitsCurrentReading() async {
        let monitor = BatteryMonitor(
            reader: FakeBatteryReader(result: BatteryReading(
                currentCapacity: 81,
                maxCapacity: 100,
                isCharging: false,
                isConnectedToPower: false,
                isPresent: true
            )),
            lowPowerModeProvider: { false },
            iopsRunLoopSourceFactory: { _, _ in nil }
        )

        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        let value = await iterator.next()

        XCTAssertEqual(value?.percentage, 81)
        monitor.stop()
    }

    func testNilIOPSNotificationSourceStillRefreshesAndStops() async {
        let reader = FakeBatteryReader(result: makeReading(percentage: 64))
        let monitor = BatteryMonitor(
            reader: reader,
            lowPowerModeProvider: { false },
            iopsRunLoopSourceFactory: { _, _ in nil }
        )

        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        let value = await iterator.next()

        XCTAssertEqual(value?.percentage, 64)
        XCTAssertEqual(reader.readCount, 1)

        monitor.stop()
        let stoppedValue = await iterator.next()

        XCTAssertNil(stoppedValue)
        XCTAssertEqual(reader.readCount, 1)
    }

    func testStartAndStopAreIdempotent() {
        let reader = FakeBatteryReader(result: makeReading(percentage: 50))
        let harness = IOPSNotificationSourceHarness()
        defer { harness.releaseRetainedContext() }
        let monitor = BatteryMonitor(
            reader: reader,
            lowPowerModeProvider: { false },
            iopsRunLoopSourceFactory: harness.factory
        )

        monitor.start()
        monitor.start()

        XCTAssertEqual(harness.factoryInvocationCount, 1)
        XCTAssertEqual(reader.readCount, 1)
        XCTAssertTrue(CFRunLoopContainsSource(CFRunLoopGetMain(), harness.source, .defaultMode))

        monitor.stop()
        monitor.stop()

        XCTAssertFalse(CFRunLoopContainsSource(CFRunLoopGetMain(), harness.source, .defaultMode))
        XCTAssertEqual(reader.readCount, 1)
    }

    func testIOPSNotificationCallbackRefreshesUntilStopped() async {
        let reader = FakeBatteryReader(result: makeReading(percentage: 50))
        let harness = IOPSNotificationSourceHarness()
        defer { harness.releaseRetainedContext() }
        let monitor = BatteryMonitor(
            reader: reader,
            lowPowerModeProvider: { false },
            iopsRunLoopSourceFactory: harness.factory
        )

        var iterator = monitor.updates.makeAsyncIterator()
        monitor.start()

        XCTAssertNotNil(harness.contextPointer)
        XCTAssertNotNil(harness.callback)
        XCTAssertTrue(CFRunLoopContainsSource(CFRunLoopGetMain(), harness.source, .defaultMode))
        let immediateValue = await iterator.next()
        XCTAssertEqual(immediateValue?.percentage, 50)
        XCTAssertEqual(reader.readCount, 1)

        reader.result = makeReading(percentage: 60)
        harness.invokeCallback()
        let callbackValue = await iterator.next()
        XCTAssertEqual(callbackValue?.percentage, 60)
        XCTAssertEqual(reader.readCount, 2)

        monitor.stop()

        XCTAssertFalse(CFRunLoopContainsSource(CFRunLoopGetMain(), harness.source, .defaultMode))
        let stoppedValue = await iterator.next()
        XCTAssertNil(stoppedValue)

        reader.result = makeReading(percentage: 70)
        harness.invokeCallback()
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(reader.readCount, 2)
        let postStopValue = await iterator.next()
        XCTAssertNil(postStopValue)
    }

    func testPowerStateNotificationRefreshesUntilStopped() async {
        let reader = FakeBatteryReader(result: makeReading(percentage: 50))
        let monitor = BatteryMonitor(
            reader: reader,
            lowPowerModeProvider: { false },
            iopsRunLoopSourceFactory: { _, _ in nil }
        )

        monitor.start()
        XCTAssertEqual(reader.readCount, 1)

        NotificationCenter.default.post(
            name: .NSProcessInfoPowerStateDidChange,
            object: nil
        )
        await waitForReadCount(2, reader: reader)

        monitor.stop()
        NotificationCenter.default.post(
            name: .NSProcessInfoPowerStateDidChange,
            object: nil
        )
        try? await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(reader.readCount, 2)
    }

    func testRefreshAfterStopDoesNotReadOrEmitAnotherUpdate() async {
        let reader = FakeBatteryReader(result: makeReading(percentage: 50))
        let monitor = BatteryMonitor(
            reader: reader,
            lowPowerModeProvider: { false },
            iopsRunLoopSourceFactory: { _, _ in nil }
        )

        monitor.start()
        var iterator = monitor.updates.makeAsyncIterator()
        _ = await iterator.next()

        monitor.stop()
        monitor.refresh()

        let stoppedValue = await iterator.next()
        XCTAssertNil(stoppedValue)
        XCTAssertEqual(reader.readCount, 1)
    }

    func testStartAfterStopDoesNotRestart() {
        let reader = FakeBatteryReader(result: makeReading(percentage: 50))
        let harness = IOPSNotificationSourceHarness()
        defer { harness.releaseRetainedContext() }
        let monitor = BatteryMonitor(
            reader: reader,
            lowPowerModeProvider: { false },
            iopsRunLoopSourceFactory: harness.factory
        )

        monitor.stop()
        monitor.start()

        XCTAssertEqual(harness.factoryInvocationCount, 0)
        XCTAssertEqual(reader.readCount, 0)
        XCTAssertFalse(CFRunLoopContainsSource(CFRunLoopGetMain(), harness.source, .defaultMode))
    }

    func testDeinitRemovesSourceWhenStopWasNotCalled() {
        let harness = IOPSNotificationSourceHarness()
        defer { harness.releaseRetainedContext() }
        weak var weakMonitor: BatteryMonitor?

        do {
            let monitor = BatteryMonitor(
                reader: FakeBatteryReader(result: makeReading(percentage: 50)),
                lowPowerModeProvider: { false },
                iopsRunLoopSourceFactory: harness.factory
            )
            weakMonitor = monitor

            monitor.start()
            XCTAssertTrue(CFRunLoopContainsSource(CFRunLoopGetMain(), harness.source, .defaultMode))
        }

        XCTAssertNil(weakMonitor)
        XCTAssertFalse(CFRunLoopContainsSource(CFRunLoopGetMain(), harness.source, .defaultMode))
    }

    private func makeReading(percentage: Int) -> BatteryReading {
        BatteryReading(
            currentCapacity: percentage,
            maxCapacity: 100,
            isCharging: false,
            isConnectedToPower: false,
            isPresent: true
        )
    }

    private func waitForReadCount(
        _ expectedCount: Int,
        reader: FakeBatteryReader
    ) async {
        for _ in 0..<100 {
            if reader.readCount >= expectedCount {
                return
            }
            try? await Task.sleep(for: .milliseconds(1))
        }

        XCTFail("Timed out waiting for read count \(expectedCount)")
    }
}

private final class FakeBatteryReader: BatteryReadingProviding {
    var result: BatteryReading?
    private(set) var readCount = 0

    init(result: BatteryReading?) {
        self.result = result
    }

    func read() -> BatteryReading? {
        readCount += 1
        return result
    }
}

private final class IOPSNotificationSourceHarness {
    let source: CFRunLoopSource
    private(set) var callback: IOPSNotificationCallback?
    private(set) var contextPointer: UnsafeMutableRawPointer?
    private(set) var factoryInvocationCount = 0
    private var retainedContext: Unmanaged<AnyObject>?

    init() {
        var sourceContext = CFRunLoopSourceContext(
            version: 0,
            info: nil,
            retain: nil,
            release: nil,
            copyDescription: nil,
            equal: nil,
            hash: nil,
            schedule: nil,
            cancel: nil,
            perform: nil
        )
        source = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &sourceContext)!
    }

    var factory: IOPSRunLoopSourceFactory {
        { [self] contextPointer, callback in
            factoryInvocationCount += 1
            self.contextPointer = contextPointer
            self.callback = callback
            if let contextPointer {
                retainedContext = Unmanaged<AnyObject>
                    .fromOpaque(contextPointer)
                    .retain()
            }
            return source
        }
    }

    func invokeCallback() {
        callback?(contextPointer)
    }

    func releaseRetainedContext() {
        retainedContext?.release()
        retainedContext = nil
    }
}
