# Claudicator

macOS menu bar app that shows remaining Claude quota (5-hour session + 7-day weekly) and live countdown to reset.

## What you're building

A lightweight SwiftUI menu bar app (`MenuBarExtra`) that:
1. Reads an OAuth token from macOS Keychain (`Claude Code-credentials`)
2. Calls `GET https://api.anthropic.com/api/oauth/usage` every 90 seconds
3. Shows remaining quota % and time to reset in a popover
4. Colors the menu bar icon green / orange / red based on quota level

**Full spec, API details, and paste-ready code scaffold: see `SPEC.md`**

## Start here

Read `SPEC.md` Section 11 first — it has five complete Swift files that form a working Phase 1 skeleton. Create the Xcode project, drop those files in, get it compiling, then iterate.

## Project setup (Xcode)

```
Product Name:         Claudicator
Bundle ID:            com.ariross.claudicator
Language:             Swift
Interface:            SwiftUI
Minimum deployment:   macOS 13.0 (Ventura)
App Sandbox:          OFF  ← required for Keychain access without entitlement wrangling
```

**Info.plist — add these two keys:**
```xml
<key>LSUIElement</key>
<true/>
<key>NSUserNotificationAlertStyle</key>
<string>alert</string>
```

## Key constraints

- No external dependencies. Pure SwiftUI + Foundation + Security framework only.
- The usage endpoint is **undocumented**. Non-200 responses must show a graceful error state, not crash.
- If the Keychain read fails (Claude Code not installed / not signed in), show a "paste your token" fallback in Settings.
- Poll at most every 60 seconds. Don't hammer the endpoint.
- `LSUIElement = YES` hides the app from the Dock and App Switcher — menu bar only.

## Phase plan

**Phase 1 (build first):** Keychain read → API fetch → popover with usage rows → icon color states → manual refresh  
**Phase 2:** 90s polling loop, 1s countdown tick, Settings window (account + notifications), error states  
**Phase 3:** Notifications at 20%/5%, animated progress bars, launch-at-login (`SMAppService`)

Complete Phase 1 before starting Phase 2.
