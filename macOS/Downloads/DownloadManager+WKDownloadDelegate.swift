// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import os
import WebKit

/// `DownloadManager`'s conformance to `WKDownloadDelegate` drives each transfer: it picks a non-clobbering destination in the user's Downloads folder, records the outcome on the matching `Download`, and announces changes so the UI refreshes.
///
/// `DownloadManager` is explicitly `@MainActor`, so every callback runs on the main actor alongside the rest of its state, and each one posts `Notification.Name.downloadsDidChange` after mutating a `Download` so `DownloadViewController` reloads.
/// Each method carries an explicit `@objc(...)` selector: `WKDownloadDelegate` is an Objective-C protocol dispatched purely by selector, and the required destination callback must be the completion-handler form rather than `async` — under Swift 6 with main-actor default isolation the `async` witness did not register the selector WebKit probes, so WebKit found no destination method and silently abandoned every download without calling any delegate method.
/// Every method logs its entry and each outcome at debug level (identifying the transfer by its file name, since `DownloadManager` is a single shared instance) so a download's lifecycle can be reconstructed from a log capture when tracing misbehaviour.
extension DownloadManager: WKDownloadDelegate {
    @objc(download:decideDestinationUsingResponse:suggestedFilename:completionHandler:)
    func download(_ download: WKDownload, decideDestinationUsing _: URLResponse, suggestedFilename: String, completionHandler: @escaping @MainActor (URL?) -> Void) {
        logger.debug("Deciding destination for a download with suggested filename \(suggestedFilename)")

        let destination = uniqueDestination(for: suggestedFilename)

        if let model = model(for: download) {
            model.destinationURL = destination
            model.displayName = destination.lastPathComponent
        } else {
            logger.error("No tracked download matched this transfer while deciding its destination")
        }

        logger.debug("Chose destination \(destination.lastPathComponent); returning it to WebKit")
        NotificationCenter.default.post(name: .downloadsDidChange, object: nil)
        completionHandler(destination)
    }

    @objc(downloadDidFinish:)
    func downloadDidFinish(_ download: WKDownload) {
        logger.debug("Received a download-finished callback")

        guard let model = model(for: download) else {
            logger.error("No tracked download matched the finished transfer; ignoring")
            return
        }

        model.state = .finished
        model.wkDownload = nil

        logger.info("Download finished: \(model.displayName)")

        releaseReservation(for: model)
        NotificationCenter.default.post(name: .downloadsDidChange, object: nil)

        if let destinationURL = model.destinationURL {
            logger.debug("Posting a completion notification for \(model.displayName)")
            UserNotifier.shared.postDownloadFinished(filename: model.displayName, fileURL: destinationURL)
        } else {
            logger.debug("Finished download has no recorded destination; skipping the completion notification")
        }
    }

    @objc(download:didFailWithError:resumeData:)
    func download(_ download: WKDownload, didFailWithError error: any Error, resumeData _: Data?) {
        logger.debug("Received a download-failed callback: \(error.localizedDescription)")

        guard let model = model(for: download) else {
            logger.error("No tracked download matched the failed transfer; ignoring")
            return
        }

        // A user-initiated cancel surfaces here as `NSURLErrorCancelled` after `cancel(_:)` already set the state,
        // so leave an explicit cancellation untouched and only record a genuine failure.
        guard model.state != .cancelled else {
            logger.debug("Failure is the user cancellation already recorded for \(model.displayName); leaving its state unchanged")
            model.wkDownload = nil
            NotificationCenter.default.post(name: .downloadsDidChange, object: nil)
            return
        }

        model.state = .failed
        model.error = error
        logger.error("Download failed: \(model.displayName): \(error.localizedDescription)")

        releaseReservation(for: model)
        model.wkDownload = nil
        NotificationCenter.default.post(name: .downloadsDidChange, object: nil)
    }
}
