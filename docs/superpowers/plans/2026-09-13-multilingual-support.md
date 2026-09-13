# Multilingual Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 12-language localization with system-language following and immediate in-app language switching.

**Architecture:** Store translations in standard `.lproj/Localizable.strings` resources loaded from a `Localization` observable service. Inject that service into SwiftUI and AppKit surfaces, persist the preference in `UserDefaults`, and route every app-owned user-visible string through type-safe `LocalizationKey` values.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Combine, XCTest, Swift Package Manager

> Implementation is complete. Automated test and build verification are intentionally deferred to the user.

---

## File Structure

| Path | Responsibility |
| --- | --- |
| `Sources/StatusTrioCore/Localization/AppLanguage.swift` | Supported language identifiers, native names, locale, layout direction, and system preference matching |
| `Sources/StatusTrioCore/Localization/LocalizationKey.swift` | Type-safe translation key inventory |
| `Sources/StatusTrioCore/Localization/Localization.swift` | Preference persistence, bundle resolution, string lookup, formatting, and immediate change publication |
| `Sources/StatusTrioCore/Resources/<language>.lproj/Localizable.strings` | Twelve localized application string tables |
| `Sources/StatusTrioCore/Resources/<language>.lproj/InfoPlist.strings` | Twelve system permission prompt translations |
| `Sources/StatusTrioCore/UI/StatusPopoverView.swift` | Localized status presentation formatter and popover assembly |
| `Sources/StatusTrioCore/UI/SettingsView.swift` | Language picker and localized settings content |
| `Sources/StatusTrioCore/UI/SettingsWindowController.swift` | Inject localization and refresh the window title |
| `Sources/StatusTrioCore/UI/StatusBarController.swift` | Inject localization and refresh menus/accessibility immediately |
| `Sources/StatusTrioCore/App/AppEnvironment.swift` | Own the localization service and wire controllers |
| `Sources/StatusTrioCore/Monitoring/VolumeMonitor.swift` | Stop hardcoding localized fallback device names |
| `Sources/StatusTrioCore/Audio/AudioOutputDevice.swift` | Allow missing external device names |
| `Package.swift` | Process localization resources in `StatusTrioCore` |
| `scripts/build-app.sh` | Copy `InfoPlist.strings` into the app bundle |
| `Tests/StatusTrioCoreTests/LocalizationTests.swift` | Language resolution, persistence, lookup, and completeness tests |
| `Tests/StatusTrioCoreTests/StatusPresentationTests.swift` | Localized status and formatting tests |
| `Tests/StatusTrioCoreTests/StatusMenuBuilderTests.swift` | Localized menu tests |
| `Tests/StatusTrioCoreTests/SettingsWindowControllerTests.swift` | Localized window title test |
| `Tests/StatusTrioCoreTests/VolumeMonitorTests.swift` | Optional fallback device name tests |
| `README.md` | Document supported languages and the language setting |

### Task 1: Add supported language resolution

**Files:**
- Create: `Sources/StatusTrioCore/Localization/AppLanguage.swift`
- Create: `Tests/StatusTrioCoreTests/AppLanguageTests.swift`

- [x] **Step 1: Write failing resolution tests**

```swift
import XCTest
@testable import StatusTrioCore

final class AppLanguageTests: XCTestCase {
    func testSupportsTwelveLanguages() {
        XCTAssertEqual(AppLanguage.allCases.count, 12)
    }

    func testResolvesChineseScriptAndRegionVariants() {
        XCTAssertEqual(AppLanguage.resolved(preferredLanguages: ["zh-CN"]), .simplifiedChinese)
        XCTAssertEqual(AppLanguage.resolved(preferredLanguages: ["zh-Hans-CN"]), .simplifiedChinese)
        XCTAssertEqual(AppLanguage.resolved(preferredLanguages: ["zh-TW"]), .traditionalChinese)
        XCTAssertEqual(AppLanguage.resolved(preferredLanguages: ["zh-Hant-HK"]), .traditionalChinese)
    }

    func testResolvesBaseLanguageVariants() {
        XCTAssertEqual(AppLanguage.resolved(preferredLanguages: ["en-US"]), .english)
        XCTAssertEqual(AppLanguage.resolved(preferredLanguages: ["ja-JP"]), .japanese)
        XCTAssertEqual(AppLanguage.resolved(preferredLanguages: ["pt-BR"]), .brazilianPortuguese)
        XCTAssertEqual(AppLanguage.resolved(preferredLanguages: ["pt"]), .brazilianPortuguese)
    }

    func testUsesFirstSupportedSystemPreferenceThenEnglishFallback() {
        XCTAssertEqual(
            AppLanguage.resolved(preferredLanguages: ["fr-CA", "de-DE"]),
            .french
        )
        XCTAssertEqual(AppLanguage.resolved(preferredLanguages: ["yue-Hant"]), .english)
    }

    func testArabicUsesRightToLeftLayout() {
        XCTAssertEqual(AppLanguage.arabic.layoutDirection, .rightToLeft)
        XCTAssertEqual(AppLanguage.english.layoutDirection, .leftToRight)
    }
}
```

