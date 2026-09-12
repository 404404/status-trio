# Status Trio Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS menu bar app that renders battery, Wi-Fi, and volume in one 20 pt three-in-one icon, with a left-click popover and right-click menu.

**Architecture:** Use a Swift Package with a testable `StatusTrioCore` library and a tiny `StatusTrio` executable. AppKit owns the `NSStatusItem`, menu, and popover; SwiftUI renders popover content; Core Graphics renders the icon. Battery, Wi-Fi, and volume are isolated behind monitor protocols and merged by a main-actor store.

**Tech Stack:** Swift 6, Swift Package Manager, AppKit, SwiftUI, Core Graphics, IOKit/IOPS, CoreWLAN, Network, CoreAudio, SystemConfiguration, XCTest

---

## Planning Notes

- The current machine has Swift 6.4 and Command Line Tools, but no Xcode installation. Use Swift Package Manager so `swift build` and `swift test` work now. `Package.swift` remains openable in Xcode when installed.
- Create the distributable `.app` with `scripts/build-app.sh`, which copies the SwiftPM executable into a minimal app bundle and adds `Info.plist`.
- Keep every implementation file focused on one responsibility.
- Run each task with test-first steps and commit after the task passes.
- Run tests with `bash scripts/test.sh [XCTestFilter]`; it delegates to `swift test` and accepts an optional filter.

## File Map

| Path | Responsibility |
| --- | --- |
| `Package.swift` | Swift package, targets, frameworks, macOS platform |
| `status-menubar.svg` | Original three-in-one vector reference |
| `status-menubar-demo.html` | Original data-driven visual reference |
| `Sources/StatusTrio/main.swift` | NSApplication entry point |
| `Sources/StatusTrioCore/App/AppDelegate.swift` | App lifecycle and live environment creation |
| `Sources/StatusTrioCore/App/AppEnvironment.swift` | Wires live monitors into the store and status bar |
| `Sources/StatusTrioCore/Models/StatusSnapshot.swift` | Value types for battery, Wi-Fi, and volume |
| `Sources/StatusTrioCore/Models/StatusMappings.swift` | Pure percentage, RSSI, and volume mappings |
| `Sources/StatusTrioCore/Monitoring/MonitorProtocols.swift` | Monitor contracts and shared stream helpers |
| `Sources/StatusTrioCore/Monitoring/BatteryMonitor.swift` | IOPS and Low Power Mode monitoring |
| `Sources/StatusTrioCore/Monitoring/WiFiMonitor.swift` | CoreWLAN and NWPathMonitor monitoring |
| `Sources/StatusTrioCore/Monitoring/VolumeMonitor.swift` | CoreAudio default-device, volume, and mute monitoring |
| `Sources/StatusTrioCore/Store/SystemStatusStore.swift` | Main-actor snapshot merge and fallback refresh |
| `Sources/StatusTrioCore/UI/Icon/StatusIconGeometry.swift` | Core Graphics paths in the 120 x 120 SVG coordinate space |
| `Sources/StatusTrioCore/UI/Icon/StatusIconRenderer.swift` | Snapshot-to-`NSImage` rendering |
| `Sources/StatusTrioCore/UI/StatusBarController.swift` | Status item, click routing, popover, right-click menu |
| `Sources/StatusTrioCore/UI/StatusPopoverView.swift` | SwiftUI popover content |
| `Sources/StatusTrioCore/UI/StatusMenuBuilder.swift` | Right-click menu construction |
| `Support/Info.plist` | `LSUIElement`, bundle identity, version |
| `scripts/build-app.sh` | Release build and `.app` assembly |
| `Tests/StatusTrioCoreTests/StatusSnapshotTests.swift` | Domain model behavior |
| `Tests/StatusTrioCoreTests/StatusMappingsTests.swift` | Pure status mappings |
| `Tests/StatusTrioCoreTests/SystemStatusStoreTests.swift` | Monitor merging and recovery |
| `Tests/StatusTrioCoreTests/StatusIconGeometryTests.swift` | SVG-coordinate path geometry |
| `Tests/StatusTrioCoreTests/StatusIconRendererTests.swift` | Deterministic pixel output |
| `Tests/StatusTrioCoreTests/StatusMenuBuilderTests.swift` | Menu contents and click routing |
| `Tests/StatusTrioCoreTests/StatusPresentationTests.swift` | Popover text and percentage formatting |
| `Tests/StatusTrioCoreTests/BatteryMonitorTests.swift` | Battery reader conversion |
| `Tests/StatusTrioCoreTests/WiFiClassifierTests.swift` | Wi-Fi state precedence |
| `Tests/StatusTrioCoreTests/VolumeMonitorTests.swift` | Volume reader conversion |

---

### Task 1: Bootstrap the Swift package and domain models

**Files:**
- Create: `Package.swift`
- Add: `status-menubar.svg`
- Add: `status-menubar-demo.html`
- Create: `Sources/StatusTrioCore/StatusTrioCore.swift`
- Create: `Sources/StatusTrioCore/Models/StatusSnapshot.swift`
- Create: `Tests/StatusTrioCoreTests/StatusSnapshotTests.swift`

- [x] **Step 1: Write the failing domain model tests**

```swift
import XCTest
@testable import StatusTrioCore

final class StatusSnapshotTests: XCTestCase {
    func testMissingBatteryBehavesAsFull() {
        let battery = BatteryStatus(
            rawPercentage: nil,
            isPresent: false,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: false
        )

        XCTAssertEqual(battery.percentage, 100)
    }

    func testSnapshotDefaultsAreStable() {
        XCTAssertEqual(StatusSnapshot.placeholder.battery.percentage, 100)
        XCTAssertEqual(StatusSnapshot.placeholder.wifi.state, .unavailable)
        XCTAssertNil(StatusSnapshot.placeholder.volume.scalar)
    }
}
```

- [x] **Step 2: Create the package manifest and run the test to verify it fails**

Create `Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StatusTrio",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "StatusTrioCore",
            path: "Sources/StatusTrioCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("IOKit"),
                .linkedFramework("CoreWLAN"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("Network"),
                .linkedFramework("SystemConfiguration")
            ]
        ),
        .testTarget(
            name: "StatusTrioCoreTests",
            dependencies: ["StatusTrioCore"],
            path: "Tests/StatusTrioCoreTests"
        )
    ]
)
```

Create `Sources/StatusTrioCore/StatusTrioCore.swift`:

```swift
enum StatusTrioCoreVersion {
    static let current = "0.1.0"
}
```

Run:

```bash
swift test --filter StatusSnapshotTests
```

Expected: compilation fails because `BatteryStatus`, `WiFiStatus`, `VolumeStatus`, and `StatusSnapshot` do not exist.

- [x] **Step 3: Implement the domain models**

Create `Sources/StatusTrioCore/Models/StatusSnapshot.swift`:

```swift
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
```

- [x] **Step 4: Run the focused tests and then the full suite**

Run:

```bash
swift test --filter StatusSnapshotTests
swift test
```

Expected: both commands pass.

- [x] **Step 5: Commit the package foundation**

```bash
git add Package.swift status-menubar.svg status-menubar-demo.html Sources/StatusTrioCore Tests/StatusTrioCoreTests
git commit -m "feat: bootstrap Status Trio package and models"
```

---

### Task 2: Implement pure status mapping rules

**Files:**
- Create: `Sources/StatusTrioCore/Models/StatusMappings.swift`
- Create: `Tests/StatusTrioCoreTests/StatusMappingsTests.swift`

- [ ] **Step 1: Write the failing boundary tests**

Create `Tests/StatusTrioCoreTests/StatusMappingsTests.swift`:

```swift
import XCTest
@testable import StatusTrioCore

final class StatusMappingsTests: XCTestCase {
    func testWiFiSignalBoundaries() {
        XCTAssertEqual(StatusMappings.wifiBars(rssi: -54), 3)
        XCTAssertEqual(StatusMappings.wifiBars(rssi: -55), 3)
        XCTAssertEqual(StatusMappings.wifiBars(rssi: -56), 2)
        XCTAssertEqual(StatusMappings.wifiBars(rssi: -70), 2)
        XCTAssertEqual(StatusMappings.wifiBars(rssi: -71), 1)
        XCTAssertEqual(StatusMappings.wifiBars(rssi: -85), 1)
        XCTAssertEqual(StatusMappings.wifiBars(rssi: -86), 0)
        XCTAssertEqual(StatusMappings.wifiBars(rssi: nil), 0)
    }

    func testVolumeBoundaries() {
        XCTAssertEqual(StatusMappings.volumeSteps(scalar: 0, isMuted: false), 0)
        XCTAssertEqual(StatusMappings.volumeSteps(scalar: 0.01, isMuted: false), 1)
        XCTAssertEqual(StatusMappings.volumeSteps(scalar: 0.25, isMuted: false), 1)
        XCTAssertEqual(StatusMappings.volumeSteps(scalar: 0.26, isMuted: false), 2)
        XCTAssertEqual(StatusMappings.volumeSteps(scalar: 0.50, isMuted: false), 2)
        XCTAssertEqual(StatusMappings.volumeSteps(scalar: 0.51, isMuted: false), 3)
        XCTAssertEqual(StatusMappings.volumeSteps(scalar: 0.75, isMuted: false), 3)
        XCTAssertEqual(StatusMappings.volumeSteps(scalar: 0.76, isMuted: false), 4)
        XCTAssertEqual(StatusMappings.volumeSteps(scalar: 1.0, isMuted: false), 4)
        XCTAssertEqual(StatusMappings.volumeSteps(scalar: 0.8, isMuted: true), 0)
        XCTAssertNil(StatusMappings.volumeSteps(scalar: nil, isMuted: false))
    }

    func testBatteryColorPriority() {
        let normal = BatteryStatus(
            rawPercentage: 100,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: false
        )
        XCTAssertEqual(StatusMappings.batteryColorRole(normal), .foreground)

        let lowPower = BatteryStatus(
            rawPercentage: 100,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: true,
            isConnectedToPower: false
        )
        XCTAssertEqual(StatusMappings.batteryColorRole(lowPower), .lowPower)

        let charging = BatteryStatus(
            rawPercentage: 100,
            isPresent: true,
            isCharging: true,
            isLowPowerMode: true,
            isConnectedToPower: true
        )
        XCTAssertEqual(StatusMappings.batteryColorRole(charging), .charging)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
swift test --filter StatusMappingsTests
```

