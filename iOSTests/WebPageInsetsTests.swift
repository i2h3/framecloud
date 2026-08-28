// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

///
/// `WebPageInsetsTests` covers `WebPageInsets`, which turns one SwiftUI measurement into the JavaScript call that publishes it into the Nextcloud web interface.
///
/// It is pure input-to-value logic with no web view and no layout involved, which is what makes it testable: the measuring itself belongs to SwiftUI and the publishing to WebKit, and neither is covered here.
/// Two properties are worth pinning. The first is that the horizontal edges are resolved from layout direction to physical sides, because a safe area is physical while `EdgeInsets` is not, and the two disagree in a right-to-left locale. The second is a safety invariant rather than a cosmetic one: the measurement is interpolated straight into a JavaScript call, so a `NaN` or an infinity arriving from a degenerate layout pass would produce a statement that does not parse and would take the whole injection down with it.
///
struct WebPageInsetsTests {
    ///
    /// The text of a bundled function expression is passed through untouched, so a short stand-in is enough for every case here.
    ///
    private static let function = "(function() {})"

    @Test
    func `A measurement becomes the call that publishes it`() {
        let insets = WebPageInsets(top: 116, leading: 0, bottom: 34, trailing: 0, isRightToLeft: false)

        #expect(insets.invocation(of: Self.function) == "(function() {})(116.0, 0.0, 34.0, 0.0);")
    }

    @Test
    func `Leading and trailing resolve to physical sides by layout direction`() {
        let leftToRight = WebPageInsets(top: 0, leading: 59, bottom: 21, trailing: 59, isRightToLeft: false)
        let rightToLeft = WebPageInsets(top: 0, leading: 12, bottom: 21, trailing: 59, isRightToLeft: true)

        #expect(leftToRight.left == 59)
        #expect(leftToRight.right == 59)
        #expect(rightToLeft.left == 59)
        #expect(rightToLeft.right == 12)
    }

    @Test(arguments: [CGFloat.nan, .infinity, -.infinity, -1, -0.0])
    func `A value a layout pass cannot express becomes zero`(value: CGFloat) {
        let insets = WebPageInsets(top: value, leading: value, bottom: value, trailing: value, isRightToLeft: false)

        #expect(insets.invocation(of: Self.function) == "(function() {})(0.0, 0.0, 0.0, 0.0);")
    }

    @Test
    func `Two measurements of the same geometry are equal`() {
        let first = WebPageInsets(top: 116, leading: 0, bottom: 34, trailing: 0, isRightToLeft: false)
        let second = WebPageInsets(top: 116, leading: 0, bottom: 34, trailing: 0, isRightToLeft: false)
        let rotated = WebPageInsets(top: 0, leading: 59, bottom: 21, trailing: 59, isRightToLeft: false)

        #expect(first == second)
        #expect(first != rotated)
    }
}
