import SwiftUI
import WebKit

struct NextcloudView: View {
    @Environment(Store.self) private var store

    @State
    private var currentAppName = ""

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
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Menu {
                            ForEach(store.apps) { app in
                                Button {
                                    navigateToApp(app)
                                } label: {
                                    Label(app.name, systemImage: app.systemImage)
                                }
                            }
                        } label: {
                            Label("Apps", systemImage: "square.grid.3x3.fill")
                        }
                    }

                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            //
                        } label: {
                            Label("UnifiedSearch", systemImage: "magnifyingglass")
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
                .navigationTitle(currentAppName)
                .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            guard page.url == nil else {
                return
            }

            page.load(URL(string: "http://localhost:56827"))
        }
    }

    func navigateToApp(_ app: ServerApp) {
        let url = URL(string: "http://localhost:56827/apps/\(app.id)/")
        page.load(url)
        currentAppName = app.name
    }
}

#Preview {
    NextcloudView()
        .environment(Store(apps: [
            ServerApp(id: "files", name: "Files", systemImage: "folder.fill"),
            ServerApp(id: "activity", name: "Activity", systemImage: "bolt.fill")
        ]))
}
