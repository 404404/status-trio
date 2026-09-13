import SwiftUI

enum StatusPresentation {
    static let settingsAction = "设置…"
    static let requestWiFiNameAction = "允许定位以显示 Wi-Fi 名称"
    static let openLocationSettingsAction = "去设置中允许定位"
    static let openWiFiSettingsAction = "打开 Wi-Fi 设置"
    static let openBatterySettingsAction = "打开电源设置"
    static let openSoundSettingsAction = "打开声音设置"
    static let statusItemAccessibilityLabel = "Status Trio"

    static func statusItemAccessibilityValue(_ snapshot: StatusSnapshot) -> String {
        let batterySummary: String
        if snapshot.battery.isPresent {
            let percentage = "电池 \(snapshot.battery.percentage)%"
            let subtitle = batterySubtitle(snapshot.battery)
            batterySummary = subtitle == "电池供电" ? percentage : "\(percentage)（\(subtitle)）"
        } else {
            batterySummary = "无电池设备"
        }

        let wifiSummary = wifiAccessibilitySummary(snapshot.wifi)

        return "\(batterySummary)，\(wifiSummary)，音量 \(volumeValue(snapshot.volume))"
    }

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
        if let ssid = wifi.ssid, !ssid.isEmpty {
            return ssid
        }

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

    private static func wifiAccessibilitySummary(_ wifi: WiFiStatus) -> String {
        if let ssid = wifi.ssid, !ssid.isEmpty {
            return "Wi-Fi \(ssid)，\(wifiValue(wifi))"
        }

        switch wifi.state {
        case .connected:
            return "Wi-Fi \(StatusMappings.wifiBars(rssi: wifi.rssi)) 格"
        case .notAssociated:
            return "Wi-Fi 未关联"
        case .off:
            return "Wi-Fi 关闭"
        case .noInternet:
            return "Wi-Fi 无互联网"
        case .hotspot:
            return "Wi-Fi iPhone 热点"
        case .temporary:
            return "Wi-Fi 临时连接"
        case .shared:
            return "Wi-Fi 正在共享"
        case .unavailable:
            return "Wi-Fi 不可用"
        }
    }

    static func volumeValue(_ volume: VolumeStatus) -> String {
        guard let scalar = volume.scalar, scalar.isFinite else { return "—" }
        let clampedScalar = min(1, max(0, scalar))
        let percentage = Int((clampedScalar * 100).rounded())
        let steps = StatusMappings.volumeSteps(
            scalar: clampedScalar,
            isMuted: volume.isMuted
        ) ?? 0
        return volume.isMuted ? "静音" : "\(percentage)% · \(steps) 格"
    }

    static func volumeSubtitle(_ volume: VolumeStatus) -> String {
        volume.deviceName ?? "无默认输出设备"
    }
}

struct StatusPopoverView: View {
    @ObservedObject var store: SystemStatusStore
    let requestWiFiNameAccess: () -> Void
    let openBatterySettings: () -> Void
    let openWiFiSettings: () -> Void
    let openLocationSettings: () -> Void
    let openSettings: () -> Void
    let openSoundSettings: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BatteryStatusView(
                battery: store.snapshot.battery,
                onOpenBatterySettings: openBatterySettings
            )
            Divider()
            WiFiStatusView(
                wifi: store.snapshot.wifi,
                onRequestNameAccess: requestWiFiNameAccess,
                onOpenWiFiSettings: openWiFiSettings,
                onOpenLocationSettings: openLocationSettings
            )
            Divider()
            VolumeControlsView(
                volume: store.snapshot.volume,
                isEnabled: store.isVolumeControlAvailable,
                onVolumeChange: store.setVolume,
                onToggleMute: store.toggleMute,
                onSelectOutputDevice: store.selectOutputDevice,
                onOpenSoundSettings: openSoundSettings
            )

            Divider()

            Button(StatusPresentation.settingsAction) {
                openSettings()
            }
            .buttonStyle(.plain)

            Button("退出 Status Trio") {
                quit()
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
        }
        .padding(14)
        .frame(width: 300)
    }

}
