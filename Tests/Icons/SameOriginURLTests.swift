// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

///
/// `SameOriginURLTests` covers `SameOriginURL`, which decides whether a path a Nextcloud server named may be requested with the user's credentials attached.
///
/// This is a security boundary rather than a convenience, and it is worth saying which attack it closes: the app asks the server what its apps are, the server answers with paths — where each app lives, and where its icon lives — and the app requests both with the app password in an `Authorization` header. An app able to name an off-origin URL in either would be handed the credential. Every case below is one spelling of that attempt, or one spelling of the legitimate value it has to keep accepting.
///
struct SameOriginURLTests {
    ///
    /// The server every case resolves against.
    ///
    private static let server = URL(string: "https://cloud.example.com")!

    @Test
    func `A server-root-relative path resolves against the server`() throws {
        let asset = try #require(SameOriginURL(path: "/apps/files/img/app.svg", relativeTo: Self.server))

        #expect(asset.url.absoluteString == "https://cloud.example.com/apps/files/img/app.svg")
    }

    @Test
    func `An absolute URL on the same server is accepted as it is`() throws {
        let asset = try #require(SameOriginURL(path: "https://cloud.example.com/core/img/logo.svg", relativeTo: Self.server))

        #expect(asset.url.absoluteString == "https://cloud.example.com/core/img/logo.svg")
    }

    @Test
    func `An absolute URL on another server is refused`() {
        #expect(SameOriginURL(path: "https://evil.example/x.svg", relativeTo: Self.server) == nil)
    }

    @Test
    func `A protocol-relative URL is refused rather than read as a path`() {
        #expect(SameOriginURL(path: "//evil.example/x.svg", relativeTo: Self.server) == nil)
    }

    @Test
    func `A different scheme is a different origin`() {
        #expect(SameOriginURL(path: "http://cloud.example.com/x.svg", relativeTo: Self.server) == nil)
    }

    @Test
    func `A different port is a different origin`() {
        #expect(SameOriginURL(path: "https://cloud.example.com:8443/x.svg", relativeTo: Self.server) == nil)
    }

    @Test
    func `A port written out that the scheme already implies is the same origin`() throws {
        let asset = try #require(SameOriginURL(path: "https://cloud.example.com:443/x.svg", relativeTo: Self.server))

        #expect(asset.url.host() == "cloud.example.com")
    }

    @Test
    func `Traversal cannot leave the origin`() throws {
        let asset = try #require(SameOriginURL(path: "/apps/../../../etc/passwd", relativeTo: Self.server))

        #expect(asset.url.host() == "cloud.example.com")
    }

    @Test
    func `A subpath install resolves a root-relative path against the origin`() throws {
        let subpath = try #require(URL(string: "https://cloud.example.com/nextcloud/"))
        // Nextcloud writes its own web root into the value, so the path is already `/nextcloud/apps/…` when it needs to be.
        let asset = try #require(SameOriginURL(path: "/nextcloud/apps/files/img/app.svg", relativeTo: subpath))

        #expect(asset.url.absoluteString == "https://cloud.example.com/nextcloud/apps/files/img/app.svg")
    }

    @Test
    func `A path that is not a URL at all is refused`() {
        #expect(SameOriginURL(path: "", relativeTo: Self.server) == nil)
    }
}
