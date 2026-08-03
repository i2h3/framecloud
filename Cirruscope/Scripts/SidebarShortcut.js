// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

// Claims ⌃⌘S — Cirruscope's "Show/Hide Sidebar" shortcut — inside the page and
// reports it through the `sidebarShortcut` message handler, for every case in
// which the host window never gets offered the keystroke at all.
//
// `WebWindow.performKeyEquivalent(with:)` claims the shortcut natively while the
// app's own window is the key window, and the page then never sees the event. In
// element fullscreen it is not: WebKit moves the web view into a window of its
// own, so no `WebWindow` is asked, the "Show/Hide Sidebar" menu item is disabled
// because the responder chain there does not reach `WebViewController` either,
// and Nextcloud Talk's own keyboard handling swallows ⌃⌘S and starts a bogus
// "undefined.html" download instead (issue #59).
//
// The listener is registered on `window` in the capture phase at document start,
// before the page's own scripts attach theirs, so it is offered the event first;
// `stopImmediatePropagation()` then keeps it from reaching them at all, and
// `preventDefault()` keeps the page from acting on it by default.

(function() {
    window.addEventListener('keydown', function(event) {
        if (!event.key || event.key.toLowerCase() !== 's') {
            return;
        }

        // The native check in WebViewController.isSidebarToggleShortcut(_:) requires exactly Control and
        // Command, so Option and Shift are excluded here as well, and the two agree on the keystroke.
        if (!event.ctrlKey || !event.metaKey || event.altKey || event.shiftKey) {
            return;
        }

        event.preventDefault();
        event.stopImmediatePropagation();
        window.webkit.messageHandlers.sidebarShortcut.postMessage({});
    }, true);
})();
