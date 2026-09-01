// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// This extension answers which of the apps a server offers a given page belongs to, so a surface showing that page can name it.
///
/// One rule serves both platforms, for the reason `sortedByName()` does: the Mac reuses a window by asking which app it already shows, the iPhone titles its navigation bar with the app's name, and the two must not disagree about what a URL means.
extension Collection where Element == ServerAppTransferObject {
    /// `app(for:on:)` is the app whose pages `url` belongs to, or `nil` when it belongs to none of them.
    ///
    /// Two rules, in order. First the app whose `href` is a prefix of the URL — path component by path component, never as a string, since `/apps/files/` is not a prefix of `/apps/files_sharing/` however the two read — taking the longest such match, so a nested `href` beats its parent and a page deep inside an app still resolves to it. Then, failing that, the identifier in the URL's own `/apps/<id>/` matched against `id`.
    /// `href` is asked first because it is authoritative: it is where the server says the app lives, while the second rule assumes an app's identifier is also its path segment. That holds on every server release recorded so far, and it is an assumption rather than a guarantee — an app is free to be named one thing and served under another. The second rule earns its place on the reverse case, an entry served from outside `/apps/` at all, which is how the External Sites app files its links.
    /// The URL is read through `ServerAppPath.canonicalComponents(of:on:)` rather than as the literal path, which is what lets a route an app registers at the server's own root — a Talk conversation at `/call/<token>` — be answered by the app that owns it rather than by nothing. Each `href` is read literally, being the app's own path and never a stand-in for another's.
    /// A query or fragment is ignored. Both address something within an app rather than a different one.
    func app(for url: URL, on serverAddress: URL) -> ServerAppTransferObject? {
        guard let components = ServerAppPath.canonicalComponents(of: url, on: serverAddress) else {
            return nil
        }

        var match: (app: ServerAppTransferObject, depth: Int)?

        for app in self {
            // The server chose this path, so it is resolved through the same type that decides whether it may be
            // requested at all. One that leaves the server cannot describe a page on it either.
            guard let target = SameOriginURL(path: app.href, relativeTo: serverAddress) else {
                continue
            }

            // The literal path, not the canonical one: an `href` is where the app itself is served, so it
            // is never a root route standing in for somewhere else. Canonicalizing it would let an app
            // whose own path began with a mapped segment be rewritten into the app that segment belongs
            // to, and then match every page of it.
            guard let hrefComponents = ServerAppPath.relativeComponents(of: target.url, on: serverAddress) else {
                continue
            }

            // An app claiming the instance root would prefix every URL on the server and so match all of them.
            // No server offers one; this is what keeps a malformed answer from swallowing every other app.
            guard hrefComponents.isEmpty == false else {
                continue
            }

            guard components.starts(with: hrefComponents) else {
                continue
            }

            guard hrefComponents.count > (match?.depth ?? 0) else {
                continue
            }

            match = (app, hrefComponents.count)
        }

        if let match {
            return match.app
        }

        guard let id = ServerAppPath.appID(of: url, on: serverAddress) else {
            return nil
        }

        return first { $0.id == id }
    }
}
