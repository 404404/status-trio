import Foundation
import IOBluetooth

private enum BluetoothWorkerResult: Sendable {
    case success([BluetoothDevice])
    case poweredOff
    case unavailable
    case failed
}

/// Reads only the operating system's paired-device database. It deliberately
/// does not perform a Bluetooth inquiry, so nearby BLE advertisements are not
/// represented as paired devices.
private final class IOBluetoothPairedDeviceWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "StatusTrio.IOBluetoothPairedDeviceWorker")

    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        queue.async {
            guard let controller = IOBluetoothHostController.default() else {
                completion(.unavailable)
                return
            }
            guard Int(controller.powerState) != 0 else {
                completion(.poweredOff)
                return
            }

            let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [])
                .compactMap { device -> BluetoothDevice? in
                    guard let identifier = device.addressString, !identifier.isEmpty else { return nil }
                    let name = device.nameOrAddress ?? identifier
                    return BluetoothDevice(
                        id: identifier,
                        name: name,
                        kind: kind(for: Int(device.deviceClassMajor)),
                        isConnected: device.isConnected()
                    )
                }
            completion(.success(devices))
        }
    }

    private func kind(for majorClass: Int) -> BluetoothDeviceKind {
        // Bluetooth Class-of-Device major values are defined by the Bluetooth
        // specification. Unknown/absent values stay generic rather than being
        // presented as a guessed device type.
        switch majorClass {
        case 0x01: .computer
        case 0x02: .phone
        case 0x04: .audio
        case 0x05: .peripheral
        default: .unknown
        }
    }
}

@MainActor
final class BluetoothDeviceController: ObservableObject {
    @Published private(set) var devices: [BluetoothDevice] = []
    @Published private(set) var availability: BluetoothAvailability = .idle

    private let worker = IOBluetoothPairedDeviceWorker()
    private var isActive = false
    private var requestGate = AsyncRequestGate()
    private var periodicRefreshTask: Task<Void, Never>?

    var connectedDevices: [BluetoothDevice] {
        BluetoothDevicePresentation.grouped(devices).connected
    }

    func activate() {
        guard !isActive else { return }
        isActive = true
        refresh()
        schedulePeriodicRefresh()
    }

    func deactivate() {
        isActive = false
         _ = requestGate.advance()
        periodicRefreshTask?.cancel()
        periodicRefreshTask = nil
    }

    func refresh() {
        guard isActive else { return }
        let requestGeneration = requestGate.advance()
        worker.read { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self,
                      self.isActive,
                      self.requestGate.accepts(requestGeneration) else { return }
                switch result {
                case .success(let devices):
                    self.devices = devices
                    self.availability = .available
                case .poweredOff:
                    self.devices = []
                    self.availability = .poweredOff
                case .unavailable:
                    self.devices = []
                    self.availability = .unavailable
                case .failed:
                    self.availability = .failed
                }
            }
        }
    }

    private func schedulePeriodicRefresh() {
        periodicRefreshTask?.cancel()
        periodicRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(20))
                } catch {
                    return
                }
                guard let self, self.isActive else { return }
                self.refresh()
            }
        }
    }
}
