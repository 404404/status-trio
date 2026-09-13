import SwiftUI

struct WiFiStatusIcon: View {
    let wifi: WiFiStatus

    var body: some View {
        Image(nsImage: StatusIconRenderer.wifiImage(wifi: wifi, size: 18))
            .renderingMode(.template)
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .accessibilityLabel("Wi-Fi \(StatusPresentation.wifiValue(wifi))")
    }
}
