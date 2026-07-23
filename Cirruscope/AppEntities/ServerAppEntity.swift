// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
import CoreSpotlight

/// `ServerAppEntity` is the App Intents projection of a Nextcloud server app, exposing it to Spotlight, Siri, and the Shortcuts app as a discoverable, openable entity.
///
/// It is a value-type snapshot bridged from the `ServerAppTransferObject` DTO that `AccountStore` vends, never a managed `@Model` object, so it can cross into the App Intents machinery freely. `ServerAppEntityQuery` produces and resolves these, `OpenServerAppIntent` opens the one the user picks, and — because it is an `IndexedEntity` — `ServerAppIndexer` donates the current set to the on-device Spotlight index.
///
/// It holds the DTO and derives its `id` and `name` from it, so that `name` can be an `@ComputedProperty` bound to the Spotlight `displayName` indexing key. That binding is what publishes a declared entity *property* in the app's extracted App Intents metadata: an entity whose `properties` array is empty gives Siri nothing to match a spoken app name against, and every entity Apple's "Adopting App Intents to support system experiences" sample uses as an App Shortcut phrase parameter declares its display name this way.
struct ServerAppEntity: IndexedEntity {
    /// `defaultQuery` is the query the App Intents system uses to enumerate, resolve, and suggest these entities.
    static let defaultQuery = ServerAppEntityQuery()

    /// `typeDisplayRepresentation` is the human-readable name of this entity type, shown wherever the Shortcuts app names the kind of value.
    ///
    /// The `numericFormat` is not decoration: every entity and enum Apple's sample uses as an App Shortcut phrase parameter supplies one. `synonyms` widen what a spoken phrase may call the type; a bare "app" is deliberately not among them, being too generic to match on without dragging in unrelated utterances.
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(
            name: "Nextcloud server app",
            numericFormat: "\(placeholder: .int) Nextcloud server apps",
            synonyms: ["Nextcloud app", "server app"]
        )
    }

    /// `app` is the value snapshot this entity projects; `id` and `name` are derived from it.
    var app: ServerAppTransferObject

    /// `id` is the Nextcloud app id (e.g. `"files"`): stable across relaunches and the store's rebuild-recovery, identical to `ServerAppTransferObject.id`, and the key `AppDelegate.openServerApp(_:)` matches on — so it is safe to donate to Spotlight and to persist inside a saved Shortcut.
    var id: String {
        app.id
    }

    /// `name` is the app's localized display name (e.g. `"Files"`), declared as an entity property bound to Spotlight's `displayName` so Siri and Spotlight know which value carries the spoken name.
    @ComputedProperty(title: "Name", indexingKey: \.displayName)
    var name: String {
        app.name
    }

    /// `displayRepresentation` is how a single entity appears in Spotlight results, the Shortcuts parameter picker, and Siri.
    ///
    /// The subtitle names the server product rather than repeating the word "app": the title is already an app name, and in Spotlight — where a result carries no other context — "Nextcloud" is the one piece of information that says what the entry actually is. It deliberately does not say "Cirruscope": these are the connected server's apps, not this app's own.
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "Nextcloud")
    }

    /// `attributeSet` is the Spotlight metadata donated for this entity: it starts from `defaultAttributeSet` so it keeps the `displayRepresentation`'s title and subtitle, and adds `keywords` so a search such as "Nextcloud Notes" matches even though the title is only the bare app name.
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.keywords = ["Nextcloud", name]
        return attributes
    }

    /// `init(_:)` bridges a `ServerAppTransferObject` snapshot into an entity, keeping the DTO itself free of any App Intents dependency.
    init(_ app: ServerAppTransferObject) {
        self.app = app
    }
}
