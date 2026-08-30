// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation
import os

/// `SVGDocumentParser` walks an SVG document and accumulates every shape it paints into one `CGPath` expressed in the document's own viewBox coordinates.
///
/// It reads the subset Nextcloud's app icons are drawn in — `<svg>`, `<g>`, `<path>`, `<rect>`, `<circle>`, `<ellipse>`, `<polygon>`, `<polyline>` and `<line>`, with transforms and painting properties inherited down the tree — and ignores everything else it meets rather than failing on it, so a stray `<title>` or `<metadata>` costs nothing.
/// One thing makes it refuse a document outright instead: a `d` attribute it cannot read. A refused document falls back to a placeholder, which is the honest answer — a wrongly drawn one does not announce itself.
final class SVGDocumentParser: NSObject {
    /// `viewBox` is the rectangle of the document's own coordinate system, once `<svg>` has been read.
    private(set) var viewBox: CGRect?

    /// `shapes` is every painted element so far, in document order and in viewBox coordinates.
    private var shapes: [SVGShape] = []

    /// `states` is the inherited rendering state of each open element, innermost last.
    private var states: [SVGRenderingState] = [.initial]

    /// `hiddenDepth` counts how deep inside a hidden element the walk currently is, so its whole subtree is skipped rather than only its own shape.
    private var hiddenDepth = 0

    /// `isRefused` records that the document asked for something this parser will not approximate.
    private(set) var isRefused = false

    /// `logger` records refused documents under the `SVGDocumentParser` category.
    private static let logger = Logger(for: SVGDocumentParser.self)

    /// `parse(_:)` reads `data` and reports whether it yielded a usable document.
    ///
    /// It answers `false` for bytes that are not XML at all, which is the common failure in practice: a Nextcloud that wants authentication answers an asset request with an HTML sign-in page under a `200`, not with a `401`.
    func parse(_ data: Data) -> Bool {
        let parser = XMLParser(data: data)
        parser.delegate = self

        guard parser.parse() else {
            return false
        }

        guard !isRefused else {
            return false
        }

        return viewBox != nil && !shapes.isEmpty
    }

    /// `accumulated` is every painted element, in the order the document painted them.
    var accumulated: [SVGShape] {
        shapes
    }

    /// `add(_:in:)` adds one shape, drawn in its element's own coordinates, to the accumulated path.
    ///
    /// A shape that is only stroked is converted to the outline of that stroke first, so that an icon drawn as lines rather than as areas still contributes a silhouette. A shape that is neither filled nor stroked contributes nothing, which is what makes a full-bleed `<rect fill="none"/>` invisible rather than solid.
    /// The fill rule is read from the state the shape inherited rather than from whichever ancestor happened to mention it, because an ancestor's `fill-rule` means nothing where the shape overrides it — and in two thirds of Nextcloud's own icons it does.
    private func add(_ shape: CGPath, in state: SVGRenderingState) {
        var transform = state.transform

        if state.isFilled, let placed = shape.copy(using: &transform), Self.paints(placed) {
            shapes.append(SVGShape(path: placed, fillRule: state.fillRule == "evenodd" ? .evenOdd : .winding))
        }

        guard state.isStroked else {
            return
        }

        guard state.strokeWidth > 0 else {
            return
        }

        guard let outline = shape.copy(strokingWithWidth: state.strokeWidth, lineCap: .butt, lineJoin: .miter, miterLimit: 4) as CGPath? else {
            return
        }

        guard let placed = outline.copy(using: &transform), Self.paints(placed) else {
            return
        }

        shapes.append(SVGShape(path: placed, fillRule: .winding))
    }

    /// `paints(_:)` reports whether a path covers any area at all.
    ///
    /// A path can be non-empty and still paint nothing: a lone `moveto` is one element and no ink, which is exactly what a `d` attribute truncated by a coordinate it could not read leaves behind. Filling one would be a no-op, but *counting* one would make a document that draws nothing look like a document that draws something.
    private static func paints(_ path: CGPath) -> Bool {
        let box = path.boundingBoxOfPath

        guard !box.isNull, !box.isInfinite else {
            return false
        }

        return box.width > 0 || box.height > 0
    }

    /// `polygonPath(from:isClosed:)` is the path through the points of a `points` attribute, or `nil` if it names fewer than two.
    private func polygonPath(from text: String, isClosed: Bool) -> CGPath? {
        var scanner = SVGNumberScanner(text)
        var points: [CGPoint] = []

        while let pair = scanner.nextNumbers(2) {
            points.append(CGPoint(x: pair[0], y: pair[1]))
        }

        guard points.count >= 2 else {
            return nil
        }

        let shape = CGMutablePath()
        shape.addLines(between: points)

        if isClosed {
            shape.closeSubpath()
        }

        return shape
    }
}

