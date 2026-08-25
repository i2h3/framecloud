// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
import os
import Rainmaker

/// `NotificationMonitor` is the app-wide facility that keeps the Dock badge and notification-center banners in sync with the unread Nextcloud notifications of the connected server, as issue #41 requires.
///
/// It observes server-side changes through Rainmaker's `Server.events(_:)`, which prefers the `notify_push` WebSocket when the server offers it and otherwise polls every 30 seconds. Each event is only a hint, so the monitor reacts by re-fetching the full notification list via `Server.notifications()`; the unread count is that list's `count`, since the server returns exactly the notifications still queued for the user.
/// It broadcasts `Notification.Name.unreadNotificationCountDidChange` whenever the count changes so other parts of the app can react, and posts `Notification.Name.serverCredentialsRejected` when the stream reports the stored app password was revoked so `AppDelegate` can require a new sign-in.
@MainActor
final class NotificationMonitor {
    /// `shared` is the process-wide monitor, retained for the app's lifetime so it can own the long-lived event stream.
    static let shared = NotificationMonitor()

    /// `logger` records monitoring activity under the `NotificationMonitor` category.
    let logger = Logger(for: NotificationMonitor.self)

    /// `unreadCount` is the number of notifications currently queued for the user, exposed read-only so only the monitor mutates it.
    ///
    /// There is no read/unread flag on a Nextcloud notification: the server returns exactly the pending ones, so their count is the unread count shown on the Dock badge.
    private(set) var unreadCount = 0

    /// `server` is the connected server the monitor is currently observing, or `nil` while stopped, retained so `refreshNow()` can re-fetch on demand.
    private var server: Server?

    /// `task` is the retained consumer of the event stream, cancelled by `stop()`.
    private var task: Task<Void, Never>?

    /// `banneredIDs` holds the identifiers of notifications already turned into a banner, so re-fetching an unchanged queue does not post duplicate banners.
    private var banneredIDs: Set<Int> = []

    /// `endpointUnavailable` is set once the notifications endpoint reports it is absent so the monitor stops re-fetching and logging on every subsequent event; it is cleared on the next reconnect.
    private var endpointUnavailable = false

    /// `start(for:capabilities:)` begins observing `server` when it advertises the notifications capability, performing an immediate check and then reacting to every change.
    ///
    /// It gates on the `Notifications` capability because `Server.notifications()` only exists while the server's notifications app is enabled; when it is absent the monitor stays stopped and the badge is cleared. Any previously observed server is stopped first, so switching accounts never leaves two streams running.
    func start(for server: Server, capabilities: CapabilitySet) {
        guard capabilities.contains(Notifications.self) else {
            logger.notice("Notifications capability absent; not starting monitor")
            stop()
            return
        }

        logger.info("Starting notification monitor")
        stop()
        self.server = server
        // Request authorization now so banners can appear even when no web window is ever opened.
        UserNotifier.shared.requestAuthorization()

        task = Task {
            do {
                // The stream emits `.connected` on subscription, which drives the launch-time check as soon as possible.
                for try await event in server.events([.notifications]) {
                    switch event {
                        case .connected:
                            self.endpointUnavailable = false
                            await self.refresh()

                        case .notifications:
                            await self.refresh()

                        default:
                            break
                    }
                }
            } catch is CancellationError {
                // Expected when `stop()` cancels the task; nothing to do.
            } catch RainmakerError.credentialsRequired, RainmakerError.unexpectedStatus(code: 401) {
                self.logger.notice("Notification stream rejected credentials; requiring sign-in")
                self.stop()
                NotificationCenter.default.post(name: .serverCredentialsRejected, object: nil)
            } catch {
                self.logger.error("Notification stream ended: \(error.localizedDescription)")
            }
        }
    }

    /// `stop()` ends observation, clears the Dock badge, and resets the count to zero.
    ///
    /// `AppDelegate` calls it when the server becomes unusable — unsupported, unreachable, signed out, or with revoked credentials — and `start(for:capabilities:)` calls it before adopting a new server.
    func stop() {
        task?.cancel()
        task = nil
        server = nil
        banneredIDs.removeAll()
        endpointUnavailable = false
        unreadCount = 0
        updateDockBadge()
        NotificationCenter.default.post(name: .unreadNotificationCountDidChange, object: nil)
    }

