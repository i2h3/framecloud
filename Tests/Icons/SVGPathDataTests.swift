// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import CoreGraphics
import Foundation
import Testing

///
/// `SVGPathDataTests` covers `SVGPathData`, which reads the `d` attribute of an SVG path.
///
/// This is where a server's bytes first become geometry, and it is the part of the icon pipeline with the most ways to be quietly wrong: SVG's grammar packs tokens together wherever they are unambiguous, repeats a command for every extra group of arguments it finds, and reinterprets a repeated `moveto` as a `lineto`. Each of those is asserted here against the command stream the parser actually produced, not against a bounding box, which would be identical whether a curve had been read as a curve or dropped.
///
struct SVGPathDataTests {
    @Test
    func `Absolute and relative commands describe the same square`() throws {
        let absolute = try #require(SVGPathData.path(from: "M0 0 H10 V10 H0 Z"))
        let relative = try #require(SVGPathData.path(from: "m0 0 h10 v10 h-10 z"))

        #expect(CGPathElements(absolute) == CGPathElements(relative))
    }

    @Test
    func `A repeated moveto continues as a lineto`() throws {
        let path = try #require(SVGPathData.path(from: "M0 0 5 5 10 0"))

        #expect(CGPathElements(path).steps == ["move 0.0,0.0", "line 5.0,5.0", "line 10.0,0.0"])
    }

    @Test
    func `A command repeats for every further group of arguments`() throws {
        let path = try #require(SVGPathData.path(from: "M0 0 L1 1 2 2 3 3"))

        #expect(CGPathElements(path).steps == ["move 0.0,0.0", "line 1.0,1.0", "line 2.0,2.0", "line 3.0,3.0"])
    }

    @Test
    func `Numbers written without separators are read as several`() throws {
        let path = try #require(SVGPathData.path(from: "M.5.5L-.25-.75"))

        #expect(CGPathElements(path).steps == ["move 0.5,0.5", "line -0.25,-0.75"])
    }

    @Test
    func `A smooth cubic reflects the previous control point`() throws {
        let path = try #require(SVGPathData.path(from: "M0 0 C1 1 2 2 3 3 S5 5 6 6"))

        #expect(CGPathElements(path).steps == ["move 0.0,0.0", "curve 1.0,1.0 2.0,2.0 3.0,3.0", "curve 4.0,4.0 5.0,5.0 6.0,6.0"])
    }

    @Test
    func `A smooth quadratic reflects the previous control point`() throws {
        let path = try #require(SVGPathData.path(from: "M0 0 Q2 4 4 0 T8 0"))

        #expect(CGPathElements(path).steps == ["move 0.0,0.0", "quad 2.0,4.0 4.0,0.0", "quad 6.0,-4.0 8.0,0.0"])
    }

    @Test
    func `A smooth curve with nothing to reflect starts at the current point`() throws {
        let path = try #require(SVGPathData.path(from: "M2 2 S4 4 6 6"))

        #expect(CGPathElements(path).steps == ["move 2.0,2.0", "curve 2.0,2.0 4.0,4.0 6.0,6.0"])
    }

    @Test
    func `Closing a subpath returns to where it started`() throws {
        let path = try #require(SVGPathData.path(from: "M2 2 H8 V8 Z l1 1"))

        #expect(CGPathElements(path).steps.last == "line 3.0,3.0")
    }

    @Test
    func `Arc flags need no separators around them`() throws {
        let packed = try #require(SVGPathData.path(from: "M0 0a5 5 0 0110 0"))
        let spaced = try #require(SVGPathData.path(from: "M0 0 a5 5 0 0 1 10 0"))

        #expect(CGPathElements(packed) == CGPathElements(spaced))
        #expect(packed.currentPoint.x == 10)
    }

    @Test
    func `An arc with a zero radius degenerates to a line`() throws {
        let path = try #require(SVGPathData.path(from: "M0 0 A0 0 0 0 1 10 10"))

        #expect(CGPathElements(path).steps == ["move 0.0,0.0", "line 10.0,10.0"])
    }

    @Test
    func `A command that is not one of the ten fails the whole path`() {
        #expect(SVGPathData.path(from: "M0 0 K5 5") == nil)
    }

    @Test
    func `Arguments running out end the path where they stopped`() throws {
        let path = try #require(SVGPathData.path(from: "M0 0 L5 5 L7"))

        #expect(CGPathElements(path).steps == ["move 0.0,0.0", "line 5.0,5.0"])
    }
}
