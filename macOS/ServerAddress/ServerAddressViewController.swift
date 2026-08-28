// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AuthenticationServices
import Cocoa
import os
import Rainmaker

/// `ServerAddressViewController` backs the storyboard scene that asks the user for the address of the Nextcloud server they want to connect to.
///
/// It is presented by `AppDelegate` on launch when `AccountStore.serverAddress` is `nil`, validates the entered address by fetching the server's capabilities via `ServerConnection`, hands the validated server to `LoginSession` to run Nextcloud's Login Flow v2 and obtain an app password, and on success persists the address via `AccountStore.connect(to:)` and the credentials to `Keychain` before handing off to `WebViewController`.
/// `SignInModel` is its counterpart in the iOS app: a different interface over the same `ServerAddress`, `ServerConnection`, `LoginSession`, and `Keychain`.
class ServerAddressViewController: NSViewController {
    /// `progressIndicator` is the indeterminate spinner that is animated while a server is being validated and the login is in progress.
    ///
    /// `open(_:)` shows and starts it before issuing the network request and hides and stops it once the flow has completed or failed.
    @IBOutlet
    var progressIndicator: NSProgressIndicator!

    /// `serverAddressField` is the text field that captures the server address typed by the user.
    ///
    /// `open(_:)` reads its `stringValue`, sanitizes it, and disables the field while validating the resulting URL against the server.
    @IBOutlet
    var serverAddressField: NSTextField!

    /// `openButton` is the button that triggers `open(_:)` to validate the entered server address.
    ///
    /// `open(_:)` disables it while a validation request is in flight to prevent duplicate submissions.
    @IBOutlet
    var openButton: NSButton!

    /// `schemeHintLabel` is the hint under `serverAddressField` that names the HTTPS default Cirruscope applied to an address the user entered without a scheme of its own.
    ///
    /// `revealSchemeHint()` shows it and `controlTextDidChange(_:)` hides it again as soon as the user changes the address it describes. It starts hidden in the storyboard, and the activity indicator below it is anchored to its bottom edge, so its height is part of the layout whether it is visible or not and revealing it moves nothing.
    @IBOutlet
    var schemeHintLabel: NSTextField!

    /// `typedText` is the address as the user typed it, before `ServerAddressFormatter` rewrote the field to the canonical form.
    ///
    /// `controlTextDidChange(_:)` records it on every edit because it is the only value that still answers whether the user typed a scheme themselves: by the time `controlTextDidEndEditing(_:)` runs, AppKit has already validated the field through the formatter, so `serverAddressField.stringValue` carries the `https://` the app supplied and cannot be told apart from one the user typed. Should an edit ever reach the field without a change notification, the only consequence is a hint shown or withheld — never a wrong address, since `open(_:)` normalizes the field itself.
    var typedText = ""

    /// `addressFormatter` rewrites `serverAddressField` to the canonical address whenever editing in it ends, so the address the app is about to request is the address the user can see.
    ///
    /// It is attached in `viewDidLoad()` rather than in the storyboard so that this wiring reads next to the delegate assignment it belongs with, and so the formatter stays a plain object a test can build directly.
    private let addressFormatter = ServerAddressFormatter()

    /// `logger` records the sign-in flow under the `ServerAddressViewController` category.
    private let logger = Logger(for: ServerAddressViewController.self)

    override func viewDidLoad() {
        super.viewDidLoad()

        serverAddressField.delegate = self
        serverAddressField.formatter = addressFormatter
    }

