// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import SwiftData

/// `AppDatabase` owns the single, process-wide SwiftData `ModelContainer` backing Cirruscope's account store.
///
/// The container is configured with `groupContainer: .identifier(AppGroup.identifier)` so the store lives in the shared App Group container — under `Library/Application Support/`, disjoint from `AssetCache`'s `Library/Caches/` subtree — where a future app extension carrying the same entitlement can also open it. The store is local only (`cloudKitDatabase: .none`); secrets never go in it (they stay in `Keychain`).
///
/// `ModelContainer` is `Sendable`, so exposing it as a `static let` mirrors the existing `AppGroup` / `AssetCache.shared` singleton conventions. Access the main-actor context through `AccountStore`, which is the only type that touches it.
enum AppDatabase {
    /// `logger` records store setup and recovery under the `AppDatabase` category.
    private static let logger = Logger(for: AppDatabase.self)

    /// `storeName` is the fixed configuration name that pins the store's filename, so every target — the app and any future extension — opens the very same file rather than a differently-named default.
    private static let storeName = "Cirruscope"

    /// `schema` is the app's current SwiftData schema.
    ///
    /// It is one definition rather than two because `AccountStore`'s unit tests build their own in-memory container from it (see `AccountStoreHarness`): a schema spelled out a second time on the test side would keep exercising whichever version it was written against once the app moves on.
    static let schema = Schema(versionedSchema: SchemaV1.self)

    /// `container` is the shared model container, built on first access.
    ///
    /// Three locations are tried in order. First the App Group container, which is where a properly signed build always ends up. If opening it fails — most likely an incompatible store left by an earlier schema during pre-release development, or a genuinely corrupt file — the store files are deleted and it is tried once more: the store is largely reconstructible (apps are re-fetched from the server; only user shortcuts are authored locally), so recovering beats crash-looping on launch. If that fails too, the store is opened in the app's own container instead, because the likeliest remaining cause is not corruption at all but a build with no App Group entitlement to reach the shared container with — an ad-hoc build, which is what a fresh clone, a fork, and CI all produce, and which the sandbox then denies write access to that path. Only a failure there as well is unrecoverable.
    ///
    /// Falling back rather than trapping is what lets such a build actually run, and it is deliberately the *last* resort: an entitled build that lands there would silently be reading an empty store instead of the user's data, so the switch is logged at a level that persists to the system log.
    ///
    /// Being a `static let`, it is opened only once something actually asks for it, which is what lets the account store's tests run entirely on their own in-memory container: nothing in them reaches `AccountStore.shared`, so this store is never opened on their behalf — and it must stay that way, since the recovery path above deletes the developer's real store files.
    static let container: ModelContainer = {
        let schema = Self.schema
        let sharedConfiguration = ModelConfiguration(
            storeName,
            schema: schema,
            groupContainer: .identifier(AppGroup.identifier),
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(for: schema, configurations: sharedConfiguration)
        } catch {
            logger.error("Could not open the SwiftData store in the App Group container; recreating it: \(error.localizedDescription)")
        }

        destroyStore(at: sharedConfiguration.url)

        do {
            return try ModelContainer(for: schema, configurations: sharedConfiguration)
        } catch {
            logger.error("Could not open the recreated SwiftData store in the App Group container; falling back to this build's own container: \(error.localizedDescription)")
        }

        let ownConfiguration = ModelConfiguration(
            storeName,
            schema: schema,
            groupContainer: .none,
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(for: schema, configurations: ownConfiguration)
        } catch {
            preconditionFailure("Could not open the SwiftData store in the App Group container or in this build's own container: \(error.localizedDescription)")
        }
    }()

    /// `destroyStore(at:)` removes the SQLite store file and its `-wal`/`-shm`/`-journal` sidecars so a fresh container can be created in place of an unreadable one.
    private static func destroyStore(at storeURL: URL) {
        let directory = storeURL.deletingLastPathComponent()
        let name = storeURL.lastPathComponent
        let fileManager = FileManager.default

        for suffix in ["", "-wal", "-shm", "-journal"] {
            try? fileManager.removeItem(at: directory.appending(path: name + suffix))
        }
    }
}
