import OSLog

/// Unified logging. View live with:
///   log stream --predicate 'subsystem == "com.ariross.claudicator"' --level debug
/// or in Console.app by filtering on the subsystem.
enum Log {
    static let usage = Logger(subsystem: "com.ariross.claudicator", category: "usage")
    static let auth  = Logger(subsystem: "com.ariross.claudicator", category: "auth")
}
