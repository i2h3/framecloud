// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `Settings` provides typed accessors for the app's statically configured `Info.plist` values.
///
/// The connected account's data — the server address, theming, version, apps, and keyboard shortcuts — is no longer kept here: it lives in SwiftData behind `AccountStore`, which persists it in the shared App Group container. `Settings` now exposes only the build-time configuration the app reads from its `Info.plist`, none of which is user-mutable.
enum Settings {
    /// `InfoPlistKey` collects the string keys under which `Settings` reads statically configured values from the app's `Info.plist`.
    private enum InfoPlistKey {
        /// `minimumSupportedServerMajorVersion` is the key for the `Info.plist` entry that backs `Settings.minimumSupportedServerMajorVersion`.
        static let minimumSupportedServerMajorVersion = "MinimumSupportedNextcloudMajorVersion"

        /// `privacyPolicy` is the key for the `Info.plist` entry that backs `Settings.privacyPolicy`.
        static let privacyPolicy = "PrivacyPolicy"

        /// `supportURL` is the key for the `Info.plist` entry that backs `Settings.supportURL`.
        static let supportURL = "SupportURL"
    }

    /// `minimumSupportedServerMajorVersion` is the lowest Nextcloud major version the app accepts.
    ///
    /// `ServerAddressViewController` consults this value after fetching the server's capabilities via `Rainmaker` and rejects servers running an older major release.
    static var minimumSupportedServerMajorVersion: Int {
        guard let value = Bundle.main.object(forInfoDictionaryKey: InfoPlistKey.minimumSupportedServerMajorVersion) else {
            preconditionFailure("Info.plist is missing the \"\(InfoPlistKey.minimumSupportedServerMajorVersion)\" entry.")
        }

        if let intValue = value as? Int {
            return intValue
        }

        if let stringValue = value as? String, let intValue = Int(stringValue) {
            return intValue
        }

        preconditionFailure("Info.plist entry \"\(InfoPlistKey.minimumSupportedServerMajorVersion)\" must be an integer or a string representing one but was \(type(of: value)).")
    }

    /// `privacyPolicy` is the URL of Cirruscope's online privacy policy.
    ///
    /// `AppDelegate.openPrivacyPolicy(_:)` opens it in the user's default browser when the user chooses the Help-menu item or the button on `ServerAddressViewController`.
    static var privacyPolicy: URL {
        guard let value = Bundle.main.object(forInfoDictionaryKey: InfoPlistKey.privacyPolicy) else {
            preconditionFailure("Info.plist is missing the \"\(InfoPlistKey.privacyPolicy)\" entry.")
        }

        guard let stringValue = value as? String, let url = URL(string: stringValue) else {
            preconditionFailure("Info.plist entry \"\(InfoPlistKey.privacyPolicy)\" must be a string representing a valid URL but was \(value).")
        }

        return url
    }

    /// `supportURL` is the URL of Cirruscope's online support page.
    ///
    /// `AppDelegate.openSupportPage(_:)` opens it in the user's default browser when the user chooses the Help-menu item.
    static var supportURL: URL {
        guard let value = Bundle.main.object(forInfoDictionaryKey: InfoPlistKey.supportURL) else {
            preconditionFailure("Info.plist is missing the \"\(InfoPlistKey.supportURL)\" entry.")
        }

        guard let stringValue = value as? String, let url = URL(string: stringValue) else {
            preconditionFailure("Info.plist entry \"\(InfoPlistKey.supportURL)\" must be a string representing a valid URL but was \(value).")
        }

        return url
    }
}

extension Notification.Name {
    /// `serverAppsDidChange` is posted by `AccountStore` whenever the server apps or their shortcuts change so `AppDelegate` can rebuild the View and Dock menus.
    static let serverAppsDidChange = Notification.Name("ServerAppsDidChange")

    /// `downloadsDidChange` is posted by `DownloadManager` whenever its `downloads` list or a download's state changes so `DownloadViewController` can reload its table.
    static let downloadsDidChange = Notification.Name("DownloadsDidChange")

    /// `downloadDidStart` is posted by `DownloadManager` when a new transfer begins so `AppDelegate` can open and bring the Downloads window to the foreground.
    static let downloadDidStart = Notification.Name("DownloadDidStart")

    /// `unreadNotificationCountDidChange` is posted by `NotificationMonitor` whenever the unread server-notification count changes so other parts of the app can react without reaching into the monitor.
    static let unreadNotificationCountDidChange = Notification.Name("UnreadNotificationCountDidChange")

    /// `serverCredentialsRejected` is posted by `NotificationMonitor` when its event stream reports the stored app password was revoked so `AppDelegate` can clear the keychain and require a new sign-in.
    static let serverCredentialsRejected = Notification.Name("ServerCredentialsRejected")

    /// `appearanceSettingsDidChange` is posted by `AccountStore` whenever the account's appearance settings (translucency, remove-gaps) change so every open `WebViewController` re-applies them to its live web view without a reload.
    static let appearanceSettingsDidChange = Notification.Name("AppearanceSettingsDidChange")

    /// `accentColorDidChange` is posted by `AccentColorMonitor` whenever the macOS accent color or the light/dark appearance changes so every open `WebViewController` re-resolves the accent color for its own web view and forwards it into the page without a reload.
    ///
    /// It is the system-driven counterpart to `appearanceSettingsDidChange`, which carries the account's own appearance settings; both funnel into `WebViewController.reapplyAppearance()`.
    static let accentColorDidChange = Notification.Name("AccentColorDidChange")
}
