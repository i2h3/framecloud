// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Testing

/// `KeyEquivalentMatchingOracleTests` checks `ShortcutMatching.areEquivalent(_:_:)` against real AppKit rather than against the app's beliefs about it, by comparing every pair of `ShortcutFixture.all` with what `KeyEquivalentProbe` measures.
///
/// This suite exists because being confidently wrong here is the failure mode with history: the comparison's first version stripped Shift from every shortcut on the strength of a documented-sounding claim that `keyEquivalentModifierMask`'s Shift bit "plays no part" in matching, which holds for letters and symbols but not for the function-region keys — so ⇧F5 was reported as already taken by an F5 shortcut. No amount of restating the rule in a unit test would have caught that; only asking `NSMenu` does. If Apple ever changes key-equivalent matching, this is where it surfaces.
///
/// The suite is serialized because every case drives `NSMenu` on the main actor, and it needs no server, network, or web view — the property under test is entirely local to AppKit.
@MainActor
@Suite(.serialized)
struct KeyEquivalentMatchingOracleTests {
    @Test(arguments: ShortcutFixture.all, ShortcutFixture.all)
    func `areEquivalent agrees with NSMenu key-equivalent matching`(pressed: ShortcutFixture, declared: ShortcutFixture) {
        let predicted = ShortcutMatching.areEquivalent(pressed.shortcut, declared.shortcut)
        let actual = KeyEquivalentProbe.fires(keystroke: pressed.shortcut, againstItemDeclaring: declared.shortcut)

        #expect(predicted == actual, "pressing \(pressed) against a menu item declaring \(declared): areEquivalent said \(predicted), AppKit \(actual ? "fired the item" : "did not fire the item")")
    }

    @Test
    func `The probe can tell a match from a miss`() {
        // Guards the oracle itself: were every probe to answer `false` — an item AppKit considers disabled never
        // performs its key equivalent — the comparison above would agree with nothing and still pass.
        #expect(KeyEquivalentProbe.fires(keystroke: ShortcutFixture.named("⌘z").shortcut, againstItemDeclaring: ShortcutFixture.named("⌘z").shortcut))
        #expect(KeyEquivalentProbe.fires(keystroke: ShortcutFixture.named("⌘z").shortcut, againstItemDeclaring: ShortcutFixture.named("⌘1").shortcut) == false)
    }
}
