import AppKit
import Foundation
import Sparkle

/// Thin SwiftUI-friendly wrapper around Sparkle's updater.
///
/// The feed URL (`SUFeedURL`) and the EdDSA public key (`SUPublicEDKey`) live
/// in Info.plist — Sparkle reads them from the bundle at init, so there is no
/// programmatic configuration here beyond enabling background checks. Because
/// the app ships unsigned (ad-hoc), Sparkle detects the absence of a Developer
/// ID and validates updates purely via the EdDSA signature on the appcast item.
///
/// Acts as the updater's user-driver delegate so it can pull the app forward
/// before any update window appears — Claudicator is an accessory app
/// (`LSUIElement`), so its windows would otherwise open *behind* the frontmost
/// app and get buried.
final class UpdaterService: NSObject, ObservableObject, SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController!

    /// Drives the enabled state of the "Check for Updates…" menu item — Sparkle
    /// disables checking while an update session is already in flight.
    @Published var canCheckForUpdates = false

    override init() {
        super.init()

        // startingUpdater: true → begins the scheduled background check loop.
        // self as userDriverDelegate so we can bring the app forward (below).
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
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
        NSApp.activate(ignoringOtherApps: true)
        controller.updater.checkForUpdates()
    }

    // MARK: - SPUStandardUserDriverDelegate

    /// Called right before Sparkle shows any update-related window (manual check
    /// result, scheduled-update prompt, install progress). Activating here makes
    /// the window come to the front instead of hiding behind other apps.
    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        NSApp.activate(ignoringOtherApps: true)
    }
}
