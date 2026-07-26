<!--
SPDX-FileCopyrightText: 2026 Iva Horn
SPDX-License-Identifier: MIT
-->

# Governance

This document explains how Cirruscope is run and how decisions about it get made. It's short on purpose.

## Why this project exists

I build Cirruscope in my free time, to scratch my own itch. It's a manifestation of my ideas and opinions about how interacting with the Nextcloud server user interface should feel on macOS. That personal motivation isn't a footnote — it's the whole reason the project has a consistent point of view, and it's what everything below follows from.

## How this project is run

Cirruscope is maintained by one person. As the maintainer, I reserve the ultimate authority on its development decisions and have the final say on what ships.

This is deliberate, not an accident of the project being young. A single, consistent hand keeps the app coherent and well-maintained, rather than letting it drift into a feature-bloated mess where everything is started somewhere and nothing is perfected anywhere. Keeping that focus is a feature, and protecting it is part of the job.

Because I maintain Cirruscope in my spare time, I spend that time where it yields additional user value most efficiently. That focus cuts both ways: I sometimes have to reject ideas or changes — even good ones — to keep the project agile. Neither the app nor I can be allowed to petrify under the weight of feature bloat or unnecessary complication. Every "no" to something out of scope is a "yes" to keeping the rest fast, simple, and maintainable.

## What Cirruscope is

The goal is the best *native* Nextcloud experience on macOS — one that elevates the Nextcloud interface by leaning into Apple's platform features and WebKit, rather than wrapping a generic cross-platform shell. Every decision is measured against that vision.

## Feature requests and decisions

Ideas are genuinely welcome — please open a feature request and tell me what you'd like to see.

At the same time: requests may be declined. A decline is not a verdict on the quality of your idea, and it's not about you. It usually just means the idea doesn't fit the vision or the project scope.

I won't always write a long justification for a decision. A short "out of scope" or "not planned" is a complete answer here, and I'd rather give an honest quick "no" than leave requests hanging or turn every decision into a debate.

## If this isn't for you: fork it

If you disagree with a direction I take, that's completely fine — and you have a real remedy. Cirruscope is [MIT-licensed](./LICENSE). You can fork it, adapt it, build the version you have in mind, and ship it without needing my permission.

I mention this genuinely, not dismissively. "I make the final call" is only fair because nobody is stuck with my calls — the license guarantees you can go your own way.

## Contributing

Contributions are welcome. Before you invest real time in a change beyond a small fix, please open an issue first so we can check it against the scope above — that way effort doesn't go into a pull request I'd have to decline as out of scope. See [CONTRIBUTING.md](./CONTRIBUTING.md) for the mechanics (sign-off, code style, CI).
