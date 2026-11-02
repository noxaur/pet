import AppKit

enum Eyes: Equatable { case open, blink, closed, happy, wide, squint, dizzy }
enum Arms: Equatable { case down, up, wave, reach, hold }
enum Costume: Equatable { case none, witch, santa, party, ghost }
enum Movie: Equatable { case watching, blink, laugh, gasp }

struct Pose: Equatable {
    var facing: CGFloat = 1
    var eyes: Eyes = .open
    var look = 0
    var arms: Arms = .down
    var armPhase = false
    var legs = 0
    var mouth = 0
    var squash: CGFloat = 1
    var tilt: CGFloat = 0
    var scale: CGFloat = 1
    var costume: Costume = .none
    var alpha: CGFloat = 1
    var turned = false
    var sitting = false
    var laptopFrame: Int?
    var movie: Movie?
}

/// Clawd on the 12 × 8 pixel grid of the official Claude Code art: an 8-wide body, two square eyes,
/// stubby arms and four legs. Rows count down from the top of the body; fractions draw finer detail.
enum Sprite {
    static let pixel: CGFloat = 6
    static let columns = 12
    static let rows = 8
    static var size: CGSize { CGSize(width: CGFloat(columns) * pixel, height: CGFloat(rows) * pixel) }

    // Colours of the official animation as Clawd decodes and draws it, so walking and typing match.
    static let body = CGColor(srgbRed: 219 / 255, green: 128 / 255, blue: 95 / 255, alpha: 1)
    static let shade = CGColor(srgbRed: 196 / 255, green: 114 / 255, blue: 84 / 255, alpha: 1)
    static let ink = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
    static let white = CGColor(srgbRed: 1, green: 0.98, blue: 0.95, alpha: 1)
    static let laptop = ink
    static let grey = CGColor(srgbRed: 0.47, green: 0.47, blue: 0.49, alpha: 1)
    static let greyLight = CGColor(srgbRed: 0.60, green: 0.60, blue: 0.62, alpha: 1)
    static let greyDark = CGColor(srgbRed: 0.34, green: 0.34, blue: 0.36, alpha: 1)
    static let greyBack = CGColor(srgbRed: 0.25, green: 0.25, blue: 0.27, alpha: 1)
    static let glow = CGColor(srgbRed: 0.35, green: 0.55, blue: 1.0, alpha: 1)
    static let frame3D = CGColor(srgbRed: 0.97, green: 0.96, blue: 0.93, alpha: 1)
    static let redLens = CGColor(srgbRed: 0.92, green: 0.15, blue: 0.20, alpha: 1)
    static let blueLens = CGColor(srgbRed: 0.20, green: 0.62, blue: 0.95, alpha: 1)
    static let blueEye = CGColor(srgbRed: 0.03, green: 0.15, blue: 0.32, alpha: 1)
    static let pumpkin = CGColor(srgbRed: 0.95, green: 0.64, blue: 0.23, alpha: 1)
    static let red = CGColor(srgbRed: 0.82, green: 0.16, blue: 0.18, alpha: 1)
    static let teal = CGColor(srgbRed: 0.27, green: 0.68, blue: 0.66, alpha: 1)
    static let yellow = CGColor(srgbRed: 0.98, green: 0.82, blue: 0.27, alpha: 1)

    static func draw(_ pose: Pose, at feet: CGPoint, in ctx: CGContext, pixel s: CGFloat = pixel) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setAlpha(pose.alpha)
        ctx.setShouldAntialias(pose.tilt != 0)
        ctx.translateBy(x: feet.x, y: feet.y)
        ctx.scaleBy(x: pose.scale, y: pose.scale)
        let middle = CGFloat(rows) * s / 2
        ctx.translateBy(x: 0, y: middle)
        ctx.rotate(by: pose.tilt)
        ctx.translateBy(x: 0, y: -middle)
        ctx.scaleBy(x: (2 - pose.squash) * pose.facing, y: pose.squash)

        func px(_ c: CGFloat, _ r: CGFloat, _ w: CGFloat = 1, _ h: CGFloat = 1, _ color: CGColor = body) {
            ctx.setFillColor(color)
            ctx.fill(CGRect(x: (c - CGFloat(columns) / 2) * s, y: (CGFloat(rows) - r - h) * s, width: w * s, height: h * s))
        }

        if pose.costume == .ghost {
            let sheet = CGColor(srgbRed: 0.97, green: 0.97, blue: 1, alpha: 0.92)
            px(2, -1, 8, 1, sheet)
            px(1, 0, 10, 7, sheet)
            for c in stride(from: 1, to: 11, by: 3) { px(CGFloat(c) + (pose.armPhase ? 1.5 : 0), 7, 1.5, 1, sheet) }
            px(3, 1, 1, 2, ink)
            px(8, 1, 1, 2, ink)
            px(5.5, 4, 1, pose.mouth > 0 ? 1 : 0.5, ink)
            return
        }

