import AppKit

/// The background of Fader's own windows (the menu and the shortcut overlay): Apple's Liquid Glass
/// on macOS 26 and later, the older frosted material before that.
///
/// Apple's guidance for AppKit is to put the content *inside* an `NSGlassEffectView` (its
/// `contentView`) rather than drawing glass behind it, so macOS keeps the content readable on
/// the glass. The system adapts the glass for Reduce Transparency and Increase Contrast by itself.
@MainActor
enum GlassSurface {
    /// Wraps `content` in glass with rounded corners. Use the result as the window's content view.
    static func make(around content: NSView, cornerRadius: CGFloat, fallback: NSVisualEffectView.Material) -> NSView {
        content.autoresizingMask = [.width, .height]
        let background: NSView
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular  // Apple's pick for anything over content that could be busy
            glass.cornerRadius = cornerRadius
            glass.contentView = content
            background = glass
        } else {
            let frosted = NSVisualEffectView()
            frosted.material = fallback
            frosted.blendingMode = .behindWindow
            frosted.state = .active
            frosted.maskImage = roundedMask(radius: cornerRadius)
            content.frame = frosted.bounds
            frosted.addSubview(content)
            background = frosted
        }
        return roundedClip(around: background, radius: cornerRadius)
    }

    /// A view that cuts `content` to rounded corners. The glass view's backdrop (the part that
    /// blurs what's behind the window) is a full rectangle, and macOS draws the window's shadow
    /// around it, which showed as a faint square outline around the rounded shape.
    private static func roundedClip(around content: NSView, radius: CGFloat) -> NSView {
        let clip = NSView()
        clip.wantsLayer = true
        clip.layer?.cornerRadius = radius
        clip.layer?.cornerCurve = .continuous  // the same curve as Liquid Glass corners
        clip.layer?.masksToBounds = true
        content.frame = clip.bounds
        content.autoresizingMask = [.width, .height]
        clip.addSubview(content)
        return clip
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let size = NSSize(width: radius * 2 + 1, height: radius * 2 + 1)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
