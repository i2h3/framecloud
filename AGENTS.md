<!--
SPDX-FileCopyrightText: 2026 Iva Horn
SPDX-License-Identifier: MIT
-->

#  AGENTS.md

You are an experienced software engineer specialized on native apps for macOS written in Swift using AppKit.

## Repository Structure

- `Cirruscope/` contains the Swift source code, resources, and configuration for the app target.
    - `AppDelegate/` contains `AppDelegate.swift`, the application delegate that owns the web windows and builds the server-app items in the View and Dock menus, and its window-restoration and provide-feedback extensions.
    - `Web/` contains `WebViewController` with its `WKNavigationDelegate`, `WKUIDelegate`, and menu-validation extensions, the `WebWindow`/`WebWindowController` that host it, and `WebViewScript.swift`, which enumerates the bundled JavaScript resources and loads their source from the bundle on demand.
    - `Downloads/` contains the download feature: `DownloadManager.swift` is the `WKDownloadDelegate` facility that coordinates every transfer decoupled from the UI, `DownloadManager+WKDownloadDelegate.swift` is its delegate conformance, `Download.swift` is the runtime model of a single transfer, and `DownloadViewController` with its table data-source and delegate extensions and `DownloadTableCellView` presents the download history.
    - `Settings/` contains `Settings.swift`, which defines the app's persisted settings, the general and server-apps settings view controllers with their table extensions, and `ShortcutRecorderView`.
    - `ServerAddress/` contains `ServerAddressViewController` with its text-field-delegate and web-authentication extensions used to sign in.
    - `Views/` contains custom views shared across features, such as `BackgroundImageView`.
    - `Models/` contains the shared value types: `Credentials` (the login name and app password from Login Flow v2), `CirruscopeError` (the shared error type thrown by app-level facilities), `ServerAppTransferObject` (a value snapshot of a Nextcloud server app shown in the menus and settings), and `KeyboardShortcutTransferObject` (a value snapshot of a user-assigned keyboard shortcut for a server app). These are the `Sendable` data transfer objects `AccountStore` vends in place of its SwiftData records; they carry no business logic.
    - `Persistence/` contains the SwiftData stack: `AppDatabase` (owns the process-wide `ModelContainer` in the shared App Group container and opens it through the migration plan), `AccountStore` (the `@MainActor` repository that is the sole reader and writer of the connected account's data and maps its `@Model` records to the value types in `Models/`), the versioned schemas `SchemaV1` (a frozen snapshot of the schema shipped in `1.0.0`, whose model copies are nested in the enum via per-model `SchemaV1+<Model>.swift` extension files) and `SchemaV2` (the current schema, referencing the live models), `CirruscopeMigrationPlan` (the custom `SchemaV1`→`SchemaV2` migration that renames the `AppShortcut` record to `KeyboardShortcut` without losing users' keyboard shortcuts), and `Models/` with the current `@Model` records: `Account`, `ServerApp`, and `KeyboardShortcut`.
    - `AppEntities/` contains the App Intents entity types and their queries that project persisted data for Spotlight, Siri, and the Shortcuts app: `ServerAppEntity` (a Nextcloud server app) and `ServerAppEntityQuery`.
    - `AppIntents/` contains the App Intents themselves and their supporting types: `OpenServerAppIntent` (opens a server app in a web window), `ServerAppShortcuts` (the `AppShortcutsProvider` declaring the Siri phrases), and `ServerAppIndexer` (donates the entities to Spotlight and refreshes the App Shortcut parameters when the app list changes).
    - `AssetCache.swift` manages on-disk copies of remote assets in the app's caches directory.
    - `Keychain.swift` stores the Login Flow v2 credentials in the macOS Keychain.
    - `Logging.swift` adds the `Logger(for:)` and `OSSignposter(for:)` convenience initializers that every behavioural type uses to build its own `os` logger and signposter under the app's bundle-identifier subsystem, categorized by type name.
    - `ShortcutMatching.swift` defines when two key equivalents mean the same keystroke to AppKit, the single comparison both the reserved-shortcut lookup in `AppDelegate` and the duplicate-shortcut lookups in `AccountStore` use.
    - `ServerConnection.swift` builds and validates `Rainmaker.Server` instances and fetches the server apps.
    - `UserNotifier.swift` presents notifications from the web interface, and download-completion notifications from `DownloadManager`, in the macOS Notification Center.
    - `Assets.xcassets` contains image and color assets.
    - `AppIcon.icon` is the app icon bundle.
    - `Base.lproj/Main.storyboard` defines the app's user interface; its strings are localized through `mul.lproj/Main.xcstrings`, a String Catalog covering German, French, and Spanish.
    - `Cirruscope.css` is the stylesheet injected into the web view.
    - `Scripts/` contains the JavaScript resources injected into or evaluated within the web view.
    - `Info.plist` is the app's information property list, and `PrivacyInfo.xcprivacy` is its privacy manifest. The user-facing usage descriptions macOS shows in its permission prompts are not in that file — they come from the target's `INFOPLIST_KEY_*` build settings and are localized through `InfoPlist.xcstrings`, a String Catalog covering German, French, and Spanish.
