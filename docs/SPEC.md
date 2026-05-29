# Claudicator — Mac Menu Bar App
## Product Spec & Technical Implementation Guide

---

## 1. Overview

**Claudicator** is a lightweight macOS menu bar app that shows:
- Remaining Claude quota (5-hour session + 7-day weekly) from the real Anthropic usage API
- Live countdown timer to the next reset
- Menu bar icon that changes color based on how much quota remains

Target OS: macOS 13 Ventura+ (MenuBarExtra API)  
Language: Swift 5.9 + SwiftUI  
No external dependencies. No backend. All data is local.

---

## 2. Core Features

| Feature | Description |
|---|---|
| Menu bar icon | Color-coded dot: green (>50%), orange (20–50%), red (<20%) |
| Popover panel | Expandable panel showing 5-hour session + weekly quota |
| Session countdown | Live timer showing time until the rolling quota window resets |
| Low quota alerts | macOS notifications at 20% and 5% remaining |
| Settings window | Account (token status) + notification preferences |

---

## 3. Data Sources & Architecture

> **Key finding:** Claude Code's OAuth credentials live in macOS Keychain, and all Claude products (Claude.ai, Cowork, Claude Code) share a single usage pool queryable via an undocumented internal endpoint: `GET https://api.anthropic.com/api/oauth/usage`. This gives us real-time, accurate data with no manual tracking needed.
>
> **Caveat:** This endpoint is undocumented and intended for Anthropic's own clients. It could change at any time. Handle failures gracefully and fall back to cached data.

### 3.1 Auth Token — macOS Keychain

Claude Code stores its OAuth credentials in macOS Keychain under the service name **`Claude Code-credentials`**.

**Reading the token:**
```swift
import Security

func readClaudeToken() throws -> String {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "Claude Code-credentials",
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else {
        throw KeychainError.notFound
    }
    // data is JSON: { "claudeAiOauth": { "accessToken": "sk-ant-oat01-...", ... } }
    let json = try JSONDecoder().decode(KeychainPayload.self, from: data)
    return json.claudeAiOauth.accessToken
}

struct KeychainPayload: Decodable {
    let claudeAiOauth: OAuthCredentials
}
struct OAuthCredentials: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: TimeInterval
    let subscriptionType: String?  // "pro", "max", "team", etc.
}
```

If the Keychain item isn't present (Claude Code not installed), fall back to prompting the user to paste their token manually from `claude auth status`.

### 3.2 Usage API Endpoint

All Claude products share one usage pool. The endpoint Claude Code uses internally:

```
GET https://api.anthropic.com/api/oauth/usage
```

**Headers required:**
```
Authorization:    Bearer <accessToken>
Accept:           application/json
Content-Type:     application/json
User-Agent:       claudicator/1.0
anthropic-beta:   oauth-2025-04-20
```

**Response shape:**
```json
{
  "five_hour": {
    "utilization": 6.0,
    "resets_at": "2025-11-04T04:59:59.943648+00:00"
  },
  "seven_day": {
    "utilization": 35.0,
    "resets_at": "2025-11-06T03:59:59.943679+00:00"
  },
  "seven_day_oauth_apps": null,
  "seven_day_opus": {
    "utilization": 0.0,
    "resets_at": null
  }
}
```

`utilization` = **percentage used** (0–100). Remaining = `100 - utilization`.  
`resets_at` = RFC 3339 UTC timestamp when that window resets.

**Polling strategy:** fetch every 90 seconds. On fetch failure (401 = token expired, network error), show a warning state and retry. Cache the last good response so the UI never goes blank.

### 3.3 What the data gives us

| Shown in UI | Source field |
|---|---|
| Session remaining % (5h) | `100 - five_hour.utilization` |
| Session reset countdown | `five_hour.resets_at` → countdown timer |
| Weekly remaining % | `100 - seven_day.utilization` |
| Weekly reset date | `seven_day.resets_at` |
| Opus usage (Max plan) | `seven_day_opus.utilization` |
| Plan type | `subscriptionType` from Keychain payload |

