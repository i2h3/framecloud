// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
import Cocoa
import CoreSpotlight
import os

/// `AppDelegate`'s Spotlight continuation bridges a Spotlight result selection to the same window logic the View and Dock menus, and `OpenServerAppIntent`, use.
///
/// When a user selects a `ServerAppEntity` that `ServerAppIndexer` donated to the Spotlight index, macOS foregrounds Cirruscope and delivers a `CSSearchableItemActionType` `NSUserActivity`. App Intents does not auto-run `OpenServerAppIntent` for that selection in an AppKit app, so this recovers the selected entity's Nextcloud app id and opens it via `AppDelegate.openServerApp(_:)`.
extension AppDelegate {
    /// `openServerAppFromSpotlight(_:)` opens the server app identified by a `CSSearchableItemActionType` activity, returning whether it handled the activity.
    func openServerAppFromSpotlight(_ userActivity: NSUserActivity) -> Bool {
        logger.notice("Continuing user activity of type \"\(userActivity.activityType, privacy: .public)\"")

        guard userActivity.activityType == CSSearchableItemActionType else {
            logger.debug("User activity is not a Spotlight selection; not handling it")
            return false
        }

        guard let appID = serverAppID(from: userActivity) else {
            logger.error("Spotlight selection carried no recognizable server app id; ignoring it")
            return false
        }

        guard let app = AccountStore.shared.serverApp(forID: appID) else {
            logger.error("Spotlight-selected server app \"\(appID, privacy: .public)\" is no longer offered by the server; ignoring it")
            return false
        }

        logger.notice("Spotlight selected server app \"\(app.name, privacy: .public)\" (\(app.id, privacy: .public)); opening it")
        openServerApp(app)
        return true
    }

    /// `serverAppID(from:)` recovers the selected `ServerAppEntity`'s Nextcloud app id from a Spotlight-selection activity, preferring App Intents' `appEntityIdentifier` annotation and falling back to parsing the raw `CSSearchableItemActivityIdentifier`.
    private func serverAppID(from userActivity: NSUserActivity) -> String? {
        if let identifier = userActivity.appEntityIdentifier {
            return identifier.identifier
        }

        guard let rawIdentifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String else {
            return nil
        }

        return EntityIdentifier(activityIdentifier: rawIdentifier)?.identifier
    }
}