Expected: compilation fails because `StatusMappings` and `BatteryColorRole` do not exist.

- [ ] **Step 3: Implement the mappings**

Create `Sources/StatusTrioCore/Models/StatusMappings.swift`:

```swift
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
        case -55...:
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
```

- [ ] **Step 4: Run the mapping and full test suites**

Run:

```bash
swift test --filter StatusMappingsTests
swift test
```

Expected: both commands pass.

- [ ] **Step 5: Commit the mappings**

```bash
git add Sources/StatusTrioCore/Models/StatusMappings.swift Tests/StatusTrioCoreTests/StatusMappingsTests.swift
git commit -m "feat: add pure status mapping rules"
```

---

### Task 3: Add monitor contracts and the main-actor store

**Files:**
- Create: `Sources/StatusTrioCore/Monitoring/MonitorProtocols.swift`
- Create: `Sources/StatusTrioCore/Store/SystemStatusStore.swift`
- Create: `Tests/StatusTrioCoreTests/SystemStatusStoreTests.swift`

- [ ] **Step 1: Write failing store tests with fake monitors**

Create `Tests/StatusTrioCoreTests/SystemStatusStoreTests.swift`:

```swift
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

        store.start()
        battery.send(BatteryStatus(rawPercentage: 42, isPresent: true, isCharging: false, isLowPowerMode: false, isConnectedToPower: false))
        wifi.send(WiFiStatus(state: .connected, rssi: -60))
        volume.send(VolumeStatus(scalar: 0.6, isMuted: false, deviceName: "Speaker"))
        await Task.yield()

        XCTAssertEqual(store.snapshot.battery.percentage, 42)
        XCTAssertEqual(store.snapshot.wifi.state, .connected)
        XCTAssertEqual(store.snapshot.volume.scalar, 0.6)
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

        var publishCount = 0
        store.onSnapshotChange = { _ in publishCount += 1 }
        store.start()
        battery.send(.placeholder)
        battery.send(.placeholder)
        await Task.yield()

        XCTAssertEqual(publishCount, 1)
        store.stop()
    }
}

@MainActor
private final class FakeBatteryMonitor: BatteryMonitoring {
    let updates: AsyncStream<BatteryStatus>
    private let continuation: AsyncStream<BatteryStatus>.Continuation

    init() {
        (updates, continuation) = AsyncStream.makeStream()
    }

    func start() {}
    func stop() { continuation.finish() }
    func refresh() {}
    func send(_ value: BatteryStatus) { continuation.yield(value) }
}

@MainActor
private final class FakeWiFiMonitor: WiFiMonitoring {
    let updates: AsyncStream<WiFiStatus>
    private let continuation: AsyncStream<WiFiStatus>.Continuation

    init() { (updates, continuation) = AsyncStream.makeStream() }
    func start() {}
    func stop() { continuation.finish() }
    func refresh() {}
    func send(_ value: WiFiStatus) { continuation.yield(value) }
}

@MainActor
private final class FakeVolumeMonitor: VolumeMonitoring {
    let updates: AsyncStream<VolumeStatus>
    private let continuation: AsyncStream<VolumeStatus>.Continuation

    init() { (updates, continuation) = AsyncStream.makeStream() }
    func start() {}
    func stop() { continuation.finish() }
    func refresh() {}
    func send(_ value: VolumeStatus) { continuation.yield(value) }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
swift test --filter SystemStatusStoreTests
```

Expected: compilation fails because monitor protocols and `SystemStatusStore` do not exist.

- [ ] **Step 3: Implement monitor protocols**

Create `Sources/StatusTrioCore/Monitoring/MonitorProtocols.swift`:

```swift
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
```

- [ ] **Step 4: Implement `SystemStatusStore`**

Create `Sources/StatusTrioCore/Store/SystemStatusStore.swift`:

```swift
import Combine
import Foundation

@MainActor
final class SystemStatusStore: ObservableObject {
    @Published private(set) var snapshot: StatusSnapshot

    var onSnapshotChange: ((StatusSnapshot) -> Void)?

    private let batteryMonitor: any BatteryMonitoring
    private let wifiMonitor: any WiFiMonitoring
    private let volumeMonitor: any VolumeMonitoring
    private let refreshInterval: Duration
    private var monitorTasks: [Task<Void, Never>] = []
    private var refreshTask: Task<Void, Never>?

    init(
        batteryMonitor: any BatteryMonitoring,
        wifiMonitor: any WiFiMonitoring,
        volumeMonitor: any VolumeMonitoring,
        refreshInterval: Duration = .seconds(5),
        initialSnapshot: StatusSnapshot = .placeholder
    ) {
        self.batteryMonitor = batteryMonitor
        self.wifiMonitor = wifiMonitor
        self.volumeMonitor = volumeMonitor
        self.refreshInterval = refreshInterval
        self.snapshot = initialSnapshot
    }

    func start() {
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
                try? await Task.sleep(for: refreshInterval)
                guard !Task.isCancelled else { return }
                self.refreshAll()
            }
        }
    }

    func stop() {
        batteryMonitor.stop()
        wifiMonitor.stop()
        volumeMonitor.stop()
        monitorTasks.forEach { $0.cancel() }
        monitorTasks.removeAll()
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refreshAll() {
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
        guard next != snapshot else { return }
        snapshot = next
        onSnapshotChange?(next)
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
```

- [ ] **Step 5: Run focused and full tests, then commit**

Run:

```bash
swift test --filter SystemStatusStoreTests
swift test
```

Expected: both commands pass.

```bash
git add Sources/StatusTrioCore/Monitoring/MonitorProtocols.swift Sources/StatusTrioCore/Store/SystemStatusStore.swift Tests/StatusTrioCoreTests/SystemStatusStoreTests.swift
git commit -m "feat: add monitor contracts and status store"
```

---

### Task 4: Build the icon geometry in the SVG coordinate space

**Files:**
- Create: `Sources/StatusTrioCore/UI/Icon/StatusIconGeometry.swift`
- Create: `Tests/StatusTrioCoreTests/StatusIconGeometryTests.swift`

- [ ] **Step 1: Write failing geometry tests**

Create `Tests/StatusTrioCoreTests/StatusIconGeometryTests.swift`:

```swift
import CoreGraphics
import XCTest
@testable import StatusTrioCore

final class StatusIconGeometryTests: XCTestCase {
    func testBatteryPathsStayInsideCanvas() {
        let track = StatusIconGeometry.batteryTrack()
        let fill = StatusIconGeometry.batteryFill(progress: 0.5)

        XCTAssertTrue(StatusIconGeometry.canvas.contains(track.boundingBox))
        XCTAssertTrue(StatusIconGeometry.canvas.contains(fill.boundingBox))
    }

    func testZeroBatteryHasNoFillPath() {
        XCTAssertTrue(StatusIconGeometry.batteryFill(progress: 0).isEmpty)
    }

    func testVolumeDotCount() {
        XCTAssertEqual(StatusIconGeometry.volumeDots().count, 4)
    }
}

private extension CGRect {
    func contains(_ other: CGRect) -> Bool {
        insetBy(dx: -0.01, dy: -0.01).contains(other)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
swift test --filter StatusIconGeometryTests
```

Expected: compilation fails because `StatusIconGeometry` does not exist.

- [ ] **Step 3: Implement the path builder**

Create `Sources/StatusTrioCore/UI/Icon/StatusIconGeometry.swift`:

```swift
import CoreGraphics
import Foundation

enum StatusIconGeometry {
    static let canvas = CGRect(x: 0, y: 0, width: 120, height: 120)

    private static let batteryRadius: CGFloat = 51.5
    private static let batteryCenter = CGPoint(x: 59.5, y: 61.49)
    private static let batteryStart: CGFloat = 148.65 * .pi / 180
    private static let batterySweep: CGFloat = 242.7 * .pi / 180

    static func batteryTrack() -> CGPath {
        batteryArc(progress: 1)
    }

    static func batteryFill(progress: Double) -> CGPath {
        let clamped = min(1, max(0, progress))
        guard clamped > 0 else { return CGMutablePath() }
        return batteryArc(progress: clamped)
    }

    static func wifiArcs(level: Int) -> [CGPath] {
        let outer = arc(
            center: CGPoint(x: 59.5, y: 78.3),
            radius: 31,
            start: 227.35 * .pi / 180,
            end: 312.65 * .pi / 180
        )
        let middle = arc(
            center: CGPoint(x: 59.5, y: 78.89),
            radius: 18.5,
            start: 227.5 * .pi / 180,
            end: 312.5 * .pi / 180
        )
        let all = [outer, middle]
        switch level {
        case 3: return all
        case 2: return [middle]
        case 1: return []
        default: return []
        }
    }

    static func wifiDot() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 59.5, y: 69.9))
        path.addCurve(
            to: CGPoint(x: 66.5, y: 73),
            control1: CGPoint(x: 61.0, y: 69.9),
            control2: CGPoint(x: 65.2, y: 70.8)
        )
        path.addCurve(
            to: CGPoint(x: 66.5, y: 75),
            control1: CGPoint(x: 66.7, y: 73.8),
            control2: CGPoint(x: 66.7, y: 74.3)
        )
        path.addCurve(
            to: CGPoint(x: 59.5, y: 80.95),
            control1: CGPoint(x: 63.8, y: 78.8),
            control2: CGPoint(x: 61.15, y: 80.95)
        )
        path.addCurve(
            to: CGPoint(x: 52.5, y: 75),
            control1: CGPoint(x: 57.85, y: 80.95),
            control2: CGPoint(x: 55.2, y: 78.8)
        )
        path.addCurve(
            to: CGPoint(x: 52.5, y: 73),
            control1: CGPoint(x: 52.3, y: 74.3),
            control2: CGPoint(x: 52.3, y: 73.8)
        )
        path.addCurve(
            to: CGPoint(x: 59.5, y: 69.9),
            control1: CGPoint(x: 53.8, y: 70.8),
            control2: CGPoint(x: 58.0, y: 69.9)
        )
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
        left.addArc(center: CGPoint(x: 49, y: 58), radius: 8, startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: true)
        left.addLine(to: CGPoint(x: 54, y: 50))

        let right = CGMutablePath()
        right.move(to: CGPoint(x: 66, y: 50))
        right.addLine(to: CGPoint(x: 70, y: 50))
        right.addArc(center: CGPoint(x: 70, y: 58), radius: 8, startAngle: 3 * .pi / 2, endAngle: -.pi / 2, clockwise: true)
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
        path.addArc(
            center: center,
            radius: radius,
            startAngle: start,
            endAngle: end,
            clockwise: false
        )
        return path
    }
}
```

