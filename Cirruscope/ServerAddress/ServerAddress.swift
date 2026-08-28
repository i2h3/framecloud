// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import Network

///
/// `ServerAddress` is a Nextcloud instance address the user typed or pasted, normalized into the one canonical form Cirruscope talks to a server with and shows back to them.
///
/// The canonical form is `scheme://host[:port][/subpath]` with no trailing slash, no query, and no fragment, because that is the only shape `Rainmaker.Server` can derive its endpoints from unharmed.
///
struct ServerAddress: Sendable {
    /// `url` is the canonical instance address, the value `ServerConnection.anonymous(address:)` is called with.
    ///
    /// It always carries a supported scheme, a syntactically resolvable host, and neither a query nor a fragment, so `Rainmaker.Server` can append its endpoint paths to it without carrying anything of the user's input along.
    let url: URL

    /// `inferredScheme` is `true` when the input carried no scheme of its own and HTTPS was supplied for it.
    ///
    /// It is the single input to the hint `ServerAddressViewController.revealSchemeHint()` reveals, and the one fact about the input that cannot be recovered from `url` afterwards: once the field has been rewritten, an address the app completed and one the user typed in full are the same string.
    let inferredScheme: Bool

    /// `displayString` is the canonical address as text, the value `ServerAddressFormatter` writes back into the server-address field.
    ///
    /// It is `url.absoluteString` rather than a separately assembled string so the text the user reads and the address the app connects to can never disagree — including for an internationalized domain, where the ASCII form Cirruscope actually resolves (`xn--bcher-kva.example`) is what gets shown.
    var displayString: String {
        url.absoluteString
    }

    /// `init(normalizing:)` turns raw user input into the canonical address, or throws the `ServerAddressError` explaining why the input cannot be one.
    ///
    /// The steps are ordered so that the most specific diagnosis wins: paste artifacts are removed first, then the scheme is resolved (defaulting to HTTPS), then `URL(string:)` parses the result, and only then are the parts inspected. That order matters because `URL(string:)` normalizes far less than it looks like it does — it preserves the case of an ASCII host and scheme verbatim, accepts a port of `99999`, accepts `!!!` as a host, and reports no host at all for `https://` — so each of those is checked here rather than assumed away.
    /// The result is idempotent: normalizing `displayString` again returns the same value, which it has to be, because the field is repeatedly fed its own output.
    init(normalizing input: String) throws(ServerAddressError) {
        let text = Self.sanitized(input)

        guard text.isEmpty == false else {
            throw .empty
        }

        guard text.count <= Self.maximumLength else {
            throw .tooLong
        }

        guard text.unicodeScalars.allSatisfy({ CharacterSet.controlCharacters.contains($0) == false }) else {
            throw .invalidCharacters
        }

        let (candidate, inferredScheme) = try Self.schemed(text)

        guard let parsed = URL(string: candidate) else {
            throw .malformed(text)
        }

        guard let scheme = parsed.scheme?.lowercased(), Self.supportedSchemes.contains(scheme) else {
            throw .malformed(text)
        }

        guard parsed.user(percentEncoded: false) == nil else {
            throw .credentialsInAddress
        }

        guard parsed.password(percentEncoded: false) == nil else {
            throw .credentialsInAddress
        }

        guard var host = parsed.host(percentEncoded: false)?.lowercased() else {
            throw .missingHost
        }

        guard host.isEmpty == false else {
            throw .missingHost
        }

        if host.hasSuffix("."), host.count > 1 {
            host = String(host.dropLast())
        }

        guard Self.isResolvable(host: host) else {
            throw .invalidHost(parsed.host(percentEncoded: true) ?? host)
        }

        if host.contains(":") {
            host = "[" + host.replacingOccurrences(of: "%", with: "%25") + "]"
        }

        var port = ""

        if let number = parsed.port {
            guard number > 0, number <= 65535 else {
                throw .invalidPort(number)
            }

            if Self.defaultPorts[scheme] != number {
                port = ":" + String(number)
            }
        }

        let canonical = scheme + "://" + host + port + Self.instancePath(of: parsed.path(percentEncoded: true))

        guard let url = URL(string: canonical), url.absoluteString == canonical else {
            throw .malformed(text)
        }

        self.url = url
        self.inferredScheme = inferredScheme
    }

    /// `maximumLength` is the number of characters of input beyond which normalization refuses to look at the value at all.
    ///
    /// Nothing about a Nextcloud address needs anywhere near this much room; the limit exists so a pathological paste cannot be percent-encoded into a value that ends up in an alert message or a log line. The number itself is a judgement call rather than a standard.
    private static let maximumLength = 2048

