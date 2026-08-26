// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import SwiftUI
import WidgetKit

/// `WidgetsBundle` is the extension's entry point, listing every widget the extension offers.
///
/// One bundle serves both apps: the `Widgets` target builds for macOS and iOS from the same sources (`Widgets/Widgets.xcconfig` sets `SDKROOT = auto`), so a widget added here appears on both platforms unless its own declaration says otherwise. It currently offers only `PlaceholderWidget`, the scaffolding widget.
@main
struct WidgetsBundle: WidgetBundle {
    /// `body` lists the widgets on offer, in the order the widget gallery presents them.
    var body: some Widget {
        PlaceholderWidget()
    }
}
