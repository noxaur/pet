import AppKit
import PermissionFlow

/// Accessibility access, which Clawd needs to move windows. PermissionFlow opens System Settings and lets the user drag Clawd into the list.
@MainActor
final class Permissions {
    private let flow = PermissionFlow.makeController()

    static var accessibilityGranted: Bool {
        PermissionStatusRegistry.provider(for: .accessibility).authorizationState() == .granted
    }

    func requestAccessibility() {
        flow.authorize(pane: .accessibility, suggestedAppURLs: [Bundle.main.bundleURL])
    }
}
