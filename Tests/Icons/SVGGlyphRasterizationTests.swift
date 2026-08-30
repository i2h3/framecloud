// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import CoreGraphics
import Foundation
import Testing

///
/// `SVGGlyphRasterizationTests` measures the CoreGraphics behaviour the icon renderer is built on, and then asserts the renderer agrees with it.
///
/// Three of its assumptions are the kind a unit test cannot settle by restating them. That `CGMutablePath.addRelativeArc(center:radius:startAngle:delta:transform:)` under a scaling transform really draws SVG's elliptical arc; that `copy(strokingWithWidth:…)` inflates an outline the way a stroke is expected to; and that the whole chain of fit, flip and fill rule puts ink where the document said. Each is measured against something independent — the geometry the shape must have — rather than against a second copy of the belief.
/// The pixel cases are the end of the pipeline and pin the most at once: a glyph painting one corner of its viewBox must come out opaque in the matching corner of the bitmap, which fails if the y flip is wrong, and a shape with a hole must keep the hole under one fill rule and lose it under the other.
///
struct SVGGlyphRasterizationTests {
    @Test
    func `Two arcs of half a turn each close a full circle`() throws {
        let path = try #require(SVGPathData.path(from: "M0 10 A10 10 0 1 0 20 10 A10 10 0 1 0 0 10"))
        let box = path.boundingBoxOfPath

        #expect(abs(box.minX) < 0.01)
        #expect(abs(box.minY) < 0.01)
        #expect(abs(box.width - 20) < 0.01)
        #expect(abs(box.height - 20) < 0.01)
    }

    @Test
    func `Radii too small to span the chord are scaled up until they fit`() throws {
        // A unit radius cannot reach across ten units, so the specification enlarges it to exactly half the chord — which
        // makes this a semicircle five deep rather than the flatter arc the numbers literally ask for.
        let path = try #require(SVGPathData.path(from: "M0 0 A1 1 0 0 1 10 0"))
        let box = path.boundingBoxOfPath

        #expect(abs(box.width - 10) < 0.01)
        #expect(abs(box.height - 5) < 0.01)
    }

    @Test
    func `The sweep flag chooses which side of the chord the arc bulges to`() throws {
        let clockwise = try #require(SVGPathData.path(from: "M0 0 A5 5 0 0 1 10 0"))
        let counterclockwise = try #require(SVGPathData.path(from: "M0 0 A5 5 0 0 0 10 0"))

        #expect(clockwise.boundingBoxOfPath.minY < 0)
        #expect(counterclockwise.boundingBoxOfPath.maxY > 0)
    }

    @Test
    func `A glyph renders to a bitmap of the requested pixel size`() throws {
        let glyph = try #require(SVGGlyph(data: SVGGlyphFixture.data(SVGGlyphFixture.square)))
        let image = try #require(SVGGlyphRasterizer.image(of: glyph, size: CGSize(width: 16, height: 16), scale: 2))

        #expect(image.width == 32)
        #expect(image.height == 32)
    }

    @Test
    func `A glyph painting one corner is opaque in that corner and clear in the opposite one`() throws {
        let glyph = try #require(SVGGlyph(data: SVGGlyphFixture.data(SVGGlyphFixture.topLeftQuadrant)))
        let image = try #require(SVGGlyphRasterizer.image(of: glyph, size: CGSize(width: 20, height: 20), scale: 1))

        #expect(try alpha(of: image, x: 5, y: 5) > 200)
        #expect(try alpha(of: image, x: 15, y: 15) < 50)
    }

    @Test
    func `A hole survives the even-odd rule and closes under the nonzero one`() throws {
        let hollow = try #require(SVGGlyph(data: SVGGlyphFixture.data(SVGGlyphFixture.donut)))
        let solid = try #require(SVGGlyph(data: SVGGlyphFixture.data(SVGGlyphFixture.overriddenFillRule)))
        let size = CGSize(width: 20, height: 20)
        let hollowImage = try #require(SVGGlyphRasterizer.image(of: hollow, size: size, scale: 1))
        let solidImage = try #require(SVGGlyphRasterizer.image(of: solid, size: size, scale: 1))

        #expect(try alpha(of: hollowImage, x: 10, y: 10) < 50)
        #expect(try alpha(of: solidImage, x: 10, y: 10) > 200)
        #expect(try alpha(of: hollowImage, x: 2, y: 2) > 200)
    }

    @Test
    func `A glyph encodes to PNG bytes`() throws {
        let glyph = try #require(SVGGlyph(data: SVGGlyphFixture.data(SVGGlyphFixture.square)))
        let data = try #require(SVGGlyphRasterizer.pngData(of: glyph, size: CGSize(width: 16, height: 16), scale: 2))

        #expect(data.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
    }

    @Test
    func `A size that is not a size yields no bitmap rather than a crash`() throws {
        let glyph = try #require(SVGGlyph(data: SVGGlyphFixture.data(SVGGlyphFixture.square)))

        // `Int(_:)` traps on a non-finite `Double`, so these have to be refused before the conversion.
        #expect(SVGGlyphRasterizer.image(of: glyph, size: CGSize(width: CGFloat.nan, height: 16), scale: 2) == nil)
        #expect(SVGGlyphRasterizer.image(of: glyph, size: CGSize(width: 16, height: CGFloat.infinity), scale: 2) == nil)
        #expect(SVGGlyphRasterizer.image(of: glyph, size: CGSize(width: 16, height: 16), scale: CGFloat.nan) == nil)
        #expect(SVGGlyphRasterizer.image(of: glyph, size: .zero, scale: 2) == nil)
        #expect(SVGGlyphRasterizer.image(of: glyph, size: CGSize(width: -16, height: -16), scale: 2) == nil)
        #expect(SVGGlyphRasterizer.image(of: glyph, size: CGSize(width: 100_000, height: 100_000), scale: 2) == nil)
    }

    /// `alpha(of:x:y:)` is the opacity of one pixel, addressed from the top-left corner of the image as it would be seen.
    private func alpha(of image: CGImage, x: Int, y: Int) throws -> UInt8 {
        let provider = try #require(image.dataProvider)
        let data = try #require(provider.data)
        let bytes = try #require(CFDataGetBytePtr(data))
        // The renderer's bitmap is RGBA with the alpha last, so the fourth byte of the pixel is the one wanted.
        let offset = y * image.bytesPerRow + x * 4 + 3

        #expect(offset < CFDataGetLength(data))

        return bytes[offset]
    }
}
