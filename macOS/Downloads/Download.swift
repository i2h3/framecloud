// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import WebKit

/// `Download` is the runtime record of a single file transfer that `DownloadManager` coordinates and `DownloadViewController` displays.
///
/// `DownloadManager` creates one from the `WKDownload` handed to it by `WebViewController+WKNavigationDelegate`, keeps it in its in-memory `downloads` list for the lifetime of the process, and mutates its `state`, `destinationURL`, and `displayName` as the transfer progresses.
/// `DownloadTableCellView` reads these properties to populate a row and observes `progress` to reflect live progress, so the model is the single source of truth shared between the coordinator and the UI.
/// It is deliberately not `Codable`: issue #23 requires download history to live only for the current run and never be persisted across launches.
@MainActor
final class Download: Identifiable {
    /// `State` enumerates the mutually exclusive phases a `Download` moves through, which `DownloadTableCellView` maps to the visibility of its stop and reveal buttons and the text it shows.
    ///
    /// A download starts `inProgress` and ends in exactly one terminal case: `finished` once `DownloadManager` receives `downloadDidFinish`, `cancelled` when the user stops it, or `failed` when the transfer errors for any other reason.
    enum State {
        /// `inProgress` is the phase while the transfer is running and its bytes are still arriving.
        case inProgress

        /// `finished` is the terminal phase once the file has been fully written to `destinationURL`.
        case finished

        /// `failed` is the terminal phase when the transfer errored, with the underlying error kept in `error`.
        case failed

        /// `cancelled` is the terminal phase after the user stopped the transfer via `DownloadManager.cancel(_:)`.
        case cancelled
    }

    /// `id` uniquely identifies the download so the model can satisfy `Identifiable`.
    let id = UUID()

    /// `progress` is the `Progress` reported by the underlying `WKDownload`, captured at creation so it stays readable after `wkDownload` is released on a terminal state.
    ///
    /// `DownloadTableCellView` binds it to its `NSProgressIndicator.observedProgress` and observes its `fractionCompleted` to update the status text.
    let progress: Progress

    /// `displayName` is the file name shown in the row.
    ///
    /// It starts from the download's originating request and is replaced with the chosen destination's last path component once `DownloadManager` picks one, so it reflects any `name (1)` suffix applied to avoid overwriting an existing file.
    var displayName: String

    /// `destinationURL` is the location in the user's Downloads folder the file is written to, or `nil` until `DownloadManager` decides it in `download(_:decideDestinationUsing:suggestedFilename:)`.
    ///
    /// `DownloadTableCellView.revealInFinder(_:)` opens Finder on it, and `DownloadManager` passes it to `UserNotifier.postDownloadFinished(filename:fileURL:)` when the transfer finishes.
    var destinationURL: URL?

    /// `state` is the download's current phase, which `DownloadManager` advances and `DownloadTableCellView` renders.
    var state: State = .inProgress

    /// `error` is the failure reported to `download(_:didFailWithError:resumeData:)`, kept for diagnostics when `state` is `failed`.
    var error: (any Error)?

    /// `wkDownload` is the underlying transfer, held strongly because `WKDownload.delegate` is `weak` and nothing else retains it once `WebViewController` hands it off.
    ///
    /// `DownloadManager` uses it to `cancel(_:)` an in-progress download and clears it on a terminal state so the transfer object is released.
    var wkDownload: WKDownload?

    /// `init(_:)` creates a record for `wkDownload`, capturing its `progress` and deriving an initial `displayName` from the request it originated from.
    ///
    /// `DownloadManager.handle(_:)` calls it before adding the record to its list and installing itself as the download's delegate.
    init(_ wkDownload: WKDownload) {
        self.wkDownload = wkDownload
        progress = wkDownload.progress
        displayName = wkDownload.originalRequest?.url?.lastPathComponent ?? "download"
    }
}
