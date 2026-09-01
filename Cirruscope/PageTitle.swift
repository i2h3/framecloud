// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `PageTitle` shortens the title a Nextcloud page gives itself to the part worth showing in the app's own interface.
///
/// Nextcloud composes a document title as the application's name followed by the instance's, and its single-page apps prepend whatever is open inside them, so a title reads "Files - Nextcloud" or "Ada - Talk - Nextcloud". The instance's name is the one component a native app never needs: the user is looking at one server, and the app's own chrome says which.
/// It is only ever a fallback. Where a page can be resolved to one of the server's apps, that app's own name is shorter still and is used instead — see `ServerAppTransferObject+Resolution.swift`.
enum PageTitle {
    /// `separator` is the string Nextcloud joins a title's components with.
    private static let separator = " - "

    /// `withoutSiteName(_:)` is `title` with its trailing instance-name component removed, or `title` unchanged when there is no such component to remove.
    ///
    /// Positional rather than matched against the instance's real name, because the name is not always known where this is used: it reaches macOS on the theming capability and is stored there, while iOS persists nothing and never asks. Dropping the last component instead needs nothing but the title.
    /// The cost of that is an instance whose own name contains the separator, which is then only partly removed. That is a worse title rather than a wrong one, and it is the reason this returns the input untouched whenever the result would be empty or there is only one component: a title is a label, and no rule for shortening it is worth showing the user nothing.
    static func withoutSiteName(_ title: String) -> String {
        let components = title.components(separatedBy: Self.separator)

        guard components.count >= 2 else {
            return title
        }

        let shortened = components.dropLast().joined(separator: Self.separator)

        guard shortened.isEmpty == false else {
            return title
        }

        return shortened
    }
}
