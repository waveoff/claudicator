import Combine
import Foundation
import SwiftUI

// MARK: - UsageStore
//
// WebKit-free. Gets an OAuth access token from OAuthService and calls the
// shared usage endpoint with plain URLSession. Stores quota *reset dates*
// (not a per-second countdown) so the menu popover isn't re-published every
// second — the live countdown is rendered locally by TimelineView in the
// view layer. That avoids the MenuBarExtra reconciliation crash.

final class UsageStore: ObservableObject {

    // MARK: Published state

    @Published var sessionUsed: Double?
    @Published var sessionResetDate: Date?
    @Published var weekUsed: Double?
    @Published var weekResetDate: Date?
    @Published var lastFetchedAt: Date?
    @Published var lastError: String?
    @Published var subscriptionType: String?
    @Published var needsLogin: Bool = false
    @Published var isRefreshing: Bool = false

    // MARK: Private

    private var pollingTimer: AnyCancellable?

    /// When rate-limited (HTTP 429), suppress *polled* fetches until this time
    /// so we honor the server's Retry-After instead of hammering on each poll.
    /// A manual refresh still goes through (user intent).
    private var backoffUntil: Date?

    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let pollInterval: TimeInterval = 150   // 2.5 min — balances freshness against the shared endpoint's limit
    private static let defaultBackoff: TimeInterval = 120

    // MARK: Init

    init() {
        startPolling()
    }

    // MARK: Public API

    func startPolling() {
        refresh()
        pollingTimer = Timer.publish(every: Self.pollInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                if let until = self.backoffUntil, Date() < until {
                    Log.usage.info("Skipping poll — backing off \(Int(until.timeIntervalSinceNow), privacy: .public)s more")
                    return
                }
                self.refresh()
            }
    }

