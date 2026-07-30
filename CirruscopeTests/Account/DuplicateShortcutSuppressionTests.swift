// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Testing

/// `DuplicateShortcutSuppressionTests` covers the rule that decides which single app a keyboard shortcut reaches when the stored data offers more than one candidate.
///
/// This is the logic issue #64 is about, and the reason it needs covering at this level rather than through `ShortcutRecorderView`: the recorder refuses a combination another app already holds, but data recorded before that check existed can still contain duplicates, and the store is what keeps such a duplicate off the menus. Two enabled menu items sharing one key equivalent have no reliable tie-break in AppKit, so "the first app in menu order, on every call" is the property these cases pin — together with the matching asymmetry `appHolding(_:)` exists to prevent, where an app the store suppresses would still be named as a combination's occupant.
@MainActor
@Suite(.serialized)
struct DuplicateShortcutSuppressionTests {
    /// `harness` is this case's own store over a fresh in-memory container, reserving nothing; a case that needs Cirruscope's own menu items to occupy something builds its own.
    private let harness = AccountStoreHarness()

    /// `commandOne` is the combination most cases assign, chosen because no menu item in `Main.storyboard` declares a digit.
    private let commandOne = ShortcutFixture.named("⌘1").shortcut

    @Test
    func `A shortcut two apps share reaches the first of them in menu order`() {
        harness.store.persist(serverApps: [ServerAppFixture.files, ServerAppFixture.photos])
        harness.store.setShortcut(commandOne, forAppID: "files")
        harness.store.setShortcut(commandOne, forAppID: "photos")

        #expect(harness.store.shortcut(forAppID: "files") == commandOne)
        #expect(harness.store.shortcut(forAppID: "photos") == nil)
    }

    @Test
    func `Menu order, not insertion order, decides which app wins`() {
        // Persisted with the later app first and its shortcut recorded first, so neither insertion order nor
        // assignment order can be what the answer comes from.
        harness.store.persist(serverApps: [ServerAppFixture.photos, ServerAppFixture.files])
        harness.store.setShortcut(commandOne, forAppID: "photos")
        harness.store.setShortcut(commandOne, forAppID: "files")

        #expect(harness.store.shortcut(forAppID: "files") == commandOne)
        #expect(harness.store.shortcut(forAppID: "photos") == nil)
    }

    @Test
    func `Two apps sharing a display name are broken by app identifier`() {
        harness.store.persist(serverApps: ServerAppFixture.sameNameApps)
        harness.store.setShortcut(commandOne, forAppID: "notes-beta")
        harness.store.setShortcut(commandOne, forAppID: "notes")

        // Two apps under one name leave the alphabetical comparison tied, and `sameNameApps` lists "notes-beta"
        // first — and has the server place it first too — precisely so neither array position nor the server's own
        // order can be what decides this. Only `serverApps`' `id` tie-break is left, which is what keeps the
        // winner from changing between two readings of an unstable sort.
        #expect(harness.store.shortcut(forAppID: "notes") == commandOne)
        #expect(harness.store.shortcut(forAppID: "notes-beta") == nil)
    }

    @Test
    func `The same duplicate resolves the same way on every call`() {
        harness.store.persist(serverApps: [ServerAppFixture.files, ServerAppFixture.photos])
        harness.store.setShortcut(commandOne, forAppID: "files")
        harness.store.setShortcut(commandOne, forAppID: "photos")

        let firstReading = harness.store.shortcut(forAppID: "files")
        harness.store.setShortcut(ShortcutFixture.named("↑").shortcut, forAppID: "talk")
        let secondReading = harness.store.shortcut(forAppID: "files")

        // An unstable sort would let the winner change between calls, which is what the `appID` tie-break rules out.
        #expect(firstReading == secondReading)
        #expect(harness.store.shortcut(forAppID: "photos") == nil)
    }

