// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
import os
import WebKit

/// `WebViewController`'s conformance to `WKUIDelegate` handles the web interface's requests that need native UI.
///
/// It grants camera and microphone capture to the configured Nextcloud server without an extra web-view prompt, presents an open panel so the web interface can upload files, and redirects new-window requests into the existing web view. WKWebView shows no file chooser of its own, so without `runOpenPanelWith` an "Upload" action in Nextcloud does nothing; and it would prompt per-site for camera/microphone on top of the one-time macOS system permission. Because the web view only ever loads the trusted server the user signed in to — `WebViewController+WKNavigationDelegate` hands any other host to the system browser — media capture for that origin is granted automatically; any other origin falls back to the default prompt.
/// Nextcloud opens some actions, including certain downloads, in a new window — as does `target="_blank"`, `window.open()`, and the system context menu's "Open Link in New Window" — and WKWebView drops those unless a second web view is returned, so `createWebViewWith` instead presents a genuine new Cirruscope window for a same-host destination, or hands an external-host one to the system browser, mirroring the host check `WebViewController+WKNavigationDelegate` already applies to ordinary navigation.
/// Every method here logs its entry and each outcome at debug level so the behaviour of a specific window — identified by the appended `logID` — can be reconstructed from a log capture when tracing misbehaviour.
extension WebViewController: WKUIDelegate {
    func webView(_: WKWebView, decideMediaCapturePermissionsFor origin: WKSecurityOrigin, initiatedBy _: WKFrameInfo, type _: WKMediaCaptureType) async -> WKPermissionDecision {
        logger.debug("Deciding media capture permission for origin \(origin.host) (WebViewController \(self.logID))")

        guard let serverHost = AccountStore.shared.serverAddress?.host, origin.host.caseInsensitiveCompare(serverHost) == .orderedSame else {
            logger.debug("Origin is not the configured server; returning .prompt (WebViewController \(self.logID))")
            return .prompt
        }

        logger.debug("Origin is the configured server; granting media capture (WebViewController \(self.logID))")
        return .grant
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame _: WKFrameInfo) async -> [URL]? {
        logger.debug("Presenting file open panel (multiple selection: \(parameters.allowsMultipleSelection), directories: \(parameters.allowsDirectories)) (WebViewController \(self.logID))")

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canCreateDirectories = false

        let response: NSApplication.ModalResponse

        if let window = webView.window {
            response = await panel.beginSheetModal(for: window)
        } else {
            logger.debug("No host window; running the open panel modally (WebViewController \(self.logID))")
            response = panel.runModal()
        }

        guard response == .OK else {
            logger.debug("File open panel was cancelled; returning nil (WebViewController \(self.logID))")
            return nil
        }

        logger.debug("File open panel returned \(panel.urls.count) file(s) (WebViewController \(self.logID))")
        return panel.urls
    }

    func webView(_: WKWebView, createWebViewWith _: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures _: WKWindowFeatures) -> WKWebView? {
        logger.debug("Handling new-window request for \(navigationAction.request.url?.absoluteString ?? "no URL") (WebViewController \(self.logID))")

        guard navigationAction.targetFrame == nil else {
            logger.debug("New-window request already has a target frame; leaving it to that frame (WebViewController \(self.logID))")
            return nil
        }

        guard let url = navigationAction.request.url else {
            logger.debug("New-window request has no URL; ignoring (WebViewController \(self.logID))")
            return nil
        }

        if let host = url.host,
           let serverHost = AccountStore.shared.serverAddress?.host,
           host.caseInsensitiveCompare(serverHost) != .orderedSame
        {
            logger.debug("New-window request targets external host \(host); opening it in the system browser (WebViewController \(self.logID))")
            NSWorkspace.shared.open(url)
        } else {
            logger.debug("New-window request stays on the configured server or has no comparable host; presenting a new web view window (WebViewController \(self.logID))")
            (NSApp.delegate as? AppDelegate)?.presentWebViewWindow(targetURL: url)
        }

        return nil
    }
}
