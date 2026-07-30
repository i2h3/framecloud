// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Cocoa
import os
import WebKit

/// `WebViewController` backs the storyboard scene that hosts the embedded `WKWebView` Cirruscope uses to display Nextcloud.
///
/// `AppDelegate` presents it on launch when `AccountStore.serverAddress` is non-`nil`, and `ServerAddressViewController` transitions to it after persisting a freshly validated server address.
/// It injects the bundled `Cirruscope.css` stylesheet, bridges custom title-bar drag behaviour, and tracks the state of Nextcloud's sidebar so that `WebViewController+NSMenuItemValidation` can drive the "Show/Hide Sidebar" menu item. The drag and sidebar behaviours are driven by the JavaScript resources enumerated in `WebViewScript`, which are loaded from the bundle on demand rather than embedded in this source file.
/// The hosted `WKWebView` is hidden in the storyboard and only revealed by `WebViewController+WKNavigationDelegate` once its initial page load completes so the user is not exposed to the unstyled intermediate paint of the Nextcloud interface.
class WebViewController: NSViewController, WKScriptMessageHandler {
    // MARK: - Outlets

    ///
    /// Show the cached web user interface background image (if any available).
    ///
    @IBOutlet
    var backgroundImageView: NSImageView!

    @IBOutlet
    var stateOverlay: NSStackView!

    ///
    /// An animated activity indicator.
    ///
    /// Only visible during the initial page load, hidden when a load failed.
    ///
    @IBOutlet
    var progressIndicator: NSProgressIndicator!

    ///
    /// Multi-functional label for the current state.
    ///
    /// Should be something like "Loading" on window revelation and "Server unreachable" in case of failed page loads.
    ///
    @IBOutlet
    var headline: NSTextField!

    ///
    /// An optional and longer text to explain the failed page load, if so.
    ///
    @IBOutlet
    var explanation: NSTextField!

    ///
    /// Optional retry button for failed page loads.
    ///
    /// Visibility depends on the web view state.
    ///
    @IBOutlet
    var retry: NSButton!

    /// `webView` is the `WKWebView` that loads `AccountStore.serverAddress` and renders the Nextcloud web interface.
    ///
    /// `viewDidLoad()` configures it, installs the user scripts produced by `injectCustomStyleSheet()`, `installWindowDragBridge()`, and `installSidebarToggleBridge()`, and triggers the initial navigation.
    /// The view is hidden in the storyboard and unhidden by `webView(_:didFinish:)` after the initial navigation has completed.
    @IBOutlet
    var webView: WKWebView!

    // MARK: - Logging

    /// `logger` records this web view controller's activity under the `WebViewController` category; it is not `private` so the delegate conformances in `WebViewController+WKNavigationDelegate` and `+WKUIDelegate` can log through it.
    let logger = Logger(for: WebViewController.self)

    /// `nextLogID` hands out the monotonically increasing values behind `logID`, so each `WebViewController` receives a distinct identifier for the lifetime of the process.
    private static var nextLogID: UInt64 = 0

    /// `logID` is a per-instance identifier appended to this controller's log messages, for example "(WebViewController 3)", so entries from different web windows — which each have their own `WebViewController` sharing the `WebViewController` category — can be told apart while the category stays stable and filterable.
    ///
    /// It is an auto-incremented `UInt64`, which `os.Logger` prints in the clear (unlike a string, which would be redacted), and it is not `private` so the delegate extensions that log can append it too.
    let logID: UInt64 = {
        WebViewController.nextLogID += 1
        return WebViewController.nextLogID
    }()

    // MARK: - Initial Load

    /// `hasRevealedAfterInitialLoad` is `true` once `webView` has been unhidden after its initial navigation has completed.
    ///
    /// `webView(_:didFinish:)` consults this flag so the reveal happens exactly once, on the first finished navigation, and subsequent navigations do not touch the view's visibility.
    var hasRevealedAfterInitialLoad = false

    /// `hasStartedInitialLoad` is `true` once the initial navigation has been issued, so `viewWillAppear()` triggers it exactly once.
    private var hasStartedInitialLoad = false

    /// `pendingRetryURL` is the URL the retry button should reload: the address that last failed to load, or the initial target before the first load has been attempted.
    ///
    /// `startInitialLoadIfNeeded()` seeds it with the initial target, `handleNavigationFailure(_:)` updates it to the URL that actually failed, and `retryLoad(_:)` reloads it — rather than calling `WKWebView.reload()`, which does nothing after a provisional failure that never committed a page.
    private var pendingRetryURL: URL?

