// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// `SVGGlyphRasterizer` draws an `SVGGlyph` into a bitmap, and encodes one as PNG for the places that take image bytes rather than an image.
///
/// A raster rather than a vector is what crosses from the work that produces an icon to the work that shows one: `CGPath` is not `Sendable` and `CGImage` is, so ending here is what lets a glyph be parsed off the main actor and handed to a menu on it without an unchecked escape hatch. It is also what the surfaces themselves want — an `NSMenuItem` takes an image, and App Intents and Spotlight take PNG bytes.
/// Glyphs are drawn as opaque black on nothing, and the colour is immaterial: every consumer of this marks the result a template image, which reads only the alpha and tints it to suit whatever is drawing it. A caller that needs the glyph in some other colour — as the Spotlight artwork does — takes `SVGGlyph`'s shapes and fills them itself rather than asking for a second ink here.
enum SVGGlyphRasterizer {
    /// `dimensionLimit` is the largest bitmap edge, in pixels, this will allocate.
    ///
    /// Every caller asks for tens of pixels, so this is not a limit any of them meets; it is there so that a caller computing a size from something it did not choose cannot ask for an allocation that fails instead of an icon.
    private static let dimensionLimit = 4096

    /// `image(of:size:scale:)` draws `glyph` at `size` points with `scale` pixels to the point, or returns `nil` if a bitmap of that shape cannot be made.
    static func image(of glyph: SVGGlyph, size: CGSize, scale: CGFloat) -> CGImage? {
        // Converting a non-finite `Double` to an `Int` traps, and an icon is not worth a crash, so the
        // requested dimensions are checked before they are converted rather than after.
        guard size.width.isFinite, size.height.isFinite, scale.isFinite else {
            return nil
        }

        let requestedWidth = (size.width * scale).rounded()
        let requestedHeight = (size.height * scale).rounded()

        guard requestedWidth >= 1, requestedHeight >= 1 else {
            return nil
        }

        guard requestedWidth <= Double(dimensionLimit), requestedHeight <= Double(dimensionLimit) else {
            return nil
        }

        let width = Int(requestedWidth)
        let height = Int(requestedHeight)

        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }

        context.interpolationQuality = .high
        context.setShouldAntialias(true)
        context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)

        for shape in glyph.shapes(fittedIn: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))) {
            context.addPath(shape.path)
            context.fillPath(using: shape.fillRule)
        }

        return context.makeImage()
    }

    /// `pngData(of:size:scale:)` is `image(of:size:scale:)` encoded as PNG, for the interfaces that take image bytes.
    static func pngData(of glyph: SVGGlyph, size: CGSize, scale: CGFloat) -> Data? {
        guard let image = image(of: glyph, size: size, scale: scale) else {
            return nil
        }

        let data = NSMutableData()

        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }

        CGImageDestinationAddImage(destination, image, nil)

        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return data as Data
    }
}
