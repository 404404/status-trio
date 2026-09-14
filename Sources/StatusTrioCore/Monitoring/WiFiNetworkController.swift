import CoreWLAN
import Foundation
import SystemConfiguration

private struct WiFiScanPayload: Sendable {
    let networks: [WiFiNetwork]
    let details: WiFiConnectionDetails
}

private enum WiFiScanWorkerResult: Sendable {
    case success(WiFiScanPayload)
    case poweredOff
    case noInterface
    case failed
}

private enum WiFiAssociationWorkerResult: Sendable {
    case success(WiFiConnectionDetails)
    case networkUnavailable
    case timedOut
    case failed
}

/// CoreWLAN exposes synchronous scan and association APIs. This worker owns a
/// serial queue so those calls never run on the main actor and cannot overlap.
private final class CoreWLANNetworkWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "StatusTrio.CoreWLANNetworkWorker")

    func scan(completion: @escaping @Sendable (WiFiScanWorkerResult) -> Void) {
        queue.async { [self] in
            completion(scanSynchronously())
        }
    }

    func setPower(
        _ isOn: Bool,
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        queue.async {
            guard let interface = CWWiFiClient.shared().interface() else {
                completion(false)
                return
            }
            do {
                try interface.setPower(isOn)
                completion(true)
            } catch {
                completion(false)
            }
        }
    }

    func associate(
        to network: WiFiNetwork,
        password: String?,
        completion: @escaping @Sendable (WiFiAssociationWorkerResult) -> Void
    ) {
        queue.async { [self] in
            completion(associateSynchronously(to: network, password: password))
        }
    }

    private func scanSynchronously() -> WiFiScanWorkerResult {
        guard let interface = CWWiFiClient.shared().interface() else { return .noInterface }
        guard interface.powerOn() else { return .poweredOff }

        do {
            let rawNetworks = try interface.scanForNetworks(withSSID: nil)
            let associatedBSSID = interface.bssid()
            let candidates = rawNetworks.compactMap(projectCandidate)
            let actualNetwork = rawNetworks.first {
                bssid($0.bssid, matches: associatedBSSID)
            }
            return .success(
                WiFiScanPayload(
                    networks: WiFiNetwork.merge(candidates, connectedBSSID: associatedBSSID),
                    details: makeDetails(interface: interface, actualNetwork: actualNetwork)
                )
            )
        } catch {
            return .failed
        }
    }

    private func associateSynchronously(
        to selected: WiFiNetwork,
        password: String?
    ) -> WiFiAssociationWorkerResult {
        guard let interface = CWWiFiClient.shared().interface(), interface.powerOn() else {
            return .networkUnavailable
        }
        guard let targetBSSID = selected.preferredCandidate?.bssid else {
            return .networkUnavailable
        }

        do {
            let networks = try interface.scanForNetworks(withSSID: nil)
            guard let target = networks.first(where: {
                $0.ssid == selected.ssid
                    && securityKind(for: $0) == selected.security
                    && bssid($0.bssid, matches: targetBSSID)
            }) else {
                return .networkUnavailable
            }

            // Do not disassociate first: CoreWLAN is asked to associate directly
            // with the selected AP and macOS retains the prior association until
            // it has progressed the new request.
            try interface.associate(to: target, password: password)

            let deadline = Date().addingTimeInterval(12)
            while Date() < deadline {
                if bssid(interface.bssid(), matches: targetBSSID) {
                    return .success(makeDetails(interface: interface, actualNetwork: target))
                }
                Thread.sleep(forTimeInterval: 0.25)
            }
            return .timedOut
        } catch {
            // CoreWLAN does not provide a stable public error taxonomy for all
            // authentication failures, so do not guess that this was a bad
            // password. The UI presents an accurate generic failure instead.
            return .failed
        }
    }

    private func securityKind(for network: CWNetwork) -> WiFiSecurityKind {
        let preferredKinds: [(CWSecurity, WiFiSecurityKind)] = [
            (.wpa3Transition, .wpa3Transition),
            (.wpa3Enterprise, .wpa3Enterprise),
            (.wpa3Personal, .wpa3Personal),
            (.oweTransition, .oweTransition),
            (.OWE, .owe),
            (.wpa2Enterprise, .wpa2Enterprise),
            (.wpaEnterpriseMixed, .wpaEnterpriseMixed),
            (.wpaEnterprise, .wpaEnterprise),
            (.enterprise, .enterprise),
            (.wpa2Personal, .wpa2Personal),
            (.wpaPersonalMixed, .wpaPersonalMixed),
            (.wpaPersonal, .wpaPersonal),
            (.personal, .personal),
            (.dynamicWEP, .dynamicWEP),
            (.WEP, .wep),
            (.none, .open)
        ]
        return preferredKinds.first { network.supportsSecurity($0.0) }?.1 ?? .unknown
    }

    private func projectCandidate(_ network: CWNetwork) -> WiFiNetworkCandidate? {
        guard let ssid = network.ssid else { return nil }
        return WiFiNetworkCandidate(
            ssid: ssid,
            bssid: network.bssid,
            rssi: normalizedMeasurement(network.rssiValue),
            channel: network.wlanChannel?.channelNumber,
            security: securityKind(for: network)
        )
    }

    private func makeDetails(
        interface: CWInterface,
        actualNetwork: CWNetwork?
    ) -> WiFiConnectionDetails {
        let interfaceName = interface.interfaceName
        let ipv4 = interfaceName.flatMap { networkConfiguration(interface: $0, family: "IPv4") } ?? [:]
        let ipv6 = interfaceName.flatMap { networkConfiguration(interface: $0, family: "IPv6") } ?? [:]
        let dns = interfaceName.flatMap { networkConfiguration(interface: $0, family: "DNS") } ?? [:]
        let channel = interface.wlanChannel()
        let transmitRate = interface.transmitRate()

        return WiFiConnectionDetails(
            ssid: interface.ssid(),
            bssid: interface.bssid(),
            band: displayBand(channel?.channelBand.rawValue),
            channel: channel?.channelNumber,
            channelWidth: displayChannelWidth(channel?.channelWidth.rawValue),
            rssi: normalizedMeasurement(interface.rssiValue()),
            noise: actualNetwork.flatMap { normalizedMeasurement($0.noiseMeasurement) },
            phyMode: displayPHY(interface.activePHYMode().rawValue),
            transmitRateMbps: transmitRate.isFinite && transmitRate > 0 ? transmitRate : nil,
            security: WiFiSecurityKind(coreWLANRawValue: interface.security().rawValue),
            countryCode: actualNetwork?.countryCode,
            interfaceName: interfaceName,
            ipv4Addresses: stringValues(in: ipv4, key: "Addresses"),
            ipv6Addresses: stringValues(in: ipv6, key: "Addresses"),
            router: stringValues(in: ipv4, key: "Router").first,
            dnsServers: stringValues(in: dns, key: "ServerAddresses")
        )
    }

    private func networkConfiguration(interface: String, family: String) -> [String: Any] {
        guard let store = SCDynamicStoreCreate(nil, "StatusTrio" as CFString, nil, nil),
              let value = SCDynamicStoreCopyValue(
                store,
                "State:/Network/Interface/\(interface)/\(family)" as CFString
              ) as? [String: Any] else {
            return [:]
        }
        return value
    }

    private func stringValues(in dictionary: [String: Any], key: String) -> [String] {
        if let values = dictionary[key] as? [String] { return values }
        if let value = dictionary[key] as? String { return [value] }
        return []
    }

    private func normalizedMeasurement(_ value: Int) -> Int? {
        value < 0 ? value : nil
    }

    private func bssid(_ lhs: String?, matches rhs: String?) -> Bool {
        guard let lhs, let rhs else { return false }
        return lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }

    private func displayBand(_ rawValue: Int?) -> String? {
        guard let rawValue else { return nil }
        return switch rawValue {
        case 1: "2.4 GHz"
        case 2: "5 GHz"
        case 3: "6 GHz"
        default: nil
        }
    }

    private func displayChannelWidth(_ rawValue: Int?) -> String? {
        guard let rawValue else { return nil }
        return switch rawValue {
        case 1: "20 MHz"
        case 2: "40 MHz"
        case 3: "80 MHz"
        case 4: "160 MHz"
        default: nil
        }
    }

    private func displayPHY(_ rawValue: Int) -> String? {
        return switch rawValue {
        case 1: "802.11a"
        case 2: "802.11b"
        case 3: "802.11g"
        case 4: "802.11n"
        case 5: "802.11ac"
        case 6: "802.11ax"
        default: nil
        }
    }
}

