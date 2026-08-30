// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import UIKit

/// This extension turns the bitmap `ServerAppIcons` renders into the template image a SwiftUI menu takes.
extension UIImage {
    /// `serverAppIconSize` is the edge length, in points, that a server app's icon is drawn at in a menu.
    ///
    /// A menu draws the icon beside its label at a size it decides for itself, so this is the resolution the bitmap is produced at rather than the size it appears at. It matches the size the Mac's menus use, for want of a reason to differ.
    static let serverAppIconSize: CGFloat = 16

    /// `serverAppIcon(forAppID:serverAddress:size:scale:)` is the icon of one Nextcloud app, ready to be shown in a menu, or `nil` if none has been cached for it yet.
    ///
    /// It comes back as a template image, so the menu tints it the way it tints an SF Symbol rather than drawing it as a picture that ignores the appearance around it. The glyphs Nextcloud ships are monochrome, so nothing is lost by discarding their colour.
    static func serverAppIcon(forAppID appID: String, serverAddress: URL, size: CGFloat = UIImage.serverAppIconSize, scale: CGFloat) -> UIImage? {
        let bounds = CGSize(width: size, height: size)

        guard let image = ServerAppIcons.shared.image(forAppID: appID, serverAddress: serverAddress, size: bounds, scale: scale) else {
            return nil
        }

        return UIImage(cgImage: image, scale: scale, orientation: .up).withRenderingMode(.alwaysTemplate)
    }
}
