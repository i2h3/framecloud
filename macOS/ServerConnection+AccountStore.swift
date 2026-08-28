// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import Rainmaker

/// `ServerConnection`'s macOS half: the parts of talking to a server that also write what was learned to `AccountStore`.
///
/// `ServerConnection` itself lives in `Core/` and is compiled into both apps and the widget extension, so it can depend on nothing macOS-only — and `AccountStore` is SwiftData, main-actor, and macOS-only, as are the `ServerAppTransferObject` values it stores. This extension is where that dependency is allowed to exist. iOS reuses the pure half and persists nothing but the credential.
extension ServerConnection {
    /// `validateAndPersist(_:)` validates `server` and records what the validation found: its theming, and — when the version is supported — its version string.
    ///
    /// It is what `AppDelegate` and `ServerAddressViewController` call in place of `validate(_:)`, and it returns that call's outcome unchanged so their `switch` reads the same as before.
    /// Theming is persisted on both branches, deliberately: an unsupported server's appearance is still the appearance of the server the user is looking at an alert about, and the sign-in window they are sent back to is themed from it.
    static func validateAndPersist(_ server: Server) async throws -> ValidationOutcome {
        let outcome = try await validate(server)

        let capabilities = switch outcome {
            case let .supported(capabilities): capabilities
            case let .unsupported(capabilities): capabilities
        }

        if let theming = try? capabilities.get(Theming.self) {
            await AccountStore.shared.persist(theming: theming)
        } else {
            logger.debug("No theming capability present")
        }

        if case .supported = outcome {
            await AccountStore.shared.setServerVersion(capabilities.version.string)
        }

        return outcome
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
}
