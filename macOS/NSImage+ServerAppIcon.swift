// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
import Foundation

/// This extension turns the bitmap `ServerAppIcons` renders into the template image AppKit's menus and table cells take.
extension NSImage {
    /// `menuItemSize` is the edge length, in points, that a server app's icon is drawn at in a menu.
    ///
    /// AppKit grows a menu row to fit an image taller than the text beside it, so an icon much above this makes the whole list taller than the rest of the menu it sits in. Sixteen points is what the system's own imaged menu items use.
    static let serverAppIconSize: CGFloat = 16

    /// `serverAppIcon(forAppID:serverAddress:size:)` is the icon of one Nextcloud app, ready to be handed to a menu item, or `nil` if none has been cached for it yet.
    ///
    /// It comes back as a template image, so AppKit tints it for the appearance it is drawn in and inverts it when its row is highlighted — which is what makes a downloaded icon behave like one of the system's own symbols rather than like a picture pasted into a menu. The glyphs Nextcloud ships are monochrome, so nothing is lost by discarding their colour, and the ink asked for is immaterial here for the same reason: a template reads only the alpha. `ServerAppIconThumbnail` is the one place where the ink matters, because what it draws is not a template.
    /// Two pixels to the point is the highest backing scale any Mac has, so rendering at that scale is exact rather than a compromise.
    static func serverAppIcon(forAppID appID: String, serverAddress: URL, size: CGFloat = NSImage.serverAppIconSize) -> NSImage? {
        let bounds = CGSize(width: size, height: size)

        guard let image = ServerAppIcons.shared.image(forAppID: appID, serverAddress: serverAddress, size: bounds, scale: 2) else {
            return nil
        }

        let icon = NSImage(cgImage: image, size: NSSize(width: size, height: size))
        icon.isTemplate = true

        return icon
    }
}
