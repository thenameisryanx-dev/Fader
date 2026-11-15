import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class HUDState {
    var name = ""
    var icon: NSImage?
    var volume: Float = 1
    var muted = false
}

/// The small on-screen overlay shown when a shortcut changes an app's volume.
@MainActor
final class HUDController {
    private let state = HUDState()
    private(set) var panel: NSPanel?
    /// The next step in hiding the overlay: start fading, then take the window away. A new press
    /// cancels whichever step is waiting, so an old fade can't hide an overlay that was just shown.
    private var hideTimer: Timer?
    /// Where Fader's menu bar icon is on screen, so the overlay can hang below it.
    var menuBarIconFrame: () -> CGRect? = { nil }
    /// How long the overlay stays after the last press, and how long it takes to fade out.
    var hideDelay: TimeInterval = 1.2
    var fadeDuration: TimeInterval = 0.25
    /// Tests use this to put the overlay somewhere off screen instead of under the menu bar.
    var placeOverride: ((NSPanel) -> Void)?

    func show(name: String, icon: NSImage?, volume: Float, muted: Bool) {
        state.name = name
        state.icon = icon
        state.volume = volume
        state.muted = muted

        let panel = self.panel ?? Self.makePanel(showing: HUDView(state: state))
        self.panel = panel
        // Only when it appears: holding a shortcut keeps it in one place.
        let appearing = !panel.isVisible
        if appearing { (placeOverride ?? position)(panel) }
        panel.alphaValue = 1  // also stops a fade-out that's under way
        panel.orderFrontRegardless()
        // The shadow takes the window's shape: work it out from the rounded glass, not a square.
        if appearing { panel.invalidateShadow() }

        hideTimer?.invalidate()
        hideTimer = after(hideDelay) { [weak self] in self?.fadeOut() }
    }

    private func fadeOut() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeDuration
            panel.animator().alphaValue = 0
        }
        hideTimer = after(fadeDuration) { panel.orderOut(nil) }
    }

    private func after(_ seconds: TimeInterval, run step: @escaping @MainActor () -> Void) -> Timer {
        let timer = Timer(timeInterval: seconds, repeats: false) { _ in MainActor.assumeIsolated(step) }
        // .common: it still fires while a menu is open or a slider is being dragged.
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    static func makePanel(showing view: HUDView) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        // Real Liquid Glass, built exactly like the menu (see GlassSurface).
        panel.contentView = GlassSurface.make(
            around: NSHostingView(rootView: view), cornerRadius: Theme.hudCornerRadius, fallback: .hudWindow
        )
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let frame = HUDLayout.frame(
            for: panel.frame.size,
            screen: screen.frame,
            visible: screen.visibleFrame,
            menuBarShowing: MenuBarCheck.isShowing(on: screen),
            icon: menuBarIconFrame()
        )
        panel.setFrameOrigin(frame.origin)
    }
}

struct HUDView: View {
    let state: HUDState

    var body: some View {
        HStack(spacing: 12) {
            if let icon = state.icon {
                Image(nsImage: icon).resizable().frame(width: 32, height: 32)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(state.name).font(.headline).lineLimit(1)
                if state.muted {
                    Label("Muted", systemImage: "speaker.slash.fill")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    // Apple's bar slides to each new value over about half a second, so it lagged
                    // behind every shortcut press. A new id gives SwiftUI a fresh bar for each
                    // value, and a fresh bar starts out already filled to it.
                    ProgressView(value: Double(state.volume))
                        .progressViewStyle(.linear)
                        .id(state.volume)
                }
            }
            Text(state.muted ? "" : "\(Int((state.volume * 100).rounded()))%")
                .font(.callout.monospacedDigit())
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(width: 280, height: 64)
    }
}
