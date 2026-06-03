# Security Policy

Claudicator handles a sensitive credential — the OAuth token Claude Code stores in
your macOS Keychain — so we take security reports seriously and appreciate
responsible disclosure.

## Reporting a vulnerability

**Please do not open a public issue for security problems.**

Report it through **GitHub's private vulnerability reporting**: go to the
[Security tab](https://github.com/waveoff/claudicator/security) and click
**Report a vulnerability**. This opens a private advisory that stays confidential
between you and the maintainer until a fix ships.

Please include:

- A description of the issue and why it's a security concern.
- Steps to reproduce, or a proof of concept.
- The Claudicator version and your macOS version.
- Any relevant logs (with tokens and personal data redacted).

**What to expect:** we aim to acknowledge a report within a few days, keep you
updated as we investigate, and credit you in the release notes once a fix is out
(unless you'd prefer to stay anonymous). As an unpaid open-source project we can't
promise a formal SLA, but we'll act on valid reports as quickly as we can.

## Supported versions

Claudicator is pre-1.0 and ships frequently. Only the **latest released version**
receives security fixes. Please update before reporting — the in-app updater will
get you current, or grab the newest build from the
[Releases page](https://github.com/waveoff/claudicator/releases).

## Security posture

A few facts that help frame what is and isn't in scope:

- **The token never leaves your Mac.** Claudicator reads the OAuth token from the
  Keychain and uses it only to call `api.anthropic.com` directly. There is no
  Claudicator server, no proxy, and no telemetry.
- **Your password never touches the app.** Sign-in uses the same PKCE OAuth flow
  as Claude Code; the app only ever sees the resulting token.
- **The usage endpoint is undocumented.** Claudicator calls a Claude quota
  endpoint that Anthropic has not published. It may change or disappear without
  notice; that's a reliability consideration, and we mention it here for full
  transparency about what the app talks to.
- **Builds are open and verifiable.** The source is MIT-licensed and public. If
  you don't want to trust a prebuilt binary, you can build your own from source.

### Out of scope

- Vulnerabilities in macOS, the Keychain, Xcode, or Anthropic's services
  themselves — please report those to the relevant vendor.
- The undocumented endpoint changing or returning errors (that's expected
  behavior the app handles gracefully, not a vulnerability).
- Issues that require a already-compromised local machine or physical access to an
  unlocked device.

Thanks for helping keep Claudicator and its users safe.
