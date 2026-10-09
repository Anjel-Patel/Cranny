import AppKit

@MainActor
enum Haptics {
    static func tap(_ pattern: NSHapticFeedbackManager.FeedbackPattern = .alignment) {
        guard !AppSettings.shared.disableHaptics else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    var hasNotch: Bool {
        auxiliaryTopLeftArea != nil && auxiliaryTopRightArea != nil && safeAreaInsets.top > 0
    }

    /// Size of the camera housing, measured from the menu bar areas on either side of it.
    var notchSize: CGSize {
        guard let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else { return .zero }
        let width = frame.width - left.width - right.width
        return CGSize(width: max(0, width), height: safeAreaInsets.top)
    }

    var menuBarHeight: CGFloat {
        let h = frame.maxY - visibleFrame.maxY
        return h > 0 ? h : 24
    }

    var notchGeometry: NotchGeometry { NotchGeometry(screen: self) }
}

/// Where a screen's notch is. Developers can simulate other Macs on the main screen with
/// `defaults write io.github.rdbms234.Cranny debugNotchSize 200x38`, or `none` for a Mac
/// without a notch (relaunch Cranny afterwards).
struct NotchGeometry {
    let hasNotch: Bool
    let size: CGSize
    /// Horizontal centre of the notch in screen coordinates.
    let midX: CGFloat

    init(screen: NSScreen) {
        var hasNotch = screen.hasNotch
        var size = screen.notchSize
        var midX = screen.frame.midX
        if hasNotch, let left = screen.auxiliaryTopLeftArea, size.width > 0 {
            midX = screen.frame.minX + left.width + size.width / 2
        }
        if screen == NSScreen.screens.first, let override = UserDefaults.standard.string(forKey: "debugNotchSize") {
            if override.lowercased() == "none" {
                hasNotch = false
                size = .zero
                midX = screen.frame.midX
            } else {
                let parts = override.lowercased().split(separator: "x").compactMap { Double($0) }
                if parts.count == 2, (60...400).contains(parts[0]), (16...60).contains(parts[1]) {
                    hasNotch = true
                    size = CGSize(width: parts[0], height: parts[1])
                    midX = screen.frame.midX
                }
            }
        }
        self.hasNotch = hasNotch
        self.size = size
        self.midX = midX
    }
}

enum ImageTools {
    /// Accent colour of an image, biased towards saturated, bright pixels and
    /// lifted so it stays readable on a black background.
    static func accentColor(of image: NSImage) -> NSColor? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let side = 12
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }

        var r = 0.0, g = 0.0, b = 0.0, total = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let pr = Double(pixels[i]) / 255, pg = Double(pixels[i + 1]) / 255, pb = Double(pixels[i + 2]) / 255
            let maxC = max(pr, pg, pb), minC = min(pr, pg, pb)
            let saturation = maxC == 0 ? 0 : (maxC - minC) / maxC
            let weight = 0.05 + saturation * saturation * maxC
            r += pr * weight; g += pg * weight; b += pb * weight; total += weight
        }
        guard total > 0 else { return nil }
        let base = NSColor(srgbRed: r / total, green: g / total, blue: b / total, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        base.usingColorSpace(.sRGB)?.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        return NSColor(hue: h, saturation: min(1, s * 1.15), brightness: max(0.7, v), alpha: 1)
    }
}
