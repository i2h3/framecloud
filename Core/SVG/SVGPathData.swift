// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation

/// `SVGPathData` turns the text of an SVG `d` attribute into a `CGPath`.
///
/// It implements the whole path grammar — `M`, `L`, `H`, `V`, `C`, `S`, `Q`, `T`, `A` and `Z`, each in an absolute and a relative form — including the two parts of it that are easy to miss: a command letter may be followed by several groups of arguments and repeats for each, and a `moveto` that repeats becomes a `lineto` rather than starting further subpaths.
/// Elliptical arcs are the one command CoreGraphics cannot take as written. SVG describes an arc by the point it ends at, CoreGraphics by the centre it turns around, so `addArc(_:from:to:radiusX:radiusY:rotation:isLargeArc:isSweep:)` converts between the two parameterizations.
enum SVGPathData {
    /// `commandLimit` bounds how many commands one path may contain before its text is treated as malformed.
    ///
    /// The text comes from a server and is parsed where a menu is being built, so a scanner that stopped advancing would freeze the app rather than lose an icon. Nothing legitimate comes close: the largest of Nextcloud's own app icons is two orders of magnitude below this.
    private static let commandLimit = 100_000

    /// `path(from:)` parses `text` as SVG path data, or returns `nil` if it is malformed.
    ///
    /// Malformed means a command letter that is not one of the ten, or a path long enough to reach `commandLimit`. Arguments that merely run out mid-command end the path where they stopped instead of failing it, which is what the specification asks a renderer to do with a truncated `d`.
    static func path(from text: String) -> CGPath? {
        let path = CGMutablePath()
        var scanner = SVGNumberScanner(text)
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var previousCubicControl: CGPoint?
        var previousQuadraticControl: CGPoint?
        var command: Character?
        var commandCount = 0

        while true {
            scanner.skipSeparators()

            if scanner.isAtEnd {
                break
            }

            if let next = scanner.nextCommand() {
                command = next
            } else if !scanner.isAtNumber() {
                break
            }

            guard let active = command else {
                break
            }

            commandCount += 1

            guard commandCount <= commandLimit else {
                return nil
            }

            let isRelative = active.isLowercase

            func resolve(_ x: Double, _ y: Double) -> CGPoint {
                isRelative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            }

            // Matched case by case rather than through `uppercased()`: that returns a `String`, and for some
            // letters more than one character of it, so building a `Character` from it traps on input the
            // server chose. `ß` is enough to do it.
            switch active {
                case "M", "m":
                    guard let arguments = scanner.nextNumbers(2) else {
                        return path
                    }

                    current = resolve(arguments[0], arguments[1])
                    subpathStart = current
                    path.move(to: current)
                    previousCubicControl = nil
                    previousQuadraticControl = nil
                    // A repeated moveto is a lineto, per the SVG grammar.
                    command = isRelative ? "l" : "L"
                case "L", "l":
                    guard let arguments = scanner.nextNumbers(2) else {
                        return path
                    }

                    current = resolve(arguments[0], arguments[1])
                    path.addLine(to: current)
                    previousCubicControl = nil
                    previousQuadraticControl = nil
                case "H", "h":
                    guard let x = scanner.nextNumber() else {
                        return path
                    }

                    current = CGPoint(x: isRelative ? current.x + x : x, y: current.y)
                    path.addLine(to: current)
                    previousCubicControl = nil
                    previousQuadraticControl = nil
                case "V", "v":
                    guard let y = scanner.nextNumber() else {
                        return path
                    }

                    current = CGPoint(x: current.x, y: isRelative ? current.y + y : y)
                    path.addLine(to: current)
                    previousCubicControl = nil
                    previousQuadraticControl = nil
                case "C", "c":
                    guard let arguments = scanner.nextNumbers(6) else {
                        return path
                    }

                    let firstControl = resolve(arguments[0], arguments[1])
                    let secondControl = resolve(arguments[2], arguments[3])
                    let end = resolve(arguments[4], arguments[5])
                    path.addCurve(to: end, control1: firstControl, control2: secondControl)
                    current = end
                    previousCubicControl = secondControl
                    previousQuadraticControl = nil
                case "S", "s":
                    guard let arguments = scanner.nextNumbers(4) else {
                        return path
                    }

                    let firstControl = reflection(of: previousCubicControl, about: current)
                    let secondControl = resolve(arguments[0], arguments[1])
                    let end = resolve(arguments[2], arguments[3])
                    path.addCurve(to: end, control1: firstControl, control2: secondControl)
                    current = end
                    previousCubicControl = secondControl
                    previousQuadraticControl = nil
                case "Q", "q":
                    guard let arguments = scanner.nextNumbers(4) else {
                        return path
                    }

                    let control = resolve(arguments[0], arguments[1])
                    let end = resolve(arguments[2], arguments[3])
                    path.addQuadCurve(to: end, control: control)
                    current = end
                    previousQuadraticControl = control
                    previousCubicControl = nil
                case "T", "t":
                    guard let arguments = scanner.nextNumbers(2) else {
                        return path
                    }

                    let control = reflection(of: previousQuadraticControl, about: current)
                    let end = resolve(arguments[0], arguments[1])
                    path.addQuadCurve(to: end, control: control)
                    current = end
                    previousQuadraticControl = control
                    previousCubicControl = nil
                case "A", "a":
                    guard let ellipse = scanner.nextNumbers(3) else {
                        return path
                    }

                    guard let isLargeArc = scanner.nextFlag() else {
                        return path
                    }

                    guard let isSweep = scanner.nextFlag() else {
                        return path
                    }

                    guard let endpoint = scanner.nextNumbers(2) else {
                        return path
                    }

                    let end = resolve(endpoint[0], endpoint[1])
                    addArc(path, from: current, to: end, radiusX: ellipse[0], radiusY: ellipse[1], rotation: ellipse[2], isLargeArc: isLargeArc, isSweep: isSweep)
                    current = end
                    previousCubicControl = nil
                    previousQuadraticControl = nil
                case "Z", "z":
                    path.closeSubpath()
                    current = subpathStart
                    previousCubicControl = nil
                    previousQuadraticControl = nil
                default:
                    return nil
            }
        }

        return path
    }

