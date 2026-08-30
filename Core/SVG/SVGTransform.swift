// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation

/// `SVGTransform` turns the text of an SVG `transform` attribute into the `CGAffineTransform` it describes.
///
/// An attribute may name several functions in a row, and SVG applies them left to right — the leftmost is the outermost, so a point passes through the rightmost first. That is the reverse of how `concatenating(_:)` reads, which is the one thing worth getting right here.
/// Nextcloud's own app icons use this to normalize icons drawn on one grid into a viewBox of another size, which is why a `translate` followed by a `scale` is the common case rather than an exotic one.
enum SVGTransform {
    /// `transform(from:)` parses `text`, ignoring any function it does not recognize.
    ///
    /// An unrecognized or malformed function contributes the identity rather than failing the whole attribute, because a transform that cannot be read is far more likely to be a decorative extra than the one placing the artwork.
    static func transform(from text: String) -> CGAffineTransform {
        var result = CGAffineTransform.identity
        var remainder = Substring(text)

        while let open = remainder.firstIndex(of: "(") {
            guard let close = remainder[open...].firstIndex(of: ")") else {
                break
            }

            let name = remainder[remainder.startIndex ..< open].trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",")))
            var scanner = SVGNumberScanner(String(remainder[remainder.index(after: open) ..< close]))
            var values: [Double] = []

            while let value = scanner.nextNumber() {
                values.append(value)
            }

            result = function(named: name, values: values).concatenating(result)
            remainder = remainder[remainder.index(after: close)...]
        }

        return result
    }

    /// `function(named:values:)` is the transform one named SVG function with `values` stands for, or the identity if the pair does not describe one.
    private static func function(named name: String, values: [Double]) -> CGAffineTransform {
        switch name {
            case "matrix":
                guard values.count == 6 else {
                    return .identity
                }

                return CGAffineTransform(a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
            case "translate":
                guard let x = values.first else {
                    return .identity
                }

                return CGAffineTransform(translationX: x, y: values.count > 1 ? values[1] : 0)
            case "scale":
                guard let x = values.first else {
                    return .identity
                }

                return CGAffineTransform(scaleX: x, y: values.count > 1 ? values[1] : x)
            case "rotate":
                guard let degrees = values.first else {
                    return .identity
                }

                guard values.count >= 3 else {
                    return CGAffineTransform(rotationAngle: degrees * .pi / 180)
                }

                return CGAffineTransform(translationX: values[1], y: values[2]).rotated(by: degrees * .pi / 180).translatedBy(x: -values[1], y: -values[2])
            case "skewX":
                guard let degrees = values.first else {
                    return .identity
                }

                return CGAffineTransform(a: 1, b: 0, c: tan(degrees * .pi / 180), d: 1, tx: 0, ty: 0)
            case "skewY":
                guard let degrees = values.first else {
                    return .identity
                }

                return CGAffineTransform(a: 1, b: tan(degrees * .pi / 180), c: 0, d: 1, tx: 0, ty: 0)
            default:
                return .identity
        }
    }
}
