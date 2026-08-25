// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `ServerAddressError` is the reason `ServerAddress(normalizing:)` could not turn what the user typed into an address to connect to.
///
/// It is deliberately separate from `CirruscopeError`, which collects the operational failures the app's facilities throw — a Keychain rejection, an unexpected HTTP status, a login that timed out. These cases are not failures of the app at all but statements about one text field's contents, and keeping them apart is what lets `ServerAddress(normalizing:)` be typed as `throws(ServerAddressError)`: `ServerAddressViewController.open(_:)` then handles a closed set of input problems without also having to consider a `keychainFailure` it cannot get there.
/// The conformance to `LocalizedError` is what makes each case presentable: `open(_:)` shows `localizedDescription` as the informative text of an alert titled "Invalid Server Address", so every case has to read as a complete instruction to the user on its own.
enum ServerAddressError: Error, Equatable, LocalizedError {
    /// `empty` is thrown when the input holds nothing but whitespace, or nothing at all.
    ///
    /// No path through the user interface reaches it: the "Connect" button is disabled while the field holds nothing but whitespace, and `ServerAddressFormatter` leaves a field it cannot normalize exactly as it is. The case exists so the type refuses an empty input rather than producing the bare `https://` the inline sanitation it replaced produced.
    case empty

    /// `tooLong` is thrown when the input exceeds `ServerAddress.maximumLength` characters.
    ///
    /// It is diagnosed separately from `malformed` because that case carries the input into the alert message, which a pathological paste has no business appearing in.
    case tooLong

    /// `invalidCharacters` is thrown when the input still holds control characters after the invisible and line-breaking ones a paste carries have been removed.
    ///
    /// Like `tooLong`, it is kept apart from `malformed` so the message does not interpolate characters that cannot be displayed.
    case invalidCharacters

    /// `unsupportedScheme` is thrown when the input names a scheme other than HTTP or HTTPS, carrying it in lowercase for the message.
    ///
    /// This is the case that replaces the previous behaviour of prefixing anything unrecognized with `https://`, which turned `ftp://x` into `https://ftp://x/` and treated a `javascript:` or `file:` input as the beginning of a host name.
    case unsupportedScheme(String)

    /// `credentialsInAddress` is thrown when the input carries a user name or a password.
    ///
    /// Refusing rather than silently dropping them matters twice over: the credentials Cirruscope uses come from Login Flow v2 in the next step, so a password typed here would never be used, and `https://cloud.example.com@evil.example` reads as one host while naming another, which is worth stopping rather than quietly rewriting.
    case credentialsInAddress

    /// `malformed` is thrown when the input cannot be parsed as a URL at all, carrying the sanitized input for the message.
    ///
    /// Foundation is the judge here, and it is stricter than it looks in exactly one place that matters: a space inside a host makes the whole value unparseable, while a space in a path is accepted and percent-encoded.
    case malformed(String)

    /// `missingHost` is thrown when the input parses but names no server, as `https://` and `/nextcloud` do.
    ///
    /// `URL(string:)` accepts both, which is why the host is checked here rather than assumed to exist.
    case missingHost

    /// `invalidHost` is thrown when the host cannot name a server, carrying it in the percent-encoded form so a host that is blank or invisible once decoded still shows up in the message.
    case invalidHost(String)

    /// `invalidPort` is thrown when the input names a port outside `1...65535`, which `URL(string:)` itself accepts.
    case invalidPort(Int)

    var errorDescription: String? {
        switch self {
            case .empty:
                String(localized: "Please enter the address of your Nextcloud server.", comment: "Error shown when the server address field is empty.")

            case .tooLong:
                String(localized: "The address is too long. Please enter only the address of your Nextcloud server.", comment: "Error shown when the entered server address is longer than any address could reasonably be.")

            case .invalidCharacters:
                String(localized: "The address contains characters that are not allowed in a web address. Please check the address and try again.", comment: "Error shown when the entered server address contains control characters.")

            case let .unsupportedScheme(scheme):
                String(localized: "Cirruscope can only connect to a Nextcloud server over HTTP or HTTPS, not “\(scheme)”.", comment: "Error shown when the entered server address uses a scheme other than HTTP or HTTPS; the placeholder is that scheme.")

            case .credentialsInAddress:
                String(localized: "Please enter the server address without a user name or password. Signing in happens in the next step.", comment: "Error shown when the entered server address contains user information.")

            case let .malformed(address):
                String(localized: "“\(address)” is not a valid URL. Please check the address and try again.", comment: "Alert message shown when the entered server address is not a valid URL; the placeholder is the address the user typed.")

            case .missingHost:
                String(localized: "The address is missing a server name. Please enter an address such as https://cloud.example.com.", comment: "Error shown when the entered server address names no server.")

            case let .invalidHost(host):
                String(localized: "“\(host)” is not a valid server name. Please check the address and try again.", comment: "Error shown when the server name in the entered address cannot name a server; the placeholder is that name.")

            case let .invalidPort(port):
                String(localized: "“\(port)” is not a valid port number. Please enter a port between 1 and 65535.", comment: "Error shown when the port in the entered server address is out of range; the placeholder is that port.")
        }
    }
}
