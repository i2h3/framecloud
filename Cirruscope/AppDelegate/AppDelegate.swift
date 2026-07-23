// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Cocoa
import os
import Rainmaker
import WebKit

/// `AppDelegate` is the application delegate of Cirruscope and owns the lifecycle of every window the app shows.
///
/// On launch it consults `AccountStore.serverAddress` to decide whether to present `WebViewController` directly or to first show `ServerAddressViewController`. When a server address is already configured it first re-validates the server's capabilities against `Settings.minimumSupportedServerMajorVersion`, falling back to `ServerAddressViewController` only when the stored credentials were revoked or the server runs an unsupported major version; an unreachable server is treated as transient and keeps the web window, which surfaces its own retry UI. It also keeps freshly instantiated `NSWindowController`s alive until their windows close.
@main
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    /// `windowControllers` retains every `NSWindowController` that `present(windowController:sender:)` has shown so that their windows are not deallocated while visible.
    ///
    /// Each entry is removed when the corresponding `NSWindow.willCloseNotification` fires.
    private var windowControllers: [NSWindowController] = []

    /// `lastCascadePoint` is the point at which the most recently presented window was cascaded.
    ///
    /// `present(windowController:sender:)` updates it on every call so that subsequent windows opened via the "New Window" menu item are offset from the previous one rather than stacking on top of each other.
    private var lastCascadePoint: NSPoint = .zero

    /// `serverAppsSeparator` is the View-menu separator after which the dynamic server-app menu items are inserted.
    ///
    /// `rebuildServerAppsMenu()` inserts one item per `AccountStore.serverApps` entry directly after it, so the apps occupy the section the storyboard brackets with a separator above and below.
    @IBOutlet
    var serverAppsSeparator: NSMenuItem!

    /// `serverAppMenuItems` holds the server-app items currently inserted into the View menu so `rebuildServerAppsMenu()` can remove the previous set before inserting an updated one.
    private var serverAppMenuItems: [NSMenuItem] = []

    /// `logger` records launch and window-management activity under the `AppDelegate` category; it is not `private` so `AppDelegate`'s extensions in other files can log through it.
    let logger = Logger(for: AppDelegate.self)

    func applicationDidFinishLaunching(_: Notification) {
        logger.notice("Application finished launching")
        UserNotifier.shared.configure()
        NotificationCenter.default.addObserver(self, selector: #selector(serverAppsDidChange), name: .serverAppsDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(downloadDidStart), name: .downloadDidStart, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(serverCredentialsRejected), name: .serverCredentialsRejected, object: nil)
        rebuildServerAppsMenu()
        // Keep Spotlight and the Siri/Shortcuts app-parameter options in step with the server's app list.
        ServerAppIndexer.shared.start()
        presentInitialWindow(forLaunch: true)
    }

    func applicationDidBecomeActive(_: Notification) {
        // Keep the Dock badge fresh when the user returns to the app; does nothing while the monitor is stopped.
        NotificationMonitor.shared.refreshNow()
    }

    func applicationDockMenu(_: NSApplication) -> NSMenu? {
        let apps = AccountStore.shared.serverApps

        guard apps.isEmpty == false else {
            return nil
        }

        let menu = NSMenu()

        for app in apps {
            menu.addItem(menuItem(for: app))
        }

        return menu
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows: Bool) -> Bool {
        logger.log("App should handle reopen")

        if !hasVisibleWindows, windowControllers.isEmpty {
            presentInitialWindow(forLaunch: false)
        }

        return true
    }

    /// `application(_:continue:restorationHandler:)` opens the Nextcloud server app a user selected from a Spotlight result.
    ///
    /// macOS delivers the selection here as a `CSSearchableItemActionType` activity (Core Spotlight's AppKit contract). The handling lives in `openServerAppFromSpotlight(_:)` in the `AppDelegate+Spotlight` extension, so this file stays free of App Intents and Core Spotlight imports.
    func application(_: NSApplication, continue userActivity: NSUserActivity, restorationHandler _: @escaping ([any NSUserActivityRestoring]) -> Void) -> Bool {
        openServerAppFromSpotlight(userActivity)
    }

    func applicationWillTerminate(_: Notification) {
        logger.log("App will terminate")
    }

    func applicationSupportsSecureRestorableState(_: NSApplication) -> Bool {
        true
    }

    @IBAction
    func newWindow(_: Any?) {
        presentInitialWindow(forLaunch: false)
    }

    /// `openPrivacyPolicy(_:)` opens Cirruscope's online privacy policy in the user's default browser.
    ///
    /// It backs both the Help-menu "Privacy Policy…" item and the "Privacy Policy" button on `ServerAddressViewController`; both target the responder chain rather than this object directly, so a single handler serves every entry point.
    @IBAction
    func openPrivacyPolicy(_: Any?) {
        logger.debug("Opening privacy policy")
        NSWorkspace.shared.open(Settings.privacyPolicy)
    }

    /// `openSupportPage(_:)` opens Cirruscope's online support page in the user's default browser.
    ///
    /// It backs the Help-menu "Get Support…" item, which targets the responder chain.
    @IBAction
    func openSupportPage(_: Any?) {
        logger.debug("Opening support page")
        NSWorkspace.shared.open(Settings.supportURL)
    }

    /// `presentInitialWindow(forLaunch:)` validates the configured server and presents the window the app should show: a `WebViewWindowController` when a supported server is reachable or merely unreachable — in which case the web view shows its own "Server unreachable" retry UI — and a `ServerAddressWindowController` when no server is configured, the stored credentials were revoked, or the server runs an unsupported major version.
    ///
    /// `applicationDidFinishLaunching(_:)` calls it with `forLaunch` set to coordinate with AppKit window restoration: it opens a fresh web window only when none was restored. When the server reports an unsupported version or revoked credentials it closes any restored web windows so none lingers on a server the app can no longer use; an unreachable server is treated as transient, so restored windows are left in place to show their retry UI. `newWindow(_:)` and `applicationShouldHandleReopen(_:hasVisibleWindows:)` call it with `forLaunch` cleared, which always opens a new web window on success and leaves any already-open windows untouched on failure.
    private func presentInitialWindow(forLaunch: Bool) {
        logger.log("Presenting initial window")

        guard let serverAddress = AccountStore.shared.serverAddress else {
            logger.info("No server address configured; presenting sign-in")
            presentWindow(withIdentifier: "ServerAddressWindowController")
            return
        }

        guard let server = ServerConnection.authenticated(address: serverAddress) else {
            // The address is configured but no credentials are stored, so the user must log in again.
            logger.notice("Server configured but no stored credentials; requiring sign-in")
            presentWindow(withIdentifier: "ServerAddressWindowController")
            return
        }

        Task {
            do {
                switch try await ServerConnection.validate(server) {
                    case let .supported(capabilities):
                        logger.info("Server supported; presenting web window")
                        // At launch the validate round-trip runs after AppKit's local restoration, so any restored
                        // web windows are already tracked; open a fresh one only when nothing was restored. A
                        // user-initiated new window always opens.
                        if forLaunch == false || hasOpenWebWindow == false {
                            presentWebViewWindow()
                        }

                        await ServerConnection.refreshNavigationApps(using: server)
                        // Begin (or restart) tracking unread notifications for the Dock badge and banners.
                        NotificationMonitor.shared.start(for: server, capabilities: capabilities)

                    case let .unsupported(version):
                        logger.notice("Server at \(serverAddress.absoluteString) runs unsupported version \(version)")
                        NotificationMonitor.shared.stop()

                        if forLaunch {
                            closeWebViewWindows()
                        }

                        presentAlert(title: String(localized: "Unsupported Server", comment: "Alert title shown at launch when the configured server runs a Nextcloud version older than the app supports."), message: String(localized: "Cirruscope requires Nextcloud version \(Settings.minimumSupportedServerMajorVersion) or later. The server at “\(serverAddress.absoluteString)” is running version \(version).", comment: "Alert message shown at launch when the configured server's Nextcloud version is too old; placeholders are the minimum supported major version, the server address, and the server's version."))
                        presentWindow(withIdentifier: "ServerAddressWindowController")
                }
            } catch RainmakerError.credentialsRequired, RainmakerError.unexpectedStatus(code: 401) {
                // The stored app password was revoked on the server; discard it and require a new login.
                requireSignIn()
            } catch {
                // The server is unreachable — network down, server offline, DNS/TLS/timeout — as opposed to
                // reporting revoked credentials, which is handled above. This is transient and must not look
                // like a reset: keep the configured server address and stored credentials, keep or open the
                // web window, and let `WebViewController` surface its own "Server unreachable" retry UI.
                // Showing an alert or falling back to the sign-in window here would appear to wipe the user's
                // settings. As in the `.supported` case, only open a fresh window when none was restored.
                logger.error("Could not reach server; leaving the web window to show its retry UI: \(error.localizedDescription)")
                NotificationMonitor.shared.stop()

                if forLaunch == false || hasOpenWebWindow == false {
                    presentWebViewWindow()
                }
            }
        }
    }

    /// `requireSignIn()` discards the rejected credentials, alerts the user, and returns the app to the sign-in screen.
    ///
    /// `presentInitialWindow(forLaunch:)` calls it when validation reports the stored app password was revoked, the `serverCredentialsRejected` observer calls it when `NotificationMonitor`'s event stream detects the same during a session, and `WebViewController+WKNavigationDelegate` calls it when a silent retry of the server's login page with the stored app password lands back on the login page a second time. In every case the app is signing the user out on its own initiative rather than because the user asked to, so — unlike `logOut()` — it shows an alert explaining why before presenting the sign-in screen. It stops the monitor, clears the keychain, closes any web windows left on the now-unusable server, and presents `ServerAddressWindowController`. It does not attempt to revoke the app password: the server has already rejected it, so revoking it again would be pointless.
    func requireSignIn() {
        logger.notice("Credentials rejected; clearing keychain and requiring sign-in")
        NotificationMonitor.shared.stop()
        Keychain.clearAll()
        closeWebViewWindows()

        presentAlert(
            title: String(localized: "Signed Out", comment: "Alert title shown when the app signs the user out on its own because the server rejected the stored credentials."),
            message: String(localized: "Your Nextcloud credentials are no longer valid, so Cirruscope signed you out. Sign in again to continue.", comment: "Alert message shown when the app signs the user out because the server rejected the stored credentials.")
        )

        presentWindow(withIdentifier: "ServerAddressWindowController")
    }

    /// `serverCredentialsRejected()` returns the app to sign-in when `NotificationMonitor` reports its stream was rejected because the stored app password was revoked.
    @objc
    private func serverCredentialsRejected() {
        logger.notice("Notification monitor reported rejected credentials")
        requireSignIn()
    }

    /// `hasOpenWebWindow` is `true` while at least one web window is open, including any AppKit restored at launch.
    ///
    /// `presentInitialWindow(forLaunch:)` reads it at launch to avoid opening a duplicate window when AppKit already restored one, and `NotificationMonitor` reads it to suppress its own banners while the embedded web interface can surface its own.
    var hasOpenWebWindow: Bool {
        windowControllers.contains { $0 is WebWindowController }
    }

    /// `closeWebViewWindows()` closes every open web window.
    ///
    /// `presentInitialWindow(forLaunch:)` calls it at launch when the server turns out to be unreachable, unsupported, or to have revoked the stored credentials, so a restored window does not linger on a server the app can no longer use.
    private func closeWebViewWindows() {
        logger.debug("Closing web view windows…")

        // Iterate a snapshot: closing a window fires the `willClose` observer that mutates `windowControllers`.
        for windowController in windowControllers.filter({ $0 is WebWindowController }) {
            windowController.close()
        }
    }

    /// `presentWebViewWindow(targetURL:)` opens and tracks a web window, loading `targetURL` when given or `AccountStore.serverAddress` otherwise.
    ///
    /// `presentInitialWindow()` and `ServerAddressViewController` open the root window through it, and `openServerApp(_:)` opens app-specific windows, so every web window is created, cascaded, and retained the same way.
    func presentWebViewWindow(targetURL: URL? = nil) {
        logger.debug("Presenting web view window…")

        let storyboard = NSStoryboard(name: "Main", bundle: nil)

        guard let windowController = storyboard.instantiateController(withIdentifier: "WebViewWindowController") as? WebWindowController else {
            return
        }

        windowController.targetURL = targetURL
        // Give every web window a unique restoration identifier so AppKit tracks and restores each one separately.
        windowController.window?.identifier = NSUserInterfaceItemIdentifier(UUID().uuidString)
        present(windowController: windowController)
    }

    /// `openServerApp(_:)` brings the web window already showing `app` to the front, or opens a new window loading the app when none is open.
    ///
    /// The currently shown app of each window is reported by `WebViewController.currentAppID`. It does nothing when no server address is configured.
    func openServerApp(_ app: ServerAppTransferObject) {
        logger.log("Opening server app…")

        guard let serverAddress = AccountStore.shared.serverAddress else {
            return
        }

        if let existing = windowControllers.first(where: { ($0.contentViewController as? WebViewController)?.currentAppID == app.id }) {
            logger.log("Found existing window for server app \(app.id) to bring to front")
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        guard let url = URL(string: app.href, relativeTo: serverAddress)?.absoluteURL else {
            return
        }

        logger.log("Failed to find existing window for server app \(app.id) to bring to front, opening a new web view window")
        presentWebViewWindow(targetURL: url)
    }

    /// `logOut()` performs a full app-level logout: fires off a best-effort revocation of the stored Login Flow v2 app password on the server, closes every window, clears the web view's stored cookies and site data so no session for the old server lingers, disconnects the account via `AccountStore.disconnect()` (which deletes the account — cascading into its cached theme, version, apps, and shortcuts — empties `AssetCache`, and clears the stored Login Flow v2 credentials), and presents a fresh `ServerAddressWindowController`.
    ///
    /// Both `GeneralSettingsViewController.logOut(_:)` (the explicit Settings button) and `WebViewController+WKNavigationDelegate`'s detection of the web view navigating to the server's own logout or login page call this shared implementation, so both entry points behave identically and go through the same tracked window-presentation path as every other window `AppDelegate` creates.
    ///
    /// The credentialed `Server` for revocation is captured synchronously before anything else runs, then handed to an unawaited `Task` so a slow or unreachable server can never delay the window-closing, site-data-clearing, or sign-in-presenting steps below, matching Nextcloud's own fail-open guidance for this call. `Server` captures the app password by value at construction, and `ServerConnection.revokeAppPassword(using:)` never re-reads `Keychain`, so the `Task` remains free to complete the request even after `AccountStore.disconnect()` clears the same credential from `Keychain` further down in this method.
    func logOut() {
        logger.notice("Logging out; revoking the app password on the server, closing all windows, clearing the web view's site data, and clearing the server address and credentials")

        if let serverAddress = AccountStore.shared.serverAddress, let server = ServerConnection.authenticated(address: serverAddress) {
            logger.debug("Attempting to revoke the app password on the server before completing local sign-out")
            Task {
                await ServerConnection.revokeAppPassword(using: server)
            }
        } else {
            logger.debug("No server address or stored credentials to revoke an app password for")
        }

        // Stop tracking notifications and clear the Dock badge before the credentials it relies on are removed.
        NotificationMonitor.shared.stop()

        for window in NSApplication.shared.windows {
            window.close()
        }

        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
            self.logger.debug("Cleared the web view's site data")
        }

        AccountStore.shared.disconnect()

        presentWindow(withIdentifier: "ServerAddressWindowController")
    }

    /// `showDownloads(_:)` backs the "Downloads" menu item, opening the download history window or bringing it to the front when it is already open.
    ///
    /// It targets the responder chain from the menu item, so this single handler serves the menu; `downloadDidStart()` opens the same window when a transfer begins.
    @IBAction
    func showDownloads(_: Any?) {
        logger.log("Showing downloads…")
        showDownloadsWindow()
    }

    /// `showDownloadsWindow()` brings the single Downloads window to the front, instantiating and tracking it from the storyboard first when none is open, and activates the app so the window comes to the foreground.
    ///
    /// `showDownloads(_:)` and `downloadDidStart()` both call it, so the menu item and a starting download converge on one window rather than each opening its own.
    func showDownloadsWindow() {
        if let existing = windowControllers.first(where: { $0.contentViewController is DownloadViewController }) {
            logger.log("Showing existing downloads window…")
            existing.showWindow(self)
        } else {
            logger.log("Showing new downloads window…")
            presentWindow(withIdentifier: "DownloadsWindowController")
        }

        NSApp.activate()
    }

    /// `downloadDidStart()` opens the Downloads window when `DownloadManager` reports that a transfer has begun.
    ///
    /// `DownloadManager.handle(_:)` posts `Notification.Name.downloadDidStart` on the main actor, so presenting the window here runs on the main thread.
    @objc
    private func downloadDidStart() {
        logger.log("Download did start")
        showDownloadsWindow()
    }

    @IBAction
    func performServerApp(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let app = AccountStore.shared.serverApps.first(where: { $0.id == id })
        else {
            return
        }

        openServerApp(app)
    }

    /// `serverAppsDidChange()` rebuilds the View menu when `Settings` posts that the server apps or their shortcuts changed.
    @objc
    private func serverAppsDidChange() {
        logger.log("Server apps did change")
        rebuildServerAppsMenu()
    }

    /// `rebuildServerAppsMenu()` replaces the dynamic server-app items in the View menu with the current `AccountStore.serverApps`, applying each app's configured shortcut.
    ///
    /// It removes the items it previously inserted and inserts the current apps directly after `serverAppsSeparator`, which keeps them within the storyboard's bracketed section.
    private func rebuildServerAppsMenu() {
        logger.log("Rebuilding server apps menu…")

        guard let menu = serverAppsSeparator?.menu else {
            return
        }

        for item in serverAppMenuItems {
            menu.removeItem(item)
        }

        serverAppMenuItems.removeAll()

        var index = menu.index(of: serverAppsSeparator) + 1

        for app in AccountStore.shared.serverApps {
            let item = menuItem(for: app)
            menu.insertItem(item, at: index)
            serverAppMenuItems.append(item)
            index += 1
        }

        logger.log("Completed server app menu rebuilding")
    }

    /// `menuItem(for:)` builds a menu item that opens `app` via `performServerApp(_:)`, applying the user's configured keyboard shortcut for it when one exists.
    private func menuItem(for app: ServerAppTransferObject) -> NSMenuItem {
        let item = NSMenuItem(title: app.name, action: #selector(performServerApp(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = app.id

        if let shortcut = AccountStore.shared.shortcut(forAppID: app.id) {
            item.keyEquivalent = shortcut.keyEquivalent
            item.keyEquivalentModifierMask = shortcut.modifierMask
        }

        return item
    }

    private func presentWindow(withIdentifier identifier: String) {
        logger.log("Presenting window with identifier \(identifier)…")
        let storyboard = NSStoryboard(name: "Main", bundle: nil)

        guard let windowController = storyboard.instantiateController(withIdentifier: identifier) as? NSWindowController else {
            return
        }

        present(windowController: windowController)
    }

    private func presentAlert(title: String, message: String) {
        logger.log("Presenting alert with title \(title) and informative text \(message)…")

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func present(windowController: NSWindowController, sender: Any? = nil) {
        logger.log("Presenting window controller \(windowController)…")

        guard let window = windowController.window else {
            return
        }

        lastCascadePoint = window.cascadeTopLeft(from: lastCascadePoint)
        track(windowController)
        windowController.showWindow(sender)
    }

    /// `track(_:)` retains `windowController` so its window survives while visible and drops it once the window closes.
    ///
    /// `present(windowController:sender:)` calls it after cascading and before showing; the restoration path calls it on its own for windows AppKit positions and shows itself, so those are retained without being cascaded or shown a second time.
    func track(_ windowController: NSWindowController) {
        logger.log("Tracking window controller \(windowController)…")
        guard let window = windowController.window else {
            return
        }

        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self, weak windowController] _ in
            // The observer is delivered on the main queue, so the main-actor state it drops the window controller from is safe to touch here.
            MainActor.assumeIsolated {
                guard let self, let windowController else {
                    return
                }
                self.windowControllers.removeAll { $0 === windowController }
            }
        }

        windowControllers.append(windowController)
    }
}
