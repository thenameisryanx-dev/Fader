import AppKit
import SwiftUI
import Testing
@testable import Fader

/// The on-screen overlay a volume shortcut shows. Its bar is Apple's progress bar, which slides
/// to each new value over about half a second. Each shortcut press then showed up late on the bar,
/// and holding the key made it trail further behind.
@MainActor
struct HUDTests {
    @Test func barJumpsStraightToTheNewVolume() throws {
        let state = HUDState()
        state.name = "Music"
        state.volume = 0.2
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: 0, width: 280, height: 64),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: HUDView(state: state))
        window.orderFrontRegardless()
        defer { window.close() }
        spinRunLoop(0.3)

        state.volume = 0.8
        spinRunLoop(0.05)  // a fraction of the old slide, well under one shortcut repeat

        let bar = try #require(progressIndicator(in: window.contentView))
        #expect(abs(bar.doubleValue - 0.8) < 0.001)
        let sliding = layersStillMoving(bar.layer)
        #expect(sliding.isEmpty, "bar is still sliding: \(sliding)")
    }

    /// Bug: the overlay didn't look like Liquid Glass. It drew SwiftUI glass inside a plain square
    /// window, with a square shadow. Apple says to use AppKit's glass view with the content inside
    /// it, like Fader's menu: glass view, content inside, clipped to rounded corners.
    @Test func overlayIsLiquidGlassBuiltLikeTheMenu() throws {
        let panel = HUDController.makePanel(showing: HUDView(state: HUDState()))
        let clip = try #require(panel.contentView)
        let layer = try #require(clip.layer)
        #expect(layer.masksToBounds)
        #expect(layer.cornerRadius == Theme.hudCornerRadius)
        #expect(layer.cornerCurve == .continuous)
        #expect(!panel.isOpaque)
        #expect(panel.backgroundColor == .clear)

        if #available(macOS 26, *) {
            let glass = try #require(clip.subviews.first as? NSGlassEffectView)
            #expect(glass.cornerRadius == Theme.hudCornerRadius)
            #expect(glass.style == .regular)
            #expect(glass.contentView is NSHostingView<HUDView>)
        }

        // The content fills the glass exactly: nothing squashed, shifted or left as a bare edge.
        panel.layoutIfNeeded()
        let hosting = try #require(firstView(of: NSHostingView<HUDView>.self, in: clip))
        #expect(clip.frame.size == CGSize(width: 280, height: 64))
        #expect(hosting.convert(hosting.bounds, to: clip) == clip.bounds)
    }

    /// Bug: pressing a shortcut while the overlay was fading out made it vanish anyway. The old
    /// fade still finished and hid the window, even though a new press had just shown it.
    @Test func pressDuringFadeOutKeepsOverlayShowing() throws {
        let hud = HUDController()
        hud.hideDelay = 0.5
        hud.fadeDuration = 0.6
        hud.placeOverride = { $0.setFrameOrigin(NSPoint(x: -20_000, y: 0)) }

        hud.show(name: "Music", icon: nil, volume: 0.5, muted: false)
        spinRunLoop(0.8)  // the fade started at 0.5 s and would finish at 1.1 s
        let panel = try #require(hud.panel)
        #expect(panel.isVisible)
        #expect(panel.alphaValue < 1, "the fade should be under way before the second press")

        hud.show(name: "Music", icon: nil, volume: 0.6, muted: false)
        spinRunLoop(0.4)  // 1.2 s: past the old fade's end, before the new press's fade starts (1.3 s)
        #expect(panel.isVisible)
        #expect(panel.alphaValue == 1)

        spinRunLoop(1.0)  // 2.2 s: the new fade (1.3 s to 1.9 s) is over, so it has gone away on its own
        #expect(!panel.isVisible)
    }

    // MARK: Helpers

    private func spinRunLoop(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func firstView<V: NSView>(of type: V.Type, in view: NSView) -> V? {
        if let match = view as? V { return match }
        return view.subviews.lazy.compactMap { firstView(of: type, in: $0) }.first
    }

    private func progressIndicator(in view: NSView?) -> NSProgressIndicator? {
        guard let view else { return nil }
        if let bar = view as? NSProgressIndicator { return bar }
        return view.subviews.lazy.compactMap { progressIndicator(in: $0) }.first
    }

    /// Layers whose on-screen position or size hasn't reached where they're going yet.
    private func layersStillMoving(_ layer: CALayer?) -> [String] {
        guard let layer else { return [] }
        var moving: [String] = []
        if let shown = layer.presentation()?.frame, shown != layer.frame {
            moving.append("\(type(of: layer)) shown \(shown.width) wide, heading for \(layer.frame.width)")
        }
        for sublayer in layer.sublayers ?? [] { moving += layersStillMoving(sublayer) }
        return moving
    }
}
