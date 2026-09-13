# Popup Battery Details Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show battery percentage, charged/charging state, estimated time to full, and a Battery Settings shortcut in the popup.

**Architecture:** Extend the existing IOPS battery reading and `BatteryStatus` value model with charged state and time-to-full metadata. Keep formatting in `StatusPresentation`, render a focused SwiftUI battery row, and let `StatusBarController` own the system settings URL fallback.

**Tech Stack:** Swift 6, SwiftUI, AppKit, IOKit/IOPS, XCTest, Swift Package Manager

---

## File Structure

| Path | Responsibility |
| --- | --- |
| `Sources/StatusTrioCore/Monitoring/BatteryMonitor.swift` | Parse IOPS charged state and time-to-full; emit enriched battery status |
| `Sources/StatusTrioCore/Models/StatusSnapshot.swift` | Store stable battery presentation data |
| `Sources/StatusTrioCore/UI/StatusPopoverView.swift` | Format battery title and subtitle; assemble popup |
| `Sources/StatusTrioCore/UI/BatteryStatusView.swift` | Render battery row and settings button |
| `Sources/StatusTrioCore/UI/StatusBarController.swift` | Wire battery settings action and URL fallbacks |
| `Tests/StatusTrioCoreTests/BatteryMonitorTests.swift` | Verify IOPS parsing and monitor normalization |
| `Tests/StatusTrioCoreTests/StatusSnapshotTests.swift` | Verify model defaults |
| `Tests/StatusTrioCoreTests/StatusPresentationTests.swift` | Verify title/status/time formatting |
| `Tests/StatusTrioCoreTests/StatusMenuBuilderTests.swift` | Verify Battery Settings URL fallback order |
| `README.md` | Document the new popup battery detail |

### Task 1: Read charged state and time-to-full

**Files:**
- Modify: `Sources/StatusTrioCore/Monitoring/BatteryMonitor.swift`
- Test: `Tests/StatusTrioCoreTests/BatteryMonitorTests.swift`

- [ ] **Step 1: Write failing parser and monitor tests**

Add these tests to `BatteryMonitorTests` after `testParserConvertsValidInternalBatteryDescription`:

```swift
func testParserReadsChargedStateAndTimeToFullCharge() {
    let description: [String: Any] = [
        kIOPSTypeKey: kIOPSInternalBatteryType,
        kIOPSCurrentCapacityKey: 68,
        kIOPSMaxCapacityKey: 100,
        kIOPSIsChargingKey: true,
        kIOPSIsChargedKey: false,
        kIOPSTimeToFullChargeKey: 85,
        kIOPSPowerSourceStateKey: kIOPSACPowerValue,
        kIOPSIsPresentKey: true
    ]

    XCTAssertEqual(
        IOPSBatteryReader.parse(description),
        BatteryReading(
            currentCapacity: 68,
            maxCapacity: 100,
            isCharging: true,
            isCharged: false,
            timeToFullChargeMinutes: 85,
            isConnectedToPower: true,
            isPresent: true
        )
    )
}

func testParserTreatsMissingAndNonPositiveTimeToFullAsUnknown() {
    for time in [nil, 0, -1] as [Int?] {
        var description: [String: Any] = [
            kIOPSTypeKey: kIOPSInternalBatteryType,
            kIOPSCurrentCapacityKey: 68,
            kIOPSMaxCapacityKey: 100,
            kIOPSIsChargingKey: true,
            kIOPSIsChargedKey: false,
            kIOPSPowerSourceStateKey: kIOPSACPowerValue,
            kIOPSIsPresentKey: true
        ]
        description[kIOPSTimeToFullChargeKey] = time

        XCTAssertNil(IOPSBatteryReader.parse(description)?.timeToFullChargeMinutes)
    }
}

func testMonitorOnlyEmitsTimeWhileCharging() async {
    let reader = FakeBatteryReader(result: BatteryReading(
        currentCapacity: 68,
        maxCapacity: 100,
        isCharging: false,
        isCharged: true,
        timeToFullChargeMinutes: 85,
        isConnectedToPower: true,
        isPresent: true
    ))
    let monitor = BatteryMonitor(
        reader: reader,
        lowPowerModeProvider: { false }
    )

    monitor.refresh()
    var iterator = monitor.updates.makeAsyncIterator()
    let value = await iterator.next()

    XCTAssertTrue(value?.isCharged == true)
    XCTAssertNil(value?.timeToFullChargeMinutes)
    monitor.stop()
}
```

- [ ] **Step 2: Run the focused tests and verify failure**

Run:

```bash
bash scripts/test.sh BatteryMonitorTests
```

