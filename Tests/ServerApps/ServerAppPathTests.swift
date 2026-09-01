// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

///
/// `ServerAppPathTests` covers `ServerAppPath`, which reduces a URL to the path it addresses within one Nextcloud instance.
///
/// Every case here is a spelling difference the server itself introduces. Nextcloud serves the same app under `/apps/…` or `/index.php/apps/…` depending on one configuration option, and an instance installed in a subdirectory writes that directory into every path it names — including the ones it reports through its own navigation endpoint. The point of this type is that two paths meaning the same page compare equal, so the cases are pairs of spellings rather than a list of inputs.
/// The logic replaced here — `WebViewController.appID(fromPath:)` — had no tests at all, and answered `nil` for every subpath install because it required `apps` to be the first component of the path. That case is below.
///
struct ServerAppPathTests {
    ///
    /// An instance at the root of its host, which is how most are installed.
    ///
    private static let server = URL(string: "https://cloud.example.com")!

    ///
    /// An instance installed in a subdirectory, whose web root is part of every path it names.
    ///
    private static let subpathServer = URL(string: "https://cloud.example.com/nextcloud/")!

    // MARK: - Relative Components

    @Test
    func `A path is reported as its components`() throws {
        let url = try #require(URL(string: "https://cloud.example.com/apps/files/files/12"))

        #expect(ServerAppPath.relativeComponents(of: url, on: Self.server) == ["apps", "files", "files", "12"])
    }

    @Test
    func `An index.php segment is not part of the path`() throws {
        let url = try #require(URL(string: "https://cloud.example.com/index.php/apps/files/"))

        #expect(ServerAppPath.relativeComponents(of: url, on: Self.server) == ["apps", "files"])
    }

    @Test
    func `A subdirectory install reports the path within itself`() throws {
        let url = try #require(URL(string: "https://cloud.example.com/nextcloud/apps/files/"))

        #expect(ServerAppPath.relativeComponents(of: url, on: Self.subpathServer) == ["apps", "files"])
    }

    @Test
    func `A subdirectory install drops its web root before index.php`() throws {
        let url = try #require(URL(string: "https://cloud.example.com/nextcloud/index.php/apps/files/"))

        #expect(ServerAppPath.relativeComponents(of: url, on: Self.subpathServer) == ["apps", "files"])
    }

    @Test
    func `The instance's own root is an empty path rather than no path`() throws {
        let url = try #require(URL(string: "https://cloud.example.com/"))

        // Distinct from `nil`, which says the URL is not on this instance at all.
        #expect(ServerAppPath.relativeComponents(of: url, on: Self.server) == [])
    }

    @Test
    func `A query and a fragment are not part of the path`() throws {
        let url = try #require(URL(string: "https://cloud.example.com/apps/files/?dir=/Photos#top"))

        #expect(ServerAppPath.relativeComponents(of: url, on: Self.server) == ["apps", "files"])
    }

    @Test
    func `A URL on another server has no path on this one`() throws {
        let url = try #require(URL(string: "https://evil.example/apps/files/"))

        #expect(ServerAppPath.relativeComponents(of: url, on: Self.server) == nil)
    }

    @Test
    func `A URL beside the instance is not a URL within it`() throws {
        let url = try #require(URL(string: "https://cloud.example.com/owncloud/apps/files/"))

        // Same origin, different web root: no more part of this instance than another host would be.
        #expect(ServerAppPath.relativeComponents(of: url, on: Self.subpathServer) == nil)
    }

    // MARK: - App Identifier

    @Test
    func `An app's identifier is read out of its path`() throws {
        let url = try #require(URL(string: "https://cloud.example.com/apps/files/files/12"))

        #expect(ServerAppPath.appID(of: url, on: Self.server) == "files")
    }

    @Test
    func `An identifier is read on an instance without pretty URLs`() throws {
        let url = try #require(URL(string: "https://cloud.example.com/index.php/apps/spreed/"))

        #expect(ServerAppPath.appID(of: url, on: Self.server) == "spreed")
    }

    @Test
    func `An identifier is read on an instance installed in a subdirectory`() throws {
        let url = try #require(URL(string: "https://cloud.example.com/nextcloud/apps/files/"))

        // The case the macOS implementation this replaces could not see: it required `apps` to come first.
        #expect(ServerAppPath.appID(of: url, on: Self.subpathServer) == "files")
    }

    @Test(arguments: [
        "https://cloud.example.com/settings/user",
        "https://cloud.example.com/apps",
        "https://cloud.example.com/apps/",
        "https://cloud.example.com/",
        "https://evil.example/apps/files/",
    ])
    func `A URL naming no app has no identifier`(address: String) throws {
        let url = try #require(URL(string: address))

        #expect(ServerAppPath.appID(of: url, on: Self.server) == nil)
    }

    // MARK: - Canonical Components

    @Test
    func `A route an app registers at the server root is reported as that app's path`() throws {
        let url = try #require(URL(string: "https://cloud.example.com/call/abc123"))

        #expect(ServerAppPath.canonicalComponents(of: url, on: Self.server) == ["apps", "spreed"])
    }

    @Test
    func `A root route is recognized on an instance without pretty URLs`() throws {
        let url = try #require(URL(string: "https://cloud.example.com/index.php/call/abc123"))

        #expect(ServerAppPath.canonicalComponents(of: url, on: Self.server) == ["apps", "spreed"])
    }

    @Test
    func `A root route is recognized on an instance installed in a subdirectory`() throws {
        let url = try #require(URL(string: "https://cloud.example.com/nextcloud/call/abc123"))

        #expect(ServerAppPath.canonicalComponents(of: url, on: Self.subpathServer) == ["apps", "spreed"])
    }

    @Test
    func `An ordinary app path is its own canonical form`() throws {
        let url = try #require(URL(string: "https://cloud.example.com/apps/files/files/12"))

        #expect(ServerAppPath.canonicalComponents(of: url, on: Self.server) == ["apps", "files", "files", "12"])
    }

    @Test(arguments: [
        "https://cloud.example.com/settings/apps",
        "https://cloud.example.com/u/admin",
    ])
    func `A root route belonging to no app is left as it is`(address: String) throws {
        // Both are real root routes on a current server — the app-management page and a user profile — and
        // neither belongs to an app the navigation endpoint offers, so neither is rewritten to one.
        let url = try #require(URL(string: address))

        #expect(ServerAppPath.canonicalComponents(of: url, on: Self.server)?.first != "apps")
    }

    @Test
    func `An identifier is read from a route an app registers at the server root`() throws {
        let url = try #require(URL(string: "https://cloud.example.com/call/abc123"))

        #expect(ServerAppPath.appID(of: url, on: Self.server) == "spreed")
    }
}
