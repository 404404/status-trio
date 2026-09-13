import SwiftUI

struct BatterySettingsPane: View {
    @ObservedObject var store: SettingsStore
    @EnvironmentObject private var localization: Localization

    var body: some View {
        PreferencesPane {
            PreferenceCheckboxRow(
                label: .settingsBatteryShowPercentage,
                isOn: $store.showsBatteryPercentage
            )

            PreferenceCheckboxRow(
                label: .settingsBatteryShowChargingIndicator,
                description: .settingsBatteryChargingDescription,
                isOn: $store.showsChargingIndicator
            )

            Divider()

            PreferenceRow(label: .settingsBatterySymbolScale) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 12) {
                        Slider(
                            value: $store.batterySymbolScale,
                            in: SettingsStore.batterySymbolScaleRange,
                            step: 0.05
                        )
                        .disabled(!store.isBatterySymbolSizeEnabled)
                        .accessibilityLabel(
                            localization.string(.settingsBatterySymbolScaleAccessibility)
                        )
                        .accessibilityValue("\(Int(store.batterySymbolScale * 100))%")

                        Text("\(Int(store.batterySymbolScale * 100))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }

                    Text(localization.string(.settingsBatterySymbolScaleDescription))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            PreferenceCheckboxRow(
                label: .settingsBatteryStatusColors,
                description: .settingsBatteryStatusColorsDescription,
                isOn: $store.usesBatteryStatusColors
            )

            PreferenceRow(
                label: .settingsBatteryCriticalThreshold,
                description: .settingsBatteryCriticalThresholdDescription
            ) {
                HStack(spacing: 12) {
                    Slider(
                        value: $store.batteryCriticalThreshold,
                        in: SettingsStore.batteryCriticalThresholdRange,
                        step: 1
                    )
                    .disabled(!store.usesBatteryStatusColors)
                    .accessibilityLabel(
                        localization.string(.settingsBatteryCriticalThreshold)
                    )
                    .accessibilityValue("\(Int(store.batteryCriticalThreshold))%")

                    Text("\(Int(store.batteryCriticalThreshold))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }
            }
        }
    }
}
