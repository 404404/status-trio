import CoreLocation

@MainActor
protocol WiFiNameAuthorizing: AnyObject {
    var access: WiFiNameAccess { get }
    var onAccessChange: (() -> Void)? { get set }

    func requestAccess()
}

@MainActor
final class CoreLocationWiFiNameAuthorizer: NSObject, WiFiNameAuthorizing {
    private let manager: CLLocationManager

    var onAccessChange: (() -> Void)?

    init(manager: CLLocationManager = CLLocationManager()) {
        self.manager = manager
        super.init()
        manager.delegate = self
    }

    var access: WiFiNameAccess {
        Self.map(manager.authorizationStatus)
    }

    func requestAccess() {
        guard access == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    private static func map(_ status: CLAuthorizationStatus) -> WiFiNameAccess {
        switch status {
        case .notDetermined:
            .notDetermined
        case .authorizedAlways, .authorizedWhenInUse:
            .authorized
        case .denied:
            .denied
        case .restricted:
            .restricted
        @unknown default:
            .restricted
        }
    }
}

extension CoreLocationWiFiNameAuthorizer: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            self?.onAccessChange?()
        }
    }
}
