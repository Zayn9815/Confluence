import Foundation
import Security

public enum SecretKey: String, Sendable, CaseIterable {
    case geminiAPIKey = "com.bilal.confluence.secret.gemini"
    case twelveDataAPIKey = "com.bilal.confluence.secret.twelvedata"
    case finnhubAPIKey = "com.bilal.confluence.secret.finnhub"
}

/// Zero-dependency Swift 6 `Sendable` actor wrapping Apple's native `Security.framework` Keychain.
/// Replaces unmaintained KeychainAccess (which carries SPM `.unsafeFlags` blockers).
/// Uses `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` so optional API keys remain encrypted on device
/// and accessible during `BGAppRefreshTask` without ever leaving the device or hitting logs.
public actor KeychainStore {
    public static let shared = KeychainStore()
    private let service = "com.bilal.confluence.keychain"

    public init() {}

    public func save(_ value: String, for key: SecretKey) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try delete(key)
            return
        }
        guard let data = trimmed.data(using: .utf8) else { return }

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]

        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributesToUpdate as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.osStatus(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.osStatus(updateStatus)
        }
    }

    public func read(_ key: SecretKey) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func delete(_ key: SecretKey) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.osStatus(status)
        }
    }

    public func hasValue(for key: SecretKey) -> Bool {
        if let v = read(key), !v.isEmpty {
            return true
        }
        return false
    }
}

public enum KeychainError: Error, LocalizedError, Sendable {
    case osStatus(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .osStatus(let code):
            return "Keychain error (OSStatus \(code))"
        }
    }
}