    /// `hasRetriedLoginRedirect` is `true` once `WebViewController+WKNavigationDelegate` has silently re-issued a navigation redirected to the server's login page with the stored app password, so a second such redirect is recognized as the credential itself being rejected rather than an ordinary expired browser-session cookie.
    ///
    /// `webView(_:decidePolicyFor:decisionHandler:)` sets it before retrying and consults it to decide whether to retry again or fall back to `AppDelegate.requireSignIn()`; `webView(_:didFinish:)` clears it on every successful load so a later, unrelated session expiry still gets its own retry attempt.
    var hasRetriedLoginRedirect = false

    /// `webWindowController` is the `WebWindowController` hosting this controller, from which the `targetURL` to load is read once the view is in its window.
    private var webWindowController: WebWindowController? {
        view.window?.windowController as? WebWindowController
    }

    /// `restorableURL` is the URL to persist for window restoration: the page currently shown, or the window's target before the first load completes.
    ///
    /// `WebWindow.encodeRestorableState(with:)` reads it so a relaunch can reopen this window on the same page.
    var restorableURL: URL? {
        webView.url ?? webWindowController?.targetURL
    }

    /// `startInitialLoadIfNeeded()` issues the initial navigation the first time the view appears, loading the host window controller's `targetURL` when set or `AccountStore.serverAddress` otherwise.
    ///
    /// It runs from `viewWillAppear()` rather than `viewDidLoad()` because the host `WebWindowController` and its `targetURL` are only reachable once the view has been placed in its window.
    private func startInitialLoadIfNeeded() {
        guard hasStartedInitialLoad == false else {
            return
        }

        guard let url = webWindowController?.targetURL ?? AccountStore.shared.serverAddress else {
            preconditionFailure("WebViewController was loaded without a connected server address.")
        }

        hasStartedInitialLoad = true
        pendingRetryURL = url
        logger.info("Starting initial navigation (WebViewController \(self.logID))")
        webView.load(authenticatedRequest(for: url))
    }

