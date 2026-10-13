import Foundation
import Security

/// A random ID for this app install, used for the one-phone-per-account rule.
///
/// Kept in the Keychain so it survives reinstalling the app, and stored "this device
/// only" so restoring a backup onto a new phone doesn't carry it over.
struct DeviceIdentity {
    var service = "com.abhaysingh.pawdone.device-id"

    func id() -> String {
        if let existing = read() {
            return existing
        }
        let id = UUID().uuidString.lowercased()
        save(id)
        return id
    }

    /// Deletes the stored ID. Used by tests.
    func reset() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "device-id",
        ]
    }

    private func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func save(_ id: String) {
        var attributes = baseQuery
        attributes[kSecValueData as String] = Data(id.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
