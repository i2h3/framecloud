// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os

///
/// `Script` enumerates the JavaScript both apps inject into their web view, and loads it from the bundle on demand.
///
/// Each case's raw value is the name of the resource behind it, so the JavaScript and CSS stay standalone files that can be edited with their own tooling instead of being embedded as string literals in Swift source. Lookup is by name against the flat bundle, which is why moving those resources between source folders does not disturb either app.
/// It lives here rather than in `Core/` because only the two apps drive a web view; the widget extension has none. macOS's own `macOSScript` enumerates the four scripts that are macOS-only — window dragging, the ⌃⌘S claim, the appearance attributes, and the notification bridge — and this holds what turned out to be the same job on both platforms.
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
    /// `styleSheet` appends the app's bundled `Cirruscope.css` to the document as a `<style>` element.
    ///
    /// It is the one case whose resource is not itself JavaScript: `source` reads the stylesheet and wraps it in the script that installs it, so the caller handles it exactly like the others. Both apps install it as a user script that runs at the *start* of every document load, early enough that the page never paints unstyled.
    /// Each app bundles its own `Cirruscope.css` — `macOS/Cirruscope.css` and `iOS/Cirruscope.css` — and they are deliberately different stylesheets for two very different windows. Only the loading is shared, and it can be because each target's bundle holds exactly one resource by that name.
    ///
    case styleSheet = "Cirruscope"

    ///
    /// Records failures to load a bundled resource under the `Script` category.
    ///
    private static let logger = Logger(for: Script.self)

    ///
    /// The file extension of the resource behind this case.
    ///
    private var resourceExtension: String {
        switch self {
            case .sidebarToggle, .sidebarToggleState:
                "js"

            case .styleSheet:
                "css"
        }
    }

    ///
    /// The JavaScript to inject or evaluate for this case, or `nil` if the resource behind it is missing from the bundle or cannot be decoded as UTF-8.
    ///
    /// It is read lazily at the point of use, so edits to the underlying file take effect without any change to Swift source.
    ///
    var source: String? {
        guard let contents = resourceContents else {
            return nil
        }

        switch self {
            case .sidebarToggle, .sidebarToggleState:
                return contents

            case .styleSheet:
                return Self.injection(of: contents)
        }
    }

    ///
    /// The text of the bundled resource behind this case, or `nil` when it cannot be read.
    ///
    private var resourceContents: String? {
        guard
            let url = Bundle.main.url(forResource: rawValue, withExtension: resourceExtension),
            let contents = try? String(contentsOf: url, encoding: .utf8)
        else {
            Self.logger.error("Could not load bundled resource \(self.rawValue).\(self.resourceExtension)")
            return nil
        }

        return contents
    }

    ///
    /// Wraps `styleSheet` in the script that appends it to the document as a `<style>` element.
    ///
    /// The stylesheet is carried across as a template literal, so three characters have to be escaped for it to survive as text: a backslash, a backtick — `Cirruscope.css` has several, inside its own comments — and the `${` that would otherwise open an interpolation. Nothing in either stylesheet interpolates today; the escape is here so that a rule which ever needs `${` in a `content` string does not silently truncate the whole sheet.
    /// The element is appended to `documentElement` rather than to `head`, because at document start there may not be a `head` yet. A `<style>` child of `<html>` applies just the same, and stays where it was put once the document finishes parsing.
    ///
    private static func injection(of styleSheet: String) -> String {
        let escaped = styleSheet
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "${", with: "\\${")

        return """
        (function() {
            var style = document.createElement('style');
            style.textContent = `\(escaped)`;
            document.documentElement.appendChild(style);
        })();
        """
    }
}
