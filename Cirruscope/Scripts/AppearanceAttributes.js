// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

// Mirrors the account's appearance settings and the app's effective accent color
// onto <html>: the two settings as the data attributes Cirruscope.css scopes its
// translucency and full-width rules to, and the accent color as the
// --cirruscope-accent-color custom property the stylesheet re-derives Nextcloud's
// whole primary color family from. Unlike the other bundled scripts this is a
// function expression rather than a self-invoking script: WebViewController
// invokes it with the current values — both as a document-start user script and
// live via evaluateJavaScript when a setting, the macOS appearance, or the
// accent-color preference changes — so the values are baked in at injection time.
//
// data-cirruscope-accent is what the stylesheet gates its accent rules on, rather
// than the presence of the custom property, which CSS cannot test for: a var()
// reference to an unset custom property is invalid at computed-value time, so
// --color-primary-element would compute to nothing at all and every primary button
// on the page would lose its color instead of keeping Nextcloud's own. accentColor
// is null when Swift could not express the color in sRGB, and the attribute then
// reads "false" so the server's theme stays untouched.
//
// The attributes go on <html> deliberately. Nextcloud puts its own data-theme-*
// attributes on <body> and rewrites them as the user switches themes, so <html> is
// the one element in the document nothing on the page competes for.

(function(translucency, fullWidth, accentColor, accentIsBright) {
    var root = document.documentElement;
    root.setAttribute('data-cirruscope-translucency', translucency);
    root.setAttribute('data-cirruscope-full-width', fullWidth);
    root.setAttribute('data-cirruscope-accent', accentColor ? 'true' : 'false');
    root.setAttribute('data-cirruscope-accent-bright', accentIsBright);

    if (accentColor) {
        root.style.setProperty('--cirruscope-accent-color', accentColor);
    } else {
        root.style.removeProperty('--cirruscope-accent-color');
    }
})
