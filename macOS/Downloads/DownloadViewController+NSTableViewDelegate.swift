// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Cocoa

/// `DownloadViewController`'s conformance to `NSTableViewDelegate` builds each row's `DownloadTableCellView` and binds it to the corresponding `Download`.
///
/// It dequeues the storyboard's prototype cell by the column identifier, matching how `ServerAppsViewController` reuses its own prototype, and lets the cell's Auto Layout constraints drive the automatic row height.
extension DownloadViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn,
              let cell = tableView.makeView(withIdentifier: tableColumn.identifier, owner: self) as? DownloadTableCellView
        else {
            return nil
        }

        cell.configure(with: DownloadManager.shared.downloads[row])
        return cell
    }
}
