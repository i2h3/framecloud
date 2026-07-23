// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

/// `KeyboardShortcut` is the SwiftData record for the keyboard shortcut a user assigns to a `ServerApp`, persisted so shortcuts survive relaunches and app-list refreshes.
///
/// It is the persistent counterpart of the value-type `KeyboardShortcutTransferObject` DTO; `AccountStore` maps between them. It hangs off its `app` with a cascade delete rule, so removing the app removes the shortcut and there is no separate pruning step.
@Model
final class KeyboardShortcut {
    /// `keyEquivalent` is the character that triggers the shortcut, as assigned to `NSMenuItem.keyEquivalent`.
    var keyEquivalent: String

    /// `modifierFlags` is the raw value of the `NSEvent.ModifierFlags` required by the shortcut.
    var modifierFlags: UInt

    /// `app` is the server app this shortcut belongs to; it is the inverse of `ServerApp.shortcut`.
    var app: ServerApp?

    init(keyEquivalent: String, modifierFlags: UInt, app: ServerApp? = nil) {
        self.keyEquivalent = keyEquivalent
        self.modifierFlags = modifierFlags
        self.app = app
    }
}