- [x] **Step 2: Run the focused test and verify failure**

Run: `bash scripts/test.sh AppLanguageTests`

Expected: compilation fails because `AppLanguage` does not exist.

- [x] **Step 3: Implement `AppLanguage`**

Define all twelve cases with their BCP-47 raw values, native names, locale, layout direction, and this resolver:

```swift
static func resolved(preferredLanguages: [String]) -> AppLanguage {
    for identifier in preferredLanguages {
        if let match = match(identifier) {
            return match
        }
    }
    return .english
}

static func match(_ identifier: String) -> AppLanguage? {
    let normalized = identifier.replacingOccurrences(of: "_", with: "-").lowercased()

    if normalized == "zh"
        || normalized.hasPrefix("zh-hans")
        || normalized.hasPrefix("zh-cn")
        || normalized.hasPrefix("zh-sg")
        || normalized.hasPrefix("zh-my") {
        return .simplifiedChinese
    }

    if normalized.hasPrefix("zh-hant")
        || normalized.hasPrefix("zh-tw")
        || normalized.hasPrefix("zh-hk")
        || normalized.hasPrefix("zh-mo") {
        return .traditionalChinese
    }

    if normalized == "pt" || normalized.hasPrefix("pt-br") {
        return .brazilianPortuguese
    }

    return allCases.first { language in
        let raw = language.rawValue.lowercased()
        return normalized == raw || normalized.hasPrefix("\(raw)-")
    }
}
```

`layoutDirection` returns `.rightToLeft` only for `.arabic`; `nsLayoutDirection` maps the same value to `NSUserInterfaceLayoutDirection`.

- [x] **Step 4: Run the focused tests**

Run: `bash scripts/test.sh AppLanguageTests`

Expected: all `AppLanguageTests` pass.

- [x] **Step 5: Commit**

```bash
git add Sources/StatusTrioCore/Localization/AppLanguage.swift \
  Tests/StatusTrioCoreTests/AppLanguageTests.swift
git commit -m "feat: add supported language resolution"
```

### Task 2: Add localization resources and runtime service

**Files:**
- Create: `Sources/StatusTrioCore/Localization/LocalizationKey.swift`
- Create: `Sources/StatusTrioCore/Localization/Localization.swift`
- Create: `Sources/StatusTrioCore/Resources/en.lproj/Localizable.strings`
- Create: `Sources/StatusTrioCore/Resources/zh-Hans.lproj/Localizable.strings`
- Create: `Sources/StatusTrioCore/Resources/zh-Hant.lproj/Localizable.strings`
- Create: `Sources/StatusTrioCore/Resources/ja.lproj/Localizable.strings`
- Create: `Sources/StatusTrioCore/Resources/ko.lproj/Localizable.strings`
- Create: `Sources/StatusTrioCore/Resources/es.lproj/Localizable.strings`
- Create: `Sources/StatusTrioCore/Resources/fr.lproj/Localizable.strings`
- Create: `Sources/StatusTrioCore/Resources/de.lproj/Localizable.strings`
- Create: `Sources/StatusTrioCore/Resources/it.lproj/Localizable.strings`
- Create: `Sources/StatusTrioCore/Resources/pt-BR.lproj/Localizable.strings`
- Create: `Sources/StatusTrioCore/Resources/ru.lproj/Localizable.strings`
- Create: `Sources/StatusTrioCore/Resources/ar.lproj/Localizable.strings`
- Modify: `Package.swift`
- Create: `Tests/StatusTrioCoreTests/LocalizationTests.swift`

