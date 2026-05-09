//
//  KeychainHelper.swift
//  ChineseLawsSearch
//

import Foundation
import Security

enum KeychainHelper {
    static func save(_ value: String, forKey key: String) {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass:                kSecClassGenericPassword,
            kSecAttrAccount:          key,
            kSecAttrSynchronizable:   kCFBooleanTrue!,
            kSecValueData:            data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(forKey key: String) -> String? {
        // Try synchronizable item first (current format)
        let syncQuery: [CFString: Any] = [
            kSecClass:                kSecClassGenericPassword,
            kSecAttrAccount:          key,
            kSecAttrSynchronizable:   kCFBooleanTrue!,
            kSecReturnData:           true,
            kSecMatchLimit:           kSecMatchLimitOne
        ]
        var result: AnyObject?
        if SecItemCopyMatching(syncQuery as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let value = String(data: data, encoding: .utf8) {
            return value
        }

        // Fall back to legacy non-synchronizable item and migrate it
        let legacyQuery: [CFString: Any] = [
            kSecClass:                kSecClassGenericPassword,
            kSecAttrAccount:          key,
            kSecAttrSynchronizable:   kSecAttrSynchronizableAny,
            kSecReturnData:           true,
            kSecMatchLimit:           kSecMatchLimitOne
        ]
        result = nil
        if SecItemCopyMatching(legacyQuery as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let value = String(data: data, encoding: .utf8) {
            save(value, forKey: key)   // migrate to synchronizable format
            return value
        }

        return nil
    }

    static func delete(forKey key: String) {
        let query: [CFString: Any] = [
            kSecClass:              kSecClassGenericPassword,
            kSecAttrAccount:        key,
            kSecAttrSynchronizable: kCFBooleanTrue!
        ]
        SecItemDelete(query as CFDictionary)
    }
}