- [ ] **Step 4: Run geometry and full tests**

Run:

```bash
swift test --filter StatusIconGeometryTests
swift test
```

Expected: both commands pass.

- [ ] **Step 5: Commit geometry**

```bash
git add Sources/StatusTrioCore/UI/Icon/StatusIconGeometry.swift Tests/StatusTrioCoreTests/StatusIconGeometryTests.swift
git commit -m "feat: add three-in-one icon geometry"
```

---

### Task 5: Render normal, charging, low-power, Wi-Fi, and volume states

**Files:**
- Create: `Sources/StatusTrioCore/UI/Icon/StatusIconRenderer.swift`
- Create: `Tests/StatusTrioCoreTests/StatusIconRendererTests.swift`

- [ ] **Step 1: Write failing renderer tests**

Create `Tests/StatusTrioCoreTests/StatusIconRendererTests.swift`:

```swift
import AppKit
import CoreGraphics
import XCTest
@testable import StatusTrioCore

final class StatusIconRendererTests: XCTestCase {
    func testRendererProducesExpectedPixelSize() {
        let image = StatusIconRenderer.render(
            snapshot: .placeholder,
            size: 20,
            scale: 2,
            foreground: CGColor(gray: 1, alpha: 1)
        )

        XCTAssertEqual(image.width, 40)
        XCTAssertEqual(image.height, 40)
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
            image: StatusIconRenderer.render(
                snapshot: snapshot,
                size: 20,
                scale: 2,
                foreground: CGColor(gray: 1, alpha: 1)
            )
        )

        XCTAssertTrue(pixels.containsColor(red: 0.20, green: 0.78, blue: 0.35, tolerance: 0.08))
    }

    func testOffStateUsesMutedSignalAndSlash() throws {
        let snapshot = StatusSnapshot(
            battery: .placeholder,
            wifi: WiFiStatus(state: .off, rssi: nil),
            volume: .placeholder
        )

        let image = StatusIconRenderer.render(
            snapshot: snapshot,
            size: 20,
            scale: 2,
            foreground: CGColor(gray: 1, alpha: 1)
        )

        XCTAssertEqual(image.width, 40)
        XCTAssertEqual(image.height, 40)
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
            image: StatusIconRenderer.render(
                snapshot: snapshot,
                size: 20,
                scale: 2,
                foreground: CGColor(gray: 1, alpha: 1)
            )
        )

        XCTAssertTrue(pixels.containsColor(red: 0.95, green: 0.73, blue: 0.0, tolerance: 0.08))
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

    func containsColor(red: Double, green: Double, blue: Double, tolerance: Double) -> Bool {
        bytes.enumerated().contains { index, byte in
            index % 4 == 0 && abs(Double(byte) / 255.0 - red) <= tolerance
        } && bytes.enumerated().contains { index, byte in
            index % 4 == 1 && abs(Double(byte) / 255.0 - green) <= tolerance
        } && bytes.enumerated().contains { index, byte in
            index % 4 == 2 && abs(Double(byte) / 255.0 - blue) <= tolerance
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
swift test --filter StatusIconRendererTests
```

Expected: compilation fails because `StatusIconRenderer` does not exist.

- [ ] **Step 3: Implement the renderer**

Create `Sources/StatusTrioCore/UI/Icon/StatusIconRenderer.swift`:

```swift
import AppKit
import CoreGraphics

enum StatusIconRenderer {
    static let baseSize: CGFloat = 20

    static func image(
        snapshot: StatusSnapshot,
        size: CGFloat = baseSize,
        appearance: NSAppearance
    ) -> NSImage {
        appearance.performAsCurrentDrawingAppearance {
            let foreground = NSColor.labelColor.usingColorSpace(.deviceRGB)?.cgColor
                ?? CGColor(gray: 1, alpha: 1)
            let image = NSImage(size: NSSize(width: size, height: size))
            image.lockFocus()
            defer { image.unlockFocus() }
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            draw(snapshot: snapshot, in: context, size: size, foreground: foreground)
        }
    }

    static func render(
        snapshot: StatusSnapshot,
        size: CGFloat,
        scale: CGFloat,
        foreground: CGColor
    ) -> CGImage {
        let pixelWidth = Int(size * scale)
        let pixelHeight = Int(size * scale)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: pixelWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.scaleBy(x: scale, y: scale)
        draw(snapshot: snapshot, in: context, size: size, foreground: foreground)
        return context.makeImage()!
    }

    private static func draw(
        snapshot: StatusSnapshot,
        in context: CGContext,
        size: CGFloat,
        foreground: CGColor
    ) {
        context.saveGState()
        defer { context.restoreGState() }

        let scale = size / 120
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
            fillColor = CGColor(red: 0.204, green: 0.780, blue: 0.349, alpha: 1)
        case .lowPower:
            fillColor = CGColor(red: 0.949, green: 0.725, blue: 0.0, alpha: 1)
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
            let color = bars == 0 ? mutedColor : foreground
            for path in StatusIconGeometry.wifiArcs(level: bars) {
                context.setStrokeColor(color)
                context.addPath(path)
                context.strokePath()
            }
            context.setFillColor(color)
            context.addPath(StatusIconGeometry.wifiDot())
            context.fillPath()

        case .notAssociated, .off, .unavailable:
            context.setStrokeColor(mutedColor)
            for path in StatusIconGeometry.wifiArcs(level: 3) {
                context.addPath(path)
                context.strokePath()
            }
            context.setFillColor(mutedColor)
            context.addPath(StatusIconGeometry.wifiDot())
            context.fillPath()
            if wifi.state == .off {
                context.setLineWidth(6)
                context.addPath(StatusIconGeometry.wifiOffSlash())
                context.strokePath()
            }

        case .noInternet:
            context.setStrokeColor(mutedColor)
            for path in StatusIconGeometry.wifiArcs(level: 3) {
                context.addPath(path)
                context.strokePath()
            }
            let overlay = StatusIconGeometry.noInternetOverlay()
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
            context.addPath(StatusIconGeometry.temporaryWedge())
            context.fillPath()
            context.saveGState()
            context.setBlendMode(.clear)
            context.addPath(StatusIconGeometry.temporaryScreenCutout())
            context.fillPath()
            context.restoreGState()
            context.setStrokeColor(foreground)
            context.setLineWidth(7)
            context.addPath(StatusIconGeometry.temporaryWedge())
            context.strokePath()

        case .shared:
            context.setFillColor(foreground)
            context.addPath(StatusIconGeometry.sharedWedge())
            context.fillPath()
            context.saveGState()
            context.setBlendMode(.clear)
            context.addPath(StatusIconGeometry.sharedArrowCutout())
            context.fillPath()
            context.restoreGState()
            context.setStrokeColor(foreground)
            context.setLineWidth(7)
            context.addPath(StatusIconGeometry.sharedWedge())
            context.strokePath()
        }
    }

    private static func drawVolume(
        _ volume: VolumeStatus,
        in context: CGContext,
        foreground: CGColor
    ) {
        let level = StatusMappings.volumeSteps(scalar: volume.scalar, isMuted: volume.isMuted) ?? 0
        for (index, point) in StatusIconGeometry.volumeDots().enumerated() {
            let isVisible = index < level
            context.setFillColor(
                isVisible ? foreground : (foreground.copy(alpha: 0.22) ?? foreground)
            )
            context.fillEllipse(
                in: CGRect(
                    x: point.x - StatusIconGeometry.volumeDotRadius,
                    y: point.y - StatusIconGeometry.volumeDotRadius,
                    width: StatusIconGeometry.volumeDotRadius * 2,
                    height: StatusIconGeometry.volumeDotRadius * 2
                )
            )
        }
    }
}
```

- [ ] **Step 4: Run renderer and full tests**

Run:

```bash
swift test --filter StatusIconRendererTests
swift test
```

Expected: both commands pass. If the geometry is visually inverted, update `StatusIconGeometryTests` first with a failing bounding-box assertion, then correct the arc direction.

- [ ] **Step 5: Commit the renderer**

```bash
git add Sources/StatusTrioCore/UI/Icon/StatusIconRenderer.swift Tests/StatusTrioCoreTests/StatusIconRendererTests.swift
git commit -m "feat: render three-in-one menu bar icon"
```

---

### Task 6: Add temporary and shared Wi-Fi overlays

**Files:**
- Modify: `Sources/StatusTrioCore/UI/Icon/StatusIconGeometry.swift`
- Modify: `Sources/StatusTrioCore/UI/Icon/StatusIconRenderer.swift`
- Modify: `Tests/StatusTrioCoreTests/StatusIconGeometryTests.swift`
- Modify: `Tests/StatusTrioCoreTests/StatusIconRendererTests.swift`

- [ ] **Step 1: Write failing overlay tests**

Append to `StatusIconGeometryTests`:

```swift
    func testSpecialWiFiOverlaysExist() {
        XCTAssertFalse(StatusIconGeometry.temporaryWedge().isEmpty)
        XCTAssertFalse(StatusIconGeometry.temporaryScreenCutout().isEmpty)
        XCTAssertFalse(StatusIconGeometry.sharedWedge().isEmpty)
        XCTAssertFalse(StatusIconGeometry.sharedArrowCutout().isEmpty)
    }
```

Append to `StatusIconRendererTests`:

```swift
    func testTemporaryAndSharedStatesProducePixels() {
        for state in [WiFiState.temporary, .shared] {
            let snapshot = StatusSnapshot(
                battery: .placeholder,
                wifi: WiFiStatus(state: state, rssi: -50),
                volume: .placeholder
            )
            let image = StatusIconRenderer.render(
                snapshot: snapshot,
                size: 20,
                scale: 2,
                foreground: CGColor(gray: 1, alpha: 1)
            )
            XCTAssertGreaterThan(image.width, 0)
        }
    }
```

- [ ] **Step 2: Run the overlay tests to verify they fail**

Run:

