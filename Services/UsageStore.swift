import Combine
import Foundation
import SwiftUI

@MainActor
final class UsageStore: ObservableObject {
    @Published var fiveHourRemaining: Double?
    @Published var weekRemaining: Double?
    @Published var fiveHourSecondsLeft: Int?
    @Published var weekSecondsLeft: Int?
    @Published var lastFetchedAt: Date?
    @Published var lastError: String?

    private var pollingTimer: AnyCancellable?
    private var countdownTimer: AnyCancellable?

    private static let usageEndpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let pollInterval: TimeInterval = 90
    private static let userAgent = "claudicator/1.0"
    private static let betaHeader = "oauth-2025-04-20"

    private static let resetDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func startPolling() {
        refresh()

        pollingTimer = Timer.publish(every: Self.pollInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh()
            }

        countdownTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tickCountdowns()
            }
    }

    func refresh() {
        Task {
            do {
                let token = try ClaudeTokenProvider.shared.currentAccessToken()
                let usage = try await fetchUsage(token: token)
                applyUsage(usage)
                lastFetchedAt = Date()
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    var statusColor: Color {
        let pct = fiveHourRemaining ?? 100
        if pct > 50 { return .green }
        if pct > 20 { return .orange }
        return .red
    }

    static func format(duration seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "soon" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60

        if days > 0 {
            return "\(days)d \(hours)h"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func tickCountdowns() {
        if let current = fiveHourSecondsLeft, current > 0 {
            fiveHourSecondsLeft = current - 1
        }
        if let current = weekSecondsLeft, current > 0 {
            weekSecondsLeft = current - 1
        }
    }

    private func applyUsage(_ usage: UsageResponse) {
        if let fiveHour = usage.five_hour {
            fiveHourRemaining = fiveHour.remaining
            fiveHourSecondsLeft = secondsUntilReset(fiveHour.resets_at)
        }

        if let week = usage.seven_day {
            weekRemaining = week.remaining
            weekSecondsLeft = secondsUntilReset(week.resets_at)
        }
    }

    private func fetchUsage(token: String) async throws -> UsageResponse {
        var request = URLRequest(url: Self.usageEndpoint)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.betaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw NSError(
                    domain: "UsageAPI",
                    code: 401,
                    userInfo: [NSLocalizedDescriptionKey: "Auth expired or invalid. Re-authenticate in Claude Code."]
                )
            }
            throw NSError(
                domain: "UsageAPI",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Usage API failed with status \(httpResponse.statusCode)."]
            )
        }

        return try JSONDecoder().decode(UsageResponse.self, from: data)
    }

    private func secondsUntilReset(_ isoString: String?) -> Int? {
        guard let isoString else { return nil }

        if let date = Self.resetDateFormatter.date(from: isoString) {
            return max(0, Int(date.timeIntervalSinceNow))
        }

        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        guard let date = fallback.date(from: isoString) else {
            return nil
        }

        return max(0, Int(date.timeIntervalSinceNow))
    }
}
