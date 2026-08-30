// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation

/// `SVGRenderingState` is what an SVG element inherits from the elements it sits inside: where it is placed, and whether it is painted at all.
///
/// SVG's painting properties inherit down the tree, so a `fill` set on a `<g>` governs every shape inside it that does not set its own. Carrying only the transform down — the obvious thing to do — silently paints shapes their parent said not to paint, which is how a decorative full-bleed `<rect fill="none"/>` turns into a solid black square.
/// The fill rule inherits the same way, and that matters more than it looks: two thirds of Nextcloud's own app icons declare `fill-rule:evenodd` on the root `<svg>` and then override it to `nonzero` on the one path they draw. Judging the rule anywhere but at the shape being painted reads those backwards.
/// Colour is not carried, only whether there is any. These icons are monochrome glyphs meant to be tinted by whatever shows them, so the only question worth inheriting is whether a shape contributes to the silhouette.
struct SVGRenderingState {
    /// `transform` places this element's coordinates in the coordinates of the document's viewBox.
    let transform: CGAffineTransform

    /// `fill` is the fill this element paints with, as written; `"none"` means it paints no interior.
    let fill: String

    /// `stroke` is the stroke this element outlines with, as written, or `nil` if it has none.
    let stroke: String?

    /// `strokeWidth` is the width that stroke is drawn at, in this element's own coordinates.
    let strokeWidth: Double

    /// `fillRule` is the rule deciding which parts of a self-overlapping shape count as inside it, as written; SVG's initial value is `"nonzero"`.
    let fillRule: String

    /// `isFilled` reports whether this element contributes its interior to the silhouette.
    var isFilled: Bool {
        fill != "none"
    }

    /// `isStroked` reports whether this element contributes an outline to the silhouette.
    var isStroked: Bool {
        guard let stroke else {
            return false
        }

        return stroke != "none"
    }

    /// `initial` is the state at the root of a document, which is SVG's own set of initial values: no transform, a black fill, no stroke.
    static let initial = SVGRenderingState(transform: .identity, fill: "black", stroke: nil, strokeWidth: 1, fillRule: "nonzero")

    /// `inheriting(_:)` is the state an element with `attributes` has, given this one as its parent's.
    func inheriting(_ attributes: SVGPresentationAttributes) -> SVGRenderingState {
        var transform = transform

        if let text = attributes.value("transform") {
            transform = SVGTransform.transform(from: text).concatenating(transform)
        }

        return SVGRenderingState(transform: transform, fill: attributes.value("fill") ?? fill, stroke: attributes.value("stroke") ?? stroke, strokeWidth: attributes.number("stroke-width") ?? strokeWidth, fillRule: attributes.value("fill-rule") ?? fillRule)
    }
}
