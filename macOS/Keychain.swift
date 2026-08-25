// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os

/// `Keychain` stores the `Credentials` obtained from Login Flow v2 in the macOS Keychain, keyed by the address of the server they authenticate against.
///
/// `ServerAddressViewController` writes credentials here after a successful login, `ServerConnection.authenticated(address:)` and `WebViewController` read them back, and `AccountStore.disconnect()` clears them when the user disconnects.
/// Items use the app's default Keychain access group, so no `keychain-access-groups` entitlement is required under the App Sandbox.
enum Keychain {
    /// `service` is the constant `kSecAttrService` value under which every credential item is filed, so the app's items can be enumerated and cleared as a group.
    ///
    /// It is derived from the app's bundle identifier rather than hardcoded so the Keychain items stay tied to the app across future renames without a code change.
    private static let service: String = {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            preconditionFailure("Missing bundle identifier")
        }

        return bundleIdentifier
    }()

    /// `logger` records Keychain access under the `Keychain` category, at debug level for successful reads, writes, and clears and at error level for failures.
    private static let logger = Logger(for: Keychain.self)

    /// `store(_:for:)` persists `credentials` for `server`, replacing any credentials previously stored for the same server.
    ///
    /// It throws `CirruscopeError.keychainFailure` if the Keychain rejects the write.
    static func store(_ credentials: Credentials, for server: URL) throws {
        let data = try JSONEncoder().encode(credentials)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: server.absoluteString,
        ]

        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)

        guard status == errSecSuccess else {
            logger.error("Keychain store failed: OSStatus \(status)")
            throw CirruscopeError.keychainFailure(status)
        }

        logger.debug("Stored credentials for \(server)")
    }

    /// `credentials(for:)` returns the credentials stored for `server`, or `nil` if none have been stored or the stored value cannot be decoded.
    static func credentials(for server: URL) -> Credentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: server.absoluteString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            if status == errSecItemNotFound {
                logger.debug("No stored credentials for \(server)")
            } else {
                logger.error("Keychain read failed: OSStatus \(status)")
            }
            return nil
        }

        guard let credentials = try? JSONDecoder().decode(Credentials.self, from: data) else {
            logger.error("Stored credentials could not be decoded")
            return nil
        }

        logger.debug("Retrieved stored credentials for \(server)")
        return credentials
    }

    /// `clearAll()` removes every credential item the app has stored.
    ///
    /// `AccountStore.disconnect()` calls this when the account is disconnected so that no credentials remain for a server the app no longer talks to.
    static func clearAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]

        SecItemDelete(query as CFDictionary)
        logger.debug("Cleared all stored credentials")
    }
}