```bash
swift test --filter StatusIconGeometryTests/testSpecialWiFiOverlaysExist
swift test --filter StatusIconRendererTests/testTemporaryAndSharedStatesProducePixels
```

Expected: compilation fails because the overlay geometry functions do not exist.

- [ ] **Step 3: Add the overlay paths**

Add to `StatusIconGeometry`:

```swift
    static func temporaryWedge() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 38.5, y: 55.5))
        path.addArc(
            center: CGPoint(x: 59.5, y: 78.3),
            radius: 31,
            startAngle: 227.35 * .pi / 180,
            endAngle: 312.65 * .pi / 180,
            clockwise: false
        )
        path.addLine(to: CGPoint(x: 59.5, y: 77.45))
        path.closeSubpath()
        return path
    }

    static func temporaryScreenCutout() -> CGPath {
        let path = CGMutablePath()
        path.addRoundedRect(
            in: CGRect(x: 50.5, y: 53.5, width: 18, height: 12),
            cornerWidth: 2.5,
            cornerHeight: 2.5
        )
        path.move(to: CGPoint(x: 57.5, y: 65.5))
        path.addLine(to: CGPoint(x: 61.5, y: 65.5))
        path.addLine(to: CGPoint(x: 61.5, y: 67.5))
        path.addLine(to: CGPoint(x: 63, y: 67.5))
        path.addLine(to: CGPoint(x: 63, y: 70.5))
        path.addLine(to: CGPoint(x: 56, y: 70.5))
        path.addLine(to: CGPoint(x: 56, y: 67.5))
        path.addLine(to: CGPoint(x: 57.5, y: 67.5))
        path.closeSubpath()
        return path
    }

    static func sharedWedge() -> CGPath {
        temporaryWedge()
    }

    static func sharedArrowCutout() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 59.5, y: 51.5))
        path.addLine(to: CGPoint(x: 67.5, y: 59.5))
        path.addLine(to: CGPoint(x: 63, y: 59.5))
        path.addLine(to: CGPoint(x: 63, y: 72.5))
        path.addLine(to: CGPoint(x: 56, y: 72.5))
        path.addLine(to: CGPoint(x: 56, y: 59.5))
        path.addLine(to: CGPoint(x: 51.5, y: 59.5))
        path.closeSubpath()
        return path
    }
```

- [ ] **Step 4: Compose the transparent cutouts in the renderer**

Replace the `.temporary, .shared` branch in `drawWiFi` with:

```swift
        case .temporary:
            context.setFillColor(foreground)
            context.addPath(StatusIconGeometry.temporaryWedge())
            context.fillPath()
            context.saveGState()
            context.setBlendMode(.clear)
            context.addPath(StatusIconGeometry.temporaryScreenCutout())
            context.fillPath()
            context.restoreGState()
            context.setStrokeColor(foreground)
            context.setLineWidth(7)
            context.addPath(StatusIconGeometry.temporaryWedge())
            context.strokePath()
        case .shared:
            context.setFillColor(foreground)
            context.addPath(StatusIconGeometry.sharedWedge())
            context.fillPath()
            context.saveGState()
            context.setBlendMode(.clear)
            context.addPath(StatusIconGeometry.sharedArrowCutout())
            context.fillPath()
            context.restoreGState()
            context.setStrokeColor(foreground)
            context.setLineWidth(7)
            context.addPath(StatusIconGeometry.sharedWedge())
            context.strokePath()
```

- [ ] **Step 5: Run tests and commit**

```bash
swift test
git add Sources/StatusTrioCore/UI/Icon/StatusIconGeometry.swift Sources/StatusTrioCore/UI/Icon/StatusIconRenderer.swift Tests/StatusTrioCoreTests/StatusIconGeometryTests.swift Tests/StatusTrioCoreTests/StatusIconRendererTests.swift
git commit -m "feat: add special Wi-Fi icon overlays"
```

---

### Task 7: Add the AppKit app shell and right-click menu

**Files:**
- Modify: `Package.swift`
- Create: `Sources/StatusTrio/main.swift`
- Create: `Sources/StatusTrioCore/UI/StatusMenuBuilder.swift`
- Create: `Sources/StatusTrioCore/UI/StatusBarController.swift`
- Create: `Sources/StatusTrioCore/App/AppDelegate.swift`
- Create: `Tests/StatusTrioCoreTests/StatusMenuBuilderTests.swift`

- [ ] **Step 1: Write failing menu and click-routing tests**

Create `Tests/StatusTrioCoreTests/StatusMenuBuilderTests.swift`:

```swift
import AppKit
import XCTest
@testable import StatusTrioCore

@MainActor
final class StatusMenuBuilderTests: XCTestCase {
    func testMenuContainsVersionPlaceholderAndQuit() {
        let menu = StatusMenuBuilder.makeMenu(version: "1.0.0")

        XCTAssertEqual(menu.items.map(\.title), [
            "Status Trio 1.0.0",
            "设置…",
            "",
            "退出 Status Trio"
        ])
        XCTAssertFalse(menu.items[0].isEnabled)
        XCTAssertFalse(menu.items[1].isEnabled)
        XCTAssertTrue(menu.items[3].isEnabled)
    }

    func testClickClassification() {
        XCTAssertEqual(StatusBarController.clickKind(eventType: .leftMouseUp, modifiers: []), .left)
        XCTAssertEqual(StatusBarController.clickKind(eventType: .rightMouseUp, modifiers: []), .right)
        XCTAssertEqual(StatusBarController.clickKind(eventType: .leftMouseUp, modifiers: [.control]), .right)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
swift test --filter StatusMenuBuilderTests
```

Expected: compilation fails because `StatusMenuBuilder` and `StatusBarController` do not exist.

- [ ] **Step 3: Implement the menu builder**

Create `Sources/StatusTrioCore/UI/StatusMenuBuilder.swift`:

```swift
import AppKit

@MainActor
enum StatusMenuBuilder {
    static func makeMenu(version: String) -> NSMenu {
        let menu = NSMenu()

        let versionItem = NSMenuItem(
            title: "Status Trio \(version)",
            action: nil,
            keyEquivalent: ""
        )
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        let settingsItem = NSMenuItem(
            title: "设置…",
            action: nil,
            keyEquivalent: ""
        )
        settingsItem.isEnabled = false
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出 Status Trio",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApplication.shared
        menu.addItem(quitItem)

        return menu
    }
}
```

- [ ] **Step 4: Add the executable target, status bar controller, and app entry point**

Replace `Package.swift` with:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StatusTrio",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "StatusTrio", targets: ["StatusTrio"])
    ],
    targets: [
        .target(
            name: "StatusTrioCore",
            path: "Sources/StatusTrioCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("IOKit"),
                .linkedFramework("CoreWLAN"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("Network"),
                .linkedFramework("SystemConfiguration")
            ]
        ),
        .executableTarget(
            name: "StatusTrio",
            dependencies: ["StatusTrioCore"],
            path: "Sources/StatusTrio"
        ),
        .testTarget(
            name: "StatusTrioCoreTests",
            dependencies: ["StatusTrioCore"],
            path: "Tests/StatusTrioCoreTests"
        )
    ]
)
```

Create `Sources/StatusTrioCore/UI/StatusBarController.swift`:

```swift
import AppKit
import Combine

@MainActor
final class StatusBarController: NSObject {
    enum ClickKind: Equatable {
        case left
        case right
    }

    private let statusItem: NSStatusItem
    private let store: SystemStatusStore
    private var cancellable: AnyCancellable?
    private let quitAction: () -> Void
    private var appearanceObservation: NSKeyValueObservation?

    init(store: SystemStatusStore, quitAction: @escaping () -> Void) {
        self.store = store
        self.quitAction = quitAction
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureButton()
        render(snapshot: store.snapshot)

        cancellable = store.$snapshot
            .removeDuplicates()
            .sink { [weak self] snapshot in
                self?.render(snapshot: snapshot)
            }

        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                self.render(snapshot: self.store.snapshot)
            }
        }
    }

    static func clickKind(eventType: NSEvent.EventType, modifiers: NSEvent.ModifierFlags) -> ClickKind? {
        if eventType == .rightMouseUp || modifiers.contains(.control) {
            return .right
        }
        if eventType == .leftMouseUp {
            return .left
        }
        return nil
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard
            let event = NSApp.currentEvent,
            let click = Self.clickKind(eventType: event.type, modifiers: event.modifierFlags)
        else { return }

        switch click {
        case .left:
            break
        case .right:
            showMenu()
        }
    }

    private func render(snapshot: StatusSnapshot) {
        guard let button = statusItem.button else { return }
        button.image = StatusIconRenderer.image(
            snapshot: snapshot,
            appearance: button.effectiveAppearance
        )
    }

    private func showMenu() {
        let menu = StatusMenuBuilder.makeMenu(version: "1.0.0")
        guard let button = statusItem.button else { return }
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.minY - 4),
            in: button
        )
    }
}
```

Create `Sources/StatusTrioCore/App/AppDelegate.swift`:

```swift
import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: SystemStatusStore?
    private var statusBarController: StatusBarController?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        let store = SystemStatusStore(
            batteryMonitor: UnavailableBatteryMonitor(),
            wifiMonitor: UnavailableWiFiMonitor(),
            volumeMonitor: UnavailableVolumeMonitor()
        )
        let controller = StatusBarController(store: store) {
            NSApplication.shared.terminate(nil)
        }

        self.store = store
        self.statusBarController = controller
        store.start()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        store?.stop()
    }
}
```

Create temporary unavailable monitors in `MonitorProtocols.swift` so Task 7 leaves the app working:

```swift
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
```

Create `Sources/StatusTrio/main.swift`:

```swift
import AppKit
import StatusTrioCore

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
```

- [ ] **Step 5: Run tests, build, manual smoke test, and commit**

Run:

```bash
swift test --filter StatusMenuBuilderTests
swift test
swift build
swift run StatusTrio
```

Expected: tests pass, build succeeds, and a static 20 pt icon appears in the menu bar. Right-click shows the version, disabled settings, divider, and quit. Press Control-C in the terminal to stop the smoke test.

```bash
git add Sources/StatusTrio Sources/StatusTrioCore/App Sources/StatusTrioCore/UI Sources/StatusTrioCore/Monitoring/MonitorProtocols.swift Tests/StatusTrioCoreTests/StatusMenuBuilderTests.swift
git commit -m "feat: add menu bar app shell"
```

---

### Task 8: Add the left-click SwiftUI popover

**Files:**
- Create: `Sources/StatusTrioCore/UI/StatusPopoverView.swift`
- Modify: `Sources/StatusTrioCore/UI/StatusBarController.swift`
- Create: `Tests/StatusTrioCoreTests/StatusPresentationTests.swift`

- [ ] **Step 1: Write failing presentation tests**

Create `Tests/StatusTrioCoreTests/StatusPresentationTests.swift`:

```swift
import XCTest
@testable import StatusTrioCore

