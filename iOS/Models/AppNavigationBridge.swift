// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import WebKit

///
/// Receives what `Script.sidebarToggleState` reports about Nextcloud's app-navigation toggle, so `NextcloudView` can show its own toolbar control only where there is one and reflect whether it is currently open.
///
/// It is a class, and an `NSObject` at that, because WebKit requires one: `WKScriptMessageHandler` is a class-bound Objective-C protocol and a SwiftUI `View` is a struct, so there has to be an object for `WKUserContentController` to deliver messages to. It holds no view state and makes no decisions of its own — everything here is the page's answer, restated.
/// `NextcloudView.init()` registers it on the `WebPage.Configuration` before building the page, which is the only moment that works: the configuration is a struct the page copies, so a handler added afterwards would never be reached.
///
@Observable
@MainActor
final class AppNavigationBridge: NSObject, WKScriptMessageHandler {
    ///
    /// The name `Script.sidebarToggleState` posts to, and the name the handler is registered under.
    ///
    /// It matches the macOS `ScriptMessageName.sidebarToggleState` case because both platforms run the same script; the string lives in both places rather than in a shared type because it is the script's own vocabulary, and the script is what defines it.
    ///
    static let messageName = "sidebarToggleState"

    ///
    /// Whether the loaded Nextcloud app offers an app-navigation toggle at all.
    ///
    /// Not every app has one — the Dashboard, for instance — which is why the toolbar control is hidden rather than disabled when this is `false`.
    ///
    private(set) var isAvailable = false

    ///
    /// Whether Nextcloud's app navigation is currently shown.
    ///
    private(set) var isExpanded = false

    ///
    /// Records what the page reports under the `AppNavigationBridge` category.
    ///
    private let logger = Logger(for: AppNavigationBridge.self)

    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else {
            logger.error("Received an app-navigation state message with an unexpected body")
            return
        }

        isAvailable = body["available"] as? Bool ?? false
        isExpanded = body["expanded"] as? Bool ?? false
    }
}
