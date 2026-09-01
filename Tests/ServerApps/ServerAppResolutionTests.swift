// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

///
/// `ServerAppResolutionTests` covers `app(for:on:)`, which decides which of a server's apps a loaded page belongs to.
///
/// Two surfaces read it and neither can afford to be wrong in the same way. The iPhone titles its navigation bar with the answer, where a miss is merely a longer title; the Mac decides whether a window is already showing an app, where a miss opens a second window for a page the user already has open. So the cases below are less about the ordinary answer than about the ways a plausible implementation gets it wrong: a string prefix that matches a differently named app, a spelling of the same path the server chose for its own reasons, and a page on a host that only looks like the right one.
/// Results are compared on `id`, `ServerAppTransferObject` being `Codable, Identifiable, Sendable` and deliberately not `Equatable`.
///
struct ServerAppResolutionTests {
    ///
    /// An instance at the root of its host, which is how most are installed.
    ///
    private static let server = URL(string: "https://cloud.example.com")!

    ///
    /// An instance installed in a subdirectory, whose web root is part of every path it names.
    ///
    private static let subpathServer = URL(string: "https://cloud.example.com/nextcloud/")!

    ///
    /// Three apps as a server reports them, including the pair whose names share a prefix.
    ///
    private static let apps = [
        ServerAppTransferObject(id: "files", order: 0, href: "/apps/files/", name: "Files"),
        ServerAppTransferObject(id: "files_sharing", order: 1, href: "/apps/files_sharing/", name: "File Sharing"),
        ServerAppTransferObject(id: "spreed", order: 2, href: "/apps/spreed/", name: "Talk"),
    ]

    ///
    /// Resolves `address` against `apps` and answers the identifier of the app it belongs to, or `nil`.
    ///
    private func resolve(_ address: String, in apps: [ServerAppTransferObject] = ServerAppResolutionTests.apps, on server: URL = ServerAppResolutionTests.server) throws -> String? {
        let url = try #require(URL(string: address))

        return apps.app(for: url, on: server)?.id
    }

    // MARK: - The Ordinary Answer

    @Test
    func `An app's own address resolves to it`() throws {
        #expect(try resolve("https://cloud.example.com/apps/files/") == "files")
    }

    @Test
    func `A trailing slash is not part of the question`() throws {
        #expect(try resolve("https://cloud.example.com/apps/files") == "files")
    }

    @Test
    func `A page deep inside an app resolves to that app`() throws {
        #expect(try resolve("https://cloud.example.com/apps/files/files/12?dir=/Photos#top") == "files")
    }

    // MARK: - Spellings The Server Chooses

    @Test
    func `An app is recognized on an instance without pretty URLs`() throws {
        #expect(try resolve("https://cloud.example.com/index.php/apps/spreed/") == "spreed")
    }

    @Test
    func `An app whose own path carries index.php is recognized without it`() throws {
        // The reverse of the case above: the navigation endpoint answered with the long spelling and the
        // server redirected to the short one.
        let apps = [ServerAppTransferObject(id: "files", order: 0, href: "/index.php/apps/files/", name: "Files")]

        #expect(try resolve("https://cloud.example.com/apps/files/", in: apps) == "files")
    }

    @Test
    func `An app is recognized on an instance installed in a subdirectory`() throws {
        // Nextcloud writes its own web root into the href, so both sides carry it and both must shed it.
        let apps = [ServerAppTransferObject(id: "files", order: 0, href: "/nextcloud/apps/files/", name: "Files")]

        #expect(try resolve("https://cloud.example.com/nextcloud/apps/files/files/12", in: apps, on: Self.subpathServer) == "files")
    }

    // MARK: - Ways To Get It Wrong

    @Test
    func `An app is not confused with one whose path its own path begins`() throws {
        // The case a string prefix fails: "/apps/files/" is not a prefix of "/apps/files_sharing/", however
        // the two read as text. Both apps are present so the wrong answer is available to be given.
        #expect(try resolve("https://cloud.example.com/apps/files_sharing/list") == "files_sharing")
    }

    @Test
    func `The most specific app wins where one is served inside another`() throws {
        let apps = [
            ServerAppTransferObject(id: "files", order: 0, href: "/apps/files/", name: "Files"),
            ServerAppTransferObject(id: "files_new", order: 1, href: "/apps/files/new/", name: "New Files"),
        ]

        #expect(try resolve("https://cloud.example.com/apps/files/new/12", in: apps) == "files_new")
        #expect(try resolve("https://cloud.example.com/apps/files/files/12", in: apps) == "files")
    }

    @Test
    func `An app claiming the instance root does not swallow every page`() throws {
        // No server offers such an entry. If a malformed answer produced one, its path would prefix every
        // URL on the instance and it would be the answer to every question asked here.
        let apps = [
            ServerAppTransferObject(id: "everything", order: 0, href: "/", name: "Everything"),
            ServerAppTransferObject(id: "files", order: 1, href: "/apps/files/", name: "Files"),
        ]

        #expect(try resolve("https://cloud.example.com/settings/user", in: apps) == nil)
        #expect(try resolve("https://cloud.example.com/apps/files/", in: apps) == "files")
    }

