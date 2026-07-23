// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

extension SchemaV1 {
    /// `Account` is the v1 root record for the connected Nextcloud account: server address, cached branding and version, and the apps it offers.
    ///
    /// It is a frozen copy of the `Account` model as it shipped in `1.0.0`; see `SchemaV1` for why the v1 models are nested here rather than reusing the live top-level types.
    @Model
    final class Account {
        /// `serverAddress` is the URL of the connected Nextcloud server, or `nil` while a sign-in is still in progress.
        var serverAddress: URL?

        /// `serverVersion` is the human-readable version string of the connected server.
        var serverVersion: String?

        /// `themeBackground` is the `background` value from the server's `Theming` capability: an image URL string or a hex color value.
        var themeBackground: String?

        /// `themeLogo` is the URL of the instance logo published in the server's `Theming` capability.
        var themeLogo: URL?

        /// `themeBackgroundPlain` is the `backgroundPlain` flag from the server's `Theming` capability.
        var themeBackgroundPlain: Bool?

        /// `apps` are the Nextcloud server apps offered by this account's server; deleting the account cascades to them.
        @Relationship(deleteRule: .cascade, inverse: \ServerApp.account)
        var apps: [ServerApp] = []

        init(
            serverAddress: URL? = nil,
            serverVersion: String? = nil,
            themeBackground: String? = nil,
            themeLogo: URL? = nil,
            themeBackgroundPlain: Bool? = nil
        ) {
            self.serverAddress = serverAddress
            self.serverVersion = serverVersion
            self.themeBackground = themeBackground
            self.themeLogo = themeLogo
            self.themeBackgroundPlain = themeBackgroundPlain
        }
    }
}
