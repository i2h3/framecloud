// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit

/// `ShortcutMatching` is the single definition of when two key equivalents mean the same keystroke to AppKit, so every conflict check in the app agrees on it.
///
/// `AppDelegate.reservedShortcutName(for:)` uses it to compare a shortcut against Cirruscope's own fixed menu items, and `AccountStore.nameOfApp(usingShortcut:otherThanAppID:)` to compare it against the shortcuts of the other server apps. Both questions are the same one — "would one keystroke trigger both of these?" — and its answer is subtle enough (see `matchedModifiers(of:)`) that stating it twice would invite the two from drifting apart.
enum ShortcutMatching {
    /// `areEquivalent(_:_:)` is `true` when AppKit's key-equivalent matching cannot tell `one` and `other` apart, so a single keystroke would trigger both.
    static func areEquivalent(_ one: AppShortcutTransferObject, _ other: AppShortcutTransferObject) -> Bool {
        one.keyEquivalent == other.keyEquivalent && matchedModifiers(of: one) == matchedModifiers(of: other)
    }

    /// `matchedModifiers(of:)` is the part of `shortcut`'s modifier mask that AppKit actually matches an event against: its mask as-is for a function-region key, and its mask without Shift for every other key equivalent.
    ///
    /// Both halves were measured directly against real `NSMenu.performKeyEquivalent(with:)`, because the two behave oppositely and neither is documented. For a key equivalent whose character *carries* Shift — an uppercase letter, or whichever character Shift produces on the current layout, such as `"!"` for ⇧1 — the `.shift` bit in `keyEquivalentModifierMask` plays no part at all: an item with `"Z"` matches a ⇧⌘Z event whether or not its mask names Shift, so the bit must be ignored here or a recorded ⇧⌘Z would not be recognized as the same shortcut as a menu item declaring plain `"Z"` with ⌘. The character's *case*, by contrast, is the only thing that distinguishes such shortcuts and is therefore deliberately left untouched: it is what separates "Redo" (`"Z"`, ⌘) from "Undo" (`"z"`, ⌘) — lowercasing it, as an earlier version of this comparison did, collapsed the two into one, so recording ⇧⌘Z reported a conflict with "Undo" instead of "Redo". `ShortcutRecorderView.handle(keyCode:modifierFlags:charactersIgnoringModifiers:)` correspondingly records the character exactly as `charactersIgnoringModifiers` produced it (never lowercased), so both sides of the comparison preserve case the same way.
    ///
    /// A function-region key (F-keys, arrows, Home/End, Page Up/Down, etc.) is the one exception: `AppShortcutTransferObject.keyEquivalent` stores it as the Private Use Area scalar `NSMenuItem.keyEquivalent` expects (see `ShortcutRecorderView.functionRegionKeyNames`), and AppKit does honour the `.shift` bit there, matching an item declaring F5 with Shift against a ⇧F5 event but not against a bare F5 one, and vice versa. Stripping Shift from those, as this method's first version did, would report ⇧F5 as already taken by an F5 shortcut although the two can coexist perfectly well.
    ///
    /// The tempting generalization of that exception — "the bit matters for any key equivalent whose character cannot carry Shift" — is wrong, and was measured to be so rather than reasoned about: for the shift-invariant typable keys (Tab, Space, Return), AppKit ignores the mask's Shift bit exactly as it does for letters, so ⌘Tab and ⇧⌘Tab match the same keystroke and really are one shortcut. The Private Use Area region is therefore the predicate, not caselessness. `KeyEquivalentMatchingOracleTests` pins every case here against real `NSMenu` matching, so this distinction cannot quietly rot.
    private static func matchedModifiers(of shortcut: AppShortcutTransferObject) -> NSEvent.ModifierFlags {
        isFunctionRegionKey(shortcut.keyEquivalent) ? shortcut.modifierMask : shortcut.modifierMask.subtracting(.shift)
    }

    /// `isFunctionRegionKey(_:)` is `true` when `keyEquivalent` is one of the function-region keys, which AppKit represents as a single scalar from the Unicode Private Use Area block `NSUpArrowFunctionKey` (U+F700) onwards rather than as a typable character.
    ///
    /// It is the app's single test for that region, so the same notion decides matching here, which shortcuts `ShortcutRecorderView.displayString(for:)` renders with a friendly name, and which keystrokes the test suites synthesize with `.function` set. It deliberately spans the whole block rather than the specific scalars AppKit names, since a key equivalent from anywhere in it is a key AppKit will not derive Shift from.
    static func isFunctionRegionKey(_ keyEquivalent: String) -> Bool {
        guard keyEquivalent.unicodeScalars.count == 1 else {
            return false
        }

        guard let scalar = keyEquivalent.unicodeScalars.first else {
            return false
        }

        return (0xF700 ... 0xF8FF).contains(scalar.value)
    }
}
