// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import WidgetKit

/// `PlaceholderTimelineProvider` supplies the scaffolding widget's timeline, so the extension exercises the whole WidgetKit path — placeholder, snapshot, timeline — without depending on a server, an account, or the shared App Group container.
///
/// That independence is the point while the target is being set up: `AppGroup.containerURL` is unreachable for any build signed without the App Group entitlement, which on iOS is every build until an iOS App ID carrying it exists, so a provider that read real state could not be distinguished from a broken one. It is expected to be replaced wholesale by a provider that reads the account store.
struct PlaceholderTimelineProvider: TimelineProvider {
    /// `placeholder(in:)` is the redacted view WidgetKit renders before any real entry exists, and returns the same shape as a live entry so the redaction has something to mask.
    func placeholder(in _: Context) -> PlaceholderEntry {
        PlaceholderEntry(date: Date(), emoji: "😀")
    }

    /// `getSnapshot(in:completion:)` is what the widget gallery shows, and answers immediately because nothing here needs loading.
    func getSnapshot(in _: Context, completion: @escaping (PlaceholderEntry) -> Void) {
        completion(PlaceholderEntry(date: Date(), emoji: "😀"))
    }

    /// `getTimeline(in:completion:)` returns five entries an hour apart and asks WidgetKit to come back for more once they are spent, which is enough for the timeline to visibly advance while the extension is being verified by hand.
    ///
    /// The offsets are added as intervals rather than through `Calendar`, so no arm of this method can fail and need a force unwrap for a date that is only ever decorative.
    func getTimeline(in _: Context, completion: @escaping (Timeline<PlaceholderEntry>) -> Void) {
        let currentDate = Date()
        let entries = (0 ..< 5).map { hourOffset in
            PlaceholderEntry(date: currentDate.addingTimeInterval(Double(hourOffset) * 3600), emoji: "😀")
        }

        completion(Timeline(entries: entries, policy: .atEnd))
    }
}
