import AppKit
import Foundation

@MainActor
final class PackagerModel: ObservableObject {
    enum State: Equatable {
        case waiting
        case validating
        case ready
        case packaging
        case complete(URL)
        case failed(String)
    }

    @Published var files: [AudioRole: URL] = [:]
    @Published var title = ""
    @Published var artist = ""
    @Published var album = ""
    @Published var genre = ""
    @Published var year = ""
    @Published var artworkURL: URL?
    @Published var stemNames: [AudioRole: String] = [
        .drums: "Drums", .bass: "Bass", .other: "Other", .vocals: "Vocals"
    ]
    @Published var state: State = .waiting
    @Published var report: ValidationReport?
    @Published var statusText = "Add the master and four matching stereo stems."

    var hasAllFiles: Bool { AudioRole.allCases.allSatisfy { files[$0] != nil } }
    var canCreate: Bool { state == .ready && hasAllFiles }

    func setFile(_ url: URL, for role: AudioRole) {
        files[role] = url
        report = nil
        state = .waiting
        statusText = hasAllFiles ? "Checking compatibility…" : "Add the remaining audio files."
        if role == .master && title.isEmpty {
            title = url.deletingPathExtension().lastPathComponent
        }
        if hasAllFiles { Task { await validate() } }
    }

    func clear(_ role: AudioRole) {
        files[role] = nil
        report = nil
        state = .waiting
        statusText = "Add the remaining audio files."
    }

    func validate() async {
        guard hasAllFiles else { return }
        state = .validating
        statusText = "Checking sample rate, channels, duration and stem-sum peak…"
        do {
            let bridge = try EngineBridge()
            let result = try await bridge.validate(files: files)
            report = result
            state = .ready
            statusText = result.limiterEnabled
                ? "Compatible. Limiter protection will be embedded for the measured stem sum."
                : "Compatible. No Stem Master dynamics processing is required."
        } catch {
            state = .failed(error.localizedDescription)
            statusText = error.localizedDescription
        }
    }

    func create() async {
        guard canCreate else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = sanitizedOutputName()
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        state = .packaging
        statusText = "Preparing audio…"
        do {
            let bridge = try EngineBridge()
            try await bridge.package(
                files: files,
                output: destination,
                title: title,
                artist: artist,
                album: album,
                genre: genre,
                year: year,
                artwork: artworkURL,
                stemNames: stemNames
            ) { message in
                Task { @MainActor in
                    if !message.isEmpty { self.statusText = message }
                }
            }
            state = .complete(destination)
            statusText = "Traktor Stem file created successfully."
        } catch {
            state = .failed(error.localizedDescription)
            statusText = error.localizedDescription
        }
    }

    func revealOutput() {
        if case .complete(let url) = state {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func sanitizedOutputName() -> String {
        let base = title.isEmpty ? "Untitled" : title
        let invalid = CharacterSet(charactersIn: "/:")
        let safe = base.components(separatedBy: invalid).joined(separator: "-")
        return safe.hasSuffix(".stem.mp4") ? safe : "\(safe).stem.mp4"
    }
}
