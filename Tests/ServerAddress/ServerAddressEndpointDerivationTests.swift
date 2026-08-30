// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

/// `ServerAddressEndpointDerivationTests` measures the Foundation behaviour `ServerAddress` is built on, rather than restating what `ServerAddress` does.
///
/// Every rule about the canonical form rests on an assumption about somebody else's code, and this project has a scar from encoding such an assumption twice instead of measuring it once. Two assumptions are load-bearing here. The first is `Rainmaker.Server`'s: it derives every endpoint by appending a path to the address it was given, so the canonical form may drop a trailing slash but must not carry a query — the paths below are the ones `Server.init` appends, spelled out as literals because neither test target links Rainmaker. The second is `URL(string:)`'s: it normalizes far less than its name suggests, and each thing it leaves alone or accepts is a check `ServerAddress` has to perform itself.
struct ServerAddressEndpointDerivationTests {
    @Test(arguments: [
        "https://cloud.example.com",
        "https://cloud.example.com/",
    ])
    func `A trailing slash on the address does not change the endpoints derived from it`(address: String) throws {
        let url = try #require(URL(string: address))

        #expect(url.appending(path: "/ocs/v2.php/", directoryHint: .isDirectory).absoluteString == "https://cloud.example.com/ocs/v2.php/")
        #expect(url.appending(path: "index.php/login/v2", directoryHint: .notDirectory).absoluteString == "https://cloud.example.com/index.php/login/v2")
    }

    @Test(arguments: [
        "https://cloud.example.com/nextcloud",
        "https://cloud.example.com/nextcloud/",
    ])
    func `A subpath install is preserved by the endpoints derived from it`(address: String) throws {
        let url = try #require(URL(string: address))

        #expect(url.appending(path: "/ocs/v2.php/", directoryHint: .isDirectory).absoluteString == "https://cloud.example.com/nextcloud/ocs/v2.php/")
        #expect(url.appending(path: "index.php/login/v2", directoryHint: .notDirectory).absoluteString == "https://cloud.example.com/nextcloud/index.php/login/v2")
    }

    @Test
    func `A query on the address leaks into every endpoint derived from it`() throws {
        // This is why the canonical form drops the query and the fragment instead of merely tolerating them: the appended path lands in front of the query, which then travels with every request.
        let url = try #require(URL(string: "https://cloud.example.com/?dir=/x"))

        #expect(url.appending(path: "/ocs/v2.php/", directoryHint: .isDirectory).absoluteString == "https://cloud.example.com/ocs/v2.php/?dir=/x")
        #expect(try ServerAddress(normalizing: "https://cloud.example.com/?dir=/x").url.query == nil)
    }

    @Test
    func `An empty path segment in the address leaks into every endpoint derived from it`() throws {
        let url = try #require(URL(string: "https://cloud.example.com//"))

        #expect(url.appending(path: "/ocs/v2.php/", directoryHint: .isDirectory).absoluteString == "https://cloud.example.com//ocs/v2.php/")
        #expect(try ServerAddress(normalizing: "https://cloud.example.com//").url.path() == "")
    }

    @Test
    func `URL keeps the case of an ASCII scheme and host exactly as written`() throws {
        // Nothing lowercases these, which is why ServerAddress does.
        let url = try #require(URL(string: "HTTPS://Cloud.Example.COM"))

        #expect(url.absoluteString == "HTTPS://Cloud.Example.COM")
        #expect(url.scheme == "HTTPS")
        #expect(url.host() == "Cloud.Example.COM")
    }

    @Test
    func `URL parses a bare host and port as a scheme and a path`() throws {
        // The ambiguity the whole scheme-detection rule exists for: the first of these looks like it has a scheme and the second does not parse at all.
        let url = try #require(URL(string: "localhost:8080"))

        #expect(url.scheme == "localhost")
        #expect(url.host() == nil)
        #expect(url.path() == "8080")
        #expect(URL(string: "192.168.1.5:8080") == nil)
    }

    @Test
    func `URL accepts a host and a port that cannot work`() throws {
        // Neither of these is rejected by Foundation, so both are checked by ServerAddress.
        #expect(try #require(URL(string: "https://!!!/")).host() == "!!!")
        #expect(try #require(URL(string: "https://host:99999")).port == 99999)
    }

    @Test
    func `URL and URLComponents disagree about a missing host`() {
        // ServerAddress reads the host off URL, where a missing one is nil rather than the empty string URLComponents reports.
        #expect(URL(string: "https://")?.host() == nil)
        #expect(URLComponents(string: "https://")?.host == "")
    }

    @Test
    func `URL converts an internationalized host only in its serialized form`() throws {
        // The percent-encoded accessor returns the UTF-8 form, not the form on the wire, so the canonical string comes from absoluteString rather than from reassembled components.
        let url = try #require(URL(string: "https://bücher.example"))

        #expect(url.absoluteString == "https://xn--bcher-kva.example")
        #expect(url.host(percentEncoded: false) == "xn--bcher-kva.example")
        #expect(url.host(percentEncoded: true) == "b%C3%BCcher.example")
    }
}
