import Foundation
import Sparkle

/// Thin SwiftUI-friendly wrapper around Sparkle's updater.
///
/// The feed URL (`SUFeedURL`) and the EdDSA public key (`SUPublicEDKey`) live
/// in Info.plist — Sparkle reads them from the bundle at init, so there is no
/// programmatic configuration here beyond enabling background checks. Because
/// the app ships unsigned (ad-hoc), Sparkle detects the absence of a Developer
/// ID and validates updates purely via the EdDSA signature on the appcast item.
final class UpdaterService: ObservableObject {
    private let controller: SPUStandardUpdaterController

    /// Drives the enabled state of the "Check for Updates…" menu item — Sparkle
    /// disables checking while an update session is already in flight.
    @Published var canCheckForUpdates = false

    init() {
        // startingUpdater: true → begins the scheduled background check loop.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Opt-out automatic checks. The Cowork audience skews non-technical, so
        // we silently poll the feed rather than showing Sparkle's first-launch
        // "enable automatic updates?" prompt. Downloads still wait for the user
        // to click Install (automaticallyDownloadsUpdates stays false).
        controller.updater.automaticallyChecksForUpdates = true

        controller.updater
            .publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// Triggers a user-initiated check; shows Sparkle's standard UI (no update,
    /// found, error). Wired to the "Check for Updates…" menu item.
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}
