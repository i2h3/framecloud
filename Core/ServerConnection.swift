// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import Rainmaker

/// `ServerConnection` builds `Rainmaker.Server` instances and validates them, centralizing the connection logic both apps' sign-in paths share.
///
/// `anonymous(address:)` is used before the user has authenticated and to initiate Login Flow v2, `authenticated(address:)` builds a credentialed server from `Keychain`, `validate(_:)` fetches capabilities and reports whether the server's version is supported, and `revokeAppPassword(using:)` invalidates a credential the app is about to discard.
/// Everything here is free of persistence on purpose. macOS records what a validation found — theming, the server version, the navigation apps — in `AccountStore`, which is SwiftData and macOS-only; that half lives in `ServerConnection+AccountStore` beside the store it writes to, and macOS calls `validateAndPersist(_:)` rather than `validate(_:)` directly. iOS keeps nothing but the credential, so it calls `validate(_:)` as it stands.
enum ServerConnection {
    /// `ValidationOutcome` reports the result of `validate(_:)`.
    ///
    /// Both cases carry the fetched `CapabilitySet` rather than only the supported one, because a caller may have something to do with it either way: `ServerConnection+AccountStore` persists an unsupported server's theming too, and the version string an unsupported-server alert names is read back out of these capabilities.
    enum ValidationOutcome {
        /// `supported` carries the capabilities of a server whose major version meets `InfoPlist.minimumSupportedServerMajorVersion`.
        case supported(CapabilitySet)

        /// `unsupported` carries the capabilities of a server whose major version is below `InfoPlist.minimumSupportedServerMajorVersion`.
        case unsupported(CapabilitySet)
    }

    /// `logger` records connection and validation activity under the `ServerConnection` category.
    ///
    /// Not `private`: `ServerConnection+AccountStore` logs the persistence half of a validation under the same category, so both halves of one operation read as one story in `log stream`.
    static let logger = Logger(for: ServerConnection.self)

    /// `anonymous(address:)` builds a `Server` without credentials, used to validate reachability and to initiate Login Flow v2.
    static func anonymous(address: URL) -> Server {
        Server(address: address, userAgent: userAgent)
    }

    /// `authenticated(address:)` builds a `Server` carrying the credentials stored for `address`, or `nil` if none have been stored.
    ///
    /// The returned server can call authenticated endpoints such as `navigation()`.
    static func authenticated(address: URL) -> Server? {
        guard let credentials = Keychain.credentials(for: address) else {
            return nil
        }

        return Server(address: address, password: credentials.appPassword, user: credentials.user, userAgent: userAgent)
    }

    /// `validate(_:)` fetches `server`'s capabilities and reports whether its major version meets `InfoPlist.minimumSupportedServerMajorVersion`.
    ///
    /// It rethrows any error raised while fetching the capabilities so callers can distinguish an unreachable or unauthorized server from an unsupported one.
    /// It writes nothing anywhere. macOS wants a validation to also record the server's theming and version, and gets that from `validateAndPersist(_:)`, which wraps this; keeping the two apart is what lets iOS — which persists neither — reuse the check itself.
    static func validate(_ server: Server) async throws -> ValidationOutcome {
        logger.info("Validating server capabilities")

        let capabilities = try await server.capabilities()
        let minimumMajorVersion = InfoPlist.minimumSupportedServerMajorVersion

        guard capabilities.version.major >= minimumMajorVersion else {
            logger.notice("Server version \(capabilities.version.string) is below the minimum \(minimumMajorVersion)")
            return .unsupported(capabilities)
        }

        logger.info("Server version \(capabilities.version.string) is supported")

        return .supported(capabilities)
    }

    /// `revokeAppPassword(using:)` asks the server to revoke the Login Flow v2 app password `server` is currently authenticated with, so the credential the app is about to discard locally is also invalidated on the server.
    ///
    /// `AppDelegate.logOut()` on macOS and `Store.logout()` on iOS call this as a best-effort step: failures are logged and swallowed rather than thrown, because Nextcloud's own guidance is that app-password revocation is fail-open — if the server cannot be reached or rejects the request, the client should still remove the credential locally regardless. `server` must already carry the credentials to revoke, obtained via `authenticated(address:)` before the caller clears them from `Keychain`; this method never re-reads `Keychain` itself, so it stays valid to call even after the credential has been cleared locally.
    static func revokeAppPassword(using server: Server) async {
        do {
            try await server.deleteAppPassword()
            logger.info("Revoked the app password on the server")
        } catch {
            logger.notice("Could not revoke the app password on the server; proceeding with local sign-out regardless: \(error.localizedDescription)")
        }
    }

    /// `userAgent` is the HTTP user agent Cirruscope presents to the server, derived from the app's bundle name.
    static var userAgent: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Cirruscope"
    }
}
