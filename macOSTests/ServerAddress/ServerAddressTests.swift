// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Testing

/// `ServerAddressTests` covers `ServerAddress(normalizing:)`, the only place in Cirruscope that decides what a typed or pasted Nextcloud address means.
///
/// It is pure input-to-value logic with no server and no text field involved, which is what makes it testable at all, and it is worth pinning case by case because each rule is a decision about someone's data rather than a formatting detail: which scheme an input without one gets, whether an explicit `http://` survives, which part of a pasted deep link is the address of the instance and which part is the instance's own routing, and which inputs are refused outright instead of being turned into a request to somewhere unintended.
/// Every case that normalizes successfully is also asserted to be idempotent, because the canonical form is written back into the field the user then submits: normalizing it a second time must not move it again.
/// The messages are not asserted, only that each failure has one. Their text is localized, so asserting it would measure the language the machine running the tests is set to, and `macOSTests` deliberately contributes no localized strings of its own.
struct ServerAddressTests {
    @Test(arguments: [
        // An address without a scheme defaults to HTTPS, which is the visible half of this type: someone who types a bare host is shown that Cirruscope chose HTTPS for them.
        ("localhost", "https://localhost"),
        ("cloud.example.com", "https://cloud.example.com"),
        (" cloud.example.com ", "https://cloud.example.com"),
        ("cloud.example.com/", "https://cloud.example.com"),
        ("nextcloud.local", "https://nextcloud.local"),
        // An explicit scheme is preserved in both directions: HTTP is never upgraded, and it is the only way to select it.
        ("http://localhost", "http://localhost"),
        ("https://cloud.example.com", "https://cloud.example.com"),
        // The scheme and the host are case-insensitive; a path is not, and keeps the case it was typed in.
        ("HTTPS://Cloud.Example.COM", "https://cloud.example.com"),
        ("HTTP://LOCALHOST:8080/NextCloud", "http://localhost:8080/NextCloud"),
        // A scheme written with the wrong number of slashes, and a protocol-relative paste, are repaired rather than refused.
        ("https:localhost", "https://localhost"),
        ("https:/localhost", "https://localhost"),
        ("https:////cloud.example.com", "https://cloud.example.com"),
        ("//cloud.example.com", "https://cloud.example.com"),
    ])
    func `An address without a scheme defaults to HTTPS and an explicit one is kept`(input: String, expected: String) throws {
        #expect(try ServerAddress(normalizing: input).displayString == expected)
        #expect(try ServerAddress(normalizing: expected).displayString == expected)
    }

    @Test(arguments: [
        // Foundation reports the scheme `localhost` and the path `8080` for the first of these, which is the trap this rule exists for.
        ("localhost:8080", "https://localhost:8080"),
        ("192.168.1.5:8080", "https://192.168.1.5:8080"),
        ("www.example.com:8080/x", "https://www.example.com:8080/x"),
        ("1.2.3.4", "https://1.2.3.4"),
        // An IPv6 literal, bracketed as typed or bracketed for the user, with its zone identifier percent-encoded.
        ("[::1]:8443", "https://[::1]:8443"),
        ("https://[::1]", "https://[::1]"),
        ("::1", "https://[::1]"),
        ("fe80::1%en0", "https://[fe80::1%25en0]"),
        // The port a scheme already implies is dropped; one that is not the default for that scheme is kept.
        ("https://host:443", "https://host"),
        ("http://host:80", "http://host"),
        ("http://host:443", "http://host:443"),
        ("https://host:8443/", "https://host:8443"),
        ("localhost:443", "https://localhost"),
        ("localhost:80", "https://localhost:80"),
        ("localhost:", "https://localhost"),
        // A host may end in the DNS root dot, but no certificate is issued for that form, so the canonical address drops it.
        ("https://cloud.example.com.", "https://cloud.example.com"),
        // Underscores are tolerated, because internal installations use them even though host names may not.
        ("https://my_server.local", "https://my_server.local"),
    ])
    func `A host, a port, and an IP literal are told apart from a scheme`(input: String, expected: String) throws {
        #expect(try ServerAddress(normalizing: input).displayString == expected)
        #expect(try ServerAddress(normalizing: expected).displayString == expected)
    }

