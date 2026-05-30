# 📓 Dev Journal #002 — Getting Claudicator onto Other Macs

> **Series:** Claudicator Development Journal · Entry 002 of ∞
> **Date:** 2026-05-30
> **Milestone:** Distribution research + first DMG
> **Status:** ✅ Shipping v1 as open source + unsigned DMG
> **Author:** Ari + Claude

---

## TL;DR

The app is stable and in daily use, so the question became: how do other people
install it? Gatekeeper is the gate. We chose **Option A — open source + an
unsigned DMG on GitHub Releases** for v1, built the first `.dmg`, and added a
`LICENSE` + README install docs. Notarization is the obvious next step if the
audience grows; **the Mac App Store is effectively closed** to us because of the
OAuth model from entry #001.

---

## The Gatekeeper constraint

Anything handed to another Mac has to get past Gatekeeper. The scary "Apple could
not verify…" wall is triggered by the `com.apple.quarantine` flag macOS attaches
to files downloaded via browser/AirDrop. Locally-built copies don't carry it,
which is why our own install opened cleanly — a misleading "works on my machine."
To preview the real user experience, set the flag manually:

```
xattr -w com.apple.quarantine "0081;00000000;Safari;" Claudicator.dmg
```

---

## The three distribution paths

| Option | Cost | User experience | Verdict |
|---|---|---|---|
| **A — open source + unsigned DMG** | free | "Open Anyway" dance once via System Settings | ✅ chosen for v1 |
| **B — Developer ID + notarization** | $99/yr | frictionless double-click | revisit as audience grows |
| **C — Mac App Store** | $99/yr | store install | ❌ blocked (see below) |

Key insight: **open source and notarization solve different problems and stack.**
Open source answers "can I trust the code?"; notarization answers "will macOS let
me run it?". Doing one doesn't remove the need for the other.

---

## What we shipped (Option A)

- **`build-dmg.sh`** — one command: builds Release (ad-hoc signed), stages the app
  + an `/Applications` symlink, produces `Claudicator.dmg` (~354 KB).
- **`LICENSE`** (MIT) — without it, nobody legally has the right to use the code.
- **README** — Install, Build-from-source, and Privacy sections.
- **`.gitignore`** — added `*.dmg` (ship via GitHub Releases, not the repo).

Gotcha worth remembering: `xcodebuild` mutates `project.pbxproj` (adds a spurious
self-reference) on every command-line build. Discard that change before
committing — it doesn't happen when building in the Xcode GUI.

---

## Auto-updates → Sparkle (deferred, but decided)

[Sparkle](https://sparkle-project.org) is the answer and works **without an Apple
account** — it has its own EdDSA signature mechanism, separate from Apple signing,
that secures the update channel. The big win for our unsigned Option A: Sparkle
does in-place updates and strips the quarantine flag, so users do the "Open
Anyway" dance **once ever**, not per release. The appcast can be a static file on
GitHub Releases. It's the one worthwhile exception to the no-dependencies rule.
Not implemented yet — deferred by choice, but it's the chosen path.

---

## Why the App Store is closed to us

Split cleanly into the easy part and the blockers.

**The easy part (in our control):** enable the App Sandbox + `network.client`
entitlements, Hardened Runtime, and a privacy manifest. Our Keychain already uses
our *own* service name (`com.ariross.claudicator`), not Claude Code's — so the
original SPEC's cross-app-read problem doesn't even apply anymore (we abandoned it
in entry #001).

**The real blockers (not in our control):**
1. We **impersonate Claude Code's first-party OAuth client** — reusing its
   `client_id` and Anthropic's redirect URI. App Review forbids this
   (guidelines 5.2.1 / 5.2.5 / 2.5.1). Showstopper.
2. The scopes go well beyond read-only usage: `org:create_api_key user:inference`.
3. The core feature depends on an **undocumented endpoint** (`api/oauth/usage`).
4. We use the **"Claude" trademark** (5.2.5).

A genuinely compliant version would need Anthropic to provide a sanctioned
third-party OAuth client, a documented public usage API, and brand permission.
Until that exists, the Mac App Store is off the table.

---

## Decisions

- **v1 distribution:** Option A — open source + unsigned DMG via GitHub Releases.
- **Notarization (Option B):** revisit once the audience grows beyond technical users.
- **Sparkle:** deferred, but the chosen auto-update path.
- **App Store:** off the table given the current auth model.

---

## Open questions

- The ToS gray area flagged in entry #001 (reusing Claude Code's `client_id` + an
  undocumented endpoint) now applies to **public** distribution — higher stakes,
  since strangers will run it. Still unresolved.
- LICENSE copyright holder currently reads "Waveoff" — confirm that's the intended
  credit.

---

<sub>← Previous: [#001 MVP](./001-mvp.md) · Next: [#003 Auto-Updates](./003-auto-updates.md) · [Journal index](./index.md)</sub>
