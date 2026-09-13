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
