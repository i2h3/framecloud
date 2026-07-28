// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import Rainmaker
import SwiftData

/// `AccountStore` is the main-actor repository over Cirruscope's SwiftData store (`AppDatabase.container`), owning every read and write of the connected account's data.
///
/// It replaces the server-related values the app used to keep in `UserDefaults` via `Settings`. Consumers reach it as `AccountStore.shared`, mirroring the `AssetCache.shared` / `NotificationMonitor.shared` conventions, and it keeps posting `Notification.Name.serverAppsDidChange` so the existing AppKit menus and settings tab refresh exactly as before. As further domains arrive (files, notes, …) they gain methods here, or sibling main-actor stores sharing `AppDatabase.container`.
///
/// Reads return value-type DTOs (`ServerAppTransferObject`, `AppShortcutTransferObject`), never managed `@Model` objects, so AppKit table views and menus hold snapshots that stay valid across an upsert. Every access is confined to the main actor and only `Sendable` values ever cross the boundary to the nonisolated `ServerConnection`, which is what keeps the store race-free under Swift 6 complete concurrency. Autosave is disabled and each mutator saves explicitly, so every change commits atomically and is on disk by the time a future extension process reads it.
@MainActor
final class AccountStore {
    /// `shared` is the process-wide account store.
    static let shared = AccountStore()

    /// `logger` records store activity under the `AccountStore` category.
    private let logger = Logger(for: AccountStore.self)

    /// `context` is the container's main-actor context, the single context this store ever touches.
    private var context: ModelContext {
        AppDatabase.container.mainContext
    }

    /// `cachedAccount` retains the single `Account` between calls so the hot `serverAddress` read path does not re-fetch on every navigation decision.
    ///
    /// `AccountStore` is the sole mutator on the main actor, so the cache stays consistent; `disconnect()` clears it after deleting the record.
    private var cachedAccount: Account?

    private init() {
        // Commit explicitly rather than relying on deferred autosave, which is insufficient for the cross-process
        // read contract and could otherwise fire at an `await` suspension point in the middle of a mutation.
        context.autosaveEnabled = false
    }

    // MARK: - Current Account

    /// `currentAccount(createIfNeeded:)` returns the single `Account`, fetching it once and caching it, and optionally inserting a fresh one when none exists yet.
    private func currentAccount(createIfNeeded: Bool) -> Account? {
        if let cachedAccount {
            return cachedAccount
        }

        var descriptor = FetchDescriptor<Account>()
        descriptor.fetchLimit = 1

        if let existing = try? context.fetch(descriptor).first {
            cachedAccount = existing
            return existing
        }

        guard createIfNeeded else {
            return nil
        }

        let account = Account()
        context.insert(account)
        cachedAccount = account
        return account
    }

    /// `save()` commits pending changes, logging rather than throwing on failure to match the app's existing fire-and-forget persistence behavior.
    private func save() {
        do {
            try context.save()
        } catch {
            logger.error("Could not save the account store: \(error.localizedDescription)")
        }
    }

