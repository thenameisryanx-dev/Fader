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

    // MARK: Helpers

    private func spinRunLoop(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
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