        if let movie = pose.movie { return drawMovie(movie, in: ctx, pixel: s) }
        if let i = pose.laptopFrame, let laptop = Official.laptop, laptop.frames.indices.contains(i) {
            let k = s / pixel
            ctx.interpolationQuality = .none
            ctx.draw(laptop.frames[i], in: CGRect(x: laptop.rect.minX * k, y: laptop.rect.minY * k,
                                                  width: laptop.rect.width * k, height: laptop.rect.height * k))
            return
        }
        if pose.sitting { return drawSitting(pose, in: ctx, pixel: s, hat: px) }

        // Turned slightly towards where he walks: the back edge in shade and the face one pixel forward.
        let t: CGFloat = pose.turned ? 1 : 0
        px(2, 0, 8, 6)
        if pose.turned { px(2, 0, 1, 6, shade) }

        switch pose.arms {
        case .down:
            if pose.turned { px(1, 2, 1, 2, shade) } else { px(0, 2, 2, 2) }
            px(10, 2, 2, 2)
        case .up, .hold:
            px(0, 0, 2, 2); px(10, 0, 2, 2)
        case .wave:
            px(0, 2, 2, 2)
            if pose.armPhase { px(10, 0, 2, 2) } else { px(10, 1, 2, 2) }
        case .reach:
            px(0, 2, 2, 2); px(10, 2, 3, 2)
        }

        let lift: [CGFloat] = switch pose.legs {
        case 1: [2, 1, 2, 1]
        case 2: [1, 2, 1, 2]
        case 3: [1, 1, 1, 1]
        default: [2, 2, 2, 2]
        }
        for (i, c) in [2, 4, 7, 9].enumerated() { px(CGFloat(c), 6, 1, lift[i], pose.turned && c == 2 ? shade : body) }

        let look = CGFloat(pose.look) * 0.5
        for e in [3 + t + look, 8 + t + look] {
            switch pose.eyes {
            case .open: px(e, 1, 1, 1, ink)
            case .blink, .closed: px(e, 1.5, 1, 0.5, ink)
            case .squint: px(e, 1.25, 1, 0.5, ink)
            case .happy: px(e, 1, 1, 0.5, ink); px(e - 0.5, 1.5, 0.5, 0.5, ink); px(e + 1, 1.5, 0.5, 0.5, ink)
            case .wide: px(e, 0.5, 1, 1.5, ink); px(e, 0.5, 0.5, 0.5, white)
            case .dizzy: px(e, 1, 0.5, 0.5, ink); px(e + 0.5, 1.5, 0.5, 0.5, ink)
            }
        }
        if pose.mouth > 0 { px(5.5 + t, 2.5, 1, 0.5 * CGFloat(pose.mouth), ink) }

