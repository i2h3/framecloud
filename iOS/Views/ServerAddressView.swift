// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AuthenticationServices
import os
import Rainmaker
import SwiftUI

///
/// Asks for the address of the Nextcloud server to connect to, and signs in against it.
///
/// It is the iOS counterpart of macOS's `ServerAddressViewController` and deliberately performs the same steps in the same order against the same shared types — `ServerAddress`, `ServerConnection`, `LoginSession`, `Keychain` — so the two platforms cannot drift on what an entered address means or on which servers are accepted. `connect()` splits along the same seam `open(_:)` does: the normalization, the field rewrite, and the disabling happen synchronously, and only the network half goes to a `Task`.
///
struct ServerAddressView: View {
    ///
    /// A sign-in failure worth showing the user, as the title and message of an alert.
    ///
    /// Cancelling the grant sheet is not one of these: it is the user's own decision and produces no alert, matching macOS.
    ///
    private struct Failure {
        ///
        /// The alert title, naming the kind of failure.
        ///
        let title: String

        ///
        /// The alert message, which is the failing error's `localizedDescription`.
        ///
        let message: String
    }

    @Environment(Store.self)
    private var store

    ///
    /// The server address as it currently stands in the text field.
    ///
    /// `connect()` overwrites it with the canonical form `ServerAddress` resolved, so the address the app is about to request is the address the user can see — the same thing `ServerAddressFormatter` does for the AppKit field.
    ///
    @State
    private var enteredAddress: String

    ///
    /// Whether a sign-in attempt is in flight, which the Connect button shows as a spinner in place of its label.
    ///
    @State
    private var isConnecting: Bool

    ///
    /// The address the HTTPS caption below the field describes, or `nil` when it describes none.
    ///
    /// This is what makes the caption survive its own arrival. Setting a flag instead cannot work: the caption appears because `connect()` rewrote the field, and any observer of that rewrite — a `didSet`, an `onChange` — fires *after* both assignments and retires the caption in the render that was meant to show it. Recording which address the caption is about has no ordering to get wrong. It is the SwiftUI counterpart of macOS keeping `typedText` beside the field's displayed value.
    ///
    @State
    private var hintedAddress: String?

    ///
    /// The failure to present, or `nil` while there is none.
    ///
    @State
    private var failure: Failure?

    ///
    /// Drives the compact layout: while the keyboard is up the wordmark and tagline step down a size and the footer
    /// links fade out, so the field and its button keep the shrunken area above the keys to themselves.
    ///
    @FocusState
    private var addressIsFocused: Bool

