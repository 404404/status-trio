import SwiftUI

struct WiFiStatusView: View {
    let wifi: WiFiStatus
    let onRequestNameAccess: () -> Void
    let onOpenWiFiSettings: () -> Void
    let onOpenLocationSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi")
                .frame(width: 24)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Wi-Fi")
                    .font(.headline)

                subtitle
            }

            Spacer()

            Text(StatusPresentation.wifiValue(wifi))
                .font(.body.monospacedDigit().weight(.semibold))

            Button(
                StatusPresentation.openWiFiSettingsAction,
                systemImage: "gearshape",
                action: onOpenWiFiSettings
            )
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(StatusPresentation.openWiFiSettingsAction)
            .frame(width: 24, height: 24)
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        if let ssid = wifi.ssid, !ssid.isEmpty {
            Text(ssid)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        } else if wifi.state.isNetworkAssociated && wifi.nameAccess == .notDetermined {
            Button(StatusPresentation.requestWiFiNameAction, action: onRequestNameAccess)
                .buttonStyle(.link)
                .font(.caption)
                .lineLimit(1)
        } else if wifi.state.isNetworkAssociated
                    && (wifi.nameAccess == .denied || wifi.nameAccess == .restricted) {
            Button(StatusPresentation.openLocationSettingsAction, action: onOpenLocationSettings)
                .buttonStyle(.link)
                .font(.caption)
                .lineLimit(1)
        } else {
            Text(StatusPresentation.wifiSubtitle(wifi))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
