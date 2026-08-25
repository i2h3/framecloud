// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import Rainmaker
import SwiftData

/// `AccountStore` is the main-actor repository over a SwiftData container, owning every read and write of the connected account's data.
///
/// It replaces the server-related values the app used to keep in `UserDefaults` via `Settings`. Consumers reach it as `AccountStore.shared`, mirroring the `AssetCache.shared` / `NotificationMonitor.shared` conventions, and it keeps posting `Notification.Name.serverAppsDidChange` so the existing AppKit menus and settings tab refresh exactly as before. As further domains arrive (files, notes, …) they gain methods here, or sibling main-actor stores sharing the same container.
///
/// Reads return value-type DTOs (`ServerAppTransferObject`, `KeyboardShortcutTransferObject`), never managed `@Model` objects, so AppKit table views and menus hold snapshots that stay valid across an upsert. Every access is confined to the main actor and only `Sendable` values ever cross the boundary to the nonisolated `ServerConnection`, which is what keeps the store race-free under Swift 6 complete concurrency. Autosave is disabled and each mutator saves explicitly, so every change commits atomically and is on disk by the time a future extension process reads it.
///
/// The container, and the two things this store reaches outside itself for, arrive through `init(container:isReservedShortcut:notifyServerAppsDidChange:)` so its logic can be exercised against an in-memory store; `macOSTests/Account/` does exactly that. Production builds exactly one instance, `shared`.
@MainActor
final class AccountStore {
    /// `shared` is the process-wide account store, over the app's on-disk container.
    ///
    /// It is the only instance production code builds, and the only one that must ever be built over `AppDatabase.container`: each instance memoizes the single `Account` separately (see `cachedAccount`), so two of them over one container would each believe a stale answer. Being a `static let` it is created lazily, which is what keeps the real store closed during a test run that never names it.
    static let shared = AccountStore(container: AppDatabase.container)

    /// `logger` records store activity under the `AccountStore` category.
    private let logger = Logger(for: AccountStore.self)

    /// `container` is the SwiftData container this store owns every read and write of.
    ///
    /// It is held rather than reached for so it can be handed in, and because a `ModelContainer` closes its store once nothing references it any more.
    private let container: ModelContainer

    /// `isReservedShortcut` reports whether a shortcut is already occupied by one of Cirruscope's own fixed menu items, which `shortcut(forAppID:)` consults to keep such a stored shortcut off the menus.
    ///
    /// It wraps `AppDelegate.reservedShortcutName(for:)` rather than calling it directly because that lookup answers from the live `NSApp.mainMenu`, and the test bundle is hosted by the app: the real `Main.storyboard` menu bar is loaded for the whole test run, so a case using ⌘Z — which both "Undo" and "Redo" declare — would be measuring the storyboard instead of this store. A test hands in a closure naming exactly the combinations it means to reserve.
    private let isReservedShortcut: @MainActor (KeyboardShortcutTransferObject) -> Bool

    /// `notifyServerAppsDidChange` announces that the account's apps or their shortcuts changed, so the View and Dock menus and the Apps settings tab refresh.
    ///
    /// It is injected for the mirror image of `isReservedShortcut`'s reason: `AppDelegate` observes `Notification.Name.serverAppsDidChange` for the whole life of a hosted test run, so a test write posting it would have the real `AppDelegate.rebuildServerAppsMenu()` read `shared` — the developer's actual account — and rewrite the live menu bar, on a main-queue turn no test can wait for. A test hands in a closure that counts instead, which is also the only way to assert that a mutator announced at all, the production post being deliberately asynchronous. `postServerAppsDidChange()` is that production post.
    private let notifyServerAppsDidChange: @MainActor () -> Void

    /// `context` is the container's main-actor context, the single context this store ever touches.
    private var context: ModelContext {
        container.mainContext
    }

    /// `cachedAccount` retains the single `Account` between calls so the hot `serverAddress` read path does not re-fetch on every navigation decision.
    ///
    /// `AccountStore` is the sole mutator on the main actor, so the cache stays consistent; `deleteAccount()` clears it after deleting the record.
    private var cachedAccount: Account?

