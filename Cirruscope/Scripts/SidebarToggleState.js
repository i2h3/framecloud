// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

// Reports whether Nextcloud's sidebar toggle is present and expanded through
// the `sidebarToggleState` message handler, both once on injection and on every
// subsequent DOM mutation that could change either value.

(function() {
    function reportState() {
        var element = document.querySelector('.app-navigation-toggle');
        var available = !!element;
        var expanded = available && element.getAttribute('aria-expanded') === 'true';
        window.webkit.messageHandlers.sidebarToggleState.postMessage({
            available: available,
            expanded: expanded
        });
    }

    reportState();

    var observer = new MutationObserver(function() {
        reportState();
    });

    observer.observe(document.documentElement, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ['aria-expanded', 'class']
    });
})();
