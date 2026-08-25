// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

/// `SchemaV2` is the current versioned schema of Cirruscope's SwiftData store: identical to `SchemaV1` except that the `AppShortcut` record is renamed to `KeyboardShortcut`.
///
/// Unlike the frozen `SchemaV1`, this schema references the app's live top-level `@Model` types (`Account`, `ServerApp`, `KeyboardShortcut`), so it always reflects the model definitions the rest of the app uses. `AppDatabase` builds its container from this schema, and `CirruscopeMigrationPlan` migrates a `SchemaV1` store up to it. The rename is a store-entity change (`AppShortcut` → `KeyboardShortcut`) that SwiftData cannot infer on its own, which is why the plan carries a custom stage rather than a lightweight one.
enum SchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(2, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [Account.self, ServerApp.self, KeyboardShortcut.self]
    }
}