- [x] **Step 1: Write failing localization tests**

```swift
import XCTest
@testable import StatusTrioCore

@MainActor
final class LocalizationTests: XCTestCase {
    func testManualLanguagePersistsAndResolves() {
        let suite = makeSuite()
        defer { clear(suite) }

        let localization = Localization(defaults: suite.defaults, preferredLanguages: ["en"])
        localization.setPreference(.language(.german))

        XCTAssertEqual(localization.resolvedLanguage, .german)
        XCTAssertEqual(
            Localization(defaults: suite.defaults, preferredLanguages: ["en"]).resolvedLanguage,
            .german
        )
    }

    func testSystemLanguageFollowsInjectedPreferences() {
        let suite = makeSuite()
        defer { clear(suite) }

        let localization = Localization(
            defaults: suite.defaults,
            preferredLanguages: ["zh-TW", "en-US"]
        )

        XCTAssertEqual(localization.preference, .system)
        XCTAssertEqual(localization.resolvedLanguage, .traditionalChinese)
    }

    func testInvalidStoredLanguageFallsBackToSystem() {
        let suite = makeSuite()
        defer { clear(suite) }
        suite.defaults.set("not-a-language", forKey: Localization.defaultsKey)

        let localization = Localization(defaults: suite.defaults, preferredLanguages: ["ja-JP"])

        XCTAssertEqual(localization.preference, .system)
        XCTAssertEqual(localization.resolvedLanguage, .japanese)
    }

    func testEveryLanguageHasEveryNonEmptyKey() throws {
        for language in AppLanguage.allCases {
            let bundle = try XCTUnwrap(
                Bundle.module.url(forResource: language.rawValue, withExtension: "lproj")
                    .flatMap(Bundle.init(url:))
            )

            for key in LocalizationKey.allCases {
                let value = bundle.localizedString(forKey: key.rawValue, value: nil, table: nil)
                XCTAssertFalse(value.isEmpty, "\(language.rawValue) missing \(key.rawValue)")
                XCTAssertNotEqual(value, key.rawValue, "\(language.rawValue) missing \(key.rawValue)")
            }
        }
    }

    func testFormattedStringUsesSelectedLanguageLocale() {
        let suite = makeSuite()
        defer { clear(suite) }
        let localization = Localization(defaults: suite.defaults, preferredLanguages: ["en"])
        localization.setPreference(.language(.simplifiedChinese))

        XCTAssertEqual(
            localization.format(.batteryTitle, 68),
            String(format: "电池 · %d%%", locale: Locale(identifier: "zh-Hans"), 68)
        )
    }

    private func makeSuite() -> (defaults: UserDefaults, name: String) {
        let name = "StatusTrioCoreTests.Localization.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }

    private func clear(_ suite: (defaults: UserDefaults, name: String)) {
        suite.defaults.removePersistentDomain(forName: suite.name)
    }
}
```

- [x] **Step 2: Run the focused test and verify failure**

Run: `bash scripts/test.sh LocalizationTests`

Expected: compilation fails because `Localization`, `LocalizationKey`, resources, and `Bundle.module` are not yet configured.

- [x] **Step 3: Add the exact key inventory**

Create `LocalizationKey` with these raw values and no others:

