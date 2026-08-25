// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Cocoa

/// `ServerAppsViewController`'s conformance to `NSTableViewDelegate` builds each row's views: the app name in the first column and a `ShortcutRecorderView` bound to the app's shortcut in `AccountStore` in the second, including the lookup that keeps the row from recording a combination another app already uses.
extension ServerAppsViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn,
              let columnIndex = tableView.tableColumns.firstIndex(of: tableColumn)
        else {
            return nil
        }

        let app = apps[row]

        switch columnIndex {
            case 0:
                // The first column shows the app name in the storyboard's prototype cell view, falling
                // back to a plain label if no prototype is registered for the column.
                let cell = tableView.makeView(withIdentifier: tableColumn.identifier, owner: self) as? NSTableCellView
                cell?.textField?.stringValue = app.name
                return cell ?? NSTextField(labelWithString: app.name)

            case 1:
                let recorder = ShortcutRecorderView(frame: .zero)
                recorder.shortcut = AccountStore.shared.shortcut(forAppID: app.id)

                recorder.onChange = { shortcut in
                    AccountStore.shared.setShortcut(shortcut, forAppID: app.id)
                }

                // Only this controller knows which app the row stands for, so it is what turns the recorder's
                // "is this combination occupied?" question into a lookup excluding the row's own app.
                recorder.conflictingAppName = { shortcut in
                    AccountStore.shared.nameOfApp(usingShortcut: shortcut, otherThanAppID: app.id)
                }

                return recorder

            default:
                return nil
        }
    }
}
