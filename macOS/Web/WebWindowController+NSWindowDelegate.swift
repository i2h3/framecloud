// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Cocoa
import os

/// `WebWindowController`'s conformance to `NSWindowDelegate` records the size of the window it hosts, so the next web window opens at that size (issue #82).
///
/// The storyboard's "Web Window" scene already connects the window's `delegate` outlet to this window controller, so both hooks below are reached without any wiring in code. Between them they cover every way a user settles on a size: dragging a resize edge, and whatever the window measures when it closes — which is also how a zoomed (green-button) size is picked up, zooming firing no live-resize notification. What they cannot cover is quitting with a window still open, `NSWindow.willCloseNotification` not being posted when the application terminates; `AppDelegate.applicationWillTerminate(_:)` records the frontmost web window for that case.
///
/// Neither hook decides anything itself. `WebWindowFrame` owns where the frame is kept and which states are worth remembering — fullscreen is not — so both callers stay one line and the rule lives in one place.
extension WebWindowController: NSWindowDelegate {
    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }

        logger.debug("Web window did end live resize")
        WebWindowFrame.record(window)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }

        logger.debug("Web window will close")
        WebWindowFrame.record(window)
    }
}
