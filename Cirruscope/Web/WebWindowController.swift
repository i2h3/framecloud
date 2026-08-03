// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Cocoa
import os

/// `WebWindowController` is the window controller for the storyboard "Web Window" scene, carrying the URL its `WebViewController` should load.
///
/// `AppDelegate.presentWebViewWindow(targetURL:)` instantiates it and sets `targetURL` (the URL of a specific server app, or `nil` for the server root) before presenting it; the hosted `WebViewController` reads `targetURL` back from its window controller when it first appears.
class WebWindowController: NSWindowController {
    /// `targetURL` is the URL the hosted `WebViewController` should load, or `nil` to load `AccountStore.serverAddress`.
    ///
    /// `AppDelegate.presentWebViewWindow(targetURL:)` sets it before the window is shown; `WebViewController.startInitialLoadIfNeeded()` reads it when the view first appears.
    var targetURL: URL?

    /// `logger` records this window controller's activity under the `WebWindowController` category.
    ///
    /// It is not `private` so this controller's `NSWindowDelegate` conformance in `WebWindowController+NSWindowDelegate.swift` logs through the same one.
    let logger = Logger(for: WebWindowController.self)

    override func windowDidLoad() {
        super.windowDidLoad()
        logger.debug("Did load")

        // Opt the window into AppKit state restoration; `AppDelegate` recreates it on relaunch and `WebWindow`
        // encodes which page it shows. The per-window identifier is assigned by whoever creates the window.
        window?.isRestorable = true
        window?.restorationClass = AppDelegate.self
    }
}
