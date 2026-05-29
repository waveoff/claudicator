# Changelog

All notable changes to Claudicator are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project aims to follow [Semantic Versioning](https://semver.org/).

## [0.1.0] — 2026-05-29

First working version (MVP / Phase 1).

### Added
- Mac menu bar icon and usage popover (5-hour session + weekly quota).
- Claude account sign-in via secure browser OAuth (paste-code flow) — your
  password never touches the app.
- Live usage data with auto-refresh every 90s and a per-minute reset countdown.
- Color-coded status: green / orange / red by remaining quota.
- Manual refresh button.
- Tokens stored securely in the macOS Keychain.
- App logging via Console (subsystem `com.ariross.claudicator`).
- User README, development journal, and spec under `docs/`.
- `.gitignore` covering secrets, build artifacts, and Xcode user state.
