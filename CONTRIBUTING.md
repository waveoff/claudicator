# Contributing to Claudicator

Thanks for your interest in improving Claudicator — a lightweight macOS menu bar
app that shows your remaining Claude quota with a live countdown to reset.

This is a small, focused project. Contributions of all sizes are welcome, from
typo fixes to new features. This guide covers how to build it, how the code is
organized, and how to get a change merged.

## Ground rules

- **Keep it lightweight.** Claudicator is intentionally small and dependency-light.
  New runtime dependencies need a strong justification — prefer SwiftUI,
  Foundation, and the Security framework.
- **Privacy is a feature, not a nice-to-have.** No analytics, no telemetry, no
  third-party servers. The app reads a token from the Keychain and talks only to
  `api.anthropic.com`. Any change that sends data anywhere else will be declined.
- **Discuss big changes first.** For anything beyond a bug fix or small
  improvement, open an issue before you start so we can agree on the approach.

## Building from source

**Requirements**

- macOS 13.0 (Ventura) or later
- Xcode 15 or later (full Xcode, not just the Command Line Tools)

**Run it**

1. Clone the repo and open `Claudicator.xcodeproj` in Xcode.
2. Select the `Claudicator` scheme and run (`⌘R`).
3. The app appears in the menu bar — there's no Dock icon or window. Click the
   gauge to open the popover.

To connect a real account, use **Connect to Claude…** and complete the same OAuth
flow you already use for Claude Code. If you have Claude Code installed and signed
in, Claudicator reads its existing Keychain token automatically.

**Packaging a release build**

`./build-dmg.sh` builds a self-signed Release `.app` and packages it as a DMG.
Maintainers publish releases with `./build-dmg.sh --release`. See the comments at
the top of the script for details on the self-signed-identity approach and why it
matters for Keychain "Always Allow" surviving updates.

## How the code is organized

```
ClaudicatorApp.swift   App entry point — the MenuBarExtra and its lifecycle.
Models/
  UsageResponse.swift  Decodes the JSON from the usage endpoint.
Services/
  KeychainService.swift  Reads the OAuth token from the macOS Keychain.
  OAuthService.swift     The PKCE OAuth sign-in flow.
  UsageStore.swift       Polls usage, holds app state, drives the UI.
  UpdaterService.swift   In-app auto-updates.
  Log.swift              Lightweight logging.
Views/
  ConnectView.swift    The "paste your code" / connect flow.
  ContentView.swift    The popover.
  UsageRowView.swift   A single quota row (bar + percent + countdown).
```

The development journal in `docs/journal/` records the *why* behind major
decisions (the WKWebView dead end, distribution, Sparkle auto-updates). It's the
fastest way to understand how things got to where they are — read it before
reworking anything load-bearing.

## A few things to watch

- **The usage endpoint is undocumented.** Treat every non-200 response and every
  unexpected JSON shape as something to handle gracefully, never as a crash.
- **Don't mutate `@Published` state from a fast timer.** Throttle UI-driving
  updates; a 1-second countdown tick should not trigger a full re-fetch or thrash
  published properties.
- **Cache Keychain reads.** Reading the Keychain on every poll is unnecessary and
  can trigger repeated permission prompts.

## Submitting a change

1. Fork the repo and create a branch off `main`.
2. Make your change. Keep the diff focused — one logical change per PR.
3. Make sure the app still builds and runs (`⌘R`) and that you've manually
   exercised the path you touched.
4. Update `CHANGELOG.md` under `[Unreleased]` if your change is user-facing.
5. Open a pull request and fill in the template. Link the issue it resolves.

## Code style

- Follow standard Swift conventions and match the surrounding code.
- Prefer clear names over comments, but comment the *why* when something is
  non-obvious (especially anything touching the undocumented endpoint or Keychain).
- Keep views small and move logic into the services/store layer.

## Roadmap

The phase plan lives in `CLAUDE.md`. Phase 1 (read → fetch → popover → colors →
refresh) is done. Phase 2 (polling loop, countdown, Settings, error states) and
Phase 3 (low-quota notifications, animated bars, launch-at-login) are good places
to look for work. Issues labelled **good first issue** are a gentle way in.

## License

By contributing, you agree that your contributions are licensed under the
[MIT License](LICENSE) that covers this project.
