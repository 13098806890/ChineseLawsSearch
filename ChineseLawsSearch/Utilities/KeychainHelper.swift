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
            SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        } else if status != errSecSuccess {
            print("[KeychainHelper] SecItemAdd failed for key '\(key)': OSStatus \(status)")
        }
    }

    static func load(forKey key: String) -> String? {
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
            save(value, forKey: key)
            return value
        }

        return nil
    }

    static func delete(forKey key: String) {
        let base: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrAccount: key
        ]
        SecItemDelete(base.merging([kSecAttrSynchronizable: kCFBooleanTrue!]) { _, new in new } as CFDictionary)
        SecItemDelete(base.merging([kSecAttrSynchronizable: kSecAttrSynchronizableAny]) { _, new in new } as CFDictionary)
    }

    // MARK: - Device-local data storage (not synced to iCloud)

    static func saveLocalData(_ data: Data, forKey key: String) {
        let query: [CFString: Any] = [
            kSecClass:               kSecClassGenericPassword,
            kSecAttrAccount:         key,
            kSecAttrSynchronizable:  kCFBooleanFalse!,
            kSecAttrAccessible:      kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(query.merging([kSecValueData: data]) { _, new in new } as CFDictionary, nil)
        if status == errSecDuplicateItem {
            SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        }
    }

    static func loadLocalData(forKey key: String) -> Data? {
        let query: [CFString: Any] = [
            kSecClass:               kSecClassGenericPassword,
            kSecAttrAccount:         key,
            kSecAttrSynchronizable:  kCFBooleanFalse!,
            kSecReturnData:          true,
            kSecMatchLimit:          kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func deleteLocalData(forKey key: String) {
        let query: [CFString: Any] = [
            kSecClass:              kSecClassGenericPassword,
            kSecAttrAccount:        key,
            kSecAttrSynchronizable: kCFBooleanFalse!
        ]
        SecItemDelete(query as CFDictionary)
    }
}
