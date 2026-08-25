// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
import os

/// `WebWindowFrame` remembers how large the user last made a web window, so the next one opens at that size instead of the fixed one the storyboard declares.
///
/// The storyboard's "Web Window" scene carries a fixed 1200 × 800 content rect, and AppKit's own state restoration does not stand in for remembering a size: it restores the windows that were open at quit, which macOS skips entirely while "Close windows when quitting an application" is enabled, and it says nothing at all about a window created during a session. `WebWindowController+NSWindowDelegate` records a frame whenever the user finishes resizing a window and when a window closes, `AppDelegate.applicationWillTerminate(_:)` records the frontmost one at quit, and `AppDelegate.presentWebViewWindow(targetURL:)` applies the remembered size to every new window.
///
/// Persistence is AppKit's own frame-name mechanism — `NSWindow.saveFrame(usingName:)` and `setFrameUsingName(_:)`, which keep the frame in `UserDefaults.standard` under `NSWindow Frame <name>` and adjust it for a changed screen configuration on the way back out. `setFrameAutosaveName(_:)` is deliberately *not* used: it refuses a name another live window already claimed, so with several web windows open only the first would ever autosave. The `UserDefaults` domain is the standard one rather than the shared App Group suite, because a window's size is this app's own window chrome — nothing an extension would read — and reaching the App Group container needs an entitlement an ad-hoc build cannot carry (see AGENTS.md → "Building and Signing").
///
/// Only the *size* is ever applied. `AppDelegate.present(windowController:sender:)` owns where a window goes, cascading each one off `lastCascadePoint`, and a remembered absolute position would compete with that.
enum WebWindowFrame {
    /// `logger` records this facility's activity under the `WebWindowFrame` category.
    private static let logger = Logger(for: WebWindowFrame.self)

    /// `defaultName` is the AppKit frame name every web window shares, and therefore the one remembered size they all open at.
    ///
    /// It is shared rather than per server app on purpose; see DECISIONS.md → "Why do all web windows share one remembered size?".
    static let defaultName = "WebWindow"

    /// `isRecordable(styleMask:)` reports whether a window carrying `styleMask` has a frame worth remembering, which is every state but fullscreen.
    ///
    /// A fullscreen window's `frame` is its screen's, so recording it would have the next window open screen-sized — and non-fullscreen at that, since the remembered size is applied to an ordinary window. `WebWindow.repositionControlButtons()` steps aside in fullscreen for the same reason of it not being the window's own geometry.
    ///
    /// This is the window's own, native fullscreen — the green button or View ▸ Enter Full Screen — and not the element fullscreen a page's own button triggers. WebKit answers the latter by moving the web view into a fullscreen window of its own (see DECISIONS.md → "Why does a page's full screen button put the web view into WebKit's own window rather than the app's?"), which leaves `WebWindow` behind at its ordinary frame and its style mask untouched. That frame is the user's own, so it stays worth remembering.
    static func isRecordable(styleMask: NSWindow.StyleMask) -> Bool {
        styleMask.contains(.fullScreen) == false
    }

    /// `record(_:name:)` remembers `window`'s frame under `name`, unless the window is in fullscreen.
    ///
    /// `WebWindowController`'s `NSWindowDelegate` conformance calls it when a live resize ends and when the window closes, and `AppDelegate.applicationWillTerminate(_:)` calls it for the frontmost web window — `NSWindow.willCloseNotification` is not posted when the application terminates, so without that last caller a size the user reached by zooming rather than dragging would be lost on quit.
    static func record(_ window: NSWindow, name: String = defaultName) {
        guard isRecordable(styleMask: window.styleMask) else {
            logger.debug("Not recording the frame of a fullscreen web window")
            return
        }

        window.saveFrame(usingName: name)
        logger.debug("Recorded web window size \(Int(window.frame.width)) × \(Int(window.frame.height))")
    }

    /// `applySize(to:name:)` resizes `window` to the size remembered under `name`, leaving it exactly where it already is, and does nothing when no size has been remembered yet.
    ///
    /// `AppDelegate.presentWebViewWindow(targetURL:)` calls it on every web window it creates, before handing the window to `present(windowController:sender:)` to be cascaded — which offsets the origin and keeps the size this applied. The restoration path in `AppDelegate+NSWindowRestoration` deliberately does not call it: AppKit assigns a restored window its own saved frame.
    ///
    /// The origin is captured and put back because `setFrameUsingName(_:)` applies the whole remembered frame, position included, and may even land the window on a different screen. Restoring it afterwards reduces the call to its size alone. The size itself needs no clamping of its own: `NSWindow` constrains a frame against the window's minimum and maximum size — the storyboard declares a 600 × 400 minimum — and against the screen.
    static func applySize(to window: NSWindow, name: String = defaultName) {
        let origin = window.frame.origin

        guard window.setFrameUsingName(name) else {
            logger.debug("No web window size remembered yet; leaving the new window at its storyboard size")
            return
        }

        window.setFrameOrigin(origin)
        logger.debug("Applied remembered web window size \(Int(window.frame.width)) × \(Int(window.frame.height))")
    }
}
