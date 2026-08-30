// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import CoreGraphics
import Foundation
import Testing

///
/// `SVGTransformTests` covers `SVGTransform`, which reads the `transform` attribute of an SVG element.
///
/// The functions themselves are arithmetic and hard to get wrong. The order they compose in is not: SVG applies a list of them left to right, so the leftmost is outermost and a point meets the rightmost first — the opposite of how `concatenating(_:)` reads. Getting that backwards still places artwork somewhere plausible, which is why it is asserted rather than assumed.
///
struct SVGTransformTests {
    @Test
    func `Each function is the transform it names`() {
        #expect(SVGTransform.transform(from: "translate(3 4)") == CGAffineTransform(translationX: 3, y: 4))
        #expect(SVGTransform.transform(from: "scale(2 3)") == CGAffineTransform(scaleX: 2, y: 3))
        #expect(SVGTransform.transform(from: "matrix(1 2 3 4 5 6)") == CGAffineTransform(a: 1, b: 2, c: 3, d: 4, tx: 5, ty: 6))
    }

    @Test
    func `A scale given one value scales both axes`() {
        #expect(SVGTransform.transform(from: "scale(2)") == CGAffineTransform(scaleX: 2, y: 2))
    }

    @Test
    func `A rotation about a point leaves that point where it was`() {
        let transform = SVGTransform.transform(from: "rotate(90 5 5)")
        let fixed = CGPoint(x: 5, y: 5).applying(transform)

        #expect(abs(fixed.x - 5) < 0.0001)
        #expect(abs(fixed.y - 5) < 0.0001)
    }

    @Test
    func `Functions compose left to right, the leftmost outermost`() {
        let transform = SVGTransform.transform(from: "translate(10 0) scale(2)")
        let moved = CGPoint(x: 1, y: 0).applying(transform)

        // Scaled first, then translated: 1 × 2 + 10. The other order would put it at 22.
        #expect(moved.x == 12)
    }

    @Test
    func `Separators between and inside functions are optional`() {
        let spaced = SVGTransform.transform(from: "translate(1, 2) scale(3)")
        let packed = SVGTransform.transform(from: "translate(1 2)scale(3)")

        #expect(spaced == packed)
    }

    @Test
    func `An unrecognized function contributes nothing`() {
        #expect(SVGTransform.transform(from: "wobble(3)") == .identity)
        #expect(SVGTransform.transform(from: "wobble(3) translate(1 2)") == CGAffineTransform(translationX: 1, y: 2))
    }

    @Test
    func `An attribute naming no function is the identity`() {
        #expect(SVGTransform.transform(from: "") == .identity)
    }
}
