// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os

///
/// `Script` enumerates the JavaScript resources both apps inject into or evaluate within their web view.
///
/// Each case maps to a `.js` file of the same name in `Cirruscope/Scripts/`, which keeps the scripts in standalone files that can be edited with JavaScript tooling instead of being embedded as string literals in Swift source.
/// It lives here rather than in `Core/` because only the two apps drive a web view; the widget extension has none. macOS's own `WebViewScript` enumerates the four scripts that are macOS-only — window dragging, the ⌃⌘S claim, the appearance attributes, and the notification bridge — and this holds the two that turned out to be the same job on both platforms.
///
enum Script: String {
    ///
    /// `sidebarToggle` clicks Nextcloud's app-navigation toggle to show or hide the navigation.
    ///
    /// `WebViewController.toggleSidebar(_:)` evaluates it on demand from the "Show/Hide Sidebar" menu item, and `NextcloudView.toggleAppNavigation()` from its toolbar toggle.
    ///
    case sidebarToggle = "SidebarToggle"

    ///
    /// `sidebarToggleState` observes Nextcloud's app-navigation toggle and reports its availability and expanded state through the `sidebarToggleState` message handler.
    ///
    /// Both apps install it as a user script that runs at the end of every document load. Its `MutationObserver` is what carries it across Nextcloud's single-page navigations, which never reload the document and so never re-run the script itself.
    ///
    case sidebarToggleState = "SidebarToggleState"

    ///
    /// Records failures to load a bundled script under the `Script` category.
    ///
    private static let logger = Logger(for: Script.self)

    ///
    /// The JavaScript text of the bundled `.js` resource backing this case, or `nil` if the resource is missing from the bundle or cannot be decoded as UTF-8.
    ///
    /// It is read lazily at the point of use so edits to the underlying `.js` file take effect without any change to Swift source. The lookup is by name against the flat bundle, which is why moving these resources between source folders does not disturb either app.
    ///
    var source: String? {
        guard
            let url = Bundle.main.url(forResource: rawValue, withExtension: "js"),
            let source = try? String(contentsOf: url, encoding: .utf8)
        else {
            Self.logger.error("Could not load bundled script resource \(rawValue).js")
            return nil
        }

        return source
    }
}
