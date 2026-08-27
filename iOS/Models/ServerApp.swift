///
/// Represents a Nextcloud server app.
///
struct ServerApp: Identifiable {
    ///
    /// The technical unique identifier of the Nextcloud server app.
    ///
    let id: String

    ///
    /// The user facing label content.
    ///
    let name: String

    ///
    /// The SF Symbols name to use.
    ///
    let systemImage: String
}