```text
menu.version, menu.settings, menu.quit
settings.title
settings.language, settings.language.followSystem, settings.language.description
settings.iconSize, settings.iconSize.accessibilityValue, settings.iconSize.description
settings.battery.title, settings.battery.showPercentage,
settings.battery.showChargingIndicator, settings.battery.chargingDescription,
settings.battery.symbolScale, settings.battery.symbolScaleAccessibility,
settings.battery.symbolScaleDescription, settings.battery.statusColors,
settings.battery.statusColorsDescription, settings.battery.criticalThreshold,
settings.battery.criticalThresholdDescription
battery.title, battery.state.notPresent, battery.state.charged,
battery.state.calculatingTimeToFull, battery.timeToFull.minutes,
battery.timeToFull.hours, battery.timeToFull.hoursMinutes,
battery.state.lowPowerMode, battery.state.connectedToPower,
battery.state.onBattery, battery.action.openSettings,
battery.accessibility.value
common.parenthetical, common.labelValue
wifi.title, wifi.value.bars, wifi.value.notAssociated, wifi.value.off,
wifi.value.noInternet, wifi.value.hotspot, wifi.value.temporary,
wifi.value.shared, wifi.value.unavailable, wifi.subtitle.connected,
wifi.subtitle.notAssociated, wifi.subtitle.off, wifi.subtitle.noInternet,
wifi.subtitle.hotspot, wifi.subtitle.temporary, wifi.subtitle.shared,
wifi.subtitle.unavailable, wifi.action.requestNameAccess,
wifi.action.openLocationSettings, wifi.action.openSettings,
wifi.accessibility.withSSID
volume.title, volume.titleUnavailable, volume.muted, volume.unmuted,
volume.value, volume.noDefaultDevice, volume.output.title,
volume.output.empty, volume.output.current, volume.output.switchTo,
volume.output.unknownDevice, volume.action.openSettings,
volume.accessibility.label
accessibility.status, accessibility.battery, accessibility.volume
```

Use `case menuVersion = "menu.version"`-style Swift cases. Add `CaseIterable` and `Sendable`.

- [x] **Step 4: Create all twelve `.strings` files**

Every file must contain the same keys and non-empty translations. Use these source values as the semantic contract:

```text
"menu.version" = "Status Trio %@";
"menu.settings" = "Settings…";
"menu.quit" = "Quit Status Trio";
"settings.title" = "Settings";
"settings.language" = "Language";
"settings.language.followSystem" = "Follow System";
"settings.language.description" = "Changes apply immediately.";
"settings.iconSize" = "Icon Size";
"settings.iconSize.accessibilityValue" = "%d points";
"settings.iconSize.description" = "Adjusts the menu bar icon render size from 20–32 pt.";
"settings.battery.title" = "Battery Display";
"settings.battery.showPercentage" = "Show battery percentage";
"settings.battery.showChargingIndicator" = "Show bolt while charging or connected to power";
"settings.battery.chargingDescription" = "When enabled, the percentage becomes a white bolt while charging or connected to power.";
"settings.battery.symbolScale" = "Percentage/bolt size";
"settings.battery.symbolScaleAccessibility" = "Battery percentage and bolt size";
"settings.battery.symbolScaleDescription" = "The percentage and bolt share this size.";
"settings.battery.statusColors" = "Color the arc by battery state";
"settings.battery.statusColorsDescription" = "Low battery is red, Low Power Mode is yellow, and charging or connected power is green.";
"settings.battery.criticalThreshold" = "Low battery threshold";
"settings.battery.criticalThresholdDescription" = "Battery levels below this threshold are treated as low and shown in red.";
"battery.title" = "Battery · %d%%";
"battery.state.notPresent" = "No battery";
"battery.state.charged" = "Fully charged";
"battery.state.calculatingTimeToFull" = "Calculating time to full";
"battery.timeToFull.minutes" = "About %d min to full";
"battery.timeToFull.hours" = "About %d h to full";
"battery.timeToFull.hoursMinutes" = "About %d h %d min to full";
"battery.state.lowPowerMode" = "Low Power Mode";
"battery.state.connectedToPower" = "Connected to power";
"battery.state.onBattery" = "On battery";
"battery.action.openSettings" = "Open Battery Settings";
"battery.accessibility.value" = "Battery %d%%";
"common.parenthetical" = "%@ (%@)";
"common.labelValue" = "%@, %@";
"wifi.title" = "Wi-Fi";
"wifi.value.bars" = "%d bars";
"wifi.value.notAssociated" = "Not associated";
"wifi.value.off" = "Off";
"wifi.value.noInternet" = "No internet";
"wifi.value.hotspot" = "iPhone hotspot";
"wifi.value.temporary" = "Temporary";
"wifi.value.shared" = "Sharing";
"wifi.value.unavailable" = "Unavailable";
"wifi.subtitle.connected" = "Connected";
"wifi.subtitle.notAssociated" = "Wi-Fi is on but not associated";
"wifi.subtitle.off" = "Wi-Fi is off or unavailable";
"wifi.subtitle.noInternet" = "Network reachability check failed";
"wifi.subtitle.hotspot" = "Using an iPhone hotspot";
"wifi.subtitle.temporary" = "Temporary Wi-Fi connection";
"wifi.subtitle.shared" = "Sharing the internet";
"wifi.subtitle.unavailable" = "Unable to read network status";
"wifi.action.requestNameAccess" = "Allow location to show Wi-Fi name";
"wifi.action.openLocationSettings" = "Allow location in Settings";
"wifi.action.openSettings" = "Open Wi-Fi Settings";
"wifi.accessibility.withSSID" = "Wi-Fi %@, %@";
"volume.title" = "Volume · %d%%";
"volume.titleUnavailable" = "Volume · —";
"volume.muted" = "Muted";
"volume.unmuted" = "Unmute";
"volume.value" = "%d%% · %d bars";
"volume.noDefaultDevice" = "No default output device";
"volume.output.title" = "Output";
"volume.output.empty" = "No output devices available";
"volume.output.current" = "Current output device";
"volume.output.switchTo" = "Switch to %@";
"volume.output.unknownDevice" = "Unknown output device";
"volume.action.openSettings" = "Open Sound Settings";
"volume.accessibility.label" = "Volume";
"accessibility.status" = "%@, %@, %@";
"accessibility.battery" = "Battery %d%%";
"accessibility.volume" = "Volume %@";
```

