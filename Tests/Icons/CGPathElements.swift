// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation

/// `CGPathElements` is a readable, comparable transcript of what a `CGPath` actually contains.
///
/// A path's bounding box is the tempting thing to assert on and is nearly worthless for a parser: it is identical whether the curve between two corners was read as a line, a quadratic, or nothing at all. Walking the path instead pins the command each piece of `d` was turned into, which is the thing under test.
/// Coordinates are rounded before comparison because the arithmetic behind a relative command accumulates, and a test that fails on the last bit of a `Double` is measuring the floating-point unit rather than the parser.
struct CGPathElements: Equatable, CustomStringConvertible {
    /// `steps` are the path's commands in order, each rendered as text so a failing comparison reads as a diff rather than as two opaque values.
    let steps: [String]

    /// `init(_:)` walks `path` and transcribes it.
    init(_ path: CGPath) {
        var steps: [String] = []

        path.applyWithBlock { element in
            let points = element.pointee.points

            switch element.pointee.type {
                case .moveToPoint:
                    steps.append("move \(Self.text(points[0]))")
                case .addLineToPoint:
                    steps.append("line \(Self.text(points[0]))")
                case .addQuadCurveToPoint:
                    steps.append("quad \(Self.text(points[0])) \(Self.text(points[1]))")
                case .addCurveToPoint:
                    steps.append("curve \(Self.text(points[0])) \(Self.text(points[1])) \(Self.text(points[2]))")
                case .closeSubpath:
                    steps.append("close")
                @unknown default:
                    steps.append("unknown")
            }
        }

        self.steps = steps
    }

    /// `description` is the transcript one step per line, which is what a failed expectation prints.
    var description: String {
        steps.joined(separator: "\n")
    }

    /// `text(_:)` renders one point at the precision these comparisons are made at.
    private static func text(_ point: CGPoint) -> String {
        "\((point.x * 1000).rounded() / 1000),\((point.y * 1000).rounded() / 1000)"
    }
}