        drawHat(pose.costume, px)
    }

    private static func drawHat(_ costume: Costume, _ px: (CGFloat, CGFloat, CGFloat, CGFloat, CGColor) -> Void) {
        switch costume {
        case .santa:
            px(2, -1, 8, 1, white)
            px(3, -2, 6, 1, red); px(4, -3, 4, 1, red); px(6, -4, 3, 1, red)
            px(8.5, -5, 1.5, 1.5, white)
        case .party:
            px(4, -1, 4, 1, teal); px(4.5, -2, 3, 1, yellow); px(5, -3, 2, 1, teal)
            px(5.5, -4, 1, 1, yellow); px(5.5, -5, 1, 1, red)
        case .none, .witch, .ghost:
            // Halloween keeps the ghost and the greetings, but Clawd goes without the witch hat.
            break
        }
    }

    /// Clawd sitting side-on at his laptop, typing, in the half pixels of the official art:
    /// a shaded back, one eye, the arm on the keyboard and the open laptop in front of him.
    private static func drawSitting(_ pose: Pose, in ctx: CGContext, pixel s: CGFloat,
                                    hat px: (CGFloat, CGFloat, CGFloat, CGFloat, CGColor) -> Void) {
        let u = s / 2
        func dot(_ c: Int, _ r: Int, _ w: Int, _ h: Int, _ color: CGColor) {
            ctx.setFillColor(color)
            ctx.fill(CGRect(x: CGFloat(c - 7) * u, y: CGFloat(14 - r - h) * u, width: CGFloat(w) * u, height: CGFloat(h) * u))
        }

        dot(5, 0, 10, 11, body)
        dot(15, 0, 2, 3, body)
        dot(15, 5, 2, 6, body)
        dot(1, 0, 4, 11, shade)
        dot(17, 9, 2, 2, body)

        for (c, w, color) in [(1, 2, shade), (4, 2, body), (10, 2, body), (14, 2, body)] { dot(c, 11, w, 3, color) }
        dot(0, 12, 1, 2, shade)

        let lift = pose.armPhase ? 0 : 1
        dot(17, 5 + lift, 4, 4, shade)
        dot(17, 7 + lift, 3, 2, body)

        switch pose.eyes {
        case .blink, .closed: dot(7, 4, 2, 1, ink)
        case .happy: dot(7, 3, 2, 1, ink); dot(6, 4, 1, 1, ink); dot(9, 4, 1, 1, ink)
        case .wide: dot(7, 2, 2, 3, ink); dot(7, 2, 1, 1, white)
        default: dot(7, 3, 2, 2, ink)
        }

        dot(18, 13, 6, 1, laptop)
        for i in 0..<5 { dot(23 + i, 12 - i, 2, 1, laptop) }
        drawHat(pose.costume, { c, r, w, h, color in px(c + 1, r + 1, w, h, color) })
    }

    /// Clawd reclining in a grey home-cinema chair with red and blue 3D glasses on, side-on like his laptop
    /// pose, on half pixels with the floor at row 22: the back with its headrest, the seat, the footrest
    /// with his legs stretched out on it, and the armrest along his side with a cup holder.
    private static func drawMovie(_ look: Movie, in ctx: CGContext, pixel s: CGFloat) {
        let u = s / 2
        func dot(_ c: Int, _ r: Int, _ w: Int, _ h: Int, _ color: CGColor) {
            ctx.setFillColor(color)
            ctx.fill(CGRect(x: CGFloat(c - 12) * u, y: CGFloat(22 - r - h) * u, width: CGFloat(w) * u, height: CGFloat(h) * u))
        }

        dot(0, -3, 6, 1, greyBack); dot(-1, -2, 7, 5, greyBack)
        dot(2, -3, 3, 1, grey); dot(2, -2, 4, 5, grey); dot(2, -2, 4, 1, greyLight)
        dot(0, 3, 7, 6, greyBack); dot(3, 3, 4, 6, grey); dot(3, 3, 4, 1, greyDark)
        dot(1, 9, 7, 8, greyBack); dot(4, 9, 4, 8, grey); dot(4, 9, 4, 1, greyDark)
        dot(1, 14, 3, 3, greyBack); dot(4, 14, 16, 3, grey)

        dot(6, 3, 4, 11, shade)
        dot(10, 3, 10, 11, body)
        dot(20, 3, 2, 3, body)
        dot(20, 8, 2, 6, body)
        if look == .laugh || look == .gasp { dot(20, 6, 2, look == .gasp ? 2 : 1, ink) }

        // The blue lens over the eye we see, the red one peeking past his face, the arm back to his ear.
        dot(6, 5, 5, 1, frame3D)
        dot(10, 4, 6, 4, frame3D)
        dot(11, 5, 4, 2, blueLens)
        dot(15, 4, 7, 1, frame3D)
        dot(20, 4, 3, 3, frame3D)
        dot(21, 5, 2, 1, redLens)
        switch look {
        case .watching: dot(12, 5, 2, 2, blueEye)
        case .blink: dot(12, 6, 2, 1, blueEye)
        case .laugh: dot(12, 5, 2, 1, blueEye)
        case .gasp: dot(12, 5, 2, 2, blueEye); dot(11, 5, 1, 1, blueEye)
        }

        dot(18, 14, 10, 2, grey); dot(18, 14, 10, 1, greyLight); dot(27, 14, 1, 2, greyDark)
        dot(23, 16, 2, 3, ink)
        dot(22, 11, 5, 1, shade)
        dot(22, 12, 6, 2, body)

        dot(3, 10, 3, 6, greyBack)
        dot(6, 10, 13, 6, grey)
        dot(6, 10, 13, 1, greyLight)
        dot(6, 15, 13, 1, greyDark)
        dot(16, 10, 2, 1, ink)
        dot(12, 8, 5, 2, shade)
        dot(12, 9, 4, 1, body)

        dot(1, 17, 21, 3, greyBack)
        dot(1, 20, 21, 1, ink)
        dot(2, 21, 19, 1, glow)
    }

    static func icon() -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 16), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            draw(Pose(), at: CGPoint(x: 11, y: 2), in: ctx, pixel: 1.6)
            return true
        }
        return image
    }
}
