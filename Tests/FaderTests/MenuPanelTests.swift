import AppKit
import Observation
import SwiftUI
import Testing
@testable import Fader

/// The menu that drops down from Fader's menu bar icon. It used to be Apple's `MenuBarExtra`
/// window, which came out about 19 points taller than its content and left an empty strip
/// at the top. Fader now sizes the menu itself.
@MainActor
struct MenuPanelTests {
    // A pretend screen far away from the real ones, so nothing flashes up while tests run.
    let screen = CGRect(x: -20_000, y: 0, width: 1440, height: 870)  // below a 30 pt menu bar
    var icon: CGRect { CGRect(x: -20_000 + 1000, y: 870, width: 31, height: 30) }

    // MARK: Where the menu goes

    @Test func menuIsExactlyAsBigAsItsContent() {
        let frame = MenuPanelLayout.frame(for: CGSize(width: 340, height: 226), below: icon, on: screen)
        #expect(frame.size == CGSize(width: 340, height: 226))
    }

    @Test func menuHangsJustBelowTheIconAndLinesUpWithIt() {
        let frame = MenuPanelLayout.frame(for: CGSize(width: 340, height: 226), below: icon, on: screen)
        #expect(frame.maxY == icon.minY - MenuPanelLayout.gap)
        #expect(frame.minX == icon.minX)
    }

    @Test func menuStaysOnScreenWhenTheIconIsNearTheRightEdge() {
        let nearEdge = CGRect(x: screen.maxX - 40, y: 870, width: 31, height: 30)
        let frame = MenuPanelLayout.frame(for: CGSize(width: 340, height: 226), below: nearEdge, on: screen)
        #expect(frame.maxX == screen.maxX - MenuPanelLayout.margin)
    }

    @Test func menuTallerThanTheScreenIsCutToFit() {
        let frame = MenuPanelLayout.frame(for: CGSize(width: 340, height: 2000), below: icon, on: screen)
        #expect(frame.minY >= screen.minY)
        #expect(frame.maxY == icon.minY - MenuPanelLayout.gap)
    }

    // MARK: The real window

    @Observable final class FakeContent {
        var height: CGFloat = 300
    }

    struct FakeMenu: View {
        let content: FakeContent
        var body: some View {
            Color.clear.frame(width: 340, height: content.height)
        }
    }

    @Test func windowMatchesTheContentWhenItOpens() {
        let content = FakeContent()
        let panel = MenuPanel(rootView: FakeMenu(content: content))
        panel.show(below: icon, on: screen)
        defer { panel.close() }
        #expect(panel.window.frame.size == CGSize(width: 340, height: 300))
    }

    @Test func windowShrinksWhenTheContentDoesAndKeepsItsTop() {
        let content = FakeContent()
        let panel = MenuPanel(rootView: FakeMenu(content: content))
        panel.show(below: icon, on: screen)
        defer { panel.close() }
        let top = panel.window.frame.maxY

        content.height = 226  // e.g. an app stopped playing and its row went away
        waitUntil(panel) { panel.window.frame.height == 226 }

        #expect(panel.window.frame.size == CGSize(width: 340, height: 226))
        #expect(panel.window.frame.maxY == top)
    }

    @Test func windowGrowsWhenTheContentDoes() {
        let content = FakeContent()
        let panel = MenuPanel(rootView: FakeMenu(content: content))
        panel.show(below: icon, on: screen)
        defer { panel.close() }

        content.height = 400
        waitUntil(panel) { panel.window.frame.height == 400 }

        #expect(panel.window.frame.height == 400)
    }

    @Test func reopeningAfterAChangeWhileClosedStillFits() {
        let content = FakeContent()
        let panel = MenuPanel(rootView: FakeMenu(content: content))
        panel.show(below: icon, on: screen)
        panel.close()

        content.height = 180
        panel.show(below: icon, on: screen)
        defer { panel.close() }

        #expect(panel.window.frame.height == 180)
    }

    /// Lets SwiftUI and AppKit process the change (for up to 2 s), until `condition` holds.
    /// Tests don't run the app's event loop, so this does its window layout step by hand.
    private func waitUntil(_ panel: MenuPanel, _ condition: () -> Bool) {
        for _ in 0..<200 where !condition() {
            panel.window.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }
}
