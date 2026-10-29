import AppKit
import QuartzCore

func now() -> Double { CACurrentMediaTime() }

/// Clawd's body: one click-through panel that follows him, simple physics over the floors and
/// window tops, and the small awaitable moves (`walk`, `jump`, `say`) that the behaviours use.
@MainActor
final class Clawd: NSObject {
    let panel: NSPanel
    let view: MascotView

    var x: CGFloat = 0
    var y: CGFloat = 0
    var vx: CGFloat = 0
    var vy: CGFloat = 0
    var grounded = false
    var platform: Platform?
    var platforms: [Platform] = []

    var facing: CGFloat = 1
    var walkTarget: CGFloat?
    var walkSpeed: CGFloat = 80
    var backwards = false
    var walls = true
    var puppet = false
    var floating = false
    var held = false
    var grabbable = true

    var eyes: Eyes?
    var arms: Arms = .down
    var legs: Int?
    var mouth = 0
    var tilt: CGFloat = 0
    var squash: CGFloat = 1
    var scale: CGFloat = 1
    var alpha: CGFloat = 1
    var costume: Costume = .none
    var baseCostume: Costume = .none
    var lookAtMouse = true
    var sitting = false
    var laptopFrame: Int?

    var onGrab: (() -> Void)?
    var onThrownLanding: ((CGFloat) -> Void)?
    var onClick: ((Int) -> Void)?

    private var bubble: String?
    private var bubbleUntil = 0.0
    private var thrown = false
    private var press: (start: CGPoint, offset: CGPoint)?
    private var mouseVelocity = CGPoint.zero
    private var lastMouse = CGPoint.zero
    private var lastTick = now()
    private var lastScan = 0.0
    private var walked: CGFloat = 0
    private var lastX: CGFloat = 0
    private var blinkAt = now() + 2
    private var link: CADisplayLink?
    private var driver: (start: Double, duration: Double, update: (CGFloat) -> Void)?
    private var lastDrawn: (Pose, String?, Bool)?
    private var lastOrigin = CGPoint(x: -1, y: -1)

    static let gravity: CGFloat = 2300

    override init() {
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: MascotView.size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        view = MascotView(frame: NSRect(origin: .zero, size: MascotView.size))
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.contentView = view
        view.onMouseDown = { [weak self] _ in self?.pressBegan() }
        view.onMouseDragged = { [weak self] _ in self?.pressMoved() }
        view.onMouseUp = { [weak self] event in self?.pressEnded(event.clickCount) }
    }

