// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation

/// `SVGGlyph` is one monochrome vector icon read out of an SVG document: the coordinate system it was drawn in, and the shapes that make up its silhouette.
///
/// It exists because a Nextcloud server names each of its apps' icons as an SVG and neither platform will decode one for the app. macOS does have a decoder behind `NSImage(data:)`, but it is a private image representation and iOS has no equivalent at all, so leaning on it would mean one platform showing icons and the other not.
/// What it reads is deliberately a subset — enough for the icons Nextcloud ships, which are single-path white glyphs — and it returns `nil` rather than approximating anything outside it. No gradients, no `<use>`, no CSS stylesheets, no text. Colour is discarded entirely, because every place these are shown wants a template that takes the tint of whatever is showing it.
struct SVGGlyph {
    /// `viewBox` is the rectangle of the coordinate system `shapes` are expressed in.
    ///
    /// It is frequently not anchored at the origin — Material Symbols, which twenty of Nextcloud's own app icons are drawn as, use `0 -960 960 960` — so it has to be subtracted rather than assumed away.
    let viewBox: CGRect

    /// `shapes` are the icon's painted elements, in the order the document paints them.
    let shapes: [SVGShape]

    /// `init?(data:)` reads an SVG document, or returns `nil` if it is not one this can draw faithfully.
    init?(data: Data) {
        let parser = SVGDocumentParser()

        guard parser.parse(data) else {
            return nil
        }

        guard let viewBox = parser.viewBox else {
            return nil
        }

        self.viewBox = viewBox
        shapes = parser.accumulated
    }

    /// `shapes(fittedIn:)` are the icon's shapes placed inside `rect`, scaled to fit without distortion, centred on both axes, and flipped onto CoreGraphics' upward y axis.
    ///
    /// The flip is the part worth stating out loud: SVG measures y downward from the top of the viewBox and CoreGraphics measures it upward from the bottom of the context, so a glyph drawn without it comes out mirrored — invisibly so for the many icons that happen to be symmetric, which is what makes getting it wrong easy to miss.
    func shapes(fittedIn rect: CGRect) -> [SVGShape] {
        guard viewBox.width > 0, viewBox.height > 0 else {
            return shapes
        }

        var transform = transform(fittingIn: rect)

        return shapes.compactMap { shape in
            guard let placed = shape.path.copy(using: &transform) else {
                return nil
            }

            return SVGShape(path: placed, fillRule: shape.fillRule)
        }
    }

    /// `transform(fittingIn:)` maps the icon's own coordinates onto `rect`, preserving its aspect ratio and turning SVG's downward y axis into CoreGraphics' upward one.
    func transform(fittingIn rect: CGRect) -> CGAffineTransform {
        let scale = min(rect.width / viewBox.width, rect.height / viewBox.height)
        let originX = rect.minX + (rect.width - viewBox.width * scale) / 2
        let originY = rect.minY + (rect.height - viewBox.height * scale) / 2

        return CGAffineTransform(translationX: originX, y: originY).scaledBy(x: scale, y: -scale).translatedBy(x: -viewBox.minX, y: -viewBox.minY - viewBox.height)
    }
}
