import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: PackagerModel
    @State private var showDetails = false

    private let panel = Color(red: 0.105, green: 0.11, blue: 0.125)
    private let background = Color(red: 0.065, green: 0.068, blue: 0.078)

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            ScrollView {
                VStack(spacing: 14) {
                    metadataPanel
                    tracksPanel
                    statusPanel
                }
                .padding(16)
            }
            footer
        }
        .frame(minWidth: 760, minHeight: 610)
        .background(background)
        .preferredColorScheme(.dark)
    }

    private var titleBar: some View {
        HStack {
            Image(systemName: "square.stack.3d.up.fill")
                .foregroundStyle(Color.white.opacity(0.72))
            Text("STEM PACKAGER")
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.8)
            Spacer()
            Text("TRAKTOR-READY .STEM.MP4")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.35))
        }
        .padding(.horizontal, 16)
        .frame(height: 42)
        .background(Color(red: 0.17, green: 0.18, blue: 0.20))
    }

    private var metadataPanel: some View {
        HStack(alignment: .top, spacing: 14) {
            Button(action: chooseArtwork) {
                ZStack {
                    Rectangle().fill(Color.white.opacity(0.055))
                    if let url = model.artworkURL, let image = NSImage(contentsOf: url) {
                        Image(nsImage: image).resizable().scaledToFill()
                    } else {
                        VStack(spacing: 5) {
                            Image(systemName: "photo.badge.plus").font(.system(size: 22))
                            Text("ARTWORK").font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(Color.white.opacity(0.35))
                    }
                }
                .frame(width: 112, height: 112)
                .clipped()
                .overlay(Rectangle().stroke(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help("Choose JPEG or PNG artwork")

            VStack(spacing: 9) {
                metadataRow("Track", text: $model.title, placeholder: "Track title")
                metadataRow("Artist", text: $model.artist, placeholder: "Artist")
                metadataRow("Album", text: $model.album, placeholder: "Album")
                HStack(spacing: 12) {
                    metadataRow("Genre", text: $model.genre, placeholder: "Genre")
                    metadataRow("Year", text: $model.year, placeholder: "Year", labelWidth: 36)
                }
            }
        }
        .padding(14)
        .background(panel)
    }

    private func metadataRow(_ label: String, text: Binding<String>, placeholder: String, labelWidth: CGFloat = 48) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.38))
                .frame(width: labelWidth, alignment: .trailing)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .frame(height: 25)
                .background(Color.white.opacity(0.055))
                .overlay(Rectangle().stroke(Color.white.opacity(0.08)))
        }
    }

    private var tracksPanel: some View {
        VStack(spacing: 4) {
            ForEach([AudioRole.drums, .bass, .other, .vocals, .master]) { role in
                FileDropRow(
                    role: role,
                    displayName: stemNameBinding(role),
                    url: model.files[role],
                    select: { model.setFile($0, for: role) },
                    clear: { model.clear(role) }
                )
            }
        }
        .padding(10)
        .background(panel)
    }

    private var statusPanel: some View {
        VStack(spacing: 0) {
            Button { showDetails.toggle() } label: {
                HStack(spacing: 9) {
                    if model.state == .validating || model.state == .packaging {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: statusIcon).foregroundStyle(statusColor)
                    }
                    Text(model.statusText)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .lineLimit(2)
                    Spacer()
                    Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.35))
                }
                .contentShape(Rectangle())
                .padding(12)
            }
            .buttonStyle(.plain)

            if showDetails, let report = model.report {
                Divider().overlay(Color.white.opacity(0.08))
                Text("\(report.sampleRate) Hz  •  Stereo  •  \(duration(report.duration))  •  Stem sum \(report.stemSumTruePeakDbfs, specifier: "%.1f") dBFS  •  Compressor off  •  Limiter \(report.limiterEnabled ? "on" : "off")")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        }
        .background(panel)
    }

    private var footer: some View {
        HStack {
            Text("Source files are never altered")
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.32))
            Spacer()
            if case .complete = model.state {
                Button("SHOW IN FINDER") { model.revealOutput() }
            }
            Button("EXPORT STEM.MP4") { Task { await model.create() } }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.32, green: 0.34, blue: 0.37))
                .disabled(!model.canCreate)
        }
        .padding(.horizontal, 16)
        .frame(height: 55)
        .background(Color(red: 0.14, green: 0.145, blue: 0.16))
    }

    private func stemNameBinding(_ role: AudioRole) -> Binding<String> {
        Binding(
            get: { model.stemNames[role] ?? role.rawValue },
            set: { model.stemNames[role] = $0 }
        )
    }

    private func chooseArtwork() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK { model.artworkURL = panel.url }
    }

    private var statusIcon: String {
        switch model.state {
        case .ready, .complete: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        default: "info.circle.fill"
        }
    }

    private var statusColor: Color {
        switch model.state {
        case .ready, .complete: .green
        case .failed: .red
        default: Color.white.opacity(0.35)
        }
    }

    private func duration(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded())
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}