Expected: compilation fails because `BatteryReading` and `BatteryStatus` do not yet define `isCharged` or `timeToFullChargeMinutes`.

- [ ] **Step 3: Add fields and parsing**

Change `BatteryReading` in `BatteryMonitor.swift` to:

```swift
struct BatteryReading: Equatable {
    var currentCapacity: Int
    var maxCapacity: Int
    var isCharging: Bool
    var isCharged: Bool = false
    var timeToFullChargeMinutes: Int? = nil
    var isConnectedToPower: Bool
    var isPresent: Bool
}
```

In `IOPSBatteryReader.parse`, capture normalized time before constructing the result:

```swift
let rawTimeToFullCharge = integerValue(description[kIOPSTimeToFullChargeKey])
let timeToFullCharge = rawTimeToFullCharge.flatMap { $0 > 0 ? $0 : nil }

return BatteryReading(
    currentCapacity: current,
    maxCapacity: maximum,
    isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
    isCharged: description[kIOPSIsChargedKey] as? Bool ?? false,
    timeToFullChargeMinutes: timeToFullCharge,
    isConnectedToPower: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
    isPresent: description[kIOPSIsPresentKey] as? Bool ?? true
)
```

- [ ] **Step 4: Extend `BatteryStatus` and emit the new fields**

Add `isCharged` and `timeToFullChargeMinutes` to `BatteryStatus` in `StatusSnapshot.swift` with an explicit initializer whose defaults preserve existing call sites:

```swift
struct BatteryStatus: Equatable, Sendable {
    let rawPercentage: Int?
    let isPresent: Bool
    let isCharging: Bool
    let isCharged: Bool
    let timeToFullChargeMinutes: Int?
    let isLowPowerMode: Bool
    let isConnectedToPower: Bool

    init(
        rawPercentage: Int?,
        isPresent: Bool,
        isCharging: Bool,
        isCharged: Bool = false,
        timeToFullChargeMinutes: Int? = nil,
        isLowPowerMode: Bool,
        isConnectedToPower: Bool
    ) {
        self.rawPercentage = rawPercentage
        self.isPresent = isPresent
        self.isCharging = isCharging
        self.isCharged = isCharged
        self.timeToFullChargeMinutes = timeToFullChargeMinutes
        self.isLowPowerMode = isLowPowerMode
        self.isConnectedToPower = isConnectedToPower
    }
```

In `BatteryMonitor.refresh()`, pass charged state directly and only retain time while charging:

```swift
status = BatteryStatus(
    rawPercentage: percentage,
    isPresent: true,
    isCharging: reading.isCharging,
    isCharged: reading.isCharged,
    timeToFullChargeMinutes: reading.isCharging
        ? reading.timeToFullChargeMinutes
        : nil,
    isLowPowerMode: lowPowerModeProvider(),
    isConnectedToPower: reading.isConnectedToPower
)
```

For the missing/non-present branches, pass `isCharged: false` and `timeToFullChargeMinutes: nil`.

- [ ] **Step 5: Run the focused tests**

Run:

```bash
bash scripts/test.sh BatteryMonitorTests
```

Expected: all `BatteryMonitorTests` pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/StatusTrioCore/Monitoring/BatteryMonitor.swift \
  Sources/StatusTrioCore/Models/StatusSnapshot.swift \
  Tests/StatusTrioCoreTests/BatteryMonitorTests.swift
git commit -m "feat: read battery charged state and time to full"
```

### Task 2: Format battery title and status

**Files:**
- Modify: `Sources/StatusTrioCore/UI/StatusPopoverView.swift`
- Modify: `Tests/StatusTrioCoreTests/StatusPresentationTests.swift`
- Modify: `Tests/StatusTrioCoreTests/StatusSnapshotTests.swift`

- [ ] **Step 1: Write failing presentation tests**

Replace `testBatterySubtitlePriority` with:

```swift
func testBatteryTitleAndSubtitlePriority() {
    XCTAssertEqual(StatusPresentation.batteryTitle(makeBattery(percentage: 68)), "电池 · 68%")
    XCTAssertEqual(
        StatusPresentation.batterySubtitle(
            makeBattery(
                isPresent: false,
                isCharging: true,
                isCharged: true,
                isLowPowerMode: true,
                isConnectedToPower: true
            )
        ),
        "无电池设备"
    )
    XCTAssertEqual(
        StatusPresentation.batterySubtitle(
            makeBattery(
                isCharging: true,
                isCharged: true,
                isLowPowerMode: true,
                isConnectedToPower: true
            )
        ),
        "已充满"
    )
    XCTAssertEqual(
        StatusPresentation.batterySubtitle(
            makeBattery(
                isCharging: true,
                isLowPowerMode: true,
                isConnectedToPower: true,
                timeToFullChargeMinutes: 85
            )
        ),
        "预计 1 小时 25 分钟充满"
    )
    XCTAssertEqual(
        StatusPresentation.batterySubtitle(
            makeBattery(isCharging: true, isConnectedToPower: true)
        ),
        "正在计算充满时间"
    )
    XCTAssertEqual(
        StatusPresentation.batterySubtitle(
            makeBattery(isLowPowerMode: true, isConnectedToPower: true)
        ),
        "低电量模式"
    )
    XCTAssertEqual(
        StatusPresentation.batterySubtitle(makeBattery(isConnectedToPower: true)),
        "已连接电源"
    )
    XCTAssertEqual(StatusPresentation.batterySubtitle(makeBattery()), "电池供电")
}

