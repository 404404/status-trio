import SwiftUI

enum StatusPresentation {
    static let settingsAction = "设置…"
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

        let wifiSummary: String
        switch snapshot.wifi.state {
        case .connected:
            wifiSummary = "Wi-Fi \(StatusMappings.wifiBars(rssi: snapshot.wifi.rssi)) 格"
        case .notAssociated:
            wifiSummary = "Wi-Fi 未关联"
        case .off:
            wifiSummary = "Wi-Fi 关闭"
        case .noInternet:
            wifiSummary = "Wi-Fi 无互联网"
        case .hotspot:
            wifiSummary = "Wi-Fi iPhone 热点"
        case .temporary:
            wifiSummary = "Wi-Fi 临时连接"
        case .shared:
            wifiSummary = "Wi-Fi 正在共享"
        case .unavailable:
            wifiSummary = "Wi-Fi 不可用"
        }

        return "\(batterySummary)，\(wifiSummary)，音量 \(volumeValue(snapshot.volume))"
    }

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
    let openSettings: () -> Void
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
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(value)
                .font(.body.monospacedDigit().weight(.semibold))
        }
    }
}
