// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

/// `SchemaV1` is the initial versioned schema of Cirruscope's SwiftData store, exactly as it shipped in the `1.0.0` App Store build.
///
/// It is a frozen historical snapshot and must never change: its model definitions describe the store on disk for every user who installed `1.0.0`, so `CirruscopeMigrationPlan` can read that store and migrate it forward. Its models are frozen copies rather than the app's live top-level types because the live types have since evolved (the `AppShortcut` record was renamed to `KeyboardShortcut` in `SchemaV2`), and they are nested in this enum so their Swift type names (`SchemaV1.Account`, …) do not collide with the live ones while the entity names SwiftData records — `Account`, `ServerApp`, `AppShortcut` — stay exactly what the shipped store contains. Each nested model lives in its own `SchemaV1+<Model>.swift` extension file. Never edit these types or the version identifier; introduce changes in a new `SchemaV{n}` and a migration stage instead.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [Account.self, ServerApp.self, AppShortcut.self]
    }
}
