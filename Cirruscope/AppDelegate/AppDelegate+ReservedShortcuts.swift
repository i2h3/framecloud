// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit

/// `AppDelegate`'s reserved-shortcut lookup tells `ShortcutRecorderView` and `AccountStore.shortcut(forAppID:)` whether a server app's recorded (or already-stored) shortcut collides with one of Cirruscope's own fixed menu items, since `AppDelegate` is the one that builds and owns the live menu bar those items live in.
extension AppDelegate {
    /// `reservedShortcutName(for:)` is the title of the first menu item anywhere in `NSApp.mainMenu`'s tree — other than a dynamically-inserted server app item — whose key equivalent `shortcut` collides with, or `nil` when it collides with none.
    ///
    /// A server app's shortcut can never shadow one of Cirruscope's own fixed menu items this way — including ones in a completely different menu than the View menu's server app section, since AppKit resolves a key equivalent against the whole menu bar, not just one submenu, and there is no reliable, documented tie-break for two enabled items that share one. Reading the live menu, rather than a hand-maintained duplicate of `Main.storyboard`'s shortcuts, means this can never drift out of sync with it, and reports the item's actual (already-localized) title for free.
    ///
    /// Dynamic server app items are recognized by their action, `performServerApp(_:)`, and skipped: otherwise an already-assigned server app shortcut would collide with its own menu item (or, once two apps briefly share a shortcut mid-edit, with each other) instead of only with Cirruscope's fixed ones. Collisions *between* two server apps are therefore not this method's concern at all; `AccountStore.nameOfApp(usingShortcut:otherThanAppID:)` answers those from the stored shortcuts instead, where each app's identity is unambiguous.
    static func reservedShortcutName(for shortcut: AppShortcutTransferObject) -> String? {
        firstConflictingItem(in: NSApp.mainMenu, matching: shortcut)?.title
    }

    /// `firstConflictingItem(in:matching:)` recursively searches `menu` and its submenus for the first non-server-app item whose key equivalent `candidate` collides with, per `ShortcutMatching.areEquivalent(_:_:)`.
    private static func firstConflictingItem(in menu: NSMenu?, matching candidate: AppShortcutTransferObject) -> NSMenuItem? {
        guard let menu else {
            return nil
        }

        for item in menu.items {
            if let hit = firstConflictingItem(in: item.submenu, matching: candidate) {
                return hit
            }

            guard item.action != #selector(performServerApp(_:)),
                  item.keyEquivalent.isEmpty == false
            else {
                continue
            }

            let itemShortcut = AppShortcutTransferObject(keyEquivalent: item.keyEquivalent, modifierFlags: item.keyEquivalentModifierMask.rawValue)

            if ShortcutMatching.areEquivalent(itemShortcut, candidate) {
                return item
            }
        }

        return nil
    }
}
