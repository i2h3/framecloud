// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit

/// `KeyboardShortcutTransferObject` is a value-type snapshot of a user-assigned key equivalent for a server app, persisted by `AccountStore` as a `KeyboardShortcut` and applied to the app's menu items.
///
/// It stores the key equivalent character and the raw value of the `NSEvent.ModifierFlags`; `ShortcutRecorderView` produces it and the menu builder applies it to `NSMenuItem.keyEquivalent` and `keyEquivalentModifierMask`. It is `Sendable` so it can cross actors without exposing a managed `@Model` object.
struct KeyboardShortcutTransferObject: Codable, Equatable, Sendable {
    /// `keyEquivalent` is the character that triggers the shortcut, as assigned to `NSMenuItem.keyEquivalent`.
    let keyEquivalent: String

    /// `modifierFlags` is the raw value of the `NSEvent.ModifierFlags` required by the shortcut, assigned (via `modifierMask`) to `NSMenuItem.keyEquivalentModifierMask`.
    let modifierFlags: UInt

    /// `modifierMask` reconstructs the `NSEvent.ModifierFlags` from `modifierFlags` for assignment to a menu item.
    var modifierMask: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlags)
    }
}