final class StatusPresentationTests: XCTestCase {
    func testBatterySubtitlePriority() {
        let connected = BatteryStatus(
            rawPercentage: 100,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: true
        )
        XCTAssertEqual(StatusPresentation.batterySubtitle(connected), "已连接电源")

        let charging = BatteryStatus(
            rawPercentage: 100,
            isPresent: true,
            isCharging: true,
            isLowPowerMode: false,
            isConnectedToPower: true
        )
        XCTAssertEqual(StatusPresentation.batterySubtitle(charging), "正在充电")

        let lowPower = BatteryStatus(
            rawPercentage: 100,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: true,
            isConnectedToPower: false
        )
        XCTAssertEqual(StatusPresentation.batterySubtitle(lowPower), "低电量模式")
    }

    func testVolumeSubtitleAndValue() {
        XCTAssertEqual(
            StatusPresentation.volumeValue(VolumeStatus(scalar: nil, isMuted: false, deviceName: nil)),
            "—"
        )
        XCTAssertEqual(
            StatusPresentation.volumeValue(VolumeStatus(scalar: 0.62, isMuted: false, deviceName: "Speaker")),
            "62% · 3 格"
        )
    }
}
```

- [ ] **Step 2: Run the presentation test to verify it fails**

Run:

```bash
swift test --filter StatusPresentationTests
```

Expected: compilation fails because `StatusPresentation` does not exist.

- [ ] **Step 3: Implement presentation helpers and the SwiftUI view**

Create `Sources/StatusTrioCore/UI/StatusPopoverView.swift`:

```swift
import SwiftUI

enum StatusPresentation {
    static func batterySubtitle(_ battery: BatteryStatus) -> String {
        if !battery.isPresent { return "无电池设备" }
        if battery.isCharging { return "正在充电" }
        if battery.isLowPowerMode { return "低电量模式" }
        if battery.isConnectedToPower { return "已连接电源" }
        return "电池供电"
    }

    static func wifiValue(_ wifi: WiFiStatus) -> String {
        switch wifi.state {
        case .connected:
            return "\(StatusMappings.wifiBars(rssi: wifi.rssi)) 格"
        case .notAssociated:
            return "未关联"
        case .off:
            return "关闭"
        case .noInternet:
            return "无互联网"
        case .hotspot:
            return "iPhone 热点"
        case .temporary:
            return "临时连接"
        case .shared:
            return "正在共享"
        case .unavailable:
            return "不可用"
        }
    }

    static func wifiSubtitle(_ wifi: WiFiStatus) -> String {
        switch wifi.state {
        case .connected:
            return "已连接"
        case .notAssociated:
            return "Wi-Fi 开启，未关联"
        case .off:
            return "Wi-Fi 关闭或不可用"
        case .noInternet:
            return "网络可达性检查失败"
        case .hotspot:
            return "使用 iPhone 热点"
        case .temporary:
            return "临时 Wi-Fi 连接"
        case .shared:
            return "正在共享互联网"
        case .unavailable:
            return "无法读取网络状态"
        }
    }

    static func volumeValue(_ volume: VolumeStatus) -> String {
        guard let scalar = volume.scalar else { return "—" }
        let percentage = Int((min(1, max(0, scalar)) * 100).rounded())
        let steps = StatusMappings.volumeSteps(scalar: scalar, isMuted: volume.isMuted) ?? 0
        return volume.isMuted ? "静音" : "\(percentage)% · \(steps) 格"
    }

    static func volumeSubtitle(_ volume: VolumeStatus) -> String {
        volume.deviceName ?? "无默认输出设备"
    }
}

struct StatusPopoverView: View {
    @ObservedObject var store: SystemStatusStore
    let quit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusRow(
                icon: "battery.100",
                title: "电池",
                subtitle: StatusPresentation.batterySubtitle(store.snapshot.battery),
                value: "\(store.snapshot.battery.percentage)%"
            )
            Divider()
            statusRow(
                icon: "wifi",
                title: "Wi-Fi",
                subtitle: StatusPresentation.wifiSubtitle(store.snapshot.wifi),
                value: StatusPresentation.wifiValue(store.snapshot.wifi)
            )
            Divider()
            statusRow(
                icon: "speaker.wave.2.fill",
                title: "音量",
                subtitle: StatusPresentation.volumeSubtitle(store.snapshot.volume),
                value: StatusPresentation.volumeValue(store.snapshot.volume)
            )

            Divider()

            Button("设置…") {}
                .buttonStyle(.plain)
                .disabled(true)
                .foregroundStyle(.secondary)

            Button("退出 Status Trio") {
                quit()
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
        }
        .padding(14)
        .frame(width: 300)
    }

    private func statusRow(
        icon: String,
        title: String,
        subtitle: String,
        value: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(value)
                .font(.body.monospacedDigit().weight(.semibold))
        }
    }
}
```

- [ ] **Step 4: Wire left click to an anchored popover**

Add to `StatusBarController`:

```swift
    private let popover = NSPopover()

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 300, height: 228)
        popover.contentViewController = NSHostingController(
            rootView: StatusPopoverView(store: store, quit: quitAction)
        )
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(
                relativeTo: button.bounds,
                of: button,
                preferredEdge: .minY
            )
        }
    }
```

Call `configurePopover()` after `configureButton()` and replace the `.left` branch with `togglePopover()`. Add `import SwiftUI` to `StatusBarController.swift`.

- [ ] **Step 5: Run tests, smoke test, and commit**

Run:

```bash
swift test
swift build
swift run StatusTrio
```

Expected: left-click opens the popover below the status item; clicking outside or pressing Esc closes it. Right-click remains a native menu.

```bash
git add Sources/StatusTrioCore/UI/StatusPopoverView.swift Sources/StatusTrioCore/UI/StatusBarController.swift Tests/StatusTrioCoreTests/StatusPresentationTests.swift
git commit -m "feat: add status popover"
```

---

### Task 9: Implement battery monitoring

**Files:**
- Create: `Sources/StatusTrioCore/Monitoring/BatteryMonitor.swift`
- Create: `Tests/StatusTrioCoreTests/BatteryMonitorTests.swift`

- [ ] **Step 1: Write failing battery reader tests**

Create `Tests/StatusTrioCoreTests/BatteryMonitorTests.swift`:

```swift
import XCTest
@testable import StatusTrioCore

@MainActor
final class BatteryMonitorTests: XCTestCase {
    func testMonitorConvertsReaderOutput() async {
        let reader = FakeBatteryReader(result: BatteryReading(
            currentCapacity: 73,
            maxCapacity: 100,
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

        XCTAssertEqual(value?.percentage, 73)
        XCTAssertTrue(value?.isCharging == true)
        XCTAssertTrue(value?.isLowPowerMode == true)
    }

    func testMissingBatteryUsesFullValue() async {
        let reader = FakeBatteryReader(result: nil)
        let monitor = BatteryMonitor(reader: reader, lowPowerModeProvider: { false })

        monitor.refresh()
        var iterator = monitor.updates.makeAsyncIterator()
        let value = await iterator.next()

        XCTAssertEqual(value?.percentage, 100)
        XCTAssertFalse(value?.isPresent == true)
    }
}

private final class FakeBatteryReader: BatteryReading {
    let result: BatteryReading?

    init(result: BatteryReading?) {
        self.result = result
    }

    func read() -> BatteryReading? {
        result
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
swift test --filter BatteryMonitorTests
```

Expected: compilation fails because `BatteryReading`, `FakeBatteryReader`, and `BatteryMonitor` do not exist.

- [ ] **Step 3: Implement the IOPS reader and monitor**

Create `Sources/StatusTrioCore/Monitoring/BatteryMonitor.swift`:

```swift
import Foundation
import IOKit.ps

struct BatteryReading: Equatable {
    var currentCapacity: Int
    var maxCapacity: Int
    var isCharging: Bool
    var isConnectedToPower: Bool
    var isPresent: Bool
}

protocol BatteryReading: AnyObject {
    func read() -> BatteryReading?
}

final class IOPSBatteryReader: BatteryReading {
    func read() -> BatteryReading? {
        guard
            let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(snapshot, source)?
                    .takeUnretainedValue() as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 100
            let maximum = description[kIOPSMaxCapacityKey] as? Int ?? 100
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            let connected = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let present = description[kIOPSIsPresentKey] as? Bool ?? true
            return BatteryReading(
                currentCapacity: current,
                maxCapacity: maximum,
                isCharging: charging,
                isConnectedToPower: connected,
                isPresent: present
            )
        }
        return nil
    }
}

@MainActor
final class BatteryMonitor: BatteryMonitoring {
    let updates: AsyncStream<BatteryStatus>
    private let continuation: AsyncStream<BatteryStatus>.Continuation
    private let reader: any BatteryReading
    private let lowPowerModeProvider: () -> Bool
    private var runLoopSource: CFRunLoopSource?
    private var lowPowerObserver: NSObjectProtocol?

    init(
        reader: any BatteryReading = IOPSBatteryReader(),
        lowPowerModeProvider: @escaping () -> Bool = {
            ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    ) {
        self.reader = reader
        self.lowPowerModeProvider = lowPowerModeProvider
        (updates, continuation) = AsyncStream.makeStream()
    }

    func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in monitor.refresh() }
        }, context)?.takeRetainedValue() {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }

        lowPowerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }

