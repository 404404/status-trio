import SwiftUI

struct OutputDeviceList: View {
    @EnvironmentObject private var localization: Localization
    let devices: [AudioOutputDevice]
    let onSelect: (AudioOutputDevice) -> Void

    var body: some View {
        if devices.isEmpty {
            Label(localization.string(.volumeOutputEmpty), systemImage: "questionmark.circle")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        } else if devices.count > 4 {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(devices) { device in
                        OutputDeviceRow(device: device, onSelect: onSelect)
                    }
                }
            }
            .frame(height: 142)
        } else {
            LazyVStack(spacing: 2) {
                ForEach(devices) { device in
                    OutputDeviceRow(device: device, onSelect: onSelect)
                }
            }
        }
    }
}
