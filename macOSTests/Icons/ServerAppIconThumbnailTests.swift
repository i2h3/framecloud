// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
@testable import Cirruscope
import CoreGraphics
import Foundation
import Testing

///
/// `ServerAppIconThumbnailTests` covers the artwork donated to Spotlight and the Shortcuts app: a small white window with three traffic lights and the app's glyph in its body.
///
/// The bug this artwork exists to fix was invisible to every test the project had, because it was not about geometry — the glyph was drawn perfectly and simply could not be seen, being black on a dark background. So what is asserted here is colour and opacity rather than shape: that the plate is opaque, that the glyph contrasts with it, and that the traffic lights are there. Any of those quietly reverting would put the icons back where they started.
/// It is a macOS suite rather than a shared one because the artwork reaches into AppKit twice — for the secondary label colour and to encode the result — and because resolving that colour in the wrong appearance is one of the ways this can go wrong.
///
@MainActor
struct ServerAppIconThumbnailTests {
    ///
    /// A glyph filling its whole viewBox, so that the body of the window is covered by ink wherever the artwork puts it.
    ///
    private static func glyph() -> SVGGlyph? {
        SVGGlyph(data: SVGGlyphFixture.data(SVGGlyphFixture.square))
    }

    ///
    /// Reads back one pixel of a PNG, addressed from the top-left corner as it would be seen.
    ///
    private func pixel(of data: Data, x: Int, y: Int) throws -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        let representation = try #require(NSBitmapImageRep(data: data))
        let color = try #require(representation.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
        let component = { (value: CGFloat) in UInt8((value * 255).rounded()) }

        return (component(color.redComponent), component(color.greenComponent), component(color.blueComponent), component(color.alphaComponent))
    }

    @Test
    func `The thumbnail is a PNG of the expected size`() throws {
        let glyph = try #require(Self.glyph())
        let data = try #require(ServerAppIconThumbnail.pngData(drawing: glyph))
        let representation = try #require(NSBitmapImageRep(data: data))

        #expect(data.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        #expect(representation.pixelsWide == Int(ServerAppIconThumbnail.size * 2))
        #expect(representation.pixelsHigh == Int(ServerAppIconThumbnail.size * 2))
    }

    @Test
    func `The window body is opaque and white`() throws {
        let glyph = try #require(Self.glyph())
        let data = try #require(ServerAppIconThumbnail.pngData(drawing: glyph))
        let edge = Int(ServerAppIconThumbnail.size * 2)
        // Just inside the plate's right edge, clear of both the traffic lights and the glyph.
        let body = try pixel(of: data, x: edge - Int(Double(edge) * 0.12), y: edge / 2)

        // Opacity is the property that fixed the original bug: a plate that lets the background through
        // hands the decision about whether the icon can be seen back to whatever is behind it.
        #expect(body.alpha == 255)
        #expect(body.red > 240 && body.green > 240 && body.blue > 240)
    }

    @Test
    func `The glyph reads as grey against the white body`() throws {
        let glyph = try #require(Self.glyph())
        let data = try #require(ServerAppIconThumbnail.pngData(drawing: glyph))
        let edge = Int(ServerAppIconThumbnail.size * 2)
        let ink = try pixel(of: data, x: edge / 2, y: Int(Double(edge) * 0.62))

        // The secondary label colour on white: clearly darker than the plate, and clearly not black.
        // Both bounds matter — the upper one is the contrast that was missing, the lower one is what
        // keeps this from silently becoming the bare black glyph again.
        #expect(ink.red < 200)
        #expect(ink.red > 60)
    }

    @Test
    func `The three traffic lights are there and are the right colours`() throws {
        let glyph = try #require(Self.glyph())
        let data = try #require(ServerAppIconThumbnail.pngData(drawing: glyph))
        let edge = Double(ServerAppIconThumbnail.size * 2)
        let plate = CGRect(x: edge * 0.07, y: edge * 0.07, width: edge * 0.86, height: edge * 0.86)
        let diameter = plate.width * 0.095
        // Mirrored into top-left-origin coordinates, since that is how the pixels are addressed.
        let row = Int(edge - (plate.maxY - plate.height * 0.145))
        let centers = (0 ..< 3).map { Int(plate.minX + plate.width * 0.11 + Double($0) * diameter * 1.65 + diameter / 2) }

        let close = try pixel(of: data, x: centers[0], y: row)
        let minimize = try pixel(of: data, x: centers[1], y: row)
        let zoom = try pixel(of: data, x: centers[2], y: row)

        #expect(close.red > 200 && close.green < 120 && close.blue < 120)
        #expect(minimize.red > 200 && minimize.green > 150 && minimize.blue < 120)
        #expect(zoom.green > 150 && zoom.red < 150)
    }

    @Test
    func `The bitmap's own corner is clear, so the plate is rounded and inset`() throws {
        let glyph = try #require(Self.glyph())
        let data = try #require(ServerAppIconThumbnail.pngData(drawing: glyph))

        // The corner sits outside the plate entirely; only the shadow reaches it, faintly.
        #expect(try pixel(of: data, x: 0, y: 0).alpha < 40)
    }
}
