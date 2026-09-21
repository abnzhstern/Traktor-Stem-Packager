import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: PackagerModel
    @EnvironmentObject private var updateChecker: UpdateChecker
    @State private var showDetails = false

    private let panel = Color(red: 0.105, green: 0.11, blue: 0.125)
    private let background = Color(red: 0.065, green: 0.068, blue: 0.078)

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            ScrollView {
                VStack(spacing: 14) {
                    modePanel
                    if model.mode == .portableAAC {
                        metadataPanel
                    } else {
                        nativeConfigPanel
                    }
                    tracksPanel
                    statusPanel
                }
                .padding(16)
            }
            footer
        }
        .frame(minWidth: 760, minHeight: 660)
        .background(background)
        .preferredColorScheme(.dark)
        .task { await updateChecker.checkAutomatically() }
        .alert(item: $updateChecker.notice) { notice in
            if notice.offersDownload {
                return Alert(
                    title: Text(notice.title),
                    message: Text(notice.message),
                    primaryButton: .default(Text("Download Update")) { updateChecker.openLatestRelease() },
                    secondaryButton: .cancel(Text("Not Now"))
                )
            }
            return Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var modePanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            Picker("Output", selection: Binding(
                get: { model.mode },
                set: { model.setMode($0) }
            )) {
                ForEach(PackagingMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(model.mode == .portableAAC
                 ? "Creates a portable five-track Stem file using AAC 256 kbps."
                 : "Experimental: installs 16-bit/44.1 kHz ALAC stems as a sidecar linked to the original track in Traktor Pro 4.")
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.42))
        }
        .padding(12)
        .background(panel)
    }

    private var nativeConfigPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TRAKTOR NATIVE LINK")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(Color.white.opacity(0.45))
            pathRow(
                label: "Collection",
                url: model.collectionURL,
                emptyText: "Choose collection.nml",
                action: chooseCollection
            )
            pathRow(
                label: "Stems folder",
                url: model.stemsDirectoryURL,
                emptyText: "Choose Traktor’s configured Stems folder",
                action: chooseStemsDirectory
            )
            Text("The selected master must already be imported and analyzed in this collection. Traktor must be closed during installation. A collection backup is created automatically.")
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.4))
        }
        .padding(14)
        .background(panel)
    }

    private func pathRow(label: String, url: URL?, emptyText: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.4))
                .frame(width: 78, alignment: .trailing)
            Text(url?.path(percentEncoded: false) ?? emptyText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(url == nil ? Color.white.opacity(0.32) : Color.white.opacity(0.72))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("CHOOSE", action: action)
                .font(.system(size: 9, weight: .semibold))
        }
    }

    private var titleBar: some View {
        HStack {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 5) {
                Text("TRAKTOR STEM PACKAGER")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(0.7)
                Text("LUCKYSTAR PRODUCTIONS")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(2.2)
                    .foregroundStyle(Color.white.opacity(0.46))
            }
            Spacer()
            Text("TRAKTOR-READY .STEM.MP4")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.35))
        }
        .padding(.horizontal, 16)
        .frame(height: 72)
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
                    metadataRow("Producer", text: $model.producer, placeholder: "Producer", labelWidth: 56)
                    metadataRow("Label", text: $model.label, placeholder: "Label", labelWidth: 36)
                }
                HStack(spacing: 12) {
                    metadataRow("Genre", text: $model.genre, placeholder: "Genre", labelWidth: 56)
                    metadataRow("Released", text: $model.releaseDate, placeholder: "YYYY-MM-DD", labelWidth: 52)
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
            Button(model.mode == .portableAAC ? "EXPORT STEM.MP4" : "INSTALL LINKED STEMS") {
                Task { await model.create() }
            }
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
        if panel.runModal() == .OK { model.setArtwork(panel.url) }
    }

    private func chooseCollection() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.xml]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose Traktor Pro 4 collection.nml"
        if panel.runModal() == .OK { model.collectionURL = panel.url }
    }

    private func chooseStemsDirectory() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose the Stems folder configured in Traktor Pro 4"
        if panel.runModal() == .OK { model.stemsDirectoryURL = panel.url }
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
