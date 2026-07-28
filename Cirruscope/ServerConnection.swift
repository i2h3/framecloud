// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import Rainmaker

/// `ServerConnection` builds `Rainmaker.Server` instances and validates them, centralizing the connection logic shared by `AppDelegate` and `ServerAddressViewController`.
///
/// `anonymous(address:)` is used before the user has authenticated and to initiate Login Flow v2, `authenticated(address:)` builds a credentialed server from `Keychain`, and `validate(_:)` fetches capabilities, persists theming, and reports whether the server's version is supported.
enum ServerConnection {
    /// `ValidationOutcome` reports the result of `validate(_:)`.
    enum ValidationOutcome {
        /// `supported` carries the fetched `CapabilitySet` of a server whose major version meets `Settings.minimumSupportedServerMajorVersion`.
        case supported(CapabilitySet)

        /// `unsupported` carries the human-readable version string of a server whose major version is below `Settings.minimumSupportedServerMajorVersion`.
        case unsupported(version: String)
    }

    /// `logger` records connection and validation activity under the `ServerConnection` category.
    private static let logger = Logger(for: ServerConnection.self)

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

    /// `validate(_:)` fetches `server`'s capabilities, persists its theming, and reports whether its major version is supported, recording the version string of a supported server via `AccountStore.setServerVersion(_:)`.
    ///
    /// It rethrows any error raised while fetching the capabilities so callers can distinguish an unreachable or unauthorized server from an unsupported one.
    static func validate(_ server: Server) async throws -> ValidationOutcome {
        logger.info("Validating server capabilities")
        let capabilities = try await server.capabilities()

        if let theming = try? capabilities.get(Theming.self) {
            await AccountStore.shared.persist(theming: theming)
        } else {
            logger.debug("No theming capability present")
        }

        let minimumMajorVersion = Settings.minimumSupportedServerMajorVersion

        guard capabilities.version.major >= minimumMajorVersion else {
            logger.notice("Server version \(capabilities.version.string) is below the minimum \(minimumMajorVersion)")
            return .unsupported(version: capabilities.version.string)
        }

        await AccountStore.shared.setServerVersion(capabilities.version.string)
        logger.info("Server version \(capabilities.version.string) is supported")

        return .supported(capabilities)
    }

    /// `refreshNavigationApps(using:)` fetches the server's navigation apps with the authenticated `server` and persists them via `AccountStore.persist(serverApps:)`.
    ///
    /// Failures are ignored because the apps list is non-critical: when it cannot be fetched the previously persisted list is simply left in place.
    ///
    /// Mapping `Rainmaker.NavigationItem` to `ServerAppTransferObject` happens here, at the boundary where the network library is already in scope, rather than inside the store or on the transfer object itself — the store then depends on nothing but the app's own value types, and the transfer object stays free of logic.
    static func refreshNavigationApps(using server: Server) async {
        do {
            let items = try await server.navigation()
            let apps = items.map { ServerAppTransferObject(id: $0.id, order: $0.order, href: $0.href, name: $0.name) }
            await AccountStore.shared.persist(serverApps: apps)
        } catch {
            logger.notice("Could not refresh navigation apps; keeping the previous list: \(error.localizedDescription)")
        }
    }

    /// `revokeAppPassword(using:)` asks the server to revoke the Login Flow v2 app password `server` is currently authenticated with, so the credential the app is about to discard locally is also invalidated on the server.
    ///
    /// `AppDelegate.logOut()` calls this as a best-effort step, mirroring `refreshNavigationApps(using:)`: failures are logged and swallowed rather than thrown, because Nextcloud's own guidance is that app-password revocation is fail-open — if the server cannot be reached or rejects the request, the client should still remove the credential locally regardless. `server` must already carry the credentials to revoke, obtained via `authenticated(address:)` before the caller clears them from `Keychain`; this method never re-reads `Keychain` itself, so it stays valid to call even after the credential has been cleared locally.
    static func revokeAppPassword(using server: Server) async {
        do {
            try await server.deleteAppPassword()
            logger.info("Revoked the app password on the server")
        } catch {
            logger.notice("Could not revoke the app password on the server; proceeding with local sign-out regardless: \(error.localizedDescription)")
        }
    }

    /// `userAgent` is the HTTP user agent Cirruscope presents to the server, derived from the app's bundle name.
    private static var userAgent: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Cirruscope"
    }
}
