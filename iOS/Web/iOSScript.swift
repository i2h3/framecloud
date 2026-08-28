// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os

///
/// `iOSScript` enumerates the JavaScript resources bundled with the iOS app that `NextcloudView` injects into or evaluates within its `WebPage`.
///
/// Each case maps to a `.js` file of the same name in `iOS/Scripts/`, which keeps the scripts in standalone files that can be edited with JavaScript tooling instead of being embedded as string literals in Swift source.
/// These are the scripts only iOS runs, as `macOSScript` holds those only macOS runs and `Script` the ones both apps share. A case here rather than in `Script` is what keeps the macOS bundle from being asked for a resource it does not carry, which would fail to load and be logged on every launch of the shipped app.
///
enum iOSScript: String {
    ///
    /// `safeAreaInsets` publishes the margins the app's own interface covers onto `<html>` as the four `--cirruscope-safe-area-*` custom properties `Cirruscope.css` insets Nextcloud's content by.
    ///
    /// Its resource is a function expression rather than a self-invoking script, as `macOSScript.appearanceAttributes` is: `NextcloudView` invokes it with the measurements SwiftUI took, both to install it as a document-start user script and to push a new measurement into a page already on screen.
    ///
    case safeAreaInsets = "SafeAreaInsets"

    ///
    /// Records failures to load a bundled script under the `iOSScript` category.
    ///
    private static let logger = Logger(for: iOSScript.self)

    ///
    /// The JavaScript text of the bundled `.js` resource backing this case, or `nil` if the resource is missing from the bundle or cannot be decoded as UTF-8.
    ///
    /// It is read lazily at the point of use so edits to the underlying `.js` file take effect without any change to Swift source.
    ///
    var source: String? {
        guard let url = Bundle.main.url(forResource: rawValue, withExtension: "js") else {
            Self.logger.error("Could not find bundled script resource \(self.rawValue).js")
            return nil
        }

        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            Self.logger.error("Could not decode bundled script resource \(self.rawValue).js")
            return nil
        }

        return source
    }
}
