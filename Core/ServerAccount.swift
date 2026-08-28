// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// `ServerAccount` is a Nextcloud server address together with the credentials that authenticate against it — the two halves of one `Keychain` item, which files a `Credentials` value under the address it belongs to.
///
struct ServerAccount {
    /// `server` is the root address of the Nextcloud server, as the server itself reported it in the Login Flow v2 result.
    let server: URL

    /// `credentials` are the login name and app password that authenticate against `server`.
    let credentials: Credentials
}
