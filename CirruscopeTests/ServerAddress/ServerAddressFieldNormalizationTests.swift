// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
@testable import Cirruscope
import Testing

/// `ServerAddressFieldNormalizationTests` measures the AppKit behaviour `ServerAddressViewController` depends on: that a text field carrying `ServerAddressFormatter` shows the canonical server address once editing ends, and that reading `stringValue` while editing is still in progress already yields it.
///
/// It exists because that is an assumption about the framework rather than about the app — `NSControl.validateEditing()` runs the formatter before `NSTextField.textDidEndEditing(_:)` notifies the delegate or sends the field's action, and `NSControl.stringValue`'s getter runs it too while a cell is being edited — and per `AGENTS.md` such assumptions are asserted against the framework itself, the way `KeyEquivalentProbe` does for key equivalents. A test that only exercised `ServerAddressFormatter` in isolation could not catch either ordering changing.
@MainActor
@Suite(.serialized)
struct ServerAddressFieldNormalizationTests {
    /// `makeField()` builds an editable text field carrying `ServerAddressFormatter` inside a real window, so editing can be begun and ended through the same first-responder machinery AppKit itself uses.
    ///
    /// The window is returned alongside the field because it owns the field editor: without being in a window, the field has no `currentEditor()` to type into and never ends editing.
    private func makeField() -> (window: NSWindow, field: NSTextField) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))

        field.formatter = ServerAddressFormatter()
        window.contentView?.addSubview(field)

        return (window, field)
    }

    @Test
    func `A host name entered without a scheme is completed once editing ends`() throws {
        let (window, field) = makeField()

        #expect(window.makeFirstResponder(field))
        try #require(field.currentEditor()).string = "localhost"
        #expect(window.makeFirstResponder(nil))

        #expect(field.stringValue == "https://localhost")
    }

    @Test
    func `Reading the field while it is still being edited already yields the canonical address`() throws {
        let (window, field) = makeField()

        #expect(window.makeFirstResponder(field))
        try #require(field.currentEditor()).string = "  localhost  "

        #expect(field.stringValue == "https://localhost")
    }

    @Test
    func `A blank field is left blank rather than gaining a bare scheme`() throws {
        let (window, field) = makeField()

        #expect(window.makeFirstResponder(field))
        try #require(field.currentEditor()).string = "   "
        #expect(window.makeFirstResponder(nil))

        #expect(field.stringValue.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    @Test
    func `An address the app cannot use is left exactly as it was typed`() throws {
        // The formatter never fails, so `ServerAddressViewController.open(_:)` can explain the problem instead of the user being held in the field.
        let (window, field) = makeField()

        #expect(window.makeFirstResponder(field))
        try #require(field.currentEditor()).string = "ftp://host"
        #expect(window.makeFirstResponder(nil))

        #expect(field.stringValue == "ftp://host")
    }
}
