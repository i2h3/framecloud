// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

// Publishes the margins of the web view that the app's own interface covers —
// the device's safe area plus the height of the navigation bar floating above
// the page — onto <html> as the four --cirruscope-safe-area-* custom properties
// Cirruscope.css insets Nextcloud's content by. The web view ignores the safe
// area so that backgrounds and borders reach the bezel; these values are how the
// content inside them keeps clear of the notch, the toolbar, and the home
// indicator without any of it being hardcoded per device.
//
// Like AppearanceAttributes.js on macOS this is a function expression rather
// than a self-invoking script: NextcloudView invokes it with the measurements
// SwiftUI took, both as a document-start user script and live through
// WebPage.callJavaScript when the geometry changes.
//
// The values go on <html> for the same reason the Mac's accent color does:
// Nextcloud owns <body>'s attributes and rewrites them as themes change, so
// <html> is the one element nothing on the page competes for. Writing them there
// as an inline style also means they survive Nextcloud's single-page
// navigations, which never replace the document, so no MutationObserver is
// needed to re-assert them.
//
// The insets arrive in points and are written as CSS pixels unconverted, which
// holds because Nextcloud serves <meta name="viewport" content="width=device-
// width, initial-scale=1">: the layout viewport is then exactly as many CSS
// pixels wide as the web view is points. Deriving a scale from clientWidth
// instead would be worse than doing nothing, because at document start — when
// this runs — the viewport meta has not been applied yet and clientWidth still
// reports the 980-pixel default, which would inset the page by roughly 2.4×.

(function(top, right, bottom, left) {
    var root = document.documentElement;

    root.style.setProperty('--cirruscope-safe-area-top', top + 'px');
    root.style.setProperty('--cirruscope-safe-area-right', right + 'px');
    root.style.setProperty('--cirruscope-safe-area-bottom', bottom + 'px');
    root.style.setProperty('--cirruscope-safe-area-left', left + 'px');
})
