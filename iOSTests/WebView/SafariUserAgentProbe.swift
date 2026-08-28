// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import WebKit

///
/// `SafariUserAgentProbe` reports what a real `WebPage` tells a page it is, given an application name.
///
/// `SafariUserAgent` exists because of an assumption about WebKit — that a `WebPage` names no browser of its own, and that what it is handed is appended to the end of the string. A test that restated that assumption could not catch it being wrong, so this drives the real thing instead and lets `SafariUserAgentTests` assert against what came back, the same way `KeyEquivalentProbe` does for AppKit in the macOS suite.
/// `about:blank` is enough: the user agent is a property of the web view rather than of anything loaded into it, so no server and no network are involved.
///
@MainActor
enum SafariUserAgentProbe {
    ///
    /// What `navigator.userAgent` reports in a `WebPage` configured with `applicationName`, or `nil` if the page returns something other than a string.
    ///
    static func reportedUserAgent(applicationName: String?) async throws -> String? {
        var configuration = WebPage.Configuration()
        configuration.applicationNameForUserAgent = applicationName

        let page = WebPage(configuration: configuration)

        for try await event in page.load(URL(string: "about:blank")!) where event == .finished {
            break
        }

        return try await page.callJavaScript("return navigator.userAgent;") as? String
    }
}
