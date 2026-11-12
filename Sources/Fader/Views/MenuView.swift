import AppKit
import SwiftUI

struct MenuView: View {
    let model: MixerModel
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if model.mainVolume.isAvailable {
                MainVolumeRowView(main: model.mainVolume)
            }

            if model.permission != .authorized {
                PermissionBanner(model: model)
            }

            Divider()

            if model.rows.isEmpty {
                Text("No apps are playing audio")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else if model.rows.count > 6 {
                ScrollView { rowList }.frame(height: 400)
            } else {
                rowList
            }

            Divider()

            HStack {
                Button(action: openSettings) {
                    Label("Settings…", systemImage: "gearshape")
                }
                .glassButton(shape: .capsule)
                Spacer()
                Button("Quit Fader") { NSApp.terminate(nil) }
                    .glassButton(shape: .capsule)
            }
            .controlSize(.large)
        }
        .padding(Theme.menuPadding)
        .frame(width: 340)
    }

    private var header: some View {
        HStack {
            Text("Fader").font(.headline.weight(.semibold))
            Spacer()
            if let device = model.outputDevice {
                Label(device.name, systemImage: "hifispeaker.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var rowList: some View {
        VStack(spacing: 14) {
            ForEach(model.rows) { row in
                AppRowView(row: row, model: model)
            }
        }
    }
}

private struct AppRowView: View {
    let row: MixerModel.AppRow
    let model: MixerModel

    var body: some View {
        VolumeRowView(
            name: row.name,
            volume: row.volume,
            isMuted: row.isMuted,
            canMute: true,
            setVolume: { model.setVolume($0, for: row.id) },
            toggleMute: { model.toggleMute(row.id) }
        ) {
            ZStack(alignment: .bottomTrailing) {
                if let icon = row.icon {
                    Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                } else {
                    Image(systemName: "app.fill").frame(width: 18, height: 18)
                }
                if row.isPlaying {
                    Circle().fill(.green).frame(width: 6, height: 6)
                }
            }
        }
    }
}

/// The output device's own volume, the same one the volume keys change.
private struct MainVolumeRowView: View {
    let main: MainVolumeModel

    var body: some View {
        VolumeRowView(
            name: "Overall volume",
            volume: main.volume,
            isMuted: main.isMuted,
            canMute: main.canMute,
            setVolume: main.setVolume,
            toggleMute: main.toggleMute
        ) {
            EmptyView()
        }
    }
}

/// One part of the mixer, laid out like the sliders in macOS's own Control Center: the app's icon,
/// name and percentage on top, then a speaker icon (click it to mute) in front of the slider.
private struct VolumeRowView<Icon: View>: View {
    let name: String
    let volume: Float
    let isMuted: Bool
    let canMute: Bool
    let setVolume: (Float) -> Void
    let toggleMute: () -> Void
    @ViewBuilder let icon: Icon

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                icon
                Text(name).lineLimit(1)
                Spacer()
                Text(isMuted ? "Muted" : "\(Int((volume * 100).rounded()))%")
                    .monospacedDigit()
            }
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button(action: toggleMute) {
                    Image(systemName: Theme.speakerSymbol(volume: volume, isMuted: isMuted))
                        .foregroundStyle(isMuted ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())  // the whole square is clickable, not just the symbol
                }
                .buttonStyle(.plain)
                .disabled(!canMute)
                .help(isMuted ? "Unmute" : "Mute")
                .accessibilityLabel(isMuted ? "Unmute \(name)" : "Mute \(name)")

                // The large size gets the Liquid Glass slider knob on macOS 26 and later.
                Slider(
                    value: Binding(
                        get: { Double(volume) },
                        set: { setVolume(Float($0)) }
                    ),
                    in: 0...1
                )
                .controlSize(.large)
                .disabled(isMuted)
            }
        }
    }
}

private struct PermissionBanner: View {
    let model: MixerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fader needs System Audio Recording access to change app volumes.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if model.permission == .denied {
                    Button("Open System Settings") {
                        NSWorkspace.shared.open(AudioCapturePermission.settingsURL)
                    }
                } else {
                    Button("Allow Access") { model.requestPermission() }
                }
            }
            .glassButton(shape: .capsule)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A soft grey shape, not more glass: Apple's guidelines say not to stack glass on glass.
        .background(
            .quaternary,
            in: RoundedRectangle(
                cornerRadius: Theme.concentricRadius(outer: Theme.menuCornerRadius, inset: Theme.menuPadding),
                style: .continuous
            )
        )
    }
}
