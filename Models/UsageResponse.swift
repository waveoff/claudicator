import Foundation

/// One quota window from `GET https://api.anthropic.com/api/oauth/usage`.
/// `utilization` is the percentage USED (0–100); remaining = 100 − utilization.
struct UsageWindow: Decodable {
    let utilization: Double
    let resets_at: String?

    var remaining: Double { max(0, 100 - utilization) }
}

/// Top-level response from the OAuth usage endpoint. All Claude products
/// (claude.ai, Claude Code, Desktop) share one pool.
struct UsageResponse: Decodable {
    let five_hour: UsageWindow?
    let seven_day: UsageWindow?
    let seven_day_oauth_apps: UsageWindow?
    let seven_day_opus: UsageWindow?
}