    @Test
    func `A duplicate is recognized across a redundant Shift bit`() {
        harness.store.persist(serverApps: [ServerAppFixture.files, ServerAppFixture.photos])
        harness.store.setShortcut(ShortcutFixture.named("⌘Z").shortcut, forAppID: "files")
        harness.store.setShortcut(ShortcutFixture.named("⇧⌘Z").shortcut, forAppID: "photos")

        // One keystroke triggers both of these, so they are one shortcut. This is the case that fails if the store
        // ever compares transfer objects with `==` instead of through `ShortcutMatching`.
        #expect(harness.store.shortcut(forAppID: "photos") == nil)
    }

    @Test
    func `Two apps whose shortcuts differ only in a function-region Shift bit both keep theirs`() {
        harness.store.persist(serverApps: [ServerAppFixture.files, ServerAppFixture.photos])
        harness.store.setShortcut(ShortcutFixture.named("⌘F5").shortcut, forAppID: "files")
        harness.store.setShortcut(ShortcutFixture.named("⇧⌘F5").shortcut, forAppID: "photos")

        // The negative control for the case above: for a caseless function-region key AppKit does honour the Shift
        // bit, so these are two shortcuts and neither app may lose its own.
        #expect(harness.store.shortcut(forAppID: "files") == ShortcutFixture.named("⌘F5").shortcut)
        #expect(harness.store.shortcut(forAppID: "photos") == ShortcutFixture.named("⇧⌘F5").shortcut)
    }

    @Test
    func `A stored shortcut Cirruscope's own menu already uses is not applied`() {
        let reserving = AccountStoreHarness(reserving: [commandOne])
        reserving.store.persist(serverApps: [ServerAppFixture.files])
        reserving.store.setShortcut(commandOne, forAppID: "files")

        #expect(reserving.store.shortcut(forAppID: "files") == nil)
    }

    @Test
    func `A shortcut nothing reserves is applied`() {
        // The control for the case above, so that one cannot pass merely because nothing is ever applied.
        harness.store.persist(serverApps: [ServerAppFixture.files])
        harness.store.setShortcut(commandOne, forAppID: "files")

        #expect(harness.store.shortcut(forAppID: "files") == commandOne)
    }

    @Test
    func `An app is never reported as conflicting with itself`() {
        harness.store.persist(serverApps: [ServerAppFixture.files])
        harness.store.setShortcut(commandOne, forAppID: "files")

        // This is what lets a settings row re-record the shortcut it already displays.
        #expect(harness.store.nameOfApp(usingShortcut: commandOne, otherThanAppID: "files") == nil)
    }

    @Test
    func `The app holding a combination is named for another app`() {
        harness.store.persist(serverApps: [ServerAppFixture.files, ServerAppFixture.photos])
        harness.store.setShortcut(commandOne, forAppID: "files")

        #expect(harness.store.nameOfApp(usingShortcut: commandOne, otherThanAppID: "photos") == "Files")
    }

    @Test
    func `An unassigned combination names no app`() {
        harness.store.persist(serverApps: ServerAppFixture.all)

        #expect(harness.store.nameOfApp(usingShortcut: commandOne, otherThanAppID: "files") == nil)
    }

    @Test
    func `The suppressed app of a duplicate is not named as the occupant`() {
        harness.store.persist(serverApps: [ServerAppFixture.files, ServerAppFixture.photos])
        harness.store.setShortcut(commandOne, forAppID: "files")
        harness.store.setShortcut(commandOne, forAppID: "photos")

        // "Files" holds the combination and "Photos" is the suppressed duplicate. Naming "Photos" to the row that
        // visibly holds it — or naming anything at all to "Files" — is the contradiction `appHolding(_:)` prevents:
        // the row showing ⌘1 must be able to re-record it, and the row showing nothing must be told who has it.
        #expect(harness.store.nameOfApp(usingShortcut: commandOne, otherThanAppID: "photos") == "Files")
        #expect(harness.store.nameOfApp(usingShortcut: commandOne, otherThanAppID: "files") == nil)
    }
}
