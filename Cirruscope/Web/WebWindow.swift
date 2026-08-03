// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit

/// `WebWindow` is the window of the storyboard "Web Window" scene that hosts `WebViewController`.
///
/// It keeps the standard close, miniaturize, and zoom buttons aligned with Cirruscope's custom title bar. AppKit returns those buttons to their default position on every layout pass, so `WebWindow` repositions them again at the end of the same pass — synchronously, so they are never displayed at the default position and do not visibly jump.
class WebWindow: NSWindow {
    /// `toolbarHeight` is the height of Cirruscope's custom title bar that the window buttons are vertically centered within.
    private static let toolbarHeight: CGFloat = 50

    /// `leadingInset` is the distance from the window's leading edge to the first window button.
    private static let leadingInset: CGFloat = 20

    /// `buttonSpacing` is the horizontal distance between the leading edges of adjacent window buttons.
    private static let buttonSpacing: CGFloat = 23

    /// `restorableStateURLKey` is the coder key under which the displayed page URL is stored for window restoration.
    ///
    /// `encodeRestorableState(with:)` writes it; `AppDelegate.restoreWindow(withIdentifier:state:completionHandler:)` reads it back.
    static let restorableStateURLKey = "url"

    override func encodeRestorableState(with coder: NSCoder) {
        super.encodeRestorableState(with: coder)

        // Persist the page the window currently shows so a relaunch can reopen it there. The window itself is the
        // restorable participant, so it (not the view controller) encodes the state AppKit hands to the restoration class.
        if let url = (contentViewController as? WebViewController)?.restorableURL {
            coder.encode(url as NSURL, forKey: Self.restorableStateURLKey)
        }
    }

    /// `performKeyEquivalent(with:)` claims ⌃⌘S — Cirruscope's own "Show/Hide Sidebar" shortcut — before the event ever reaches the hosted `WKWebView`.
    ///
    /// `-[NSWindow performKeyEquivalent:]`'s default implementation asks the content view hierarchy — which includes the web view — before it ever falls back to the menu bar, and a `WKWebView` can itself claim a command-key event by forwarding it to the loaded page's JavaScript, which may call `preventDefault()` for its own purposes. Nextcloud Talk does exactly that for ⌃⌘S (issue #59): its own keyboard handling — almost certainly a `event.ctrlKey || event.metaKey` check meant to unify Mac and Windows/Linux shortcuts under one condition, which also fires when *both* are held together on Mac — swallows the event and triggers an unrelated, broken "export" download instead ("undefined.html"), and the "Show/Hide Sidebar" menu item, despite being enabled, never even gets asked. Intercepting the shortcut here, ahead of the content view hierarchy, guarantees Cirruscope's own action always wins regardless of what any loaded page's script does with the keystroke.
    ///
    /// This covers the shortcut only while this window is the one AppKit offers the event to, which it is not while the page is in element fullscreen: the key window then belongs to WebKit rather than to the app. `WebViewScript.sidebarShortcut` claims the keystroke from inside the page for that case, and both halves agree on which keystroke it is — this one through `WebViewController.isSidebarToggleShortcut(_:)`, the script through the same modifier set spelled out in JavaScript.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if WebViewController.isSidebarToggleShortcut(event),
           let webViewController = contentViewController as? WebViewController
        {
            webViewController.toggleSidebar(nil)
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        repositionControlButtons()
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        repositionControlButtons()
    }

    /// `repositionControlButtons()` moves the close, miniaturize, and zoom buttons to align with the custom title bar, leaving them untouched while they are not yet available or while the window is in fullscreen.
    ///
    /// In fullscreen macOS relocates the window buttons into the auto-revealing title bar; the custom placement is skipped there so the buttons stay reachable in that title bar (including the green button used to leave fullscreen) instead of being pulled into the hidden content area.
    private func repositionControlButtons() {
        guard styleMask.contains(.fullScreen) == false else {
            return
        }

        let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

        for (index, type) in buttonTypes.enumerated() {
            guard let button = standardWindowButton(type),
                  let superview = button.superview
            else {
                continue
            }

            let buttonHeight = button.bounds.height
            let topInset = (Self.toolbarHeight - buttonHeight) / 2
            let leading = Self.leadingInset + CGFloat(index) * Self.buttonSpacing

            let originInWindow = NSPoint(x: leading, y: frame.height - topInset - buttonHeight)

            button.setFrameOrigin(superview.convert(originInWindow, from: nil))
        }
    }
}
