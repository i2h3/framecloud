// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
import CoreGraphics
import Foundation
import os

/// `ServerAppIconThumbnail` draws the picture of a Nextcloud app that Spotlight and the Shortcuts app are given: a small white window, three traffic lights in its top-left corner, and the app's own glyph centred in the body below them.
///
/// It exists because those two surfaces are the only ones that draw a downloaded icon *literally*. Everywhere else in the app an icon is a template image, which AppKit tints for the appearance it is drawn in; a donated bitmap leaves the process and is composited by something that will not tint it, so a bare glyph is legible in one appearance and nearly invisible in the other. That was the bug: black on black.
///
/// What fixes it is that the artwork is **opaque**. Nothing about it depends on what is behind it, so one bitmap is correct in both appearances and no second donation is needed when the user switches — which matters, because that switch usually happens while the app is not running. The window shape is the same idea as the app's own icon, and gives a Spotlight row something recognizable at a glance where a bare glyph read as a smudge.
/// The shadow does the work a border would otherwise do, and does it in only the appearance that needs it: it lifts the white plate off Spotlight's near-white light background, and in dark appearance it disappears into the background by itself, where the white body already contrasts strongly. `DECISIONS.md` records what else was measured and rejected, including Spotlight's own `darkThumbnailURL`, which turns out to be inert.
enum ServerAppIconThumbnail {
    /// `size` is the edge length, in points, of the artwork handed to Spotlight and Shortcuts.
    ///
    /// Larger than anything those surfaces are known to draw, because they decide their own size and scaling down is the direction that costs nothing.
    static let size: CGFloat = 64

    /// `shadowMarginFraction` is how much of the bitmap's edge is left empty around the plate, so the shadow has somewhere to fall instead of being clipped.
    private static let shadowMarginFraction: CGFloat = 0.07

    /// `shadowBlurFraction` is the shadow's blur radius as a share of the bitmap's edge.
    private static let shadowBlurFraction: CGFloat = 0.035

    /// `cornerRadiusFraction` is the plate's corner radius as a share of its own width, chosen to sit alongside the rounded rectangles macOS draws its own icons as.
    private static let cornerRadiusFraction: CGFloat = 0.20

    /// `trafficLightDiameterFraction` is a traffic light's diameter as a share of the plate's width.
    private static let trafficLightDiameterFraction: CGFloat = 0.095

    /// `glyphSideFraction` is the edge of the square the app's glyph is fitted into, as a share of the plate's width.
    private static let glyphSideFraction: CGFloat = 0.46

    /// `trafficLightColors` are the close, minimize and zoom colours, in that order.
    ///
    /// Taken from the app's own icon rather than from the ones macOS paints on a real window, because the point of this artwork is to look like the Cirruscope icon; the two sets are close but not identical. They are written down here because `AppIcon.icon` is an Icon Composer bundle whose layers no Swift code can reach — so if the icon is ever recoloured, this is the second place that has to change.
    private static let trafficLightColors = [
        CGColor(srgbRed: 1.0, green: 0.21961, blue: 0.23529, alpha: 1),
        CGColor(srgbRed: 1.0, green: 0.8, blue: 0.0, alpha: 1),
        CGColor(srgbRed: 0.20392, green: 0.78039, blue: 0.34902, alpha: 1),
    ]

    /// `logger` records thumbnail drawing under the `ServerAppIconThumbnail` category.
    private static let logger = Logger(for: ServerAppIconThumbnail.self)

    /// `pngData(forAppID:serverAddress:)` is the windowed icon of one app as PNG bytes, or `nil` if no icon has been cached for it or it cannot be drawn.
    ///
    /// A `nil` is ordinary rather than a failure — nothing has been fetched yet on a first launch — and the caller simply donates no image, which Spotlight and Shortcuts answer with their own generic one.
    static func pngData(forAppID appID: String, serverAddress: URL) -> Data? {
        guard let glyph = ServerAppIcons.shared.glyph(forAppID: appID, serverAddress: serverAddress) else {
            return nil
        }

        return pngData(drawing: glyph)
    }

    /// `pngData(drawing:)` is the artwork on its own, separate from the lookup so that what it draws can be asserted against actual pixels.
    ///
    /// That matters more here than it looks: the two ways this could silently go back to being unreadable — the plate losing its opacity, and the glyph losing its contrast against it — are both invisible to a test of the geometry and obvious to a test of the colours.
    static func pngData(drawing glyph: SVGGlyph) -> Data? {
        let edge = size * 2
        let margin = edge * shadowMarginFraction
        let plate = CGRect(x: margin, y: margin, width: edge - margin * 2, height: edge - margin * 2)
        let radius = plate.width * cornerRadiusFraction

        guard let ink = glyphColor() else {
            return nil
        }

        guard let context = CGContext(data: nil, width: Int(edge), height: Int(edge), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }

        context.setShouldAntialias(true)
        context.interpolationQuality = .high

        // The plate, under a soft shadow. Saved and restored around it so nothing drawn on top of the
        // window casts one of its own.
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -edge * 0.012), blur: edge * shadowBlurFraction, color: CGColor(gray: 0, alpha: 0.28))
        context.addPath(CGPath(roundedRect: plate, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fillPath()
        context.restoreGState()

        let diameter = plate.width * trafficLightDiameterFraction
        let lightsCenterY = plate.maxY - plate.height * 0.145

        for (index, color) in trafficLightColors.enumerated() {
            let x = plate.minX + plate.width * 0.11 + CGFloat(index) * diameter * 1.65
            context.setFillColor(color)
            context.fillEllipse(in: CGRect(x: x, y: lightsCenterY - diameter / 2, width: diameter, height: diameter))
        }

        // The glyph is centred in the body — between the underside of the traffic lights and the bottom of
        // the plate — rather than on the plate as a whole, which read as sitting noticeably low.
        let bodyCenterY = (lightsCenterY - diameter / 2 + plate.minY) / 2
        let side = plate.width * glyphSideFraction
        let box = CGRect(x: plate.midX - side / 2, y: bodyCenterY - side / 2, width: side, height: side)

        context.setFillColor(ink)

        for shape in glyph.shapes(fittedIn: box) {
            context.addPath(shape.path)
            context.fillPath(using: shape.fillRule)
        }

        guard let composed = context.makeImage() else {
            return nil
        }

        return NSBitmapImageRep(cgImage: composed).representation(using: .png, properties: [:])
    }

    /// `glyphColor()` is the colour the app's glyph is filled with: the secondary label colour, resolved in the light appearance.
    ///
    /// The light one always, and deliberately. The plate is white whatever the system is set to, so the ink on it has to be the one meant for a light surface; resolving it in the current appearance would produce pale grey on white the moment the user switched to dark, which is the same class of bug this whole type exists to fix.
    private static func glyphColor() -> CGColor? {
        var resolved: CGColor?

        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
            resolved = NSColor.secondaryLabelColor.usingColorSpace(.sRGB)?.cgColor
        }

        guard let resolved else {
            logger.error("The secondary label colour could not be resolved; no thumbnail will be drawn")
            return nil
        }

        return resolved
    }
}
