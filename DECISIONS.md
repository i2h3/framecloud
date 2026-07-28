<!--
SPDX-FileCopyrightText: 2026 Iva Horn
SPDX-License-Identifier: MIT
-->

# Design Decisions

A technical FAQ of the design and architecture choices behind Cirruscope, and the reasoning for each — from the maintainer's perspective. It records *why* the project is built the way it is, complementing [AGENTS.md](./AGENTS.md), which covers *how* to work in the codebase. It is the developer-facing counterpart to the public [FAQ on the website](./Website/support.html); where a decision also shapes the public story, such as supported platforms or features, that page carries the polished version.

Entries are edited freely. This file is version-controlled, so its history lives in git — when a decision changes, the answer is simply updated or removed rather than annotated with its past.

## Why AppKit and not SwiftUI?

Cirruscope is a thin native frame around Nextcloud's web interface, so nearly all of its own user interface is macOS chrome: the menu bar, document-like web windows, the Dock menu, window restoration, and standard keyboard handling. AppKit lets the app reach all of that directly, whereas SwiftUI's macOS scene model abstracts exactly these away. Two areas make the choice concrete rather than a matter of taste.

**Window chrome and lifecycle.** The web windows are a custom `NSWindow` subclass ([`Cirruscope/Web/WebWindow.swift`](./Cirruscope/Web/WebWindow.swift)) with a transparent, title-hidden, full-size-content title bar so Nextcloud's UI extends under the chrome — and the subclass then repositions the traffic-light buttons by hand (`standardWindowButton(.closeButton / .miniaturizeButton / .zoomButton)` in `repositionControlButtons()`), re-running on every relayout and stepping aside in fullscreen. The same class overrides `performKeyEquivalent(with:)` to claim ⌃⌘S for "Show/Hide Sidebar" *before* the event reaches the embedded `WKWebView`, because Nextcloud Talk's own JavaScript would otherwise swallow it (issue #59). Window state restoration is hand-written as well: `AppDelegate` is the `restorationClass`, each window encodes its URL through `encodeRestorableState(with:)` and carries a UUID identity, and at launch the restored windows are reconciled against stored credentials and the server's supported version before being shown. Manipulating the standard window buttons, intercepting a key equivalent above the content view, and gating per-window restoration on app state all sit outside what SwiftUI's `WindowGroup`/`Window` scenes expose.

**The embedded web view.** SwiftUI gained a native `WebView` and observable `WebPage` in macOS 26, but as of that release it does not surface the WebKit APIs Cirruscope depends on. Two the app uses today have no equivalent there:

- **Downloads.** Every transfer is driven through `WKDownloadDelegate` / `WKDownload` — choosing a non-clobbering destination in `~/Downloads`, observing its `Progress`, cancelling, and deliberately moving the delegate onto an app-wide `DownloadManager` so a transfer survives the window that started it ([`Cirruscope/Downloads/`](./Cirruscope/Downloads/)). `WebPage` ships no download support at all — no `WKDownload`, no download events — so the download manager would have nothing to attach to.
- **New windows from web content.** `WKUIDelegate`'s `webView(_:createWebViewWith:for:windowFeatures:)` ([`Cirruscope/Web/WebViewController+WKUIDelegate.swift`](./Cirruscope/Web/WebViewController+WKUIDelegate.swift)) turns `window.open()` / `target="_blank"` into a real new Cirruscope window for the same host, or hands external links to the system browser. `WebPage` exposes no `createWebViewWith`-style hook.

Where the new API *does* cover a need — navigation policy via `WebPage.NavigationDeciding`, JavaScript dialogs and the file-upload panel via `WebPage.DialogPresenting`, and even the JavaScript-to-native bridge through the `WKUserContentController` it still exposes — Cirruscope simply predates it and already leans on the mature `WKNavigationDelegate` / `WKUIDelegate` / `WKScriptMessageHandler` model. But the download and new-window gaps are hard blockers, not conveniences, so hosting the web view in AppKit stays the right call.

## Why wrap Nextcloud's web interface in a `WKWebView` instead of building the UI natively?

Nextcloud's functionality — Files, Talk, Calendar, Mail, and every other app — lives server-side as web applications that evolve with each server release. Reimplementing any of it natively would be an enormous, never-finished effort that would always lag the server and break as it changes. And the payoff would be slight: the web interface already delivers the full feature set competently, so a native rebuild would spend disproportionate, frankly unreasonable effort duplicating what already works for barely any user-visible benefit. Hosting the web interface in a `WKWebView` means Cirruscope always shows the real, current Nextcloud, and the native shell contributes only what the web UI *cannot*: OS integration such as downloads, notifications, the Dock badge, and system keyboard shortcuts.

## Why macOS only, and not iOS (for now)?

Focus. Cirruscope's value is deep, macOS-specific native integration, and doing that well for one platform with a single maintainer is already a full effort — the build targets macOS only and relies on macOS-only APIs throughout. Nextcloud already ships its own iOS client, so the gap Cirruscope fills is on the Mac. This is deliberately "for now" not "never."

## Why Apple platforms only (no Windows or Linux)?

The entire point of the project is being deeply native to Apple's platform technologies. A Windows or Linux version would not be a port — it would be a separate project built from the ground up, sharing essentially none of the native integration that gives Cirruscope its reason to exist. That is out of scope for the resources available, and on Linux especially, Nextcloud's own web interface already works well in any browser.

## Why SwiftData with value-type DTOs behind a main-actor store?

Persistence uses SwiftData rather than Core Data or a third-party store, for a modern, first-party model with low ceremony and an explicitly versioned schema. Because the app builds with complete strict concurrency, `@Model` objects are never passed across actor boundaries: a single main-actor store is the sole gateway to the container and hands out `Sendable` value-type data transfer objects, so the rest of the app works with safe, inert value types rather than live managed objects. See the persistence layer for the store and schema.

## Why ad-hoc code signing by default?

The checked-in build signs ad-hoc (`CODE_SIGN_IDENTITY = -`, no team, no provisioning profile) so that a fresh clone, a fork, or CI can build and link with no Apple Developer account installed at all. The project previously required the maintainer's own real credentials for every build, which is exactly why CI itself could not build. A real "Apple Development" identity, and the entitlement-backed capabilities that need it, are opted into locally through a gitignored `Local.xcconfig`. See [AGENTS.md → Building and Signing](./AGENTS.md#building-and-signing) for the mechanics.

## Why is App Transport Security disabled (arbitrary loads allowed)?

`Info.plist` sets `NSAllowsArbitraryLoads = true`. Cirruscope connects to whatever Nextcloud server the user runs, and self-hosted instances are commonly reached over plain HTTP, a self-signed certificate, or a `.local`/LAN hostname. ATS's default policy would refuse those connections outright, making the app unusable for a large part of its audience. The trade-off — giving up ATS's blanket transport guarantees — is accepted deliberately, because the destination is a server the user chose and controls.

## Why strict Swift 6 concurrency with no default main-actor isolation?

The app builds with `SWIFT_STRICT_CONCURRENCY = complete` and no default actor isolation, so main-actor isolation is always explicit rather than assumed. This is a correctness decision: Cirruscope lives among WebKit, AppKit, and authentication callbacks that do not all run on the main thread, and a closure that merely *looks* main-actor-isolated because of where it is written caused a real production crash when the framework invoked it off the main thread. The codebase therefore standardizes on forming such closures in `nonisolated` factory methods that hop explicitly to the main actor. See [AGENTS.md → Concurrency](./AGENTS.md#concurrency) for the pattern and the specific fix.

## Why are only parts of the app unit-tested?

The app splits into two halves, and only one of them repays unit testing. The native half holds real decision logic that is pure input-to-output — whether two keyboard shortcuts mean the same keystroke, how one renders as symbolic text, how the store derives its snapshots — and that code is both cheap to test and demonstrably in need of it: the rule for comparing key equivalents was subtly wrong in a way that reading it never revealed. The WebKit half is the opposite. Navigation policy, downloads, injected JavaScript, and notification bridging only mean anything against a live Nextcloud server in a real web view, so a test there buys little beyond "the delegate fired" while costing a server fixture, network flakiness, and permanent maintenance. Those paths are verified by hand against a real server, with the app's own `os` logging as the record.

Tests are therefore expected wherever logic is Swift-only and server-free, and deliberately absent around WebKit — a deliberate scope, not a backlog. One habit comes out of the same work and generalizes: where the app depends on undocumented framework behaviour, the test measures the framework rather than restating the belief, so [`KeyEquivalentMatchingOracleTests`](./CirruscopeTests/KeyboardShortcuts/KeyEquivalentMatchingOracleTests.swift) asks a real `NSMenu` what it matches and holds [`ShortcutMatching`](./Cirruscope/ShortcutMatching.swift) to that answer. See [AGENTS.md → Testing](./AGENTS.md#testing) for the mechanics.

## Why is a keyboard shortcut another app already uses rejected rather than moved?

Recording a combination that a different Nextcloud server app — or one of Cirruscope's own menu items — already holds is refused, naming the occupant, instead of quietly transferring it. Two enabled menu items sharing one key equivalent have no reliable, documented tie-break in AppKit, so accepting the second assignment would leave one of the two unreachable and give the user no way to tell which. Refusing in place keeps the menu bar unambiguous and puts the explanation where the user is already looking. Transferring was considered and rejected: a shortcut silently disappearing from another app's row is a worse surprise than a keystroke that visibly declines to take.

Shortcuts stored before that check existed can still collide, and those are honoured for the first app in menu order while showing as unassigned for the other, rather than being deleted. A duplicate is something the user once entered deliberately, so the app declines to destroy it behind their back and merely stops applying it; clearing or re-recording the winner hands the combination back. See [`AccountStore.shortcut(forAppID:)`](./Cirruscope/Persistence/AccountStore.swift).
