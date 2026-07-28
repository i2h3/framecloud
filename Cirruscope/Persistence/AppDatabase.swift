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
    /// If opening the store fails — most likely an incompatible store left by an earlier schema during pre-release development, or a genuinely corrupt file — the store files are deleted and the container is rebuilt once. The store is largely reconstructible (apps are re-fetched from the server; only user shortcuts are authored locally), so recovering beats crash-looping on launch. A second failure is treated as an unrecoverable provisioning problem.
    ///
    /// Being a `static let`, it is opened only once something actually asks for it, which is what lets the account store's tests run entirely on their own in-memory container: nothing in them reaches `AccountStore.shared`, so this store is never opened on their behalf — and it must stay that way, since the recovery path above deletes the developer's real store files.
    static let container: ModelContainer = {
        let schema = Self.schema
        let configuration = ModelConfiguration(
            storeName,
            schema: schema,
            groupContainer: .identifier(AppGroup.identifier),
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            logger.error("Could not open the SwiftData store; recreating it: \(error.localizedDescription)")
            destroyStore(at: configuration.url)

            do {
                return try ModelContainer(for: schema, configurations: configuration)
            } catch {
                preconditionFailure("Could not open the SwiftData store even after recreating it: \(error.localizedDescription)")
            }
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
