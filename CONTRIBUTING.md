<!--
SPDX-FileCopyrightText: 2026 Iva Horn
SPDX-License-Identifier: MIT
-->

# Contributing to Cirruscope

Thanks for your interest in contributing.
This document is written for developers, in the same spirit as [README.md](./README.md).
For a more general introduction, see [the official website](https://cirruscope.app).

## Before You Start

For anything beyond a small fix, please open an issue first and check it against the project's scope in [GOVERNANCE.md](./GOVERNANCE.md) before writing code. Cirruscope is a single-maintainer project with a deliberately focused scope, so a pull request that falls outside it may be declined regardless of how well it's built — opening an issue first saves you that wasted effort. Small, obvious fixes (typos, clear bugs) are fine to send directly.

## Developer Certificate of Origin

Every contribution to Cirruscope must be signed off under the [Developer Certificate of Origin](https://developercertificate.org/) (DCO).
By signing off a commit, you certify that you wrote it (or otherwise have the right to submit it) under this project's license.

Add a `Signed-off-by: Your Name <your@email.com>` trailer to every commit message, using the name and email address you want associated with the contribution:

```
git commit -s -m "Your commit message"
```

To avoid typing `-s` every time, set up a git alias:

```
git config --global alias.ci 'commit -s'
```

If you forgot to sign off a commit you already made, amend it:

```
git commit --amend -s
```

For multiple commits on a branch, sign them all off at once against the branch you're merging into (e.g. `develop`):

```
git rebase --exec 'git commit --amend --no-edit -s' develop
```

then force-push your branch to update the pull request.

[.github/workflows/dco.yml](.github/workflows/dco.yml) checks every commit on every push and pull request against `main`/`develop` for a `Signed-off-by:` trailer, and must pass before a pull request can be merged.

> **Note:** GitHub's default "Squash and merge" only carries commit *titles* into the squashed commit, dropping `Signed-off-by:` trailers along the way. Either merge with "Create a merge commit" instead, or manually keep a `Signed-off-by:` line in the squash commit message before confirming the merge.

## AI-Assisted Contributions

If you used an AI tool (e.g. GitHub Copilot, ChatGPT, Claude, or similar) to help write any part of a contribution — code, tests, documentation, or commit messages — check the corresponding box in the pull request template.

Disclosure doesn't lower the bar: you must be able to explain every part of your contribution — what it does, why it's written the way it is, and any trade-offs involved — in review, and you are personally accountable for it regardless of how it was produced. Do not open a pull request for code you have not reviewed and understood yourself. This doesn't replace the Developer Certificate of Origin above either: signing off a commit still certifies that you have the right to submit its content.

## Local Code Signing

The project builds ad-hoc by default (see [Cirruscope.xcconfig](./Cirruscope.xcconfig)), so a plain checkout builds with no Apple Developer account needed — this is also what CI uses. To run Cirruscope on-device with a real "Apple Development" identity instead, copy [Local.xcconfig.example](./Local.xcconfig.example) to `Local.xcconfig` (gitignored) next to it and fill in your own team; it overrides the ad-hoc defaults for your local builds only.

## Code Quality Checks

- Run `swiftformat .` before committing; CI lints with `swiftformat --lint`.
- New files need SPDX copyright/license headers; run `reuse lint` to confirm compliance.
- Run the unit tests before opening a pull request: **Product ▸ Test (⌘U)** with the `Cirruscope for macOS` scheme selected. The scheme is shared, so a fresh clone is already set up for it — nothing to configure. CI runs the same tests headlessly and then a Release build; see [AGENTS.md → Testing](./AGENTS.md#testing) for that command line if you want it outside Xcode.
- Changing anything in `Core/` or `Cirruscope/` changes all three targets at once — those folders compile into the macOS app, the iOS app, and the widget extension alike — so compile-check the `Cirruscope for iOS` and `Widgets` schemes as well before opening a pull request. See [AGENTS.md → Platform Scope](./AGENTS.md#platform-scope) for why shared placement is the default and what each shared folder is allowed to depend on.
- Changing Swift-only logic that needs no server or web view — shortcut handling, string rendering, pure decision functions — means adding or updating its tests in the same pull request. The WebKit-facing code is deliberately not unit-tested; see [AGENTS.md → Testing](./AGENTS.md#testing) for where the line sits and why.
- Any claimed performance improvement must be backed by evidence: include the benchmark, profiling data, or test results that show the before/after impact and explain the scenario it applies to.
- See [AGENTS.md](./AGENTS.md) for the full set of project conventions followed by human and AI contributors alike.

## Contribution Workflow

1. Fork the repository or create a branch.
2. Open a pull request against `develop`.
3. All CI actions must pass successfully before a pull request can be accepted.

## License

By contributing to Cirruscope, you agree that your contributions will be licensed under this project's [LICENSE](./LICENSE).
