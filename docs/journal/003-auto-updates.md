# 📓 Dev Journal #003 — Auto-Updates with Sparkle

> **Series:** Claudicator Development Journal · Entry 003 of ∞
> **Date:** 2026-05-31
> **Milestone:** In-app auto-updates, end to end
> **Status:** ✅ Live — shipped v0.1.0 → v0.5.0, each updating the last in place
> **Author:** Ari + Claude

---

## TL;DR

User interviews said automated updates were critical. We implemented the Sparkle
path decided in #002 — **without any Apple account**. It works end to end:
EdDSA-signed appcast on GitHub Releases, a one-command release script, and a real
`0.3.0 → 0.4.0 → 0.5.0` chain that updated itself with no Gatekeeper wall. Along
the way we also switched from ad-hoc to a **stable self-signed identity**, cleaned
up a recurring `project.pbxproj` bug, and hit the hard limit of free distribution:
the per-update **Keychain prompt can't be removed without a Developer ID**.

Switched versioning to **semver**, starting honestly at `0.1.0` (we're pre-1.0).

---

## What shipped

- **Sparkle 2.9.2** via SPM (the one sanctioned exception to no-dependencies).
- **`UpdaterService`** wrapping `SPUStandardUpdaterController`; background checks on,
  downloads gated on user confirmation; a "Check for Updates…" menu item.
- **`build-dmg.sh --release`** — builds, EdDSA-signs the DMG, generates a one-item
  `appcast.xml`, and publishes the GitHub release (DMG + appcast) in one command.
- Feed served from the **`/releases/latest/download/appcast.xml`** redirect, so the
  URL baked into the app never changes.

---

## Dead ends & diagnoses (the useful part)

**1. Xcode silently drops custom Info.plist keys.**
With `GENERATE_INFOPLIST_FILE = YES`, arbitrary `INFOPLIST_KEY_*` build settings
(e.g. `SUFeedURL`, `SUPublicEDKey`) are **not** written to the generated plist —
only Apple-known keys are. Verified by reading the built `Info.plist` and finding
them missing. Fix: a physical `Info.plist` holding just the two Sparkle keys,
merged via `INFOPLIST_FILE` (generation *augments* it). Then a second bite: the
synchronized root group copied that `Info.plist` into `Contents/Resources/` as a
stray resource → fixed with a `membershipException`.

**2. Private repo = silent 404 for everyone but you.**
First release looked fine (`gh` listed both assets), but the feed URL 404'd. Cause:
the repo was **private**, and Sparkle / end users fetch *unauthenticated* — GitHub
returns 404, not 403, for private-repo assets. Made the repo public (after a
secret scan). Also learned: the release must **not** be a pre-release, or the
`latest` redirect skips it and breaks the feed.

**3. Menu-bar apps open update windows behind everything.**
`LSUIElement` apps are never "active," so Sparkle's window appeared buried. Fix:
`NSApp.activate(ignoringOtherApps:)` in `checkForUpdates()` **and** via
`SPUStandardUserDriverDelegate.standardUserDriverWillHandleShowingUpdate`. (Gotcha:
`SPUUserUpdateState` is a concrete class — `any` doesn't compile.) Confirmed fixed.

**4. The Keychain prompt that wouldn't stick (the big one).**
Ad-hoc signing (`codesign -s -`) gives **every build a different identity**, so a
granted "Always Allow" never matched the next version. Switched `build-dmg.sh` to a
**stable self-signed cert** ("Claudicator Code Signing") — verified identical
designated requirements across versions. *And it still re-prompted.* Root cause:
the **legacy keychain's "Always Allow" records a version-specific trusted-app
entry that does not generalize across versions**, even with a stable DR. The proper
fix — the **data-protection keychain** (`kSecUseDataProtectionKeychain`) — refuses a
self-signed binary with `errSecMissingEntitlement (-34018)` because it needs a Team
ID. Proven with a signed probe. So: **no free fix.** Decision below.

**5. `project.pbxproj` self-reference churn — root-caused at last.**
Every Xcode session appended a recursive reference to `Claudicator.xcodeproj`
(6 had piled up), dirtying the tree and tripping the release guard. The #002 entry
called it a build-time artifact; the real cause is that the **file-system
synchronized group is rooted at `SOURCE_ROOT`, which contains the `.xcodeproj`** —
Xcode keeps rediscovering it as a sub-project. Removed all six (file refs + orphan
Products groups + `projectReferences`) and added `Claudicator.xcodeproj` to the
group's `membershipExceptions`. (Recurrence fix not yet confirmed under a long
Xcode session.)

**6. Release notes showed the whole GitHub website.**
`releaseNotesLink` pointed at the release *page*, which Sparkle loaded — nav bar,
"Sign in," tabs and all — into its window. Fix: embed the CHANGELOG section
directly in the appcast `<description>` (CDATA, HTML-escaped, pre-wrapped). Renders
inline now; still raw markdown (`### Fixed`) — prettifying is deferred.

---

## Versioning

- **Semver**, starting at `0.1.0` — `1.0` was a claim we hadn't earned.
- Two numbers, two jobs: `MARKETING_VERSION` (`CFBundleShortVersionString`, the
  human/tag version) and `CURRENT_PROJECT_VERSION` (`CFBundleVersion`, **what Sparkle
  actually compares**). Keeping both equal (dotted semver) is simplest; the rule is
  *bump both every release, never ship two builds at the same version.*

---

## Decisions

- **Auto-update:** Sparkle + EdDSA, feed on GitHub Releases `latest` redirect.
- **Signing:** stable self-signed cert (free), replacing ad-hoc — gives a stable
  identity even though it's not Apple-trusted.
- **Keychain prompt:** **accept it** (free, secure). Users click Allow once per
  update. Relaxing the ACL would remove it but make the token world-readable —
  rejected.
- **Releases:** one command, `./build-dmg.sh --release`, guarded against dirty
  tree / unpushed master / duplicate tag / pre-release.

---

## Open questions

- **Developer ID ($99/yr) is now the consolidated fix for THREE frictions:**
  Gatekeeper first-launch (#002), the per-update Keychain prompt, and the
  data-protection keychain. Each free workaround has hit the same wall. Revisit when
  the Cowork audience justifies it.
- **Build-from-source is broken for third parties:** `build-dmg.sh` now hard-requires
  the "Claudicator Code Signing" identity, which a cloner won't have. The README
  still says `./build-dmg.sh` just works. Needs an ad-hoc fallback or doc fix.
- **Inline release notes** still render raw markdown — convert to HTML in the build
  script (flagged as a follow-up task).
- **Self-reference recurrence** — confirm the `membershipException` actually stops
  Xcode re-adding it across a real editing session.

---

<sub>← Previous: [#002 Distribution](./002-distribution.md) · Next: [#004 Release Notes Markdown](./004-release-notes-markdown.md) · [Journal index](./index.md)</sub>
