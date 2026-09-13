import SwiftUI

struct VolumeControlsView: View {
    let volume: VolumeStatus
    let isEnabled: Bool
    let onVolumeChange: (Double) -> Void
    let onToggleMute: () -> Void
    let onSelectOutputDevice: (AudioOutputDevice) -> Void
    let onOpenSoundSettings: () -> Void

    @State private var draftVolume = 0.0
    @State private var isAdjusting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("系统音量")
                    .font(.headline.weight(.semibold))

                Spacer()

                Button(
                    StatusPresentation.openSoundSettingsAction,
                    systemImage: "gearshape",
                    action: onOpenSoundSettings
                )
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(StatusPresentation.openSoundSettingsAction)
                .accessibilityLabel(StatusPresentation.openSoundSettingsAction)
                .frame(width: 24, height: 24)
            }

            HStack(spacing: 10) {
                Button(
                    volume.isMuted ? "取消静音" : "静音",
                    systemImage: volume.isMuted ? "speaker.slash.fill" : "speaker.fill",
                    action: onToggleMute
                )
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(volume.isMuted ? Color.red : Color.secondary)
                .help(volume.isMuted ? "取消静音" : "静音")
                .disabled(!isEnabled)
                .frame(width: 24)

                Slider(
                    value: $draftVolume,
                    in: 0...1,
                    onEditingChanged: handleVolumeEditing
                )
                .tint(volume.isMuted ? Color.secondary : Color.accentColor)
                .disabled(!isEnabled)
                .accessibilityLabel("音量")
                .accessibilityValue(percentageText)

                Image(systemName: "speaker.wave.3.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text(percentageText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .trailing)
            }

            Divider()

            Text("输出")
                .font(.headline.weight(.semibold))

            OutputDeviceList(
                devices: volume.outputDevices,
                onSelect: onSelectOutputDevice
            )
        }
        .onAppear(perform: synchronizeVolume)
        .onChange(of: draftVolume) { _, newValue in
            updateVolume(newValue)
        }
        .onChange(of: volume.scalar) { _, _ in
            guard !isAdjusting else { return }
            synchronizeVolume()
        }
    }

    private var percentageText: String {
        guard draftVolume.isFinite else { return "—" }
        return "\(Int((min(1, max(0, draftVolume)) * 100).rounded()))%"
    }

    private func handleVolumeEditing(_ isEditing: Bool) {
        isAdjusting = isEditing
    }

    private func updateVolume(_ newValue: Double) {
        let scalar = volume.scalar ?? -1
        guard scalar.isFinite,
              abs(newValue - min(1, max(0, scalar))) >= 0.0005 else {
            return
        }
        onVolumeChange(newValue)
    }

    private func synchronizeVolume() {
        guard let scalar = volume.scalar, scalar.isFinite else {
            draftVolume = 0
            return
        }
        draftVolume = min(1, max(0, scalar))
    }
}
