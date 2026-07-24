// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os

/// `WebViewScript` enumerates the JavaScript resources bundled with the app that `WebViewController` injects into or evaluates within its `WKWebView`.
///
/// Each case maps to a `.js` file of the same name in the `Scripts` group, which keeps the scripts in standalone files that can be edited with JavaScript tooling instead of being embedded as string literals in Swift source.
/// `WebViewController` reads `source` at the moment it needs a script, either to install it as a `WKUserScript` via `installUserScript(_:injectionTime:)` or to evaluate it on demand with `WKWebView.evaluateJavaScript(_:)`.
enum WebViewScript: String {
    /// `windowDrag` forwards `mousedown` events that land on Nextcloud's header to the `windowDrag` message handler so the host window can begin a drag.
    ///
    /// `WebViewController.installWindowDragBridge()` installs it as a user script that runs at the end of every document load.
    case windowDrag = "WindowDrag"

    /// `sidebarToggleState` observes Nextcloud's sidebar toggle and reports its availability and expanded state through the `sidebarToggleState` message handler.
    ///
    /// `WebViewController.installSidebarToggleBridge()` installs it as a user script that runs at the end of every document load.
    case sidebarToggleState = "SidebarToggleState"

    /// `sidebarToggle` clicks Nextcloud's sidebar toggle to show or hide the sidebar.
    ///
    /// `WebViewController.toggleSidebar(_:)` evaluates it on demand when the user activates the "Show/Hide Sidebar" menu item.
    case sidebarToggle = "SidebarToggle"

    /// `notificationBridge` overrides the web Notification API so notifications created by the Nextcloud web interface are forwarded to the `notification` message handler instead of being lost.
    ///
    /// `WebViewController.installNotificationBridge()` installs it as a user script that runs at the start of every document load, before the page's own scripts read the API.
    case notificationBridge = "NotificationBridge"

    /// `appearanceAttributes` sets the `data-cirruscope-translucency`, `data-cirruscope-full-width`, `data-cirruscope-accent`, and `data-cirruscope-accent-bright` attributes on `<html>` that `Cirruscope.css` scopes its translucency, full-width, and accent-color rules to, along with the `--cirruscope-accent-color` custom property those accent rules re-derive Nextcloud's primary color family from.
    ///
    /// Unlike the other cases its resource is a function expression rather than a self-invoking script: `WebViewController.appearanceAttributeScript()` invokes it with the account's current appearance settings and the app's effective accent color, both to install it as a document-start user script and to re-apply it on demand with `WKWebView.evaluateJavaScript(_:)`.
    case appearanceAttributes = "AppearanceAttributes"

    /// `logger` records failures to load a bundled script under the `WebViewScript` category.
    private static let logger = Logger(for: WebViewScript.self)

    /// `source` is the JavaScript text of the bundled `.js` resource backing this case, or `nil` if the resource is missing from the bundle or cannot be decoded as UTF-8.
    ///
    /// It is read lazily at the point of use so edits to the underlying `.js` file take effect without any change to Swift source.
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