    @Test(arguments: [
        // What someone actually pastes: the URL out of the address bar of a browser they are signed in to.
        ("https://cloud.example.com/index.php/apps/files?dir=/&fileid=12#anchor", "https://cloud.example.com"),
        ("https://cloud.example.com/apps/files/", "https://cloud.example.com"),
        ("https://cloud.example.com/settings/user", "https://cloud.example.com"),
        ("https://cloud.example.com/index.php", "https://cloud.example.com"),
        ("https://cloud.example.com/s/AbCdEf", "https://cloud.example.com"),
        ("https://cloud.example.com/f/1234", "https://cloud.example.com"),
        ("https://cloud.example.com/call/abc123", "https://cloud.example.com"),
        ("https://cloud.example.com/u/iva", "https://cloud.example.com"),
        ("https://cloud.example.com/remote.php/dav/files/iva", "https://cloud.example.com"),
        ("https://cloud.example.com/status.php", "https://cloud.example.com"),
        // A subpath install keeps its subpath, both on its own and in front of an entry point.
        ("cloud.example.com/nextcloud", "https://cloud.example.com/nextcloud"),
        ("cloud.example.com/Nextcloud/", "https://cloud.example.com/Nextcloud"),
        ("https://host/nextcloud/index.php/login", "https://host/nextcloud"),
        ("http://localhost/nextcloud/index.php/settings/admin/overview", "http://localhost/nextcloud"),
        // A query or a fragment would be carried into every endpoint Rainmaker appends to the address, so neither survives.
        ("https://cloud.example.com?x=1", "https://cloud.example.com"),
        ("https://cloud.example.com#frag", "https://cloud.example.com"),
        ("https://host/#/apps/files", "https://host"),
        // Empty and relative segments are resolved rather than propagated.
        ("https://cloud.example.com//", "https://cloud.example.com"),
        ("https://host//nextcloud//", "https://host/nextcloud"),
        ("https://host/a/../b", "https://host/b"),
        ("https://host/./x", "https://host/x"),
    ])
    func `A pasted deep link is reduced to the instance it belongs to`(input: String, expected: String) throws {
        #expect(try ServerAddress(normalizing: input).displayString == expected)
        #expect(try ServerAddress(normalizing: expected).displayString == expected)
    }

    @Test(arguments: [
        // An internationalized domain is shown in the ASCII form Cirruscope actually resolves, so a lookalike host cannot hide behind its rendering.
        ("bücher.example", "https://xn--bcher-kva.example"),
        ("xn--bcher-kva.example", "https://xn--bcher-kva.example"),
        ("https://bücher.example/Bücher", "https://xn--bcher-kva.example/B%C3%BCcher"),
        ("https://\u{FF23}\u{FF2C}\u{FF2F}\u{FF35}\u{FF24}\u{FF0E}example\u{FF0E}com", "https://cloud.example.com"),
    ])
    func `An internationalized host is shown in the form it is resolved as`(input: String, expected: String) throws {
        #expect(try ServerAddress(normalizing: input).displayString == expected)
        #expect(try ServerAddress(normalizing: expected).displayString == expected)
    }

    @Test(arguments: [
        // A CRLF pair is one Swift Character, so removing it takes a pass over unicode scalars rather than characters.
        ("\n\tcloud.example.com\r\n", "https://cloud.example.com"),
        ("https://cloud.\r\nexample.com", "https://cloud.example.com"),
        ("cloud.example.com\u{200B}", "https://cloud.example.com"),
        ("\u{202E}cloud.example.com", "https://cloud.example.com"),
        ("\u{FEFF}cloud.example.com", "https://cloud.example.com"),
        // Delimiters an address was copied along with.
        ("<https://cloud.example.com>", "https://cloud.example.com"),
        ("\u{201C}https://cloud.example.com\u{201D}", "https://cloud.example.com"),
        ("\"cloud.example.com\"", "https://cloud.example.com"),
        ("<\u{201C}cloud.example.com\u{201D}>", "https://cloud.example.com"),
    ])
    func `Paste artifacts are removed rather than refused`(input: String, expected: String) throws {
        #expect(try ServerAddress(normalizing: input).displayString == expected)
        #expect(try ServerAddress(normalizing: expected).displayString == expected)
    }

    @Test(arguments: [
        // Whether the scheme was supplied by Cirruscope is what decides whether the user is told about the HTTPS default, and it cannot be recovered from the canonical address afterwards.
        ("localhost", true),
        ("cloud.example.com:8080", true),
        ("//cloud.example.com", true),
        ("::1", true),
        ("https://cloud.example.com", false),
        ("HTTPS://cloud.example.com", false),
        ("http://localhost", false),
        ("https:cloud.example.com", false),
    ])
    func `An address reports whether Cirruscope supplied its scheme`(input: String, expected: Bool) throws {
        #expect(try ServerAddress(normalizing: input).inferredScheme == expected)
    }

