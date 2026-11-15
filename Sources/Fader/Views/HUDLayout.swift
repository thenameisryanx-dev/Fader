import AppKit

/// Where the shortcut overlay goes, the way macOS places its own volume popup: hanging below
/// the menu bar icon, or at the top middle of the screen when the menu bar is hidden (an app in
/// full screen). Pure math, so it can be tested without a screen.
enum HUDLayout {
    /// Space between the overlay and the icon above it, or the top of the screen.
    static let gap: CGFloat = 6
    /// Closest the overlay gets to the sides of the screen.
    static let margin: CGFloat = 8

    /// - Parameters:
    ///   - screen: the whole screen; `visible` is the part below the menu bar.
    ///   - menuBarShowing: false while an app is in full screen.
    ///   - icon: Fader's menu bar icon, if it has one on screen.
    static func frame(
        for size: CGSize, screen: CGRect, visible: CGRect, menuBarShowing: Bool, icon: CGRect?
    ) -> CGRect {
        if menuBarShowing, let icon, screen.intersects(icon) {
            let top = min(icon.minY, visible.maxY) - gap
            let x = min(max(icon.midX - size.width / 2, visible.minX + margin), visible.maxX - margin - size.width)
            return CGRect(x: x, y: top - size.height, width: size.width, height: size.height)
        }
        let top = (menuBarShowing ? visible.maxY : screen.maxY) - gap
        return CGRect(x: screen.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height)
    }
}

/// Whether a screen's menu bar is showing. While an app is in full screen, macOS takes the menu
/// bar window off the screen. Apple's own "is the menu bar visible" and "visible frame" answers
/// don't change for other apps' full screen (checked on macOS 27.2), so this asks the list of
/// on-screen windows. Window sizes and positions don't need Screen Recording permission.
enum MenuBarCheck {
    /// - Parameters:
    ///   - menuBarWindows: frames of the on-screen menu bar windows, in window-list coordinates
    ///     (measured from the top-left of the main screen).
    ///   - display: the screen's frame in the same coordinates.
    static func isShowing(menuBarWindows: [CGRect], on display: CGRect) -> Bool {
        menuBarWindows.contains { $0.height > 0 && display.intersects($0) }
    }

    @MainActor
    static func isShowing(on screen: NSScreen) -> Bool {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return true }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let menuBarLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
        let menuBars = windows.compactMap { window -> CGRect? in
            guard window[kCGWindowLayer as String] as? Int == menuBarLevel,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary
            else { return nil }
            return CGRect(dictionaryRepresentation: bounds as CFDictionary)
        }
        return isShowing(menuBarWindows: menuBars, on: CGDisplayBounds(number.uint32Value))
    }
}
