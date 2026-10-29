import AppKit

struct Particle {
    enum Kind { case z, sweat, heart, dust, star, note, spark }
    var kind: Kind
    var p: CGPoint
    var v: CGPoint
    var life: Double
    var age: Double = 0
}

/// The panel content: Clawd, his shadow, the small particles around him and his speech bubble.
/// Every point is relative to `feet`, the bottom centre of the sprite.
final class MascotView: NSView {
    static let size = CGSize(width: 300, height: 240)
    static let feet = CGPoint(x: 150, y: 20)

    var pose = Pose()
    var bubble: String?
    var particles: [Particle] = []
    var showsShadow = true
    var onMouseDown: ((NSEvent) -> Void)?
    var onMouseDragged: ((NSEvent) -> Void)?
    var onMouseUp: ((NSEvent) -> Void)?

    private static let ink = NSColor(srgbRed: 0.11, green: 0.07, blue: 0.06, alpha: 1)
    private var measured: (text: String, string: NSAttributedString, fit: CGRect)?

    private static func font(_ size: CGFloat) -> NSFont {
        NSFont(name: "Menlo-Bold", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .bold)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onMouseDown?(event) }
    override func mouseDragged(with event: NSEvent) { onMouseDragged?(event) }
    override func mouseUp(with event: NSEvent) { onMouseUp?(event) }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let feet = Self.feet
        if showsShadow {
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.16))
            let half = Sprite.size.width * 0.42 * pose.scale
            ctx.fillEllipse(in: CGRect(x: feet.x - half, y: feet.y - 4, width: half * 2, height: 8))
        }
        Sprite.draw(pose, at: feet, in: ctx)
        for particle in particles { draw(particle, in: ctx) }
        if let bubble { draw(bubble: bubble, in: ctx) }
    }

    private func draw(_ particle: Particle, in ctx: CGContext) {
        let fade = CGFloat(max(0, 1 - particle.age / particle.life))
        let p = CGPoint(x: Self.feet.x + particle.p.x, y: Self.feet.y + particle.p.y)
        func square(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: CGColor) {
            ctx.setFillColor(color.copy(alpha: color.alpha * fade) ?? color)
            ctx.fill(CGRect(x: p.x + x, y: p.y + y, width: w, height: h))
        }
        switch particle.kind {
        case .dust:
            let size = 4 + 6 * (1 - fade)
            square(-size / 2, 0, size, size, CGColor(gray: 0.6, alpha: 0.7))
        case .sweat:
            square(0, 0, 3, 5, CGColor(srgbRed: 0.45, green: 0.75, blue: 1, alpha: 1))
        case .spark:
            square(0, 0, 4, 4, Sprite.body)
        case .star:
            square(-1, -4, 3, 9, Sprite.yellow); square(-4, -1, 9, 3, Sprite.yellow)
        case .heart:
            let pink = CGColor(srgbRed: 1, green: 0.42, blue: 0.55, alpha: 1)
            square(-5, 2, 4, 3, pink); square(1, 2, 4, 3, pink); square(-4, -1, 8, 3, pink); square(-2, -3, 4, 2, pink)
        case .z, .note:
            let text = particle.kind == .z ? "z" : "♪"
            let size = particle.kind == .z ? 11 + 7 * (1 - fade) : 15
            let attributes: [NSAttributedString.Key: Any] = [
                .font: Self.font(size),
                .foregroundColor: Self.ink.withAlphaComponent(fade)
            ]
            NSAttributedString(string: text, attributes: attributes).draw(at: p)
        }
    }

    private func draw(bubble text: String, in ctx: CGContext) {
        if text != measured?.text {
            let string = NSAttributedString(string: text, attributes: [.font: Self.font(12), .foregroundColor: Self.ink])
            measured = (text, string, string.boundingRect(with: NSSize(width: 230, height: 120), options: .usesLineFragmentOrigin))
        }
        guard let (_, string, fit) = measured else { return }
        let width = ceil(fit.width) + 18, height = ceil(fit.height) + 12
        let hatRoom: CGFloat = [.none, .witch, .ghost].contains(pose.costume) ? 12 : 48
        let base = Self.feet.y + Sprite.size.height * pose.scale + hatRoom
        let x = min(max(6, Self.feet.x - width / 2), bounds.width - width - 6)
        let box = CGRect(x: x, y: base + 8, width: width, height: height)

        let path = CGMutablePath()
        path.addRoundedRect(in: box, cornerWidth: 7, cornerHeight: 7)
        path.move(to: CGPoint(x: Self.feet.x - 7, y: box.minY))
        path.addLine(to: CGPoint(x: Self.feet.x - 2, y: box.minY - 9))
        path.addLine(to: CGPoint(x: Self.feet.x + 6, y: box.minY))
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 6, color: CGColor(gray: 0, alpha: 0.25))
        ctx.addPath(path)
        ctx.setFillColor(Sprite.white)
        ctx.fillPath()
        ctx.restoreGState()
        ctx.addPath(path)
        ctx.setStrokeColor(Sprite.ink)
        ctx.setLineWidth(2)
        ctx.setLineJoin(.round)
        ctx.strokePath()
        ctx.setFillColor(Sprite.white)
        ctx.fill(CGRect(x: Self.feet.x - 5, y: box.minY - 1.5, width: 9.5, height: 3))
        string.draw(with: box.insetBy(dx: 9, dy: 6), options: .usesLineFragmentOrigin)
    }
}
