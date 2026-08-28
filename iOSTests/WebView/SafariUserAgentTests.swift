// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

///
/// `SafariUserAgentTests` covers `SafariUserAgent`, the application name the web view is given so Nextcloud reads it as Safari rather than as an unrecognized browser.
///
/// Half of what it asserts is about the app's own value and half about WebKit, because the value is only correct in terms of what WebKit does with it. `SafariUserAgentProbe` measures that, and the cases here assert the two agree — a string that looks right in isolation is worth nothing if a `WebPage` appends it somewhere else, or if it stopped needing to be appended at all.
/// The regression these guard against is a real one the macOS app already had (issue #15): a web view that names the app is a web view Nextcloud warns about by name.
///
@MainActor
struct SafariUserAgentTests {
    @Test
    func `The application name completes the user agent into one Safari sends`() {
        let version = ProcessInfo.processInfo.operatingSystemVersion

        #expect(SafariUserAgent.applicationName == "Version/\(version.majorVersion).\(version.minorVersion) Mobile/15E148 Safari/604.1")
    }

    @Test
    func `A page identifies itself as Safari of the system's own version`() async throws {
        let reported = try #require(try await SafariUserAgentProbe.reportedUserAgent(applicationName: SafariUserAgent.applicationName))
        let version = ProcessInfo.processInfo.operatingSystemVersion

        #expect(reported.hasSuffix(SafariUserAgent.applicationName))
        #expect(reported.contains("Version/\(version.majorVersion).\(version.minorVersion)"))
        #expect(reported.contains("Safari/"))
        #expect(!reported.contains("Cirruscope"))
    }

    @Test
    func `A page left to itself names no browser at all`() async throws {
        let reported = try #require(try await SafariUserAgentProbe.reportedUserAgent(applicationName: nil))

        #expect(!reported.contains("Safari"))
        #expect(!reported.contains("Version/"))
    }
}
