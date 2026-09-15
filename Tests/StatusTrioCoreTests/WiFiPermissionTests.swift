import Testing
@testable import StatusTrioCore

@MainActor
struct WiFiPermissionTests {
    @Test func waitsForPermissionBeforeScanning() {
        let controller = WiFiNetworkController()
        controller.activate(nameAccess: .notDetermined)
        defer { controller.deactivate() }
        #expect(controller.state == .idle)
        #expect(controller.networks.isEmpty)
        controller.refresh()
        #expect(controller.state == .idle)
    }

    @Test(arguments: [WiFiNameAccess.denied, .restricted])
    func blockedPermissionDoesNotScan(access: WiFiNameAccess) {
        let controller = WiFiNetworkController()
        controller.activate(nameAccess: access)
        defer { controller.deactivate() }
        #expect(controller.state == .permissionDenied)
    }
}
