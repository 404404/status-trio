import AppKit
import SwiftUI

struct IconSizePreview: View {
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
