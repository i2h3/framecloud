// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import SwiftUI
import WidgetKit

/// `PlaceholderWidgetView` renders one `PlaceholderEntry`, and is deliberately the plainest thing that still proves the entry reached the view.
///
/// Its strings are intentionally not localized: they are diagnostic labels for a widget nobody is meant to keep, and `Widgets/Localizable.xcstrings` stays empty until the real widget brings copy worth translating.
struct PlaceholderWidgetView: View {
    /// `entry` is the timeline entry being rendered, handed over by `PlaceholderWidget`'s configuration closure.
    var entry: PlaceholderEntry

    /// `body` shows the entry's date and symbol, so both halves of `PlaceholderEntry` are visible on screen and a stalled timeline is obvious.
    var body: some View {
        VStack {
            HStack {
                Text(verbatim: "Time:")
                Text(entry.date, style: .time)
            }

            Text(verbatim: "Emoji:")
            Text(verbatim: entry.emoji)
        }
    }
}
