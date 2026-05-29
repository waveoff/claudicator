import Foundation

/// One quota window from `GET https://api.anthropic.com/api/oauth/usage`.
/// `utilization` is the percentage USED (0–100) — the same figure shown at
/// claude.ai/settings/usage. We surface "used" directly rather than inverting.
struct UsageWindow: Decodable {
    let utilization: Double
    let resets_at: String?

    var used: Double { min(100, max(0, utilization)) }
}

/// Top-level response from the OAuth usage endpoint. All Claude products
/// (claude.ai, Claude Code, Desktop) share one pool.
struct UsageResponse: Decodable {
    let five_hour: UsageWindow?
    let seven_day: UsageWindow?
    let seven_day_oauth_apps: UsageWindow?
    let seven_day_opus: UsageWindow?
}