    ///
    /// Whether there is something to submit.
    ///
    /// This is the port of `ServerAddressViewController.updateOpenButtonEnablement()`: whitespace is trimmed before the check, so a field holding nothing but spaces offers no sign-in at all. It also closes while an attempt is in flight, which is what makes it the whole guard `connect()` needs.
    ///
    private var canConnect: Bool {
        isConnecting == false && enteredAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    ///
    /// Whether the HTTPS caption has something to explain, which is true for exactly as long as the field still holds the address it was raised for.
    ///
    private var showsSchemeHint: Bool {
        hintedAddress == enteredAddress
    }

    ///
    /// Records the sign-in flow under the `ServerAddressView` category.
    ///
    /// Static because a `View` is a value rebuilt on every parent body evaluation, and one logger per screen is enough.
    ///
    private static let logger = Logger(for: ServerAddressView.self)

    ///
    /// The app builds one of these empty; the parameters exist so the previews can show the states a preview cannot reach by actually signing in.
    ///
    init(enteredAddress: String = "", isConnecting: Bool = false, hintedAddress: String? = nil) {
        _enteredAddress = State(initialValue: enteredAddress)
        _isConnecting = State(initialValue: isConnecting)
        _hintedAddress = State(initialValue: hintedAddress)
    }

    var body: some View {
        // One pair of spacers, not three: the wordmark and the form are a single optically centered group, so the
        // screen has one deliberate 48 point gap instead of two arbitrary voids. Keyboard avoidance lifts that group
        // as a whole, which is why nothing needs to be pinned to the bottom.
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            VStack(alignment: .leading, spacing: 48) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: "Cirruscope")
                        .font(.system(size: addressIsFocused ? 28 : 40, weight: .bold))
                        .foregroundStyle(Gradient(colors: [.accent.opacity(0.75), .accent]))
                        // Still a glow, just half strength: radius 24 at full opacity haloed the glyph edges, while
                        // 0.35 alpha keeps the bloom and lets the letterforms stay crisp.
                        .shadow(color: .accent.opacity(0.35), radius: 18, x: 0, y: 0)

                    Text("Your Nextcloud experience, elevated.")
                        .font(addressIsFocused ? .subheadline : .title3)
                        // `.tertiary` lands near 1.9:1 against a white background; `.secondary` clears 4.5:1.
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    // A label, not a headline: the sentence this replaces ran to two lines at body size, competed
                    // with the wordmark for the top of the hierarchy, and pushed the field down the screen. What it
                    // used to explain is the footnote below, which is the only place that explanation is needed.
                    Text("Server address")
                        .font(.subheadline.weight(.semibold))

                    TextField("Server Address", text: $enteredAddress, prompt: Text(verbatim: "https://your.nextcloud.com"))
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .submitLabel(.go)
                        .disabled(isConnecting)
                        .focused($addressIsFocused)
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
                        .onSubmit(connect)

                    // Shown only once an address entered without a scheme of its own has actually been rewritten, so
                    // the note is present when it has something to explain — the rule `revealSchemeHint()` follows on
                    // macOS. It stays laid out either way and only fades, because inserting it used to shove the
                    // button upwards under a thumb already on its way down.
                    Text("Assuming HTTPS for a secure connection unless specified differently.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .opacity(showsSchemeHint ? 1 : 0)
                        .accessibilityHidden(showsSchemeHint == false)

                    // One labelled, full width action rather than a 26 point icon hanging off the field's trailing
                    // edge: it clears the 44 point minimum, it says what it does, and the spinner trades places with
                    // the label inside it so the row never changes size mid-attempt.
                    Button(action: connect) {
                        ZStack {
                            HStack(spacing: 8) {
                                Text("Connect")

                                Image(systemName: "arrow.right")
                            }
                            .fontWeight(.semibold)
                            .opacity(isConnecting ? 0 : 1)

                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .opacity(isConnecting ? 1 : 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    // `canConnect` already closes while an attempt is in flight, so it is the only condition here.
                    .disabled(canConnect == false)
                    .padding(.top, 16)
                }
            }
            .frame(maxWidth: 440, alignment: .leading)

            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        // Out of the centered group entirely: as a sibling of the spacers the footer took a third of the leftover
        // height with it, which is where the gap below the form came from.
        .safeAreaInset(edge: .bottom) {
            HStack {
                Link("Privacy Policy", destination: InfoPlist.privacyPolicy)

                Spacer()

                Link("Support", destination: InfoPlist.support)
            }
            .font(.footnote)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            // Legal links are not what anyone is reaching for while typing a host name.
            .opacity(addressIsFocused ? 0 : 1)
        }
        .animation(.default, value: showsSchemeHint)
        .animation(.default, value: addressIsFocused)
        // Deliberately keyed to the attempt rather than to the tap: `connect()` may decline to start one, and in that
        // case the keyboard should stay exactly where the user still needs it.
        .onChange(of: isConnecting) { _, isConnecting in
            if isConnecting {
                addressIsFocused = false
            }
        }
        .alert(
            Text(verbatim: failure?.title ?? ""),
            isPresented: Binding(get: { failure != nil }, set: {
                if $0 == false {
                    failure = nil
                }
            }),
            presenting: failure
        ) { _ in
            // No buttons of our own: SwiftUI supplies its own localized dismiss button when the actions builder is
            // empty, and there is nothing to offer here beyond acknowledging the failure.
        } message: { failure in
            Text(verbatim: failure.message)
        }
    }

    ///
    /// Normalize the entered address, show the user what it resolved to, and hand the server behind it to `signIn(to:)`.
    ///
    /// Everything that can be decided without the network happens here, synchronously, which is what makes `canConnect` a sufficient guard: `isConnecting` is already `true` by the time this returns, so a second tap in the same frame finds the door shut. macOS gets the same property from disabling its button inside `open(_:)` before the `Task`.
    ///
    private func connect() {
        guard canConnect else {
            return
        }

        let address: ServerAddress

        do {
            address = try ServerAddress(normalizing: enteredAddress)
        } catch {
            Self.logger.error("Entered server address is not usable: \(String(describing: error))")
            failure = Failure(title: String(localized: "Invalid Server Address", comment: "Alert title shown when the entered server address cannot be used to reach a Nextcloud server."), message: error.localizedDescription)
            return
        }

        // Show the resolved address before anything is requested, so a bare host name visibly becomes the `https://`
        // URL the request will use, and record it as the address the caption below the field is about.
        enteredAddress = address.displayString
        hintedAddress = address.inferredScheme ? address.displayString : nil
        isConnecting = true

        Task {
            defer {
                isConnecting = false
            }

            await signIn(to: address)
        }
    }

    ///
    /// Validate the server at `address` and, if it is supported, run Login Flow v2 against it and adopt the account the grant produced.
    ///
    /// Adopting it is what switches `ContentView` over to `NextcloudView`. Every failure either populates `failure` for the alert or, in the one case of the user dismissing the grant sheet, passes silently — that is their decision, not an error.
    ///
    private func signIn(to address: ServerAddress) async {
        let server = ServerConnection.anonymous(address: address.url)

        do {
            switch try await ServerConnection.validate(server) {
                case let .unsupported(capabilities):
                    let version = capabilities.version.string
                    Self.logger.notice("Server version \(version) is unsupported")
                    failure = Failure(title: String(localized: "Unsupported Server Version", comment: "Alert title shown when the server runs a Nextcloud version older than the app supports."), message: String(localized: "Cirruscope requires Nextcloud server version \(InfoPlist.minimumSupportedServerMajorVersion) or later. The server at “\(address.displayString)” is running version \(version).", comment: "Alert message shown when the server's Nextcloud version is too old; placeholders are the minimum supported major version, the server address, and the server's version."))

                case .supported:
                    Self.logger.info("Server supported; starting Login Flow v2")

                    guard let anchor = Self.presentationAnchor() else {
                        Self.logger.error("No window to present the authentication session from")
                        throw CirruscopeError.loginPresentationFailed
                    }

                    let result = try await LoginSession(anchor: anchor).signIn(to: server)
                    let credentials = Credentials(user: result.name, appPassword: result.password)

                    try Keychain.store(credentials, for: result.server)
                    Self.logger.info("Stored credentials and connected to \(result.server)")

                    store.account = ServerAccount(server: result.server, credentials: credentials)
            }
        } catch CirruscopeError.loginCancelled {
            Self.logger.notice("Sign-in cancelled by the user")
        } catch {
            Self.logger.error("Sign-in failed: \(error.localizedDescription)")
            failure = Failure(title: String(localized: "Could Not Reach Server", comment: "Alert title shown when the server could not be reached during sign-in."), message: error.localizedDescription)
        }
    }

    ///
    /// The window the Login Flow v2 grant sheet is anchored to, or `nil` when there is none to anchor it to.
    ///
    /// macOS hands `LoginSession` the sign-in window directly, a view controller having one. A SwiftUI `View` has no equivalent reference, so the key window of the foreground-active scene is looked up instead — which is that same window, since this screen is what the app is showing when it runs. `nil` is unreachable while the sign-in screen is on screen; `signIn(to:)` reports it as `CirruscopeError.loginPresentationFailed` rather than presenting a sheet somewhere the user cannot see it.
    ///
    private static func presentationAnchor() -> ASPresentationAnchor? {
        UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow
    }
}

#Preview("Default") {
    ServerAddressView()
        .environment(Store())
}

#Preview("Assumed HTTPS") {
    ServerAddressView(enteredAddress: "https://cloud.example.com", hintedAddress: "https://cloud.example.com")
        .environment(Store())
}

#Preview("Connecting") {
    ServerAddressView(enteredAddress: "https://cloud.example.com", isConnecting: true)
        .environment(Store())
}
