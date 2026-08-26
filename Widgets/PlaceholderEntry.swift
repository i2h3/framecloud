// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import WidgetKit

/// `PlaceholderEntry` is the single timeline entry type of the scaffolding widget, carrying just enough to prove that a timeline reaches the view: a date and a symbol to draw.
///
/// It exists so the extension has something to render while the target is still being wired up, and is expected to be deleted whole rather than grown — a real widget's entry describes the server state it shows, not a decorative glyph. `PlaceholderTimelineProvider` produces these and `PlaceholderWidgetView` renders them.
struct PlaceholderEntry: TimelineEntry {
    /// `date` is when WidgetKit should display this entry, which `TimelineEntry` requires and the view also shows outright, so the timeline advancing is visible rather than inferred.
    let date: Date

    /// `emoji` stands in for whatever a real widget would show, chosen because it needs no asset, no localization, and no server connection to prove the render path works.
    let emoji: String
}
