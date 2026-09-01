// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `ServerAppTransferObject` is a value-type snapshot of a Nextcloud server app the user can navigate to, used to populate the View and Dock menus and the Apps settings tab.
///
/// It keeps just the fields both apps need: the `id` used to detect which app a window shows, to match a row across a refresh, to find that app's cached icon, and to break a tie between two apps sharing one name, the `order` the server assigns, the `href` used to build the app's URL, and the `name` used both as the menu label and as what the list is sorted by. It is `Sendable` so it can be passed freely between actors without exposing a managed `@Model` object.
///
/// On macOS it is the immutable projection `AccountStore` returns from its `ServerApp` records — and, since `persist(serverApps:)` takes it too, also the type an app list is written back with, so nothing about the store's surface depends on the network library's own models. iOS persists nothing and builds these straight from a navigation response, which is why the type lives here rather than beside that store: one shape of a server app, described once.
/// It carries no icon. An icon is fetched by the path a navigation response gives and found again by the app's identifier, so the path is worth nothing once the fetch has happened — see `ServerAppIcons`.
struct ServerAppTransferObject: Codable, Identifiable, Sendable {
    /// `id` is the Nextcloud app identifier (e.g. `"files"`), matched against the `/apps/<id>/` path of a web view's URL to detect which app a window currently shows.
    let id: String

    /// `order` is the position the server assigns the app in the web interface's own app menu, recorded as reported on every refresh but not what any of Cirruscope's lists are sorted by — see `AccountStore.serverApps` for the order they use instead and why.
    let order: Int

    /// `href` is where the server says the app lives (e.g. `"/apps/files/"`), resolved against the connected server address to form the URL a window loads.
    ///
    /// Usually a server-relative path, and not reliably one: Talk reports its entry as a full URL where every other app on the same instance reports a path. So it is only ever resolved through `SameOriginURL`, which takes either and proves the result stays on the server that named it.
    let href: String

    /// `name` is the localized display name of the app, used as its menu item label.
    let name: String
}
