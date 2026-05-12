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
            kSecClass:              kSecClassGenericPassword,
            kSecAttrAccount:        key,
            kSecAttrSynchronizable: kCFBooleanTrue!
        ]
        let status = SecItemAdd(query.merging([kSecValueData: data]) { _, new in new } as CFDictionary, nil)
        if status == errSecDuplicateItem {
            // Already exists — update in place (atomic, no delete+add gap)
            SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        }
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
        // Delete both synchronizable and legacy (non-synchronizable) items
        let base: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrAccount: key
        ]
        SecItemDelete(base.merging([kSecAttrSynchronizable: kCFBooleanTrue!]) { _, new in new } as CFDictionary)
        SecItemDelete(base.merging([kSecAttrSynchronizable: kSecAttrSynchronizableAny]) { _, new in new } as CFDictionary)
    }
}
