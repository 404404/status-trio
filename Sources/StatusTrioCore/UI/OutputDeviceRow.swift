import SwiftUI

struct OutputDeviceRow: View {
    let device: AudioOutputDevice
    let onSelect: (AudioOutputDevice) -> Void

    var body: some View {
        Button {
            onSelect(device)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(device.isCurrent ? Color.accentColor : Color.secondary.opacity(0.14))

                    Image(systemName: device.isCurrent ? "hifispeaker.fill" : "hifispeaker")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(device.isCurrent ? Color.white : Color.secondary)
                }
                .frame(width: 28, height: 28)

                Text(device.name)
                    .font(.body.weight(device.isCurrent ? .semibold : .regular))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let volume = device.volume, volume.isFinite {
                    Text(volume.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(device.isCurrent ? "当前输出设备" : "切换到 \(device.name)")
        .accessibilityValue(device.isCurrent ? "当前输出设备" : "")
    }
}