Translate the complete value set into `zh-Hans`, `zh-Hant`, `ja`, `ko`, `es`, `fr`, `de`, `it`, `pt-BR`, `ru`, and `ar`. Preserve every format specifier exactly once and in a grammar-safe order. Arabic resources must use valid UTF-8 Arabic strings.

- [x] **Step 5: Process resources in SwiftPM**

Add to the `StatusTrioCore` target:

```swift
resources: [.process("Resources")]
```

- [x] **Step 6: Implement `Localization`**

Use `@MainActor final class Localization: ObservableObject`, `@Published private(set) var preference`, `@Published private(set) var resolvedLanguage`, and `static let defaultsKey = "appLanguage"`. Persist only fixed-language raw values; `.system` removes the key. Resolve strings through the selected `.lproj` bundle, fall back to `en.lproj`, then return the key. Format with:

```swift
func format(_ key: LocalizationKey, _ arguments: CVarArg...) -> String {
    String(
        format: string(key),
        locale: resolvedLanguage.locale,
        arguments: arguments
    )
}
```

Observe `NSLocale.currentLocaleDidChangeNotification` and re-resolve only while the preference is `.system`.

- [x] **Step 7: Run localization tests**

Run: `bash scripts/test.sh LocalizationTests`

Expected: all localization and completeness tests pass.

- [x] **Step 8: Commit**

```bash
git add Package.swift Sources/StatusTrioCore/Localization \
  Sources/StatusTrioCore/Resources Tests/StatusTrioCoreTests/LocalizationTests.swift
git commit -m "feat: add localization resources and runtime service"
```

### Task 3: Add language selection and runtime wiring

**Files:**
- Modify: `Sources/StatusTrioCore/UI/SettingsView.swift`
- Modify: `Sources/StatusTrioCore/UI/SettingsWindowController.swift`
- Modify: `Sources/StatusTrioCore/App/AppEnvironment.swift`
- Modify: `Tests/StatusTrioCoreTests/SettingsWindowControllerTests.swift`

- [x] **Step 1: Update the window title test first**

Construct the controller with a fixed-language `Localization`, then assert `window.title == "设置"`. Add a second assertion after switching to German that the existing window title becomes `"Einstellungen"`.

- [x] **Step 2: Run the focused test and verify failure**

Run: `bash scripts/test.sh SettingsWindowControllerTests`

Expected: compilation fails because the controller does not yet accept `Localization`.

- [x] **Step 3: Inject localization and add the picker**

`SettingsView` uses `@EnvironmentObject private var localization: Localization`. Add a language section before icon size:

