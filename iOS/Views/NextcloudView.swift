// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import os
import SwiftUI
import WebKit

struct NextcloudView: View {
    @Environment(Store.self)
    private var store

    ///
    /// Which way text runs, which is what decides whether SwiftUI's leading edge is the physically left one.
    ///
    @Environment(\.layoutDirection)
    private var layoutDirection

    ///
    /// How many pixels this screen draws to the point, which is the resolution an icon has to be rendered at to look sharp on it.
    ///
    @Environment(\.displayScale)
    private var displayScale

    @State
    private var page: WebPage

    ///
    /// Carries what the loaded page reports about its app-navigation toggle, which is what decides whether the toolbar control is on screen and how it renders.
    ///
    @State
    private var appNavigation: AppNavigationBridge

    ///
    /// The page's own script store, kept so the document-start scripts can be re-registered with a fresh measurement rather than only ever seeded once.
    ///
    /// `WebPage.Configuration` is a struct the page copies at initialization, but this property of it is a class, so the copy and this reference are the same object and a script added through it still reaches the page.
    ///
    @State
    private var userContentController: WKUserContentController

    ///
    /// The most recent measurement of how much of the web view the app's own interface covers, or `nil` until the first layout pass has produced one.
    ///
    /// Nothing is loaded while it is `nil`: the first document has to be able to inset itself as it parses, and until SwiftUI has laid the view out there is no honest value to give it.
    ///
    @State
    private var insets: WebPageInsets?

    ///
    /// Records this screen's activity under the `NextcloudView` category.
    ///
    /// Static because a `View` is a value rebuilt on every parent body evaluation, and one logger per screen is enough.
    ///
    private static let logger = Logger(for: NextcloudView.self)

    init() {
        var configuration = WebPage.Configuration()
        let appNavigation = AppNavigationBridge()

        // Completes the user agent into one Safari sends, so Nextcloud does not warn about an unrecognized browser.
        // It has to be set here for the same reason as the handler below, and stays set for the whole session: the
        // Cirruscope name the server associates a login with belongs to the sign-in request, not to this web view.
        configuration.applicationNameForUserAgent = SafariUserAgent.applicationName

        // The handler has to be on the configuration before the page is built: `WebPage.Configuration` is a struct the
        // page copies at initialization, so one registered afterwards would never reach it. User scripts are not
        // installed here at all — they are installed from the first measurement, which does not exist yet.
        configuration.userContentController.add(appNavigation, name: AppNavigationBridge.messageName)

        let page = WebPage(configuration: configuration)
        page.isInspectable = true

        _page = State(initialValue: page)
        _appNavigation = State(initialValue: appNavigation)
        _userContentController = State(initialValue: configuration.userContentController)
    }

