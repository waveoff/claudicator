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

    @Published var sessionRemaining: Double?
    @Published var sessionResetDate: Date?
    @Published var weekRemaining: Double?
    @Published var weekResetDate: Date?
    @Published var lastFetchedAt: Date?
    @Published var lastError: String?
    @Published var subscriptionType: String?
    @Published var needsLogin: Bool = false

    // MARK: Private

    private var pollingTimer: AnyCancellable?

    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let pollInterval: TimeInterval = 90

    // MARK: Init

    init() {
        startPolling()
    }

    // MARK: Public API

    func startPolling() {
        refresh()
        pollingTimer = Timer.publish(every: Self.pollInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        Task { await fetch() }
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
            Log.usage.info("Fetched usage: session=\(usage.five_hour?.remaining ?? -1)% week=\(usage.seven_day?.remaining ?? -1)%")
            await MainActor.run {
                self.lastError        = nil
                self.lastFetchedAt    = Date()
                self.subscriptionType = OAuthService.shared.subscriptionType
                if let w = usage.five_hour {
                    self.sessionRemaining = w.remaining
                    self.sessionResetDate = Self.parseDate(w.resets_at)
                }
                if let w = usage.seven_day {
                    self.weekRemaining = w.remaining
                    self.weekResetDate = Self.parseDate(w.resets_at)
                }
            }
        } catch {
            await MainActor.run { self.lastError = error.localizedDescription }
        }
    }

    // MARK: Computed

    var statusColor: Color {
        let pct = sessionRemaining ?? 100
        if pct > 50 { return .green }
        if pct > 20 { return .orange }
        return .red
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

    /// "Resets in 1h 54m" / "Resets in 5d 23h" / "Resets soon", computed from
    /// `date` relative to now. Called at render time (TimelineView), not stored.
    static func resetString(to date: Date?) -> String {
        guard let date else { return "Resets —" }
        let seconds = Int(date.timeIntervalSinceNow)
        guard seconds > 0 else { return "Resets soon" }
        let days  = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let mins  = (seconds % 3_600) / 60
        if days  > 0 { return "Resets in \(days)d \(hours)h" }
        if hours > 0 { return "Resets in \(hours)h \(mins)m" }
        return "Resets in \(mins)m"
    }
}