        refresh()
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
            self.runLoopSource = nil
        }
        if let lowPowerObserver {
            NotificationCenter.default.removeObserver(lowPowerObserver)
            self.lowPowerObserver = nil
        }
        continuation.finish()
    }

    func refresh() {
        let reading = reader.read()
        let status: BatteryStatus

        if let reading, reading.isPresent {
            let percentage = reading.maxCapacity > 0
                ? Int((Double(reading.currentCapacity) / Double(reading.maxCapacity) * 100).rounded())
                : reading.currentCapacity
            status = BatteryStatus(
                rawPercentage: percentage,
                isPresent: true,
                isCharging: reading.isCharging,
                isLowPowerMode: lowPowerModeProvider(),
                isConnectedToPower: reading.isConnectedToPower
            )
        } else {
            status = BatteryStatus(
                rawPercentage: nil,
                isPresent: false,
                isCharging: false,
                isLowPowerMode: lowPowerModeProvider(),
                isConnectedToPower: false
            )
        }

        continuation.yield(status)
    }
}
```

- [ ] **Step 4: Run tests and verify the live reading manually**

Run:

```bash
swift test --filter BatteryMonitorTests
swift test
```

Run the app:

```bash
swift run StatusTrio
```

Expected: the battery arc tracks the current battery value; plugging and unplugging power changes the subtitle and color behavior within one second.

- [ ] **Step 5: Commit battery monitoring**

```bash
git add Sources/StatusTrioCore/Monitoring/BatteryMonitor.swift Tests/StatusTrioCoreTests/BatteryMonitorTests.swift
git commit -m "feat: monitor battery state"
```

---

### Task 10: Implement Wi-Fi monitoring and best-effort classification

**Files:**
- Create: `Sources/StatusTrioCore/Monitoring/WiFiMonitor.swift`
- Create: `Tests/StatusTrioCoreTests/WiFiClassifierTests.swift`

- [ ] **Step 1: Write failing classifier tests**

Create `Tests/StatusTrioCoreTests/WiFiClassifierTests.swift`:

```swift
import XCTest
@testable import StatusTrioCore

final class WiFiClassifierTests: XCTestCase {
    func testOffAndNotAssociatedWin() {
        XCTAssertEqual(
            WiFiClassifier.classify(.init(powerOn: false, serviceActive: false, mode: .none, pathSatisfied: false, pathUsesWiFi: false, pathExpensive: false, sharingActive: false, rssi: 0)),
            .off
        )
        XCTAssertEqual(
            WiFiClassifier.classify(.init(powerOn: true, serviceActive: false, mode: .none, pathSatisfied: false, pathUsesWiFi: false, pathExpensive: false, sharingActive: false, rssi: 0)),
            .notAssociated
        )
    }

    func testSpecialStates() {
        XCTAssertEqual(
            WiFiClassifier.classify(.init(powerOn: true, serviceActive: true, mode: .station, pathSatisfied: true, pathUsesWiFi: true, pathExpensive: false, sharingActive: true, rssi: -50)),
            .shared
        )
        XCTAssertEqual(
            WiFiClassifier.classify(.init(powerOn: true, serviceActive: true, mode: .ibss, pathSatisfied: true, pathUsesWiFi: true, pathExpensive: false, sharingActive: false, rssi: -50)),
            .temporary
        )
        XCTAssertEqual(
            WiFiClassifier.classify(.init(powerOn: true, serviceActive: true, mode: .station, pathSatisfied: true, pathUsesWiFi: true, pathExpensive: true, sharingActive: false, rssi: -50)),
            .hotspot
        )
    }

    func testNoInternetAndConnected() {
        XCTAssertEqual(
            WiFiClassifier.classify(.init(powerOn: true, serviceActive: true, mode: .station, pathSatisfied: false, pathUsesWiFi: true, pathExpensive: false, sharingActive: false, rssi: -50)),
            .noInternet
        )
        XCTAssertEqual(
            WiFiClassifier.classify(.init(powerOn: true, serviceActive: true, mode: .station, pathSatisfied: true, pathUsesWiFi: true, pathExpensive: false, sharingActive: false, rssi: -50)),
            .connected
        )
    }
}
```

- [ ] **Step 2: Run the classifier test to verify it fails**

Run:

```bash
swift test --filter WiFiClassifierTests
```

Expected: compilation fails because `WiFiClassifier` and its input type do not exist.

- [ ] **Step 3: Implement the pure classifier**

Create `Sources/StatusTrioCore/Monitoring/WiFiMonitor.swift` and begin with:

```swift
import CoreWLAN
import Foundation
import Network
import SystemConfiguration

struct WiFiClassificationInput: Equatable {
    var powerOn: Bool
    var serviceActive: Bool
    var mode: CWInterfaceMode
    var pathSatisfied: Bool
    var pathUsesWiFi: Bool
    var pathExpensive: Bool
    var sharingActive: Bool
    var rssi: Int
}

enum WiFiClassifier {
    static func classify(_ input: WiFiClassificationInput) -> WiFiState {
        if !input.powerOn { return .off }
        if !input.serviceActive { return .notAssociated }
        if input.sharingActive { return .shared }
        if input.mode == .ibss { return .temporary }
        if input.pathUsesWiFi && input.pathExpensive { return .hotspot }
        if !input.pathSatisfied { return .noInternet }
        return .connected
    }
}
```

- [ ] **Step 4: Implement the live monitor**

Append to `WiFiMonitor.swift`:

```swift
@MainActor
final class WiFiMonitor: NSObject, WiFiMonitoring, CWEventDelegate {
    let updates: AsyncStream<WiFiStatus>
    private let continuation: AsyncStream<WiFiStatus>.Continuation
    private let client = CWWiFiClient.shared()
    private let pathMonitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: "StatusTrio.WiFiPath")
    private var latestPath = PathSnapshot()
    private var lastValidStatus: WiFiStatus?
    private var lastValidDate: Date?
    private let staleInterval: TimeInterval
    private let now: () -> Date

    init(staleInterval: TimeInterval = 30, now: @escaping () -> Date = Date.init) {
        self.staleInterval = staleInterval
        self.now = now
        (updates, continuation) = AsyncStream.makeStream()
        super.init()
    }

    func start() {
        client.delegate = self
        for event: CWEventType in [.powerDidChange, .linkDidChange, .linkQualityDidChange, .modeDidChange] {
            try? client.startMonitoringEvent(with: event)
        }

        pathMonitor.pathUpdateHandler = { [weak self] path in
            let snapshot = PathSnapshot(
                satisfied: path.status == .satisfied,
                usesWiFi: path.usesInterfaceType(.wifi),
                expensive: path.isExpensive
            )
            Task { @MainActor in
                self?.latestPath = snapshot
                self?.refresh()
            }
        }
        pathMonitor.start(queue: pathQueue)
        refresh()
    }

    func stop() {
        client.delegate = nil
        try? client.stopMonitoringAllEvents()
        pathMonitor.cancel()
        continuation.finish()
    }

    func refresh() {
        guard let interface = client.interface() else {
            publish(.unavailable, rssi: nil)
            return
        }

        let sharing = SystemInternetSharingDetector.isActive()
        let input = WiFiClassificationInput(
            powerOn: interface.powerOn(),
            serviceActive: interface.serviceActive(),
            mode: interface.interfaceMode(),
            pathSatisfied: latestPath.satisfied,
            pathUsesWiFi: latestPath.usesWiFi,
            pathExpensive: latestPath.expensive,
            sharingActive: sharing,
            rssi: interface.rssiValue()
        )
        let state = WiFiClassifier.classify(input)
        guard state != .unavailable else {
            publish(.unavailable, rssi: nil)
            return
        }
        publish(state, rssi: interface.rssiValue())
    }

    nonisolated func powerStateDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor [weak self] in self?.refresh() }
    }

    nonisolated func linkDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor [weak self] in self?.refresh() }
    }

    nonisolated func modeDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor [weak self] in self?.refresh() }
    }

    nonisolated func linkQualityDidChangeForWiFiInterface(
        withName interfaceName: String,
        rssi: Int,
        transmitRate: Double
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.lastValidStatus?.state == .connected {
                self.publish(.connected, rssi: rssi)
            } else {
                self.refresh()
            }
        }
    }

    private func publish(_ state: WiFiState, rssi: Int?) {
        let candidate = WiFiStatus(state: state, rssi: rssi)
        if state == .unavailable, let lastValidStatus, let lastValidDate {
            if now().timeIntervalSince(lastValidDate) <= staleInterval {
                continuation.yield(lastValidStatus)
                return
            }
        }

        if state != .unavailable {
            lastValidStatus = candidate
            lastValidDate = now()
        }
        continuation.yield(candidate)
    }
}

private struct PathSnapshot {
    var satisfied = false
    var usesWiFi = false
    var expensive = false
}

enum SystemInternetSharingDetector {
    static func isActive() -> Bool {
        guard let store = SCDynamicStoreCreate(nil, "StatusTrio" as CFString, nil, nil),
              let value = SCDynamicStoreCopyValue(store, "com.apple.nat" as CFString) as? [String: Any],
              let nat = value["NAT"] as? [String: Any]
        else { return false }
        return (nat["Enabled"] as? Int) == 1
    }
}
```

If the Swift import names differ, inspect the generated Swift interface with:

```bash
swiftc -print-target-info
rg -n "startMonitoringEvent|linkQualityDidChange" "$(xcrun --show-sdk-path)/System/Library/Frameworks/CoreWLAN.framework/Headers"
```

Then adjust only the Objective-C selector spelling; the classifier and state model remain unchanged.

- [ ] **Step 5: Run tests, smoke test, and commit**

Run:

```bash
swift test --filter WiFiClassifierTests
swift test
swift run StatusTrio
```

Expected: turning Wi-Fi off, disconnecting from a network, and changing signal strength update the icon within one second. Unsupported special states fall back to connected or not-associated.

```bash
git add Sources/StatusTrioCore/Monitoring/WiFiMonitor.swift Tests/StatusTrioCoreTests/WiFiClassifierTests.swift
git commit -m "feat: monitor Wi-Fi state"
```

---

### Task 11: Implement volume monitoring

**Files:**
- Create: `Sources/StatusTrioCore/Monitoring/VolumeMonitor.swift`
- Create: `Tests/StatusTrioCoreTests/VolumeMonitorTests.swift`

- [ ] **Step 1: Write failing volume monitor tests**

Create `Tests/StatusTrioCoreTests/VolumeMonitorTests.swift`:

```swift
import XCTest
@testable import StatusTrioCore

