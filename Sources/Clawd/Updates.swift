import AppKit
import Sparkle

/// Sparkle updates from the appcast on the latest GitHub release.
/// Info.plist turns on daily checks and silent installs, so a new Clawd arrives the next time he quits.
@MainActor
final class Updates: NSObject, SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController!

    override init() {
        super.init()
        // A `swift run` build has no Info.plist with a feed URL, so it does not look for updates.
        let bundled = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        controller = SPUStandardUpdaterController(startingUpdater: bundled, updaterDelegate: nil,
                                                  userDriverDelegate: self)
    }

    func check() { controller.checkForUpdates(nil) }

    /// Clawd has no Dock icon, so Sparkle shows a found update gently when it cannot install it silently.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }
}