```swift
VStack(alignment: .leading, spacing: 8) {
    Text(localization.string(.settingsLanguage))
        .font(.headline)

    Picker(
        localization.string(.settingsLanguage),
        selection: Binding(
            get: { localization.preference },
            set: { localization.setPreference($0) }
        )
    ) {
        Text(localization.string(.settingsLanguageFollowSystem))
            .tag(LanguagePreference.system)

        ForEach(AppLanguage.allCases) { language in
            Text(language.nativeName)
                .tag(LanguagePreference.language(language))
        }
    }
    .labelsHidden()

    Text(localization.string(.settingsLanguageDescription))
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

Replace every settings literal with its `LocalizationKey`.

- [x] **Step 4: Refresh the window title and layout direction**

`SettingsWindowController` stores `Localization`, injects it with `.environmentObject`, and subscribes to `$resolvedLanguage`. Update both `window.title` and `window.contentView?.userInterfaceLayoutDirection` from that subscription and when creating the window.

- [x] **Step 5: Wire `AppEnvironment`**

Create one `Localization()` in `AppEnvironment.live()`, pass it to `SettingsWindowController` and `StatusBarController`, and retain it as an `AppEnvironment` property.

- [x] **Step 6: Run focused and regression tests**

Run: `bash scripts/test.sh SettingsWindowControllerTests`

Expected: pass.

Run: `swift test`

Expected: pass.

- [x] **Step 7: Commit**

```bash
git add Sources/StatusTrioCore/UI/SettingsView.swift \
  Sources/StatusTrioCore/UI/SettingsWindowController.swift \
  Sources/StatusTrioCore/App/AppEnvironment.swift \
  Tests/StatusTrioCoreTests/SettingsWindowControllerTests.swift
git commit -m "feat: add language picker and runtime wiring"
```

### Task 4: Localize status presentation

**Files:**
- Modify: `Sources/StatusTrioCore/UI/StatusPopoverView.swift`
- Modify: `Tests/StatusTrioCoreTests/StatusPresentationTests.swift`

- [ ] **Step 1: Convert tests to injected localization**

Mark the test class `@MainActor`. Add a helper that creates `Localization` with an isolated `UserDefaults` suite and selects Simplified Chinese. Change every `StatusPresentation` call to pass the localization argument, preserving all existing Chinese expectations.

Add English assertions for battery, Wi-Fi, volume, and accessibility output.

- [ ] **Step 2: Run the focused test and verify failure**

Run: `bash scripts/test.sh StatusPresentationTests`

Expected: compilation fails because presentation methods do not yet accept `Localization`.

- [ ] **Step 3: Replace static strings with localized formatting**

Keep `StatusPresentation` static and change its signatures to include `localization: Localization`. Remove all six static action constants and translate through keys. Use `localization.format` for every value containing `%d` or `%@`.

Use status fields, not localized equality, to decide whether the accessibility battery summary is in the ordinary on-battery state:

```swift
let isOrdinaryBatteryState = battery.isPresent
    && !battery.isCharged
    && !battery.isCharging
    && !battery.isLowPowerMode
    && !battery.isConnectedToPower
```

- [ ] **Step 4: Run focused tests**

Run: `bash scripts/test.sh StatusPresentationTests`

Expected: pass in Chinese and English cases.

- [ ] **Step 5: Commit**

```bash
git add Sources/StatusTrioCore/UI/StatusPopoverView.swift \
  Tests/StatusTrioCoreTests/StatusPresentationTests.swift