Note: there is no separate "Cowork quota" — all Claude products (Cowork, Claude Code, claude.ai, Desktop) draw from the same pool.

---

## 4. App Architecture

```
Claudicator/
├── ClaudicatorApp.swift          — App entry point, MenuBarExtra
├── Models/
│   ├── UsageResponse.swift       — Decodable API response models
│   └── AppSettings.swift         — UserDefaults-backed settings
├── Services/
│   ├── KeychainService.swift     — Read OAuth token from macOS Keychain
│   ├── UsageStore.swift          — ObservableObject: fetch, poll, state
│   └── NotificationService.swift — macOS UNUserNotificationCenter
├── Views/
│   ├── ContentView.swift         — Main popover content
│   ├── UsageRowView.swift        — Reusable progress bar + countdown row
│   └── SettingsView.swift        — Account + notifications settings
└── Resources/
    ├── Assets.xcassets           — App icon + SF Symbols usage
    └── Info.plist
```

### 4.1 State (UsageStore)

`UsageStore` is an `ObservableObject` with `@Published` properties. It owns:
- The polling timer (90s via `Timer.publish`)
- The countdown ticker (1s via `Timer.publish`)
- The network fetch logic
- Computed helpers: `statusColor`, `format(duration:)`

### 4.2 Menu bar icon color logic

```swift
var statusColor: Color {
    let pct = fiveHourRemaining ?? 100
    if pct > 50 { return .green }
    if pct > 20 { return .orange }
    return .red
}
```

---

## 5. UI Specification

### 5.1 Menu Bar Icon

- **SF Symbol**: `brain.head.profile`
- Tinted with `statusColor` (green / orange / red)
- When <50%: show remaining % as text label next to icon

```swift
MenuBarExtra("Claudicator", systemImage: "brain.head.profile") {
    ContentView().environmentObject(usageStore)
}
```

### 5.2 Popover Panel

Width: **260pt**, padding: **12pt**

```
┌──────────────────────────────┐
│  ● Claudicator          [↺]  │  ← dot = statusColor, ↺ = refresh
├──────────────────────────────┤
│  5-hour session              │
│  ████████████░░  94%         │  ← progress bar
│  Resets in 2h 14m            │  ← live countdown
├──────────────────────────────┤
│  This week                   │
│  ██████░░░░░░░░  65%         │
│  Resets in 3d 5h             │
├──────────────────────────────┤
│  [error message if any]      │  ← red, only shown on error
├──────────────────────────────┤
│  Updated 23s ago      [Quit] │  ← footer
└──────────────────────────────┘
```

### 5.3 Settings Window

Two tabs: **Account** and **Notifications**

**Account tab:**
- Token status label: "Connected — Pro plan" (from Keychain, read-only)
- "Re-read from Keychain" button
- Manual token input field (fallback for users without Claude Code)
- Refresh interval picker: 60s / 90s / 120s

**Notifications tab:**
- Toggle: Notify at 20% session remaining
- Toggle: Notify at 5% session remaining
- Toggle: Notify on session reset
- Toggle: Notify on weekly reset

---

## 6. Permissions

| Permission | Why | How |
|---|---|---|
| Network (outbound) | Call `api.anthropic.com` | `com.apple.security.network.client` entitlement |
| Keychain read | Read Claude Code credentials | Disable App Sandbox (simplest) |
| Notifications | Low quota alerts | Request via `UNUserNotificationCenter` at launch |

**Recommended: Disable App Sandbox.** This is a developer tool, not App Store bound. Avoids Keychain entitlement complexity.

---

## 7. Build Instructions

```
1. File → New → Project → macOS → App
2. Product Name: Claudicator
3. Bundle ID: com.ariross.claudicator
4. Interface: SwiftUI | Language: Swift
5. Minimum deployment: macOS 13.0
6. Signing: Personal Team (for local use)
7. Disable App Sandbox in .entitlements
```

**Info.plist — required keys:**
```xml
<key>LSUIElement</key>
<true/>
<key>NSUserNotificationAlertStyle</key>
<string>alert</string>
```

