import CoreGraphics
import Testing
@testable import Fader

/// Where the shortcut overlay goes. Like macOS's own volume popup: under the menu bar icon,
/// or at the top middle of the screen when there's no menu bar (an app in full screen).
struct HUDLayoutTests {
    // A 1440 × 900 screen with a 30 pt menu bar, far away from the real ones.
    let screen = CGRect(x: -20_000, y: 0, width: 1440, height: 900)
    let visible = CGRect(x: -20_000, y: 0, width: 1440, height: 870)
    let size = CGSize(width: 280, height: 64)
    var icon: CGRect { CGRect(x: -20_000 + 1000, y: 870, width: 31, height: 30) }

    // MARK: Placing the overlay

    @Test func hangsCentredBelowTheMenuBarIcon() {
        let frame = HUDLayout.frame(for: size, screen: screen, visible: visible, menuBarShowing: true, icon: icon)
        #expect(frame.size == size)
        #expect(frame.midX == icon.midX)
        #expect(frame.maxY == icon.minY - HUDLayout.gap)
    }

    @Test func staysOnScreenWhenTheIconIsNearTheRightEdge() {
        let nearEdge = CGRect(x: screen.maxX - 40, y: 870, width: 31, height: 30)
        let frame = HUDLayout.frame(for: size, screen: screen, visible: visible, menuBarShowing: true, icon: nearEdge)
        #expect(frame.maxX == visible.maxX - HUDLayout.margin)
    }

    @Test func goesToTheTopMiddleWhenAnAppIsFullScreen() {
        let frame = HUDLayout.frame(for: size, screen: screen, visible: visible, menuBarShowing: false, icon: icon)
        #expect(frame.size == size)
        #expect(frame.midX == screen.midX)
        // Right at the top of the screen, where the hidden menu bar would be.
        #expect(frame.maxY == screen.maxY - HUDLayout.gap)
    }

    @Test func goesToTheTopMiddleBelowTheMenuBarWhenTheIconIsOnAnotherScreen() {
        let otherScreenIcon = CGRect(x: 5000, y: 870, width: 31, height: 30)
        let frame = HUDLayout.frame(
            for: size, screen: screen, visible: visible, menuBarShowing: true, icon: otherScreenIcon
        )
        #expect(frame.midX == screen.midX)
        #expect(frame.maxY == visible.maxY - HUDLayout.gap)
    }

    @Test func goesToTheTopMiddleWhenThereIsNoIcon() {
        let frame = HUDLayout.frame(for: size, screen: screen, visible: visible, menuBarShowing: true, icon: nil)
        #expect(frame.midX == screen.midX)
        #expect(frame.maxY == visible.maxY - HUDLayout.gap)
    }

    // MARK: Telling whether the menu bar is showing

    // Window positions as macOS lists them: measured from the top-left of the main screen.
    let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let secondDisplay = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

    @Test func menuBarShowsWhenItsWindowIsOnThisScreen() {
        let menuBar = CGRect(x: 0, y: 0, width: 1440, height: 30)
        #expect(MenuBarCheck.isShowing(menuBarWindows: [menuBar], on: display))
    }

    /// Measured on macOS 27.2: while an app is in full screen, the menu bar window is gone from
    /// the list of on-screen windows, and comes back when full screen ends.
    @Test func menuBarIsHiddenWhenItsWindowIsGone() {
        #expect(!MenuBarCheck.isShowing(menuBarWindows: [], on: display))
    }

    @Test func aMenuBarOnAnotherScreenDoesNotCount() {
        let otherMenuBar = CGRect(x: 1440, y: 0, width: 1920, height: 30)
        #expect(!MenuBarCheck.isShowing(menuBarWindows: [otherMenuBar], on: display))
        #expect(MenuBarCheck.isShowing(menuBarWindows: [otherMenuBar], on: secondDisplay))
    }
}
