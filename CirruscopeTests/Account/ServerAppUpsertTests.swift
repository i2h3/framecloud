// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Testing

/// `ServerAppUpsertTests` covers `AccountStore.persist(serverApps:)` and the `serverApps` snapshot it feeds the menus and the Apps settings tab from.
///
/// The upsert is the half of the store whose whole point is what it does *not* destroy: an app list arrives on every launch and every reconnect, and matching by identifier is what keeps a user's recorded shortcut alive across those refreshes while still pruning one whose app the server stopped offering. Both of those are asserted here, along with the ordering the snapshot applies because SwiftData does not preserve a to-many relationship's order.
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
    func `Server apps are returned sorted ascending by order`() {
        // Persisted deliberately out of order: SwiftData does not preserve the order of a to-many relationship, so
        // the sort in `serverApps` is the only thing putting the menus in the order the server intended.
        harness.store.persist(serverApps: [ServerAppFixture.talk, ServerAppFixture.files, ServerAppFixture.photos])

        #expect(harness.store.serverApps.map(\.order) == [0, 1, 2])
        #expect(harness.store.serverApps.map(\.id) == ["files", "photos", "talk"])
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

        // Two rows sharing one identifier would leave `storedShortcuts`' (order, appID) ordering with a tie it
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
