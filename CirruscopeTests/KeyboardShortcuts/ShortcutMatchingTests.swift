// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
@testable import Cirruscope
import Testing

/// `ShortcutMatchingTests` covers `ShortcutMatching.areEquivalent(_:_:)`, the comparison every keyboard shortcut conflict check in the app goes through.
///
/// The cases below state the rule in the app's own terms — which shortcuts count as the same keystroke and which do not — while `KeyEquivalentMatchingOracleTests` checks the same corpus against real `NSMenu` matching. Both exist because either alone is insufficient: this suite documents intent readably and fails loudly when the rule changes, the oracle catches the rule being confidently wrong about AppKit.
struct ShortcutMatchingTests {
    @Test(arguments: ShortcutFixture.all)
    func `A shortcut is equivalent to itself`(fixture: ShortcutFixture) {
        #expect(ShortcutMatching.areEquivalent(fixture.shortcut, fixture.shortcut))
    }

    @Test(arguments: ShortcutFixture.all, ShortcutFixture.all)
    func `Equivalence does not depend on argument order`(one: ShortcutFixture, other: ShortcutFixture) {
        #expect(ShortcutMatching.areEquivalent(one.shortcut, other.shortcut) == ShortcutMatching.areEquivalent(other.shortcut, one.shortcut))
    }

    @Test
    func `The Shift bit is redundant when the key equivalent's character carries Shift`() {
        // A recorded ⇧⌘Z keeps the Shift bit; a storyboard item declaring the same shortcut may omit it. Both are
        // the one keystroke AppKit fires "Redo" for, so a conflict check has to see them as the same shortcut.
        #expect(ShortcutMatching.areEquivalent(ShortcutFixture.named("⇧⌘Z").shortcut, ShortcutFixture.named("⌘Z").shortcut))

        // Same for a symbol Shift produces: ⇧⌘! stores "!" whether or not the Shift bit rides along.
        #expect(ShortcutMatching.areEquivalent(ShortcutFixture.named("⇧⌘!").shortcut, ShortcutFixture.named("⌘!").shortcut))
    }

    @Test
    func `The key equivalent's case distinguishes two shortcuts`() {
        // "Redo" (⇧⌘Z) against "Undo" (⌘z): lowercasing the character, as an early version of this comparison did,
        // collapsed the two and reported ⇧⌘Z as taken by "Undo".
        #expect(ShortcutMatching.areEquivalent(ShortcutFixture.named("⇧⌘Z").shortcut, ShortcutFixture.named("⌘z").shortcut) == false)
    }

    @Test
    func `The Shift bit is significant for a function-region key`() {
        // F5 has no case to carry Shift in, so the modifier bit is all that separates these — and AppKit honours it,
        // which means both can be assigned to different apps at the same time.
        #expect(ShortcutMatching.areEquivalent(ShortcutFixture.named("F5").shortcut, ShortcutFixture.named("⇧F5").shortcut) == false)
        #expect(ShortcutMatching.areEquivalent(ShortcutFixture.named("⌘F5").shortcut, ShortcutFixture.named("⇧⌘F5").shortcut) == false)
        #expect(ShortcutMatching.areEquivalent(ShortcutFixture.named("↑").shortcut, ShortcutFixture.named("⇧↑").shortcut) == false)
    }

    @Test
    func `The Shift bit stays redundant for a shift-invariant typable key`() {
        // Tab and Space cannot carry Shift in their character either, which invites the assumption that they behave
        // like F5 above. They do not: AppKit ignores the bit for them, so ⌘⇥ and ⇧⌘⇥ are one shortcut, not two.
        // Treating them as distinct would let two apps claim a combination only one of them can ever receive.
        #expect(ShortcutMatching.areEquivalent(ShortcutFixture.named("⌘⇥").shortcut, ShortcutFixture.named("⇧⌘⇥").shortcut))
        #expect(ShortcutMatching.areEquivalent(ShortcutFixture.named("⌘space").shortcut, ShortcutFixture.named("⇧⌘space").shortcut))
    }

    @Test
    func `A different key equivalent is never the same shortcut`() {
        #expect(ShortcutMatching.areEquivalent(ShortcutFixture.named("⌘1").shortcut, ShortcutFixture.named("⌘z").shortcut) == false)
        #expect(ShortcutMatching.areEquivalent(ShortcutFixture.named("F5").shortcut, ShortcutFixture.named("↑").shortcut) == false)
    }

    @Test
    func `A modifier other than Shift is never discarded`() {
        #expect(ShortcutMatching.areEquivalent(ShortcutFixture.named("⌘z").shortcut, ShortcutFixture.named("⌥⌘z").shortcut) == false)
        #expect(ShortcutMatching.areEquivalent(ShortcutFixture.named("⌘z").shortcut, ShortcutFixture.named("⌃⌘z").shortcut) == false)
        #expect(ShortcutMatching.areEquivalent(ShortcutFixture.named("⌥⌘z").shortcut, ShortcutFixture.named("⌃⌘z").shortcut) == false)
    }

    @Test
    func `Only a Private Use Area key equivalent counts as a function-region key`() {
        #expect(ShortcutMatching.isFunctionRegionKey("\u{F708}"))
        #expect(ShortcutMatching.isFunctionRegionKey("\u{F700}"))
        #expect(ShortcutMatching.isFunctionRegionKey("z") == false)
        #expect(ShortcutMatching.isFunctionRegionKey("\t") == false)
        #expect(ShortcutMatching.isFunctionRegionKey(" ") == false)
        #expect(ShortcutMatching.isFunctionRegionKey("") == false)

        // A multi-scalar string is not a single key: an emoji key equivalent cannot come from the recorder, but the
        // predicate must not mistake its first scalar for the whole value.
        #expect(ShortcutMatching.isFunctionRegionKey("\u{F708}\u{F708}") == false)
    }
}
