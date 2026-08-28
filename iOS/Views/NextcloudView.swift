import SwiftUI
import WebKit

struct NextcloudView: View {
    @Environment(Store.self)
    private var store

    @State
    private var page: WebPage

    init() {
        let configuration = WebPage.Configuration()

        if
            let url = Bundle.main.url(forResource: "Cirruscope", withExtension: "css"),
            let css = try? String(contentsOf: url, encoding: .utf8)
        {
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
            configuration.userContentController.addUserScript(script)
        }

        let page = WebPage(configuration: configuration)
        page.isInspectable = true

        _page = State(initialValue: page)
    }

    var body: some View {
        NavigationStack {
            WebView(page)
                .webViewMagnificationGestures(.disabled)
                .webViewBackForwardNavigationGestures(.disabled)
                .toolbar {
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