@MainActor
final class WiFiNetworkController: ObservableObject {
    @Published private(set) var networks: [WiFiNetwork] = []
    @Published private(set) var details = WiFiConnectionDetails.unavailable
    @Published private(set) var state: WiFiListState = .idle

    private let worker: CoreWLANNetworkWorker
    private let passwordStore: any WiFiPasswordStoring
    private var requestGate = AsyncRequestGate()
    private var isActive = false
    private var periodicRefreshTask: Task<Void, Never>?
    private var lastNameAccess: WiFiNameAccess = .notDetermined

    init(
        passwordStore: any WiFiPasswordStoring = KeychainWiFiPasswordStore()
    ) {
        worker = CoreWLANNetworkWorker()
        self.passwordStore = passwordStore
    }

    deinit {
        periodicRefreshTask?.cancel()
    }

    func activate(nameAccess: WiFiNameAccess) {
        lastNameAccess = nameAccess
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
        if case .connecting(_) = state {
            state = .idle
        }
    }

    func refresh(nameAccess: WiFiNameAccess? = nil) {
        if let nameAccess { lastNameAccess = nameAccess }
        guard isActive, !state.isScanning else { return }
        let requestGeneration = requestGate.advance()
        state = .scanning
        worker.scan { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self,
                      self.isActive,
                      self.requestGate.accepts(requestGeneration) else { return }
                self.receive(result)
            }
        }
    }

    func setPower(_ isOn: Bool) {
        guard isActive else { return }
        let requestGeneration = requestGate.advance()
        worker.setPower(isOn) { [weak self] changed in
            Task { @MainActor [weak self] in
                guard let self,
                      self.isActive,
                      self.requestGate.accepts(requestGeneration) else { return }
                if changed {
                    self.refresh()
                } else {
                    self.state = .failed
                }
            }
        }
    }

    func connect(
        to network: WiFiNetwork,
        password: String?,
        rememberPassword: Bool
    ) {
        guard isActive else { return }
        guard !network.security.isEnterprise else {
            state = .enterpriseNetwork
            return
        }
        let suppliedPassword = password?.isEmpty == false ? password : nil
        let passwordToUse = suppliedPassword ?? passwordStore.password(for: network.identity)
        guard !network.security.requiresPassword || passwordToUse != nil else {
            state = .connectionFailed
            return
        }

        let requestGeneration = requestGate.advance()
        state = .connecting(network.identity)
        worker.associate(to: network, password: passwordToUse) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self,
                      self.isActive,
                      self.requestGate.accepts(requestGeneration) else { return }

                switch result {
                case .success(let details):
                    self.details = details
                    self.state = .ready
                    if rememberPassword, let suppliedPassword {
                        self.passwordStore.save(suppliedPassword, for: network.identity)
                    }
                    self.refresh()
                case .networkUnavailable:
                    self.state = .networkUnavailable
                case .timedOut:
                    self.state = .connectionTimedOut
                case .failed:
                    self.state = .connectionFailed
                }
            }
        }
    }

    private func receive(_ result: WiFiScanWorkerResult) {
        switch result {
        case .success(let payload):
            networks = payload.networks
            details = payload.details
            if payload.networks.isEmpty,
               lastNameAccess == .denied || lastNameAccess == .restricted {
                state = .permissionDenied
            } else {
                state = .ready
            }
        case .poweredOff:
            networks = []
            details = .unavailable
            state = .poweredOff
        case .noInterface:
            networks = []
            details = .unavailable
            state = .noInterface
        case .failed:
            // A failed scan is intentionally distinct from an empty successful
            // result so a privacy/permission problem is never shown as "none".
            state = lastNameAccess == .denied || lastNameAccess == .restricted
                ? .permissionDenied
                : .failed
        }
    }

    private func schedulePeriodicRefresh() {
        periodicRefreshTask?.cancel()
        periodicRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    return
                }
                guard let self, self.isActive else { return }
                self.refresh()
            }
        }
    }
}