    /// `postServerAppsDidChange()` posts `Notification.Name.serverAppsDidChange` on the next main-thread turn.
    ///
    /// The async hop is deliberate: it keeps `AppDelegate.rebuildServerAppsMenu()` and `ServerAppsViewController.reload()` from running reentrantly inside the `ShortcutRecorderView.onChange` handler that triggered the write.
    private func postServerAppsDidChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .serverAppsDidChange, object: nil)
        }
    }

    // MARK: - Server Address

    /// `serverAddress` is the URL of the connected server, or `nil` while none is configured.
    var serverAddress: URL? {
        currentAccount(createIfNeeded: false)?.serverAddress
    }

    /// `connect(to:)` records `address` as the connected server, creating the account record if needed.
    ///
    /// `ServerAddressViewController` calls it after a successful Login Flow v2 sign-in.
    func connect(to address: URL) {
        currentAccount(createIfNeeded: true)?.serverAddress = address
        save()
    }

    /// `disconnect()` deletes the account — cascading to its apps and their shortcuts — then empties `AssetCache` and clears the stored Login Flow v2 credentials, so nothing describing the old server remains.
    ///
    /// `AppDelegate.logOut()` calls it; this reproduces the old `Settings.serverAddress = nil` cascade in one place.
    func disconnect() {
        if let account = currentAccount(createIfNeeded: false) {
            context.delete(account)
        }

        cachedAccount = nil
        save()

        AssetCache.shared.clear()
        Keychain.clearAll()
        postServerAppsDidChange()
    }

    // MARK: - Theming

    /// `themeBackground` is the connected server's `Theming` `background` value (an image URL string or a hex color), or `nil`.
    var themeBackground: String? {
        currentAccount(createIfNeeded: false)?.themeBackground
    }

    /// `themeLogo` is the connected server's instance logo URL, or `nil`.
    var themeLogo: URL? {
        currentAccount(createIfNeeded: false)?.themeLogo
    }

    /// `themeBackgroundPlain` is the connected server's `backgroundPlain` flag, or `nil`.
    var themeBackgroundPlain: Bool? {
        currentAccount(createIfNeeded: false)?.themeBackgroundPlain
    }

    /// `persist(theming:)` records the server's branding into the account and downloads the referenced assets into `AssetCache`.
    ///
    /// The metadata write and its save happen synchronously on the main actor; the asset downloads are awaited afterwards and run off the main actor, so a slow download never blocks it and cannot interleave with the commit. `ServerConnection.validate(_:)` awaits this before any UI relying on the cached branding is shown. The background download is skipped when `theming.background` is a color value rather than an `http`/`https` image URL.
    ///
    /// `theming.background` may be an absolute URL or a server-root-relative path — Nextcloud returns a relative path for backgrounds picked from its shipped gallery — so it is resolved against `account.serverAddress` before being stored and cached. Resolution is skipped when `theming.backgroundPlain` is `true`, since `background` then holds a color value (e.g. `"#00679e"`) that would otherwise resolve into a bogus fetchable URL (the server address with a `#`-fragment).
    func persist(theming: Theming) async {
        let account = currentAccount(createIfNeeded: true)

        let backgroundURL = theming.backgroundPlain
            ? nil
            : URL(string: theming.background, relativeTo: account?.serverAddress)?.absoluteURL

        account?.themeBackground = backgroundURL?.absoluteString ?? theming.background
        account?.themeLogo = theming.logo
        account?.themeBackgroundPlain = theming.backgroundPlain
        save()

        if let backgroundURL, backgroundURL.scheme == "http" || backgroundURL.scheme == "https" {
            do {
                try await AssetCache.shared.cache(remote: backgroundURL)
            } catch {
                logger.notice("Could not cache theming background: \(error.localizedDescription)")
            }
        }

        do {
            try await AssetCache.shared.cache(remote: theming.logo)
        } catch {
            logger.notice("Could not cache theming logo: \(error.localizedDescription)")
        }
    }

    // MARK: - Server Version

    /// `serverVersion` is the human-readable version string of the connected server, or `nil`.
    var serverVersion: String? {
        currentAccount(createIfNeeded: false)?.serverVersion
    }

    /// `setServerVersion(_:)` records the connected server's version string.
    ///
    /// `ServerConnection.validate(_:)` calls it once a supported server's capabilities are retrieved. It is a method rather than a settable property because `ServerConnection` is nonisolated and reaches it with `await` across the main-actor boundary.
    func setServerVersion(_ version: String?) {
        currentAccount(createIfNeeded: true)?.serverVersion = version
        save()
    }

    // MARK: - Server Apps

    /// `serverApps` is the connected server's apps as value snapshots, sorted ascending by `order`.
    ///
    /// The sort is applied here because SwiftData does not preserve the order of a to-many relationship. `AppDelegate` reads it to build the View and Dock menus and `ServerAppsViewController` to list the apps.
    var serverApps: [ServerAppTransferObject] {
        guard let account = currentAccount(createIfNeeded: false) else {
            return []
        }

        return account.apps
            .sorted { $0.order < $1.order }
            .map { ServerAppTransferObject(id: $0.appID, order: $0.order, href: $0.href, name: $0.name) }
    }

    /// `persist(navigationApps:)` upserts the server's navigation apps: existing rows are updated in place, new ones inserted, and ones the server no longer offers deleted — which cascades to their shortcuts.
    ///
    /// Matching by `appID` rather than replacing the list wholesale is what lets a user's keyboard shortcut survive an app-list refresh; a shortcut is pruned only when its app actually disappears. `ServerConnection.refreshNavigationApps(using:)` calls it after fetching the apps.
    func persist(navigationApps: [NavigationItem]) {
        guard let account = currentAccount(createIfNeeded: true) else {
            return
        }

        // Snapshot the current apps before inserting, so the deletion pass iterates a stable list.
        let existingApps = account.apps
        var existingByID: [String: ServerApp] = [:]
        for app in existingApps {
            existingByID[app.appID] = app
        }

        var incomingIDs: Set<String> = []

        for item in navigationApps {
            incomingIDs.insert(item.id)

            if let existing = existingByID[item.id] {
                existing.order = item.order
                existing.href = item.href
                existing.name = item.name
            } else {
                context.insert(ServerApp(appID: item.id, order: item.order, href: item.href, name: item.name, account: account))
            }
        }

        for app in existingApps where incomingIDs.contains(app.appID) == false {
            context.delete(app)
        }

        save()
        postServerAppsDidChange()
    }

    // MARK: - App Shortcuts

    /// `storedShortcuts` are the shortcuts currently stored for the connected account's apps, each paired with the app it belongs to, in the order the menus list those apps.
    ///
    /// The order is `serverApps`' own, ascending by `order`, with `appID` breaking a tie so that it is total: `appHolding(_:)` reads the first match from it to decide which single app a shared shortcut belongs to, and that answer has to be the same on every call rather than depend on an unstable sort.
    private var storedShortcuts: [(appID: String, name: String, shortcut: AppShortcutTransferObject)] {
        guard let account = currentAccount(createIfNeeded: false) else {
            return []
        }

        return account.apps
            .sorted { ($0.order, $0.appID) < ($1.order, $1.appID) }
            .compactMap { app in
                guard let stored = app.shortcut else {
                    return nil
                }

                return (app.appID, app.name, AppShortcutTransferObject(keyEquivalent: stored.keyEquivalent, modifierFlags: stored.modifierFlags))
            }
    }

    /// `appHolding(_:)` is the one app a keystroke matching `shortcut` actually reaches — the first entry in `storedShortcuts` carrying an equivalent shortcut — or `nil` when no app carries it at all.
    ///
    /// Answering both `shortcut(forAppID:)` and `nameOfApp(usingShortcut:otherThanAppID:)` from this same entry is what keeps the two from contradicting each other where a duplicate is stored: were the latter to consider every stored shortcut instead, an app whose duplicate the former suppresses would still be named as the occupant of a combination the settings tab shows as unassigned for it, and the app visibly holding that combination could not even re-record it.
    private func appHolding(_ shortcut: AppShortcutTransferObject) -> (appID: String, name: String, shortcut: AppShortcutTransferObject)? {
        storedShortcuts.first { ShortcutMatching.areEquivalent($0.shortcut, shortcut) }
    }

    /// `shortcut(forAppID:)` is the user's keyboard shortcut for the app with `appID`, or `nil` when none is assigned, the app is unknown, the stored shortcut collides with one of Cirruscope's own reserved shortcuts (see `AppDelegate.reservedShortcutName(for:)`), or another app already holds the same one (see `appHolding(_:)`).
    ///
    /// Both collisions can only come from data recorded before their respective checks existed, since `ShortcutRecorderView` now refuses to record either going forward; suppressing them here as well means such a shortcut is not applied to a menu item — and is shown as unassigned in the settings tab, so the user can see it is not in effect and record another — rather than being deleted behind the user's back.
    func shortcut(forAppID appID: String) -> AppShortcutTransferObject? {
        guard let stored = currentAccount(createIfNeeded: false)?.apps.first(where: { $0.appID == appID })?.shortcut else {
            return nil
        }

        let shortcut = AppShortcutTransferObject(keyEquivalent: stored.keyEquivalent, modifierFlags: stored.modifierFlags)

        guard AppDelegate.reservedShortcutName(for: shortcut) == nil else {
            return nil
        }

        // Honour a shortcut two apps share for the first of them only, so one keystroke never reaches two equally
        // enabled menu items, between which AppKit has no reliable, documented tie-break.
        guard appHolding(shortcut)?.appID == appID else {
            return nil
        }

        return shortcut
    }

    /// `nameOfApp(usingShortcut:otherThanAppID:)` is the name of the server app that the same keystroke as `shortcut` already reaches, or `nil` when that app is the one with `appID` itself or no app holds the combination.
    ///
    /// `ServerAppsViewController` hands it to each row's `ShortcutRecorderView` as its `conflictingAppName`, so a combination another app already uses is rejected while recording — naming that app — instead of leaving two menu items to share one key equivalent, exactly as `AppDelegate.reservedShortcutName(for:)` does for Cirruscope's own fixed items. Excluding the app being edited is what lets a row re-record the shortcut it already displays without being told it conflicts with itself.
    func nameOfApp(usingShortcut shortcut: AppShortcutTransferObject, otherThanAppID appID: String) -> String? {
        guard let holder = appHolding(shortcut) else {
            return nil
        }

        return holder.appID == appID ? nil : holder.name
    }

    /// `setShortcut(_:forAppID:)` assigns, replaces, or (when `shortcut` is `nil`) clears the keyboard shortcut of the app with `appID`, then notifies observers so the menus update.
    ///
    /// `ServerAppsViewController` calls it from each row's `ShortcutRecorderView`. It does nothing when the app is unknown, which cannot happen for a row the settings tab is showing.
    ///
    /// It deliberately stores whatever it is given: rejecting a shortcut another app or a fixed menu item already occupies is the caller's job, done while recording (see `nameOfApp(usingShortcut:otherThanAppID:)` and `AppDelegate.reservedShortcutName(for:)`), so the settings tab can explain the rejection where the user is looking instead of a write silently doing nothing. Should a future caller — an App Intent, a widget — write a duplicate anyway, `shortcut(forAppID:)` still keeps it off the menus.
    func setShortcut(_ shortcut: AppShortcutTransferObject?, forAppID appID: String) {
        guard let app = currentAccount(createIfNeeded: false)?.apps.first(where: { $0.appID == appID }) else {
            return
        }

        if let shortcut {
            if let existing = app.shortcut {
                existing.keyEquivalent = shortcut.keyEquivalent
                existing.modifierFlags = shortcut.modifierFlags
            } else {
                context.insert(AppShortcut(keyEquivalent: shortcut.keyEquivalent, modifierFlags: shortcut.modifierFlags, app: app))
            }
        } else if let existing = app.shortcut {
            context.delete(existing)
        }

        save()
        postServerAppsDidChange()
    }
}
