// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
import CoreSpotlight
import Foundation
import os

/// `ServerAppIndexer` keeps Spotlight and Siri in step with the connected server's app list, donating each `ServerAppEntity` to the on-device Spotlight index and refreshing the App Shortcut parameters when the apps change.
///
/// It is a main-actor observer of `Notification.Name.serverAppsDidChange` — the same signal `AppDelegate` and `ServerAppsViewController` react to — so `AccountStore` itself never imports App Intents or Core Spotlight; donation is just one more subscriber to the store's existing write-then-notify contract. `AppDelegate.applicationDidFinishLaunching(_:)` calls `start()` once, which indexes the apps already persisted from a previous run and then keeps the index current on every change, including clearing it when `AccountStore.disconnect()` empties the account.
///
/// Indexing runs at most a handful of times per session, so each pass logs at `.notice` with the counts and app ids in the clear (`.public`), letting a log capture show exactly what was donated to or removed from Spotlight; failures log at `.error`.
@MainActor
final class ServerAppIndexer: NSObject {
    /// `shared` is the process-wide indexer, mirroring the `AccountStore.shared` / `NotificationMonitor.shared` conventions.
    static let shared = ServerAppIndexer()

    /// `logger` records indexing activity under the `ServerAppIndexer` category.
    private let logger = Logger(for: ServerAppIndexer.self)

    /// `indexedIDs` is the set of app ids currently donated to Spotlight, retained so a shrinking app list can have its removed entries deleted from the index rather than left behind, and so a reindex can tell whether the app list actually changed.
    private var indexedIDs: Set<String> = []

    override private init() {
        super.init()
    }

    /// `start()` registers the change observer and performs the initial index over the apps already persisted from a previous run.
    func start() {
        logger.notice("Starting server app indexer; registering for change notifications and performing the initial index")
        NotificationCenter.default.addObserver(self, selector: #selector(serverAppsDidChange), name: .serverAppsDidChange, object: nil)
        reindex(isInitial: true)
    }

    /// `serverAppsDidChange()` reindexes when `AccountStore` reports the app list or a shortcut changed, deferring to the next main-thread turn so it never runs reentrantly inside the mutation that posted the notification — matching `ServerAppsViewController`.
    @objc
    private func serverAppsDidChange() {
        logger.debug("Received serverAppsDidChange; scheduling a reindex")
        DispatchQueue.main.async { [weak self] in
            self?.reindex(isInitial: false)
        }
    }

    /// `reindex(isInitial:)` donates the current apps to Spotlight, deletes the ids the server no longer offers, and asks the App Intents system to refresh the App Shortcut parameter values.
    ///
    /// `isInitial` distinguishes the one-shot index from `start()` from a later change, for the log only. The parameter refresh runs on **every** pass, including the initial one: `updateAppShortcutParameters()` is what makes the system pull the current values from `ServerAppEntityQuery`, and without it Siri never learns the app names and cannot bind a parameterized phrase such as "Open Notes in Cirruscope" — it silently falls back to merely launching the app. An earlier revision skipped the call unless the app id set had changed, which in practice meant never (the server's app list is stable across launches) and broke exactly that. The call is cheap and idempotent, so it is unconditional; if it fails because the app is not yet registered with the App Intents subsystem (`LNMetadataProviderErrorDomain` 9004, typical of a build run from a non-standard location), the system logs that itself.
    private func reindex(isInitial: Bool) {
        let apps = AccountStore.shared.serverApps
        let entities = apps.map(ServerAppEntity.init)
        let currentIDs = Set(apps.map(\.id))
        let removedIDs = indexedIDs.subtracting(currentIDs)
        indexedIDs = currentIDs

        let currentList = currentIDs.sorted().joined(separator: ", ")
        logger.notice("Reindexing Spotlight (\(isInitial ? "initial" : "on change", privacy: .public)): \(apps.count, privacy: .public) app(s) currently offered [\(currentList, privacy: .public)]")

        if removedIDs.isEmpty == false {
            logger.notice("Spotlight: removing \(removedIDs.count, privacy: .public) stale entr(y/ies) [\(removedIDs.sorted().joined(separator: ", "), privacy: .public)]")
        }

        Task {
            // Use a named index, not CSSearchableIndex.default(): Apple documents the default index as being for
            // prototyping and development only (it does not support batching). Creating it here as a fresh local
            // value also keeps it out of the main actor's isolation region, so it can be passed to these nonisolated
            // async calls without tripping Swift's sending diagnostic.
            let index = CSSearchableIndex(name: "ServerAppIndex")

            do {
                if removedIDs.isEmpty == false {
                    try await index.deleteAppEntities(identifiedBy: Array(removedIDs), ofType: ServerAppEntity.self)
                    self.logger.notice("Spotlight: deleted \(removedIDs.count, privacy: .public) stale entr(y/ies)")
                }

                try await index.indexAppEntities(entities)
                self.logger.notice("Spotlight: donated \(entities.count, privacy: .public) app(s) to the index")
            } catch {
                self.logger.error("Could not update the Spotlight index: \(error.localizedDescription, privacy: .public)")
            }

            ServerAppShortcuts.updateAppShortcutParameters()
            self.logger.notice("Requested an App Shortcut parameter refresh; the system now pulls the current values from ServerAppEntityQuery")
        }
    }
}
