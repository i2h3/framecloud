// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
import AppKit
import os

/// `OpenServerAppIntent` opens a chosen Nextcloud server app inside Cirruscope, backing the Shortcuts "Open Nextcloud App" action, the Siri phrases declared in `ServerAppShortcuts`, and activation of a `ServerAppEntity` Spotlight result.
///
/// It conforms to `OpenIntent`, and that conformance is what makes the `target` parameter usable inside an App Shortcut phrase: it is the only thing that records the `com.apple.link.systemProtocol.OpenEntity` system protocol in the app's extracted App Intents metadata, and without that entry the system does not recognise `${target}` as a phrase token — it skips every phrase template mentioning the parameter ("Skipping phrase template with an unrecognized token"), donates nothing to Siri, and a spoken phrase then merely brings the app forward. Established by building Apple's "Adopting App Intents to support system experiences" sample and diffing its metadata against this app's: its `OpenLandmarkIntent` carries that system protocol while a plain `AppIntent` records an empty `systemProtocols`. The second half of the requirement lives on the entity — `ServerAppEntity.typeDisplayRepresentation` must supply a `numericFormat`.
///
/// `OpenIntent` also supplies `openAppWhenRun`, so running the intent foregrounds Cirruscope, plus a default `perform()` that only opens the app. The override below is what actually navigates: it re-resolves the selected `ServerAppEntity` to a fresh `ServerAppTransferObject` through `AccountStore` — rather than trusting a possibly-stale donated entity — and hands it to `AppDelegate.openServerApp(_:)`, reusing the same focus-an-existing-window-or-open-a-new-one logic as the View and Dock menus. Apple's sample overrides `perform()` on macOS for the same reason. Every branch logs at `.notice` (misses at `.error`) with the app id in the clear, so a log capture shows exactly which app was requested and whether it opened; the logger is `static` because App Intents instantiates the intent as a plain value with a synthesized `init()`.
struct OpenServerAppIntent: OpenIntent {
    /// `title` is the action's name in the Shortcuts app.
    static let title: LocalizedStringResource = "Open Nextcloud App"

    /// `description` explains the action in the Shortcuts app. It names no app because App Intents metadata is extracted statically at build time — a runtime value such as `Bundle.main.name` cannot be embedded — and the Shortcuts app already labels every action with the owning app's name and icon.
    static let description = IntentDescription("Open a Nextcloud server app.")

    /// `logger` records intent activity under the `OpenServerAppIntent` category.
    private static let logger = Logger(for: OpenServerAppIntent.self)

    /// `target` is the server app to open, chosen from `ServerAppEntity.defaultQuery`.
    ///
    /// `OpenIntent` requires exactly this name, and the App Shortcut phrases interpolate it as `${target}`, so renaming it would both break the conformance and invalidate every localized phrase.
    @Parameter(title: "App", requestValueDialog: "Which app?")
    var target: ServerAppEntity

    /// `perform()` resolves `target` to the current app snapshot and opens it, or asks the user to pick another app when the server no longer offers it.
    @MainActor
    func perform() async throws -> some IntentResult {
        Self.logger.notice("perform: requested to open server app with id \"\(target.id, privacy: .public)\"")

        guard let app = AccountStore.shared.serverApp(forID: target.id) else {
            Self.logger.error("perform: no server app with id \"\(target.id, privacy: .public)\" is currently offered by the server; requesting a different value")
            throw $target.needsValueError()
        }

        guard let appDelegate = NSApp.delegate as? AppDelegate else {
            Self.logger.error("perform: no AppDelegate available; cannot open \"\(app.id, privacy: .public)\"")
            return .result()
        }

        Self.logger.notice("perform: resolved \"\(app.name, privacy: .public)\" (\(app.id, privacy: .public)); handing to AppDelegate.openServerApp")
        appDelegate.openServerApp(app)
        Self.logger.notice("perform: finished opening \"\(app.id, privacy: .public)\"")
        return .result()
    }
}