func testBatteryTimeToFullFormatting() {
    let cases: [(Int?, String)] = [
        (1, "预计 1 分钟充满"),
        (59, "预计 59 分钟充满"),
        (60, "预计 1 小时充满"),
        (85, "预计 1 小时 25 分钟充满"),
        (120, "预计 2 小时充满"),
        (nil, "正在计算充满时间"),
        (0, "正在计算充满时间"),
        (-1, "正在计算充满时间")
    ]

    for (minutes, expected) in cases {
        XCTAssertEqual(
            StatusPresentation.batteryTimeToFullText(minutes: minutes),
            expected,
            "minutes: \(String(describing: minutes))"
        )
    }
}
```

Change the charging accessibility expectation to:

```swift
"电池 73%（预计 1 小时 25 分钟充满），Wi-Fi 3 格，音量 50% · 2 格"
```

and make the battery fixture in that test pass `timeToFullChargeMinutes: 85`.

Update `makeBattery` in `StatusPresentationTests` to accept:

```swift
isCharged: Bool = false,
timeToFullChargeMinutes: Int? = nil,
```

and pass both fields to `BatteryStatus`.

- [ ] **Step 2: Add snapshot default assertions**

In `StatusSnapshotTests.testSnapshotPlaceholderHasStableDefaults`, add:

```swift
XCTAssertFalse(snapshot.battery.isCharged)
XCTAssertNil(snapshot.battery.timeToFullChargeMinutes)
```

- [ ] **Step 3: Run the focused tests and verify failure**

Run:

```bash
bash scripts/test.sh StatusPresentationTests
```

Expected: compilation fails because `batteryTitle` and `batteryTimeToFullText` do not exist.

- [ ] **Step 4: Implement formatting in `StatusPresentation`**

Add next to the existing battery presentation helpers:

```swift
static func batteryTitle(_ battery: BatteryStatus) -> String {
    "电池 · \(battery.percentage)%"
}

static func batteryTimeToFullText(minutes: Int?) -> String {
    guard let minutes, minutes > 0 else {
        return "正在计算充满时间"
    }

    let hours = minutes / 60
    let remainingMinutes = minutes % 60

    if hours == 0 {
        return "预计 \(remainingMinutes) 分钟充满"
    }
    if remainingMinutes == 0 {
        return "预计 \(hours) 小时充满"
    }
    return "预计 \(hours) 小时 \(remainingMinutes) 分钟充满"
}
```

Replace `batterySubtitle` with:

```swift
static func batterySubtitle(_ battery: BatteryStatus) -> String {
    if !battery.isPresent { return "无电池设备" }
    if battery.isCharged { return "已充满" }
    if battery.isCharging {
        return batteryTimeToFullText(minutes: battery.timeToFullChargeMinutes)
    }
    if battery.isLowPowerMode { return "低电量模式" }
    if battery.isConnectedToPower { return "已连接电源" }
    return "电池供电"
}
```

- [ ] **Step 5: Run the focused tests**

Run:

```bash
bash scripts/test.sh StatusPresentationTests
```

Expected: all `StatusPresentationTests` pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/StatusTrioCore/UI/StatusPopoverView.swift \
  Tests/StatusTrioCoreTests/StatusPresentationTests.swift \
  Tests/StatusTrioCoreTests/StatusSnapshotTests.swift
git commit -m "feat: format battery charged state and time to full"
```

### Task 3: Render battery row and open Battery Settings

**Files:**
- Create: `Sources/StatusTrioCore/UI/BatteryStatusView.swift`
- Modify: `Sources/StatusTrioCore/UI/StatusPopoverView.swift`
- Modify: `Sources/StatusTrioCore/UI/StatusBarController.swift`
- Modify: `Tests/StatusTrioCoreTests/StatusMenuBuilderTests.swift`
- Modify: `Tests/StatusTrioCoreTests/StatusPresentationTests.swift`
- Modify: `README.md`