    /// `refreshNow()` re-fetches the notifications immediately, used by `AppDelegate.applicationDidBecomeActive(_:)` to keep the badge fresh when the user returns to the app.
    ///
    /// It does nothing while the monitor is stopped.
    func refreshNow() {
        guard server != nil else {
            return
        }

        Task {
            await refresh()
        }
    }

    /// `refresh()` fetches the current notifications, updates the count and Dock badge, and posts banners for newly arrived ones.
    ///
    /// A `notFound` result means the notifications app was disabled after the capability check, so the badge is cleared and further re-fetching is suppressed until the next reconnect. Rejected credentials stop the monitor and ask `AppDelegate` for a new sign-in; any other error is transient and leaves the current badge untouched so a temporary network blip does not clear it.
    private func refresh() async {
        guard let server, endpointUnavailable == false else {
            return
        }

        do {
            let items = try await server.notifications()
            logger.debug("Fetched \(items.count, privacy: .public) notification(s)")
            unreadCount = items.count
            updateDockBadge()
            NotificationCenter.default.post(name: .unreadNotificationCountDidChange, object: nil)
            postBanners(for: items)
        } catch RainmakerError.notFound {
            logger.notice("Notifications endpoint unavailable; clearing badge")
            endpointUnavailable = true
            unreadCount = 0
            updateDockBadge()
            NotificationCenter.default.post(name: .unreadNotificationCountDidChange, object: nil)
        } catch RainmakerError.credentialsRequired, RainmakerError.unexpectedStatus(code: 401) {
            logger.notice("Notification refresh rejected credentials; requiring sign-in")
            stop()
            NotificationCenter.default.post(name: .serverCredentialsRejected, object: nil)
        } catch {
            logger.notice("Could not refresh notifications: \(error.localizedDescription)")
        }
    }

    /// `updateDockBadge()` reflects `unreadCount` onto the Dock icon, clearing the badge when there is nothing unread or no server is configured.
    ///
    /// The count is rendered with the current locale's digits and capped at `"999+"` so the badge stays narrow. `NSDockTile.display()` is called after each change to have the Dock repaint the tile promptly. Note that the badge only appears at all once notification authorization includes `.badge`, which `UserNotifier.requestAuthorization()` requests; macOS gates the app-icon badge — the Dock tile included — behind that option for any `UNUserNotificationCenter` client.
    private func updateDockBadge() {
        defer {
            NSApp.dockTile.display()
        }

        guard AccountStore.shared.serverAddress != nil, unreadCount > 0 else {
            NSApp.dockTile.badgeLabel = nil
            return
        }

        let label = unreadCount > 999 ? "999+" : unreadCount.formatted()
        logger.debug("Updating Dock badge to \(label, privacy: .public)")
        NSApp.dockTile.badgeLabel = label
    }

    /// `bannersAllowed` is `true` only while no web window is open, so the monitor's banners do not duplicate the ones the embedded Nextcloud web interface raises through `UserNotifier`'s web bridge.
    ///
    /// The Dock badge updates regardless; only the banners are suppressed while a web window can surface its own.
    private var bannersAllowed: Bool {
        (NSApp.delegate as? AppDelegate)?.hasOpenWebWindow == false
    }

    /// `postBanners(for:)` posts a banner for each notification not seen in the previous fetch, then records the current set so the same notification never banners twice.
    ///
    /// It records the seen identifiers even while banners are suppressed, so re-enabling them later does not retroactively banner notifications that arrived meanwhile.
    private func postBanners(for items: [NotificationItem]) {
        defer {
            banneredIDs = Set(items.map(\.id))
        }

        guard bannersAllowed, let serverAddress = AccountStore.shared.serverAddress else {
            return
        }

        for item in items where banneredIDs.contains(item.id) == false {
            UserNotifier.shared.postServerNotification(item, serverAddress: serverAddress)
        }
    }
}