---

## 8. Implementation Phases

### Phase 1 — MVP (build first)
- [ ] `ClaudicatorApp.swift` — `MenuBarExtra` skeleton
- [ ] `Models/UsageResponse.swift` — Decodable models
- [ ] `Services/KeychainService.swift` — Keychain read
- [ ] `Services/UsageStore.swift` — fetch + polling + countdown
- [ ] `Views/UsageRowView.swift` — progress bar component
- [ ] `Views/ContentView.swift` — popover with both rows
- [ ] Menu bar icon color states

### Phase 2 — Settings & error handling
- [ ] `Views/SettingsView.swift` — account + notifications tabs
- [ ] Error state UI in popover (red message, retry button)
- [ ] `AppSettings` — UserDefaults for refresh interval + notification prefs
- [ ] Manual token fallback in Settings

### Phase 3 — Polish
- [ ] `Services/NotificationService.swift` — UNUserNotificationCenter alerts at 20%/5%
- [ ] Animated progress bars (`.animation(.easeInOut, value: percent)`)
- [ ] Auto-launch at login (`SMAppService`)
- [ ] Opus row (show only if `seven_day_opus` non-null and non-zero)

---

## 9. SF Symbols Used

- `brain.head.profile` — menu bar icon
- `arrow.clockwise` — refresh button
- `gear` — settings button
- `bell` — notifications settings
- `key` — account/token settings

---

## 10. Constants

```swift
enum Config {
    static let usageEndpoint = "https://api.anthropic.com/api/oauth/usage"
    static let keychainService = "Claude Code-credentials"
    static let userAgent = "claudicator/1.0"
    static let anthropicBeta = "oauth-2025-04-20"
    static let defaultPollInterval: TimeInterval = 90
    static let bundleID = "com.ariross.claudicator"
}
```

---

## 11. Phase 1 Code Scaffold — Start Here

Complete, paste-ready Swift files. Drop these into the Xcode project and it will compile.

### `ClaudicatorApp.swift`
```swift
import SwiftUI

@main
struct ClaudicatorApp: App {
    @StateObject private var usageStore = UsageStore()

    var body: some Scene {
        MenuBarExtra("Claude Quota", systemImage: "brain.head.profile") {
            ContentView()
                .environmentObject(usageStore)
                .frame(width: 260)
                .onAppear {
                    usageStore.startPolling()
                }
        }
    }
}
```

Set `LSUIElement = YES` in Info.plist to hide the Dock icon.

---

### `Models/UsageResponse.swift`
```swift
import Foundation

struct UsageWindow: Decodable {
    let utilization: Double
    let resets_at: String?

    var remaining: Double { max(0, 100 - utilization) }

    var resetsAtDate: Date? {
        guard let s = resets_at else { return nil }
        return ISO8601DateFormatter().date(from: s)
    }
}

struct UsageResponse: Decodable {
    let five_hour: UsageWindow?
    let seven_day: UsageWindow?
    let seven_day_oauth_apps: UsageWindow?
    let seven_day_opus: UsageWindow?
}
```

---

### `Services/KeychainService.swift`
```swift
import Security
import Foundation

struct ClaudeCredentials: Decodable {
    struct Oauth: Decodable {
        let accessToken: String
        let expiresAt: TimeInterval
        let subscriptionType: String?
    }
    let claudeAiOauth: Oauth
}

final class ClaudeTokenProvider {
    static let shared = ClaudeTokenProvider()
    private init() {}

    func currentAccessToken() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let json = try? JSONDecoder().decode(ClaudeCredentials.self, from: data)
        else {
            throw NSError(
                domain: "ClaudeToken",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Claude Code credentials not found in Keychain. Is Claude Code installed and signed in?"]
            )
        }
        return json.claudeAiOauth.accessToken
    }
}
```

> If decoding fails, check the actual JSON shape with:
> `security find-generic-password -s "Claude Code-credentials" -w`

---

