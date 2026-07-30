import CryptoKit
import Foundation
import Security

enum KeychainKeyStore {
    private static let service = "com.local.ClipTiny.encryption"
    private static let account = "history-key-v1"

    static func loadOrCreateKey() throws -> SymmetricKey {
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let lookupStatus = SecItemCopyMatching(
            lookup as CFDictionary,
            &result
        )
        if lookupStatus == errSecSuccess,
           let data = result as? Data,
           data.count == 32 {
            return SymmetricKey(data: data)
        }
        guard lookupStatus == errSecItemNotFound else {
            throw KeychainError(status: lookupStatus)
        }

        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        let insert: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: "ClipTiny 历史加密密钥",
            kSecValueData as String: keyData
        ]
        let insertStatus = SecItemAdd(insert as CFDictionary, nil)
        guard insertStatus == errSecSuccess else {
            throw KeychainError(status: insertStatus)
        }
        return key
    }
}

private struct KeychainError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        if let message = SecCopyErrorMessageString(status, nil) {
            return "钥匙串错误 \(status)：\(message)"
        }
        return "钥匙串错误：\(status)"
    }
}
