import AppKit
import SwiftUI

/// Fader's look: Apple's Liquid Glass (macOS 26 and later) with standard controls, laid out like
/// macOS's own Control Center. Sliders use the accent colour chosen in System Settings → Appearance,
/// as Apple's guidelines recommend; picking "Graphite" there makes them grey.
enum Theme {
    /// The speaker icon in front of each slider, which is also its mute button. Like Control Center,
    /// it shows more sound waves as the volume rises, and a crossed-out speaker when muted.
    static func speakerSymbol(volume: Float, isMuted: Bool) -> String {
        if isMuted { return "speaker.slash.fill" }
        switch volume {
        case ..<0.01: return "speaker.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    // MARK: Shapes

    /// Space between the edge of the menu and its contents.
    static let menuPadding: CGFloat = 14
    /// Corner radius of the menu: rounder on Liquid Glass, like Apple's own menus there.
    static var menuCornerRadius: CGFloat {
        if #available(macOS 26, *) { 18 } else { 12 }
    }
    static let hudCornerRadius: CGFloat = 18
    static let minimumCornerRadius: CGFloat = 4

    /// Apple's "concentric corners" rule: a shape `inset` points inside a rounded container
    /// gets a corner radius that follows the container's curve, never fully sharp.
    static func concentricRadius(outer: CGFloat, inset: CGFloat) -> CGFloat {
        max(outer - inset, minimumCornerRadius)
    }
}

extension View {
    /// Liquid Glass behind this view on macOS 26 and later; the older frosted material before that.
    @ViewBuilder
    func glassBackground(cornerRadius: CGFloat) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: .rect(cornerRadius: cornerRadius, style: .continuous))
        } else {
            background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

extension View {
    /// Apple's Liquid Glass button on macOS 26 and later; the standard bordered button before that.
    @ViewBuilder
    func glassButton(shape: ButtonBorderShape) -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glass).buttonBorderShape(shape)
        } else {
            buttonStyle(.bordered).buttonBorderShape(shape)
        }
    }
}
