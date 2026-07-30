// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Testing

/// `ServerAppUpsertTests` covers `AccountStore.persist(serverApps:)` and the `serverApps` snapshot it feeds the menus and the Apps settings tab from.
///
/// The upsert is the half of the store whose whole point is what it does *not* destroy: an app list arrives on every launch and every reconnect, and matching by identifier is what keeps a user's recorded shortcut alive across those refreshes while still pruning one whose app the server stopped offering. Both of those are asserted here, along with the order the snapshot imposes, SwiftData preserving none of its own: that it is the names' rather than the positions the server assigned, that the comparison is the localized one and not `<` — the trap the sort exists to avoid, a plain string comparison reading a lowercase name and a trailing number wrongly — and that it is total, so a menu rebuild cannot reshuffle two apps sharing a name and, with them, which one a duplicate shortcut reaches (see `DuplicateShortcutSuppressionTests`).
///
/// Where a locale files a diacritic is deliberately not asserted. `localizedStandardCompare(_:)` answers in the user's own locale by design, and locales genuinely disagree — Swedish orders "Ä" after "Z", English with "A" — so pinning one answer would assert the test machine's locale rather than the store's behaviour.
@MainActor
@Suite(.serialized)
struct ServerAppUpsertTests {
    /// `harness` is this case's own store over a fresh in-memory container; Swift Testing instantiates the suite once per case, so no case sees another's data.
    private let harness = AccountStoreHarness()

    @Test
    func `A store with no account has no server apps`() {
        #expect(harness.store.serverApps.isEmpty)
    }

    @Test
    func `Persisting apps for the first time creates the account and stores them`() {
        harness.store.persist(serverApps: ServerAppFixture.all)

        #expect(harness.store.serverApps.map(\.id) == ["files", "photos", "talk"])
    }

    @Test
    func `Server apps are returned in the order the menus list them`() {
        // Persisted deliberately shuffled: SwiftData does not preserve the order of a to-many relationship, so the
        // sort in `serverApps` is the only thing giving the menus and the settings table an order at all.
        harness.store.persist(serverApps: [ServerAppFixture.talk, ServerAppFixture.files, ServerAppFixture.photos])

        #expect(harness.store.serverApps.map(\.id) == ["files", "photos", "talk"])
    }

    @Test
    func `Server apps are returned alphabetically and not in the server's own order`() {
        harness.store.persist(serverApps: ServerAppFixture.unalphabeticalApps)

        #expect(harness.store.serverApps.map(\.id) == ["deck", "files", "talk"])
        // The server's own positions come out descending, which is what tells this apart from a list that merely
        // happens to agree with them: the fixture's names run the exact opposite way to its `order` values.
        #expect(harness.store.serverApps.map(\.order) == [2, 1, 0])
    }

    @Test
    func `A lowercase name is ordered by its letter rather than behind every uppercase one`() {
        harness.store.persist(serverApps: ServerAppFixture.unalphabeticalApps)

        // `<` orders Swift strings by Unicode scalar, which files every lowercase name behind every uppercase one:
        // it puts "deck" last where a person reading the menu looks for it first. Asserting what `<` would answer
        // for these very names is the negative control — it keeps the store's sort from being quietly rewritten as
        // a plain string comparison, and keeps a rename of the fixture from leaving the case unable to tell.
        #expect(ServerAppFixture.unalphabeticalApps.map(\.name).sorted() == ["Files", "Talk", "deck"])
        #expect(harness.store.serverApps.map(\.name) == ["deck", "Files", "Talk"])
    }

    @Test
    func `A trailing number in a name is read as a number and not as characters`() {
        harness.store.persist(serverApps: ServerAppFixture.numberedApps)

        // "Talk 2" before "Talk 10", as Finder lists them; comparing the digits as characters would invert this.
        #expect(harness.store.serverApps.map(\.id) == ["talk2", "talk10"])
    }

    @Test
    func `Two apps sharing a display name are ordered by identifier`() {
        harness.store.persist(serverApps: ServerAppFixture.sameNameApps)

        // Neither the array's own order nor the server's positions can be the answer here: the fixture lists the
        // apps in the opposite order to both, leaving the identifier as the only tie-break left.
        #expect(harness.store.serverApps.map(\.id) == ["notes", "notes-beta"])
    }

