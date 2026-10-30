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
            } else if model.rows.count > 7 {
                ScrollView { rowList }.frame(height: 380)
            } else {
                rowList
            }

            Divider()

            HStack {
                Button("Settings…", action: openSettings)
                Spacer()
                Button("Quit Fader") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 340)
    }

    private var header: some View {
        HStack {
            Text("Fader").font(.headline)
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
        VStack(spacing: 10) {
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
                    Image(nsImage: icon).resizable().frame(width: 24, height: 24)
                } else {
                    Image(systemName: "app.fill").frame(width: 24, height: 24)
                }
                if row.isPlaying {
                    Circle().fill(.green).frame(width: 7, height: 7)
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
            Image(systemName: "speaker.wave.3.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
        }
    }
}

/// Icon, name, slider, mute button and percentage: one line of the mixer.
private struct VolumeRowView<Icon: View>: View {
    let name: String
    let volume: Float
    let isMuted: Bool
    let canMute: Bool
    let setVolume: (Float) -> Void
    let toggleMute: () -> Void
    @ViewBuilder let icon: Icon

    var body: some View {
        HStack(spacing: 8) {
            icon

            VStack(alignment: .leading, spacing: 0) {
                Text(name).font(.callout).lineLimit(1)
                Slider(
                    value: Binding(
                        get: { Double(volume) },
                        set: { setVolume(Float($0)) }
                    ),
                    in: 0...1
                )
                .controlSize(.small)
                .disabled(isMuted)
            }

            Button(action: toggleMute) {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 18)
                    .foregroundStyle(isMuted ? .red : .secondary)
            }
            .buttonStyle(.borderless)
            .disabled(!canMute)
            .help(isMuted ? "Unmute" : "Mute")

            Text(isMuted ? "–" : "\(Int((volume * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
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
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }
}
