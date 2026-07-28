// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
@testable import Cirruscope

/// `KeyEquivalentProbe` answers what real AppKit does with a key equivalent: whether an `NSMenuItem` declaring one shortcut fires for the keystroke behind another.
///
/// It is the oracle `KeyEquivalentMatchingOracleTests` measures `ShortcutMatching.areEquivalent(_:_:)` against, so that comparison is checked against AppKit's actual behavior rather than against a restatement of what the app believes it to be — the belief is exactly what was wrong before (see `ShortcutMatching.matchedModifiers(of:)`). Each probe builds a throwaway menu with one enabled item and hands `NSMenu.performKeyEquivalent(with:)` a synthesized key-down event, which is the same entry point AppKit uses for the real menu bar.
///
/// `NSObject` is the superclass because the probe is also the item's action target; the fired flag records that the item matched. Everything is `@MainActor` since `NSMenu` is.
@MainActor
final class KeyEquivalentProbe: NSObject {
    /// `didFire` is `true` once the menu item's action reached this probe, meaning AppKit considered the event a match for the item's key equivalent.
    private var didFire = false

    @objc
    private func fire(_: Any?) {
        didFire = true
    }

    /// `fires(keystroke:againstItemDeclaring:)` is `true` when a menu item declaring `item` is triggered by the keystroke a user pressing `keystroke` produces.
    ///
    /// The item is force-enabled and `autoenablesItems` turned off because AppKit will not perform a key equivalent for an item it considers disabled, and a throwaway menu has no responder chain to validate against — without that, every probe answers `false` and the oracle would vacuously agree with anything.
    static func fires(keystroke: AppShortcutTransferObject, againstItemDeclaring item: AppShortcutTransferObject) -> Bool {
        let probe = KeyEquivalentProbe()
        let menu = NSMenu()
        menu.autoenablesItems = false

        let menuItem = NSMenuItem(title: "Probe", action: #selector(fire(_:)), keyEquivalent: item.keyEquivalent)
        menuItem.keyEquivalentModifierMask = item.modifierMask
        menuItem.target = probe
        menuItem.isEnabled = true
        menu.addItem(menuItem)

        menu.performKeyEquivalent(with: keyDown(for: keystroke))
        return probe.didFire
    }

    /// `keyDown(for:)` synthesizes the key-down event AppKit would deliver for `shortcut`.
    ///
    /// `.function` is added for a function-region key because AppKit sets that flag on every key-down in that region regardless of the physical fn key, while `AppShortcutTransferObject` never stores it (`ShortcutRecorderView.handle(keyCode:modifierFlags:charactersIgnoringModifiers:)` keeps only Command, Option, Control, and Shift) — so leaving it out would make the probe measure an event the user cannot actually produce. `charactersIgnoringModifiers` equals `characters` here because that is what the recorder stored the key equivalent from in the first place, Shift included.
    private static func keyDown(for shortcut: AppShortcutTransferObject) -> NSEvent {
        var flags = shortcut.modifierMask

        if ShortcutMatching.isFunctionRegionKey(shortcut.keyEquivalent) {
            flags.insert(.function)
        }

        // Force-unwrapped deliberately: these arguments are always a valid key-down event, and a `nil` here is a
        // broken probe rather than a test expectation worth reporting through.
        return NSEvent.keyEvent(with: .keyDown,
                                location: .zero,
                                modifierFlags: flags,
                                timestamp: 0,
                                windowNumber: 0,
                                context: nil,
                                characters: shortcut.keyEquivalent,
                                charactersIgnoringModifiers: shortcut.keyEquivalent,
                                isARepeat: false,
                                keyCode: 0)!
    }
}
