import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case basics
    case menuBar
    case battery
    case updates
    case about

    var id: Self { self }

    var titleKey: LocalizationKey {
        switch self {
        case .basics: .settingsTabBasics
        case .menuBar: .settingsTabMenuBar
        case .battery: .settingsTabBattery
        case .updates: .settingsUpdatesTitle
        case .about: .settingsTabAbout
        }
    }

    var systemImage: String {
        switch self {
        case .basics: "gearshape"
        case .menuBar: "menubar.rectangle"
        case .battery: "battery.100percent"
        case .updates: "arrow.triangle.2.circlepath"
        case .about: "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .basics: .blue
        case .menuBar: .indigo
        case .battery: .green
        case .updates: .orange
        case .about: .gray
        }
    }
}
