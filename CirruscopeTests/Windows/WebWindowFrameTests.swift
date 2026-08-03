// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
@testable import Cirruscope
import Testing

/// `WebWindowFrameTests` covers `WebWindowFrame`, which remembers how large the user last made a web window so the next one opens at that size (issue #82).
///
/// Two things are worth pinning, and only one of them is the app's own arithmetic. `isRecordable(styleMask:)` is the pure rule that a fullscreen frame is not a window's own geometry and must never be remembered. Everything else rests on `NSWindow.saveFrame(usingName:)` and `setFrameUsingName(_:)`, whose behaviour the app assumes rather than implements — so the round-trip case measures those two against a *second, freshly created* window rather than restating a belief about them, per AGENTS.md → "When the code assumes something about a framework, test the framework". Alongside that it asserts what `WebWindowFrame` adds on top: the origin survives, because `AppDelegate.present(windowController:sender:)` owns positioning and a remembered position would compete with its cascade.
///
/// The fullscreen rule is pinned at that pure function and nowhere else, deliberately. Reaching it through a real window means setting `.fullScreen` on the style mask by hand, and AppKit refuses outright — `-[NSWindow setStyleMask:]` raises `NSGenericException` with "NSWindowStyleMaskFullScreen set on a window outside of a full screen transition", which crashes the whole test run rather than failing one case. Actually entering fullscreen is no way around it either: it is animated and asynchronous, and it would put the machine running the tests into fullscreen. Splitting the rule out as a function over a style mask is what leaves it testable at all.
///
/// Every case passes its own `name`, so no two contend for one stored frame, and none of them is `WebWindowFrame.defaultName` — writing that would overwrite the size the developer running the tests last left a real web window at. `removeStoredFrame(named:)` clears the key afterwards so a run leaves `UserDefaults` as it found it, which is also what lets the "nothing remembered yet" case be meaningful on a machine that has run these tests before.
@MainActor
@Suite(.serialized)
struct WebWindowFrameTests {
    /// `removeStoredFrame(named:)` deletes the `UserDefaults` entry AppKit keeps a named frame in, returning the domain to the state a machine that had never saved that name would be in.
    ///
    /// The key shape — `NSWindow Frame <name>` — is AppKit's, undocumented as a format but stable for decades and the only way to undo a `saveFrame(usingName:)`, `NSWindow` offering no removal counterpart. A case that relies on the key being absent asserts that it is, so this going stale would surface as that case failing rather than as silent leakage.
    private func removeStoredFrame(named name: String) {
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(name)")
    }

    /// `makeWindow(frame:)` builds a titled, resizable, closable window at `frame`, matching the style mask the storyboard's "Web Window" scene declares.
    ///
    /// It deliberately builds a plain `NSWindow` rather than a `WebWindow`: the subclass repositions the standard window buttons on every layout pass and hosts a `WKWebView` through the storyboard, none of which this facility touches.
    private func makeWindow(frame: NSRect) -> NSWindow {
        NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    }

    @Test(arguments: [
        // The storyboard's own mask for the web window, and the same mask once macOS has taken it fullscreen.
        (NSWindow.StyleMask([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]), true),
        (NSWindow.StyleMask([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView, .fullScreen]), false),
        // A bare mask either way, so the rule is shown to turn on `.fullScreen` alone rather than on any of its company.
        (NSWindow.StyleMask([.borderless]), true),
        (NSWindow.StyleMask([.fullScreen]), false),
    ])
    func `A frame is worth remembering unless the window is in fullscreen`(styleMask: NSWindow.StyleMask, isRecordable: Bool) {
        #expect(WebWindowFrame.isRecordable(styleMask: styleMask) == isRecordable)
    }

    @Test
    func `A recorded size is applied to a later window while its position is left alone`() {
        let name = "WebWindowFrameTests.RoundTrip"
        removeStoredFrame(named: name)
        defer { removeStoredFrame(named: name) }

        let recorded = makeWindow(frame: NSRect(x: 120, y: 140, width: 900, height: 650))
        WebWindowFrame.record(recorded, name: name)

        // A second, separately created window, so what is measured is the frame actually making it through
        // `UserDefaults` and back rather than anything the first window still holds in memory.
        let applied = makeWindow(frame: NSRect(x: 300, y: 320, width: 1200, height: 800))
        let originBeforeApplying = applied.frame.origin
        WebWindowFrame.applySize(to: applied, name: name)

        #expect(applied.frame.size == recorded.frame.size)
        #expect(applied.frame.origin == originBeforeApplying)
    }

    @Test
    func `A window keeps its storyboard size while no size has been remembered`() {
        let name = "WebWindowFrameTests.NothingRemembered"
        removeStoredFrame(named: name)
        defer { removeStoredFrame(named: name) }

        let window = makeWindow(frame: NSRect(x: 300, y: 320, width: 1200, height: 800))
        let frameBeforeApplying = window.frame
        WebWindowFrame.applySize(to: window, name: name)

        #expect(window.frame == frameBeforeApplying)
    }
}