    /// `supportedSchemes` are the two URL schemes Cirruscope can reach a Nextcloud server over, in the order the leading-scheme check tries them.
    ///
    /// HTTPS comes first because it is also the scheme an input without one defaults to. Anything else — `ftp`, `file`, `nc`, `javascript`, a reverse-DNS app scheme — is refused as `ServerAddressError.unsupportedScheme` instead of being treated as part of a host, which is what the string-prefix check this type replaced did when it turned `ftp://x` into `https://ftp://x/`.
    private static let supportedSchemes = ["https", "http"]

    /// `defaultPorts` maps each supported scheme to the port it already implies, which the canonical form therefore omits.
    ///
    /// `https://host:443` and `http://host:80` normalize to `https://host` and `http://host`, while a port that is not the default for *its* scheme is kept — `http://host:443` stays as typed.
    private static let defaultPorts = ["https": 443, "http": 80]

    /// `ignoredScalars` are the code points removed from the input outright before it is parsed.
    ///
    /// Tab, carriage return, and line feed are removed because the URL Standard removes them too, and because a URL pasted out of a wrapped mail or a chat message arrives with them embedded. The rest are invisible: a soft hyphen, the zero-width and word-joiner characters a copy out of a rendered web page picks up, the byte-order mark, and the bidirectional formatting characters, which are also a spoofing vector in an address the user is being asked to read and confirm.
    /// They are filtered over `unicodeScalars` rather than `Character` values on purpose: a CRLF pair is a *single* `Character` in Swift, so filtering characters would leave it in place.
    private static let ignoredScalars: Set<Unicode.Scalar> = ["\u{0009}", "\u{000A}", "\u{000D}", "\u{00AD}", "\u{200B}", "\u{200C}", "\u{200D}", "\u{200E}", "\u{200F}", "\u{2028}", "\u{2029}", "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}", "\u{2060}", "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}", "\u{FEFF}"]

    /// `wrappingDelimiters` are the paired delimiters stripped from around an address that was copied together with the punctuation surrounding it.
    ///
    /// Angle brackets are the pair RFC 3986 itself recommends for delimiting a URL in running text, and mail clients add them; the quotation marks cover an address copied out of a document or a chat message, where the typographic pair is what an autocorrecting editor produced. Parentheses are deliberately absent, because a closing one can legitimately end a path.
    private static let wrappingDelimiters: [(Character, Character)] = [("<", ">"), ("\"", "\""), ("\u{201C}", "\u{201D}"), ("\u{00AB}", "\u{00BB}"), ("\u{2039}", "\u{203A}")]

    /// `entryPointSegments` are the first path segments that mark the start of a Nextcloud instance's own routing rather than part of the address of the instance itself.
    ///
    /// They are what lets someone paste the URL out of the browser they are signed in to — `https://cloud.example.com/index.php/apps/files?dir=/&fileid=12`, a `/s/…` share link, a `/call/…` Talk link — and still get the instance root, while a subpath install keeps its subpath, because `nextcloud` is deliberately not among them. The truncation cuts everything from the first matching segment onward, which is why it is also correct for `https://host/nextcloud/index.php/login`.
    /// An instance installed under a subpath literally named after one of these segments would be truncated wrongly. That trade is accepted because the result is written back into the field, where the user can see it and correct it before anything is sent.
    private static let entryPointSegments: Set<String> = ["apps", "avatar", "call", "core", "cron.php", "csrftoken", "f", "index.php", "login", "logout", "ocm-provider", "ocs", "ocs-provider", "public.php", "remote.php", "s", "settings", "status.php", "u"]

