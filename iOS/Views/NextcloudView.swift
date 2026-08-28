import os
import SwiftUI
import WebKit

struct NextcloudView: View {
    @Environment(Store.self)
    private var store

    @State
    private var page: WebPage

    ///
    /// Carries what the loaded page reports about its app-navigation toggle, which is what decides whether the toolbar control is on screen and how it renders.
    ///
    @State
    private var appNavigation: AppNavigationBridge

    ///
    /// Records this screen's activity under the `NextcloudView` category.
    ///
    /// Static because a `View` is a value rebuilt on every parent body evaluation, and one logger per screen is enough.
    ///
    private static let logger = Logger(for: NextcloudView.self)

    init() {
        let configuration = WebPage.Configuration()
        let appNavigation = AppNavigationBridge()

        // Both have to be on the configuration before the page is built: `WebPage.Configuration` is a struct the
        // page copies at initialization, so a handler or script registered afterwards would never reach it.
        configuration.userContentController.add(appNavigation, name: AppNavigationBridge.messageName)

        if let source = Script.sidebarToggleState.source {
            let script = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
            configuration.userContentController.addUserScript(script)
        }

        if let source = Script.styleSheet.source {
            let script = WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            configuration.userContentController.addUserScript(script)
        }

        let page = WebPage(configuration: configuration)
        page.isInspectable = true

        _page = State(initialValue: page)
        _appNavigation = State(initialValue: appNavigation)
    }

    var body: some View {
        NavigationStack {
            WebView(page)
                .ignoresSafeArea()
                .webViewMagnificationGestures(.disabled)
                .webViewBackForwardNavigationGestures(.disabled)
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
                                Label(app.name, systemImage: app.systemImage)
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
                .navigationTitle(page.title)
                .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            guard let account = store.account, page.url == nil else {
                return
            }

            page.load(authenticatedRequest(for: account.server))
            store.updateApps()
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

    func navigateToApp(_ app: ServerApp) {
        guard let account = store.account else {
            return
        }

        page.load(authenticatedRequest(for: account.server.appending(path: "apps/\(app.id)/")))
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
            ServerApp(id: "files", name: "Files", systemImage: "folder.fill"),
            ServerApp(id: "activity", name: "Activity", systemImage: "bolt.fill"),
        ]))
}
