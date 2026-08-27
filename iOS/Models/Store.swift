

import Rainmaker
import SwiftUI

///
/// Global iOS app state object.
///
@Observable
@MainActor
class Store {
    ///
    /// Whether an account with valid credentials is configured.
    ///
    var account: Account?

    ///
    /// Nextcloud server apps.
    ///
    /// Not persisted. Initially populated on launch by a server response. Occassionally refreshed.
    ///
    var apps: [ServerApp]

    ///
    /// Rainmaker server to interact with the Nextcloud server.
    ///
    var server: Server?

    init(account: Account? = nil, apps: [ServerApp] = []) {
        if let account {
            self.account = account
            server = Server(address: account.host, password: account.password, user: account.name)
        } else {
            server = nil
            // TODO: Check for locally stored credentials and construct an Account from that and fall back to nil otherwise.
        }

        self.apps = apps
    }

    ///
    /// Update the list of available Nextcloud server apps.
    ///
    func updateApps() {
        guard let server else {
            return
        }

        Task {
            let navigationItems = try await server.navigation()

            let apps = navigationItems.map { navigationItem in
                ServerApp(id: navigationItem.app, name: navigationItem.name, systemImage: "app.grid")
            }

            Task { @MainActor in
                self.apps = apps
            }
        }
    }

    ///
    /// Log out the current user from the connected server.
    ///
    func logout() {
        // TODO: Revoke locally stored app password on server
        // TODO: Remove locally stored credentials from keychain

        account = nil
    }
}
