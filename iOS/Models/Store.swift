// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import Rainmaker
import SwiftUI
import WebKit

///
/// Global iOS app state object.
///
@Observable
@MainActor
class Store {
    ///
    /// The configured account, or `nil` while none is.
    ///
    var account: ServerAccount? {
        didSet {
            server = account.flatMap { ServerConnection.authenticated(address: $0.server) }
        }
    }

    ///
    /// Nextcloud server apps.
    ///
    /// Not persisted. Initially populated on launch by a server response. Occassionally refreshed.
    ///
    var apps: [ServerAppTransferObject]

    ///
    /// Counts how many times the apps' icons have changed, so a view drawing them redraws when they do.
    ///
    /// The icons live outside this store — they are files on disk, shared with macOS, found by app identifier — so nothing about `apps` changes when one arrives and observation alone would not notice. This is the one observable thing that does change, and reading it in a view is what subscribes that view to the arrival.
    ///
    private(set) var iconGeneration = 0

    ///
    /// Rainmaker server to interact with the Nextcloud server.
    ///
    /// Kept in step with `account` rather than assigned independently, so the two can never disagree about who the app is talking to. It is built through `ServerConnection.authenticated(address:)` so its credentials and user agent are resolved exactly as macOS resolves them.
    ///
    private(set) var server: Server?

    ///
    /// Records account lifecycle under the `Store` category.
    ///
    private let logger = Logger(for: Store.self)

    ///
    /// Build a store around an account that is already known, or around none.
    ///
    /// The app itself uses `restored()` instead; this initializer is what previews and tests use, so they cannot pick up whatever credentials happen to sit in the Keychain of the machine they run on.
    ///
    init(account: ServerAccount? = nil, apps: [ServerAppTransferObject] = []) {
        self.account = account
        self.apps = apps

        server = account.flatMap { ServerConnection.authenticated(address: $0.server) }
    }

    ///
    /// Build a store around the account this device already holds credentials for, if it holds any.
    ///
    /// The account is read back out of the Keychain rather than from a store of its own: `Keychain.store(_:for:)` files every credential under the address it authenticates against, so one item already carries both halves of a `ServerAccount` and there is no second place for them to fall out of step. macOS keeps the address in `AccountStore` instead, because it already has a database there for the appearance settings and app shortcuts iOS does not have yet.
    ///
    static func restored() -> Store {
        Store(account: Keychain.accounts().first)
    }

    ///
    /// Update the list of available Nextcloud server apps, and the icons they are shown with.
    ///
    /// The list is sorted through the shared `sortedByName()`, which is the same order macOS lists these in — alphabetically by localized name, not in the order the server sends them, for the reason recorded in `DECISIONS.md`.
    /// The icons are fetched after the list is published rather than before, so the menu appears at once with placeholders instead of waiting on a round trip per app. `iconGeneration` is bumped when they land, which is what tells the menu to draw itself again — the apps themselves have not changed, and an icon is not something a value-type snapshot of one carries.
    ///
    func updateApps() {
        guard let server else {
            return
        }

        guard let account else {
            return
        }

        Task {
            let navigationItems = try await server.navigation()

            let apps = navigationItems
                .map { ServerAppTransferObject(id: $0.id, order: $0.order, href: $0.href, name: $0.name) }
                .sortedByName()

            await MainActor.run {
                self.apps = apps
            }

            let didFetchIcons = await ServerAppIcons.shared.refresh(navigationItems, serverAddress: account.server, credentials: account.credentials)

            guard didFetchIcons else {
                return
            }

            await MainActor.run {
                self.iconGeneration += 1
            }
        }
    }

    ///
    /// Log out the current user from the connected server.
    ///
    /// The app password is revoked on the server first, so the credential this device is about to forget is invalidated rather than left standing in the account's device list. That request is fire-and-forget: revocation is fail-open — an unreachable server must not be able to keep someone signed in locally — which is the same bargain `AppDelegate.logOut()` strikes on macOS. The web view's site data goes with it, so a later account does not inherit a session from this one.
    ///
    func logout() {
        logger.notice("Logging out; revoking the app password on the server, clearing the web view's site data, and clearing the stored credentials")

        if let server {
            Task {
                await ServerConnection.revokeAppPassword(using: server)
            }
        } else {
            logger.debug("No server to revoke an app password on")
        }

        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
            self.logger.debug("Cleared the web view's site data")
        }

        Keychain.clearAll()

        apps = []
        account = nil
    }
}
