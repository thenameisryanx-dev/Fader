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
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(name: String, icon: NSImage?, volume: Float, muted: Bool) {
        state.name = name
        state.icon = icon
        state.volume = volume
        state.muted = muted

        let panel = self.panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak panel] in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                panel?.animator().alphaValue = 0
            } completionHandler: {
                MainActor.assumeIsolated { panel?.orderOut(nil) }
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    private func makePanel() -> NSPanel {
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
        panel.contentView = NSHostingView(rootView: HUDView(state: state))
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 120))
    }
}

private struct HUDView: View {
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
                    ProgressView(value: Double(state.volume))
                        .progressViewStyle(.linear)
                }
            }
            Text(state.muted ? "" : "\(Int((state.volume * 100).rounded()))%")
                .font(.callout.monospacedDigit())
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(width: 280, height: 64)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
