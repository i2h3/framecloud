// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `ServerAddressFormatter` is the `Formatter` `ServerAddressViewController` attaches to `serverAddressField` so that whatever the user typed is rewritten to `ServerAddress`' canonical form the moment editing ends — pressing Return, tabbing out of the field, or clicking elsewhere — instead of being canonicalized out of sight inside `open(_:)`.
///
/// AppKit runs it from `NSControl.validateEditing()`, which `NSTextField.textDidEndEditing(_:)` performs before it notifies the field's delegate and before it sends the field's action, so the canonical address is on screen and in the cell's object value by the time either of those observes it. That ordering is the whole reason a formatter is used here rather than a delegate callback: rewriting the text from `controlTextDidEndEditing(_:)` would mean aborting the editing session AppKit is still in the middle of finishing. `ServerAddressFieldNormalizationTests` measures that ordering against a real text field rather than trusting it.
/// It is deliberately lenient: `getObjectValue(_:for:errorDescription:)` never fails. A formatter that returns `false` flags the cell as holding an invalid object and hands the error to `control(_:didFailToFormatString:errorDescription:)`, which for an address field means trapping the user in it over a typo — and, because `NSControl.stringValue`'s getter runs `validateEditing()` while editing is in progress, it would be asked to fail while they are still typing. Input it cannot normalize is therefore left exactly as typed, and deciding whether an address is usable stays with `ServerAddressViewController.open(_:)`, which reports it as an alert.
/// Its object value is an `NSString` — the canonical display string — rather than a `ServerAddress`: `NSCell.objectValue` is an Objective-C object, which that value type is not, and keeping the string leaves `serverAddressField.stringValue` as the field's single source of truth.
/// `isPartialStringValid(_:proposedSelectedRange:originalString:originalSelectedRange:errorDescription:)` is deliberately not overridden. Its default implementation accepts every intermediate string, which is what is wanted: canonicalizing per keystroke would rewrite text under the user's caret while they type.
final class ServerAddressFormatter: Formatter {
    /// `string(for:)` renders the cell's object value for display and for the field editor when editing begins.
    ///
    /// The object value needs no further work because `getObjectValue(_:for:errorDescription:)` is the only thing that produces one, and it produces either the canonical form or the input it could not normalize.
    override func string(for obj: Any?) -> String? {
        obj as? String
    }

    /// `getObjectValue(_:for:errorDescription:)` canonicalizes `string` through `ServerAddress` and hands the result back as the cell's object value, or hands back the input unchanged when it cannot be normalized.
    ///
    /// It always succeeds, for the reasons given on the type: an empty or blank field must stay empty rather than becoming a bare scheme, and an address the app cannot use must reach `open(_:)` so the user gets an explanation instead of a field they cannot leave.
    override func getObjectValue(_ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?, for string: String, errorDescription _: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        guard let address = try? ServerAddress(normalizing: string) else {
            obj?.pointee = string as NSString

            return true
        }

        obj?.pointee = address.displayString as NSString

        return true
    }
}
