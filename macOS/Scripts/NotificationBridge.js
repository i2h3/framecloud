// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

// Overrides the web Notification API so notifications created by the Nextcloud web interface are
// forwarded to the native app, which presents them in the macOS Notification Center. WKWebView does
// not implement the Notification API, so without this override the web interface's notifications are
// lost silently.
//
// Each notification is kept in a registry keyed by an id that is also sent to the native side. When
// the user clicks the notification in the Notification Center, the app calls
// window.__cirruscopeActivateNotification(id), which runs the page's own click handler — so whatever
// the web interface does on click (typically navigating to the notification's target) happens, just
// as it would for a native web notification.
//
// Injected at document start so the replacement is in place before the page's own scripts read the API.

(function() {
    var counter = 0;
    var registry = {};

    function CirruscopeNotification(title, options) {
        options = options || {};

        var id = "cirruscope-" + (++counter);

        this.title = title || "";
        this.body = options.body || "";
        this.tag = options.tag || "";
        this.icon = options.icon || "";
        this.data = options.data;
        this.onclick = null;
        this.onclose = null;
        this.onerror = null;
        this.onshow = null;
        this._id = id;
        this._listeners = {};

        registry[id] = this;

        try {
            window.webkit.messageHandlers.notification.postMessage({
                id: id,
                title: String(this.title),
                body: String(this.body),
                tag: String(this.tag)
            });
        } catch (error) {
            // The native message handler is unavailable; drop the notification silently.
        }
    }

    CirruscopeNotification.permission = "granted";
    CirruscopeNotification.maxActions = 0;

    CirruscopeNotification.requestPermission = function(callback) {
        if (typeof callback === "function") {
            callback("granted");
        }

        return Promise.resolve("granted");
    };

    CirruscopeNotification.prototype.close = function() {
        delete registry[this._id];
    };

    CirruscopeNotification.prototype.addEventListener = function(type, handler) {
        (this._listeners[type] = this._listeners[type] || []).push(handler);
    };

    CirruscopeNotification.prototype.removeEventListener = function(type, handler) {
        var handlers = this._listeners[type];
        if (!handlers) {
            return;
        }

        var index = handlers.indexOf(handler);
        if (index !== -1) {
            handlers.splice(index, 1);
        }
    };

    CirruscopeNotification.prototype.dispatchEvent = function(event) {
        var handlers = (this._listeners[event.type] || []).slice();
        for (var i = 0; i < handlers.length; i++) {
            handlers[i].call(this, event);
        }

        var handler = this["on" + event.type];
        if (typeof handler === "function") {
            handler.call(this, event);
        }

        return true;
    };

    // Invoked from native code when the user clicks the notification in the Notification Center.
    window.__cirruscopeActivateNotification = function(id) {
        var notification = registry[id];
        if (!notification) {
            return;
        }

        try {
            window.focus();
        } catch (error) {
            // Ignore; the native side already brings the window forward.
        }

        notification.dispatchEvent(new Event("click"));
    };

    try {
        Object.defineProperty(window, "Notification", {
            configurable: true,
            writable: true,
            value: CirruscopeNotification
        });
    } catch (error) {
        window.Notification = CirruscopeNotification;
    }
})();