    /// Manual + polled entry point. The in-flight guard means rapid taps (or a
    /// poll tick landing mid-refresh) are no-ops rather than spawning
    /// overlapping fetches — which previously raced on token refresh and the
    /// @Published writes and could crash the MenuBarExtra. `isRefreshing` also
    /// drives the button spinner. Called on the main thread (UI + .main timer).
    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            await fetch()
            await MainActor.run { self.isRefreshing = false }
        }
    }

    /// Sign out: clear the Keychain tokens and reset published state so the
    /// popover drops back to the "Connect" prompt. Called on the main thread.
    func disconnect() {
        OAuthService.shared.disconnect()
        sessionUsed = nil; sessionResetDate = nil
        weekUsed = nil; weekResetDate = nil
        subscriptionType = nil
        lastFetchedAt = nil
        lastError = nil
        backoffUntil = nil
        needsLogin = true
    }

    // MARK: Networking

    private func fetch() async {
        let accessToken: String
        do {
            accessToken = try await OAuthService.shared.validAccessToken()
        } catch {
            Log.usage.error("No access token: \(error.localizedDescription, privacy: .public)")
            await MainActor.run {
                self.needsLogin = true
                self.lastError = error.localizedDescription
            }
            return
        }
        await MainActor.run { self.needsLogin = false }

        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.setValue("application/json",      forHTTPHeaderField: "Accept")
        request.setValue("application/json",      forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20",      forHTTPHeaderField: "anthropic-beta")
        request.setValue("claudicator/1.0",       forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                await MainActor.run { self.lastError = "No HTTP response." }
                return
            }
            if http.statusCode == 429 {
                let wait = Self.retryAfter(from: http) ?? Self.defaultBackoff
                let until = Date().addingTimeInterval(wait)
                Log.usage.error("Rate limited (429); backing off \(Int(wait), privacy: .public)s")
                await MainActor.run {
                    self.backoffUntil = until
                    self.lastError = "Rate limited — paused for \(Int(wait))s."
                }
                return
            }
            guard (200...299).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let hint = http.statusCode == 401
                    ? " (token expired — try reconnecting)"
                    : ""
                await MainActor.run {
                    self.lastError = "HTTP \(http.statusCode)\(hint): \(body.prefix(120))"
                }
                return
            }

            let usage = try JSONDecoder().decode(UsageResponse.self, from: data)
            Log.usage.info("Fetched usage (used): session=\(usage.five_hour.map { String(format: "%.0f", $0.used) } ?? "—", privacy: .public)% week=\(usage.seven_day.map { String(format: "%.0f", $0.used) } ?? "—", privacy: .public)%")
            await MainActor.run {
                self.backoffUntil     = nil
                self.lastError        = nil
                self.lastFetchedAt    = Date()
                self.subscriptionType = OAuthService.shared.subscriptionType
                if let w = usage.five_hour {
                    self.sessionUsed      = w.used
                    self.sessionResetDate = Self.parseDate(w.resets_at)
                }
                if let w = usage.seven_day {
                    self.weekUsed         = w.used
                    self.weekResetDate    = Self.parseDate(w.resets_at)
                }
            }
        } catch {
            await MainActor.run { self.lastError = error.localizedDescription }
        }
    }

    // MARK: Computed

    var statusColor: Color { Self.quotaColor(used: sessionUsed ?? 0) }

    /// The popover palette, matching claude.ai's usage page:
    ///   0–80% → accent blue · 80–90% → warning amber · 90%+ → danger red.
    /// Shared by the popover bars and the header dot so they always agree.
    /// (The menu bar arc uses its own logic — native template tint below the
    /// danger threshold, fixed red at/above — see MenuBarLabel.)
    static let warningThreshold: Double = 80
    static let dangerThreshold:  Double = 90

    static func quotaColor(used: Double) -> Color {
        if used >= dangerThreshold  { return .claudeDanger }
        if used >= warningThreshold { return .claudeWarning }
        return .claudeAccent
    }

    /// Parse a `Retry-After` response header — either delta-seconds
    /// ("120") or an HTTP date — into seconds from now. Clamped to a sane
    /// range so a bogus value can't pause us for hours or retry instantly.
    private static func retryAfter(from http: HTTPURLResponse) -> TimeInterval? {
        guard let raw = (http.value(forHTTPHeaderField: "Retry-After") ??
                         http.value(forHTTPHeaderField: "retry-after"))?
            .trimmingCharacters(in: .whitespaces) else { return nil }

        let seconds: TimeInterval?
        if let s = TimeInterval(raw) {
            seconds = s
        } else {
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.timeZone = TimeZone(identifier: "GMT")
            fmt.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            seconds = fmt.date(from: raw).map { $0.timeIntervalSinceNow }
        }
        guard let value = seconds else { return nil }
        return min(max(value, 5), 3_600)   // 5s … 1h
    }

    // MARK: Date / duration helpers

    /// The API returns RFC 3339 with fractional seconds, e.g.
    /// "2025-11-04T04:59:59.943648+00:00". Try fractional first, then plain.
    private static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }

    /// Compact two-unit countdown for the inline row, e.g. "resets 1h 54m" /
    /// "resets 4d 3h" / "resets 12m". Rendered at TimelineView tick, not
    /// stored, so it ticks every minute without republishing the store.
    static func compactResetString(to date: Date?) -> String {
        guard let date else { return "resets —" }
        let seconds = Int(date.timeIntervalSinceNow)
        guard seconds > 0 else { return "resets soon" }
        let days  = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let mins  = (seconds % 3_600) / 60
        if days  > 0 { return "resets \(days)d \(hours)h" }
        if hours > 0 { return "resets \(hours)h \(mins)m" }
        return "resets \(mins)m"
    }
}

// MARK: - claude.ai usage palette

extension Color {
    /// 0–80% — claude.ai's accent blue (#2A78D6).
    static let claudeAccent  = Color(red: 42 / 255, green: 120 / 255, blue: 214 / 255)
    /// 80–90% — claude.ai's warning amber (#FAB219).
    static let claudeWarning = Color(red: 250 / 255, green: 178 / 255, blue: 25 / 255)
    /// 90%+ — claude.ai's danger red (#D03B3B).
    static let claudeDanger  = Color(red: 208 / 255, green: 59 / 255, blue: 59 / 255)
}