    var body: some View {
        NavigationStack {
            // The web view ignores the safe area so the page paints to the bezel, which leaves it no insets of its own
            // to report. This reader is the sibling that still respects the safe area, and sits at the one place whose
            // insets are the whole of what covers the page: the device's own, plus the navigation bar above it.
            GeometryReader { proxy in
                WebView(page)
                    // `.container` rather than the default of every region: the bare `ignoresSafeArea()` would ignore
                    // the keyboard too, and a focused field in Talk or Text would then sit behind it.
                    .ignoresSafeArea(.container, edges: .all)
                    .webViewMagnificationGestures(.disabled)
                    .webViewBackForwardNavigationGestures(.disabled)
                    .onChange(of: measurement(in: proxy), initial: true) { _, measurement in
                        apply(measurement)
                    }
            }
            .toolbar {
                // Not every Nextcloud app offers an app navigation, so the control leaves the toolbar rather
                // than greying out. `ToolbarContent.hidden(_:)` would say that more directly but is macOS-only —
                // it belongs to toolbar customization, which iOS has no equivalent of — so the item is built
                // conditionally instead.
                if appNavigation.isAvailable {
                    // A `Toggle` rather than a `Button` so the toolbar renders its on state as the selected
                    // glass background: `sidebar.left` has no filled variant to swap to, so reflecting the state
                    // through the symbol would have been a silent no-op. The setter ignores its argument and
                    // only asks the page to toggle — `isExpanded` then follows what the page actually did,
                    // rather than what the tap assumed it would do.
                    ToolbarItem(placement: .navigation) {
                        Toggle(isOn: Binding(get: { appNavigation.isExpanded }, set: { _ in toggleAppNavigation() })) {
                            Label("App Navigation", systemImage: "sidebar.left")
                        }
                        .toggleStyle(.button)
                    }
                }

                ToolbarTitleMenu {
                    ForEach(store.apps) { app in
                        Button {
                            navigateToApp(app)
                        } label: {
                            Label {
                                Text(app.name)
                            } icon: {
                                icon(for: app)
                            }
                        }
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            store.logout()
                        } label: {
                            Label("Logout", systemImage: "iphone.and.arrow.forward.outward")
                        }
                    } label: {
                        Label("Account", systemImage: "person.fill")
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
        .task(id: insets) {
            guard insets != nil else {
                return
            }

            guard page.url == nil else {
                return
            }

            guard let account = store.account else {
                return
            }

            page.load(authenticatedRequest(for: account.server))
            store.updateApps()
        }
        .task {
            await republishInsetsOnNavigation()
        }
    }

    ///
    /// What the navigation bar is titled with: the name of the Nextcloud app on screen, or the page's own title where the app cannot be told.
    ///
    /// The app's name is the shorter of the two by some way — "Files" against "Files - Nextcloud" — and this title is also the button that opens the app menu, so the space it does not take is space the app-navigation toggle and the account menu get to keep.
    /// Reading `page.url` here is what subscribes this view to it, `WebPage` being observable, exactly as reading `page.title` subscribes it to that. Nothing else in the app reads the URL from a view body, so it is worth naming the mechanism.
    /// The fallback is reached by more than a failure, so it has to read as a title in its own right rather than as an error, which is what `PageTitle.withoutSiteName(_:)` makes it. It covers the moment after launch before the app list has arrived, and the pages that genuinely belong to no app the server lists — its settings and a user's profile among them. A page that merely leaves its app's own path does not land here: a Talk conversation at `/call/<token>` resolves to Talk, the rule knowing the routes an app registers at the server's root.
    ///
    private var navigationTitle: String {
        guard let url = page.url else {
            return PageTitle.withoutSiteName(page.title)
        }

        guard let app = store.app(for: url) else {
            return PageTitle.withoutSiteName(page.title)
        }

        return app.name
    }

    ///
    /// Reads how much of the web view the app's own interface covers out of a layout that still respects the safe area.
    ///
    /// The reader is inset by exactly what covers the page, so its own insets are the measurement. It reports a width of zero until the view has actually been laid out, and that pass is not a measurement: adopting it would release the first load against insets of zero, so the page would parse uninset and be corrected a frame later.
    ///
    private func measurement(in proxy: GeometryProxy) -> WebPageInsets? {
        guard proxy.size.width > 0 else {
            return nil
        }

        let safeArea = proxy.safeAreaInsets

        return WebPageInsets(top: safeArea.top, leading: safeArea.leading, bottom: safeArea.bottom, trailing: safeArea.trailing, isRightToLeft: layoutDirection == .rightToLeft)
    }

    ///
    /// Adopts a new measurement, so that documents loaded from now on inset themselves as they parse and the one already on screen re-insets itself now.
    ///
    private func apply(_ measurement: WebPageInsets?) {
        guard let measurement else {
            return
        }

        guard measurement != insets else {
            return
        }

        insets = measurement

        installUserScripts(with: measurement)
        publishInsets()
    }

    ///
    /// Registers every user script the page runs, with `measurement` baked into the one that publishes the insets.
    ///
    /// All three are re-registered together on every measurement rather than the insets script alone, because a `WKUserContentController` can only be emptied wholesale. Doing it at all is what keeps a document loaded after a rotation from being seeded with the insets of the previous orientation.
    /// The stylesheet runs at document start so the page never paints unstyled, the insets script immediately after it so the properties it declares are set before the first layout, and the app-navigation observer at document end, once there is a document for it to observe.
    ///
    private func installUserScripts(with measurement: WebPageInsets) {
        userContentController.removeAllUserScripts()

        if let source = Script.styleSheet.source {
            userContentController.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }

        if let function = iOSScript.safeAreaInsets.source {
            userContentController.addUserScript(WKUserScript(source: measurement.invocation(of: function), injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }

        if let source = Script.sidebarToggleState.source {
            userContentController.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        }
    }

    ///
    /// Publishes the current measurement into the page already on screen.
    ///
    /// The user script covers every document from its own start, so this is what covers the case the user script cannot: a page that is already parsed when the geometry changes under it, which is what a rotation is.
    ///
    private func publishInsets() {
        guard let insets else {
            return
        }

        guard let function = iOSScript.safeAreaInsets.source else {
            return
        }

        Task {
            do {
                _ = try await page.callJavaScript(insets.invocation(of: function))
            } catch {
                Self.logger.error("Could not publish the safe area insets: \(error.localizedDescription)")
            }
        }
    }

    ///
    /// Publishes the current measurement again each time a new document commits.
    ///
    /// A backstop, not the mechanism: the user script has already set the properties by the time this runs. It is here for the case where a document commits carrying a seed that predates the last measurement, and it costs nothing when it has nothing to correct. `.committed` rather than `.finished` because the document exists from that point on, well before the page has finished loading and painting.
    ///
    private func republishInsetsOnNavigation() async {
        do {
            for try await event in page.navigations where event == .committed {
                publishInsets()
            }
        } catch {
            Self.logger.error("Stopped observing navigations: \(error.localizedDescription)")
        }
    }

    ///
    /// Ask the page to show or hide Nextcloud's app navigation, by clicking the toggle the web interface offers.
    ///
    /// The same script backs macOS's "Show/Hide Sidebar" menu item, so both platforms drive the web interface through one click target. Nothing is assumed about the outcome: `AppNavigationBridge` reports the resulting state back, and the toolbar control renders from that.
    ///
    private func toggleAppNavigation() {
        guard let source = Script.sidebarToggle.source else {
            return
        }

        Task {
            do {
                _ = try await page.callJavaScript(source)
            } catch {
                Self.logger.error("Could not toggle the app navigation: \(error.localizedDescription)")
            }
        }
    }

    ///
    /// The image one server app is listed with: its own, when one has been downloaded, and a generic placeholder when it has not.
    ///
    /// Reading `store.iconGeneration` is what subscribes this menu to icons arriving: they live in files shared with the Mac rather than on the apps themselves, so nothing about `store.apps` changes when one lands and observation would otherwise never notice.
    ///
    @ViewBuilder
    private func icon(for app: ServerAppTransferObject) -> some View {
        let _ = store.iconGeneration

        if let account = store.account, let icon = UIImage.serverAppIcon(forAppID: app.id, serverAddress: account.server, scale: displayScale) {
            Image(uiImage: icon)
        } else {
            Image(systemName: "app.grid")
        }
    }

    ///
    /// Load one server app into the web view.
    ///
    /// The path comes from the server, and `authenticatedRequest(for:)` attaches the app password to whatever it resolves to, so it is proven to stay on the connected server first. macOS resolves the same value the same way, through the same type.
    ///
    func navigateToApp(_ app: ServerAppTransferObject) {
        guard let account = store.account else {
            return
        }

        guard let target = SameOriginURL(path: app.href, relativeTo: account.server) else {
            Self.logger.error("The path offered for server app \(app.id) does not stay on the connected server; refusing to open it")
            return
        }

        page.load(authenticatedRequest(for: target.url))
    }

    ///
    /// Build the request that loads `url`, attaching HTTP Basic authentication derived from the connected account's app password.
    ///
    /// Nextcloud accepts the app password as Basic authentication and establishes a web session from it, so the embedded web view is signed in without a second in-page login after the native one. macOS does the same thing in `WebViewController.authenticatedRequest(for:)`; both encode the header through `Credentials.basicAuthorizationValue` so they cannot encode it differently. With no account configured the request goes out unauthenticated and the server presents its normal login page.
    ///
    private func authenticatedRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)

        if let account = store.account {
            request.setValue(account.credentials.basicAuthorizationValue, forHTTPHeaderField: "Authorization")
        }

        return request
    }
}

#Preview {
    NextcloudView()
        .environment(Store(apps: [
            ServerAppTransferObject(id: "files", order: 0, href: "/apps/files/", name: "Files"),
            ServerAppTransferObject(id: "activity", order: 1, href: "/apps/activity/", name: "Activity"),
        ]))
}
