// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `SVGGlyphFixture` is the corpus of SVG documents the icon suites parse, one per shape of real-world input the renderer was built against.
///
/// Every document here is hand-authored. Nextcloud's own app icons are licensed under the AGPL and must never be committed into this MIT-licensed repository, however convenient a regression corpus they would make — so each fixture instead reproduces one *property* measured from them: the negative-origin viewBox that twenty of them are drawn with, the `fill-rule` declared on the root and overridden on the path that two thirds of them use, the transform that normalizes one grid onto another, the `fill="none"` decoration that must not be painted.
/// They are deliberately tiny. A fixture that is hard to read cannot be checked by eye against what a test claims about it, and these are the assertions that keep the parser honest.
enum SVGGlyphFixture {
    /// `square` is the simplest possible document: one absolute path filling the whole viewBox.
    static let square = "<svg viewBox=\"0 0 10 10\"><path d=\"M0 0 H10 V10 H0 Z\" fill=\"#fff\"/></svg>"

    /// `topLeftQuadrant` paints only the top-left quarter of its viewBox, which is what makes it able to tell an upside-down render from a correct one.
    static let topLeftQuadrant = "<svg viewBox=\"0 0 10 10\"><path d=\"M0 0 H5 V5 H0 Z\" fill=\"#fff\"/></svg>"

    /// `materialSymbol` uses the negative-origin viewBox of a Material Symbols export, painting the top-left quarter of it.
    static let materialSymbol = "<svg viewBox=\"0 -960 960 960\"><path d=\"M0 -960 H480 V-480 H0 Z\" fill=\"#fff\"/></svg>"

    /// `wide` is twice as wide as it is tall, so fitting it into a square has to letterbox rather than stretch it.
    static let wide = "<svg viewBox=\"0 0 20 10\"><path d=\"M0 0 H20 V10 H0 Z\" fill=\"#fff\"/></svg>"

    /// `styled` writes its fill as a `style` declaration rather than as an attribute, as a third of Nextcloud's icons do.
    static let styled = "<svg viewBox=\"0 0 10 10\"><path d=\"M0 0 H10 V10 H0 Z\" style=\"fill:#fff\"/></svg>"

    /// `contradicting` says one thing as an attribute and another in `style`, which CSS resolves in favour of the declaration.
    static let contradicting = "<svg viewBox=\"0 0 10 10\"><path d=\"M0 0 H10 V10 H0 Z\" fill=\"none\" style=\"fill:#fff\"/></svg>"

    /// `unpainted` decorates its viewBox with a rectangle that is neither filled nor stroked, which must contribute nothing.
    static let unpainted = "<svg viewBox=\"0 0 10 10\"><rect x=\"0\" y=\"0\" width=\"10\" height=\"10\" fill=\"none\"/><path d=\"M0 0 H5 V5 H0 Z\" fill=\"#fff\"/></svg>"

    /// `inheritedNone` sets `fill="none"` on a group, which every shape inside it inherits.
    static let inheritedNone = "<svg viewBox=\"0 0 10 10\"><g fill=\"none\"><path d=\"M0 0 H10 V10 H0 Z\"/></g></svg>"

    /// `transformedGroup` places its shape through a transform on the group around it.
    static let transformedGroup = "<svg viewBox=\"0 0 10 10\"><g transform=\"translate(5 5)\"><path d=\"M0 0 H5 V5 H0 Z\" fill=\"#fff\"/></g></svg>"

    /// `hidden` marks its only shape as not displayed, which leaves the document with nothing to draw.
    static let hidden = "<svg viewBox=\"0 0 10 10\"><path d=\"M0 0 H10 V10 H0 Z\" fill=\"#fff\" display=\"none\"/></svg>"

    /// `roundedRectangle` draws a `<rect>` with corner radii rather than a path.
    static let roundedRectangle = "<svg viewBox=\"0 0 10 10\"><rect x=\"1\" y=\"1\" width=\"8\" height=\"8\" rx=\"2\" fill=\"#fff\"/></svg>"

    /// `strokedLine` paints nothing but a stroke, as one of Nextcloud's own app icons does.
    static let strokedLine = "<svg viewBox=\"0 0 10 10\"><path d=\"M0 5 H10\" fill=\"none\" stroke=\"#fff\" stroke-width=\"2\"/></svg>"

    /// `donut` is a square with a square hole wound the same way, so the two fill rules disagree about it: nonzero fills it solid, even-odd leaves the hole.
    static let donut = "<svg viewBox=\"0 0 10 10\"><path d=\"M0 0 H10 V10 H0 Z M3 3 H7 V7 H3 Z\" fill=\"#fff\" fill-rule=\"evenodd\"/></svg>"

    /// `overriddenFillRule` declares even-odd on the root and nonzero on the path, which is how two thirds of Nextcloud's app icons are written.
    static let overriddenFillRule = "<svg viewBox=\"0 0 10 10\" style=\"fill-rule:evenodd\"><path d=\"M0 0 H10 V10 H0 Z M3 3 H7 V7 H3 Z\" style=\"fill:#fff;fill-rule:nonzero\"/></svg>"

    /// `sizedWithoutViewBox` declares no viewBox, leaving its own width and height as the coordinate system.
    static let sizedWithoutViewBox = "<svg width=\"10\" height=\"10\"><path d=\"M0 0 H10 V10 H0 Z\" fill=\"#fff\"/></svg>"

    /// `signInPage` is what a Nextcloud that wants authentication answers an asset request with: HTML, under a `200`, where an icon was expected.
    static let signInPage = "<!DOCTYPE html>\n<html><head><title>Nextcloud</title></head><body>Log in</body></html>"

    /// `nonLetterCommand` names a path command with a letter that is not one, and whose uppercase form is two characters rather than one.
    ///
    /// The path data comes from a server, so a command letter is untrusted input. Building a `Character` out of `"ß".uppercased()` — which is `"SS"` — traps, which made this the one input in the grammar able to crash the app rather than lose an icon.
    static let nonLetterCommand = "<svg viewBox=\"0 0 10 10\"><path d=\"M0 0 ß5 5\" fill=\"#fff\"/></svg>"

    /// `absurdNumber` asks for a coordinate too large to be a number, which `Double` reads as an infinity.
    static let absurdNumber = "<svg viewBox=\"0 0 10 10\"><path d=\"M0 0 L1e999 1e999\" fill=\"#fff\"/></svg>"

    /// `oversizedCorners` rounds a rectangle's corners by more than the rectangle is wide.
    static let oversizedCorners = "<svg viewBox=\"0 0 10 10\"><rect x=\"0\" y=\"0\" width=\"10\" height=\"10\" rx=\"400\" ry=\"400\" fill=\"#fff\"/></svg>"

    /// `negativeStroke` asks to be outlined with a stroke of negative width.
    static let negativeStroke = "<svg viewBox=\"0 0 10 10\"><path d=\"M0 5 H10\" fill=\"none\" stroke=\"#fff\" stroke-width=\"-4\"/></svg>"

    /// `emptyDocument` is a well-formed SVG that paints nothing at all.
    static let emptyDocument = "<svg viewBox=\"0 0 10 10\"></svg>"

    /// `data(_:)` is one of these documents as the bytes a parser is handed.
    static func data(_ document: String) -> Data {
        Data(document.utf8)
    }
}