git commit -m "feat: localize status presentation"
```

### Task 5: Localize menus and SwiftUI views

**Files:**
- Modify: `Sources/StatusTrioCore/UI/StatusMenuBuilder.swift`
- Modify: `Sources/StatusTrioCore/UI/StatusBarController.swift`
- Modify: `Sources/StatusTrioCore/UI/StatusPopoverView.swift`
- Modify: `Sources/StatusTrioCore/UI/BatteryStatusView.swift`
- Modify: `Sources/StatusTrioCore/UI/WiFiStatusView.swift`
- Modify: `Sources/StatusTrioCore/UI/WiFiStatusIcon.swift`
- Modify: `Sources/StatusTrioCore/UI/VolumeControlsView.swift`
- Modify: `Sources/StatusTrioCore/UI/OutputDeviceList.swift`
- Modify: `Sources/StatusTrioCore/UI/OutputDeviceRow.swift`
- Modify: `Tests/StatusTrioCoreTests/StatusMenuBuilderTests.swift`

- [ ] **Step 1: Update menu tests first**

Pass a fixed Simplified Chinese `Localization` into `StatusMenuBuilder.makeMenu` and keep the existing expected Chinese titles. Add a German case asserting `"Einstellungen…"` and `"Status Trio beenden"`.

- [ ] **Step 2: Run the focused test and verify failure**

Run: `bash scripts/test.sh StatusMenuBuilderTests`

Expected: compilation fails because menu construction does not accept localization yet.

- [ ] **Step 3: Localize menu construction**

Add `localization: Localization` to `makeMenu`, use `localization.format(.menuVersion, version)`, `localization.string(.menuSettings)`, and `localization.string(.menuQuit)`, and set:

```swift
menu.userInterfaceLayoutDirection = localization.resolvedLanguage.nsLayoutDirection
```

- [ ] **Step 4: Inject localization into the popover and refresh accessibility**

`StatusBarController` stores `Localization`, injects it into `StatusPopoverView` with `.environmentObject(localization)`, passes it to `StatusMenuBuilder`, and subscribes to `$resolvedLanguage` to call `renderLatestSnapshot()` immediately. The status item accessibility label remains `"Status Trio"`; its value uses `StatusPresentation.statusItemAccessibilityValue(snapshot, localization: localization)`.

- [ ] **Step 5: Replace view literals with environment-backed keys**

Add `@EnvironmentObject private var localization: Localization` to each SwiftUI view listed above. Replace every literal with `localization.string(...)` or `localization.format(...)`, including `.help` and `.accessibilityLabel`/`.accessibilityValue`. Reuse `StatusPresentation` methods where a value already exists.

- [ ] **Step 6: Run focused and regression tests**

Run: `bash scripts/test.sh StatusMenuBuilderTests`

Expected: pass.

Run: `swift test`

Expected: pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/StatusTrioCore/UI Tests/StatusTrioCoreTests/StatusMenuBuilderTests.swift
git commit -m "feat: localize menus and status views"
```

### Task 6: Remove hardcoded device-name fallbacks

**Files:**
- Modify: `Sources/StatusTrioCore/Monitoring/VolumeMonitor.swift`
- Modify: `Sources/StatusTrioCore/Audio/AudioOutputDevice.swift`
- Modify: `Sources/StatusTrioCore/Audio/CoreAudioOutputController.swift`
- Modify: `Sources/StatusTrioCore/UI/OutputDeviceRow.swift`
- Modify: `Tests/StatusTrioCoreTests/VolumeMonitorTests.swift`
- Modify: `Tests/StatusTrioCoreTests/StatusSnapshotTests.swift`

- [ ] **Step 1: Write failing optional-name tests**

Change the fake CoreAudio client case with a nil device name to expect `VolumeReading.deviceName == nil`. Add a `CoreAudioOutputController` test or a focused `AudioOutputDevice` construction test asserting a missing name remains `nil`. Update any test that expects `"默认输出设备"`.

- [ ] **Step 2: Run focused tests and verify failure**

Run: `bash scripts/test.sh VolumeMonitorTests`

Expected: compilation fails because `VolumeReading.deviceName` is still non-optional.

- [ ] **Step 3: Make external names optional**

Change `VolumeReading.deviceName` and `AudioOutputDevice.name` to `String?`. In `CoreAudioVolumeReader.read()` and `CoreAudioOutputController.outputDevices()`, pass the raw name or `nil` instead of localized fallback text. Update sorting to compare fallback empty strings safely.

- [ ] **Step 4: Render localized fallbacks in the UI**

`OutputDeviceRow` displays `localization.string(.volumeOutputUnknownDevice)` when `device.name` is nil, and uses the same resolved name in `.help` and `.accessibilityValue`. `VolumeControlsView` already gets `VolumeStatus.deviceName` as optional; keep `StatusPresentation.volumeSubtitle` responsible for the localized no-default-device fallback.

- [ ] **Step 5: Run focused and regression tests**

Run: `bash scripts/test.sh VolumeMonitorTests`

Expected: pass.

Run: `swift test`

Expected: pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/StatusTrioCore/Monitoring/VolumeMonitor.swift \
  Sources/StatusTrioCore/Audio/AudioOutputDevice.swift \
  Sources/StatusTrioCore/Audio/CoreAudioOutputController.swift \
  Sources/StatusTrioCore/UI/OutputDeviceRow.swift \
  Tests/StatusTrioCoreTests/VolumeMonitorTests.swift \
  Tests/StatusTrioCoreTests/StatusSnapshotTests.swift
