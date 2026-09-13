import SwiftUI

struct WiFiStatusIcon: View {
    let wifi: WiFiStatus

    var body: some View {
        Image(nsImage: StatusIconRenderer.wifiImage(wifi: wifi, size: 22))
            .renderingMode(.template)
            .foregroundStyle(iconColor)
            .frame(width: 24, height: 24)
            .accessibilityLabel("Wi-Fi \(StatusPresentation.wifiValue(wifi))")
    }

    private var iconColor: Color {
        switch wifi.state {
        case .connected:
            .primary
        case .noInternet, .temporary:
            .orange
        case .hotspot, .shared:
            .accentColor
        case .notAssociated, .off, .unavailable:
            .secondary
        }
    }
}
