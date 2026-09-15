import Foundation
import Security

protocol WiFiCredentialStoring: AnyObject {
    /// Resolves a credential only for a user-selected network. Callers must
    /// never invoke this while scanning nearby networks.
    func resolveCredential(for identity: WiFiNetworkIdentity) -> WiFiCredentialResult
    /// Returns false on a Keychain write failure so the UI can report that the
    /// connection succeeded but the requested remembered-password save did not.
    func save(_ password: String, for identity: WiFiNetworkIdentity) -> Bool
}

/// Reads two deliberately separate credential namespaces on demand:
///
/// - the app-owned generic-password item for passwords the user chose to
///   remember in Status Trio; and
/// - the user Keychain standard `AirPort network password` item for a
///   personal SSID, when the user has authorized access to that system item.
///
/// CoreWLAN does not provide a public API to enumerate saved passwords, and
/// `associate(password: nil)` is not treated as credential reuse. The system
/// Keychain lookup is therefore attempted only after a click and its
/// cancellation, denial, locked-keychain, and read errors remain distinct.
final class KeychainWiFiPasswordStore: WiFiCredentialStoring, @unchecked Sendable {
    private let appService = "io.github.404404.StatusTrio.wifi-password"
    private let systemAirPortService = "AirPort network password"

    func resolveCredential(for identity: WiFiNetworkIdentity) -> WiFiCredentialResult {
        let appResult = read(
            query: appQuery(for: identity, authenticationUI: kSecUseAuthenticationUIFail),
            source: .appKeychain
        )
        switch appResult {
        case .credential, .issue:
            return appResult
        case .noCredential:
            return read(
                query: systemAirPortQuery(for: identity),
                source: .systemKeychain
            )
        }
    }

    func save(_ password: String, for identity: WiFiNetworkIdentity) -> Bool {
        guard !password.isEmpty else { return false }
        let data = Data(password.utf8)
        let query = appQuery(for: identity, authenticationUI: kSecUseAuthenticationUIFail)
        let update = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }

        var newItem = query
        newItem[kSecValueData as String] = data
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(newItem as CFDictionary, nil)
        if addStatus == errSecSuccess { return true }
        if addStatus == errSecDuplicateItem {
            return SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecSuccess
        }
        return false
    }

    private func read(
        query: [String: Any],
        source: WiFiCredentialSource
    ) -> WiFiCredentialResult {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let password = String(data: data, encoding: .utf8),
                  !password.isEmpty else {
                return .issue(.readFailed)
            }
            return .credential(password, source)
        case errSecItemNotFound:
            return .noCredential
        case errSecUserCanceled:
            return .issue(.cancelled)
        case errSecAuthFailed:
            return .issue(.accessDenied)
        case errSecInteractionNotAllowed, errSecNotAvailable:
            return .issue(.keychainLocked)
        default:
            return .issue(.readFailed)
        }
    }

    private func appQuery(
        for identity: WiFiNetworkIdentity,
        authenticationUI: CFString
    ) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: appService,
            // Delimiters preserve the raw SSID, including whitespace, and keep
            // security classes distinct without writing credentials elsewhere.
            kSecAttrAccount as String: "\(identity.security.rawValue):\(identity.ssid)",
            kSecUseAuthenticationUI as String: authenticationUI,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
    }

    private func systemAirPortQuery(for identity: WiFiNetworkIdentity) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: systemAirPortService,
            kSecAttrAccount as String: identity.ssid,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIAllow,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
    }
}
