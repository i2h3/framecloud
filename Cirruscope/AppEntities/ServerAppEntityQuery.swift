// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
import os

/// `ServerAppEntityQuery` supplies `ServerAppEntity` values to the App Intents system: it enumerates every server app the connected account offers, resolves ids back to entities, and matches them by name.
///
/// It is a main-actor consumer of `AccountStore.shared` — symmetric with `AppDelegate` and `ServerAppsViewController`, which also read `AccountStore.serverApps` — mapping the DTOs the store vends into entities via `ServerAppEntity.init(_:)`. Conforming to all three query protocols mirrors the `LandmarkEntityQuery` in Apple's "Adopting App Intents to support system experiences" sample, which is likewise `@MainActor`: `allEntities()` powers the Shortcuts parameter picker, `suggestedEntities()` the suggestions, `entities(for:)` resolves a donated or saved id through `AccountStore.serverApp(forID:)`, and `entities(matching:)` matches what the user types or says.
///
/// Each call logs its outcome at `.notice` with counts and ids in the clear so Spotlight/Siri/Shortcuts interactions are reconstructable from a log capture; the logger is `static` because App Intents instantiates the query as a plain value with a synthesized `init()`.
@MainActor
struct ServerAppEntityQuery: EntityQuery, EntityStringQuery, EnumerableEntityQuery {
    /// `logger` records query activity under the `ServerAppEntityQuery` category.
    private static let logger = Logger(for: ServerAppEntityQuery.self)

    /// `allEntities()` is every server app the connected account currently offers.
    func allEntities() async throws -> [ServerAppEntity] {
        let entities = AccountStore.shared.serverApps.map(ServerAppEntity.init)
        Self.logger.notice("allEntities: returning \(entities.count, privacy: .public) server-app entities [\(entities.map(\.id).joined(separator: ", "), privacy: .public)]")
        return entities
    }

    /// `suggestedEntities()` is what Siri and the Shortcuts app offer without the user typing anything; the whole app list is short enough to suggest in full.
    func suggestedEntities() async throws -> [ServerAppEntity] {
        let entities = AccountStore.shared.serverApps.map(ServerAppEntity.init)
        Self.logger.notice("suggestedEntities: returning \(entities.count, privacy: .public) server-app entities")
        return entities
    }

    /// `entities(for:)` resolves each requested app id back to an entity, silently dropping ids the server no longer offers.
    func entities(for identifiers: [ServerAppEntity.ID]) async throws -> [ServerAppEntity] {
        let entities = identifiers.compactMap { identifier in
            AccountStore.shared.serverApp(forID: identifier).map(ServerAppEntity.init)
        }

        Self.logger.notice("entities(for:): resolved \(entities.count, privacy: .public) of \(identifiers.count, privacy: .public) requested id(s) [\(identifiers.joined(separator: ", "), privacy: .public)]")
        return entities
    }

    /// `entities(matching:)` is every server app whose name contains `string`, case-insensitively.
    func entities(matching string: String) async throws -> [ServerAppEntity] {
        let entities = AccountStore.shared
            .serverApps
            .filter { $0.name.localizedCaseInsensitiveContains(string) }
            .map(ServerAppEntity.init)

        Self.logger.notice("entities(matching:): \(entities.count, privacy: .public) match(es) for query \"\(string, privacy: .public)\"")
        return entities
    }
}
