// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
@testable import Cirruscope
import Testing

/// `WebAccentColorTests` covers `WebAccentColor(resolving:)`, the color arithmetic that turns an `NSColor` into the hex string and brightness verdict Cirruscope forwards into the Nextcloud web interface.
///
/// It is pure input-to-value logic with no web view and no server involved, which is what makes it testable at all — `WebAccentColor.effective(in:)` deliberately is not covered, because the color it reads is whichever accent the machine running the tests happens to have chosen in System Settings, so a test over it would measure the developer's preferences rather than the app.
/// Two properties are worth pinning. The first is a safety invariant, not a cosmetic one: `WebViewController.appearanceAttributeScript()` interpolates `hexString` into a JavaScript string literal without escaping anything, which is only sound because the value can contain nothing but `#` and six hexadecimal digits. The second is the brightness gate, whose threshold decides whether text on a primary element is black or white — it is a port of Nextcloud's `Util::invertTextColor()`, so a case sitting one eight-bit step either side of the boundary is the only way to catch the two implementations drifting apart.
struct WebAccentColorTests {
    @Test(arguments: [
        // The two variants of the app's own AccentColor asset, pinned here so the shipped values exist somewhere executable.
        (NSColor(srgbRed: 46 / 255, green: 106 / 255, blue: 240 / 255, alpha: 1), "#2E6AF0", false),
        (NSColor(srgbRed: 90 / 255, green: 141 / 255, blue: 255 / 255, alpha: 1), "#5A8DFF", true),
        // The endpoints.
        (NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1), "#FFFFFF", true),
        (NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1), "#000000", false),
        // A component that lands exactly between two eight-bit values, pinning rounding rather than truncation: 0.5 × 255 is 127.5, and #808080 is 128.
        (NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1), "#808080", true),
        // The same color at half alpha, pinning that the alpha channel is dropped rather than blended in.
        (NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 0.5), "#808080", true),
    ])
    func `A color resolves to its sRGB hex string and brightness verdict`(color: NSColor, hexString: String, isBright: Bool) {
        let accentColor = WebAccentColor(resolving: color)

        #expect(accentColor?.hexString == hexString)
        #expect(accentColor?.isBright == isBright)
    }

    @Test(arguments: [
        // Nextcloud flips to black text once the contrast ratio against white falls below 4.5:1, which for a neutral gray happens between these two eight-bit values.
        (118, false),
        (119, true),
    ])
    func `The brightness gate flips where Nextcloud's does`(component: Int, isBright: Bool) {
        let gray = NSColor(srgbRed: CGFloat(component) / 255, green: CGFloat(component) / 255, blue: CGFloat(component) / 255, alpha: 1)

        #expect(WebAccentColor(resolving: gray)?.isBright == isBright)
    }

    @Test
    func `A wide-gamut color still resolves to a well-formed hex string`() {
        // Converting a Display P3 primary into sRGB lands outside 0…1, which would format as a malformed token if the components were not clamped first.
        // The clamped result is a color-management detail not worth freezing, so only the shape is asserted — that shape being what makes the value safe to interpolate into JavaScript.
        let accentColor = WebAccentColor(resolving: NSColor(displayP3Red: 1, green: 0, blue: 0, alpha: 1))

        #expect(accentColor?.hexString.count == 7)
        #expect(accentColor?.hexString.first == "#")
        #expect(accentColor?.hexString.dropFirst().allSatisfy(\.isHexDigit) == true)
        #expect(accentColor?.hexString.dropFirst().allSatisfy { $0.isLowercase == false } == true)
    }
}