    /// `sanitized(_:)` removes the invisible and structural noise a paste carries, then trims the result and unwraps any delimiters left around it.
    ///
    /// Unwrapping repeats until nothing changes so that a doubly wrapped paste — a quoted angle-bracketed address — is reduced as well, and it trims again after each pass because the delimiters usually enclose spaces too.
    private static func sanitized(_ input: String) -> String {
        var value = String(String.UnicodeScalarView(input.unicodeScalars.filter { ignoredScalars.contains($0) == false })).trimmingCharacters(in: .whitespacesAndNewlines)
        var didUnwrap = true

        while didUnwrap {
            didUnwrap = false

            for (opening, closing) in wrappingDelimiters where value.count >= 2 && value.first == opening && value.last == closing {
                value = String(value.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                didUnwrap = true
            }
        }

        return value
    }

    /// `schemed(_:)` returns the input with a scheme it can be parsed as an absolute URL with, and whether that scheme had to be supplied, or throws when the input already carries one Cirruscope cannot use.
    ///
    /// The hard part is that a bare host and port is indistinguishable from a scheme to Foundation: `URL(string: "localhost:8080")` reports the scheme `localhost` and the path `8080`, and `www.example.com:8080/x` reports the whole domain as the scheme, because a dot is legal in a scheme. A leading token is therefore only treated as a scheme when it is followed by `//` — which no host and port ever is — or when it carries no dot and is followed by something that does not begin with a digit, which separates `mailto:x@y` and `javascript:alert(1)` from `localhost:8080` and from a mistyped port like `localhost:80a0`, whose better diagnosis is that the whole value is malformed.
    /// The remaining branches repair inputs Foundation would otherwise parse into something host-less: `http:`/`https:` followed by any number of slashes is re-formed into the two-slash form, and a protocol-relative `//host` paste is completed with the scheme rather than prefixed, since `https://` followed by `//host` would put the host into the path. A bare IPv6 literal is bracketed, because `https://::1` does not parse at all, and its zone identifier is percent-encoded, which is the form `URL` itself serializes.
    private static func schemed(_ input: String) throws(ServerAddressError) -> (candidate: String, inferredScheme: Bool) {
        let lowercased = input.lowercased()

        for scheme in supportedSchemes where lowercased.hasPrefix(scheme + ":") {
            return (scheme + "://" + input.dropFirst(scheme.count + 1).drop { $0 == "/" }, false)
        }

        if input.hasPrefix("//") {
            return ("https:" + input, true)
        }

        let authority = input.prefix { $0 != "/" }

        if authority.filter({ $0 == ":" }).count >= 2, IPv6Address(String(authority)) != nil {
            return ("https://[" + authority.replacingOccurrences(of: "%", with: "%25") + "]" + input.dropFirst(authority.count), true)
        }

        if let colon = input.firstIndex(of: ":") {
            let token = input[input.startIndex ..< colon]
            let remainder = input[input.index(after: colon)...]

            if isSchemeToken(token) {
                if remainder.hasPrefix("//") {
                    throw .unsupportedScheme(token.lowercased())
                }

                if token.contains(".") == false, let first = remainder.first, isASCIIDigit(first) == false {
                    throw .unsupportedScheme(token.lowercased())
                }
            }
        }

        return ("https://" + input, true)
    }

    /// `isSchemeToken(_:)` answers whether `token` could be a URL scheme at all, per the RFC 3986 grammar: a letter followed by letters, digits, `+`, `-`, or `.`.
    ///
    /// It is what keeps `192.168.1.5:8080` out of the scheme branches of `schemed(_:)` — a scheme cannot begin with a digit, which is also why `URL(string:)` rejects that input outright while accepting `localhost:8080`.
    private static func isSchemeToken(_ token: Substring) -> Bool {
        guard let first = token.first, first.isASCII, first.isLetter else {
            return false
        }

        return token.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == ".") }
    }

    /// `isASCIIDigit(_:)` answers whether `character` is one of `0` through `9`.
    ///
    /// `Character.isNumber` alone is not enough here, because it is also true for the digits of other scripts, which cannot appear in a port.
    private static func isASCIIDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }

    /// `isResolvable(host:)` answers whether `host` could name a server at all, `host` being the ASCII form `URL` has already converted an internationalized domain into.
    ///
    /// This check exists because `URL(string:)` performs none of it: it accepts `https://!!!/` and reports `!!!` as the host. An IPv6 literal is handed to `Network.IPv6Address`, which is also why the brackets have to be gone by this point — `URL.host(percentEncoded:)` strips them and `IPv6Address` rejects them. Everything else is checked as a host name: at most 253 characters, labels of at most 63, no empty label, no label bordered by a hyphen. Underscores are tolerated because internal Nextcloud installations do use them, and a name that is syntactically fine but does not resolve is left to DNS to report.
    private static func isResolvable(host: String) -> Bool {
        if host.contains(":") {
            return IPv6Address(host) != nil
        }

        guard host.count <= 253 else {
            return false
        }

        let labels = host.split(separator: ".", omittingEmptySubsequences: false)

        guard labels.isEmpty == false else {
            return false
        }

        return labels.allSatisfy { label in
            label.isEmpty == false && label.count <= 63 && label.first != "-" && label.last != "-" && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        }
    }

    /// `instancePath(of:)` reduces a parsed path to the subpath the Nextcloud instance itself is installed under, as either the empty string or a path with no trailing slash.
    ///
    /// It drops empty segments, so a stray `//` cannot propagate into every endpoint Rainmaker appends to the address, resolves `.` and `..` rather than carrying them along, and stops at the first segment in `entryPointSegments`, which is what turns a pasted deep link back into an address to sign in with. The comparison is case-insensitive because Nextcloud's own entry points are reached that way on a case-insensitive file system, but the segments that are kept keep the case they were typed in: a path is case-sensitive, and `/Nextcloud` is not `/nextcloud`.
    private static func instancePath(of path: String) -> String {
        var segments: [String] = []

        for segment in path.split(separator: "/", omittingEmptySubsequences: true) {
            let lowercased = segment.lowercased()

            if entryPointSegments.contains(lowercased) {
                break
            }

            if lowercased == "." {
                continue
            }

            if lowercased == ".." {
                if segments.isEmpty == false {
                    segments.removeLast()
                }

                continue
            }

            segments.append(String(segment))
        }

        return segments.isEmpty ? "" : "/" + segments.joined(separator: "/")
    }
}