### `Services/UsageStore.swift`
```swift
import Foundation
import Combine
import SwiftUI

final class UsageStore: ObservableObject {
    @Published var fiveHourRemaining: Double?
    @Published var fiveHourSecondsLeft: Int?
    @Published var weekRemaining: Double?
    @Published var weekSecondsLeft: Int?
    @Published var lastError: String?
    @Published var lastFetchedAt: Date?

    private var pollingTimer: AnyCancellable?
    private var countdownTimer: AnyCancellable?

    // MARK: - Polling

    func startPolling() {
        refresh()
        pollingTimer = Timer.publish(every: 90, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }

        countdownTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tickCountdowns() }
    }

    private func tickCountdowns() {
        if let s = fiveHourSecondsLeft, s > 0 { fiveHourSecondsLeft = s - 1 }
        if let s = weekSecondsLeft, s > 0 { weekSecondsLeft = s - 1 }
    }

    func refresh() {
        Task {
            do {
                let token = try ClaudeTokenProvider.shared.currentAccessToken()
                let usage = try await fetchUsage(token: token)
                await MainActor.run {
                    self.lastError = nil
                    self.lastFetchedAt = Date()
                    if let w = usage.five_hour {
                        self.fiveHourRemaining = w.remaining
                        self.fiveHourSecondsLeft = Self.secondsUntilReset(w.resets_at)
                    }
                    if let w = usage.seven_day {
                        self.weekRemaining = w.remaining
                        self.weekSecondsLeft = Self.secondsUntilReset(w.resets_at)
                    }
                }
            } catch {
                await MainActor.run { self.lastError = error.localizedDescription }
            }
        }
    }

    // MARK: - Networking

    private func fetchUsage(token: String) async throws -> UsageResponse {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claudicator/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(UsageResponse.self, from: data)
    }

    // MARK: - Helpers

    private static func secondsUntilReset(_ iso: String?) -> Int? {
        guard let iso, let resetDate = ISO8601DateFormatter().date(from: iso) else { return nil }
        return max(0, Int(resetDate.timeIntervalSinceNow))
    }

    static func format(duration seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "soon" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    var statusColor: Color {
        let pct = fiveHourRemaining ?? 100
        if pct > 50 { return .green }
        if pct > 20 { return .orange }
        return .red
    }
}
```

---

### `Views/ContentView.swift`
```swift
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var usage: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            // Header
            HStack {
                Circle()
                    .fill(usage.statusColor)
                    .frame(width: 9, height: 9)
                Text("Claudicator")
                    .font(.headline)
                Spacer()
                Button(action: { usage.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            Divider()

            // 5-hour session
            if let pct = usage.fiveHourRemaining {
                UsageRowView(
                    label: "5-hour session",
                    percent: pct,
                    timeLeft: UsageStore.format(duration: usage.fiveHourSecondsLeft)
                )
            } else {
                Text("Session: n/a").foregroundStyle(.secondary)
            }

            Divider()

            // Weekly
            if let pct = usage.weekRemaining {
                UsageRowView(
                    label: "This week",
                    percent: pct,
                    timeLeft: UsageStore.format(duration: usage.weekSecondsLeft)
                )
            } else {
                Text("Weekly: n/a").foregroundStyle(.secondary)
            }

            // Error
            if let error = usage.lastError {
                Divider()
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // Footer
            HStack {
                if let t = usage.lastFetchedAt {
                    Text("Updated \(t, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
        .padding(12)
    }
}
```

---

### `Views/UsageRowView.swift`
```swift
import SwiftUI

struct UsageRowView: View {
    let label: String
    let percent: Double   // 0–100, remaining
    let timeLeft: String

    private var barColor: Color {
        if percent > 50 { return .green }
        if percent > 20 { return .orange }
        return .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f%%", percent))
                    .font(.caption).fontWeight(.medium)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor)
                        .frame(width: geo.size.width * (percent / 100), height: 6)
                        .animation(.easeInOut(duration: 0.4), value: percent)
                }
            }
            .frame(height: 6)
            Text("Resets in \(timeLeft)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
```
