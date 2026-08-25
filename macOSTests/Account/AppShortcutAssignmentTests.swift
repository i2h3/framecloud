// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Testing

/// `AppShortcutAssignmentTests` covers the plain round trip through `AccountStore.setShortcut(_:forAppID:)` and `shortcut(forAppID:)`: recording, replacing, and clearing one app's keyboard shortcut.
///
/// `DuplicateShortcutSuppressionTests` covers which app a combination reaches when several could claim it; this suite covers the simpler contract underneath that, including the deliberate asymmetry that the store stores whatever it is given and leaves refusing an occupied combination to the recorder — visible here because a shortcut Cirruscope's own menu occupies is still stored, merely never applied.
@MainActor
@Suite(.serialized)
struct AppShortcutAssignmentTests {
    /// `harness` is this case's own store over a fresh in-memory container.
    private let harness = AccountStoreHarness()

    /// `commandOne` is the combination these cases record, chosen because no menu item in `Main.storyboard` declares a digit.
    private let commandOne = ShortcutFixture.named("⌘1").shortcut

    @Test
    func `An app with no recorded shortcut has none`() {
        harness.store.persist(serverApps: [ServerAppFixture.files])

        #expect(harness.store.shortcut(forAppID: "files") == nil)
    }

    @Test
    func `A recorded shortcut is stored and read back`() {
        harness.store.persist(serverApps: [ServerAppFixture.files])
        harness.store.setShortcut(commandOne, forAppID: "files")

        #expect(harness.store.shortcut(forAppID: "files") == commandOne)
    }

    @Test
    func `Recording again replaces the stored shortcut`() {
        harness.store.persist(serverApps: [ServerAppFixture.files])
        harness.store.setShortcut(commandOne, forAppID: "files")
        harness.store.setShortcut(ShortcutFixture.named("F5").shortcut, forAppID: "files")

        #expect(harness.store.shortcut(forAppID: "files") == ShortcutFixture.named("F5").shortcut)

        // Asserted from the other side too, so a second record inserted alongside the first would be caught rather
        // than hidden behind the app's own row reading correctly.
        #expect(harness.store.nameOfApp(usingShortcut: commandOne, otherThanAppID: "photos") == nil)
    }

    @Test
    func `Clearing a shortcut removes it`() {
        harness.store.persist(serverApps: [ServerAppFixture.files])
        harness.store.setShortcut(commandOne, forAppID: "files")
        harness.store.setShortcut(nil, forAppID: "files")

        #expect(harness.store.shortcut(forAppID: "files") == nil)
        #expect(harness.store.nameOfApp(usingShortcut: commandOne, otherThanAppID: "photos") == nil)
    }

    @Test
    func `Recording a shortcut for an unknown app does nothing`() {
        harness.store.persist(serverApps: [ServerAppFixture.files])
        let announcementsBefore = harness.notificationCount

        harness.store.setShortcut(commandOne, forAppID: "notes")

        // No announcement pins the early exit ahead of the save and the notification, rather than after them.
        #expect(harness.notificationCount == announcementsBefore)
        #expect(harness.store.nameOfApp(usingShortcut: commandOne, otherThanAppID: "files") == nil)
    }

    @Test
    func `A shortcut Cirruscope's own menu already uses is still stored`() {
        let reserving = AccountStoreHarness(reserving: [commandOne])
        reserving.store.persist(serverApps: [ServerAppFixture.files, ServerAppFixture.photos])
        reserving.store.setShortcut(commandOne, forAppID: "files")

        // Not applied, because it would shadow one of Cirruscope's own menu items…
        #expect(reserving.store.shortcut(forAppID: "files") == nil)

        // …but stored all the same, which is the observable form of the store keeping what it was given and leaving
        // the refusal to `ShortcutRecorderView`, where the user can be told why.
        #expect(reserving.store.nameOfApp(usingShortcut: commandOne, otherThanAppID: "photos") == "Files")
    }
}
