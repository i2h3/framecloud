// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import CoreGraphics
import Foundation
import Testing

///
/// `SVGGlyphTests` covers reading a whole SVG document — `SVGDocumentParser` and the `SVGGlyph` it produces — and the geometry that places one inside a rectangle.
///
/// Two properties carry most of the weight. Painting is inherited, so whether a shape is drawn at all is decided by what its ancestors said as much as by what it says; a parser that carries only the transform down paints decorations that were meant to be invisible. And the fit onto a target rectangle has to turn SVG's downward y axis into CoreGraphics' upward one, which is invisible on a symmetric glyph and unmistakable on an asymmetric one — hence a fixture painting a single corner.
///
struct SVGGlyphTests {
    @Test
    func `A document yields its viewBox and its shapes`() throws {
        let glyph = try #require(SVGGlyph(data: SVGGlyphFixture.data(SVGGlyphFixture.square)))

        #expect(glyph.viewBox == CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(glyph.shapes.count == 1)
    }

    @Test
    func `A negative viewBox origin is carried, not assumed away`() throws {
        let glyph = try #require(SVGGlyph(data: SVGGlyphFixture.data(SVGGlyphFixture.materialSymbol)))

        #expect(glyph.viewBox == CGRect(x: 0, y: -960, width: 960, height: 960))
    }

    @Test
    func `A document with no viewBox falls back to its declared size`() throws {
        let glyph = try #require(SVGGlyph(data: SVGGlyphFixture.data(SVGGlyphFixture.sizedWithoutViewBox)))

        #expect(glyph.viewBox == CGRect(x: 0, y: 0, width: 10, height: 10))
    }

    @Test
    func `A fill written as a style declaration is read`() throws {
        let glyph = try #require(SVGGlyph(data: SVGGlyphFixture.data(SVGGlyphFixture.styled)))

        #expect(glyph.shapes.count == 1)
    }

    @Test
    func `A style declaration outranks the attribute beside it`() throws {
        let glyph = try #require(SVGGlyph(data: SVGGlyphFixture.data(SVGGlyphFixture.contradicting)))

        #expect(glyph.shapes.count == 1)
    }

    @Test
    func `A shape that is neither filled nor stroked is not painted`() throws {
        let glyph = try #require(SVGGlyph(data: SVGGlyphFixture.data(SVGGlyphFixture.unpainted)))

        #expect(glyph.shapes.count == 1)
    }

    @Test
    func `A fill of none on a group reaches the shapes inside it`() {
        #expect(SVGGlyph(data: SVGGlyphFixture.data(SVGGlyphFixture.inheritedNone)) == nil)
    }

    @Test
    func `A transform on a group places the shapes inside it`() throws {
        let glyph = try #require(SVGGlyph(data: SVGGlyphFixture.data(SVGGlyphFixture.transformedGroup)))
        let shape = try #require(glyph.shapes.first)

        #expect(shape.path.boundingBoxOfPath == CGRect(x: 5, y: 5, width: 5, height: 5))
    }

    @Test
    func `A hidden shape is not painted`() {
        #expect(SVGGlyph(data: SVGGlyphFixture.data(SVGGlyphFixture.hidden)) == nil)
    }

    @Test
    func `A rectangle is read as a shape of its own`() throws {
        let glyph = try #require(SVGGlyph(data: SVGGlyphFixture.data(SVGGlyphFixture.roundedRectangle)))
        let shape = try #require(glyph.shapes.first)

        #expect(shape.path.boundingBoxOfPath == CGRect(x: 1, y: 1, width: 8, height: 8))
    }

    @Test
    func `A stroke with no fill still contributes a silhouette`() throws {
        let glyph = try #require(SVGGlyph(data: SVGGlyphFixture.data(SVGGlyphFixture.strokedLine)))
        let shape = try #require(glyph.shapes.first)

        // A line across the middle, stroked two units wide, spans one unit either side of it.
        #expect(shape.path.boundingBoxOfPath == CGRect(x: 0, y: 4, width: 10, height: 2))
    }

    @Test
    func `An explicit even-odd fill rule is carried to the shape`() throws {
        let glyph = try #require(SVGGlyph(data: SVGGlyphFixture.data(SVGGlyphFixture.donut)))
        let shape = try #require(glyph.shapes.first)

        #expect(shape.fillRule == .evenOdd)
    }

