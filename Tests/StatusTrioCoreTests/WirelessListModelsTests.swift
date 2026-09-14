import XCTest
@testable import StatusTrioCore

final class WirelessListModelsTests: XCTestCase {
    func testWiFiMergePreservesWhitespaceInSSIDIdentity() {
        let candidates = [
            WiFiNetworkCandidate(
                ssid: " Studio ",
                bssid: "00:00:00:00:00:01",
                rssi: -70,
                channel: 1,
                security: .wpa2Personal
            ),
            WiFiNetworkCandidate(
                ssid: "Studio",
                bssid: "00:00:00:00:00:02",
                rssi: -40,
                channel: 1,
                security: .wpa2Personal
            )
        ]

        let merged = WiFiNetwork.merge(candidates, connectedBSSID: nil)

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(Set(merged.map(\.ssid)), [" Studio ", "Studio"])
    }

    func testWiFiMergeNeverMixesDifferentSecurityTypes() {
        let candidates = [
            WiFiNetworkCandidate(ssid: "Office", bssid: "01", rssi: -45, channel: 44, security: .wpa2Personal),
            WiFiNetworkCandidate(ssid: "Office", bssid: "02", rssi: -50, channel: 44, security: .wpa3Personal)
        ]

        let merged = WiFiNetwork.merge(candidates, connectedBSSID: nil)

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(Set(merged.map(\.security)), [.wpa2Personal, .wpa3Personal])
    }

    func testCoreWLANSecurityRawValuesPreserveOpenAndWPA3Identity() {
        XCTAssertEqual(WiFiSecurityKind(coreWLANRawValue: 0), .open)
        XCTAssertEqual(WiFiSecurityKind(coreWLANRawValue: 4), .wpa2Personal)
        XCTAssertEqual(WiFiSecurityKind(coreWLANRawValue: 13), .wpa3Transition)
        XCTAssertEqual(WiFiSecurityKind(coreWLANRawValue: 14), .owe)
        XCTAssertEqual(WiFiSecurityKind(coreWLANRawValue: Int.max), .unknown)
    }

    func testCurrentBSSIDWinsOverStrongestCandidateForConnectedState() {
        let candidates = [
            WiFiNetworkCandidate(ssid: "Studio", bssid: "01", rssi: -35, channel: 149, security: .wpa2Personal),
            WiFiNetworkCandidate(ssid: "Studio", bssid: "02", rssi: -68, channel: 36, security: .wpa2Personal)
        ]

        let network = try! XCTUnwrap(WiFiNetwork.merge(candidates, connectedBSSID: "02").first)

        XCTAssertTrue(network.isConnected)
        XCTAssertEqual(network.preferredCandidate?.bssid, "01")
        XCTAssertEqual(network.connectedBSSID, "02")
    }

    func testAsyncRequestGateRejectsLateResults() {
        var gate = AsyncRequestGate()
        let firstRequest = gate.advance()
        let currentRequest = gate.advance()

        XCTAssertFalse(gate.accepts(firstRequest))
        XCTAssertTrue(gate.accepts(currentRequest))
    }

    func testConnectionAndAvailabilityStatesRemainExplicit() {
        let identity = WiFiNetworkIdentity(ssid: "Office", security: .wpa3Personal)

        XCTAssertEqual(WiFiListState.connecting(identity), .connecting(identity))
        XCTAssertNotEqual(WiFiListState.connectionFailed, .connectionTimedOut)
        XCTAssertNotEqual(BluetoothAvailability.poweredOff, .unavailable)
    }

    func testSignalToNoiseRatioRejectsInvalidMeasurements() {
        let valid = makeDetails(rssi: -48, noise: -92)
        let unavailableRSSI = makeDetails(rssi: nil, noise: -92)
        let misleadingNoise = makeDetails(rssi: -48, noise: -20)

        XCTAssertEqual(valid.signalToNoiseRatio, 44)
        XCTAssertNil(unavailableRSSI.signalToNoiseRatio)
        XCTAssertNil(misleadingNoise.signalToNoiseRatio)
    }

    func testBluetoothGroupingKeepsConnectedDevicesFirst() {
        let devices = [
            BluetoothDevice(id: "1", name: "Zebra", kind: .audio, isConnected: false),
            BluetoothDevice(id: "2", name: "Alpha", kind: .computer, isConnected: true),
            BluetoothDevice(id: "3", name: "Bravo", kind: .phone, isConnected: true)
        ]

        let grouped = BluetoothDevicePresentation.grouped(devices)

        XCTAssertEqual(grouped.connected.map(\.name), ["Alpha", "Bravo"])
        XCTAssertEqual(grouped.disconnected.map(\.name), ["Zebra"])
    }

    private func makeDetails(rssi: Int?, noise: Int?) -> WiFiConnectionDetails {
        WiFiConnectionDetails(
            ssid: "Studio",
            bssid: "01",
            band: nil,
            channel: nil,
            channelWidth: nil,
            rssi: rssi,
            noise: noise,
            phyMode: nil,
            transmitRateMbps: nil,
            security: .wpa2Personal,
            countryCode: nil,
            interfaceName: nil,
            ipv4Addresses: [],
            ipv6Addresses: [],
            router: nil,
            dnsServers: []
        )
    }
}
