// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
import os

/// `AccentColorMonitor` watches the two system inputs that can change the accent color Cirruscope forwards into its web views — the accent-color preference itself and the light/dark appearance — and posts `Notification.Name.accentColorDidChange` so every open `WebViewController` re-resolves and re-applies its own value.
///
/// `AppDelegate.applicationDidFinishLaunching(_:)` calls `start()` once, before any web window is presented. It is a single process-wide monitor rather than a pair of observations per web window because several `WebViewController` instances can be alive at once, and because `NSColor.systemColorsDidChangeNotification` can fire more than once for a single accent change: installing the observations once and fanning the result out over `NotificationCenter` keeps that multiplication out of the window count, the same way `AccountStore` fans out `appearanceSettingsDidChange`.
/// It also absorbs the one piece of uncertainty in this area. `NSSystemColorsDidChangeNotification` has no documented delivery queue, so the observer here is `nonisolated` and hops to the main actor itself, and `accentColorDidChange` is posted from the main actor — which lets `WebViewController.observeAccentColor()` be a plain selector-based observer with no concurrency ceremony of its own.
/// The monitor deliberately does not resolve the color. `NSColor.controlAccentColor` resolves differently under each `NSAppearance`, so each `WebViewController` resolves it against its own web view's `effectiveAppearance` through `WebAccentColor.effective(in:)`.
@MainActor
final class AccentColorMonitor: NSObject {
    /// `shared` is the process-wide monitor, retained for the app's lifetime so a single object owns the two system observations.
    static let shared = AccentColorMonitor()

    /// `logger` records accent-color and appearance change activity under the `AccentColorMonitor` category; it is `nonisolated` so the `nonisolated` observers can log through it.
    nonisolated let logger = Logger(for: AccentColorMonitor.self)

    /// `appearanceObservation` retains the key-value observation of `NSApplication.effectiveAppearance` that reports light/dark switches, whether the user flips the setting in System Settings or macOS switches automatically at sunset.
    ///
    /// `start()` assigns it, and it is released when the monitor is deallocated, which ends the observation; it is also the flag `start()` checks to stay idempotent. The application is observed rather than an individual view because the appearance is a process-wide input, and the block-based observation is used rather than `addObserver(_:forKeyPath:options:context:)` so releasing the token balances the registration — a manual registration would have to be removed in `deinit`, which is `nonisolated` under Swift 6, and a missed removal would leave a dangling observer on the process-lifetime `NSApplication`.
    private var appearanceObservation: NSKeyValueObservation?

    /// `start()` installs both system observations: the key-value observation of `NSApplication.effectiveAppearance` for light/dark switches, and the `NSColor.systemColorsDidChangeNotification` observer for accent- and highlight-color changes.
    ///
    /// Two observations are needed because neither covers both triggers. An accent-color change does not alter the effective appearance's name, and AppKit tracks it through a separate invalidation path; `NSColor.systemColorsDidChangeNotification` is posted after AppKit has reset its own color caches, so `NSColor.controlAccentColor` already resolves to the new value by the time the observer runs. The distributed `AppleColorPreferencesChangedNotification` is deliberately not used: it is receivable under the App Sandbox, but it is posted before the in-process color cache is invalidated, so an observer of it reads the previous color, and it is the notification that stopped reporting accent changes reliably on macOS 26. `NSControlTintDidChangeNotification` is no use either — its enumeration only distinguishes blue, graphite, and clear, so it cannot tell "Multicolor" from "Blue", which is exactly the distinction that decides whether the app's own `AccentColor` asset applies.
    /// The order the two are registered in does not matter: they are independent inputs, and re-applying an unchanged accent color rewrites identical attribute and property values, so a single user action reaching both costs nothing visible. `AppDelegate.applicationDidFinishLaunching(_:)` calls this before the first web window exists, and the notification observer needs no explicit removal — `NotificationCenter` drops selector-based observers when the observing object is deallocated, and this monitor lives for the process lifetime regardless.
    func start() {
        guard appearanceObservation == nil else {
            return
        }

        logger.info("Starting accent color monitor")
        appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance, options: [], changeHandler: makeEffectiveAppearanceChangeHandler())
        NotificationCenter.default.addObserver(self, selector: #selector(systemColorsDidChange), name: NSColor.systemColorsDidChangeNotification, object: nil)
    }

    /// `makeEffectiveAppearanceChangeHandler()` builds the key-value observation change handler `start()` registers on `NSApplication.effectiveAppearance`.
    ///
    /// It is `nonisolated` for the same reason as `WebViewController.makeTitleChangeHandler()`: so the closure it returns is not itself inferred main-actor-isolated and does not trip a dynamic isolation check should AppKit deliver this callback off the main thread instead of hopping to the main actor as the handler does.
    ///
    /// Nothing crosses the hop. The observation is registered with an empty option set so no value is snapshotted, and neither `NSApplication` nor `NSAppearance` is `Sendable`. The hop is load-bearing rather than incidental: when the application's `effectiveAppearance` changes, the individual views' `effectiveAppearance` has not necessarily propagated yet at the moment the observation fires, so a web view resolved inside this callout could still answer for the previous appearance — by the next main-actor turn the change has moved through the view tree.
    private nonisolated func makeEffectiveAppearanceChangeHandler() -> @Sendable (NSApplication, NSKeyValueObservedChange<NSAppearance>) -> Void {
        { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                logger.debug("Effective appearance changed; announcing accent color change")
                announceAccentColorChange()
            }
        }
    }

    /// `systemColorsDidChange()` handles `NSColor.systemColorsDidChangeNotification`, which AppKit posts once it has invalidated its own color caches.
    ///
    /// It is `nonisolated` and hops internally, following `UserNotifier`'s delegate methods, because AppKit does not document which queue this notification is delivered on: a main-actor-isolated `@objc` method would trap rather than merely misbehave if it ever changed. No delay is needed before reading the new color, unlike with the distributed notification `start()` documents rejecting.
    @objc
    private nonisolated func systemColorsDidChange() {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            logger.debug("System colors changed; announcing accent color change")
            announceAccentColorChange()
        }
    }

    /// `announceAccentColorChange()` posts `Notification.Name.accentColorDidChange` so every open `WebViewController` re-applies the appearance to its live web view.
    private func announceAccentColorChange() {
        NotificationCenter.default.post(name: .accentColorDidChange, object: nil)
    }
}
