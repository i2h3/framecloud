// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope

/// `ServerAppFixture` is the corpus of server apps the account suites seed a store with, in the shape `AccountStore.persist(serverApps:)` takes them.
///
/// The suites share it so they cannot drift on what a server's app list looks like, the same reason `ShortcutFixture` exists for the shortcut suites. Everything here is an app list a real Nextcloud server could return, so a case never has to construct a `@Model` object itself and no case depends on the store's internals.
enum ServerAppFixture {
    /// `files` is the app a case reaches for when it needs one app, ordered first.
    static let files = ServerAppTransferObject(id: "files", order: 0, href: "/apps/files/", name: "Files")

    /// `photos` is the second app in menu order, used wherever a case needs a second holder for a shortcut.
    static let photos = ServerAppTransferObject(id: "photos", order: 1, href: "/apps/photos/", name: "Photos")

    /// `talk` is the third app in menu order.
    static let talk = ServerAppTransferObject(id: "talk", order: 2, href: "/apps/spreed/", name: "Talk")

    /// `all` is the full three-app list a server offers.
    static let all = [files, photos, talk]

    /// `renamedFiles` is `files` after the server changed everything about it except its identity, so a case can tell an in-place update from a delete-and-reinsert.
    static let renamedFiles = ServerAppTransferObject(id: "files", order: 5, href: "/apps/files/new/", name: "Dateien")

    /// `sameOrderApps` are two apps the server placed at the same position, listed with the alphabetically later one first.
    ///
    /// The array order is deliberately the opposite of the identifier order, so a case asserting which of them a shared shortcut belongs to measures `storedShortcuts`' `appID` tie-break rather than the order they happened to be inserted in.
    static let sameOrderApps = [
        ServerAppTransferObject(id: "beta", order: 0, href: "/apps/beta/", name: "Beta"),
        ServerAppTransferObject(id: "alpha", order: 0, href: "/apps/alpha/", name: "Alpha"),
    ]
}