    @Test
    func `A shape overriding the root's fill rule keeps its own`() throws {
        let glyph = try #require(SVGGlyph(data: SVGGlyphFixture.data(SVGGlyphFixture.overriddenFillRule)))
        let shape = try #require(glyph.shapes.first)

        #expect(shape.fillRule == .winding)
    }

    @Test
    func `Bytes that are not an SVG at all are refused`() {
        #expect(SVGGlyph(data: SVGGlyphFixture.data(SVGGlyphFixture.signInPage)) == nil)
        #expect(SVGGlyph(data: Data([0xFF, 0xD8, 0xFF, 0xE0])) == nil)
    }

    @Test
    func `A command letter that is not one of the ten does not crash`() {
        // `"ß".uppercased()` is two characters, and building a `Character` from that traps. The path data
        // is chosen by the server, so this is untrusted input rather than a hypothetical.
        #expect(SVGGlyph(data: SVGGlyphFixture.data(SVGGlyphFixture.nonLetterCommand)) == nil)
    }

    @Test
    func `A coordinate too large to be a number is refused`() {
        #expect(SVGGlyph(data: SVGGlyphFixture.data(SVGGlyphFixture.absurdNumber)) == nil)
    }

    @Test
    func `Corner radii larger than the rectangle are clamped to it`() throws {
        let glyph = try #require(SVGGlyph(data: SVGGlyphFixture.data(SVGGlyphFixture.oversizedCorners)))
        let shape = try #require(glyph.shapes.first)

        #expect(shape.path.boundingBoxOfPath == CGRect(x: 0, y: 0, width: 10, height: 10))
    }

    @Test
    func `A stroke of negative width paints nothing`() {
        #expect(SVGGlyph(data: SVGGlyphFixture.data(SVGGlyphFixture.negativeStroke)) == nil)
    }

    @Test
    func `A document that paints nothing is refused rather than drawn empty`() {
        #expect(SVGGlyph(data: SVGGlyphFixture.data(SVGGlyphFixture.emptyDocument)) == nil)
    }

    @Test
    func `Fitting a square viewBox fills the target rectangle`() throws {
        let glyph = try #require(SVGGlyph(data: SVGGlyphFixture.data(SVGGlyphFixture.square)))
        let shape = try #require(glyph.shapes(fittedIn: CGRect(x: 0, y: 0, width: 20, height: 20)).first)

        #expect(shape.path.boundingBoxOfPath == CGRect(x: 0, y: 0, width: 20, height: 20))
    }

    @Test
    func `Fitting a wide viewBox letterboxes it rather than stretching it`() throws {
        let glyph = try #require(SVGGlyph(data: SVGGlyphFixture.data(SVGGlyphFixture.wide)))
        let shape = try #require(glyph.shapes(fittedIn: CGRect(x: 0, y: 0, width: 20, height: 20)).first)

        #expect(shape.path.boundingBoxOfPath == CGRect(x: 0, y: 5, width: 20, height: 10))
    }

    @Test
    func `Ink at the top of the viewBox lands at the top of the target`() throws {
        let glyph = try #require(SVGGlyph(data: SVGGlyphFixture.data(SVGGlyphFixture.topLeftQuadrant)))
        let shape = try #require(glyph.shapes(fittedIn: CGRect(x: 0, y: 0, width: 20, height: 20)).first)

        // CoreGraphics measures y upward, so the top-left quadrant of the viewBox is the *high* half here.
        // Without the flip this comes out at y == 0, which is the failure a symmetric glyph would hide.
        #expect(shape.path.boundingBoxOfPath == CGRect(x: 0, y: 10, width: 10, height: 10))
    }

    @Test
    func `A negative viewBox origin fits the same as a positive one`() throws {
        let glyph = try #require(SVGGlyph(data: SVGGlyphFixture.data(SVGGlyphFixture.materialSymbol)))
        let shape = try #require(glyph.shapes(fittedIn: CGRect(x: 0, y: 0, width: 20, height: 20)).first)

        #expect(shape.path.boundingBoxOfPath == CGRect(x: 0, y: 10, width: 10, height: 10))
    }

    @Test
    func `Fitting into an offset rectangle offsets the shapes with it`() throws {
        let glyph = try #require(SVGGlyph(data: SVGGlyphFixture.data(SVGGlyphFixture.square)))
        let shape = try #require(glyph.shapes(fittedIn: CGRect(x: 4, y: 6, width: 10, height: 10)).first)

        #expect(shape.path.boundingBoxOfPath == CGRect(x: 4, y: 6, width: 10, height: 10))
    }
}
