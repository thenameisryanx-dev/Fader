import AppKit
import SwiftUI

/// Where the menu goes on screen. Pure math, so it can be tested without a screen.
enum MenuPanelLayout {
    /// Space between the menu bar and the top of the menu.
    static let gap: CGFloat = 2
    /// Closest the menu gets to the sides and bottom of the screen.
    static let margin: CGFloat = 8

    /// A frame exactly as big as `content`, hanging below the menu bar `icon` and lined up with it,
    /// moved left if needed to stay on `screen` (its visible frame, without the menu bar).
    static func frame(for content: CGSize, below icon: CGRect, on screen: CGRect) -> CGRect {
        let top = min(icon.minY, screen.maxY) - gap
        let height = min(content.height, top - screen.minY - margin)
        let x = min(max(icon.minX, screen.minX + margin), screen.maxX - margin - content.width)
        return CGRect(x: x, y: top - height, width: content.width, height: height)
    }
}

/// The window that drops down from the menu bar icon, sized to its SwiftUI content.
///
/// Apple's `MenuBarExtra` sizes its window itself and came out about 19 points too tall,
/// leaving an empty strip at the top. Here every size change of the content resizes the window,
/// keeping its top edge under the menu bar.
@MainActor
final class MenuPanel {
    let window: NSPanel
    /// Called when the menu should close by itself: on Escape, or when another window takes over.
    var onDismiss: (() -> Void)?
    private let hostingView: NSHostingView<AnyView>
    private let sizeReporter = SizeReporter()
    private var icon: CGRect = .zero
    private var screen: CGRect = .zero

    init(rootView: some View) {
        let sizeReporter = sizeReporter
        hostingView = NSHostingView(rootView: AnyView(
            rootView
                .fixedSize()  // always its ideal size, never squeezed to the window's current size
                .onGeometryChange(for: CGSize.self, of: { $0.size }) { _, _ in sizeReporter.onChange?() }
        ))
        hostingView.sizingOptions = [.intrinsicContentSize]

        let panel = KeyablePanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        window = panel
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .popUpMenu
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]

        // The frosted background of a real menu, with rounded corners.
        let background = NSVisualEffectView()
        background.material = .menu
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = Self.roundedMask(radius: 12)
        window.contentView = background

        hostingView.frame = background.bounds
        hostingView.autoresizingMask = [.width, .height]
        background.addSubview(hostingView)

        sizeReporter.onChange = { [weak self] in
            // Resize after SwiftUI finishes the current layout pass, not in the middle of it.
            RunLoop.main.perform(inModes: [.common]) {
                MainActor.assumeIsolated { self?.fitToContent() }
            }
        }
        panel.onEscape = { [weak self] in self?.onDismiss?() }
        panel.onResignKey = { [weak self] in self?.onDismiss?() }
    }

    var isVisible: Bool { window.isVisible }

    /// Opens the menu below the menu bar `icon` on `screen` (its visible frame).
    func show(below icon: CGRect, on screen: CGRect) {
        self.icon = icon
        self.screen = screen
        fitToContent()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window.orderOut(nil)
    }

    private func fitToContent() {
        hostingView.layoutSubtreeIfNeeded()
        let frame = MenuPanelLayout.frame(for: hostingView.fittingSize, below: icon, on: screen)
        if window.frame != frame {
            window.setFrame(frame, display: window.isVisible)
        }
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

/// A borderless panel can't take keyboard focus unless it says so; the menu needs it for Escape.
private final class KeyablePanel: NSPanel {
    var onEscape: (() -> Void)?
    var onResignKey: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

/// Passes the content's size changes from SwiftUI to the window.
@MainActor
private final class SizeReporter {
    var onChange: (() -> Void)?
}

/// Fader's icon in the menu bar. Clicking it opens and closes the menu.
@MainActor
final class MenuBarController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel: MenuPanel
    private var clickOutsideMonitor: Any?

    init(rootView: some View) {
        panel = MenuPanel(rootView: rootView)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "slider.vertical.3", accessibilityDescription: "Fader")
            button.target = self
            button.action = #selector(iconClicked)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
        // Close like a menu does: on Escape, or when another window takes over (e.g. Settings).
        panel.onDismiss = { [weak self] in self?.close() }
    }

    @objc private func iconClicked() {
        if panel.isVisible { close() } else { open() }
    }

    func open() {
        guard let button = statusItem.button, let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main else { return }
        let icon = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        // Like Apple's menus: Fader becomes the active app while its menu is open,
        // so the sliders show in the accent colour instead of grey.
        NSApp.activate()
        panel.show(below: icon, on: screen.visibleFrame)
        button.highlight(true)
        // Clicks in other apps, on the desktop or on other menu bar icons close the menu.
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    func close() {
        guard panel.isVisible else { return }
        panel.close()
        statusItem.button?.highlight(false)
        if let clickOutsideMonitor { NSEvent.removeMonitor(clickOutsideMonitor) }
        clickOutsideMonitor = nil
        // Hand the keyboard back to the app that had it, unless a Fader window (Settings) is open.
        if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
            NSApp.deactivate()
        }
    }
}
