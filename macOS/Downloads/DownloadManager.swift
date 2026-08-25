// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import os
import WebKit

/// `DownloadManager` is the app-wide facility that coordinates every file download, decoupled from the user interface as issue #23 requires.
///
/// `WebViewController+WKNavigationDelegate` hands each `WKDownload` to the `shared` instance via `handle(_:)`, which becomes the download's `WKDownloadDelegate` (see `DownloadManager+WKDownloadDelegate`) so transfers keep running even after the web window that started them closes.
/// It owns the process-lifetime `downloads` list and posts `Notification.Name.downloadsDidChange` whenever that list or a download's state changes, which `DownloadViewController` observes to refresh its table; live byte-level progress is not broadcast here but observed directly from each `Download.progress` by `DownloadTableCellView`.
/// Files are written into the user's Downloads folder, which the app can reach because of the `com.apple.security.files.downloads.read-write` entitlement.
@MainActor
final class DownloadManager: NSObject {
    /// `shared` is the process-wide coordinator, retained for the app's lifetime so it can safely serve as the `weak` delegate of every `WKDownload`.
    static let shared = DownloadManager()

    /// `logger` records download coordination under the `DownloadManager` category; it is not `private` because `DownloadManager+WKDownloadDelegate` logs the transfer callbacks from a separate file.
    let logger = Logger(for: DownloadManager.self)

    /// `downloads` is the in-memory history of downloads for the current run, newest last, exposed read-only so only the coordinator mutates it.
    ///
    /// `DownloadViewController` reads it to populate its table; it is never persisted, so relaunching the app starts with an empty list.
    private(set) var downloads: [Download] = []

    /// `reservedDestinations` holds destination URLs that `uniqueDestination(for:)` has handed to in-flight transfers but that WebKit has not yet written to disk, so two downloads picking the same suggested name in the same instant receive distinct URLs instead of colliding on one.
    ///
    /// `releaseReservation(for:)` frees a reservation when its transfer ends; once WebKit has written the file, `FileManager` existence checks alone would suffice, so this only closes the window before the file appears on disk.
    private var reservedDestinations: Set<URL> = []

    /// `handle(_:)` adopts `wkDownload`, records it, and starts coordinating it.
    ///
    /// It installs `self` as the download's delegate, wraps it in a `Download`, and appends that to `downloads`. It then posts `Notification.Name.downloadsDidChange` so `DownloadViewController` shows the new row, and `Notification.Name.downloadDidStart` so `AppDelegate` opens and fronts the Downloads window.
    func handle(_ wkDownload: WKDownload) {
        wkDownload.delegate = self

        let download = Download(wkDownload)
        downloads.append(download)

        logger.info("Handling download \(download.displayName)")
        NotificationCenter.default.post(name: .downloadsDidChange, object: nil)
        NotificationCenter.default.post(name: .downloadDidStart, object: nil)
    }

    /// `cancel(_:)` stops an in-progress `download` and marks it `cancelled`.
    ///
    /// It cancels the underlying `WKDownload` and sets the state here rather than relying on the subsequent `download(_:didFailWithError:resumeData:)` callback, so the row does not briefly flash as failed; that callback guards against overwriting this state.
    func cancel(_ download: Download) {
        logger.notice("Cancelling download \(download.displayName)")
        download.wkDownload?.cancel { _ in }
        download.state = .cancelled

        releaseReservation(for: download)
        NotificationCenter.default.post(name: .downloadsDidChange, object: nil)
    }

    /// `model(for:)` returns the `Download` that wraps `wkDownload`, matching by object identity, or `nil` if none is tracked.
    ///
    /// The `WKDownloadDelegate` callbacks use it to find the record they concern, so it must be consulted before `Download.wkDownload` is cleared on a terminal state.
    func model(for wkDownload: WKDownload) -> Download? {
        downloads.first { $0.wkDownload === wkDownload }
    }

    /// `releaseReservation(for:)` frees the destination URL that `uniqueDestination(for:)` reserved for `download` once its transfer reaches a terminal state, so a later download can reuse that name if the file was never written.
    ///
    /// It is not `private` because the terminal `WKDownloadDelegate` callbacks in `DownloadManager+WKDownloadDelegate` call it from a separate file; `Set` removal is idempotent, so releasing the same download more than once is harmless.
    func releaseReservation(for download: Download) {
        guard let destinationURL = download.destinationURL else {
            return
        }

        reservedDestinations.remove(destinationURL)
    }

    /// `uniqueDestination(for:)` returns a file URL in the user's Downloads folder for `suggestedFilename` that does not yet exist, appending a ` (1)`, ` (2)`, … suffix to the name as needed.
    ///
    /// `WKDownload` requires a destination whose file does not already exist in an existing directory, so this avoids clobbering a previous download and matches the auto-renaming a web browser performs.
    func uniqueDestination(for suggestedFilename: String) -> URL {
        let directory = URL.downloadsDirectory
        let name = suggestedFilename.isEmpty ? "download" : suggestedFilename
        let base = directory.appending(component: name)
        let ext = base.pathExtension
        let stem = base.deletingPathExtension().lastPathComponent

        var candidate = base
        var counter = 1

        // Advance past any name already on disk or reserved by another in-flight transfer, then reserve the one
        // chosen: WebKit creates the destination file asynchronously after this returns, so without the reservation
        // two downloads that pick the same suggested name in the same instant would both see it free and collide.
        while isTaken(candidate) {
            let numberedName = ext.isEmpty ? "\(stem) (\(counter))" : "\(stem) (\(counter)).\(ext)"
            candidate = directory.appending(component: numberedName)
            counter += 1
        }

        reservedDestinations.insert(candidate)
        return candidate
    }

    /// `isTaken(_:)` reports whether `url` is unavailable as a download destination — either a file already exists there or another in-flight transfer has reserved it via `uniqueDestination(for:)`.
    private func isTaken(_ url: URL) -> Bool {
        reservedDestinations.contains(url) || FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }
}
