// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation

/// `SVGShape` is one painted element of an SVG document: its outline, and the rule deciding which parts of that outline count as inside it.
///
/// An icon is kept as a list of these rather than merged into a single path for two reasons, both of which show up in Nextcloud's own icons. The rule can differ between elements, and it changes what is drawn: a shape whose subpaths overlap fills solid under one rule and hollow under the other. And merging two separately painted shapes can cancel where they overlap, which painting them one after another never does.
struct SVGShape {
    /// `path` is the outline, in the coordinates of the document's viewBox, with SVG's y axis still pointing down.
    let path: CGPath

    /// `fillRule` decides which parts of `path` are inside it.
    let fillRule: CGPathFillRule
}