- [ ] **Step 1: Write failing URL and copy tests**

Add to `StatusMenuBuilderTests.testSystemSettingsURLFallbackOrder`:

```swift
XCTAssertEqual(
    StatusBarController.batterySettingsURLs.map(\.absoluteString),
    [
        "x-apple.systempreferences:com.apple.Battery-Settings.extension",
        "x-apple.systempreferences:com.apple.preference.battery"
    ]
)
```

Add to `StatusPresentationTests.testSettingsAction`:

```swift
XCTAssertEqual(StatusPresentation.openBatterySettingsAction, "打开电源设置")
```

- [ ] **Step 2: Run the focused tests and verify failure**

Run:

```bash
bash scripts/test.sh StatusMenuBuilderTests
```

Expected: compilation fails because `batterySettingsURLs` does not exist.

- [ ] **Step 3: Add the battery row component**

Create `BatteryStatusView.swift`:

```swift
import SwiftUI

struct BatteryStatusView: View {
    let battery: BatteryStatus
    let onOpenBatterySettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "battery.100")
                .frame(width: 24)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(StatusPresentation.batteryTitle(battery))
                    .font(.headline)
                    .monospacedDigit()
                Text(StatusPresentation.batterySubtitle(battery))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if battery.isPresent {
                Button(
                    StatusPresentation.openBatterySettingsAction,
                    systemImage: "gearshape",
                    action: onOpenBatterySettings
                )
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(StatusPresentation.openBatterySettingsAction)
                .accessibilityLabel(StatusPresentation.openBatterySettingsAction)
                .frame(width: 24, height: 24)
            }
        }
    }
}
```

- [ ] **Step 4: Wire the popup and settings URL**

In `StatusPresentation`, add:

```swift
static let openBatterySettingsAction = "打开电源设置"
```

In `StatusPopoverView`, add:

```swift
let openBatterySettings: () -> Void
```

Replace the battery `statusRow` call with:

```swift
BatteryStatusView(
    battery: store.snapshot.battery,
    onOpenBatterySettings: openBatterySettings
)
```

Delete the now-unused private `statusRow` helper.

In `StatusBarController.configurePopover()`, pass `openBatterySettings: handleOpenBatterySettings`. Add:

```swift
@objc private func handleOpenBatterySettings() {
    popover.performClose(nil)
    Self.openSystemSettings(Self.batterySettingsURLs)
}

static let batterySettingsURLs = [
    "x-apple.systempreferences:com.apple.Battery-Settings.extension",
    "x-apple.systempreferences:com.apple.preference.battery"
]
.compactMap(URL.init(string:))
```

Update README's battery feature bullet to:

```markdown
- Battery percentage, charged/charging state, estimated time to full, and a Battery Settings shortcut.
```

- [ ] **Step 5: Run focused tests**

Run:

```bash
bash scripts/test.sh StatusMenuBuilderTests
bash scripts/test.sh StatusPresentationTests
```

Expected: both suites pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/StatusTrioCore/UI/BatteryStatusView.swift \
  Sources/StatusTrioCore/UI/StatusPopoverView.swift \
  Sources/StatusTrioCore/UI/StatusBarController.swift \
  Tests/StatusTrioCoreTests/StatusMenuBuilderTests.swift \
  Tests/StatusTrioCoreTests/StatusPresentationTests.swift \
  README.md
git commit -m "feat: add popup battery details and settings shortcut"
```

### Task 4: Full verification

**Files:**
- Verify only; no source changes expected

- [ ] **Step 1: Run the full test suite**

```bash
bash scripts/test.sh
```

Expected: all tests pass.

- [ ] **Step 2: Inspect the diff and repository state**

```bash
git diff --check
git status --short --branch
git log --oneline --decorate -5
```

Expected: no whitespace errors, clean tracked worktree, and the specification plus three implementation commits are present.

- [ ] **Step 3: Build the release app bundle without launching it**

```bash
bash scripts/build-app.sh release no-open
```

Expected: `dist/StatusTrio.app` builds and receives an ad-hoc signature.

- [ ] **Step 4: Manually verify popup states**

Launch the built app and check:

1. Charging with a known estimate: title `电池 · N%`, subtitle `预计 … 充满`.
2. Charging with an unknown estimate: subtitle `正在计算充满时间`.
3. Fully charged: subtitle `已充满`.
4. Connected but not charging: subtitle `已连接电源`.
5. On battery: subtitle `电池供电`.
6. Gear closes the popup and opens System Settings > Battery.
7. A Mac without an internal battery hides the gear and remains stable.
