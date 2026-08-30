// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `SVGNumberScanner` reads the number, flag, and command tokens an SVG attribute is written in, one at a time, from a string it does not copy the meaning of.
///
/// SVG's grammar for the `d` and `transform` attributes is deliberately terse and cannot be tokenized by splitting on whitespace: separators are optional wherever they are unambiguous, so `.5.5` is two numbers, `-.437` is one, and the two flags of an elliptical arc may be written with nothing between them or the numbers around them (`a1 1 0 011 1`). Foundation's `Scanner` reads none of those the way SVG means them, which is why this exists rather than being wrapped around it.
/// It is a value type holding an index into the characters it was given, so a caller advances it by mutating its own copy and nothing is shared.
struct SVGNumberScanner {
    /// `characters` is the text being scanned, indexable by position.
    private let characters: [Character]

    /// `index` is the position of the next character to read.
    private var index: Int

    /// `init(_:)` creates a scanner positioned at the start of `text`.
    init(_ text: String) {
        characters = Array(text)
        index = 0
    }

    /// `isAtEnd` reports whether every character has been read.
    var isAtEnd: Bool {
        index >= characters.count
    }

    /// `skipSeparators()` advances past the whitespace and commas SVG allows between tokens.
    mutating func skipSeparators() {
        while index < characters.count, characters[index] == " " || characters[index] == "," || characters[index] == "\n" || characters[index] == "\t" || characters[index] == "\r" {
            index += 1
        }
    }

    /// `nextNumber()` reads the number at the current position, or returns `nil` and stays where it is if there is not one.
    ///
    /// It accepts every form SVG permits: a leading sign, an omitted integer or fractional part (`.5`, `5.`), and a scientific exponent. An exponent that turns out to be malformed (`1e`) is rewound rather than consumed, so the `e` is left for whoever reads next.
    /// A number too large to be one — `1e999`, which `Double` reads as an infinity — is refused as though it were not a number at all. Nothing downstream can do arithmetic with an infinity, and several things trap on the results, so this is the one place worth stopping it.
    mutating func nextNumber() -> Double? {
        skipSeparators()

        let start = index

        if index < characters.count, characters[index] == "+" || characters[index] == "-" {
            index += 1
        }

        var hasDigits = false

        while index < characters.count, characters[index].isNumber {
            index += 1
            hasDigits = true
        }

        if index < characters.count, characters[index] == "." {
            index += 1

            while index < characters.count, characters[index].isNumber {
                index += 1
                hasDigits = true
            }
        }

        if hasDigits, index < characters.count, characters[index] == "e" || characters[index] == "E" {
            let beforeExponent = index
            index += 1

            if index < characters.count, characters[index] == "+" || characters[index] == "-" {
                index += 1
            }

            if index < characters.count, characters[index].isNumber {
                while index < characters.count, characters[index].isNumber {
                    index += 1
                }
            } else {
                index = beforeExponent
            }
        }

        guard hasDigits else {
            index = start
            return nil
        }

        guard let value = Double(String(characters[start ..< index])), value.isFinite else {
            // `1e999` parses to an infinity and `Int(_:)` traps on one, so a value that cannot be
            // arithmetic is refused here rather than at whichever geometry first divides by it.
            index = start
            return nil
        }

        return value
    }

    /// `nextNumbers(_:)` reads exactly `count` numbers, or returns `nil` and leaves the scanner where it was if there are fewer left.
    ///
    /// Path commands take their arguments in fixed-size groups, so reading a whole group at once is what lets a caller check for one value rather than for each coordinate separately.
    mutating func nextNumbers(_ count: Int) -> [Double]? {
        let start = index
        var numbers: [Double] = []

        while numbers.count < count {
            guard let number = nextNumber() else {
                index = start
                return nil
            }

            numbers.append(number)
        }

        return numbers
    }

    /// `nextFlag()` reads one elliptical-arc flag, which is a bare `0` or `1` that needs no separator after it.
    ///
    /// Reading it as a number instead would swallow the digits that follow, since `011` is one number but three tokens: two flags and the start of a coordinate.
    mutating func nextFlag() -> Bool? {
        skipSeparators()

        guard index < characters.count else {
            return nil
        }

        switch characters[index] {
            case "0":
                index += 1
                return false
            case "1":
                index += 1
                return true
            default:
                return nextNumber().map { $0 != 0 }
        }
    }

    /// `nextCommand()` reads the letter naming the next path command, or returns `nil` and stays where it is if the next token is not one.
    mutating func nextCommand() -> Character? {
        skipSeparators()

        guard index < characters.count, characters[index].isLetter else {
            return nil
        }

        defer {
            index += 1
        }

        return characters[index]
    }

    /// `isAtNumber()` reports whether the next token is a number, which is what tells a path command it repeats rather than ends.
    mutating func isAtNumber() -> Bool {
        skipSeparators()

        guard index < characters.count else {
            return false
        }

        let character = characters[index]

        return character.isNumber || character == "-" || character == "+" || character == "."
    }
}
