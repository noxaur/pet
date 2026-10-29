import AppKit
import AVFoundation

/// The official Clawd laptop animation, read at launch from the Claude app installed on this Mac
/// rather than shipped with Clawd. Without the Claude app, Clawd draws his own laptop pose instead.
enum Official {
    /// Frames that take out the laptop and sit down, type in a loop, and pack up again.
    static let intro = 0...16, typing = 17...33, outro = 34...42
    static let fps = 12.0

    /// Every frame cropped to the same box, and that box in points relative to Clawd's feet,
    /// scaled so the standing Clawd of the first frame is as wide as `Sprite.size`.
    /// Set once on the main thread when the frames are ready.
    nonisolated(unsafe) static var laptop: (frames: [CGImage], rect: CGRect)?

    @MainActor static func load() {
        Task.detached(priority: .utility) {
            guard let loaded = try? await decode() else { return }
            await MainActor.run { laptop = loaded }
        }
    }

    private static func decode() async throws -> (frames: [CGImage], rect: CGRect)? {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop"),
              let movie = try extract("images/install-hub/clawd-laptop.mov",
                                      from: app.appendingPathComponent("Contents/Resources/ion-dist.asar")) else { return nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: movie))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        // The video decoder sometimes hands back a frame whose colour is still empty, which shows as
        // solid green. Such a frame is decoded again, and if it stays green the previous frame stands in.
        var images: [CGImage] = []
        for i in 0...outro.upperBound {
            let time = CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps))
            var image = try await generator.image(at: time).image
            for _ in 0..<3 where isGreen(image) { image = try await generator.image(at: time).image }
            if isGreen(image), let previous = images.last { image = previous }
            images.append(image)
        }
        guard !images.contains(where: isGreen) else { return nil }

        let standing = opaqueBox(images[0])
        let box = images.map(opaqueBox).reduce(standing) { $0.union($1) }
        guard standing.width > 0 else { return nil }
        let scale = Sprite.size.width / standing.width
        let rect = CGRect(x: (box.minX - standing.midX) * scale, y: (standing.maxY - box.maxY) * scale,
                          width: box.width * scale, height: box.height * scale)

        // Two device pixels per point, scaled without smoothing so the pixel art stays crisp.
        let width = Int(rect.width * 2), height = Int(rect.height * 2)
        let frames: [CGImage] = images.compactMap { image in
            guard let crop = image.cropping(to: box),
                  let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.interpolationQuality = .none
            ctx.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
            return ctx.makeImage()
        }
        return frames.count == images.count ? (frames, rect) : nil
    }

    /// Copies one file out of an Electron asar archive into Clawd's caches folder.
    private static func extract(_ path: String, from archive: URL) throws -> URL? {
        let file = try FileHandle(forReadingFrom: archive)
        defer { try? file.close() }
        guard let head = try file.read(upToCount: 16), head.count == 16 else { return nil }
        func word(_ at: Int) -> Int { Int(head[at..<at + 4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }) }
        guard let json = try file.read(upToCount: word(12)),
              var node = try JSONSerialization.jsonObject(with: json) as? [String: Any] else { return nil }
        for part in path.split(separator: "/") {
            guard let files = node["files"] as? [String: Any], let next = files[String(part)] as? [String: Any] else { return nil }
            node = next
        }
        guard let offset = (node["offset"] as? String).flatMap(UInt64.init), let size = node["size"] as? Int else { return nil }
        try file.seek(toOffset: UInt64(8 + word(4)) + offset)
        guard let data = try file.read(upToCount: size), data.count == size else { return nil }

        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("com.noxaur.clawd")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent((path as NSString).lastPathComponent)
        try data.write(to: url)
        return url
    }

    /// Whether most opaque pixels of `image` are greener than they are red. Clawd is orange.
    private static func isGreen(_ image: CGImage) -> Bool {
        let width = image.width / 16, height = image.height / 16
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return false }
        var opaque = 0, green = 0
        for i in stride(from: 0, to: width * height * 4, by: 4) where data[i + 3] > 200 {
            opaque += 1
            if data[i + 1] > data[i] { green += 1 }
        }
        return opaque > 0 && green * 2 > opaque
    }

    /// The box around the pixels of `image` that are not transparent, in image pixels from the top left.
    private static func opaqueBox(_ image: CGImage) -> CGRect {
        let width = image.width / 4, height = image.height / 4
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return .zero }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return .zero }
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where data[(y * width + x) * 4 + 3] > 128 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return .zero }
        return CGRect(x: minX * 4, y: minY * 4, width: (maxX - minX + 1) * 4, height: (maxY - minY + 1) * 4)
    }
}
