// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

/// `ServerApp` is the SwiftData record for a Nextcloud server app offered by an `Account`, persisted so the View and Dock menus and the Apps settings tab survive relaunches and become queryable by a future App Intents extension.
///
/// It is the persistent counterpart of the value-type `ServerAppTransferObject` DTO the app's UI passes around; `AccountStore` maps between the two so AppKit views never hold a managed object directly. `AccountStore.persist(navigationApps:)` upserts these by `appID` — updating existing rows and deleting ones the server no longer offers — so an app's `shortcut` survives an app-list refresh and is pruned (via cascade) only when the app itself disappears.
@Model
final class ServerApp {
    /// `appID` is the Nextcloud app identifier (e.g. `"files"`), used to match a web view's URL and to upsert this row across refreshes.
    var appID: String

    /// `order` is the position the server assigns the app; menus list apps sorted ascending by this value.
    var order: Int

    /// `href` is the server-relative path of the app (e.g. `"/apps/files/"`), resolved against `Account.serverAddress` to form the URL a window loads.
    var href: String

    /// `name` is the localized display name of the app, used as its menu item label.
    var name: String

    /// `account` is the account this app belongs to; it is the inverse of `Account.apps`.
    var account: Account?

    /// `shortcut` is the user's keyboard shortcut for this app, if any; deleting the app cascades to it.
    @Relationship(deleteRule: .cascade, inverse: \KeyboardShortcut.app)
    var shortcut: KeyboardShortcut?

    init(appID: String, order: Int, href: String, name: String, account: Account? = nil) {
        self.appID = appID
        self.order = order
        self.href = href
        self.name = name
        self.account = account
    }
}
