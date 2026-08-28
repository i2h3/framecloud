// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os

extension Logger {
    /// `init(for:)` creates a logger for `type`, using the main bundle identifier as the subsystem and `type`'s unqualified name as the category.
    ///
    /// Every behavioural type holds its own `Logger(for: Self.self)`, so `log stream` and Instruments group log entries by the type that emitted them; `String(describing:)` yields the bare type name (e.g. "WebViewController") rather than a module-qualified one, and the subsystem falls back to the app's known bundle identifier only if `Bundle.main.bundleIdentifier` is unexpectedly `nil`.
    /// It is `nonisolated` so it can initialise loggers on `nonisolated` and non-main-actor declarations as well as main-actor ones.
    nonisolated init(for type: Any.Type) {
        self.init(subsystem: Bundle.main.bundleIdentifier ?? "de.i2h3.cirruscope", category: String(describing: type))
    }
}
