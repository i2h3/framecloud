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
            await refreshServerAppIcons(from: items, using: server)
        } catch {
            logger.notice("Could not refresh navigation apps; keeping the previous list: \(error.localizedDescription)")
        }
    }

    /// `refreshServerAppIcons(from:using:)` downloads the icon of every app the server just listed, and announces the app list again once they have landed.
    ///
    /// This is the only moment the app learns where an icon lives: the path is part of a navigation response and is deliberately not persisted, since a menu finds an icon again by the app's identifier rather than by where it came from. Fetching here rather than where the menus are built is what keeps the Dock menu — which AppKit asks for and draws in the same breath — free of anything it would have to wait for.
    /// The second announcement is what redraws the menus with the icons in them; `persist(serverApps:)` has already made the first. It is sent only when something was actually fetched, so an unchanged app list does not rebuild every menu to look exactly as it already did.
    private static func refreshServerAppIcons(from items: [NavigationItem], using server: Server) async {
        guard let credentials = Keychain.credentials(for: server.address) else {
            return
        }

        let didFetchAny = await ServerAppIcons.shared.refresh(items, serverAddress: server.address, credentials: credentials)

        guard didFetchAny else {
            return
        }

        // Posted on the main actor, not from here. `NotificationCenter` delivers synchronously on the
        // posting thread, and every observer of this — `AppDelegate.rebuildServerAppsMenu()`, the Apps
        // settings tab, `ServerAppIndexer` — is main-actor-isolated, so posting from this task's own
        // executor trips Swift's isolation check and takes the process down. `AccountStore`'s own
        // `postServerAppsDidChange()` hops to the main thread for exactly this reason.
        await MainActor.run {
            NotificationCenter.default.post(name: .serverAppsDidChange, object: nil)
        }
    }
}
