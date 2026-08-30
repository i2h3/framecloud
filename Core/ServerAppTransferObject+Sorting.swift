// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// This extension holds the one order every list of server apps is shown in, so that no two of them can disagree about it.
extension Collection<ServerAppTransferObject> {
    /// `sortedByName()` is these apps alphabetically by localized name, with the app identifier settling a tie.
    ///
    /// `localizedStandardCompare(_:)` is the comparison rather than `<`, because `<` orders Swift strings by Unicode scalar and this list is read by a person: it files every lowercase name behind every uppercase one ("Files" ahead of "deck"), a French "Éditeur" behind "Zoom", and reads "Talk 10" as preceding "Talk 2". This is the collation Finder lists names with — case- and diacritic-insensitive and numeric-aware — in the user's own locale, which is the locale the server localized these names into.
    /// The identifier fallback is what makes the ordering total, since `sorted(by:)` promises no stability: two apps a server offers under one name would otherwise be free to swap places between two rebuilds of a list.
    /// `ServerAppTransferObject.order` — the position the server assigns — deliberately decides nothing. It arranges the web interface's own app menu, where it reads as a layout an administrator chose and the menu is right there to scan; a native menu is scanned for a name instead. See `DECISIONS.md` → "Why are the server apps listed alphabetically instead of in the server's own order?".
    func sortedByName() -> [ServerAppTransferObject] {
        sorted { one, other in
            let comparison = one.name.localizedStandardCompare(other.name)

            return comparison == .orderedSame ? one.id < other.id : comparison == .orderedAscending
        }
    }
}
