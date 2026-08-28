// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AuthenticationServices
import Foundation
import os
import Rainmaker

/// `LoginSession` runs Nextcloud's Login Flow v2 against one server: it presents the grant page in an `ASWebAuthenticationSession` and concurrently polls the login endpoint until the user completes the grant.
///
/// One instance drives one sign-in attempt.
///
/// The whole flow is platform-agnostic except for the window the sheet is anchored to, which is why that is the one thing the caller supplies. `ASPresentationAnchor` is `NSWindow` on macOS and `UIWindow` on iOS, so the initializer's signature needs no `#if` of its own. The caller resolves it, rather than this type reaching for a key window itself: on macOS the right window is the specific one the sign-in scene is in, not whichever is frontmost, and each caller already knows which that is. A caller with no window to offer cannot sign in and reports `CirruscopeError.loginPresentationFailed` itself, which is why nothing here is optional.
@MainActor
final class LoginSession: NSObject {
    /// `anchor` is the window the grant sheet is presented from, returned as-is by `presentationAnchor(for:)`.
    private let anchor: ASPresentationAnchor

    /// `authenticationSession` retains the `ASWebAuthenticationSession` that presents the Login Flow v2 grant page while polling is in progress.
    ///
    /// `startAuthenticationSession(using:)` assigns it, and `dismissAuthenticationSession()` cancels it once polling has produced credentials or stopped.
    private var authenticationSession: ASWebAuthenticationSession?

    /// `authenticationCancelled` is set by the `ASWebAuthenticationSession` completion handler when the user dismisses the grant sheet, signaling `pollForCredentials(on:flow:)` to stop.
    private var authenticationCancelled = false

    /// `logger` records the sign-in flow under the `LoginSession` category.
    private let logger = Logger(for: LoginSession.self)

    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
    }

    /// `signIn(to:)` runs Nextcloud's Login Flow v2 against `server` and returns the credentials the grant produced.
    ///
    /// Login Flow v2 never invokes the session's `nc` callback URL, so a successful `server.poll(_:token:)` is what signals completion; the session is then dismissed by the `defer`. It throws `CirruscopeError.loginCancelled` if the user dismisses the sheet and `CirruscopeError.loginTimedOut` if the grant is not completed in time.
    func signIn(to server: Server) async throws -> LoginResult {
        let flow = try await server.login()

        defer {
            dismissAuthenticationSession()
        }

        try startAuthenticationSession(using: flow.entry)

        return try await pollForCredentials(on: server, flow: flow)
    }

    /// `startAuthenticationSession(using:)` presents `url` in an `ASWebAuthenticationSession` so the user can authenticate and grant access.
    ///
    /// The session is retained in `authenticationSession`. Because Login Flow v2 never invokes the `nc` callback, the completion handler only fires when the user dismisses the sheet, which sets `authenticationCancelled` so `pollForCredentials(on:flow:)` stops. It throws `CirruscopeError.loginPresentationFailed` if the session cannot be presented.
    private func startAuthenticationSession(using url: URL) throws {
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "nc", completionHandler: makeAuthenticationCompletionHandler())

        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = true

        authenticationCancelled = false
        authenticationSession = session

        guard session.start() else {
            logger.error("Could not present the authentication session")
            throw CirruscopeError.loginPresentationFailed
        }
    }

    /// `makeAuthenticationCompletionHandler()` builds the completion handler `startAuthenticationSession(using:)` passes to its `ASWebAuthenticationSession`.
    ///
    /// It is `nonisolated` so the closure it returns is not itself inferred main-actor-isolated: `LoginSession` is main-actor-isolated, so a closure written directly inside one of its methods would inherit that isolation too — even though its body only creates a `Task` — and trip the very isolation check this handler exists to avoid, since `AuthenticationServices` does not guarantee it invokes the handler on the main thread (it is invoked off-main when `dismissAuthenticationSession()` calls `cancel()` right after polling succeeds).
    private nonisolated func makeAuthenticationCompletionHandler() -> (URL?, (any Error)?) -> Void {
        { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.logger.debug("Authentication sheet dismissed by the user")
                self?.authenticationCancelled = true
            }
        }
    }

    /// `pollForCredentials(on:flow:)` polls `server`'s login endpoint until the user completes the grant, returning the resulting credentials.
    ///
    /// While the grant is pending the endpoint yields no result and `server.poll(_:token:)` throws, so every failure is treated as "keep polling". It stops with `CirruscopeError.loginCancelled` if the user dismisses the sheet and `CirruscopeError.loginTimedOut` after a few minutes without completion.
    private func pollForCredentials(on server: Server, flow: LoginFlow) async throws -> LoginResult {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(300))

        while clock.now < deadline {
            try Task.checkCancellation()

            if authenticationCancelled {
                throw CirruscopeError.loginCancelled
            }

            if let result = try? await server.poll(flow.endpoint, token: flow.token) {
                logger.debug("Sign-in granted; received credentials")
                return result
            }

            try await Task.sleep(for: .seconds(1))
        }

        logger.error("Sign-in timed out after 300 seconds")
        throw CirruscopeError.loginTimedOut
    }

    /// `dismissAuthenticationSession()` cancels and releases the `ASWebAuthenticationSession`, dismissing the grant sheet once the login has completed, failed, or been cancelled.
    private func dismissAuthenticationSession() {
        authenticationSession?.cancel()
        authenticationSession = nil
    }
}

/// `LoginSession`'s conformance to `ASWebAuthenticationPresentationContextProviding` anchors the Login Flow v2 grant sheet to whichever window the caller named.
extension LoginSession: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }
}
