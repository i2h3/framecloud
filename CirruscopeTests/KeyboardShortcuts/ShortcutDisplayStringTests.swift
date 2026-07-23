// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
@testable import Cirruscope
import Testing

/// `ShortcutDisplayStringTests` covers `ShortcutRecorderView.displayString(for:)`, which renders a stored shortcut as the symbolic text the settings tab shows.
///
/// It is pure input-to-string logic on a main-actor view type, so it is testable without instantiating the view or the settings window at all. What is worth pinning is the modifier order macOS expects (⌃⌥⇧⌘, never the order the flags happen to be stored in) and that a function-region key is rendered by name instead of as the unreadable Private Use Area scalar it is stored as.
@MainActor
struct ShortcutDisplayStringTests {
    @Test
    func `Modifiers are rendered in the order macOS uses`() {
        let all = KeyboardShortcutTransferObject(keyEquivalent: "f", modifierFlags: NSEvent.ModifierFlags([.command, .option, .control, .shift]).rawValue)
        #expect(ShortcutRecorderView.displayString(for: all) == "⌃⌥⇧⌘F")
    }

    @Test
    func `A letter is rendered uppercased regardless of how it is stored`() {
        #expect(ShortcutRecorderView.displayString(for: ShortcutFixture.named("⌘z").shortcut) == "⌘Z")
        #expect(ShortcutRecorderView.displayString(for: ShortcutFixture.named("⇧⌘Z").shortcut) == "⇧⌘Z")
    }

    @Test
    func `A function-region key is rendered by name, not as its Private Use Area scalar`() {
        #expect(ShortcutRecorderView.displayString(for: ShortcutFixture.named("F5").shortcut) == "F5")
        #expect(ShortcutRecorderView.displayString(for: ShortcutFixture.named("⇧F5").shortcut) == "⇧F5")
        #expect(ShortcutRecorderView.displayString(for: ShortcutFixture.named("↑").shortcut) == "↑")
    }

    @Test
    func `A shortcut with no modifiers renders as the bare key`() {
        #expect(ShortcutRecorderView.displayString(for: ShortcutFixture.named("F5").shortcut) == "F5")
    }
}
