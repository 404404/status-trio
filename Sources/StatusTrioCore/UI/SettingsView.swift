import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject private var updaterManager = UpdaterManager.shared
    @EnvironmentObject private var localization: Localization

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
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
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(localization.string(.settingsIconSize))
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
                .accessibilityLabel(localization.string(.settingsIconSize))
                .accessibilityValue(
                    localization.format(
                        .settingsIconSizeAccessibilityValue,
                        Int(store.iconSize)
                    )
                )
            }

            HStack(spacing: 12) {
                IconSizePreview(
                    size: store.iconSize,
                    options: store.batteryIconOptions
                )
                Text(localization.string(.settingsIconSizeDescription))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(localization.string(.settingsBatteryTitle))
                    .font(.headline)

                Toggle(
                    localization.string(.settingsBatteryShowPercentage),
                    isOn: $store.showsBatteryPercentage
                )
                Toggle(
                    localization.string(.settingsBatteryShowChargingIndicator),
                    isOn: $store.showsChargingIndicator
                )

                Text(localization.string(.settingsBatteryChargingDescription))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Text(localization.string(.settingsBatterySymbolScale))
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
                .accessibilityLabel(
                    localization.string(.settingsBatterySymbolScaleAccessibility)
                )
                .accessibilityValue("\(Int(store.batterySymbolScale * 100))%")

                Text(localization.string(.settingsBatterySymbolScaleDescription))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Toggle(
                    localization.string(.settingsBatteryStatusColors),
                    isOn: $store.usesBatteryStatusColors
                )

                Text(localization.string(.settingsBatteryStatusColorsDescription))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Text(localization.string(.settingsBatteryCriticalThreshold))
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
                .accessibilityLabel(
                    localization.string(.settingsBatteryCriticalThreshold)
                )
                .accessibilityValue("\(Int(store.batteryCriticalThreshold))%")

                Text(localization.string(.settingsBatteryCriticalThresholdDescription))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(localization.string(.settingsUpdatesTitle))
                    .font(.headline)

                Toggle(
                    localization.string(.settingsUpdatesAutomatic),
                    isOn: Binding(
                        get: { updaterManager.automaticallyChecksForUpdates },
                        set: { updaterManager.automaticallyChecksForUpdates = $0 }
                    )
                )
                .disabled(!updaterManager.canCheckForUpdates)

                Button(localization.string(.settingsUpdatesCheck)) {
                    updaterManager.checkForUpdates()
                }
                .disabled(!updaterManager.canCheckForUpdates)
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