    @Test
    func `The same apps come out in the same order whichever order they arrive in`() {
        let apps = ServerAppFixture.unalphabeticalApps + ServerAppFixture.numberedApps + ServerAppFixture.sameNameApps
        harness.store.persist(serverApps: apps)
        let firstReading = harness.store.serverApps.map(\.id)

        // Re-persisting reversed rewrites every row through the update path, so a sort resting on the order the
        // records happen to arrive in would answer differently the second time. `sorted(by:)` promises no stability,
        // so only the identifier tie-break makes these two readings agree — and only that keeps a menu rebuild from
        // silently moving an app.
        harness.store.persist(serverApps: apps.reversed())

        #expect(firstReading == harness.store.serverApps.map(\.id))
        #expect(firstReading == ["deck", "files", "notes", "notes-beta", "talk", "talk2", "talk10"])
    }

    @Test
    func `A refresh updates an app in place`() {
        harness.store.persist(serverApps: [ServerAppFixture.files, ServerAppFixture.photos])
        harness.store.persist(serverApps: [ServerAppFixture.renamedFiles, ServerAppFixture.photos])

        let files = harness.store.serverApps.first { $0.id == "files" }
        #expect(harness.store.serverApps.count == 2)
        #expect(files?.name == "Dateien")
        #expect(files?.href == "/apps/files/new/")
        #expect(files?.order == 5)
    }

    @Test
    func `A refresh inserts an app the server newly offers`() {
        harness.store.persist(serverApps: [ServerAppFixture.files])
        harness.store.persist(serverApps: [ServerAppFixture.files, ServerAppFixture.talk])

        #expect(harness.store.serverApps.map(\.id) == ["files", "talk"])
    }

    @Test
    func `A refresh deletes an app the server no longer offers`() {
        harness.store.persist(serverApps: ServerAppFixture.all)
        harness.store.persist(serverApps: [ServerAppFixture.files, ServerAppFixture.talk])

        #expect(harness.store.serverApps.map(\.id) == ["files", "talk"])
    }

    @Test
    func `Persisting an empty list deletes every app`() {
        harness.store.persist(serverApps: ServerAppFixture.all)
        harness.store.persist(serverApps: [])

        // An empty list is a successful fetch of nothing, which really does mean the account offers no apps.
        // `ServerConnection.refreshNavigationApps(using:)` never gets here on a *failed* fetch — it keeps the
        // previous list by not calling the store at all.
        #expect(harness.store.serverApps.isEmpty)
    }

    @Test
    func `The same app offered twice is stored once`() {
        harness.store.persist(serverApps: [ServerAppFixture.files, ServerAppFixture.files])

        // Two rows sharing one identifier would leave `serverApps`' name-then-identifier ordering with a tie it
        // cannot break, so which app a shared shortcut belongs to would stop being decidable.
        #expect(harness.store.serverApps.map(\.id) == ["files"])
    }

    @Test
    func `A shortcut survives an app-list refresh`() {
        harness.store.persist(serverApps: [ServerAppFixture.files, ServerAppFixture.photos])
        harness.store.setShortcut(ShortcutFixture.named("⌘1").shortcut, forAppID: "files")

        // Refreshing with the *renamed* app proves the update path ran, rather than the list happening to be identical.
        harness.store.persist(serverApps: [ServerAppFixture.renamedFiles, ServerAppFixture.photos])

        #expect(harness.store.shortcut(forAppID: "files") == ShortcutFixture.named("⌘1").shortcut)
    }

    @Test
    func `A shortcut is pruned with the app it belonged to`() {
        harness.store.persist(serverApps: [ServerAppFixture.files, ServerAppFixture.photos])
        harness.store.setShortcut(ShortcutFixture.named("⌘1").shortcut, forAppID: "files")
        harness.store.persist(serverApps: [ServerAppFixture.photos])

        // The combination is free again, which is what tells the shortcut apart from one merely unreachable because
        // its app is gone: the cascade delete really removed the record.
        #expect(harness.store.nameOfApp(usingShortcut: ShortcutFixture.named("⌘1").shortcut, otherThanAppID: "photos") == nil)

        harness.store.persist(serverApps: [ServerAppFixture.files, ServerAppFixture.photos])
        #expect(harness.store.shortcut(forAppID: "files") == nil)
    }

    @Test
    func `Every app-list write announces the change, and reading announces nothing`() {
        harness.store.persist(serverApps: ServerAppFixture.all)
        harness.store.persist(serverApps: [ServerAppFixture.files])
        #expect(harness.notificationCount == 2)

        _ = harness.store.serverApps
        #expect(harness.notificationCount == 2)
    }
}
