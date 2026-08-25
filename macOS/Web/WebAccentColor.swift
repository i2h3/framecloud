// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
import os

/// `WebAccentColor` is the app's effective accent color in the two forms the Nextcloud web interface needs: an sRGB hex string, and the brightness verdict behind the handful of Nextcloud values that cannot be expressed in CSS at all.
///
/// `WebViewController.appearanceAttributeScript()` builds one with `effective(in:)` and hands both members to `WebViewScript.appearanceAttributes`, which writes them onto `<html>` as the `--cirruscope-accent-color` custom property and the `data-cirruscope-accent-bright` attribute. `Cirruscope.css` re-derives Nextcloud's whole primary color family from just those two.
/// Only two members cross into the page because the arithmetic belongs in the stylesheet. Nextcloud computes its primary family in PHP and emits ten literal hex values, but its `Util::mix()` is a weighted average in gamma-encoded sRGB and its `lighten()`/`darken()` are offsets of sRGB-HSL lightness — which `color-mix(in srgb, …)` and `hsl(from … calc(l ± n))` reproduce exactly — so the derivations live next to the rest of the Nextcloud-specific CSS instead of here. `isBright` is the exception that must be resolved natively: `--primary-invert-if-bright` and `--primary-invert-if-dark` hold the keywords `invert(100%)` and `no` rather than colors, and no CSS function turns a color into a keyword. It also supplies the sign of the hover step, which Nextcloud moves away from the text color rather than consistently darker.
/// The type is deliberately not `@MainActor`. `NSColor` is `Sendable` and `NSAppearance` carries no actor isolation, so the block `effective(in:)` hands to AppKit is never inferred main-actor-isolated and the dynamic isolation check the "Concurrency" section of `AGENTS.md` warns about is not involved here at all.
struct WebAccentColor {
    /// `logger` records failures to express an accent color in sRGB under the `WebAccentColor` category.
    private static let logger = Logger(for: WebAccentColor.self)

    /// `hexString` is the color as an sRGB CSS hex string such as `#2E6AF0`.
    ///
    /// `WebViewController.appearanceAttributeScript()` interpolates it into a JavaScript string literal without escaping anything, which is safe only because this value can contain nothing but `#` followed by six uppercase hexadecimal digits. That is why the `#RRGGBB` form is chosen over `rgb()` — no quote, backslash, or semicolon can ever appear in it — and why `WebAccentColorTests` pins the shape rather than only the values.
    /// The alpha channel is discarded: a translucent primary element would let whatever Nextcloud paints behind it bleed through, which is never what forwarding an accent color means.
    let hexString: String

    /// `isBright` is `true` when black text reads better on this color than white text does.
    ///
    /// It is a port of Nextcloud's `Util::invertTextColor()` — `colorContrast($color, '#ffffff') < 4.5` over the WCAG relative luminance computed by `Util::calculateLuma()` — so the branch Cirruscope takes and the branch the server would have taken agree. `Cirruscope.css` keys the two `--primary-invert-if-*` filter keywords, the sign of `--color-primary-element-hover`'s lightness step, and the literal `--color-primary-element-text-dark` on it.
    /// It is computed from the same eight-bit components `hexString` is formatted from, not from the raw floating-point ones, so it can never disagree with the color the page actually receives.
    let isBright: Bool

    /// `init?(resolving:)` converts `color` to sRGB and derives both members from it, or fails when the color has no sRGB representation.
    ///
    /// `effective(in:)` calls it with `NSColor.controlAccentColor` while an appearance is current; the tests call it with fixed colors. Components are clamped before being scaled to eight bits because converting a wide-gamut color into sRGB can land outside `0…1`, which would otherwise format as a malformed token.
    /// Failing rather than substituting a fallback color is deliberate: it leaves the stylesheet's `data-cirruscope-accent` gate closed, so the page keeps Nextcloud's own theme color, which still looks intentional in a way a guessed color would not. Only a pattern color lacks a color space and `controlAccentColor` is a catalog color, so this is an anomaly worth retrieving from the log store later rather than an expected state.
    init?(resolving color: NSColor) {
        guard let sRGB = color.usingColorSpace(.sRGB) else {
            Self.logger.error("Could not express accent color in sRGB; the web view keeps Nextcloud's own primary color")
            return nil
        }

        let red = Self.eightBitComponent(sRGB.redComponent)
        let green = Self.eightBitComponent(sRGB.greenComponent)
        let blue = Self.eightBitComponent(sRGB.blueComponent)

        hexString = String(format: "#%02X%02X%02X", red, green, blue)
        isBright = Self.isBright(red: red, green: green, blue: blue)
    }

    /// `effective(in:)` resolves `NSColor.controlAccentColor` for `appearance`, or returns `nil` when it has no sRGB representation.
    ///
    /// `WebViewController.appearanceAttributeScript()` calls it with its own web view's `effectiveAppearance`, so the color forwarded into the page is the one the window actually draws with: the `AccentColor` asset's light or dark variant while the user's macOS accent is "Multicolor", the matching form of the chosen system accent otherwise, and the increased-contrast form when the user has enabled that.
    /// The conversion has to happen *inside* the block. A dynamic catalog color such as `controlAccentColor` resolves against `NSAppearance.currentDrawingAppearance`, so resolving it outside would silently answer for whichever appearance happened to be current. `performAsCurrentDrawingAppearance(_:)` runs its block synchronously and restores the previously current appearance afterwards, and is used in place of the `NSAppearance.currentAppearance` setter deprecated in macOS 12.
    static func effective(in appearance: NSAppearance) -> WebAccentColor? {
        var accentColor: WebAccentColor?

        appearance.performAsCurrentDrawingAppearance {
            accentColor = WebAccentColor(resolving: NSColor.controlAccentColor)
        }

        return accentColor
    }

    /// `eightBitComponent(_:)` scales one clamped sRGB color component to the `0...255` range CSS hex notation encodes.
    private static func eightBitComponent(_ component: CGFloat) -> Int {
        Int((min(max(component, 0), 1) * 255).rounded())
    }

    /// `isBright(red:green:blue:)` answers whether a color built from these eight-bit sRGB components contrasts too weakly with white for white text to be readable on it.
    ///
    /// This is Nextcloud's `Util::invertTextColor()` written out: the contrast ratio against white is `1.05 / (luminance + 0.05)`, since white's own relative luminance is `1.0`, and Nextcloud's threshold for flipping to black text is the WCAG minimum of `4.5`.
    private static func isBright(red: Int, green: Int, blue: Int) -> Bool {
        let luminance = 0.2126 * relativeLuminanceComponent(red) + 0.7152 * relativeLuminanceComponent(green) + 0.0722 * relativeLuminanceComponent(blue)
        return 1.05 / (luminance + 0.05) < 4.5
    }

    /// `relativeLuminanceComponent(_:)` linearizes one gamma-encoded eight-bit sRGB component into the value the WCAG relative-luminance sum expects.
    ///
    /// The piecewise transfer function and its `0.03928` threshold are copied from Nextcloud's `Util::calculateLuma()` rather than from the WCAG text, which rounds the same constant differently, so `isBright(red:green:blue:)` cannot disagree with the server about a color sitting on the boundary.
    private static func relativeLuminanceComponent(_ eightBitComponent: Int) -> Double {
        let component = Double(eightBitComponent) / 255

        if component <= 0.03928 {
            return component / 12.92
        }

        return pow((component + 0.055) / 1.055, 2.4)
    }
}
