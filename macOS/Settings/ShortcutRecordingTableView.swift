// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit

/// `ShortcutRecordingTableView` is the "Server Apps" settings table's `NSTableView`, overridden only so its `ShortcutRecorderView` cells can become first responder from a plain click.
///
/// `NSTableView`'s own `validateProposedFirstResponder(_:for:)` vetoes a click that would make a view-based cell first responder, treating it as a passive label rather than an interactive control; without this override, `ShortcutRecorderView.mouseDown(with:)`'s `makeFirstResponder(self)` call is silently ignored and clicking a row never starts recording.
class ShortcutRecordingTableView: NSTableView {
    override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool {
        if responder is ShortcutRecorderView {
            return true
        }

        return super.validateProposedFirstResponder(responder, for: event)
    }
}
