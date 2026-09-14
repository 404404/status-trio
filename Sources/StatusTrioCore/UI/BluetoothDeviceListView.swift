import SwiftUI

struct BluetoothStatusView: View {
    @ObservedObject var controller: BluetoothDeviceController
    @EnvironmentObject private var localization: Localization
    let onOpenDetails: () -> Void
    let onOpenBluetoothSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpenDetails) {
                HStack(spacing: 10) {
                    Image(systemName: "bluetooth")
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localization.string(.bluetoothTitle))
                            .font(.headline)
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(localization.string(.bluetoothTitle)), \(summary)")

            Button(localization.string(.bluetoothActionOpenSettings), systemImage: "gearshape", action: onOpenBluetoothSettings)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(localization.string(.bluetoothActionOpenSettings))
                .frame(width: 24, height: 24)
        }
    }

    private var summary: String {
        switch controller.availability {
        case .idle:
            localization.string(.bluetoothUnavailable)
        case .available:
            let devices = controller.connectedDevices
            if devices.isEmpty { return localization.string(.bluetoothNoConnectedDevices) }
            return devices.map(\.name).joined(separator: ", ")
        case .poweredOff:
            localization.string(.bluetoothOff)
        case .unavailable:
            localization.string(.bluetoothUnavailable)
        case .failed:
            localization.string(.bluetoothReadFailed)
        }
    }
}

struct BluetoothDeviceListView: View {
    @ObservedObject var controller: BluetoothDeviceController
    @EnvironmentObject private var localization: Localization
    let onBack: () -> Void
    let onOpenBluetoothSettings: () -> Void

    var body: some View {
        let groups = BluetoothDevicePresentation.grouped(controller.devices)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button(action: onBack) {
                    Image(systemName: "chevron.backward")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(localization.string(.commonBack))
                Text(localization.string(.bluetoothTitle))
                    .font(.headline)
                Spacer()
                Button(action: { controller.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(localization.string(.bluetoothRefresh))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !groups.connected.isEmpty {
                        section(localization.string(.bluetoothConnected), devices: groups.connected)
                    }
                    if !groups.disconnected.isEmpty {
                        section(localization.string(.bluetoothNotConnected), devices: groups.disconnected)
                    }
                    message
                    Text(localization.string(.bluetoothPairedDeviceLimit))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxHeight: 330)

            Divider()
            Button(localization.string(.bluetoothActionOpenSettings), action: onOpenBluetoothSettings)
                .buttonStyle(.plain)
        }
        .onAppear { controller.activate() }
    }

    private func section(_ title: String, devices: [BluetoothDevice]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(devices) { device in
                HStack(spacing: 10) {
                    Image(systemName: icon(for: device.kind))
                        .frame(width: 16)
                        .foregroundStyle(.secondary)
                    Text(device.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Text(device.isConnected ? localization.string(.bluetoothConnected) : localization.string(.bluetoothNotConnected))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder
    private var message: some View {
        switch controller.availability {
        case .idle:
            ProgressView()
        case .available where controller.devices.isEmpty:
            Text(localization.string(.bluetoothNoDevices))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .poweredOff:
            Text(localization.string(.bluetoothOff))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .unavailable:
            Text(localization.string(.bluetoothUnavailable))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed:
            Text(localization.string(.bluetoothReadFailed))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .available:
            EmptyView()
        }
    }

    private func icon(for kind: BluetoothDeviceKind) -> String {
        switch kind {
        case .computer: "laptopcomputer"
        case .phone: "iphone"
        case .audio: "headphones"
        case .peripheral: "computermouse"
        case .unknown: "bluetooth"
        }
    }
}