git commit -m "fix: localize missing output-device names"
```

### Task 7: Package localized permission strings

**Files:**
- Create: `Sources/StatusTrioCore/Resources/en.lproj/InfoPlist.strings`
- Create: `Sources/StatusTrioCore/Resources/zh-Hans.lproj/InfoPlist.strings`
- Create: `Sources/StatusTrioCore/Resources/zh-Hant.lproj/InfoPlist.strings`
- Create: `Sources/StatusTrioCore/Resources/ja.lproj/InfoPlist.strings`
- Create: `Sources/StatusTrioCore/Resources/ko.lproj/InfoPlist.strings`
- Create: `Sources/StatusTrioCore/Resources/es.lproj/InfoPlist.strings`
- Create: `Sources/StatusTrioCore/Resources/fr.lproj/InfoPlist.strings`
- Create: `Sources/StatusTrioCore/Resources/de.lproj/InfoPlist.strings`
- Create: `Sources/StatusTrioCore/Resources/it.lproj/InfoPlist.strings`
- Create: `Sources/StatusTrioCore/Resources/pt-BR.lproj/InfoPlist.strings`
- Create: `Sources/StatusTrioCore/Resources/ru.lproj/InfoPlist.strings`
- Create: `Sources/StatusTrioCore/Resources/ar.lproj/InfoPlist.strings`
- Modify: `scripts/build-app.sh`

- [ ] **Step 1: Add all permission translations**

Each file contains:

```text
"NSLocationWhenInUseUsageDescription" = "<translated text>";
```

The English source is `Used to show the current Wi-Fi network name in the popover.`

- [ ] **Step 2: Copy localization directories into the app bundle**

After creating `Contents/Resources`, loop over each `*.lproj/InfoPlist.strings` under `Sources/StatusTrioCore/Resources`, create the target directory, and copy the file. Fail the build when no files are copied.

- [ ] **Step 3: Build the bundle**

Run: `bash scripts/build-app.sh release no-open`

Expected: build and ad-hoc signing succeed.

- [ ] **Step 4: Verify packaged resources**

Run:

```bash
find dist/StatusTrio.app/Contents/Resources -path '*lproj*InfoPlist.strings' | sort
```

Expected: 12 files covering `ar`, `de`, `en`, `es`, `fr`, `it`, `ja`, `ko`, `pt-BR`, `ru`, `zh-Hans`, and `zh-Hant`.

- [ ] **Step 5: Commit**

```bash
git add Sources/StatusTrioCore/Resources scripts/build-app.sh
git commit -m "feat: localize permission prompt strings"
```

### Task 8: Document and verify the complete feature

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Document supported languages**

Add a feature bullet and a short section stating that language follows macOS by default, can be changed in Settings, applies immediately, and supports the twelve languages in the approved spec.

- [ ] **Step 2: Run the complete test suite**

Run: `swift test`

Expected: all existing and new tests pass.

- [ ] **Step 3: Build the release app**

Run: `bash scripts/build-app.sh release no-open`

Expected: `dist/StatusTrio.app` is rebuilt and ad-hoc signed.

- [ ] **Step 4: Inspect localizations and the app resource bundle**

Run:

```bash
find dist/StatusTrio.app -path '*lproj*' -name '*.strings' | sort
find .build -path '*StatusTrio_StatusTrioCore.bundle*' -name 'Localizable.strings' | sort
git diff --check
```

Expected: no whitespace errors, 12 app-level `InfoPlist.strings`, and all 12 SwiftPM `Localizable.strings` files are present in the resource bundle.

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: document multilingual support"
```

## Self-Review

- Spec coverage: Tasks 1–2 cover language matching, persistence, fallback, runtime strings, all twelve resources, key completeness, and formatting. Task 3 covers the settings picker and immediate window refresh. Tasks 4–5 cover status presentation, menus, popover, accessibility, help, and layout direction. Task 6 covers external device-name fallbacks. Task 7 covers system permission strings and packaging. Task 8 covers documentation and end-to-end verification.
- Placeholder scan: no TODO/TBD markers; every code-changing step names the exact files and expected verification.
- Type consistency: `AppLanguage`, `LanguagePreference`, `Localization`, `LocalizationKey`, `localization.string`, `localization.format`, `nsLayoutDirection`, and `localization:` parameters use the same names throughout.
