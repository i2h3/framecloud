// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `Credentials` bundles the Nextcloud login name and app password obtained from a completed Login Flow v2 grant.
///
/// `Keychain` persists and retrieves values of this type, `ServerConnection.authenticated(address:)` reads them to build an authenticated `Rainmaker.Server`, and `WebViewController` reads them to sign the embedded web view in via HTTP Basic authentication.
struct Credentials: Codable {
    /// `user` is the Nextcloud login name returned as the `name` of a `Rainmaker.LoginResult`.
    ///
    /// It is sent as the user component of the HTTP Basic authentication used for both `Rainmaker.Server` requests and the embedded web view.
    let user: String

    /// `appPassword` is the device-specific app password returned as the `password` of a `Rainmaker.LoginResult`.
    ///
    /// It authenticates requests in place of the account password and can be revoked on the server without affecting the account.
    let appPassword: String

    /// `basicAuthorizationValue` is the `Authorization` header value that signs an embedded web view in with these credentials.
    ///
    /// Nextcloud accepts the app password as HTTP Basic authentication and establishes a web session from it, so the web view is signed in without a separate in-page login. `WebViewController.authenticatedRequest(for:)` on macOS and `NextcloudView` on iOS both attach it; it lives on the value rather than at either call site so the two cannot encode it differently.
    var basicAuthorizationValue: String {
        "Basic \(Data("\(user):\(appPassword)".utf8).base64EncodedString())"
    }
}
