// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `AppGroup` resolves the shared App Group container declared in `Cirruscope.entitlements`, so `AssetCache` and `Settings` can persist assets and preferences somewhere a future app extension could also reach.
///
enum AppGroup {
    /// `InfoPlistKey` collects the string keys under which `AppGroup` reads statically configured values from the app's `Info.plist`.
    private enum InfoPlistKey {
        /// `identifier` is the key for the `Info.plist` entry that backs `AppGroup.identifier`.
        static let identifier = "AppGroupIdentifier"
    }

    /// `identifier` is the App Group identifier declared in `Cirruscope.entitlements`, read from `Info.plist` rather than hardcoded: the underlying bundle identifier — and therefore this App Group identifier, which is derived from it — is a brandable/customizable value that varies for differently-branded builds of this app.
    static var identifier: String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: InfoPlistKey.identifier) else {
            preconditionFailure("Info.plist is missing the \"\(InfoPlistKey.identifier)\" entry.")
        }

        guard let stringValue = value as? String else {
            preconditionFailure("Info.plist entry \"\(InfoPlistKey.identifier)\" must be a string but was \(value).")
        }

        return stringValue
    }

    /// `containerURL` is the on-disk location of the shared App Group container, or `nil` when this build cannot reach it.
    ///
    /// A build signed with a real, provisioned certificate always resolves it. An ad-hoc build cannot: ad-hoc signing embeds no entitlements (see AGENTS.md → Building and Signing), so the app runs sandboxed without membership in the group, and the container is out of reach even though the sandbox itself is active. That is the state a fresh clone, a fork, and CI all run in, so it is a legitimate degraded state to tolerate — trapping here instead, as an earlier version did, made an app that everyone could build but only the maintainer could actually launch.
    ///
    /// Being unreachable is not always visible as a `nil`, either: the container path can resolve while the sandbox still refuses to create anything under it. Callers therefore treat a non-`nil` value as a candidate rather than a guarantee, and fall back on a location private to the build — `AssetCache.assetsDirectory()` for cached assets, `AppDatabase.container` for the store.
    static let containerURL: URL? = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
}