    @Test(arguments: [
        ("", ServerAddressError.empty),
        ("   ", ServerAddressError.empty),
        ("\n\t", ServerAddressError.empty),
        // A scheme Cirruscope cannot reach a server over is named, rather than being prefixed into a host as it was before.
        ("ftp://host", ServerAddressError.unsupportedScheme("ftp")),
        ("file:///x", ServerAddressError.unsupportedScheme("file")),
        ("nc://login/server", ServerAddressError.unsupportedScheme("nc")),
        ("javascript:alert(1)", ServerAddressError.unsupportedScheme("javascript")),
        ("mailto:x@y", ServerAddressError.unsupportedScheme("mailto")),
        ("data:text/html,x", ServerAddressError.unsupportedScheme("data")),
        ("about:blank", ServerAddressError.unsupportedScheme("about")),
        ("view-source:https://x", ServerAddressError.unsupportedScheme("view-source")),
        ("ws://[::1]", ServerAddressError.unsupportedScheme("ws")),
        ("com.example.app://oauth", ServerAddressError.unsupportedScheme("com.example.app")),
        ("FTP://HOST", ServerAddressError.unsupportedScheme("ftp")),
        // Credentials are refused rather than dropped: the last of these reads as one host and names another.
        ("https://user:pass@host", ServerAddressError.credentialsInAddress),
        ("http://user@host", ServerAddressError.credentialsInAddress),
        ("https://cloud.example.com@evil.example", ServerAddressError.credentialsInAddress),
        // Nothing to connect to.
        ("https://", ServerAddressError.missingHost),
        ("https:///", ServerAddressError.missingHost),
        ("/nextcloud", ServerAddressError.missingHost),
        // A host Foundation accepts but nothing can resolve.
        ("https://!!!/", ServerAddressError.invalidHost("!!!")),
        ("..", ServerAddressError.invalidHost("..")),
        ("%20", ServerAddressError.invalidHost("%20")),
        ("https://%2f/x", ServerAddressError.invalidHost("%2f")),
        ("https://-bad-.example", ServerAddressError.invalidHost("-bad-.example")),
        // A port Foundation accepts but no socket can be opened on.
        ("https://host:0", ServerAddressError.invalidPort(0)),
        ("https://host:99999", ServerAddressError.invalidPort(99999)),
        // Unparseable: a space inside a host, a full-width colon, a mistyped port.
        ("cloud example.com", ServerAddressError.malformed("cloud example.com")),
        ("https://cloud.example.com\u{FF1A}8443", ServerAddressError.malformed("https://cloud.example.com\u{FF1A}8443")),
        ("localhost:80a0", ServerAddressError.malformed("localhost:80a0")),
        ("https://cloud.example.com\u{0007}/x", ServerAddressError.invalidCharacters),
    ])
    func `An unusable address is refused with the reason it is unusable`(input: String, expected: ServerAddressError) {
        #expect(throws: expected) {
            try ServerAddress(normalizing: input)
        }

        #expect(expected.errorDescription?.isEmpty == false)
    }

    @Test
    func `A host label longer than DNS allows is refused`() throws {
        // 64 characters in one label, one past the limit, which is worth pinning at the boundary rather than with an arbitrarily long name.
        let tooLongLabel = String(repeating: "a", count: 64)
        let longestValidLabel = String(repeating: "a", count: 63)

        #expect(throws: ServerAddressError.invalidHost("\(tooLongLabel).example")) {
            try ServerAddress(normalizing: "http://\(tooLongLabel).example")
        }

        #expect(try ServerAddress(normalizing: "http://\(longestValidLabel).example").displayString == "http://\(longestValidLabel).example")
    }

    @Test
    func `An input longer than any address is refused before it is parsed`() {
        #expect(throws: ServerAddressError.tooLong) {
            try ServerAddress(normalizing: String(repeating: "a", count: 2049))
        }
    }

    @Test
    func `Two spellings of the same address are the same value`() throws {
        // The canonical form is what the rest of the app displays and connects to, so equality has to follow it rather than the input.
        #expect(try ServerAddress(normalizing: "localhost").url == ServerAddress(normalizing: "HTTPS://localhost/").url)
        #expect(try ServerAddress(normalizing: "cloud.example.com").url == ServerAddress(normalizing: "https://cloud.example.com:443/index.php/apps/files").url)
        #expect(try ServerAddress(normalizing: "http://localhost").url != ServerAddress(normalizing: "localhost").url)
    }
}
