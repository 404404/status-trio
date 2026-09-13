import XCTest
@testable import StatusTrioCore

final class StatusPresentationTests: XCTestCase {
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

    func testWiFiValueAndSubtitleForEveryState() {
        let cases: [(WiFiStatus, String, String)] = [
            (WiFiStatus(state: .connected, rssi: -55), "3 格", "已连接"),
            (WiFiStatus(state: .notAssociated, rssi: nil), "未关联", "Wi-Fi 开启，未关联"),
            (WiFiStatus(state: .off, rssi: nil), "关闭", "Wi-Fi 关闭或不可用"),
            (WiFiStatus(state: .noInternet, rssi: nil), "无互联网", "网络可达性检查失败"),
            (WiFiStatus(state: .hotspot, rssi: nil), "iPhone 热点", "使用 iPhone 热点"),
            (WiFiStatus(state: .temporary, rssi: nil), "临时连接", "临时 Wi-Fi 连接"),
            (WiFiStatus(state: .shared, rssi: nil), "正在共享", "正在共享互联网"),
            (WiFiStatus(state: .unavailable, rssi: nil), "不可用", "无法读取网络状态")
        ]

        for (wifi, expectedValue, expectedSubtitle) in cases {
            XCTAssertEqual(
                StatusPresentation.wifiValue(wifi),
                expectedValue,
                "value for \(wifi.state)"
            )
            XCTAssertEqual(
                StatusPresentation.wifiSubtitle(wifi),
                expectedSubtitle,
                "subtitle for \(wifi.state)"
            )
        }
    }

    func testSettingsAction() {
        XCTAssertEqual(StatusPresentation.settingsAction, "设置…")
        XCTAssertEqual(StatusPresentation.requestWiFiNameAction, "允许定位以显示 Wi-Fi 名称")
        XCTAssertEqual(StatusPresentation.openLocationSettingsAction, "去设置中允许定位")
        XCTAssertEqual(StatusPresentation.openWiFiSettingsAction, "打开 Wi-Fi 设置")
        XCTAssertEqual(StatusPresentation.openBatterySettingsAction, "打开电源设置")
        XCTAssertEqual(StatusPresentation.openSoundSettingsAction, "打开声音设置")
    }

    func testWiFiSubtitlePrefersSSID() {
        XCTAssertEqual(
            StatusPresentation.wifiSubtitle(
                WiFiStatus(
                    state: .connected,
                    rssi: -55,
                    ssid: "Studio Wi-Fi",
                    nameAccess: .authorized
                )
            ),
            "Studio Wi-Fi"
        )
    }

    func testStatusItemAccessibilitySummaryIncludesAllThreeStatuses() {
        let snapshot = StatusSnapshot(
            battery: makeBattery(
                isCharging: true,
                isConnectedToPower: true,
                percentage: 73,
                timeToFullChargeMinutes: 85
            ),
            wifi: WiFiStatus(state: .connected, rssi: -55),
            volume: VolumeStatus(
                scalar: 0.5,
                isMuted: false,
                deviceName: "MacBook Pro Speakers"
            )
        )

        XCTAssertEqual(StatusPresentation.statusItemAccessibilityLabel, "Status Trio")
        XCTAssertEqual(
            StatusPresentation.statusItemAccessibilityValue(snapshot),
            "电池 73%（预计 1 小时 25 分钟充满），Wi-Fi 3 格，音量 50% · 2 格"
        )
    }

    func testStatusItemAccessibilitySummaryIncludesWiFiNameWhenAvailable() {
        let snapshot = StatusSnapshot(
            battery: makeBattery(percentage: 73),
            wifi: WiFiStatus(
                state: .connected,
                rssi: -55,
                ssid: "Office",
                nameAccess: .authorized
            ),
            volume: VolumeStatus(
                scalar: 0.5,
                isMuted: false,
                deviceName: "MacBook Pro Speakers"
            )
        )

        XCTAssertEqual(
            StatusPresentation.statusItemAccessibilityValue(snapshot),
            "电池 73%，Wi-Fi Office，3 格，音量 50% · 2 格"
        )
    }

    func testVolumeValueForNilMutedAndNormalStates() {
        XCTAssertEqual(
            StatusPresentation.volumeValue(
                VolumeStatus(scalar: nil, isMuted: false, deviceName: nil)
            ),
            "—"
        )
        XCTAssertEqual(
            StatusPresentation.volumeValue(
                VolumeStatus(scalar: 0.62, isMuted: true, deviceName: "Speaker")
            ),
            "静音"
        )
        XCTAssertEqual(
            StatusPresentation.volumeValue(
                VolumeStatus(scalar: 0.62, isMuted: false, deviceName: "Speaker")
            ),
            "62% · 3 格"
        )
        XCTAssertEqual(
            StatusPresentation.volumeValue(
                VolumeStatus(scalar: 0.625, isMuted: false, deviceName: "Speaker")
            ),
            "63% · 3 格"
        )
    }

    func testVolumeValueRejectsNonFiniteScalars() {
        let cases: [Double] = [.nan, .infinity, -.infinity]

        for scalar in cases {
            XCTAssertEqual(
                StatusPresentation.volumeValue(
                    VolumeStatus(scalar: scalar, isMuted: false, deviceName: "Speaker")
                ),
                "—",
                "value for \(scalar)"
            )
        }
    }

    func testVolumeValueClampsFiniteScalars() {
        XCTAssertEqual(
            StatusPresentation.volumeValue(
                VolumeStatus(scalar: -0.5, isMuted: false, deviceName: "Speaker")
            ),
            "0% · 0 格"
        )
        XCTAssertEqual(
            StatusPresentation.volumeValue(
                VolumeStatus(scalar: 1.5, isMuted: false, deviceName: "Speaker")
            ),
            "100% · 4 格"
        )
    }

    func testVolumeValueStepMapping() {
        let cases: [(Double, Int)] = [
            (0.00, 0),
            (0.01, 1),
            (0.25, 1),
            (0.26, 2),
            (0.50, 2),
            (0.51, 3),
            (0.75, 3),
            (0.76, 4),
            (1.00, 4)
        ]

        for (scalar, steps) in cases {
            XCTAssertEqual(
                StatusPresentation.volumeValue(
                    VolumeStatus(scalar: scalar, isMuted: false, deviceName: "Speaker")
                ),
                "\(Int((scalar * 100).rounded()))% · \(steps) 格"
            )
        }
    }

    func testVolumeSubtitleUsesDeviceNameOrFallback() {
        XCTAssertEqual(
            StatusPresentation.volumeSubtitle(
                VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "MacBook Speakers")
            ),
            "MacBook Speakers"
        )
        XCTAssertEqual(
            StatusPresentation.volumeSubtitle(
                VolumeStatus(scalar: 0.5, isMuted: false, deviceName: nil)
            ),
            "无默认输出设备"
        )
    }

    private func makeBattery(
        isPresent: Bool = true,
        isCharging: Bool = false,
        isCharged: Bool = false,
        isLowPowerMode: Bool = false,
        isConnectedToPower: Bool = false,
        percentage: Int = 100,
        timeToFullChargeMinutes: Int? = nil
    ) -> BatteryStatus {
        BatteryStatus(
            rawPercentage: percentage,
            isPresent: isPresent,
            isCharging: isCharging,
            isCharged: isCharged,
            timeToFullChargeMinutes: timeToFullChargeMinutes,
            isLowPowerMode: isLowPowerMode,
            isConnectedToPower: isConnectedToPower
        )
    }
}
