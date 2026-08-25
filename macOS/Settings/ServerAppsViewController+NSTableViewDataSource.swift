// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Cocoa

/// `ServerAppsViewController`'s conformance to `NSTableViewDataSource` reports one row per `AccountStore.serverApps` entry held in its `apps` snapshot.
extension ServerAppsViewController: NSTableViewDataSource {
    func numberOfRows(in _: NSTableView) -> Int {
        apps.count
    }
}
