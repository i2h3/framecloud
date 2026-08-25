// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Cocoa
import os

/// `DownloadViewController` presents the app's download history in a table, one row per `Download` that `DownloadManager` tracks.
///
/// It backs the single Downloads window reached from the "Downloads" menu item. It reads `DownloadManager.shared.downloads` through its `NSTableViewDataSource` conformance and reloads whenever `DownloadManager` posts `Notification.Name.downloadsDidChange`.
/// Each row's live progress is driven by `DownloadTableCellView` observing its `Download` directly, so this controller only reloads on changes to the list or a download's state, not on every byte transferred.
class DownloadViewController: NSViewController {
    /// `tableView` lists the tracked downloads; its data source is wired in the storyboard and its delegate is set in `viewDidLoad()`.
    @IBOutlet
    var tableView: NSTableView!

    /// `logger` records the download window's activity under the `DownloadViewController` category.
    private let logger = Logger(for: DownloadViewController.self)

    override func viewDidLoad() {
        super.viewDidLoad()
        logger.debug("Downloads view controller loaded")
        tableView.delegate = self
        // Derive each row's height from its cell's Auto Layout constraints rather than the storyboard's fixed
        // rowHeight (which then serves only as a scrolling estimate). Set here as well as in the storyboard so the
        // behaviour does not depend on the Interface Builder flag being honoured at load time.
        tableView.usesAutomaticRowHeights = true
        NotificationCenter.default.addObserver(self, selector: #selector(downloadsDidChange), name: .downloadsDidChange, object: nil)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        logger.debug("Downloads view controller will appear")
        tableView.reloadData()
    }

    /// `downloadsDidChange()` reloads the table when `DownloadManager` reports that the download list or a download's state changed.
    ///
    /// `DownloadManager` posts `Notification.Name.downloadsDidChange` from the main actor, so the reload runs on the main thread as `NSTableView` requires.
    @objc
    private func downloadsDidChange() {
        logger.debug("Downloads did change")
        tableView.reloadData()
    }
}
