// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `ServerAppTransferObject` is a value-type snapshot of a Nextcloud server app the user can navigate to, used to populate the View and Dock menus and the Apps settings tab.
///
/// It is the immutable projection `AccountStore` returns from its `ServerApp` records — and, since `persist(serverApps:)` takes it too, also the type an app list is written back with, so nothing about the store's surface depends on the network library's own models. It keeps just the fields the app needs: the `id` used to detect which app a window shows, to match a row across a refresh, and to break a tie between two apps sharing one name, the `order` the server assigns, the `href` used to build the app's URL, and the `name` used both as the menu label and as what the list is sorted by. It is `Sendable` so it can be passed freely between actors without exposing a managed `@Model` object.
struct ServerAppTransferObject: Codable, Identifiable, Sendable {
    /// `id` is the Nextcloud app identifier (e.g. `"files"`), matched against the `/apps/<id>/` path of a web view's URL to detect which app a window currently shows.
    let id: String

    /// `order` is the position the server assigns the app in the web interface's own app menu, recorded as reported on every refresh but not what any of Cirruscope's lists are sorted by — see `AccountStore.serverApps` for the order they use instead and why.
    let order: Int

    /// `href` is the server-relative path of the app (e.g. `"/apps/files/"`), appended to the connected server address to form the URL a window loads.
    let href: String

    /// `name` is the localized display name of the app, used as its menu item label.
    let name: String
}
