import Auth
import Foundation
import Security

/// Stores the Supabase session in the Keychain with `AfterFirstUnlockThisDeviceOnly`:
/// the token never leaves this device (no iCloud Keychain sync, not restored onto another phone).
/// The SDK default (`AfterFirstUnlock`) would migrate it through encrypted backups.
struct KeychainSessionStorage: AuthLocalStorage {
    private let service: String

    init(service: String) {
        self.service = service
    }

    func store(key: String, value: Data) throws {
        let query = baseQuery(key: key)
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            let attributes: [String: Any] = [
                kSecValueData as String: value,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ]
            try check(SecItemUpdate(query as CFDictionary, attributes as CFDictionary))
        case errSecItemNotFound:
            var item = query
            item[kSecValueData as String] = value
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            try check(SecItemAdd(item as CFDictionary, nil))
        default:
            throw KeychainError(status: status)
        }
    }

    func retrieve(key: String) throws -> Data? {
        var query = baseQuery(key: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        return result as? Data
    }

    func remove(key: String) throws {
        let status = SecItemDelete(baseQuery(key: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private func baseQuery(key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }
}

struct KeychainError: Error, CustomStringConvertible {
    let status: OSStatus

    var description: String { "Keychain error \(status)" }
}
