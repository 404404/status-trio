import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
                IconSizePreview(size: store.iconSize)
                Text("调整菜单栏图标的渲染尺寸，可选 20–28 pt。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}

private struct IconSizePreview: View {
    let size: Double

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(nsImage: StatusIconRenderer.image(
            snapshot: .placeholder,
            size: size,
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
