import Foundation
import Security

@MainActor
protocol WiFiPasswordStoring: AnyObject {
    func password(for identity: WiFiNetworkIdentity) -> String?
    func save(_ password: String, for identity: WiFiNetworkIdentity)
}

/// Stores only user-selected remembered personal-network passwords. It never
/// tries to discover or reuse macOS's own saved network credentials.
@MainActor
final class KeychainWiFiPasswordStore: WiFiPasswordStoring {
    private let service = "io.github.404404.StatusTrio.wifi-password"

    func password(for identity: WiFiNetworkIdentity) -> String? {
        var query = baseQuery(for: identity)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    func save(_ password: String, for identity: WiFiNetworkIdentity) {
        guard !password.isEmpty else { return }
        let data = Data(password.utf8)
        let query = baseQuery(for: identity)
        let update = [kSecValueData as String: data]
        let result = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if result == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            _ = SecItemAdd(newItem as CFDictionary, nil)
        }
    }

    private func baseQuery(for identity: WiFiNetworkIdentity) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            // Delimiters make the raw SSID and security value unambiguous while
            // preserving every SSID character (including whitespace).
            kSecAttrAccount as String: "\(identity.security.rawValue):\(identity.ssid)"
        ]
    }
}
