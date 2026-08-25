// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents

/// `ServerAppShortcuts` registers the App Shortcuts Cirruscope offers to Siri and the Shortcuts app, so the user can invoke them without assembling a shortcut by hand.
///
/// Its single entry binds `OpenServerAppIntent` to spoken phrases, following the shape of Apple's "Adopting App Intents to support system experiences" sample: the plain `AppShortcut` initializer (that sample parameterizes its phrases without a `parameterPresentation:`), a phrase carrying no parameter first, then the parameterized variants. Every phrase must contain `\(.applicationName)`, which is why a bare "Open Nextcloud Notes" is expressed via Spotlight (see `ServerAppEntity.attributeSet`) rather than a phrase.
///
/// The first phrase deliberately carries **no** parameter, and that is not redundancy: as of macOS 26 the system rejects every phrase template that interpolates a parameter ("Skipping phrase template with an unrecognized token", then "Empty spans, will not donate"), so the parameter-free phrase is the only one Siri actually receives. That rejection is not caused by this app — it reproduces with Apple's own sample, unmodified, in both `de-DE` and `en-US`, and on a clean virtual machine; see `DECISIONS.md`. The Shortcuts app and Spotlight are unaffected and do offer the app parameter, so keep the parameterized phrases: they cost nothing and start working the day the system accepts them.
///
/// That first phrase says "an app" rather than "a Nextcloud app" on purpose. Every phrase has to interpolate `\(.applicationName)`, so naming the server product too would put two product names in one spoken sentence — the sort of "Cirruscope … Nextcloud" collision that reads as though they were the same thing. The surrounding context carries it instead, exactly as the intent's own `App` parameter does without naming a brand. Where a surface offers no such context — a Spotlight result, or the parameter's type in the Shortcuts app — the server product *is* named; see `ServerAppEntity`.
///
/// `ServerAppIndexer` calls `updateAppShortcutParameters()` whenever the app list changes so the offered options stay current. After the `KeyboardShortcut` rename, `AppShortcut` here refers unambiguously to `AppIntents.AppShortcut`.
struct ServerAppShortcuts: AppShortcutsProvider {
    /// `appShortcuts` is the list of App Shortcuts the system registers for Cirruscope.
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenServerAppIntent(),
            phrases: [
                "Open an app in \(.applicationName)",
                "Open \(.applicationName) \(\.$target)",
                "Open \(\.$target) in \(.applicationName)",
            ],
            shortTitle: "Open Nextcloud App",
            systemImageName: "cloud"
        )
    }
}
