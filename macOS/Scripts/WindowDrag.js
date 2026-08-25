// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

// Forwards primary-button mousedown events that land on Nextcloud's header,
// but not on interactive elements within it, to the `windowDrag` message
// handler so the host window can begin a drag.

(function() {
    var interactiveSelector = 'a, button, input, textarea, select, label, [role="button"], [role="link"], [contenteditable="true"], [contenteditable=""]';

    document.addEventListener('mousedown', function(event) {
        if (event.button !== 0) {
            return;
        }

        var header = document.querySelector('#header');
        if (!header || !header.contains(event.target)) {
            return;
        }

        if (event.target.closest(interactiveSelector)) {
            return;
        }

        window.webkit.messageHandlers.windowDrag.postMessage({});
    }, true);
})();
