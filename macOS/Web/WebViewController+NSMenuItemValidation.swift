// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit

/// `WebViewController`'s conformance to `NSMenuItemValidation` keeps the "Show/Hide Sidebar" menu item in sync with the state of Nextcloud's sidebar that `WebViewController` tracks via its `sidebarToggleAvailable` and `sidebarToggleExpanded` properties.
///
/// Disabling the item when no sidebar toggle is available no longer risks ⌃⌘S falling through to the loaded page (issue #59): `WebWindow.performKeyEquivalent(with:)` claims that shortcut at the window level, before the content view hierarchy — and so the hosted `WKWebView` — ever sees it, regardless of whether this item is enabled. So disabling it here is purely about presenting an accurate menu, not about correctness: a "Show/Hide Sidebar" item that does nothing when clicked would be confusing, so it is greyed out instead on a page with no sidebar toggle to control.
extension WebViewController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleSidebar(_:)) {
            menuItem.title = sidebarToggleExpanded
                ? String(localized: "Hide Sidebar", comment: "Title of the \"Show/Hide Sidebar\" menu item while Nextcloud's sidebar is currently shown.")
                : String(localized: "Show Sidebar", comment: "Title of the \"Show/Hide Sidebar\" menu item while Nextcloud's sidebar is currently hidden.")
            return sidebarToggleAvailable
        }

        return true
    }
}
