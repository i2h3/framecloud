// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope

/// `ServerAppFixture` is the corpus of server apps the account suites seed a store with, in the shape `AccountStore.persist(serverApps:)` takes them.
///
/// The suites share it so they cannot drift on what a server's app list looks like, the same reason `ShortcutFixture` exists for the shortcut suites. Everything here is an app list a real Nextcloud server could return, so a case never has to construct a `@Model` object itself and no case depends on the store's internals.
enum ServerAppFixture {
    /// `files` is the app a case reaches for when it needs one app, first both in the server's order and alphabetically.
    static let files = ServerAppTransferObject(id: "files", order: 0, href: "/apps/files/", name: "Files")

    /// `photos` is the second app in menu order, used wherever a case needs a second holder for a shortcut.
    static let photos = ServerAppTransferObject(id: "photos", order: 1, href: "/apps/photos/", name: "Photos")

    /// `talk` is the third app in menu order.
    static let talk = ServerAppTransferObject(id: "talk", order: 2, href: "/apps/spreed/", name: "Talk")

    /// `all` is the full three-app list a server offers, its names in the same sequence as the positions the server assigned them.
    ///
    /// The two orderings agreeing here is what makes it the fixture for every case that is *not* about ordering: such a case reads the same result either way, so it cannot fail for a reason belonging to the ordering cases in `ServerAppUpsertTests`.
    static let all = [files, photos, talk]

    /// `renamedFiles` is `files` after the server changed everything about it except its identity, so a case can tell an in-place update from a delete-and-reinsert.
    static let renamedFiles = ServerAppTransferObject(id: "files", order: 5, href: "/apps/files/new/", name: "Dateien")

    /// `unalphabeticalApps` are three apps whose server-assigned positions run the exact opposite way to their names, so a case can tell which of the two orderings a list came out in.
    ///
    /// The array is in the server's own order, ascending by `order`, which is the order the web interface's app menu shows them in; Cirruscope lists them the other way round (see `AccountStore.serverApps`). One name is deliberately lowercase, as a third-party app's navigation label sometimes is: `"deck"` belongs ahead of `"Files"` and `"Talk"` under a localized comparison but behind both under `<`, so this list also measures that the store is not comparing names with `<`.
    static let unalphabeticalApps = [
        ServerAppTransferObject(id: "talk", order: 0, href: "/apps/spreed/", name: "Talk"),
        ServerAppTransferObject(id: "files", order: 1, href: "/apps/files/", name: "Files"),
        ServerAppTransferObject(id: "deck", order: 2, href: "/apps/deck/", name: "deck"),
    ]

    /// `numberedApps` are two apps whose names differ only in a trailing number, listed with the higher one first.
    ///
    /// They separate a numeric-aware comparison from a character-by-character one: `"Talk 10"` follows `"Talk 2"` when the digits are read as a number and precedes it when they are read as characters.
    static let numberedApps = [
        ServerAppTransferObject(id: "talk10", order: 0, href: "/apps/spreed10/", name: "Talk 10"),
        ServerAppTransferObject(id: "talk2", order: 1, href: "/apps/spreed2/", name: "Talk 2"),
    ]

    /// `sameNameApps` are two apps one server offers under a single display name, listed with the alphabetically later identifier first.
    ///
    /// The array order is deliberately the opposite of the identifier order, and so is the order the server assigned them, so a case asserting which of the two comes first — or which a shared shortcut belongs to — measures `serverApps`' `id` tie-break rather than either of those.
    static let sameNameApps = [
        ServerAppTransferObject(id: "notes-beta", order: 0, href: "/apps/notes-beta/", name: "Notes"),
        ServerAppTransferObject(id: "notes", order: 1, href: "/apps/notes/", name: "Notes"),
    ]
}
