// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import SwiftUI
import WidgetKit

/// `PlaceholderWidget` is the scaffolding widget the extension ships while the target is being set up, and the only member of `WidgetsBundle`.
///
/// It exists so both apps have something to embed and so Xcode's canvas has something to render, since macOS widgets compile `#Preview(as:widget:)` but do not render it. Replacing it with a real widget means replacing this type and the three `Placeholder…` types it composes, not editing them.
struct PlaceholderWidget: Widget {
    /// `kind` is the identifier WidgetKit uses to tell this widget's configured instances apart from any other widget in the bundle, and must stay stable for as long as this widget exists or already-placed instances lose their timeline.
    let kind: String = "PlaceholderWidget"

    /// `body` declares a static configuration, because nothing here is user-configurable yet: a real widget picking a server or an app would use an `AppIntentConfiguration` instead.
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PlaceholderTimelineProvider()) { entry in
            PlaceholderWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("My Widget")
        .description("This is an example widget.")
    }
}
