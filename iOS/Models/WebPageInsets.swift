// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation

///
/// `WebPageInsets` is one measurement of how much of the web view the app's own interface covers, in the form `iOSScript.safeAreaInsets` expects to be invoked with.
///
/// The web view ignores the safe area so the page can paint to the bezel, which leaves the device's own insets and the height of the navigation bar floating above it as margins the page has to keep its content clear of on its own. This carries those four margins from the measurement SwiftUI took to the JavaScript call that publishes them, and nothing else: it holds no state, reads no geometry, and decides nothing about when a measurement is taken.
/// Being `Equatable` is what lets a caller push only when the geometry actually changed rather than on every layout pass.
///
struct WebPageInsets: Equatable, Sendable {
    ///
    /// The margin covered at the top of the web view, in points.
    ///
    let top: CGFloat

    ///
    /// The margin covered at the physically right edge of the web view, in points.
    ///
    let right: CGFloat

    ///
    /// The margin covered at the bottom of the web view, in points.
    ///
    let bottom: CGFloat

    ///
    /// The margin covered at the physically left edge of the web view, in points.
    ///
    let left: CGFloat

    ///
    /// Creates a measurement from SwiftUI's layout-direction-relative edges.
    ///
    /// A safe area is physical — the notch is on the same side of the device whichever way the text runs — while `EdgeInsets` names its horizontal edges by layout direction, so the two swap in a right-to-left locale. Resolving that here rather than at the call site is what keeps `left` and `right` meaning what the stylesheet and the device both take them to mean.
    /// Every value is clamped to a finite, non-negative number: a degenerate layout pass can hand back a `NaN` or an infinity, and interpolating one of those into the script would produce a JavaScript literal that does not parse.
    ///
    init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat, isRightToLeft: Bool) {
        self.top = Self.sanitized(top)
        self.bottom = Self.sanitized(bottom)
        left = Self.sanitized(isRightToLeft ? trailing : leading)
        right = Self.sanitized(isRightToLeft ? leading : trailing)
    }

    ///
    /// The JavaScript statement that invokes `function` with this measurement.
    ///
    /// `function` is the text of the bundled function expression, which is invoked rather than interpolated into, so the measurement never becomes part of a string the page parses as anything but numbers. No escaping or locale-aware formatting is needed for the arguments themselves: `sanitized(_:)` has already reduced each one to a finite, non-negative value, and Swift's own description of a floating-point number is decimal-separated the same way in every locale.
    /// The values cross as points and are written as CSS pixels unconverted, which holds for as long as the page declares a viewport of `width=device-width` at scale 1, as Nextcloud does.
    ///
    func invocation(of function: String) -> String {
        "\(function)(\(top), \(right), \(bottom), \(left));"
    }

    ///
    /// Reduces a measured value to the finite, non-negative number the script can be handed.
    ///
    private static func sanitized(_ value: CGFloat) -> CGFloat {
        value.isFinite && value > 0 ? value : 0
    }
}