@MainActor
final class VolumeMonitorTests: XCTestCase {
    func testMonitorPublishesReaderOutput() async {
        let reader = FakeVolumeReader(
            result: VolumeReading(scalar: 0.42, isMuted: false, deviceName: "Studio Display")
        )
        let monitor = VolumeMonitor(reader: reader)

        monitor.refresh()
        var iterator = monitor.updates.makeAsyncIterator()
        let value = await iterator.next()

        XCTAssertEqual(value?.scalar, 0.42)
        XCTAssertEqual(value?.deviceName, "Studio Display")
    }

    func testMissingDevice() async {
        let monitor = VolumeMonitor(reader: FakeVolumeReader(result: nil))
        monitor.refresh()
        var iterator = monitor.updates.makeAsyncIterator()
        let value = await iterator.next()

        XCTAssertNil(value?.scalar)
        XCTAssertNil(value?.deviceName)
    }
}

private final class FakeVolumeReader: VolumeReading {
    let result: VolumeReading?

    init(result: VolumeReading?) {
        self.result = result
    }

    func read() -> VolumeReading? {
        result
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
swift test --filter VolumeMonitorTests
```

Expected: compilation fails because `VolumeReading` and `VolumeMonitor` do not exist.

- [ ] **Step 3: Implement the CoreAudio reader**

Create `Sources/StatusTrioCore/Monitoring/VolumeMonitor.swift` with:

```swift
import CoreAudio
import Foundation

struct VolumeReading: Equatable {
    var scalar: Double
    var isMuted: Bool
    var deviceName: String
}

protocol VolumeReading: AnyObject {
    func read() -> VolumeReading?
}

final class CoreAudioVolumeReader: VolumeReading {
    func read() -> VolumeReading? {
        guard let deviceID = defaultOutputDevice() else { return nil }
        guard let scalar = readVolumeScalar(deviceID: deviceID) else { return nil }
        let muted = readMute(deviceID: deviceID) ?? false
        let name = readDeviceName(deviceID: deviceID) ?? "默认输出设备"
        return VolumeReading(scalar: scalar, isMuted: muted, deviceName: name)
    }

    private func defaultOutputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        return status == noErr && deviceID != 0 ? deviceID : nil
    }

    private func readVolumeScalar(deviceID: AudioDeviceID) -> Double? {
        for element in [kAudioObjectPropertyElementMain, 1, 2] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: AudioObjectPropertyElement(element)
            )
            var value = Float(0)
            var size = UInt32(MemoryLayout<Float>.size)
            if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr {
                return Double(value)
            }
        }
        return nil
    }

    private func readMute(deviceID: AudioDeviceID) -> Bool? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr
            ? value != 0
            : nil
    }

    private func readDeviceName(deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }
        return status == noErr ? value as String? : nil
    }
}
```

- [ ] **Step 4: Implement the monitor and wire CoreAudio listeners**

Change `CoreAudioVolumeReader.defaultOutputDevice()` from `private` to internal so the monitor can attach listeners to the active device:

```swift
    func defaultOutputDevice() -> AudioDeviceID? {
```

Append to `VolumeMonitor.swift`:

```swift
struct AudioPropertyListenerRegistration {
    let objectID: AudioDeviceID
    var address: AudioObjectPropertyAddress
    let block: AudioObjectPropertyListenerBlock
}

@MainActor
final class VolumeMonitor: VolumeMonitoring {
    let updates: AsyncStream<VolumeStatus>
    private let continuation: AsyncStream<VolumeStatus>.Continuation
    private let reader: any VolumeReading
    private let listenerReader = CoreAudioVolumeReader()
    private var defaultDeviceRegistration: AudioPropertyListenerRegistration?
    private var currentDeviceRegistrations: [AudioPropertyListenerRegistration] = []

    init(reader: any VolumeReading = CoreAudioVolumeReader()) {
        self.reader = reader
        (updates, continuation) = AsyncStream.makeStream()
    }

    func start() {
        installDefaultDeviceListener()
        installCurrentDeviceListeners()
        refresh()
    }

    func stop() {
        removeCurrentDeviceListeners()
        removeDefaultDeviceListener()
        continuation.finish()
    }

    func refresh() {
        if let reading = reader.read() {
            continuation.yield(VolumeStatus(
                scalar: reading.scalar,
                isMuted: reading.isMuted,
                deviceName: reading.deviceName
            ))
        } else {
            continuation.yield(VolumeStatus(scalar: nil, isMuted: false, deviceName: nil))
        }
    }

    private func installDefaultDeviceListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                self?.removeCurrentDeviceListeners()
                self?.installCurrentDeviceListeners()
                self?.refresh()
            }
        }
        let objectID = AudioObjectID(kAudioObjectSystemObject)
        AudioObjectAddPropertyListenerBlock(objectID, &address, DispatchQueue.main, block)
        defaultDeviceRegistration = AudioPropertyListenerRegistration(
            objectID: objectID,
            address: address,
            block: block
        )
    }

    private func removeDefaultDeviceListener() {
        guard var registration = defaultDeviceRegistration else { return }
        AudioObjectRemovePropertyListenerBlock(
            registration.objectID,
            &registration.address,
            DispatchQueue.main,
            registration.block
        )
        defaultDeviceRegistration = nil
    }

    private func installCurrentDeviceListeners() {
        guard let deviceID = listenerReader.defaultOutputDevice() else { return }
        for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor in self?.refresh() }
            }
            AudioObjectAddPropertyListenerBlock(deviceID, &address, DispatchQueue.main, block)
            currentDeviceRegistrations.append(AudioPropertyListenerRegistration(
                objectID: deviceID,
                address: address,
                block: block
            ))
        }
    }

    private func removeCurrentDeviceListeners() {
        for var registration in currentDeviceRegistrations {
            AudioObjectRemovePropertyListenerBlock(
                registration.objectID,
                &registration.address,
                DispatchQueue.main,
                registration.block
            )
        }
        currentDeviceRegistrations.removeAll()
    }
}
```

- [ ] **Step 5: Run tests, smoke test, and commit**

Run:

```bash
swift test --filter VolumeMonitorTests
swift test
swift run StatusTrio
```

Expected: changing system volume updates the four dots and popover value within one second. Muting shows zero bars and “静音”. Switching output devices updates the device name.

```bash
git add Sources/StatusTrioCore/Monitoring/VolumeMonitor.swift Tests/StatusTrioCoreTests/VolumeMonitorTests.swift
git commit -m "feat: monitor system volume"
```

---

### Task 12: Replace placeholder monitors with the live environment

**Files:**
- Create: `Sources/StatusTrioCore/App/AppEnvironment.swift`
- Modify: `Sources/StatusTrioCore/App/AppDelegate.swift`
- Modify: `Sources/StatusTrioCore/Monitoring/MonitorProtocols.swift`
- Modify: `Tests/StatusTrioCoreTests/SystemStatusStoreTests.swift`

- [ ] **Step 1: Write a failing environment test**

Append to `SystemStatusStoreTests`:

```swift
    func testEnvironmentStoreUsesInjectedMonitors() async {
        let battery = FakeBatteryMonitor()
        let store = AppEnvironment.makeStore(
            batteryMonitor: battery,
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: FakeVolumeMonitor()
        )

        store.start()
        battery.send(BatteryStatus(
            rawPercentage: 55,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: false
        ))
        await Task.yield()

        XCTAssertEqual(store.snapshot.battery.percentage, 55)
        store.stop()
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
swift test --filter SystemStatusStoreTests/testEnvironmentStoreUsesInjectedMonitors
```

Expected: compilation fails because `AppEnvironment` does not exist.

- [ ] **Step 3: Implement `AppEnvironment`**

Create `Sources/StatusTrioCore/App/AppEnvironment.swift`:

```swift
import AppKit

@MainActor
final class AppEnvironment {
    let store: SystemStatusStore
    let statusBarController: StatusBarController

    init(
        store: SystemStatusStore,
        statusBarController: StatusBarController
    ) {
        self.store = store
        self.statusBarController = statusBarController
    }

    static func makeStore(
        batteryMonitor: any BatteryMonitoring,
        wifiMonitor: any WiFiMonitoring,
        volumeMonitor: any VolumeMonitoring
    ) -> SystemStatusStore {
        SystemStatusStore(
            batteryMonitor: batteryMonitor,
            wifiMonitor: wifiMonitor,
            volumeMonitor: volumeMonitor
        )
    }

    static func live() -> AppEnvironment {
        let store = makeStore(
            batteryMonitor: BatteryMonitor(),
            wifiMonitor: WiFiMonitor(),
            volumeMonitor: VolumeMonitor()
        )
        let controller = StatusBarController(store: store) {
            NSApplication.shared.terminate(nil)
        }
        return AppEnvironment(store: store, statusBarController: controller)
    }
}
```

- [ ] **Step 4: Simplify `AppDelegate` and remove temporary unavailable monitors**

Replace `applicationDidFinishLaunching` in `AppDelegate` with:

```swift
    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let environment = AppEnvironment.live()
        self.environment = environment
        environment.store.start()
    }
```

Replace the stored properties with:

```swift
    private var environment: AppEnvironment?
```

Replace `applicationWillTerminate` with:

```swift
    public func applicationWillTerminate(_ notification: Notification) {
        environment?.store.stop()
    }
