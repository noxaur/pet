import AppKit

@main
@MainActor
enum Main {
    static func main() {
        let arguments = CommandLine.arguments
        if arguments.count == 3, arguments[1] == "do" {
            DistributedNotificationCenter.default().postNotificationName(AppDelegate.command, object: arguments[2],
                                                                         userInfo: nil, deliverImmediately: true)
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let clawd = Clawd()
    let effects = Effects()
    lazy var brain = Brain(clawd: clawd, effects: effects)
    private var item: NSStatusItem?
    private var terminate: DispatchSourceSignal?
    static let command = Notification.Name("com.noxaur.clawd.do")

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !AXIsProcessTrusted() {
            let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        }
        Official.load()
        clawd.baseCostume = Self.costume(on: Date())
        clawd.costume = clawd.baseCostume
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let frame = screen.visibleFrame
        clawd.start(at: CGPoint(x: frame.midX + .random(in: -frame.width / 4...frame.width / 4), y: frame.maxY - 80))
        brain.start(brain.entrance)
        buildMenu()

        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { RunLoop.main.perform { NSApp.terminate(nil) } }
        source.resume()
        terminate = source

        DistributedNotificationCenter.default().addObserver(self, selector: #selector(command(_:)),
                                                            name: Self.command, object: nil)
    }

    /// `Clawd do <behaviour>` from a shell runs that behaviour in the running Clawd.
    @objc private func command(_ notification: Notification) {
        guard let name = notification.object as? String else { return }
        if name == "giveback" {
            return brain.perform {
                for window in self.brain.loose { try await self.brain.tidy(window) }
                for loan in self.brain.loans { try await self.brain.giveBack(loan) }
            }
        }
        guard let act = brain.behaviours[name] else { return clawd.say("i don't know how to \(name).") }
        brain.perform(act)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard brain.owesWindows else { return .terminateNow }
        Task {
            await brain.cleanUp()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    static func costume(on date: Date) -> Costume {
        let day = Calendar.current.dateComponents([.month, .day], from: date)
        switch (day.month ?? 0, day.day ?? 0) {
        case (10, 15...), (11, 1): return .witch
        case (12, _): return .santa
        default: return .none
        }
    }

    private func buildMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Sprite.icon()
        item.button?.toolTip = "Clawd"
        let menu = NSMenu()
        menu.addItem(withTitle: "Clawd", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())
        for (title, name) in [("Drag a Window", "drag"), ("Fetch a Window from Another Desktop", "fetch")] {
            menu.addItem(MenuAction(title) { [brain] in brain.behaviours[name].map(brain.perform) })
        }
        menu.addItem(MenuAction("Give Everything Back") { [weak self] in
            let note = Notification(name: Self.command, object: "giveback")
            self?.command(note)
        })
        menu.addItem(MenuAction("Party!") { [brain] in brain.perform(brain.party) })
        menu.addItem(.separator())
        let mischief = MenuAction("Mischief") { [brain] in brain.mischief.toggle() }
        mischief.state = .on
        mischief.update = { [brain] in brain.mischief ? .on : .off }
        menu.addItem(mischief)
        menu.addItem(MenuAction("Hide Clawd") { [clawd, brain] in
            if clawd.panel.isVisible {
                brain.stop()
                clawd.panel.orderOut(nil)
            } else {
                clawd.panel.orderFrontRegardless()
                brain.start()
            }
        })
        menu.addItem(.separator())
        menu.addItem(MenuAction("Quit Clawd", key: "q") { NSApp.terminate(nil) })
        menu.delegate = self
        item.menu = menu
        self.item = item
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        for case let item as MenuAction in menu.items {
            if let update = item.update { item.state = update() }
            if item.title.hasSuffix("Clawd"), item.title != "Quit Clawd" {
                item.title = clawd.panel.isVisible ? "Hide Clawd" : "Show Clawd"
            }
        }
    }
}

final class MenuAction: NSMenuItem {
    private let run: () -> Void
    var update: (() -> NSControl.StateValue)?

    init(_ title: String, key: String = "", run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { run() }
}