    /// `reflection(of:about:)` mirrors the previous curve's control point through the current point, which is what a smooth `S` or `T` uses in place of the control point it leaves out.
    ///
    /// With no previous curve of the matching kind, the specification says the control point coincides with the current point.
    private static func reflection(of control: CGPoint?, about current: CGPoint) -> CGPoint {
        guard let control else {
            return current
        }

        return CGPoint(x: 2 * current.x - control.x, y: 2 * current.y - control.y)
    }

    /// `addArc(_:from:to:radiusX:radiusY:rotation:isLargeArc:isSweep:)` appends the elliptical arc SVG describes by its endpoint, converted to the centre and angles CoreGraphics draws from.
    ///
    /// The conversion is the one in the specification's implementation notes: rotate the endpoints into the ellipse's own frame, scale the radii up if they are too small to span the chord, solve for the centre, and take the start and sweep angles from there. Degenerate inputs — a zero radius, or coincident endpoints — become a straight line, as the specification requires.
    private static func addArc(_ path: CGMutablePath, from start: CGPoint, to end: CGPoint, radiusX: Double, radiusY: Double, rotation: Double, isLargeArc: Bool, isSweep: Bool) {
        guard radiusX != 0, radiusY != 0, start != end else {
            path.addLine(to: end)
            return
        }

        var radiusX = abs(radiusX)
        var radiusY = abs(radiusY)
        let tilt = rotation * .pi / 180
        let halfDeltaX = (start.x - end.x) / 2
        let halfDeltaY = (start.y - end.y) / 2
        let rotatedX = cos(tilt) * halfDeltaX + sin(tilt) * halfDeltaY
        let rotatedY = -sin(tilt) * halfDeltaX + cos(tilt) * halfDeltaY
        let oversize = (rotatedX * rotatedX) / (radiusX * radiusX) + (rotatedY * rotatedY) / (radiusY * radiusY)

        if oversize > 1 {
            let correction = sqrt(oversize)
            radiusX *= correction
            radiusY *= correction
        }

        let sign: Double = isLargeArc == isSweep ? -1 : 1
        let numerator = max(0, radiusX * radiusX * radiusY * radiusY - radiusX * radiusX * rotatedY * rotatedY - radiusY * radiusY * rotatedX * rotatedX)
        let denominator = radiusX * radiusX * rotatedY * rotatedY + radiusY * radiusY * rotatedX * rotatedX
        let factor = denominator == 0 ? 0 : sign * sqrt(numerator / denominator)
        let rotatedCenterX = factor * radiusX * rotatedY / radiusY
        let rotatedCenterY = -factor * radiusY * rotatedX / radiusX
        let startAngle = angle(from: 1, 0, to: (rotatedX - rotatedCenterX) / radiusX, (rotatedY - rotatedCenterY) / radiusY)
        var delta = angle(from: (rotatedX - rotatedCenterX) / radiusX, (rotatedY - rotatedCenterY) / radiusY, to: (-rotatedX - rotatedCenterX) / radiusX, (-rotatedY - rotatedCenterY) / radiusY)

        if !isSweep, delta > 0 {
            delta -= 2 * .pi
        }

        if isSweep, delta < 0 {
            delta += 2 * .pi
        }

        let centerX = cos(tilt) * rotatedCenterX - sin(tilt) * rotatedCenterY + (start.x + end.x) / 2
        let centerY = sin(tilt) * rotatedCenterX + cos(tilt) * rotatedCenterY + (start.y + end.y) / 2
        let transform = CGAffineTransform(translationX: centerX, y: centerY).rotated(by: tilt).scaledBy(x: radiusX, y: radiusY)
        path.addRelativeArc(center: .zero, radius: 1, startAngle: startAngle, delta: delta, transform: transform)
    }

    /// `angle(from:_:to:_:)` is the signed angle between two vectors, which is what the arc conversion measures its start and its sweep with.
    private static func angle(from firstX: Double, _ firstY: Double, to secondX: Double, _ secondY: Double) -> Double {
        let dot = firstX * secondX + firstY * secondY
        let magnitude = sqrt(firstX * firstX + firstY * firstY) * sqrt(secondX * secondX + secondY * secondY)

        guard magnitude != 0 else {
            return 0
        }

        let value = acos(min(1, max(-1, dot / magnitude)))

        return firstX * secondY - firstY * secondX < 0 ? -value : value
    }
}
