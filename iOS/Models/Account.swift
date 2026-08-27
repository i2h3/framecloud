import Foundation

///
/// Represents a configured user account in this app.
///
struct Account {
    ///
    /// The root address of the Nextcloud server it is connected to.
    ///
    let host: URL

    ///
    /// The user name to log in with.
    ///
    let name: String

    ///
    /// The locally stored app password for this client app.
    ///
    let password: String
}
