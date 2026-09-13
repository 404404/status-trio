import SwiftUI

struct SettingsDetailView: View {
    let tab: SettingsTab
    @ObservedObject var store: SettingsStore
    @EnvironmentObject private var localization: Localization

    @ViewBuilder
    var body: some View {
        switch tab {
        case .basics:
            BasicsSettingsPane(localization: localization)
        case .menuBar:
            MenuBarSettingsPane(store: store)
        case .battery:
            BatterySettingsPane(store: store)
        case .about:
            AboutSettingsPane()
        }
    }
}
