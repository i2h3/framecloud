// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `ServerAppPath` reads a URL as a path on one Nextcloud server, in the single normalized form two such paths can be compared in.
///
/// It exists because the same Nextcloud app is addressed by more than one spelling of the same path. An instance with pretty URLs disabled serves every app under `/index.php/`, one installed in a subdirectory writes that web root into every path it names, and the navigation endpoint answers with just one of those spellings while the web view reports whichever the server actually redirected to. Comparing the two as strings therefore fails on perfectly ordinary instances.
/// What is left once both are removed is the path *within* the instance, which is the only part that says anything about which app is on screen. `ServerAppTransferObject+Resolution.swift` compares them; this only produces them.
/// It also knows the short list of routes that belong to an app without being served under that app's own prefix, because such a path says nothing about its owner and there is nowhere else to learn it from — see `appPathsByRootRoute`.
enum ServerAppPath {
    /// `relativeComponents(of:on:)` is `url`'s path components within `serverAddress`'s own web root, with an `index.php` segment removed, or `nil` when `url` does not address that server at all.
    ///
    /// An empty array is a legitimate answer — it is the server's own root — and means something different from `nil`, which is a URL pointing somewhere else entirely. A URL on the right origin but outside the web root is `nil` too, being no more part of the instance than another host would be.
    /// The origin is proven by resolving through `SameOriginURL` rather than by comparing hosts here, so one implementation decides what "the same server" means. The absolute URL is handed to it as a path, a form its initializer documents and accepts.
    static func relativeComponents(of url: URL, on serverAddress: URL) -> [String]? {
        guard SameOriginURL(path: url.absoluteString, relativeTo: serverAddress) != nil else {
            return nil
        }

        var components = Self.components(of: url)
        let root = Self.components(of: serverAddress)

        guard components.starts(with: root) else {
            return nil
        }

        components.removeFirst(root.count)

        if components.first == "index.php" {
            components.removeFirst()
        }

        return components
    }

    /// `appPathsByRootRoute` maps the first component of a route an app registers at the server's own root to the path of the app that owns it.
    ///
    /// A Nextcloud app is normally reached under `/apps/<id>/`, and a path of that shape names its own owner. An app can also register a route at the root instead, by passing `root: ''` to the `FrontpageRoute` attribute on its controller, and such a path names nothing: `/call/<token>` is a Talk conversation and says so nowhere. Talk is the reason this exists — its conversation route is the one an iPhone lands on the moment a conversation is opened, and until it was mapped the title fell back to the page's own.
    /// The entry is deliberately the app's *path* rather than its identifier, so it is matched by the same comparison every other app is, and an app whose identifier differs from its path segment is no special case.
    /// This is the complete list for a current server, and how to regenerate it is worth writing down, because it cannot be derived at run time: the routes that escape their app's prefix are those declaring `root: ''`, and grepping an installed instance's `lib/` for that attribute finds them. Doing so on Nextcloud 34 with Talk installed also turns up `/settings/apps` and `/u/<userId>`, which are left out on purpose — they belong to the settings and profile pages, which are not apps the navigation endpoint offers, so there is no name for them to resolve to and the page title is the right answer.
    /// Two more that look like candidates and are not, recorded so the question is not reopened: `/f/<fileid>` needs no entry because the server answers it with a redirect into `/apps/files/`, so the web view's URL is an ordinary app path by the time anyone reads it; and `/s/<token>` is a public share belonging to File Sharing, which is not a navigation entry either, so an entry for it would resolve to nothing.
    private static let appPathsByRootRoute = [
        "call": ["apps", "spreed"],
    ]

    /// `canonicalComponents(of:on:)` is the path of the *app* `url` belongs to, which is its own path except where a root route stands in for one.
    ///
    /// Lossy where it rewrites, and meant to be: it answers which app a URL belongs to and not which page, so a conversation token and everything else past the route is dropped. Everywhere else it is `relativeComponents(of:on:)` unchanged.
    static func canonicalComponents(of url: URL, on serverAddress: URL) -> [String]? {
        guard let components = relativeComponents(of: url, on: serverAddress) else {
            return nil
        }

        guard let first = components.first else {
            return components
        }

        guard let appPath = appPathsByRootRoute[first] else {
            return components
        }

        return appPath
    }

    /// `appID(of:on:)` is the Nextcloud app identifier `url` addresses on `serverAddress` — the `<id>` in `/apps/<id>/…` — or `nil` when it addresses no app.
    ///
    /// Normalized first, so an app is recognized on an instance served under `/index.php/` or installed in a subdirectory as readily as on one that is neither, and on a root route belonging to an app as readily as on the app's own prefix.
    static func appID(of url: URL, on serverAddress: URL) -> String? {
        guard let components = canonicalComponents(of: url, on: serverAddress) else {
            return nil
        }

        guard components.count >= 2 else {
            return nil
        }

        guard components[0] == "apps" else {
            return nil
        }

        return components[1]
    }

    /// `components(of:)` splits a URL's path into its non-empty segments, left percent-encoded.
    ///
    /// Encoded rather than decoded so a segment carrying an escaped separator stays one segment, and so both sides of a comparison are spelled the way the server spelled them.
    private static func components(of url: URL) -> [String] {
        url.path(percentEncoded: true).split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }
}
