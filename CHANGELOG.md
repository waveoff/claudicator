# Changelog

All notable changes to Claudicator are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project aims to follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

_Phase 2 / Phase 3 items will accumulate here before the next release._

---

## [0.1.0] — 2026-05-29

First public release — menu bar quota tracker for Claude Code users.[^1]

### Added
- Menu bar icon and usage popover showing 5-hour session and weekly quota.
- Claude account sign-in via secure browser OAuth (paste-code flow) — your
  password never touches the app. Token stored securely in macOS Keychain.
- Live usage data with auto-refresh every 90s and a live countdown to quota
  reset (1-second tick).
- Color-coded status icon: green / orange / red by remaining quota.
- Manual refresh button.
- App logging via Console (subsystem `com.ariross.claudicator`).

---

[^1]: Claude Code's own usage API (`GET /api/oauth/usage`) is undocumented and
may change without notice. If Claudicator stops showing data after a Claude Code
update, that's the most likely cause — check the GitHub issues page.
