import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("图标渲染范围")
                    Spacer()
                    Text("\(Int(store.iconSize)) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: $store.iconSize,
                    in: SettingsStore.iconSizeRange,
                    step: 1
                )
                .accessibilityLabel("图标渲染范围")
                .accessibilityValue("\(Int(store.iconSize)) 点")
            }

            HStack(spacing: 12) {
                IconSizePreview(
                    size: store.iconSize,
                    options: store.batteryIconOptions
                )
                Text("调整菜单栏图标的渲染尺寸，可选 20–32 pt。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("电池显示")
                    .font(.headline)

                Toggle("显示电量数字", isOn: $store.showsBatteryPercentage)
                Toggle("充电/连接电源时显示闪电", isOn: $store.showsChargingIndicator)

                Text("开启后，正在充电或已连接电源时，电量数字会替换为白色闪电；关闭则继续显示数字。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Text("电量数字/闪电大小")
                    Spacer()
                    Text("\(Int(store.batterySymbolScale * 100))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: $store.batterySymbolScale,
                    in: SettingsStore.batterySymbolScaleRange,
                    step: 0.05
                )
                .disabled(!store.isBatterySymbolSizeEnabled)
                .accessibilityLabel("电量数字和闪电大小")
                .accessibilityValue("\(Int(store.batterySymbolScale * 100))%")

                Text("数字和闪电使用同一尺寸，调整这里会同步改变两者。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Toggle("根据状态改变圆弧颜色", isOn: $store.usesBatteryStatusColors)

                Text("低电量显示红色，省电模式显示黄色，连接电源或正在充电显示绿色。关闭后圆弧使用普通前景色，数字和闪电仍为白色。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Text("低电量阈值")
                    Spacer()
                    Text("\(Int(store.batteryCriticalThreshold))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: $store.batteryCriticalThreshold,
                    in: SettingsStore.batteryCriticalThresholdRange,
                    step: 1
                )
                .disabled(!store.usesBatteryStatusColors)
                .accessibilityLabel("低电量阈值")
                .accessibilityValue("\(Int(store.batteryCriticalThreshold))%")

                Text("低于该阈值时视为低电量，并使用红色。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

private struct IconSizePreview: View {
    let size: Double
    let options: BatteryIconOptions

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(nsImage: StatusIconRenderer.image(
            snapshot: .placeholder,
            size: size,
            options: options,
            appearance: appearance
        ))
        .frame(width: CGFloat(SettingsStore.iconSizeRange.upperBound))
        .accessibilityHidden(true)
    }

    private var appearance: NSAppearance {
        switch colorScheme {
        case .dark:
            NSAppearance(named: .darkAqua) ?? NSApp.effectiveAppearance
        default:
            NSAppearance(named: .aqua) ?? NSApp.effectiveAppearance
        }
    }
}