    /// `authenticatedRequest(for:)` builds the request that loads `url`, attaching HTTP Basic authentication derived from the `Credentials` stored for the connected server address when they are available.
    ///
    /// Nextcloud accepts the app password as Basic authentication and establishes a web session from it, so the embedded web view is signed in without a separate in-page login. When no credentials are stored the request is unauthenticated and the server presents its normal login page.
    /// Not `private`: `WebViewController+WKNavigationDelegate` also calls this, to silently retry with the stored app password when the web view is redirected to the login page mid-session rather than at the initial load.
    func authenticatedRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)

        if let serverAddress = AccountStore.shared.serverAddress, let credentials = Keychain.credentials(for: serverAddress) {
            let encoded = Data("\(credentials.user):\(credentials.appPassword)".utf8).base64EncodedString()
            request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        webView.isInspectable = true
        webView.navigationDelegate = self
        webView.uiDelegate = self
        observeWebViewTitle()
        observeWebViewURL()
        injectCustomStyleSheet()
        installWindowDragBridge()
        installSidebarToggleBridge()
        installNotificationBridge()
        updateBackgroundImage()

        showLoadingState()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        startInitialLoadIfNeeded()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        progressIndicator.startAnimation(self)
    }

    // MARK: - State Overlay

    /// `showLoadingState()` configures `stateOverlay` for an in-progress page load: the spinner and `headline` are shown, `explanation` and `retry` are hidden, and the web view stays hidden behind the background until the load finishes.
    ///
    /// `viewDidLoad()` calls it for the initial load and `retryLoad(_:)` calls it again when the user retries after a failure. Because `stateOverlay` detaches hidden arranged views, toggling each child's `isHidden` also collapses it out of the card's layout.
    private func showLoadingState() {
        headline.stringValue = String(localized: "Loading…", comment: "Headline shown in the web window while the page is loading.")
        headline.isHidden = false
        progressIndicator.isHidden = false
        progressIndicator.startAnimation(self)
        explanation.isHidden = true
        retry.isHidden = true
        webView.isHidden = true
        backgroundImageView.isHidden = false
        stateOverlay.isHidden = false
    }

    /// `handleNavigationFailure(_:)` switches `stateOverlay` to its failure state — hiding the spinner and showing the "Server unreachable" headline, a friendly explanation, and the retry button — and records the URL a retry should reload.
    ///
    /// `WebViewController+WKNavigationDelegate` calls it from both `didFail` and `didFailProvisionalNavigation`. Navigations the app cancels itself — an external host handed to the browser, the server's own logout/login page, or a response turned into a download — surface here as cancellation errors rather than genuine load failures, so those are ignored to keep the overlay from flashing over content the user is still using.
    func handleNavigationFailure(_ error: any Error) {
        let nsError = error as NSError

        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return
        }

        // `WebKitErrorFrameLoadInterruptedByPolicyChange` (102): a navigation cancelled by one of our own policy decisions.
        if nsError.domain == "WebKitErrorDomain", nsError.code == 102 {
            return
        }

        pendingRetryURL = (nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL)
            ?? webView.url
            ?? webWindowController?.targetURL
            ?? AccountStore.shared.serverAddress

        progressIndicator.stopAnimation(self)
        progressIndicator.isHidden = true
        headline.stringValue = String(localized: "Server unreachable", comment: "Headline shown in the web window when a page load failed.")
        headline.isHidden = false
        explanation.stringValue = String(localized: "Check your internet connection and make sure the server is online, then try again.", comment: "Explanation shown in the web window when a page load failed.")
        explanation.isHidden = false
        retry.isHidden = false
        webView.isHidden = true
        backgroundImageView.isHidden = false
        stateOverlay.isHidden = false
    }

    /// `revealLoadedContent()` hides `stateOverlay` and the background and reveals the web view once a navigation has finished.
    ///
    /// `WebViewController+WKNavigationDelegate`'s `didFinish` calls it after every successful load, so a retry that follows a failure restores the web view too, not only the very first load. It makes the web view the first responder each time so it rejoins the key window's responder chain and re-enables the Back/Forward/Reload menu items: `handleNavigationFailure(_:)` hides the web view on a failure, which makes AppKit resign its first-responder status, so it has to be restored on every reveal rather than only the first.
    func revealLoadedContent() {
        progressIndicator.stopAnimation(self)
        stateOverlay.isHidden = true
        backgroundImageView.isHidden = true
        webView.isHidden = false
        view.window?.makeFirstResponder(webView)
    }

    /// `retryLoad(_:)` re-issues the failed navigation when the user taps the retry button, returning `stateOverlay` to its loading state until the load succeeds or fails again.
    ///
    /// It reloads `pendingRetryURL` rather than calling `WKWebView.reload()`, which would do nothing after a provisional failure that never committed a page.
    @IBAction
    func retryLoad(_: Any?) {
        guard let url = pendingRetryURL ?? webWindowController?.targetURL ?? AccountStore.shared.serverAddress else {
            return
        }

        logger.info("Retrying navigation to \(url.absoluteString) (WebViewController \(self.logID))")
        showLoadingState()
        webView.load(authenticatedRequest(for: url))
    }

    // MARK: - Background

    /// `updateBackgroundImage()` shows the server's cached theming background behind the web view, or nothing when no background image is available so the window background shows through.
    ///
    /// `viewDidLoad()` calls it. The image is the cached copy of the theming background, downloaded by `AccountStore.persist(theming:)` via `AssetCache`. Both paths that produce the *first* web window — `AppDelegate.presentInitialWindow(forLaunch:)` at launch and `ServerAddressViewController` after sign-in — await `ServerConnection.validate(_:)`, and so that download, before presenting it, which is what puts the asset on disk. A window opened later by ⌘N deliberately does not wait for that validation, and simply reads the copy those paths already cached; a miss is not an error state but the ordinary "no background available" case `cachedBackgroundImage()` returns `nil` for, leaving the window background to show through.
    private func updateBackgroundImage() {
        backgroundImageView.image = cachedBackgroundImage()
    }

    /// `cachedBackgroundImage()` returns the cached theming background image, or `nil` when the server publishes a plain color, the background is not an `http`/`https` image URL, or no cached copy exists yet.
    private func cachedBackgroundImage() -> NSImage? {
        guard AccountStore.shared.themeBackgroundPlain != true,
              let background = AccountStore.shared.themeBackground,
              let url = URL(string: background),
              url.scheme == "http" || url.scheme == "https",
              let localURL = AssetCache.shared.localURL(for: url)
        else {
            return nil
        }

        return NSImage(contentsOf: localURL)
    }

    // MARK: - Window Title

    /// `titleObservation` retains the key-value observation of `webView`'s `title` that keeps the host window's title in sync with the currently displayed Nextcloud page.
    ///
    /// `observeWebViewTitle()` assigns it during `viewDidLoad()`, and it is released when the controller is deallocated, which ends the observation.
    private var titleObservation: NSKeyValueObservation?

    /// `observeWebViewTitle()` starts mirroring `webView.title` into the host window's title so the page title identifies the window in Mission Control, the "Window" menu, and other system UI, even though the title bar itself hides it.
    ///
    /// `viewDidLoad()` calls this once after the web view has been configured. The observation reads `webView.title` on every change, including the in-page title updates Nextcloud performs as the user navigates its single-page interface, and substitutes an empty string while the page has not yet reported a title.
    private func observeWebViewTitle() {
        titleObservation = webView.observe(\.title, options: [.initial, .new], changeHandler: makeTitleChangeHandler())
    }

    /// `makeTitleChangeHandler()` builds the KVO change handler `observeWebViewTitle()` registers on `webView.title`.
    ///
    /// It is `nonisolated` so the closure it returns is not itself inferred main-actor-isolated: `WebViewController` is main-actor-isolated via `NSResponder`, so a closure written directly inside one of its methods would inherit that isolation too, and trip a dynamic isolation check if `WKWebView` ever delivered this KVO callback off the main thread instead of hopping to the main actor explicitly, as this handler now does.
    ///
    /// Only `change.newValue` — the `Sendable` `String?` KVO already snapshotted — crosses into the `Task`, rather than `webView` itself, since `WKWebView` is main-actor-isolated and not `Sendable`.
    private nonisolated func makeTitleChangeHandler() -> @Sendable (WKWebView, NSKeyValueObservedChange<String?>) -> Void {
        { [weak self] _, change in
            let title = change.newValue.flatMap(\.self) ?? ""
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                logger.debug("Web view title changed to \"\(title)\" (WebViewController \(self.logID))")
                view.window?.title = title
            }
        }
    }

    // MARK: - Web View URL

    /// `urlObservation` retains the key-value observation of `webView`'s `url` that logs every change to the currently displayed page's address.
    ///
    /// `observeWebViewURL()` assigns it during `viewDidLoad()`, and it is released when the controller is deallocated, which ends the observation.
    private var urlObservation: NSKeyValueObservation?

    /// `observeWebViewURL()` logs `webView.url` on every change so same-document navigations are visible in a log capture.
    ///
    /// `viewDidLoad()` calls this once after the web view has been configured. It complements `WebViewController+WKNavigationDelegate`, whose delegate callbacks fire only for the loading pipeline: Nextcloud's single-page interface changes the URL through the History API (`history.pushState` / `replaceState`, and `popstate`), which are same-document navigations that never issue a request or a document load, so `WKNavigationDelegate` never sees them. `WKWebView.url` is key-value-observing compliant and does update for those changes, which is why this observation catches what the delegate cannot.
    private func observeWebViewURL() {
        urlObservation = webView.observe(\.url, options: [.initial, .new], changeHandler: makeURLChangeHandler())
    }

    /// `makeURLChangeHandler()` builds the KVO change handler `observeWebViewURL()` registers on `webView.url`.
    ///
    /// It is `nonisolated` for the same reason as `makeTitleChangeHandler()`: so the closure it returns is not inferred main-actor-isolated and does not trip a dynamic isolation check should `WKWebView` ever deliver this KVO callback off the main thread instead of hopping to the main actor as this handler does.
    ///
    /// Only `change.newValue` — the `Sendable` `URL??` KVO already snapshotted — crosses into the `Task`, rather than `webView` itself, since `WKWebView` is main-actor-isolated and not `Sendable`.
    private nonisolated func makeURLChangeHandler() -> @Sendable (WKWebView, NSKeyValueObservedChange<URL?>) -> Void {
        { [weak self] _, change in
            let url = change.newValue.flatMap(\.self)
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                logger.debug("Web view URL changed to \(url?.absoluteString ?? "nil") (WebViewController \(self.logID))")
            }
        }
    }

    // MARK: - Server App

    /// `currentAppID` is the Nextcloud app id of the page the web view currently shows, derived from its URL, or `nil` when the URL does not address a recognizable app on the configured server.
    ///
    /// Until the web view reports a URL it falls back to the app id of the host window controller's `targetURL`, so a window opened for an app is recognized before its first load completes. `AppDelegate.openServerApp(_:)` reads this to focus an existing window instead of opening a duplicate.
    var currentAppID: String? {
        guard let url = webView.url else {
            return webWindowController?.targetURL.flatMap { Self.appID(fromPath: $0.path) }
        }

        guard let host = url.host,
              let serverHost = AccountStore.shared.serverAddress?.host,
              host.caseInsensitiveCompare(serverHost) == .orderedSame
        else {
            return nil
        }

        return Self.appID(fromPath: url.path)
    }

    /// `appID(fromPath:)` extracts the Nextcloud app id from a URL path of the form `/apps/<id>/…` or `/index.php/apps/<id>/…`, or returns `nil` when the path does not address an app.
    static func appID(fromPath path: String) -> String? {
        var components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        if components.first == "index.php" {
            components.removeFirst()
        }

        guard components.count >= 2, components[0] == "apps" else {
            return nil
        }

        return components[1]
    }

    // MARK: - Window Dragging

    private func installWindowDragBridge() {
        webView.configuration.userContentController.add(self, name: ScriptMessageName.windowDrag.rawValue)
        installUserScript(.windowDrag, injectionTime: .atDocumentEnd)
    }

    // MARK: - Sidebar

    /// `sidebarToggleAvailable` is `true` while the currently loaded Nextcloud page exposes a sidebar toggle that can be activated.
    ///
    /// `WebViewController+NSMenuItemValidation` reads this value to enable or disable the "Show/Hide Sidebar" menu item.
    var sidebarToggleAvailable = false

    /// `sidebarToggleExpanded` is `true` while Nextcloud's sidebar is currently shown.
    ///
    /// `WebViewController+NSMenuItemValidation` reads this value to switch the title of the "Show/Hide Sidebar" menu item between "Hide Sidebar" and "Show Sidebar".
    var sidebarToggleExpanded = false

    private func installSidebarToggleBridge() {
        webView.configuration.userContentController.add(self, name: ScriptMessageName.sidebarToggleState.rawValue)
        installUserScript(.sidebarToggleState, injectionTime: .atDocumentEnd)
    }

    @IBAction
    func toggleSidebar(_: Any?) {
        guard let source = WebViewScript.sidebarToggle.source else {
            return
        }

        webView.evaluateJavaScript(source)
    }

    // MARK: - Notifications

    private func installNotificationBridge() {
        UserNotifier.shared.requestAuthorization()
        webView.configuration.userContentController.add(self, name: ScriptMessageName.notification.rawValue)
        installUserScript(.notificationBridge, injectionTime: .atDocumentStart)
    }

    // MARK: - Web View Styling

    private func injectCustomStyleSheet() {
        guard
            let url = Bundle.main.url(forResource: "Cirruscope", withExtension: "css"),
            let css = try? String(contentsOf: url, encoding: .utf8)
        else {
            return
        }

        let escaped = css
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")

        let source = """
        (function() {
            var style = document.createElement('style');
            style.textContent = `\(escaped)`;
            document.documentElement.appendChild(style);
        })();
        """

        let script = WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)

        webView.configuration.userContentController.addUserScript(script)
    }

    // MARK: - Script Bridge

    /// `ScriptMessageName` is the central list of script-message names that the injected user scripts post back to `userContentController(_:didReceive:)`.
    ///
    /// Each raw value is the name a `WebViewScript` uses in `window.webkit.messageHandlers.<name>.postMessage(…)`; the `install…Bridge()` methods register a handler for it on the web view's `WKUserContentController`, and `userContentController(_:didReceive:)` switches on it.
    private enum ScriptMessageName: String {
        /// `windowDrag` is posted by `WebViewScript.windowDrag` to ask the host window to begin a drag.
        case windowDrag

        /// `sidebarToggleState` is posted by `WebViewScript.sidebarToggleState` to report whether Nextcloud's sidebar toggle is available and expanded.
        case sidebarToggleState

        /// `notification` is posted by `WebViewScript.notificationBridge` to forward a web notification's content to the app.
        case notification
    }

    /// `installUserScript(_:injectionTime:)` loads `script` from its bundled resource and registers it on the web view's `WKUserContentController` so it runs at `injectionTime` on every page load, doing nothing if the resource cannot be read.
    ///
    /// `installWindowDragBridge()` and `installSidebarToggleBridge()` call this after registering the script-message handlers their scripts post back to.
    private func installUserScript(_ script: WebViewScript, injectionTime: WKUserScriptInjectionTime) {
        guard let source = script.source else {
            return
        }

        let userScript = WKUserScript(source: source, injectionTime: injectionTime, forMainFrameOnly: false)
        webView.configuration.userContentController.addUserScript(userScript)
    }

    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        switch ScriptMessageName(rawValue: message.name) {
            case .windowDrag:
                guard let window = view.window,
                      let event = NSApp.currentEvent
                else {
                    return
                }
                window.performDrag(with: event)

            case .sidebarToggleState:
                guard let body = message.body as? [String: Any] else {
                    return
                }
                sidebarToggleAvailable = body["available"] as? Bool ?? false
                sidebarToggleExpanded = body["expanded"] as? Bool ?? false

            case .notification:
                guard let body = message.body as? [String: Any] else {
                    return
                }
                UserNotifier.shared.post(title: body["title"] as? String ?? "", body: body["body"] as? String ?? "", tag: body["tag"] as? String ?? "", webNotificationID: body["id"] as? String ?? "", webView: webView)

            case nil:
                break
        }
    }
}
