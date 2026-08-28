// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// `SafariUserAgent` builds the application name `NextcloudView` appends to its web view's user agent so Nextcloud reads the page as being shown in Safari.
///
/// A `WebPage` identifies itself as no browser at all: it reports `Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko)` and stops there, with neither a `Version/` nor a `Safari/` token. Nextcloud checks a browser by its user agent and warns about one it does not recognize — Talk shows a banner of its own — and naming the app in that spot instead only makes the warning name Cirruscope. Appending what Safari itself sends completes the string into one Safari really sends, which is what macOS does too, through `applicationNameForUserAgent` on the web view in `Main.storyboard` (issue #15).
/// Only the web view is dressed this way. Sign-in still presents itself as Cirruscope, and has to: Login Flow v2 names the app password it issues after the `User-Agent` of the request that began the flow, which is Rainmaker's, from `ServerConnection.userAgent`. That is the name the user later sees in their security settings, so the two user agents are deliberately different rather than accidentally inconsistent.
///
enum SafariUserAgent {
    ///
    /// The tokens that follow WebKit's own, completing the user agent into one Safari sends.
    ///
    /// `Version/` is Safari's marketing version, which on iOS is the system's own — Safari 26.5 ships with iOS 26.5 — so it is read from `ProcessInfo` rather than written down. Writing it down is what left macOS claiming `Version/18.0` long after that Safari stopped shipping, and a browser check is exactly the thing that reacts to a version claim aging backwards. The two build numbers around it are not versions of anything that moves: `Mobile/15E148` and `Safari/604.1` are the constants Safari on iOS has sent for years, as is the `AppleWebKit/605.1.15` WebKit puts in front of them.
    ///
    static var applicationName: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion

        return "Version/\(version.majorVersion).\(version.minorVersion) Mobile/15E148 Safari/604.1"
    }
}