- `CirruscopeTests/` contains the app's unit tests (see "Testing" below), grouped into one subfolder per feature domain, alongside the target's own `CirruscopeTests.xcconfig`.
    - `KeyboardShortcuts/` covers the keyboard shortcut domain: the shortcut-matching and display-string suites, the `ShortcutFixture` corpus they share, and `KeyEquivalentProbe`, the AppKit oracle one of them measures against.
    - `Account/` covers the connected account's stored data: the app-upsert, shortcut-assignment, duplicate-suppression, and account-lifecycle suites, the `ServerAppFixture` corpus they share, and `AccountStoreHarness`, which gives each case its own `AccountStore` over an in-memory SwiftData container. The app-upsert suite also covers the order `AccountStore.serverApps` lists the apps in, that order being a property of the snapshot rather than of any one menu.
- `Frameworks/` contains the bundled frameworks the app links against.
- `Products/` contains the built app bundle.
- `.github/ISSUE_TEMPLATE/` contains the GitHub issue forms for feature requests, bug reports, and the blank issue entry point.
- `.github/workflows/` contains the GitHub Actions workflows used for DCO checks, formatting, website checks, REUSE compliance, unit tests and CI builds (`test.yml`, which runs the tests and then a Release build — it replaced the former build-only `build.yml`), and release SBOM generation.
- `DECISIONS.md` is the project's design-decisions FAQ: a plain-language record of why key architecture and product choices were made, maintained per the "Design Decisions" instructions below.

## Code Style

- This project is set up to use SwiftFormat.
- Every type declarations must reside in its own source code file.
- Every type declaration must have a documentation comment.
- Every property declaration must have a documentation comment.
- Documentation comments should also explain how the documented type or property relates to other symbols in the project.
- Documentation comments should have one empty line at their top and their bottom each.
- Documentation comments must not wrap at a fixed column count but when a sentence is finished. Line lengths do not matter in documentation comments. A full sentence should always be written into a single line.
- Never wrap arguments in func declarations or calls.
- Instead of declaring multiple values in a single guard-let statement, write one dedicated guard-let statement per value.
- Always run `swiftformat .` in the project root directory after applying changes.
- Do not place business or user interface logic into data transfer objects.

## Building and Signing