/// `SVGDocumentParser`'s conformance to `XMLParserDelegate` is where the element walk itself happens.
extension SVGDocumentParser: XMLParserDelegate {
    func parser(_: XMLParser, didStartElement name: String, namespaceURI _: String?, qualifiedName _: String?, attributes: [String: String] = [:]) {
        let presentation = SVGPresentationAttributes(attributes)
        let state = (states.last ?? .initial).inheriting(presentation)
        states.append(state)

        if hiddenDepth > 0 {
            hiddenDepth += 1
            return
        }

        if presentation.value("display") == "none" || presentation.value("visibility") == "hidden" {
            hiddenDepth = 1
            return
        }

        switch name {
            case "svg":
                readViewBox(from: presentation)
            case "path":
                guard let data = presentation.value("d") else {
                    return
                }

                guard let shape = SVGPathData.path(from: data) else {
                    Self.logger.notice("Refusing an SVG whose path data could not be read")
                    isRefused = true
                    return
                }

                add(shape, in: state)
            case "rect":
                let rectangle = CGRect(x: presentation.number("x") ?? 0, y: presentation.number("y") ?? 0, width: presentation.number("width") ?? 0, height: presentation.number("height") ?? 0)

                guard rectangle.width > 0, rectangle.height > 0 else {
                    return
                }

                // A corner wider than half the side it is on is not a shape CoreGraphics will draw, and an
                // `rx` larger than the rectangle is a legal thing for a document to say, so it is clamped
                // rather than trusted — which is also what the specification asks a renderer to do with one.
                let declaredX = presentation.number("rx") ?? presentation.number("ry") ?? 0
                let declaredY = presentation.number("ry") ?? declaredX
                let radiusX = min(max(0, declaredX), rectangle.width / 2)
                let radiusY = min(max(0, declaredY), rectangle.height / 2)
                add(CGPath(roundedRect: rectangle, cornerWidth: radiusX, cornerHeight: radiusY, transform: nil), in: state)
            case "circle":
                let radius = presentation.number("r") ?? 0

                guard radius > 0 else {
                    return
                }

                let center = CGPoint(x: presentation.number("cx") ?? 0, y: presentation.number("cy") ?? 0)
                add(CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius), transform: nil), in: state)
            case "ellipse":
                let radiusX = presentation.number("rx") ?? 0
                let radiusY = presentation.number("ry") ?? 0

                guard radiusX > 0, radiusY > 0 else {
                    return
                }

                let center = CGPoint(x: presentation.number("cx") ?? 0, y: presentation.number("cy") ?? 0)
                add(CGPath(ellipseIn: CGRect(x: center.x - radiusX, y: center.y - radiusY, width: 2 * radiusX, height: 2 * radiusY), transform: nil), in: state)
            case "polygon", "polyline":
                guard let points = presentation.value("points") else {
                    return
                }

                guard let shape = polygonPath(from: points, isClosed: name == "polygon") else {
                    return
                }

                add(shape, in: state)
            case "line":
                let start = CGPoint(x: presentation.number("x1") ?? 0, y: presentation.number("y1") ?? 0)
                let end = CGPoint(x: presentation.number("x2") ?? 0, y: presentation.number("y2") ?? 0)
                let shape = CGMutablePath()
                shape.addLines(between: [start, end])
                add(shape, in: state)
            default:
                return
        }
    }

    func parser(_: XMLParser, didEndElement _: String, namespaceURI _: String?, qualifiedName _: String?) {
        if hiddenDepth > 0 {
            hiddenDepth -= 1
        }

        if states.count > 1 {
            states.removeLast()
        }
    }

    /// `readViewBox(from:)` records the document's own coordinate system, falling back to its declared size when it names no viewBox.
    private func readViewBox(from presentation: SVGPresentationAttributes) {
        if let text = presentation.value("viewBox") {
            var scanner = SVGNumberScanner(text)

            if let values = scanner.nextNumbers(4), values[2] > 0, values[3] > 0 {
                viewBox = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
                return
            }
        }

        let width = presentation.number("width") ?? 0
        let height = presentation.number("height") ?? 0

        guard width > 0, height > 0 else {
            return
        }

        viewBox = CGRect(x: 0, y: 0, width: width, height: height)
    }
}