    /// `open(_:)` normalizes whatever is in `serverAddressField` through `ServerAddress`, shows the user the address it resolved to, and then validates that address against the server before running Login Flow v2.
    ///
    /// The storyboard wires it to the Connect button, and the address field's own action clicks that button, so a Return in the field arrives here too — but only while the button is enabled, `NSCell.performClick(_:)` performing its action for an enabled receiver only. That is what keeps a second sign-in from starting while one is in flight, the button and the field both being disabled for its duration, and it is why the field's action deliberately goes through the button rather than straight to this method.
    @IBAction
    func open(_: Any) {
        let address: ServerAddress

        do {
            // Read the field editor while there is one: clicking Connect without committing what was typed never ends
            // editing, because a push button does not accept first responder, so `ServerAddressFormatter` has not run.
            address = try ServerAddress(normalizing: serverAddressField.currentEditor()?.string ?? serverAddressField.stringValue)
        } catch {
            logger.error("Entered server address is not usable: \(String(describing: error))")
            presentAlert(title: String(localized: "Invalid Server Address", comment: "Alert title shown when the entered server address cannot be used to reach a Nextcloud server."), message: error.localizedDescription)
            return
        }

        // Show the resolved address before anything is requested, so a bare host name visibly becomes the `https://`
        // URL the request will use even on that path. Assigning `stringValue` also ends an editing session in
        // progress, and does so by aborting it, which sends neither a delegate message nor the field's action — so
        // nothing here can re-enter this method, and editing is provably over before the field is disabled below.
        serverAddressField.stringValue = address.displayString

        if address.inferredScheme {
            revealSchemeHint()
        }

        let server = ServerConnection.anonymous(address: address.url)

        serverAddressField.isEnabled = false
        openButton.isEnabled = false
        progressIndicator.isHidden = false
        progressIndicator.startAnimation(self)

        Task {
            defer {
                serverAddressField.isEnabled = true
                updateOpenButtonEnablement()
                progressIndicator.isHidden = true
                progressIndicator.stopAnimation(self)
            }

            do {
                switch try await ServerConnection.validateAndPersist(server) {
                    case let .unsupported(capabilities):
                        let version = capabilities.version.string
                        logger.notice("Server version \(version) is unsupported")
                        presentAlert(title: String(localized: "Unsupported Server Version", comment: "Alert title shown when the server runs a Nextcloud version older than the app supports."), message: String(localized: "Cirruscope requires Nextcloud server version \(InfoPlist.minimumSupportedServerMajorVersion) or later. The server at “\(address.displayString)” is running version \(version).", comment: "Alert message shown when the server's Nextcloud version is too old; placeholders are the minimum supported major version, the server address, and the server's version."))

                    case .supported:
                        logger.info("Server supported; starting Login Flow v2")

                        // The Connect button that got here lives in this window, so it is on screen; a controller
                        // without one has nothing to anchor the grant sheet to and says so rather than presenting
                        // the sheet somewhere the user cannot see it.
                        guard let window = view.window else {
                            throw CirruscopeError.loginPresentationFailed
                        }

                        let result = try await LoginSession(anchor: window).signIn(to: server)
                        try Keychain.store(Credentials(user: result.name, appPassword: result.password), for: result.server)
                        AccountStore.shared.connect(to: result.server)
                        logger.info("Stored credentials and connected to \(result.server)")
                        (NSApp.delegate as? AppDelegate)?.presentWebViewWindow()
                        view.window?.close()

                        if let authenticated = ServerConnection.authenticated(address: result.server) {
                            await ServerConnection.refreshNavigationApps(using: authenticated)
                        }
                }
            } catch CirruscopeError.loginCancelled {
                logger.notice("Sign-in cancelled by the user")
            } catch {
                logger.error("Sign-in failed: \(error.localizedDescription)")
                presentAlert(title: String(localized: "Could Not Reach Server", comment: "Alert title shown when the server could not be reached during sign-in."), message: error.localizedDescription)
            }
        }
    }

    /// `updateOpenButtonEnablement()` keeps the Connect button enabled only while the address field holds something other than whitespace to submit.
    ///
    /// `controlTextDidChange(_:)` calls it while the user edits, and `open(_:)` calls it again once a sign-in attempt has finished, so the single enablement rule lives in one place rather than being restated by the unconditional re-enable it replaced. Whitespace is trimmed before the check because this button also gates the field's Return action, `NSCell.performClick(_:)` performing its action for an enabled receiver only, so a field holding nothing but spaces must offer no sign-in at all.
    func updateOpenButtonEnablement() {
        let enteredText = serverAddressField.currentEditor()?.string ?? serverAddressField.stringValue

        openButton.isEnabled = enteredText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    /// `revealSchemeHint()` shows the hint that HTTPS was assumed for an address entered without a scheme, and announces it once to assistive applications.
    ///
    /// `controlTextDidEndEditing(_:)` calls it once AppKit has run `ServerAddressFormatter` over the committed address, and `open(_:)` calls it for the one submission path that never ends editing. The label then stays visible until the next edit hides it, because the assumption it explains stays true for as long as that address is in the field.
    /// The announcement is posted only when the label was not already showing, and for the application element as `NSAccessibilityAnnouncementRequestedNotification` requires, so a VoiceOver user hears the reason for a rewrite they cannot otherwise perceive once rather than on every commit. Its text is the label's own, which keeps both wordings in one place and in one string catalog entry.
    func revealSchemeHint() {
        guard schemeHintLabel.isHidden else {
            return
        }

        logger.debug("Assumed HTTPS for an address entered without a scheme")

        schemeHintLabel.isHidden = false

        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested, userInfo: [.announcement: schemeHintLabel.stringValue, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    /// `presentAlert(title:message:)` reports a failure of the sign-in flow as a warning alert.
    ///
    /// It is presented as a sheet on the view's window where there is one — every caller runs while the Server Address window is on screen — and falls back to a modal alert otherwise, so a failure is never swallowed just because the window has already gone away.
    private func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning

        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
