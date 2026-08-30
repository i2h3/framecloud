// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `SameOriginURL` is a location a Nextcloud server named, proven to be on that same server before anything is sent to it.
///
/// The proof is the point of the type. A server describes its own resources by path — the navigation endpoint answers `"/apps/files/"` for where an app lives and `"/apps/files/img/app.svg"` for its icon — and both are requested with the user's app password in an `Authorization` header, so that they work on an instance restricting them. Each half of that is reasonable and the combination is not: the path is chosen by the server, so an app that is compromised or simply malicious could name `https://evil.example/x.svg` and be handed the credential by return of post.
/// Resolving a path therefore produces this rather than a `URL`, and everything that attaches credentials takes only this. The unsafe case is then not merely avoided at each call site but unrepresentable, which is the difference between a rule and a habit.
struct SameOriginURL: Sendable {
    /// `url` is the absolute location to request, known to be on the same origin as the server that named it.
    let url: URL

    /// `init?(path:relativeTo:)` resolves `path` against `serverAddress`, or returns `nil` if it does not stay on that server.
    ///
    /// `path` may be server-root-relative, as Nextcloud's own values are, or already absolute — some values arrive that way, and one on the right origin is no less safe for being spelled out. Anything that resolves elsewhere is refused, including the protocol-relative form (`//elsewhere.example/x.svg`), which reads like a path and is not one.
    init?(path: String, relativeTo serverAddress: URL) {
        guard let resolved = URL(string: path, relativeTo: serverAddress)?.absoluteURL else {
            return nil
        }

        guard Self.isSameOrigin(resolved, as: serverAddress) else {
            return nil
        }

        url = resolved
    }

    /// `isSameOrigin(_:as:)` reports whether two URLs address the same scheme, host, and port.
    ///
    /// A port left out is the scheme's own, so `https://cloud.example.com` and `https://cloud.example.com:443` are one origin written two ways. Hosts compare case-insensitively, as DNS does.
    private static func isSameOrigin(_ url: URL, as other: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), let otherScheme = other.scheme?.lowercased(), scheme == otherScheme else {
            return false
        }

        guard let host = url.host()?.lowercased(), let otherHost = other.host()?.lowercased(), host == otherHost else {
            return false
        }

        return port(of: url) == port(of: other)
    }

    /// `port(of:)` is a URL's port, filled in from its scheme where it was left out.
    private static func port(of url: URL) -> Int? {
        guard let port = url.port else {
            switch url.scheme?.lowercased() {
                case "https":
                    return 443
                case "http":
                    return 80
                default:
                    return nil
            }
        }

        return port
    }
}