```

Delete `UnavailableBatteryMonitor`, `UnavailableWiFiMonitor`, and `UnavailableVolumeMonitor` from `MonitorProtocols.swift`.

- [ ] **Step 5: Run the full suite, smoke test all live states, and commit**

Run:

```bash
swift test
swift run StatusTrio
```

Expected: the real battery, Wi-Fi, and volume values appear. Test charging, Wi-Fi off/connected/no-internet, volume changes, mute, and output-device switching.

```bash
git add Sources/StatusTrioCore/App Sources/StatusTrioCore/Monitoring/MonitorProtocols.swift Tests/StatusTrioCoreTests/SystemStatusStoreTests.swift
git commit -m "feat: wire live system monitors"
```

---

### Task 13: Harden refresh, wake recovery, and monitor failures

**Files:**
- Modify: `Sources/StatusTrioCore/Store/SystemStatusStore.swift`
- Modify: `Sources/StatusTrioCore/Monitoring/BatteryMonitor.swift`
- Modify: `Sources/StatusTrioCore/Monitoring/WiFiMonitor.swift`
- Modify: `Sources/StatusTrioCore/Monitoring/VolumeMonitor.swift`
- Modify: `Tests/StatusTrioCoreTests/SystemStatusStoreTests.swift`

- [ ] **Step 1: Write failing recovery tests**

Add `import AppKit` to `SystemStatusStoreTests.swift`, then append:

```swift
    func testFailingMonitorDoesNotBlockOtherUpdates() async {
        let battery = FakeBatteryMonitor()
        let wifi = FailingWiFiMonitor()
        let volume = FakeVolumeMonitor()
        let store = SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: wifi,
            volumeMonitor: volume,
            refreshInterval: .seconds(60)
        )

        store.start()
        battery.send(.placeholder)
        volume.send(VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Speaker"))
        await Task.yield()

        XCTAssertEqual(store.snapshot.battery.percentage, 100)
        XCTAssertEqual(store.snapshot.volume.scalar, 0.5)
        store.stop()
    }

    func testWakeNotificationTriggersRefresh() async {
        let battery = CountingBatteryMonitor()
        let store = SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: FakeWiFiMonitor(),
            volumeMonitor: FakeVolumeMonitor(),
            refreshInterval: .seconds(60)
        )

        store.start()
        NotificationCenter.default.post(name: NSWorkspace.didWakeNotification, object: nil)
        await Task.yield()

        XCTAssertEqual(battery.refreshCount, 2)
        store.stop()
    }
```

Add these fakes at the bottom of `SystemStatusStoreTests.swift`:

```swift
@MainActor
private final class FailingWiFiMonitor: WiFiMonitoring {
    let updates: AsyncStream<WiFiStatus>
    private let continuation: AsyncStream<WiFiStatus>.Continuation

    init() { (updates, continuation) = AsyncStream.makeStream() }
    func start() { continuation.yield(.placeholder) }
    func stop() { continuation.finish() }
    func refresh() {}
}

@MainActor
private final class CountingBatteryMonitor: BatteryMonitoring {
    let updates: AsyncStream<BatteryStatus>
    private let continuation: AsyncStream<BatteryStatus>.Continuation
    private(set) var refreshCount = 0

    init() { (updates, continuation) = AsyncStream.makeStream() }
    func start() { refresh() }
    func stop() { continuation.finish() }
    func refresh() {
        refreshCount += 1
        continuation.yield(.placeholder)
    }
}
```

- [ ] **Step 2: Run the recovery tests to verify they fail**

Run:

```bash
swift test --filter SystemStatusStoreTests
```

Expected: `testWakeNotificationTriggersRefresh` fails because the store does not observe wake notifications.

- [ ] **Step 3: Observe wake notifications in the store**

Add to `SystemStatusStore`:

```swift
    private var wakeObserver: NSObjectProtocol?
```

In `start()`, add:

```swift
        wakeObserver = NotificationCenter.default.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshAll() }
        }
```

In `stop()`, add:

```swift
        if let wakeObserver {
            NotificationCenter.default.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
```

Import AppKit in `SystemStatusStore.swift`.

- [ ] **Step 4: Rebuild Wi-Fi monitoring without finishing its stream**

Keep the stream alive across CoreWLAN interruptions. Change `WiFiMonitor.pathMonitor` from a `let` to:

```swift
    private var pathMonitor = NWPathMonitor()
```

Extract event registration into `startCoreWLANMonitoring()`, extract path registration into `startPathMonitoring()`, and keep `stop()` as the final teardown that finishes the stream. Add transient recovery:

```swift
    nonisolated func clientConnectionInterrupted() {
        Task { @MainActor [weak self] in self?.restartMonitoring() }
    }

    nonisolated func clientConnectionInvalidated() {
        Task { @MainActor [weak self] in self?.restartMonitoring() }
    }

    private func restartMonitoring() {
        try? client.stopMonitoringAllEvents()
        pathMonitor.cancel()
        pathMonitor = NWPathMonitor()
        startCoreWLANMonitoring()
        startPathMonitoring()
        refresh()
    }
```

In `BatteryMonitor`, add the module logger:

```swift
import OSLog

private let logger = Logger(subsystem: "com.lingsmbp.StatusTrio", category: "battery")
```

When `IOPSNotificationCreateRunLoopSource` returns `nil`, log without disabling the store fallback:

```swift
        } else {
            logger.error("IOPS notification source unavailable; fallback refresh remains active")
        }
```

- [ ] **Step 5: Run tests, sleep/wake smoke test, and commit**

Run:

```bash
swift test
swift run StatusTrio
```

Expected: wake from sleep triggers a refresh; if one monitor returns an error, the other two values remain live.

```bash
git add Sources/StatusTrioCore/Store/SystemStatusStore.swift Sources/StatusTrioCore/Monitoring Tests/StatusTrioCoreTests/SystemStatusStoreTests.swift
git commit -m "fix: recover monitors after failures and wake"
```

---

### Task 14: Package the app, update README, and verify the bundle

**Files:**
- Create: `Support/Info.plist`
- Create: `scripts/build-app.sh`
- Modify: `README.md`
- Modify: `.gitignore`

- [ ] **Step 1: Add the app bundle metadata**

Create `Support/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>Status Trio</string>
    <key>CFBundleExecutable</key>
    <string>StatusTrio</string>
    <key>CFBundleIdentifier</key>
    <string>com.lingsmbp.StatusTrio</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Status Trio</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 2: Add the app bundle build script**

Create `scripts/build-app.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-release}"
OPEN_APP="${2:-open}"

cd "$ROOT"

swift build -c "$CONFIGURATION"
BIN_PATH="$(swift build -c "$CONFIGURATION" --show-bin-path)"
APP_DIR="$ROOT/dist/StatusTrio.app"
CONTENTS="$APP_DIR/Contents"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BIN_PATH/StatusTrio" "$CONTENTS/MacOS/StatusTrio"
cp "$ROOT/Support/Info.plist" "$CONTENTS/Info.plist"

chmod +x "$CONTENTS/MacOS/StatusTrio"
codesign --force --sign - "$APP_DIR"

echo "Built $APP_DIR"
if [[ "$OPEN_APP" == "open" ]]; then
    open "$APP_DIR"
fi
```

Run:

```bash
chmod +x scripts/build-app.sh
bash scripts/build-app.sh release no-open
```

Expected: `dist/StatusTrio.app` is created and code-signing succeeds.

- [ ] **Step 3: Update `.gitignore` for generated output**

Ensure `.gitignore` contains:

```gitignore
.DS_Store
.superpowers/
DerivedData/
dist/
*.xcuserstate
xcuserdata/
```

- [ ] **Step 4: Update README with run and build instructions**

Append to `README.md`:

````markdown
## Development

```bash
swift test
swift run StatusTrio
```

## Build a local app bundle

```bash
bash scripts/build-app.sh release
```

The generated app is placed in `dist/StatusTrio.app`.
````

- [ ] **Step 5: Verify a Finder launch and commit**

Run:

```bash
bash scripts/build-app.sh release
open dist/StatusTrio.app
```

Expected: no Dock icon appears, only the Status Trio menu bar item. Quit from the right-click menu, then commit:

```bash
git add .gitignore README.md Support/Info.plist scripts/build-app.sh
git commit -m "build: package Status Trio app bundle"
```

---

### Task 15: Final acceptance verification

**Files:**
- Modify: `README.md` only if a verified limitation needs documenting.

- [ ] **Step 1: Run the complete automated suite**

```bash
swift test
swift build -c release
```

Expected: all tests pass and the release build succeeds.

- [ ] **Step 2: Run the manual acceptance matrix**

Verify each row and record failures in a temporary issue or local note:

| Area | Check | Expected |
| --- | --- | --- |
| Launch | Open `dist/StatusTrio.app` | Menu bar icon appears, no Dock icon |
| Appearance | Switch macOS light/dark appearance | Icon remains legible and follows foreground color |
| Battery | Change charge level | Arc changes within 1 second |
| Battery | Connect or disconnect power | Green charging state and subtitle update |
| Low Power | Toggle Low Power Mode | Battery fill becomes yellow |
| No battery | Run on a Mac without a battery | Arc is full and popover says 无电池设备 |
| Wi-Fi | Turn Wi-Fi off | Slashed Wi-Fi state appears |
| Wi-Fi | Disconnect from a network | Muted full Wi-Fi state appears |
| Wi-Fi | Move through weak/strong signal | 0–3 bars update within 1 second |
| Wi-Fi | Disconnect upstream internet | No-internet overlay appears |
| Volume | Change system volume | Four dots and popover value update |
| Volume | Mute or unmute | Zero bars and 静音 state update |
| Audio | Switch output device | Popover subtitle updates |
| Popover | Left-click status item | Anchored popover opens below icon |
| Popover | Click outside or press Esc | Popover closes |
| Menu | Right-click or Control-click | Version, disabled settings, quit items appear |
| Quit | Select quit | App exits and menu bar icon disappears |
| Wake | Sleep and wake the Mac | Status refreshes without restart |

- [ ] **Step 3: Check repository state and publish the final commit**

```bash
git status --short --branch
git log --oneline --decorate -10
git push
```

Expected: `main` tracks `origin/main`, the working tree has no modified tracked files, and the GitHub repository contains the complete implementation.

- [ ] **Step 4: Verify GitHub metadata**

Run:

```bash
gh repo view lingyired/status-trio --json url,visibility,description,repositoryTopics
```

Expected: public repository, three-in-one description, and the macOS menu bar topics remain present.

---

## Risks and Mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| CoreWLAN selector/import spelling differs in Swift | Build failure | Compile in Task 10, inspect generated interface, and adjust only selector spelling |
| CoreAudio listener removal does not match block identity | Stale callbacks after device switch | Store each listener registration and remove using the same captured block |
| RSSI thresholds differ from Apple's menu bar | Visual mismatch | Keep thresholds in `StatusMappings` behind boundary tests so they are easy to tune |
| Temperamental hotspot/sharing detection | Wrong special icon | Prefer ordinary connected state whenever confidence is low |
| SwiftPM executable appears as a CLI process | Finder behavior differs from a real bundle | Use `scripts/build-app.sh` with `LSUIElement` for final verification |
| AppKit popover edge is inverted | Popover appears above the status item | Verify Task 8 manually and switch `preferredEdge` between `.minY` and `.maxY` without changing other code |

## Open Questions

None. All product decisions are fixed in the design specification; implementation uncertainties are limited to API spelling and are covered by compile-time checks and focused tests.