    /// `init(container:isReservedShortcut:notifyServerAppsDidChange:)` builds a store over `container`, defaulting the two dependencies it reaches outside itself for to their production behaviour.
    ///
    /// A `ModelContainer` rather than a `ModelContext` is the parameter so that "the container's main-actor context" stays an invariant this store enforces, rather than something a caller could subvert by handing in a background context.
    init(container: ModelContainer, isReservedShortcut: @escaping @MainActor (KeyboardShortcutTransferObject) -> Bool = { AppDelegate.reservedShortcutName(for: $0) != nil }, notifyServerAppsDidChange: @escaping @MainActor () -> Void = { AccountStore.postServerAppsDidChange() }) {
        self.container = container
        self.isReservedShortcut = isReservedShortcut
        self.notifyServerAppsDidChange = notifyServerAppsDidChange

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

    /// `postServerAppsDidChange()` posts `Notification.Name.serverAppsDidChange` on the next main-thread turn, and is the production default for `notifyServerAppsDidChange`.
    ///
    /// The async hop is deliberate: it keeps `AppDelegate.rebuildServerAppsMenu()` and `ServerAppsViewController.reload()` from running reentrantly inside the `ShortcutRecorderView.onChange` handler that triggered the write. It is `static` and not `private` so it can serve as that default argument, which may not reference a declaration less visible than the initializer itself — keeping this explanation next to the behaviour rather than inside a parameter list.
    static func postServerAppsDidChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .serverAppsDidChange, object: nil)
        }
    }

    /// `postAppearanceSettingsDidChange()` posts `Notification.Name.appearanceSettingsDidChange` on the next main-thread turn so every open `WebViewController` re-applies the appearance without a reload.
    ///
    /// The async hop mirrors `postServerAppsDidChange()`: it keeps the observers from running reentrantly inside the `NSSwitch` action handler in `AppearanceSettingsViewController` that triggered the write.
    private func postAppearanceSettingsDidChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .appearanceSettingsDidChange, object: nil)
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
    /// `AppDelegate.logOut()` calls it; this reproduces the old `Settings.serverAddress = nil` cascade in one place. The announcement now happens in `deleteAccount()`, ahead of the two clears rather than after them, which is unobservable: the post is delivered on the next main-thread turn, while both clears are synchronous and finish inside the current one.
    func disconnect() {
        deleteAccount()

        AssetCache.shared.clear()
        Keychain.clearAll()
    }

    /// `deleteAccount()` deletes the account record — cascading to its apps and their shortcuts — drops the memoized `cachedAccount`, commits, and announces the change.
    ///
    /// It is the storage half of `disconnect()`, separated so it can be exercised on its own: `disconnect()`'s remaining two steps empty `AssetCache` and clear the `Keychain`, neither of which a test can run without destroying the developer's real cached assets and stored credentials. Clearing `cachedAccount` is what keeps a later write from landing on the deleted object instead of a fresh account.
    func deleteAccount() {
        if let account = currentAccount(createIfNeeded: false) {
            context.delete(account)
        }

        cachedAccount = nil
        save()
        notifyServerAppsDidChange()
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
    /// The metadata write and its save happen synchronously on the main actor; the asset downloads are awaited afterwards and run off the main actor, so a slow download never blocks it and cannot interleave with the commit. `ServerConnection.validate(_:)` awaits this, and both paths that produce the first web window — `AppDelegate.presentInitialWindow(forLaunch:)` at launch and `ServerAddressViewController` after sign-in — await that validation before presenting, so the branding is cached before any UI relying on it is shown. A window opened later by ⌘N deliberately does not wait, reading the copy those paths already cached; `WebViewController.cachedBackgroundImage()` treats a miss as "no background available" rather than an error. The background download is skipped when `theming.background` is a color value rather than an `http`/`https` image URL.
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

    // MARK: - Appearance

    /// `translucentAppearance` is the user's choice to let the macOS window material show through the web view, or `nil` when the user has not chosen — in which case callers apply the app default (off). `WebViewController` reads it to drive both the injected stylesheet and the native background image's visibility.
    var translucentAppearance: Bool? {
        currentAccount(createIfNeeded: false)?.translucentAppearance
    }

    /// `setTranslucentAppearance(_:)` records whether the translucent appearance is enabled, then notifies open web views so they re-apply it without a reload.
    ///
    /// `AppearanceSettingsViewController` calls it from the translucent-appearance switch.
    func setTranslucentAppearance(_ enabled: Bool) {
        currentAccount(createIfNeeded: true)?.translucentAppearance = enabled
        save()
        postAppearanceSettingsDidChange()
    }

    /// `removeGaps` is the user's choice to expand Nextcloud's content to the window edges, or `nil` when the user has not chosen — in which case callers apply the app default (on).
    var removeGaps: Bool? {
        currentAccount(createIfNeeded: false)?.removeGaps
    }

    /// `setRemoveGaps(_:)` records whether the content gaps are removed, then notifies open web views so they re-apply it without a reload.
    ///
    /// `AppearanceSettingsViewController` calls it from the remove-gaps switch.
    func setRemoveGaps(_ enabled: Bool) {
        currentAccount(createIfNeeded: true)?.removeGaps = enabled
        save()
        postAppearanceSettingsDidChange()
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

    /// `serverApps` is the connected server's apps as value snapshots, in the one order every surface lists them in: alphabetically by localized name, with the app identifier settling a tie.
    ///
    /// The sort is applied here rather than left to each caller for two reasons. SwiftData does not preserve the order of a to-many relationship, so the records arrive in no meaningful order and something has to impose one; and sorting once, at the single read every surface shares, is what keeps the View menu, the Dock menu (both built by `AppDelegate`), the Apps settings tab (`ServerAppsViewController`), the Shortcuts and Siri lists (`ServerAppEntityQuery`), the Spotlight index (`ServerAppIndexer`), and `storedShortcuts` — which walks this list — from being able to disagree about where an app sits. Each of those consumers arrived without having to know the rule, which is the point of the sort living at the read rather than in any of them. The server's own position for an app, `ServerAppTransferObject.order`, deliberately decides nothing here: it arranges the web interface's app menu, where it reads as a layout the admin chose, while a macOS menu is scanned for a name.
    ///
    /// `localizedStandardCompare(_:)` is the comparison rather than `<`, because `<` orders Swift strings by Unicode scalar and this list is read by a person: it files every lowercase name behind every uppercase one ("Files" ahead of "deck"), a French "Éditeur" behind "Zoom", and reads "Talk 10" as preceding "Talk 2". This is the collation Finder lists names with — case- and diacritic-insensitive and numeric-aware — in the user's own locale, which is the locale the server localized these names into. The identifier fallback is what makes the ordering total, since `sorted(by:)` promises no stability: two apps a server offers under one name would otherwise be free to swap places between two menu rebuilds, taking which of them a duplicate shortcut reaches with them, `appHolding(_:)` reading the first match.
    var serverApps: [ServerAppTransferObject] {
        guard let account = currentAccount(createIfNeeded: false) else {
            return []
        }

        return account.apps
            .map { ServerAppTransferObject(id: $0.appID, order: $0.order, href: $0.href, name: $0.name) }
            .sorted { one, other in
                let comparison = one.name.localizedStandardCompare(other.name)
                return comparison == .orderedSame ? one.id < other.id : comparison == .orderedAscending
            }
    }

    /// `serverApp(forID:)` is the connected server's app with `appID` as a value snapshot, or `nil` when the account offers no such app.
    ///
    /// It is the single-app counterpart of `serverApps`, added for the App Intents layer: `ServerAppEntityQuery.entities(for:)` and `OpenServerAppIntent.perform()` resolve a donated or saved app id back to a `ServerAppTransferObject`. Like every other read here it returns a value-type DTO, never the managed `ServerApp`, and reuses the same `currentAccount` cache and `first(where:)` lookup as `shortcut(forAppID:)`.
    func serverApp(forID appID: String) -> ServerAppTransferObject? {
        guard let app = currentAccount(createIfNeeded: false)?.apps.first(where: { $0.appID == appID }) else {
            return nil
        }

        return ServerAppTransferObject(id: app.appID, order: app.order, href: app.href, name: app.name)
    }

    /// `persist(serverApps:)` upserts the server's apps: existing rows are updated in place, new ones inserted, and ones the server no longer offers deleted — which cascades to their shortcuts.
    ///
    /// Matching by `id` rather than replacing the list wholesale is what lets a user's keyboard shortcut survive an app-list refresh; a shortcut is pruned only when its app actually disappears. `ServerConnection.refreshNavigationApps(using:)` calls it with the `Rainmaker.NavigationItem`s it fetched already mapped to this app's own value type, so the store's write side speaks the same type its read side returns and neither depends on the shape of the network library — which is also what lets a test seed an app list without the test target linking that library.
    func persist(serverApps: [ServerAppTransferObject]) {
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

        // Skip an id already seen in this list rather than inserting a second row for it: two rows sharing one id
        // would leave `serverApps`' name-then-identifier ordering with a tie it cannot break, so which of them a
        // shared shortcut belongs to would stop being decidable. No real server sends duplicates.
        for item in serverApps where incomingIDs.contains(item.id) == false {
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
        notifyServerAppsDidChange()
    }

    // MARK: - App Shortcuts

    /// `storedShortcuts` are the shortcuts currently stored for the connected account's apps, each paired with the app it belongs to, in the order the menus list those apps.
    ///
    /// It walks `serverApps` rather than sorting the records itself, so that order is the menus' own by construction — alphabetical by name, with the app identifier breaking a tie so that it is total. `appHolding(_:)` reads the first match from it to decide which single app a shared shortcut belongs to, and that answer has to be the same on every call rather than depend on an unstable sort. Collecting the shortcuts into a dictionary first is what keeps that walk from being a search of the relationship per app.
    private var storedShortcuts: [(appID: String, name: String, shortcut: KeyboardShortcutTransferObject)] {
        guard let account = currentAccount(createIfNeeded: false) else {
            return []
        }

        var shortcutsByAppID: [String: KeyboardShortcutTransferObject] = [:]

        for app in account.apps {
            guard let stored = app.shortcut else {
                continue
            }

            shortcutsByAppID[app.appID] = KeyboardShortcutTransferObject(keyEquivalent: stored.keyEquivalent, modifierFlags: stored.modifierFlags)
        }

        return serverApps.compactMap { app in
            guard let shortcut = shortcutsByAppID[app.id] else {
                return nil
            }

            return (app.id, app.name, shortcut)
        }
    }

    /// `appHolding(_:)` is the one app a keystroke matching `shortcut` actually reaches — the first entry in `storedShortcuts` carrying an equivalent shortcut — or `nil` when no app carries it at all.
    ///
    /// Answering both `shortcut(forAppID:)` and `nameOfApp(usingShortcut:otherThanAppID:)` from this same entry is what keeps the two from contradicting each other where a duplicate is stored: were the latter to consider every stored shortcut instead, an app whose duplicate the former suppresses would still be named as the occupant of a combination the settings tab shows as unassigned for it, and the app visibly holding that combination could not even re-record it.
    private func appHolding(_ shortcut: KeyboardShortcutTransferObject) -> (appID: String, name: String, shortcut: KeyboardShortcutTransferObject)? {
        storedShortcuts.first { ShortcutMatching.areEquivalent($0.shortcut, shortcut) }
    }

    /// `shortcut(forAppID:)` is the user's keyboard shortcut for the app with `appID`, or `nil` when none is assigned, the app is unknown, the stored shortcut collides with one of Cirruscope's own reserved shortcuts (see `AppDelegate.reservedShortcutName(for:)`), or another app already holds the same one (see `appHolding(_:)`).
    ///
    /// Both collisions can only come from data recorded before their respective checks existed, since `ShortcutRecorderView` now refuses to record either going forward; suppressing them here as well means such a shortcut is not applied to a menu item — and is shown as unassigned in the settings tab, so the user can see it is not in effect and record another — rather than being deleted behind the user's back.
    func shortcut(forAppID appID: String) -> KeyboardShortcutTransferObject? {
        guard let stored = currentAccount(createIfNeeded: false)?.apps.first(where: { $0.appID == appID })?.shortcut else {
            return nil
        }

        let shortcut = KeyboardShortcutTransferObject(keyEquivalent: stored.keyEquivalent, modifierFlags: stored.modifierFlags)

        guard isReservedShortcut(shortcut) == false else {
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
    func nameOfApp(usingShortcut shortcut: KeyboardShortcutTransferObject, otherThanAppID appID: String) -> String? {
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
    func setShortcut(_ shortcut: KeyboardShortcutTransferObject?, forAppID appID: String) {
        guard let app = currentAccount(createIfNeeded: false)?.apps.first(where: { $0.appID == appID }) else {
            return
        }

        if let shortcut {
            if let existing = app.shortcut {
                existing.keyEquivalent = shortcut.keyEquivalent
                existing.modifierFlags = shortcut.modifierFlags
            } else {
                context.insert(KeyboardShortcut(keyEquivalent: shortcut.keyEquivalent, modifierFlags: shortcut.modifierFlags, app: app))
            }
        } else if let existing = app.shortcut {
            context.delete(existing)
        }

        save()
        notifyServerAppsDidChange()
    }
}