    func start(at point: CGPoint) {
        x = point.x
        y = point.y
        lastX = x
        rescan()
        place()
        panel.orderFrontRegardless()
        let link = view.displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    // MARK: - Moves for the behaviours

    var screen: NSScreen { World.screen(nearX: x) }
    var floorY: CGFloat { screen.visibleFrame.minY }
    var onFloor: Bool { grounded && platform?.window == nil }

    func pause(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }

    @discardableResult
    func until(timeout: Double = 20, _ condition: () -> Bool) async throws -> Bool {
        let end = now() + timeout
        while !condition() {
            if now() > end { return false }
            try await Task.sleep(nanoseconds: 16_000_000)
        }
        return true
    }

    /// Walks to `target` on the current surface. Walking off the edge of a window makes him fall
    /// and keep walking after he lands.
    @discardableResult
    func walk(to target: CGFloat, speed: CGFloat = 85, backwards: Bool = false) async throws -> Bool {
        try await until(timeout: 2) { grounded }
        walkSpeed = speed
        self.backwards = backwards
        walkTarget = target
        defer { walkTarget = nil; self.backwards = false }
        return try await until(timeout: Double(abs(target - x) / speed) + 4) { walkTarget == nil || abs(x - target) < 1.5 }
    }

    /// A ballistic jump that lands on `point` when a surface is there to catch him.
    func jump(to point: CGPoint, arc: CGFloat = 70) async throws {
        try await until(timeout: 2) { grounded }
        let rise = max(point.y, y) + arc - y
        let up = sqrt(2 * Self.gravity * rise)
        let down = sqrt(2 * max(1, y + rise - point.y) / Self.gravity)
        facing = point.x >= x ? 1 : -1
        squash = 0.8
        try await pause(0.08)
        vy = up
        vx = (point.x - x) / (up / Self.gravity + down)
        grounded = false
        platform = nil
        try await until(timeout: 4) { grounded }
    }

    func hop(_ height: CGFloat = 26) async throws {
        try await until(timeout: 2) { grounded }
        vy = sqrt(2 * Self.gravity * height)
        vx = 0
        grounded = false
        platform = nil
        try await until(timeout: 3) { grounded }
    }

    /// Goes to `targetX` on `target`: walks off a window to go down, and jumps to go up.
    func travel(to targetX: CGFloat, on target: Platform, speed: CGFloat = 85) async throws {
        if target.y < y - 20, let current = platform, current.window != nil {
            let edge = targetX < (current.minX + current.maxX) / 2 ? current.minX - 24 : current.maxX + 24
            try await walk(to: edge, speed: speed)
            try await until(timeout: 3) { grounded }
        }
        let same = platform.map { $0.window == target.window && abs($0.y - target.y) < 2 } ?? false
        if !same {
            if target.y > y + 20 {
                let side: CGFloat = x < targetX ? -1 : 1
                let frame = screen.frame
                try await walk(to: min(max(targetX + side * 130, frame.minX + 60), frame.maxX - 60), speed: speed)
            }
            try await jump(to: CGPoint(x: targetX, y: target.y))
        }
        try await walk(to: targetX, speed: speed)
    }

    /// Calls `update` on each display frame with a time from 0 to 1. Use it for moves the physics does not do.
    func drive(_ duration: Double, _ update: @escaping (CGFloat) -> Void) async throws {
        driver = (now(), max(0.01, duration), update)
        defer { driver = nil }
        try await until(timeout: duration + 2) { driver == nil }
    }

    /// Hands Clawd back to the physics after a scripted move, so he lands on whatever is under him.
    func settle() {
        puppet = false
        floating = false
        grounded = false
        platform = nil
        vx = 0
        vy = 0
    }

    func say(_ text: String?, for seconds: Double = 2.8) {
        bubble = text
        bubbleUntil = now() + seconds
    }

    func spray(_ kind: Particle.Kind, count: Int = 1, spread: CGFloat = 30, speed: CGFloat = 60, life: Double = 1.2,
               at point: CGPoint = CGPoint(x: 0, y: 40)) {
        for _ in 0..<count {
            view.particles.append(Particle(
                kind: kind,
                p: CGPoint(x: point.x + .random(in: -spread...spread) * 0.3, y: point.y),
                v: CGPoint(x: .random(in: -spread...spread), y: speed * .random(in: 0.6...1.2)),
                life: life * .random(in: 0.8...1.2)))
        }
    }

    func calm() {
        puppet = false
        floating = false
        walls = true
        walkTarget = nil
        eyes = nil
        arms = .down
        legs = nil
        mouth = 0
        tilt = 0
        scale = 1
        alpha = 1
        costume = baseCostume
        lookAtMouse = true
        sitting = false
        laptopFrame = nil
        if !grounded && !held { platform = nil }
    }

    var bodyRect: CGRect {
        let size = Sprite.size
        return CGRect(x: x - size.width / 2 * scale, y: y, width: size.width * scale, height: size.height * scale)
    }

    // MARK: - Mouse

    private func pressBegan() {
        let mouse = NSEvent.mouseLocation
        press = (mouse, CGPoint(x: mouse.x - x, y: mouse.y - y))
        lastMouse = mouse
        mouseVelocity = .zero
    }

    private func pressMoved() {
        guard let press, !held, grabbable else { return }
        let mouse = NSEvent.mouseLocation
        guard hypot(mouse.x - press.start.x, mouse.y - press.start.y) > 4 else { return }
        onGrab?()
        calm()
        held = true
        grounded = false
        platform = nil
        say(["hey!", "whoa", "put me down!", "wheee", "where are we going?"].randomElement())
    }

    private func pressEnded(_ clicks: Int) {
        defer { press = nil }
        guard held else { onClick?(clicks); return }
        held = false
        thrown = true
        vx = max(-2600, min(2600, mouseVelocity.x))
        vy = max(-2600, min(2600, mouseVelocity.y))
    }

    // MARK: - Frame

    @objc private func step(_ link: CADisplayLink) {
        let time = now()
        let dt = CGFloat(min(1.0 / 30, max(0.001, time - lastTick)))
        lastTick = time
        if time - lastScan > (grounded && platform?.window == nil && walkTarget == nil ? 0.5 : 0.2) { rescan() }

        if let driver {
            let t = min(1, (time - driver.start) / driver.duration)
            driver.update(CGFloat(t))
            if t >= 1 { self.driver = nil }
        }

        if held {
            let mouse = NSEvent.mouseLocation
            let offset = press?.offset ?? CGPoint(x: 0, y: 40)
            let velocity = CGPoint(x: (mouse.x - lastMouse.x) / dt, y: (mouse.y - lastMouse.y) / dt)
            mouseVelocity = CGPoint(x: mouseVelocity.x * 0.6 + velocity.x * 0.4, y: mouseVelocity.y * 0.6 + velocity.y * 0.4)
            lastMouse = mouse
            x = mouse.x - offset.x
            y = mouse.y - offset.y
            tilt += (max(-0.6, min(0.6, -mouseVelocity.x * 0.0005)) - tilt) * min(1, dt * 12)
        } else if !puppet && !floating {
            physics(dt)
        }

        animate(dt, time)
        place()
        if !held, press == nil {
            let hit = bodyRect.insetBy(dx: 2, dy: -2).contains(NSEvent.mouseLocation)
            if panel.ignoresMouseEvents == hit { panel.ignoresMouseEvents = !hit }
        }
    }

    private func physics(_ dt: CGFloat) {
        if grounded {
            if let target = walkTarget {
                let distance = target - x
                let dir: CGFloat = distance >= 0 ? 1 : -1
                x += dir * min(abs(distance), walkSpeed * dt)
                facing = backwards ? -dir : dir
                if abs(target - x) < 1 { walkTarget = nil }
            }
            if walls { clampToWalls() }
            if let current = platform, !current.holds(x), walls || current.window != nil {
                if let next = platforms.first(where: { $0.window == current.window && $0.y == current.y && $0.holds(x) }) {
                    platform = next
                } else {
                    grounded = false
                    platform = nil
                    vy = 0
                    vx = walkTarget == nil ? 0 : facing * walkSpeed * (backwards ? -1 : 1)
                }
            }
            return
        }

        // Dropped below the floor, such as beside the Dock, he hops back up so the floor can catch him.
        if vy <= 0, y < floorY - 0.5, platforms.contains(where: { $0.window == nil && $0.holds(x) }) {
            vy = sqrt(2 * Self.gravity * (floorY - y + 24))
        }
        vy -= Self.gravity * dt
        let next = y + vy * dt
        x += vx * dt
        if walls, clampToWalls() { vx = -vx * 0.5 }
        let ceiling = screen.frame.maxY - Sprite.size.height
        if next > ceiling, vy > 0 { vy = -vy * 0.3 }
        if vy <= 0, let land = platforms.filter({ $0.holds(x) && $0.y <= y + 0.5 && $0.y >= next }).max(by: { $0.y < $1.y }) {
            y = land.y
            landed(on: land)
            return
        }
        y = min(next, ceiling + 40)
        let lowest = NSScreen.screens.map(\.visibleFrame.minY).min() ?? 0
        if y < lowest - 300 {
            y = floorY
            landed(on: platforms.first { $0.window == nil && $0.holds(x) } ?? Platform(window: nil, y: y, minX: x - 1, maxX: x + 1))
        }
    }

    private func landed(on surface: Platform) {
        let impact = -vy
        squash = max(0.6, 1 - impact / 4000)
        spray(.dust, count: impact > 500 ? 6 : 2, spread: 60, speed: 30, life: 0.5, at: CGPoint(x: 0, y: 0))
        if thrown, impact > 700 {
            vy = impact * 0.35
            vx *= 0.6
            return
        }
        grounded = true
        platform = surface
        vx = 0
        vy = 0
        if thrown {
            thrown = false
            onThrownLanding?(impact)
        }
    }

    @discardableResult
    private func clampToWalls() -> Bool {
        let screens = NSScreen.screens
        let half = Sprite.size.width / 2
        let left = (screens.map(\.frame.minX).min() ?? 0) + half
        let right = (screens.map(\.frame.maxX).max() ?? 0) - half
        if x < left { x = left; return true }
        if x > right { x = right; return true }
        return false
    }

    private func rescan() {
        lastScan = now()
        let windows = World.windows()
        platforms = World.platforms(windows)
        guard grounded, !puppet, let current = platform else { return }
        guard let id = current.window else {
            if let floor = platforms.first(where: { $0.window == nil && $0.holds(x) }) { platform = floor; y = floor.y }
            return
        }
        guard let moved = platforms.first(where: { $0.window == id }), let old = current.frame, let new = moved.frame else {
            grounded = false
            platform = nil
            return
        }
        x += new.minX - old.minX
        if let segment = platforms.first(where: { $0.window == id && $0.holds(x) }) {
            platform = segment
            y = segment.y
        } else {
            grounded = false
            platform = nil
        }
    }

    private func animate(_ dt: CGFloat, _ time: Double) {
        squash += (1 - squash) * min(1, dt * 9)
        if !held, !puppet, abs(tilt) > 0.001, grounded { tilt *= max(0, 1 - dt * 10) }
        if time > bubbleUntil { bubble = nil }

        let moved = abs(x - lastX)
        lastX = x
        if grounded || puppet { walked += moved }

        var pose = Pose()
        pose.facing = facing
        pose.squash = squash
        pose.tilt = tilt
        pose.scale = scale
        pose.alpha = alpha
        pose.costume = costume
        pose.arms = held ? .hold : arms
        if time > blinkAt + 0.13 { blinkAt = time + .random(in: 1.8...5.5) }
        let blinking = time > blinkAt
        pose.eyes = held ? .wide : eyes ?? (blinking ? .blink : .open)
        if !grounded && !puppet && !held && !floating {
            pose.legs = vy > 0 ? 3 : 0
            if vy < -900, eyes == nil { pose.eyes = .wide }
        } else if held {
            pose.legs = Int(time * 8) % 2 + 1
        } else {
            pose.legs = legs ?? (moved > 0.05 ? (Int(walked / 9) % 2 + 1) : 0)
            pose.turned = legs == nil && moved > 0.05
            pose.sitting = sitting && !pose.turned
            pose.laptopFrame = pose.sitting ? laptopFrame : nil
        }
        pose.armPhase = Int(time / 0.2) % 2 == 0
        pose.mouth = mouth > 0 ? mouth : (bubble != nil && Int(time / 0.14) % 3 == 0 ? 1 : 0)
        if lookAtMouse, eyes == nil, !held {
            let mouse = NSEvent.mouseLocation
            if abs(mouse.x - x) < 500, abs(mouse.y - y) < 500, abs(mouse.x - x) > 30 {
                pose.look = (mouse.x > x ? 1 : -1) * Int(facing)
            }
        }

        for index in view.particles.indices.reversed() {
            view.particles[index].age += Double(dt)
            if view.particles[index].age > view.particles[index].life { view.particles.remove(at: index); continue }
            view.particles[index].p.x += view.particles[index].v.x * dt
            view.particles[index].p.y += view.particles[index].v.y * dt
            if view.particles[index].kind == .sweat || view.particles[index].kind == .spark {
                view.particles[index].v.y -= 500 * dt
            }
        }

        let showShadow = grounded && costume != .ghost && !held
        if lastDrawn.map({ $0.0 != pose || $0.1 != bubble || $0.2 != showShadow }) ?? true || !view.particles.isEmpty {
            view.pose = pose
            view.bubble = bubble
            view.showsShadow = showShadow
            view.needsDisplay = true
            lastDrawn = (pose, bubble, showShadow)
        }
    }

    private func place() {
        let origin = CGPoint(x: (x - MascotView.feet.x).rounded(), y: (y - MascotView.feet.y).rounded())
        guard origin != lastOrigin else { return }
        lastOrigin = origin
        panel.setFrameOrigin(origin)
    }
}
