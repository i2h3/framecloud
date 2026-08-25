// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit

/// `BackgroundImageView` is an `NSImageView` that renders its image scaled to fill its bounds and center-cropped, matching the CSS `background-size: cover` of Nextcloud's own background rather than the aspect-fit scaling `NSImageView` offers.
///
/// `WebViewController` uses it for the themed backdrop shown behind the web view during the initial page load; with no image assigned it draws nothing, letting the window background show through.
class BackgroundImageView: NSImageView {
    override func draw(_: NSRect) {
        guard let image, image.size.width > 0, image.size.height > 0 else {
            return
        }

        let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2)

        image.draw(in: NSRect(origin: origin, size: size))
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }
}
