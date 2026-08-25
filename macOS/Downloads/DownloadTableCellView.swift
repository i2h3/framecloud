// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Cocoa
import os
import UniformTypeIdentifiers

/// `DownloadTableCellView` is the row view `DownloadViewController` dequeues for each `Download`, showing its name, progress, and status and owning the buttons that stop or reveal it.
///
/// `DownloadViewController+NSTableViewDelegate` calls `configure(with:)` to bind a row to its `Download`; the cell then drives its `progressIndicator` from the download's `Progress` and observes that progress to keep `status` current.
/// Its stop and reveal buttons target the cell itself rather than the controller, so the cell asks `DownloadManager` to cancel the download it holds or opens Finder on the finished file.
class DownloadTableCellView: NSTableCellView {
    /// `fileName` shows the download's `displayName`, the name the file is saved under in the Downloads folder.
    @IBOutlet
    var fileName: NSTextField!

    /// `icon` shows a standard file-type icon derived from the download's file name, replacing the storyboard's design-time placeholder image.
    @IBOutlet
    var icon: NSImageView!

    /// `progressIndicator` reflects the download's `Progress`, driven from a `fractionCompleted` observation, running indeterminate until the total size is known.
    @IBOutlet
    var progressIndicator: NSProgressIndicator!

    /// `status` shows the transfer's live byte description while running and a terminal message once it finishes, fails, or is cancelled.
    @IBOutlet
    var status: NSTextField!

    /// `revealInFinder` opens Finder on the finished file and is hidden until the download has finished.
    @IBOutlet
    var revealInFinder: NSButton!

    /// `stop` cancels the transfer and is shown only while the download is in progress.
    @IBOutlet
    var stop: NSButton!

    /// `logger` records the row's user actions under the `DownloadTableCellView` category.
    private let logger = Logger(for: DownloadTableCellView.self)

    /// `download` is the model the row currently represents, retained so the button actions can act on it.
    ///
    /// `configure(with:)` sets it, and the actions read it to cancel the transfer or reveal its `destinationURL`.
    private var download: Download?

    /// `progressObservation` is the key-value observation of the current download's `fractionCompleted` that keeps `status` in sync while the transfer runs.
    ///
    /// `configure(with:)` replaces it on every bind, which invalidates the previous observation so a reused cell never keeps reporting a prior download.
    private var progressObservation: NSKeyValueObservation?

    /// `configure(with:)` binds the row to `download`, populating every subview and starting to observe its progress.
    ///
    /// `DownloadViewController+NSTableViewDelegate` calls it in `tableView(_:viewFor:row:)`; it first tears down any observation left from a previous binding so cell reuse is safe, since `NSTableCellView` has no `prepareForReuse`.
    func configure(with download: Download) {
        progressObservation = nil
        self.download = download
        logger.debug("Configuring for download of \(download.displayName)")

        fileName.stringValue = download.displayName

        // Show a standard file-type icon derived from the file name's extension — a generic document icon when the
        // extension is missing or unrecognized — replacing the storyboard's design-time placeholder image.
        let contentType = UTType(filenameExtension: (download.displayName as NSString).pathExtension) ?? .data
        icon.image = NSWorkspace.shared.icon(for: contentType)

        // The progress bar is only meaningful while the transfer runs. Hiding it also frees its layout space: it is an
        // arranged subview of a vertical NSStackView with `detachesHiddenViews`, so the name and status labels close the
        // gap where the bar was once the download finishes, fails, or is cancelled. The stop button is shown only while running.
        let isInProgress = download.state == .inProgress
        progressIndicator.isHidden = !isInProgress
        stop.isHidden = !isInProgress
        revealInFinder.isHidden = download.state != .finished

        switch download.state {
            case .inProgress:
                // The total size is unknown until the response arrives, so run indeterminate until then.
                progressIndicator.observedProgress = download.progress
                let hasKnownTotal = download.progress.totalUnitCount > 0
                progressIndicator.isIndeterminate = !hasKnownTotal

                if hasKnownTotal {
                    progressIndicator.stopAnimation(nil)
                } else {
                    progressIndicator.startAnimation(nil)
                }

                // `fractionCompleted` is reliably KVO-delivered where `localizedAdditionalDescription` is not, so
                // observe the former and read the latter, hopping to the main actor since KVO fires off it.
                // The hop is async, so by the time it runs a reused cell may have been rebound to another download,
                // or this one may have finished (its terminal status already set): guard on both so a late update
                // never writes a stale transfer description over the row's current content. Only `download`'s
                // Sendable `id` crosses into the Task — the mutable `Download` itself is read back through
                // `self.download` once inside the main actor, rather than sending the reference across the hop.
                let downloadID = download.id
                progressObservation = download.progress.observe(\.fractionCompleted, options: [.initial]) { [weak self] progress, _ in
                    let additionalDescription = progress.localizedAdditionalDescription
                    Task { @MainActor in
                        guard let self, let download = self.download, download.id == downloadID, download.state == .inProgress else {
                            return
                        }

                        self.status.stringValue = additionalDescription ?? ""
                    }
                }

            case .finished:
                progressIndicator.observedProgress = nil
                progressIndicator.stopAnimation(nil)
                status.stringValue = ByteCountFormatter.string(fromByteCount: download.progress.completedUnitCount, countStyle: .file)

            case .failed:
                progressIndicator.observedProgress = nil
                progressIndicator.stopAnimation(nil)
                status.stringValue = download.error?.localizedDescription ?? String(localized: "Download failed.", comment: "Status label shown when a download fails without a specific error description.")

            case .cancelled:
                progressIndicator.observedProgress = nil
                progressIndicator.stopAnimation(nil)
                status.stringValue = String(localized: "Cancelled", comment: "Status label for a download the user cancelled.")
        }
    }

    @IBAction
    func revealInFinder(_: Any) {
        guard let destinationURL = download?.destinationURL else {
            return
        }

        logger.debug("Revealing finished download in Finder")
        NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
    }

    @IBAction
    func stop(_: Any) {
        guard let download else {
            return
        }

        logger.debug("Stopping download of \(download.displayName)")
        DownloadManager.shared.cancel(download)
    }
}
