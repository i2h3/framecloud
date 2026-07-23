// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import SwiftData

/// `AppDatabase` owns the single, process-wide SwiftData `ModelContainer` backing Cirruscope's account store.
///
/// The container is configured with `groupContainer: .identifier(AppGroup.identifier)` so the store lives in the shared App Group container — under `Library/Application Support/`, disjoint from `AssetCache`'s `Library/Caches/` subtree — where a future app extension carrying the same entitlement can also open it. The store is local only (`cloudKitDatabase: .none`); secrets never go in it (they stay in `Keychain`).
///
/// `ModelContainer` is `Sendable`, so exposing it as a `static let` mirrors the existing `AppGroup` / `AssetCache.shared` singleton conventions. Access the main-actor context through `AccountStore`, which is the only type that touches it. Opening the store — including running `CirruscopeMigrationPlan` and any quarantine or container fallback — logs at `.notice`/`.error`/`.fault` so the whole startup path is reconstructable from a log capture in a release build.
enum AppDatabase {
    /// `logger` records store setup and recovery under the `AppDatabase` category.
    private static let logger = Logger(for: AppDatabase.self)

    /// `storeName` is the fixed configuration name that pins the store's filename, so every target — the app and any future extension — opens the very same file rather than a differently-named default.
    private static let storeName = "Cirruscope"

    /// `schema` is the app's current SwiftData schema.
    ///
    /// It is one definition rather than two because `AccountStore`'s unit tests build their own in-memory container from it (see `AccountStoreHarness`): a schema spelled out a second time on the test side would keep exercising whichever version it was written against once the app moves on. It names the newest versioned schema, `SchemaV2`; `CirruscopeMigrationPlan` migrates a store written by an older one up to it.
    static let schema = Schema(versionedSchema: SchemaV2.self)

    /// `container` is the shared model container, built on first access, opened with `CirruscopeMigrationPlan` so a store written by an earlier shipped schema is migrated forward in place.
    ///
    /// Three locations are tried in order. First the App Group container, which is where a properly signed build always ends up. If opening it fails — a genuinely corrupt file, or a migration that could not complete — the store files are moved aside to `.quarantine` siblings (never deleted) and it is tried once more: the store is largely reconstructible (apps are re-fetched from the server; only user shortcuts are authored locally), so recovering beats crash-looping on launch, and quarantining rather than deleting means a failed migration never destroys the user's shortcuts — the files stay on disk for recovery. If that fails too, the store is opened in the app's own container instead, because the likeliest remaining cause is not corruption at all but a build with no App Group entitlement to reach the shared container with — an ad-hoc build, which is what a fresh clone, a fork, and CI all produce, and which the sandbox then denies write access to that path. Only a failure there as well is unrecoverable.
    ///
    /// Falling back rather than trapping is what lets such a build actually run, and it is deliberately the *last* resort: an entitled build that lands there would silently be reading an empty store instead of the user's data, so the switch is logged at a level that persists to the system log.
    ///
    /// Being a `static let`, it is opened only once something actually asks for it, which is what lets the account store's tests run entirely on their own in-memory container: nothing in them reaches `AccountStore.shared`, so this store is never opened on their behalf — and it must stay that way, since the recovery path above moves the developer's real store files aside.
    static let container: ModelContainer = {
        let schema = Self.schema
        let sharedConfiguration = ModelConfiguration(
            storeName,
            schema: schema,
            groupContainer: .identifier(AppGroup.identifier),
            cloudKitDatabase: .none
        )

        logger.notice("Opening SwiftData store \"\(storeName, privacy: .public)\" at \(sharedConfiguration.url.path, privacy: .public) with schema v\(SchemaV2.versionIdentifier.description, privacy: .public) and the migration plan")

        do {
            let container = try ModelContainer(for: schema, migrationPlan: CirruscopeMigrationPlan.self, configurations: sharedConfiguration)
            logger.notice("Opened the SwiftData store in the App Group container")
            return container
        } catch {
            logger.error("Could not open the SwiftData store in the App Group container; quarantining it and retrying: \(error.localizedDescription, privacy: .public)")
        }

        quarantineStore(at: sharedConfiguration.url)

        do {
            let container = try ModelContainer(for: schema, migrationPlan: CirruscopeMigrationPlan.self, configurations: sharedConfiguration)
            logger.notice("Rebuilt the SwiftData store in the App Group container after quarantining the previous one")
            return container
        } catch {
            logger.error("Could not open the rebuilt SwiftData store in the App Group container; falling back to this build's own container: \(error.localizedDescription, privacy: .public)")
        }

        let ownConfiguration = ModelConfiguration(
            storeName,
            schema: schema,
            groupContainer: .none,
            cloudKitDatabase: .none
        )

        do {
            let container = try ModelContainer(for: schema, migrationPlan: CirruscopeMigrationPlan.self, configurations: ownConfiguration)
            logger.notice("Opened the SwiftData store in this build's own container at \(ownConfiguration.url.path, privacy: .public); this build has no App Group entitlement, so it is not reading the shared store")
            return container
        } catch {
            logger.fault("Could not open the SwiftData store in the App Group container or in this build's own container: \(error.localizedDescription, privacy: .public)")
            preconditionFailure("Could not open the SwiftData store in the App Group container or in this build's own container: \(error.localizedDescription)")
        }
    }()

    /// `quarantineStore(at:)` moves the SQLite store file and its `-wal`/`-shm`/`-journal` sidecars aside to `.quarantine` siblings, so a fresh container can be created in place of an unreadable one without destroying the user's data — which stays on disk, recoverable, rather than being deleted.
    ///
    /// Each move is logged (and each failure logged at `.error`, without aborting the rest) so a support log shows exactly which files were set aside and where.
    private static func quarantineStore(at storeURL: URL) {
        let directory = storeURL.deletingLastPathComponent()
        let name = storeURL.lastPathComponent
        let fileManager = FileManager.default

        logger.notice("Quarantining store \"\(name, privacy: .public)\" and its sidecars in \(directory.path, privacy: .public)")

        for suffix in ["", "-wal", "-shm", "-journal"] {
            let live = directory.appending(path: name + suffix)

            guard fileManager.fileExists(atPath: live.path) else {
                logger.debug("No \"\(name + suffix, privacy: .public)\" present; nothing to quarantine")
                continue
            }

            let quarantined = directory.appending(path: name + suffix + ".quarantine")
            try? fileManager.removeItem(at: quarantined)

            do {
                try fileManager.moveItem(at: live, to: quarantined)
                logger.notice("Quarantined \"\(name + suffix, privacy: .public)\" → \"\(quarantined.lastPathComponent, privacy: .public)\"")
            } catch {
                logger.error("Could not quarantine \"\(name + suffix, privacy: .public)\": \(error.localizedDescription, privacy: .public)")
            }
        }

        logger.notice("Quarantine pass complete")
    }
}