    // MARK: - Identifier As The Second Rule

    @Test
    func `An app named differently from its own path resolves by that path`() throws {
        // What `href`-first buys: the identifier here is not the path segment, and the path is what the
        // server actually serves the app at.
        let apps = [ServerAppTransferObject(id: "talk", order: 0, href: "/apps/spreed/", name: "Talk")]

        #expect(try resolve("https://cloud.example.com/apps/spreed/", in: apps) == "talk")
    }

    @Test
    func `An app is recognized by its identifier where no path matched`() throws {
        // The second rule's own case: an entry served from somewhere other than its own name, which is how
        // the External Sites app files its links.
        let apps = [ServerAppTransferObject(id: "photos", order: 0, href: "/apps/memories/", name: "Photos")]

        #expect(try resolve("https://cloud.example.com/apps/photos/", in: apps) == "photos")
    }

    // MARK: - Pages Belonging To No App

    @Test(arguments: [
        "https://cloud.example.com/settings/user",
        "https://cloud.example.com/settings/apps",
        "https://cloud.example.com/u/admin",
        "https://cloud.example.com/",
        "https://cloud.example.com/apps/notes/",
    ])
    func `A page under none of the server's apps resolves to none of them`(address: String) throws {
        // The middle two are real routes registered at the server's own root, like Talk's conversation
        // route below, and are deliberately not mapped: the app-management and profile pages belong to no
        // app the navigation endpoint offers, so there is no name to resolve them to.
        #expect(try resolve(address) == nil)
    }

    @Test(arguments: [
        "https://evil.example/apps/files/",
        "http://cloud.example.com/apps/files/",
        "https://cloud.example.com:8443/apps/files/",
    ])
    func `A page on another server belongs to none of this one's apps`(address: String) throws {
        #expect(try resolve(address) == nil)
    }

    @Test
    func `A page beside the instance belongs to none of its apps`() throws {
        let apps = [ServerAppTransferObject(id: "files", order: 0, href: "/nextcloud/apps/files/", name: "Files")]

        #expect(try resolve("https://cloud.example.com/owncloud/apps/files/", in: apps, on: Self.subpathServer) == nil)
    }

    @Test
    func `An empty app list resolves nothing`() throws {
        #expect(try resolve("https://cloud.example.com/apps/files/", in: []) == nil)
    }

    // MARK: - Routes An App Owns Outside Its Own Prefix

    @Test
    func `A Talk conversation resolves to Talk`() throws {
        // The case this rule exists for. Talk's router leaves `/apps/spreed/` the moment a conversation is
        // opened, and `/call/<token>` names its owner nowhere.
        #expect(try resolve("https://cloud.example.com/call/abc123") == "spreed")
    }

    @Test
    func `A Talk conversation resolves on an instance without pretty URLs`() throws {
        #expect(try resolve("https://cloud.example.com/index.php/call/abc123") == "spreed")
    }

    @Test
    func `A Talk conversation resolves where Talk's own path is given as a full URL`() throws {
        // Measured rather than imagined: of the apps a current server offers, Talk is the one whose
        // navigation entry carries an absolute href while every other carries a relative path.
        let apps = [ServerAppTransferObject(id: "spreed", order: 0, href: "https://cloud.example.com/apps/spreed/", name: "Talk")]

        #expect(try resolve("https://cloud.example.com/call/abc123", in: apps) == "spreed")
        #expect(try resolve("https://cloud.example.com/apps/spreed/", in: apps) == "spreed")
    }

    @Test
    func `A conversation resolves to Talk even where its identifier is not its path segment`() throws {
        // Why the route maps to Talk's path rather than to its identifier: the same comparison every other
        // app goes through then covers this too, with no second rule to keep in step.
        let apps = [ServerAppTransferObject(id: "talk", order: 0, href: "/apps/spreed/", name: "Talk")]

        #expect(try resolve("https://cloud.example.com/call/abc123", in: apps) == "talk")
    }

    @Test
    func `A conversation on a server without Talk resolves to nothing`() throws {
        let apps = [ServerAppTransferObject(id: "files", order: 0, href: "/apps/files/", name: "Files")]

        #expect(try resolve("https://cloud.example.com/call/abc123", in: apps) == nil)
    }

    @Test
    func `An app served under a mapped segment is not mistaken for the app that segment belongs to`() throws {
        // Each `href` is compared as the literal path it is, so mapping `call` to Talk does not also rewrite
        // an entry that happens to be served beneath `call`. Listed before Talk on purpose: were the `href`
        // side canonicalized too, both would reduce to Talk's path at equal depth and the first would win.
        let apps = [
            ServerAppTransferObject(id: "callback", order: 0, href: "/call/mine/", name: "Callback"),
            ServerAppTransferObject(id: "spreed", order: 1, href: "/apps/spreed/", name: "Talk"),
        ]

        #expect(try resolve("https://cloud.example.com/call/abc123", in: apps) == "spreed")
    }
}