- Code signing defaults to ad-hoc: `Cirruscope.xcconfig` sets `CODE_SIGN_IDENTITY = -`, `CODE_SIGN_STYLE = Automatic`, and carries no `DEVELOPMENT_TEAM`, and neither `Cirruscope/Cirruscope.xcconfig` nor `CirruscopeTests/CirruscopeTests.xcconfig` sets `CODE_SIGN_ENTITLEMENTS` — so a fresh clone, a fork, or CI (`.github/workflows/test.yml`) builds, tests, and links with no Apple Developer account, certificate, or provisioning profile installed at all. This is deliberate (since commit `4d7db7f`): the project used to require the maintainer's own real credentials for every build, which is exactly why CI itself couldn't build. Both per-target xcconfigs do name a `PROVISIONING_PROFILE_SPECIFIER` (`Cirruscope` and `Cirruscope Tests`), which is inert under ad-hoc signing and needs no local counterpart — verified by building and testing a clone with no `Local.xcconfig` present.
- `Cirruscope/Cirruscope.entitlements`' App Group and Keychain-sharing capabilities need a real, provisioned certificate to sign — ad-hoc signing cannot embed them — so the default/CI build carries none of them and cannot verify that those capabilities work end to end. It does verify that the app **runs** without them, because `test.yml`'s test action launches it: the App Sandbox is still active in an ad-hoc build (it comes from `ENABLE_APP_SANDBOX`, not from the entitlements file), so the shared App Group container is unreachable, and both users of it fall back to a location private to the build — `AppDatabase.container` opens the store in the app's own container, `AssetCache` caches into its own caches directory. Keychain items need no entitlement either way; they use the app's default access group.
- Because of that, anything new that makes *launch* depend on an entitlement now fails CI as a test failure rather than surfacing later as a fork's crash. This is not theoretical: the store previously called `preconditionFailure` when it could not open in the App Group container, so an ad-hoc build built fine and then trapped during `applicationDidFinishLaunching(_:)` — reproducible locally by testing with a group container that does not exist yet, `xcodebuild test … CIRRUSCOPE_BASE_BUNDLE_IDENTIFIER=de.i2h3.cirruscope.citest`, which is the closest thing to a fresh runner. Reach for that command when a change touches the App Group, the sandbox, or anything opened at launch.
- To build and run with those capabilities, and with a real "Apple Development" identity, copy `Local.xcconfig.example` to `Local.xcconfig` next to it (gitignored, never committed — this is where the maintainer's own team ID and profile now live, not in the tracked xcconfig files) and fill in your own team. `Cirruscope.xcconfig` includes it last (`#include? "Local.xcconfig"`), so its `CODE_SIGN_IDENTITY`, `CODE_SIGN_STYLE`, `DEVELOPMENT_TEAM`, `PROVISIONING_PROFILE_SPECIFIER`, and `CODE_SIGN_ENTITLEMENTS` assignments override the ad-hoc defaults above for local builds only.
- If a build fails with a signing error, that means a `Local.xcconfig` is present and pointing at a team, profile, or certificate this machine doesn't actually have installed — fix it there, or remove the file to fall back to the ad-hoc default. Either way, that is not something to fix by editing `Cirruscope.xcconfig`/`Cirruscope/Cirruscope.xcconfig`'s checked-in defaults, which must stay ad-hoc so everyone else (including CI) keeps building.

## Testing

The `CirruscopeTests` target holds unit tests written with **Swift Testing** (`import Testing`, `@Test`, `#expect`) — not XCTest. It is hosted by the app (`TEST_HOST`/`BUNDLE_LOADER`), so tests reach the app's internal types through `@testable import Cirruscope` and may touch AppKit directly. `Cirruscope.xcodeproj/xcshareddata/xcschemes/Cirruscope.xcscheme` is committed so the scheme's test action is the same everywhere rather than depending on the per-user scheme Xcode autocreates (`xcuserdata` is gitignored).

```bash
xcodebuild test -project Cirruscope.xcodeproj -scheme Cirruscope -configuration Debug -destination 'platform=macOS'
```

In Xcode, Product ▸ Test (⌘U) with the `Cirruscope` scheme selected runs exactly the same suites; the command line above is what CI uses and what to use from a terminal session. Debug is not incidental either way: `@testable import` needs the testability that the Release configuration does not enable.

**What to test.** Swift-only logic that can be exercised without a live Nextcloud server or a web view — shortcut matching and its conflict rules, display-string rendering, DTO derivations, pure helpers and pure decision functions. When a change adds or alters logic of that kind, add or update its tests in the same change, without being asked.

**What not to test, and why.** The WebKit-facing half of the app — navigation policy, downloads, injected scripts, notification bridging — is not unit-tested: it needs a real server, a real `WKWebView`, and real network conditions, so tests there are slow, flaky, and assertion-poor compared with what they cost to maintain. That behaviour is verified by hand against a live server instead (see "Retrieving logs to research a bug"). Do not add a test whose only assertion is that a WebKit delegate was called.

**When the code assumes something about a framework, test the framework.** A unit test that restates an assumption cannot catch the assumption being wrong, and this project has a scar to prove it: the shortcut comparison was built on a documented-sounding but false claim about which modifier bits AppKit matches key equivalents against. `KeyEquivalentProbe` therefore drives real `NSMenu.performKeyEquivalent(with:)`, and `KeyEquivalentMatchingOracleTests` asserts that `ShortcutMatching.areEquivalent(_:_:)` agrees with it for every pair of a shared fixture corpus. Prefer that shape — measure the framework, then assert the app agrees — over encoding a belief twice.

**Conventions.**

- Tests live in a subfolder of `CirruscopeTests/` named after the feature domain they cover (`KeyboardShortcuts/`), never loose at the target's root, so the target stays navigable as domains accumulate. Name the folder after the domain rather than after the app source folder the code happens to sit in, since one domain's logic is typically spread across several of those. The target's file group is file-system synchronized, so a new subfolder needs no project-file change — creating it is enough.
- The same one-type-per-file and documentation rules as the app's source apply to test files: a suite is a type, so it gets its own file and a documentation comment explaining what it covers and why the suite exists at all.
- Share fixtures through a named type (`ShortcutFixture`) instead of copying a corpus between suites, so two suites cannot silently drift apart on what they cover, and use `@Test(arguments:)` for matrices rather than hand-unrolled cases.
- Annotate a suite `@MainActor` when it touches AppKit (`NSMenu`, view types), and add `.serialized` where cases would otherwise contend for the main actor.
- SwiftFormat rewrites `@Test("A display name")` into a backtick-quoted function name (`func \`A display name\`()`). That is the project's configured style — write the sentence, run `swiftformat .`, and leave the result alone.
- Tests must not contribute localized strings: `CirruscopeTests/CirruscopeTests.xcconfig` sets `SWIFT_EMIT_LOC_STRINGS = NO`, so the string-catalog completeness check stays about the app's own strings. Never wrap a test's literal in `String(localized:comment:)`.

**Testing the account store.** `AccountStore` takes its `ModelContainer` at initialization: `shared` passes `AppDatabase.container`, and the suites in `CirruscopeTests/Account/` pass an in-memory one built by `AccountStoreHarness`, one harness per test case. Two rules keep that safe and must stay observed, since nothing enforces them mechanically. Never name `AccountStore.shared` from a test — its container lives in the shared App Group container and holds the developer's real account, and `AppDatabase.container`'s recovery path *deletes* the store files on a failed open. Never build a second store over `AppDatabase.container` either: each instance memoizes the single `Account` separately, so two of them over one container would each believe a stale answer.

The store's two reaches outside itself are injected as plain closures with production defaults — no protocols, no mock types, no `#if DEBUG` — because the test bundle is hosted by the app, which changes what a test may assume. `isReservedShortcut` wraps `AppDelegate.reservedShortcutName(for:)`, which answers from the live `NSApp.mainMenu`: the real menu bar is loaded for the whole test run, so a case using ⌘Z would be measuring `Main.storyboard` rather than the store. `notifyServerAppsDidChange` wraps the `Notification.Name.serverAppsDidChange` post, which `AppDelegate` observes for the whole run, so a test write would otherwise have it rebuild the live View menu from `AccountStore.shared` on a main-queue turn no test controls; the harness counts announcements instead, which is also the only way to assert one at all, the production post being deliberately asynchronous.

`AccountStore.persist(serverApps:)` takes the app's own `ServerAppTransferObject`, not `Rainmaker.NavigationItem`; the mapping lives in `ServerConnection.refreshNavigationApps(using:)`. Keep it that way — it is what lets a test seed an app list without `CirruscopeTests` linking Rainmaker, which it deliberately does not. Note also that the host app opens a store of its own during every test run regardless (`applicationDidFinishLaunching(_:)` → `rebuildServerAppsMenu()` → `AccountStore.shared.serverApps`) — the developer's real one on a provisioned machine, the per-build fallback under ad-hoc signing on CI; that is pre-existing and expected, not a regression. What matters is that no test *writes* through it, which a run confirms by leaving the store file's modification time untouched.

**Deliberately untested in the store.** `disconnect()`'s two side effects: `AssetCache.shared.clear()` deletes the developer's real cached assets and `Keychain.clearAll()` their real credentials. Its storage half is `deleteAccount()`, and that is covered — cascade delete, memoization reset, announcement. `persist(theming:)` likewise stays out: it downloads through `AssetCache.shared` into the real App Group caches directory on every call (the logo unconditionally, even when the background is a plain colour), and its `Rainmaker.Theming` input cannot be built without linking Rainmaker. Covering the one piece of real logic in it — resolving a server-root-relative background against the account's address, and skipping that when `backgroundPlain` is set — means extracting that resolution into a pure function first; do that when it next changes rather than as a detour.

## REUSE Compliance

This project is checked for [REUSE](https://reuse.software/) Specification 3.3 compliance by `.github/workflows/reuse.yml` (`fsfe/reuse-action@v6`): every file must carry SPDX copyright and license metadata, either as an inline header or as an entry in `REUSE.toml`.

- The convention throughout the project is `SPDX-FileCopyrightText: <year> Iva Horn` and `SPDX-License-Identifier: MIT`, written as the two-line header appropriate to the file's comment syntax (`//` for Swift/JavaScript, `/* */` for CSS and `.strings`, `<!-- -->` for HTML/Markdown, `#` for shell-style configs like `.gitignore` and `.swiftformat`), placed at the very top of the file with a blank line before the rest of its content. `<year>` is the year the file was actually created — never hardcode the current year as a blanket constant, since files created in different years must carry different years, including ones added long after this instruction was written:
  ```bash
  # Year a new file is created: use the current year.
  # Year an existing file predating SPDX coverage was created: check when
  # its content first appeared, treating a delete-then-recreate at the same
  # path as a fresh creation (its year, not the original's):
  git log --follow --format=%ad --date=format:%Y -- <path> | tail -1
  ```
- Files that cannot safely hold an inline comment — binaries, pure JSON, or anything Xcode/SwiftPM/Icon Composer regenerates or rewrites through its own GUI or tooling (the asset catalog, the `AppIcon.icon` bundle, `project.pbxproj`, `contents.xcworkspacedata`, `Package.resolved`, `Main.storyboard`, `Info.plist`, `PrivacyInfo.xcprivacy`, `Localizable.xcstrings`, `.swift-version`) — are covered by a `[[annotations]]` entry in `REUSE.toml` instead. Add new files of these kinds to an existing matching `path` glob there only if its year already matches, or a new annotation block otherwise; never hand-edit an SPDX comment into them.
- `.github/PULL_REQUEST_TEMPLATE.md` is one exception: GitHub pre-fills a new pull request's description textarea with this file's raw, unrendered content, so an inline HTML comment header would show up as literal visible clutter for every contributor opening a PR — it is covered by a `REUSE.toml` entry instead, even though Markdown normally takes an inline header.
- Whenever a change adds a new file, give it SPDX coverage immediately — an inline header or a `REUSE.toml` entry — rather than leaving it for later.
- Always run `reuse lint` in the project root directory after applying changes (install via `brew install reuse` if missing), and confirm it reports "Congratulations! Your project is compliant with version 3.3 of the REUSE Specification" before considering the change complete.

## Documentation Instructions

- Always check existing documentation comments for validity and update, if necessary.
- Whenever the files and folders within the repository change, update the "Repository Structure" section of this document accordingly.
- Always check `./Website` for necessary updates in regard to localization, feature description, changes in supported target platforms, Nextcloud server releases or Nextcloud server apps.

## Design Decisions

`DECISIONS.md` is a technical FAQ recording *why* the project is built the way it is — its design and architecture choices and the reasoning behind each. It complements this document, which covers *how* to work in the codebase, and is the developer-facing counterpart to the public FAQ on `./Website`.

- Whenever a change makes, changes, or reverses a non-obvious or hard-to-reverse choice — a UI framework, target platform, dependency, persistence layer, or authentication flow, or a deliberate decision *not* to build something — add or update the matching entry in `DECISIONS.md` without being asked.
- Write each entry as a plain-language `## Why …?` question followed by a short answer that explains the reasoning and the trade-off accepted, matching the FAQ style of the existing entries.
- Do not record routine implementation details or bug fixes — only choices with lasting design consequence. Nothing enforces this mechanically the way `reuse lint` enforces licensing; it relies on recognizing when a change embodies a decision, so err toward recording it when unsure.
- When a decision changes, edit or remove its answer rather than preserving the old text — the file is version-controlled, so its history lives in git.
- Keep the reasoning consistent wherever it also appears: if a decision is likewise explained in a Swift documentation comment, `README.md`, or elsewhere in this document, update those together, and, per "Documentation Instructions" above, check `./Website` when a decision affects the public story such as supported platforms or features.

## Localization Instructions

English is the app's base (development) language, and the project is additionally localized into a set of languages configured in the Xcode project. Do not hardcode or assume that set — detect the enabled localizations programmatically so this workflow keeps working as languages are added or removed.

The localization stores are now String Catalogs, so there are no more per-locale `.lproj` resource folders to enumerate for this (only `Base.lproj`, the source, and `mul.lproj` — "multiple languages" — which holds the storyboard's catalog file itself, not a per-language folder). The canonical, and now only, source for the enabled locales is `knownRegions` in the project file; read it directly, filtering out `en` and `Base`, which are not translation targets:

```bash
plutil -convert json -o - Cirruscope.xcodeproj/project.pbxproj \
  | python3 -c 'import sys, json; d = json.load(sys.stdin); print([r for r in [o["knownRegions"] for o in d["objects"].values() if o.get("isa") == "PBXProject"][0] if r not in ("en", "Base")])'
```

Localization lives in four String Catalogs (JSON, all with the same shape: each key maps to a `comment` plus a `localizations` dict of `<locale>: {"stringUnit": {"state": ..., "value": ...}}`), and all of them must stay complete for every detected localization:

- **Swift strings** are wrapped in `String(localized:comment:)` — never hardcoded — and backed by `Cirruscope/Localizable.xcstrings`. Each key is the literal source string. App Intents strings (a `LocalizedStringResource` such as an intent title/description, a `@Parameter` title or `requestValueDialog`, or an entity's `DisplayRepresentation` subtitle / `TypeDisplayRepresentation`) resolve from the same `Localizable` table and so live in this catalog too; their keys are likewise the literal source string, but they take no `comment:` argument in code, so add the catalog comment by hand.
- **Storyboard strings** in `Cirruscope/Base.lproj/Main.storyboard` are backed by `Cirruscope/mul.lproj/Main.xcstrings` (migrated off the old per-locale `Main.strings` files — do not reintroduce those). Each key is `<objectID>.<property>`, e.g. `"5xm-BD-bvl.title"`, and the `comment` field still carries the generated `Class = …; title = …; ObjectID = …;` context Xcode always regenerates from the storyboard's current content.
- **Info.plist strings** — the usage descriptions macOS shows in its permission prompts — are backed by `Cirruscope/InfoPlist.xcstrings`. Here each key is the property-list key name (e.g. `NSCameraUsageDescription`), *not* the English text, so unlike the other catalogs this one carries an explicit `en` `stringUnit` as well. Its English source of truth is the matching `INFOPLIST_KEY_*` build setting on the Cirruscope target, set identically in both the Debug and Release configuration: change one and mirror it in the catalog's `en` value and in the other configuration. These prompts name no brand — neither the "Nextcloud" trademark nor "Cirruscope" — and describe the capability generically instead ("during video calls", not "during Nextcloud Talk calls"). That restriction is specific to these prompts: `Localizable.xcstrings` deliberately names both where the message is *about* the server product, as in "Cirruscope requires Nextcloud server version %lld or later."
- **App Shortcut phrases** declared in `ServerAppShortcuts` are backed by `Cirruscope/AppShortcuts.xcstrings` (the `AppShortcuts` table Xcode extracts from the `AppShortcutsProvider`). Xcode collapses every phrase variation into a single key whose localizations are a `stringSet` — a list of `values` rather than one `value` — so a translation must supply the whole set, one entry per source phrase and in the same order. Each phrase's `${applicationName}` and `${target}` placeholders must be preserved verbatim, and every phrase must contain `${applicationName}`.

In all four catalogs, a `stringUnit`'s — or, for App Shortcut phrases, a `stringSet`'s — `state` is the completeness/staleness signal Xcode itself tracks: a freshly added or changed source string starts at `"new"` for each locale and only reaches `"translated"` once a value is filled in, and Xcode flags a locale for re-review on its own when the source text changes later. **`state` alone is necessary but not sufficient, though** — proven the hard way: migrating off the old per-locale `Main.strings` files carried every existing value straight into the catalog and marked it `"translated"` per locale, even for the ~130 entries that were never actually translated and were just sitting there as English text. So also compare each locale's value against the `en` value, and treat a match as a real gap *unless* the key is a deliberately English/unchanged case — the brand name (`Cirruscope`), a placeholder example URL, a storyboard object whose text is fully overwritten at runtime and never shown (see the placeholder-skipping rule below), or a genuine cognate where that language's correct word simply is spelled the same (e.g. French `Services`/`Format`/`Ligatures`, German `Text`, Spanish `General` are all correct translations, not oversights):

```bash
plutil -convert json -o - Cirruscope.xcodeproj/project.pbxproj | python3 -c '
import json, sys

pbxproj = json.load(sys.stdin)
known_regions = next(o["knownRegions"] for o in pbxproj["objects"].values() if o.get("isa") == "PBXProject")
locales = [r for r in known_regions if r not in ("en", "Base")]

for catalog in ["Cirruscope/Localizable.xcstrings", "Cirruscope/mul.lproj/Main.xcstrings", "Cirruscope/InfoPlist.xcstrings", "Cirruscope/AppShortcuts.xcstrings"]:
    data = json.load(open(catalog))
    for key, entry in data["strings"].items():
        if entry.get("shouldTranslate") is False:
            continue  # e.g. a pure format passthrough like "%@", marked Don't Translate
        localizations = entry.get("localizations", {})
        en_value = localizations.get("en", {}).get("stringUnit", {}).get("value")
        for locale in locales:
            loc = localizations.get(locale, {})
            # App Shortcut phrases localize as a `stringSet` (a set of spoken variations) rather than a single
            # `stringUnit`, and a numeric format (e.g. an entity type's `numericFormat`) as plural `variations`.
            unit = loc.get("stringUnit") or loc.get("stringSet") or {}
            if not unit:
                plural = loc.get("variations", {}).get("plural", {})
                units = [v.get("stringUnit", {}) for v in plural.values()]
                if units and all(u.get("state") == "translated" for u in units):
                    continue  # every plural category is translated
                unit = units[0] if units else {}
            state, value = unit.get("state"), unit.get("value")
            if state != "translated":
                print(f"{catalog}: {key!r} [{locale}] state={state!r}")
            elif value is not None and en_value is not None and value == en_value:
                print(f"{catalog}: {key!r} [{locale}] still identical to English: {value!r} (confirm this is a deliberate exception, not a missed translation)")
'
```

Run this after applying any change, not only when you believe you recognize that a user-facing string was added, renamed, or removed — that recognition is exactly what failed before this project migrated off per-locale `Main.strings` files (a storyboard menu item's title was renamed without updating its stale, plain-text translations, and it shipped unnoticed for several changes). It is a mechanical safety net, not a substitute for judgement: a clean run only rules out the two failure modes above — it cannot tell you whether an existing translation reads *well*, so still apply the checklist below by hand for every string you touch, and use judgement on every "still identical to English" hit rather than mechanically translating deliberate exceptions.

Whenever a change adds, renames, or removes a user-facing string — in Swift, in the storyboard, or in an `INFOPLIST_KEY_*` usage description — check and update every catalog without being asked, so no localization is left behind:

- Add an entry for every new user-facing string, translated into each detected localization, to the relevant catalog. Keep the English source wording on the storyboard's Base object and as the `Localizable.xcstrings` key.
- Remove or rename entries whose source strings were deleted or changed, so no stale or orphaned keys remain and no localization is missing a key another one has.
- Only translate strings the user actually sees. Skip storyboard placeholders that are replaced at runtime (a label bound to an outlet and assigned in code, such as a cell's file-name field) and image-only button titles that are never displayed, unless the title also serves as the control's accessibility label.
- Match the established scope: the standard AppKit menu titles Xcode emits into the storyboard catalog are left untranslated by convention, so do not translate every entry — only the app's own user-facing strings.
- Never localize developer-facing text: `os` log and signpost messages stay in English (see "Logging and Diagnostics").
- Confirm the app still builds so both string catalogs compile.

## Concurrency

Cirruscope builds with `SWIFT_STRICT_CONCURRENCY = complete` (`Cirruscope.xcconfig`) and no default actor isolation, so nothing in the app module is `@MainActor` unless the SDK or the code says so explicitly — there is no implicit "everything defaults to the main actor" convenience to lean on.

- Types that subclass `NSResponder` — `NSViewController`, `NSWindowController`, `NSView` (and their subclasses like `NSTableCellView`) — already inherit `@MainActor` from the SDK itself (`NS_SWIFT_UI_ACTOR` is annotated on `NSResponder`), so they need no annotation of their own.
- Plain `NSObject` subclasses (with no `NSResponder` in their hierarchy) get no such inheritance: annotate the type `@MainActor` explicitly whenever it touches AppKit/WebKit state that requires it, as `AppDelegate` and `DownloadManager` do.
- A closure handed to a system completion-handler or callback API is only guaranteed to run on the main actor if that API's closure *parameter type* itself is annotated `@MainActor` by the SDK (e.g. `WKNavigationDelegate`'s decision handlers). When it isn't (e.g. `ASWebAuthenticationSession`'s completion handler, `NSEvent.addLocalMonitorForEvents`'s handler, KVO change handlers), never assume the calling thread.
- **A closure written directly inside a method of a main-actor type is itself inferred main-actor-isolated, purely from being lexically nested there — regardless of what its body does.** Wrapping the body in `Task { @MainActor in ... }` does *not* fix this: the compiler still inserts a dynamic isolation check at the *outer* closure's own entry point (the same mechanism as `MainActor.assumeIsolated`), and that check traps the instant the framework invokes the closure off-main, before the inner `Task` ever runs — this crashed Cirruscope in production despite the inner hop being "correct" in isolation. The actual fix is to form the closure inside a `nonisolated` factory method (returning the closure), so there is no enclosing main-actor context for the compiler to infer from, and to explicitly hop with `Task { @MainActor in ... }` *inside* that nonisolated closure — see `ServerAddressViewController.makeAuthenticationCompletionHandler()`, `ShortcutRecorderView.makeKeyDownHandler()`, and `WebViewController.makeTitleChangeHandler()`. Only pass `Sendable` values across that hop (e.g. a KVO change's `.newValue`, or a `UUID` identity, per `DownloadTableCellView`'s KVO handler) — the source object itself (an `NSEvent`, a `WKWebView`) is usually not `Sendable` and must not be captured into the `Task`.
- `UserNotifier`'s `nonisolated` delegate methods are a variant of the same pattern worth following directly: the *method* is marked `nonisolated` (rather than a closure built by a `nonisolated` factory), so it is never inferred main-actor no matter which type it's declared on, and it hops via `Task { @MainActor in ... }` internally.

## Logging and Diagnostics

Cirruscope logs through `os.Logger` and `OSSignposter` (see `Logging.swift`). Every behavioural type owns a `Logger(for: Self.self)` — the subsystem is the bundle identifier `de.i2h3.cirruscope` and the category is the type name — and the asynchronous facilities also own an `OSSignposter(for: Self.self)`. The passive `Models/` types have no logger.

### Retrieving logs to research a bug

Use `log show` to read logs already recorded in a past time range, and `log stream` to watch them live. **Invoke the tool as `/usr/bin/log`**: a shell function named `log` from the user profile otherwise shadows it and fails with "too many arguments".

```bash
# Everything Cirruscope logged in the last 30 minutes, machine-readable:
/usr/bin/log show --last 30m --predicate 'subsystem == "de.i2h3.cirruscope"' --info --debug --style ndjson

# A specific window of time (device-local clock):
/usr/bin/log show --start "2026-07-06 14:00:00" --end "2026-07-06 14:10:00" --predicate 'subsystem == "de.i2h3.cirruscope"' --info --debug --style ndjson

# One category (type) only — e.g. the download coordinator:
/usr/bin/log show --last 1h --predicate 'subsystem == "de.i2h3.cirruscope" && category == "DownloadManager"' --info --debug --style ndjson

# Watch live while reproducing a bug:
/usr/bin/log stream --predicate 'subsystem == "de.i2h3.cirruscope"' --level debug --style ndjson
```

- Only `.notice`, `.error`, and `.fault` are persisted to the store, so those are what `log show --last`/`--start` reliably returns after the fact; `.debug` and `.info` are ephemeral and appear only while `log stream` (or Instruments) is actively capturing. Put anything worth retrieving later at `.notice` or higher.
- Dynamic values are redacted as `<private>` unless the app runs from Xcode or a logging profile is installed — see the "Logging" section of `./README.md` for a ready-to-use profile.
- Signpost intervals (`InitialLoad`, `Validate`, `Login`, `Download`, `CacheAsset`, `LaunchValidation`) are best viewed by recording the app in Instruments with the *os_signpost* / *Points of Interest* instrument; they are only emitted while such a recorder is active.

### Adding logging to new code

- Give each new behavioural type its own `let logger = Logger(for: Self.self)` (and `OSSignposter(for: Self.self)` for asynchronous or long-running work). Do not add loggers to passive `Models/` types.
- `import os` in every file that *calls* a logger or signposter — including extension files — because member-import visibility is enabled.
- Make the logger/signposter `internal` (drop `private`) when the type's extensions in other files log through it, `nonisolated let` when `nonisolated` callbacks log through it, and `private static let` on the namespace enums.
- Signpost interval names are `StaticString` literals; use a unique `OSSignpostID` (`makeSignpostID(from:)` or `makeSignpostID()`) per concurrent interval, and store the `OSSignpostIntervalState` (for example on the model) when an interval spans separate callbacks.
- Keep the category equal to the type name. To tell apart several live instances of one type, give it an auto-incremented `UInt64` identifier (see `WebViewController.logID` and `nextLogID`) and append it to each message in parentheses as `(TypeName \(id))`, e.g. `(WebViewController 3)`, rather than encoding identity in the category. Integers print in the clear (a `String` id would be redacted), while secrets and personal data stay at the default private redaction.
- In the delegate-heavy WebKit and download files, log every method's entry and every return or early exit at debug level with the reason, so navigation and transfer behaviour can be reconstructed from a capture later.

## Commit Instructions

- Do not commit automatically.
- Suggest commit title after applying changes. If the changes relate to specific GitHub issues, mention them.
- Suggest commit description after applying changes.
- Every commit must carry a `Signed-off-by:` trailer per this project's [Developer Certificate of Origin](./CONTRIBUTING.md#developer-certificate-of-origin) policy, matching the git identity of whoever is being committed on behalf of in the current session (`git config user.name`/`user.email` — never a hardcoded name, since a different contributor's session must sign off as themselves), in addition to any `Co-Authored-By:` trailer already appended.

## Pull Request Instructions

- Do not open a pull request automatically.
