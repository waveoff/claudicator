import Foundation

struct UsageWindow: Decodable {
    let utilization: Double
    let resets_at: String?

    var remaining: Double { max(0, 100 - utilization) }
}

struct UsageResponse: Decodable {
    let five_hour: UsageWindow?
    let seven_day: UsageWindow?
    let seven_day_oauth_apps: UsageWindow?
    let seven_day_opus: UsageWindow?
}
