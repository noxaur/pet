import AppKit

/// A window on the current Desktop, in AppKit coordinates (origin at the bottom left of the main display).
struct Win {
    let id: CGWindowID
    let pid: pid_t
    let frame: CGRect
    let owner: String
}

/// A surface Clawd can stand on: the floor of a display, or the visible part of a window's top edge.
struct Platform: Equatable {
    var window: CGWindowID?
    var y: CGFloat
    var minX: CGFloat
    var maxX: CGFloat
    var frame: CGRect?

    func holds(_ x: CGFloat) -> Bool { x >= minX && x <= maxX }
}

enum World {
    static var mainTop: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }

    /// The windows on screen, front to back.
    static func windows() -> [Win] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let top = mainTop, me = getpid()
        return list.compactMap { info in
            guard info[kCGWindowLayer as String] as? Int == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != me,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.1,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = info[kCGWindowBounds as String],
                  let rect = CGRect(dictionaryRepresentation: bounds as! CFDictionary) // swiftlint:disable:this force_cast
            else { return nil }
            let owner = info[kCGWindowOwnerName as String] as? String ?? ""
            guard rect.width >= 120, rect.height >= 80, !["CatWM", "Dock", "Window Server"].contains(owner) else { return nil }
            return Win(id: id, pid: pid, frame: CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height),
                       owner: owner)
        }
    }

    static func platforms(_ windows: [Win]) -> [Platform] {
        var result = NSScreen.screens.map {
            Platform(window: nil, y: $0.visibleFrame.minY, minX: $0.frame.minX, maxX: $0.frame.maxX)
        }
        for (index, window) in windows.enumerated() {
            let top = window.frame.maxY
            guard let screen = screen(at: CGPoint(x: window.frame.midX, y: top - 1)),
                  top <= screen.visibleFrame.maxY - Sprite.size.height - 6 else { continue }
            var segments = [(window.frame.minX + 4, window.frame.maxX - 4)]
            for front in windows[..<index] where front.frame.minY < top && front.frame.maxY > top - 2 {
                segments = segments.flatMap { segment -> [(CGFloat, CGFloat)] in
                    let (a, b) = segment, (c, d) = (front.frame.minX, front.frame.maxX)
                    if d <= a || c >= b { return [segment] }
                    return [(a, c), (d, b)].filter { $0.1 > $0.0 }
                }
            }
            result += segments.filter { $0.1 - $0.0 > 70 }.map {
                Platform(window: window.id, y: top, minX: $0.0, maxX: $0.1, frame: window.frame)
            }
        }
        return result
    }

    static func screen(at point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    static func screen(nearX x: CGFloat) -> NSScreen {
        let screens = NSScreen.screens
        return screens.first { x >= $0.frame.minX && x < $0.frame.maxX }
            ?? screens.min { abs($0.frame.midX - x) < abs($1.frame.midX - x) } ?? screens[0]
    }

    static func uuid(of screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    /// Whether the Claude app is the one in use: it is the frontmost app and has a window open on
    /// the current Desktop, not minimized or hidden.
    static var claudeActive: Bool {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.bundleIdentifier == "com.anthropic.claudefordesktop" else { return false }
        return windows().contains { $0.pid == front.processIdentifier }
    }

    static var idleSeconds: Double {
        guard let any = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
    }

    static func appName(_ pid: pid_t) -> String {
        NSRunningApplication(processIdentifier: pid)?.localizedName ?? "that window"
    }
}

@_silgen_name("_AXUIElementGetWindow")
private func axWindowID(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Accessibility calls. They can block on a slow app, so callers run them off the main thread.
enum AX {
    static func window(_ id: CGWindowID, pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.6)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        return windows.first { element in
            var found: CGWindowID = 0
            return axWindowID(element, &found) == .success && found == id
        }
    }

    static func movable(_ window: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &settable) == .success
            && settable.boolValue
    }

    static func setPosition(_ window: AXUIElement, _ point: CGPoint) {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }

    @discardableResult
    static func focus(_ id: CGWindowID, pid: pid_t) -> Bool {
        guard let window = window(id, pid: pid) else { return false }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        return true
    }

    static func offMain<T>(_ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { continuation.resume(returning: body()) }
        }
    }
}

/// Moves one window through AX on a serial queue. Only the newest position is written,
/// so a slow app drops frames instead of lagging behind Clawd.
final class Grip: @unchecked Sendable {
    private static let queue = DispatchQueue(label: "clawd.grip", qos: .userInteractive)
    private let window: AXUIElement
    private let lock = NSLock()
    private var pending: CGPoint?
    private var busy = false

    init(_ window: AXUIElement) { self.window = window }

    /// `origin` is the bottom left corner in AppKit coordinates.
    func move(origin: CGPoint, height: CGFloat) {
        let topLeft = CGPoint(x: origin.x.rounded(), y: (World.mainTop - origin.y - height).rounded())
        lock.lock()
        pending = topLeft
        let start = !busy
        busy = true
        lock.unlock()
        if start { Self.queue.async { self.drain() } }
    }

    private func drain() {
        while true {
            lock.lock()
            guard let point = pending else { busy = false; lock.unlock(); return }
            pending = nil
            lock.unlock()
            AX.setPosition(window, point)
        }
    }
}
