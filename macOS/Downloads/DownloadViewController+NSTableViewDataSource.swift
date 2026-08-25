// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Cocoa

/// `DownloadViewController`'s conformance to `NSTableViewDataSource` reports one row per download `DownloadManager` currently tracks.
extension DownloadViewController: NSTableViewDataSource {
    func numberOfRows(in _: NSTableView) -> Int {
        DownloadManager.shared.downloads.count
    }
}
