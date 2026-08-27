// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

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
