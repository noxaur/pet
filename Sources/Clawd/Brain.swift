import AppKit

/// A window Clawd brought here from another Desktop. He takes it back after a while.
struct Loan {
    let id: CGWindowID
    let pid: pid_t
    let home: String
    let here: String
    let at: Double
    let app: String
}

/// A tiled window that Clawd floated to drag it. He puts it back in its tile after a while.
struct Loose {
    let id: CGWindowID
    let pid: pid_t
    let at: Double
    let app: String
}

/// What Clawd does next. One behaviour runs at a time as a cancellable task;
/// picking Clawd up cancels it, and the loop starts again when he lands.
@MainActor
final class Brain {
    let c: Clawd
    let fx: Effects
    var mischief = true
    private(set) var loans: [Loan] = []
    private(set) var loose: [Loose] = []
    private var task: Task<Void, Never>?
    private var nextMischief = now() + 20
    private var clicks: [Double] = []
    private var busy = false

    init(clawd: Clawd, effects: Effects) {
        c = clawd
        fx = effects
        c.onGrab = { [weak self] in self?.stop() }
        c.onThrownLanding = { [weak self] impact in self?.start { try await self?.recover(impact) } }
        c.onClick = { [weak self] count in self?.clicked(count) }
    }

    func start(_ first: (() async throws -> Void)? = nil) {
        let previous = task
        previous?.cancel()
        task = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            do {
                self.c.calm()
                if let first { try await first() }
                while !Task.isCancelled {
                    self.c.calm()
                    try await self.next()
                }
            } catch {}
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// Runs `act` now, unless Clawd is on his way to another Desktop.
    func perform(_ act: @escaping () async throws -> Void) {
        guard !busy else { c.say("one sec, i'm busy!"); return }
        start(act)
    }

    var behaviours: [String: () async throws -> Void] {
        [
            "drag": { [self] in if try await !drag() { c.say("nothing i can move here.") } },
            "fetch": { [self] in if try await !fetch() { c.say("no windows on other desktops. (or no CatWM?)") } },
            "party": party, "stroll": stroll, "look": lookAround, "climb": climb, "think": think, "peek": peek,
            "dance": dance, "sneeze": sneeze, "nap": nap, "curious": curious, "haunt": haunt, "flip": backflip,
            "giggle": giggle, "hello": entrance, "code": code
        ]
    }

    private func next() async throws {
        let time = now()
        if let window = loose.first(where: { time - $0.at > 160 }) { return try await tidy(window) }
        if let loan = loans.first(where: { time - $0.at > 200 }) { return try await giveBack(loan) }
        if World.idleSeconds > 150 { return try await nap() }
        if mischief, time > nextMischief, AXIsProcessTrusted() {
            if Int.random(in: 0..<5) < 2, try await fetch() { return }
            if try await drag() { return }
        }
        if World.claudeActive { return try await code() }
        let mouse = NSEvent.mouseLocation
        let near = hypot(mouse.x - c.x, mouse.y - c.y) < 260
        let options: [(Double, () async throws -> Void)] = [
            (30, stroll), (12, lookAround), (11, climb), (7, think), (4, peek), (4, dance), (3, sneeze),
            (c.baseCostume == .witch ? 5 : 0, haunt), (near ? 10 : 0, curious)
        ]
        var roll = Double.random(in: 0..<options.reduce(0) { $0 + $1.0 })
        for (weight, act) in options {
            roll -= weight
            if roll < 0 { return try await act() }
        }
    }

    // MARK: - Everyday life

    func entrance() async throws {
        try await c.until(timeout: 5) { c.grounded }
        try await c.pause(0.3)
        c.arms = .wave
        c.say("hi! i'm Clawd.")
        try await c.pause(2.2)
        let day = Calendar.current.dateComponents([.month, .day], from: Date())
        switch c.baseCostume {
        case .witch:
            c.eyes = .happy
            c.say(day.day == 31 ? "happy halloween! 🎃" : "happy almost-halloween! 🎃")
        case .santa:
            c.say("ho ho ho 🎄")
        default:
            c.say("i'll just... hang around here.")
        }
        try await c.pause(2.4)
    }

    private func stroll() async throws {
        let frame = c.screen.frame
        let surface = c.platform ?? Platform(window: nil, y: c.y, minX: frame.minX, maxX: frame.maxX)
        let low = max(surface.minX, frame.minX) + 50, high = min(surface.maxX, frame.maxX) - 50
        var target = low < high ? CGFloat.random(in: low...high) : c.x
        if surface.window != nil, Int.random(in: 0..<4) == 0 {
            target = Bool.random() ? surface.minX - 40 : surface.maxX + 40
            c.say(["whoops", "geronimo!", "down we go"].randomElement())
        }
        try await c.walk(to: target, speed: .random(in: 55...110))
        try await c.pause(.random(in: 0.3...1.6))
    }

    private func lookAround() async throws {
        c.lookAtMouse = false
        for _ in 0..<Int.random(in: 2...4) {
            c.facing = -c.facing
            try await c.pause(.random(in: 0.5...1.3))
        }
        if Bool.random() { try await think() }
    }

    private func climb() async throws {
        let frame = c.screen.frame
        let targets = c.platforms.filter {
            $0.window != nil && $0.y > c.y + 40 && $0.y - c.y < 760 && $0.maxX - $0.minX > 110
                && $0.minX >= frame.minX - 20 && $0.maxX <= frame.maxX + 20 && $0.window != c.platform?.window
        }
        guard let target = targets.randomElement() else { return try await stroll() }
        c.say(["hup!", "parkour!", "ooh, a window"].randomElement())
        try await c.travel(to: .random(in: (target.minX + 40)...(target.maxX - 40)), on: target)
        if c.platform?.window == target.window {
            c.arms = .up
            c.eyes = .happy
            try await c.pause(0.9)
        }
    }

    private func think() async throws {
        let date = Date()
        let parts = Calendar.current.dateComponents([.hour, .minute, .weekday], from: date)
        var lines = ["is it compiling yet?", "i could tile that.", "*hums in json*", "how many desktops do you even have?",
                     "nice windows. mind if i rearrange?", "you're doing great.", "ship it!", "i'm not a crab. probably.",
                     "have you tried turning it off and on again?", "beep boop. just kidding."]
        switch parts.hour ?? 12 {
        case 0..<5: lines += [String(format: "it's %d:%02d. go to bed!", parts.hour ?? 0, parts.minute ?? 0)]
        case 5..<9: lines += ["good morning ☀️", "coffee first."]
        case 12..<14: lines += ["lunch?", "i'd eat a sandwich if i had a mouth."]
        case 17..<20: lines += ["almost done for today?"]
        default: break
        }
        if parts.weekday == 6 { lines += ["it's friday!!"] }
        if c.baseCostume == .witch { lines += ["trick or treat!", "spooky season 🎃", "i'm a witch now. it's canon."] }
        c.say(lines.randomElement())
        c.spray(.note, count: 1, spread: 20, speed: 30, life: 1.6, at: CGPoint(x: 30, y: 52))
        try await c.pause(3)
    }

    private func peek() async throws {
        guard c.onFloor else { return try await stroll() }
        let frame = c.screen.frame
        let right = c.x > frame.midX
        let edge = right ? frame.maxX : frame.minX
        try await c.walk(to: edge + (right ? -90 : 90), speed: 110)
        c.walls = false
        try await c.walk(to: edge + (right ? 22 : -22), speed: 70)
        c.facing = right ? -1 : 1
        c.lookAtMouse = false
        try await c.pause(1.2)
        c.say("peekaboo!")
        c.eyes = .happy
        try await c.pause(1.4)
        c.eyes = nil
        try await c.walk(to: edge + (right ? -120 : 120), speed: 90)
        c.walls = true
    }

    private func dance() async throws {
        c.say(["♪ tiling tiling tiling ♪", "dance break!", "♪ beep boop ♪"].randomElement())
        for index in 0..<6 {
            c.arms = index.isMultiple(of: 2) ? .up : .wave
            c.eyes = .happy
            c.spray(.note, count: 1, spread: 40, speed: 40, life: 1.4, at: CGPoint(x: 0, y: 55))
            try await c.hop(.random(in: 14...30))
            c.facing = -c.facing
        }
    }

    private func sneeze() async throws {
        c.eyes = .squint
        c.mouth = 1
        c.say("a… a…")
        try await c.pause(1.1)
        c.say("ACHOO!", for: 1.4)
        c.mouth = 2
        c.squash = 0.7
        c.spray(.spark, count: 10, spread: 160, speed: 140, life: 0.8, at: CGPoint(x: c.facing * 40, y: 30))
        try await c.hop(16)
        c.mouth = 0
        c.eyes = .blink
        try await c.pause(0.8)
        c.say("excuse me.")
        try await c.pause(1.2)
    }

    private func nap() async throws {
        c.legs = 3
        c.eyes = .closed
        c.squash = 0.92
        c.lookAtMouse = false
        var lastZ = 0.0
        try await c.until(timeout: 60) {
            if now() - lastZ > 1.1 {
                lastZ = now()
                c.spray(.z, count: 1, spread: 10, speed: 22, life: 2.2, at: CGPoint(x: 30, y: 50))
            }
            return World.idleSeconds < 1
        }
        c.eyes = .wide
        try await c.pause(0.4)
        c.legs = nil
        c.arms = .up
        c.eyes = .closed
        c.say("*yaaawn*")
        try await c.pause(1.4)
    }

    /// While you use the Claude app, Clawd sits down at his laptop and types along. He gets up when
    /// you switch to another app or Desktop, or after a while, so the loop can check on loans. With the Claude app
    /// installed he plays its official laptop animation; otherwise he draws his own.
    private func code() async throws {
        c.sitting = true
        c.lookAtMouse = false
        let official = Official.laptop != nil
        if official { try await play(Official.intro) }
        c.say(["time to code!", "pair programming?", "i'll take the tests.", "let's ship something."].randomElement())
        let end = now() + .random(in: 40...70)
        var nextCheck = now() + 3, nextLine = now() + .random(in: 12...20)
        try await c.until(timeout: 80) {
            if now() > nextLine {
                nextLine = now() + .random(in: 14...24)
                c.say(["*clack clack clack*", "hmm, a type error.", "tests are green!", "refactoring...",
                       "almost there.", "who wrote this? oh. me."].randomElement())
            }
            if official {
                let typing = Official.typing
                c.laptopFrame = typing.lowerBound + Int(now() * Official.fps) % typing.count
            }
            if now() > nextCheck {
                nextCheck = now() + 0.3
                if !World.claudeActive { return true }
            }
            return now() > end
        }
        if official { try await play(Official.outro) }
        c.sitting = false
        c.laptopFrame = nil
    }

    private func play(_ frames: ClosedRange<Int>) async throws {
        for i in frames {
            c.laptopFrame = i
            try await c.pause(1 / Official.fps)
        }
    }

    private func curious() async throws {
        let mouse = NSEvent.mouseLocation
        c.facing = mouse.x > c.x ? 1 : -1
        c.say(["whatcha doing?", "ooh, a cursor", "can i help?", "click me. i dare you."].randomElement())
        if abs(mouse.y - c.y) < 120 {
            try await c.walk(to: mouse.x + (mouse.x > c.x ? -70 : 70), speed: 120)
        }
        c.eyes = .happy
        try await c.hop(20)
        try await c.pause(1)
    }

    /// Halloween: Clawd turns into a ghost and floats right through your windows.
    private func haunt() async throws {
        let frame = c.screen.frame
        c.costume = .ghost
        c.spray(.spark, count: 8, spread: 80, speed: 80, life: 0.7)
        c.floating = true
        c.lookAtMouse = false
        c.say("boooo 👻")
        let startX = c.x, startY = c.y
        let endX = startX > frame.midX ? frame.minX + 160 : frame.maxX - 160
        c.facing = endX > startX ? 1 : -1
        let height = min(frame.height * 0.45, 420)
        try await c.drive(Double(abs(endX - startX) / 120)) { [c] t in
            c.x = startX + (endX - startX) * t
            c.y = startY + height * sin(.pi * t) + 12 * sin(t * 18)
            c.alpha = 0.75 + 0.2 * sin(t * 30)
        }
        c.spray(.spark, count: 8, spread: 80, speed: 80, life: 0.7)
        c.costume = c.baseCostume
        c.alpha = 1
        c.settle()
        try await c.until(timeout: 3) { c.grounded }
        c.say("…you didn't see anything.")
        try await c.pause(2)
    }

    // MARK: - Being handled

    private func clicked(_ count: Int) {
        let time = now()
        clicks = clicks.filter { time - $0 < 2.5 } + [time]
        guard !busy else { return }
        if clicks.count >= 5 {
            clicks = []
            return perform(party)
        }
        perform(count >= 2 ? backflip : giggle)
    }

    private func giggle() async throws {
        c.eyes = .happy
        c.say(["hehe", "that tickles", "<3", "again!", "hi!"].randomElement())
        c.spray(.heart, count: 3, spread: 40, speed: 50, life: 1.3, at: CGPoint(x: 0, y: 50))
        try await c.hop(18)
        try await c.pause(1.2)
    }

    private func backflip() async throws {
        try await c.until(timeout: 2) { c.grounded }
        let height: CGFloat = 130
        let air = 2 * sqrt(2 * height / Clawd.gravity)
        c.say("watch this!")
        let spin = c.facing
        c.vy = sqrt(2 * Clawd.gravity * height)
        c.vx = 0
        c.grounded = false
        c.platform = nil
        try await c.drive(Double(air)) { [c] t in c.tilt = -spin * 2 * .pi * t }
        try await c.until(timeout: 2) { c.grounded }
        c.tilt = 0
        c.arms = .up
        c.eyes = .happy
        c.say("nailed it.")
        try await c.pause(1.5)
    }

    func party() async throws {
        c.costume = .party
        fx.confetti(on: c.screen)
        c.say("PARTY!! 🎉", for: 4)
        for index in 0..<10 {
            c.arms = index.isMultiple(of: 2) ? .up : .wave
            c.eyes = .happy
            c.facing = -c.facing
            c.spray(.note, count: 1, spread: 50, speed: 50, life: 1.3, at: CGPoint(x: 0, y: 55))
            try await c.hop(.random(in: 20...60))
        }
        try await c.pause(1)
    }

    private func recover(_ impact: CGFloat) async throws {
        if impact > 1400 {
            c.eyes = .dizzy
            c.say(["ow.", "i'm ok!", "the room is spinning"].randomElement())
            for _ in 0..<4 {
                c.spray(.star, count: 1, spread: 50, speed: 20, life: 0.8, at: CGPoint(x: 0, y: 58))
                try await c.pause(0.45)
            }
        } else {
            c.eyes = .happy
            c.say(["again!", "wheee!", "smooth landing"].randomElement())
            try await c.pause(1.4)
        }
    }

    // MARK: - Mischief

    /// Drags a window on this Desktop. A tiled CatWM window is floated first, and put back later.
    @discardableResult
    func drag() async throws -> Bool {
        nextMischief = now() + .random(in: 55...140)
        let screen = c.screen
        let visible = screen.visibleFrame
        let managed = await Desk.windows()
        let windows = World.windows().filter { visible.intersects($0.frame) }
        let candidates = windows.filter { window in
            guard let info = managed?.first(where: { $0.id == Int(window.id) }) else { return managed == nil }
            return info.floating || info.focused
        }
        guard let target = candidates.prefix(3).randomElement(),
              let element = await AX.offMain({ AX.window(target.id, pid: target.pid) }),
              await AX.offMain({ AX.movable(element) }) else { return false }
        let app = World.appName(target.pid)
        let tiled = managed?.first { $0.id == Int(target.id) }.map { !$0.floating } ?? false

        let floor = c.floorY
        let reachesFloor = target.frame.minY <= floor + 40
        let roomAbove = target.frame.maxY <= visible.maxY - Sprite.size.height - 10
        guard reachesFloor || roomAbove else { return false }
        let wide = target.frame.width >= visible.width - 60
        let dir: CGFloat = wide ? (Bool.random() ? 1 : -1) : (target.frame.midX < visible.midX ? 1 : -1)

        if reachesFloor {
            let edge = dir > 0 ? target.frame.minX : target.frame.maxX
            let gripX = min(max(edge + dir * 46, visible.minX + 50), visible.maxX - 50)
            let keep = target.frame.width * 0.35
            let room = dir > 0 ? visible.maxX - keep - target.frame.minX : target.frame.maxX - visible.minX - keep
            let walkRoom = dir > 0 ? visible.maxX - 60 - gripX : gripX - visible.minX - 60
            let distance = min(.random(in: 180...340), room, walkRoom)
            guard distance > 60,
                  let ground = c.platforms.first(where: { $0.window == nil && $0.holds(gripX) }) else { return false }
            c.say(["hmm. \(app) would look better over there.", "this window needs a little nudge.",
                   "a little to the \(dir > 0 ? "right" : "left")…"].randomElement())
            try await c.travel(to: gripX, on: ground, speed: 170)
            guard let frame = try await loosen(target, tiled: tiled, app: app) else { return true }
            c.facing = -dir
            c.arms = .reach
            c.eyes = .squint
            c.lookAtMouse = false
            c.puppet = true
            let grip = Grip(element)
            let startX = c.x
            let tugs = Int.random(in: 3...5)
            for index in 0..<tugs {
                let from = distance * CGFloat(index) / CGFloat(tugs)
                let length = distance / CGFloat(tugs)
                if index == 0 { c.say(["hnnngh!", "heave!", "it's heavy!"].randomElement(), for: 1.5) }
                try await c.drive(0.34) { [c] t in
                    let offset = from + length * (1 - pow(1 - t, 3))
                    c.x = startX + dir * offset
                    c.tilt = -dir * 0.2 * sin(.pi * t)
                    grip.move(origin: CGPoint(x: frame.minX + dir * offset, y: frame.minY), height: frame.height)
                }
                c.spray(.sweat, count: 2, spread: 50, speed: 120, life: 0.7, at: CGPoint(x: 0, y: 48))
                try await c.pause(.random(in: 0.15...0.35))
            }
        } else {
            guard let top = c.platforms.first(where: { $0.window == target.id }) else { return false }
            let room = dir > 0 ? visible.maxX - target.frame.maxX + target.frame.width * 0.5
                : target.frame.minX - visible.minX + target.frame.width * 0.5
            let distance = min(.random(in: 200...420), room)
            guard distance > 60 else { return false }
            c.say("hop on, \(app). we're going for a ride.")
            try await c.travel(to: min(max(target.frame.midX, top.minX + 30), top.maxX - 30), on: top, speed: 170)
            guard c.platform?.window == target.id, let frame = try await loosen(target, tiled: tiled, app: app) else {
                return true
            }
            c.say("wheee!", for: 2)
            c.arms = .up
            c.eyes = .happy
            c.facing = dir
            c.legs = 0
            c.puppet = true
            let grip = Grip(element)
            let startX = c.x
            try await c.drive(Double(distance / 240)) { [c] t in
                let eased = t * t * (3 - 2 * t)
                c.x = startX + dir * distance * eased
                c.y = frame.maxY
                c.tilt = -dir * 0.12 * sin(.pi * t)
                grip.move(origin: CGPoint(x: frame.minX + dir * distance * eased, y: frame.minY), height: frame.height)
            }
        }
        c.tilt = 0
        c.settle()
        c.arms = .down
        c.eyes = .happy
        try await c.pause(0.3)
        c.say(["there. feng shui.", "perfect.", "you're welcome.", "much better.", "best. ride. ever."].randomElement())
        try await c.pause(2)
        return true
    }

    /// Floats a tiled window so CatWM does not pull it back while Clawd drags it, and gives its frame.
    private func loosen(_ target: Win, tiled: Bool, app: String) async throws -> CGRect? {
        guard tiled else { return target.frame }
        guard await Desk.windows()?.first(where: { $0.id == Int(target.id) })?.focused == true else {
            c.say("hm. never mind.")
            return nil
        }
        c.say("CatWM has \(app) tiled. one sec…", for: 1.6)
        c.eyes = .squint
        await Desk.toggleFloating()
        try await c.pause(0.45)
        guard await Desk.windows()?.first(where: { $0.id == Int(target.id) })?.floating == true else { return nil }
        loose.append(Loose(id: target.id, pid: target.pid, at: now(), app: app))
        return World.windows().first { $0.id == target.id }?.frame ?? target.frame
    }

    /// Goes through a portal to another Desktop and brings one of its windows back to this one.
    @discardableResult
    func fetch() async throws -> Bool {
        nextMischief = now() + .random(in: 55...140)
        guard let windows = await Desk.windows(), let screens = await Desk.screens(),
              let uuid = World.uuid(of: c.screen), let display = screens.first(where: { $0.uuid == uuid }) else { return false }
        let here = display.workspace
        let taken = Set(loans.map(\.id))
        let candidates = windows.filter {
            !$0.visible && !$0.minimized && !$0.fullscreen && $0.screen == uuid
                && $0.workspace != nil && $0.workspace != here && !taken.contains(CGWindowID($0.id))
        }
        guard let pick = candidates.randomElement(), let there = pick.workspace else { return false }
        let id = CGWindowID(pick.id), pid = pid_t(pick.pid)
        let app = World.appName(pid)

        busy = true
        c.grabbable = false
        defer {
            busy = false
            c.grabbable = true
            c.walls = true
            c.scale = 1
            c.alpha = 1
        }
        let frame = c.screen.frame
        let dir: CGFloat = Desk.number(there) > Desk.number(here) ? 1 : -1
        let door = dir > 0 ? frame.maxX - 34 : frame.minX + 34
        c.say("brb, borrowing \(app) from desktop \(Desk.number(there))", for: 3)
        if let ground = c.platforms.first(where: { $0.window == nil && $0.holds(door - dir * 150) }) {
            try await c.travel(to: door - dir * 150, on: ground, speed: 170)
        }
        let closeExit = fx.portal(at: CGPoint(x: door, y: c.floorY))
        try await c.pause(0.6)
        c.walls = false
        try await c.walk(to: door, speed: 160)
        c.puppet = true
        try await c.drive(0.25) { [c] t in c.scale = 1 - 0.9 * t }
        c.alpha = 0
        closeExit()

        await Desk.show(there)
        try await waitFor { await Desk.screens()?.first(where: { $0.uuid == uuid })?.workspace == there }
        try await c.pause(0.5)

        let entry = dir > 0 ? frame.minX + 34 : frame.maxX - 34
        c.x = entry
        c.y = c.floorY
        let closeEntry = fx.portal(at: CGPoint(x: entry, y: c.y))
        try await c.pause(0.4)
        c.alpha = 1
        try await c.drive(0.25) { [c] t in c.scale = 0.1 + 0.9 * t }
        closeEntry()
        c.settle()
        try await c.walk(to: entry + dir * 220, speed: 140)

        if await Desk.windows()?.first(where: { $0.id == pick.id })?.focused != true {
            _ = await AX.offMain { AX.focus(id, pid: pid) }
        }
        guard try await waitFor({ await Desk.windows()?.first(where: { $0.id == pick.id })?.focused == true }) else {
            c.say("it ran away! never mind.")
            try await c.pause(1.5)
            await Desk.show(here)
            return true
        }
        c.arms = .up
        c.eyes = .happy
        c.say("found it! \(app), you're coming with me.", for: 2.4)
        try await c.pause(1.6)
        c.arms = .hold
        c.say("wheee!", for: 1.5)
        await Desk.carry(to: here)
        try await waitFor { await Desk.windows()?.first(where: { $0.id == pick.id })?.workspace == here }
        try await c.pause(0.5)
        loans.append(Loan(id: id, pid: pid, home: there, here: here, at: now(), app: app))
        fx.confetti(on: c.screen)
        c.arms = .up
        c.say("ta-da! \(app), special delivery 📦", for: 3.5)
        try await c.hop(30)
        try await c.hop(20)
        try await c.pause(1.5)
        return true
    }

    /// Sends a borrowed window back to its own Desktop without leaving this one.
    func giveBack(_ loan: Loan, walk: Bool = true) async throws {
        loans.removeAll { $0.id == loan.id }
        guard let windows = await Desk.windows(),
              let info = windows.first(where: { $0.id == Int(loan.id) }), !info.minimized, info.workspace == loan.here else { return }
        if walk {
            if let frame = World.windows().first(where: { $0.id == loan.id })?.frame,
               let ground = c.platforms.first(where: { $0.window == nil && $0.holds(frame.midX) }) {
                try await c.travel(to: frame.midX, on: ground, speed: 150)
            }
            c.say("ok, giving \(loan.app) back before anyone notices…", for: 2.6)
            try await c.pause(1.2)
        }
        let previous = windows.first { $0.focused && $0.id != Int(loan.id) }
        _ = await AX.offMain { AX.focus(loan.id, pid: loan.pid) }
        guard try await waitFor({ await Desk.windows()?.first(where: { $0.id == Int(loan.id) })?.focused == true }) else { return }
        await Desk.send(to: loan.home)
        if let previous { _ = await AX.offMain { AX.focus(CGWindowID(previous.id), pid: pid_t(previous.pid)) } }
        guard walk else { return }
        c.arms = .wave
        c.say("bye \(loan.app)! 👋")
        try await c.pause(2)
    }

    /// Puts a window that Clawd floated back into its CatWM tile.
    func tidy(_ window: Loose, walk: Bool = true) async throws {
        loose.removeAll { $0.id == window.id }
        guard let windows = await Desk.windows(),
              let info = windows.first(where: { $0.id == Int(window.id) }), info.floating, !info.minimized else { return }
        guard info.visible else {
            if walk { loose.append(Loose(id: window.id, pid: window.pid, at: now(), app: window.app)) }
            return
        }
        if walk {
            if info.visible, let frame = World.windows().first(where: { $0.id == window.id })?.frame,
               let ground = c.platforms.first(where: { $0.window == nil && $0.holds(frame.midX) }) {
                try await c.travel(to: frame.midX, on: ground, speed: 150)
            }
            c.say("ok ok, putting \(window.app) back in its tile.", for: 2.4)
            try await c.pause(1)
        }
        let previous = windows.first { $0.focused && $0.id != Int(window.id) }
        _ = await AX.offMain { AX.focus(window.id, pid: window.pid) }
        guard try await waitFor({ await Desk.windows()?.first(where: { $0.id == Int(window.id) })?.focused == true }) else { return }
        await Desk.toggleFloating()
        if let previous { _ = await AX.offMain { AX.focus(CGWindowID(previous.id), pid: pid_t(previous.pid)) } }
        guard walk else { return }
        c.eyes = .happy
        c.say("tidy!")
        try await c.pause(1.5)
    }

    /// Gives back every borrowed window and re-tiles every floated one. Runs before Clawd quits.
    func cleanUp() async {
        stop()
        for window in loose { try? await tidy(window, walk: false) }
        for loan in loans { try? await giveBack(loan, walk: false) }
    }

    var owesWindows: Bool { !loans.isEmpty || !loose.isEmpty }

    @discardableResult
    private func waitFor(timeout: Double = 3, _ condition: () async -> Bool) async throws -> Bool {
        let end = now() + timeout
        while now() < end {
            if await condition() { return true }
            try await c.pause(0.1)
        }
        return false
    }
}
