// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import SwiftData

/// `AccountStoreHarness` is one `AccountStore` under test, over a private in-memory SwiftData container and with stand-ins for the two things the store reaches outside itself for.
///
/// Every account suite holds one as a stored property, so Swift Testing's per-case instantiation gives each case a store nothing else can see: no case observes another's data, and none of them ever names `AccountStore.shared`, whose container lives in the shared App Group container and holds the developer's real account. The container is in-memory rather than a temporary file because nothing here tests file layout, and an in-memory store leaves no cleanup a failing case could skip.
///
/// The stand-ins are plain closures because that is how the store takes them. `reservedShortcuts` is what this harness claims Cirruscope's own menu items occupy, replacing a lookup that would otherwise answer from the app's real menu bar; `notificationCount` counts the change announcements the store made, replacing a post the app's real `AppDelegate` listens for throughout the run. The count says *that* a mutator announced, not *when*: the production post hops to the next main-thread turn and this one deliberately does not, so a case can assert it synchronously.
@MainActor
final class AccountStoreHarness {
    /// `container` is the in-memory container `store` reads and writes.
    ///
    /// It is retained here as well as by `store` because a `ModelContainer` closes its store as soon as nothing references it, and it is not private so a case can open a second `ModelContext` on it and observe that a write was committed rather than left pending in the main context.
    let container: ModelContainer

    /// `reservedShortcuts` are the combinations this harness reports as already occupied by one of Cirruscope's own fixed menu items.
    private let reservedShortcuts: [AppShortcutTransferObject]

    /// `notificationCount` is how many times `store` has announced that the server apps or their shortcuts changed.
    private(set) var notificationCount = 0

    /// `store` is the store under test, over `container` and this harness's two stand-ins.
    ///
    /// It is `lazy` because its closures capture the harness, which they cannot do before every stored property is initialized, and the capture is `unowned` because the harness owns the store that owns them.
    private(set) lazy var store = AccountStore(container: container, isReservedShortcut: { [unowned self] shortcut in isReserved(shortcut) }, notifyServerAppsDidChange: { [unowned self] in countAnnouncement() })

    /// `init(reserving:)` opens a fresh in-memory container over the app's current schema and reports `reserving` as occupied by Cirruscope's own menu items.
    ///
    /// Building the container is force-tried: an in-memory container over the very schema the app opens on every launch cannot fail for a reason a test should report as an expectation, so a throw here is a broken harness rather than a finding — the same call `KeyEquivalentProbe.keyDown(for:)`'s force-unwrap makes.
    init(reserving reservedShortcuts: [AppShortcutTransferObject] = []) {
        container = try! ModelContainer(for: AppDatabase.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        self.reservedShortcuts = reservedShortcuts
    }

    /// `isReserved(_:)` is what the store's `isReservedShortcut` seam answers with here.
    ///
    /// It compares through `ShortcutMatching.areEquivalent(_:_:)` rather than by equality so that this harness's notion of "reserved" is the app's: reserving ⌘Z also reserves ⇧⌘Z, exactly as `AppDelegate.reservedShortcutName(for:)` does against a real menu item.
    private func isReserved(_ shortcut: AppShortcutTransferObject) -> Bool {
        reservedShortcuts.contains { ShortcutMatching.areEquivalent($0, shortcut) }
    }

    /// `countAnnouncement()` is what the store's `notifyServerAppsDidChange` seam does here, in place of posting a notification the host app would act on.
    private func countAnnouncement() {
        notificationCount += 1
    }
}
