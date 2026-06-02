# Changelog

All notable changes to Claudicator are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project aims to follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

---

## [0.6.0] — 2026-06-02

### Added
- App icon: a proper Claudicator icon — the dark squircle quota gauge from the
  website — now ships with the app, the Dock/launcher, and the installer disk
  image (the mounted DMG volume shows it too). Drawn on the native macOS icon
  grid, so it sits right alongside other Mac apps.

---

## [0.5.0] — 2026-05-31

### Fixed
- Update notes now render inline in the updater window instead of loading the
  full GitHub release page — no more website chrome inside the update prompt.

---

## [0.4.0] — 2026-05-31

### Changed
- Project hygiene: removed accumulated recursive self-references from the Xcode
  project and excluded the project bundle from the synchronized file group, so
  the working tree stays clean between releases.

_No user-facing app changes — also used to validate that updates now surface in
front and no longer re-prompt for Keychain access (stable signing from 0.3.0)._

---

## [0.3.0] — 2026-05-31

### Fixed
- Update windows (manual "Check for Updates…" and background prompts) now come
  to the front instead of opening behind other apps.

### Changed
- Builds are now signed with a stable local code-signing identity instead of
  ad-hoc, so a granted Keychain "Always Allow" keeps working across
  auto-updates. (Still not Apple-notarized — fresh installs need a one-time
  Gatekeeper approval, and the 0.2.0 → 0.3.0 update asks for Keychain access
  once more as the identity changes, then persists.)

---

## [0.2.0] — 2026-05-31

### Changed
- Release tooling: `./build-dmg.sh --release` now builds, signs, and publishes
  the GitHub release (DMG + appcast) in a single command.
- Clarified the target audience (Claude Cowork / Claude.ai users) in the spec
  and changelog.

_No user-facing app changes — this version also validates the Sparkle
auto-update flow end-to-end._

---

## [0.1.0] — 2026-05-29

First public release — a menu bar quota tracker for Claude users. Especially
handy for Claude Cowork users, who (unlike Claude Code, which shows usage in its
own window) have no at-a-glance view of how much quota is left.[^1]

### Added
- Menu bar icon and usage popover showing 5-hour session and weekly quota.
- Claude account sign-in via secure browser OAuth (paste-code flow) — your
  password never touches the app. Token stored securely in macOS Keychain.
- Live usage data with auto-refresh every 90s and a live countdown to quota
  reset (1-second tick).
- Color-coded status icon: green / orange / red by remaining quota.
- Manual refresh button.
- Automatic in-app updates via Sparkle: background checks against an
  EdDSA-signed appcast (no App Store / notarization required), plus a
  "Check for Updates…" menu item.
- App logging via Console (subsystem `com.ariross.claudicator`).

---

[^1]: Claude Code's own usage API (`GET /api/oauth/usage`) is undocumented and
may change without notice. If Claudicator stops showing data after a Claude Code
update, that's the most likely cause — check the GitHub issues page.
