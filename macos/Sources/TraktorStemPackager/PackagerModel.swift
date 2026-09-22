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
    @Published var mode: PackagingMode = .portableAAC
    @Published var collectionURL: URL?
    @Published var stemsDirectoryURL: URL?
    @Published var title = ""
    @Published var artist = ""
    @Published var album = ""
    @Published var genre = ""
    @Published var releaseDate = ""
    @Published var producer = ""
    @Published var label = ""
    @Published var artworkURL: URL?
    @Published var stemNames: [AudioRole: String] = [
        .drums: "Drums", .bass: "Bass", .other: "Other", .vocals: "Vocals"
    ]
    @Published var state: State = .waiting
    @Published var report: ValidationReport?
    @Published var nativeReadiness: NativeReadiness?
    @Published var traktorRunning = false
    @Published var statusText = "Add the master and four matching stereo stems."
    private var extractedArtworkURL: URL?
    private var readinessTask: Task<Void, Never>?

    init() {
        let manager = FileManager.default
        let home = manager.homeDirectoryForCurrentUser
        let nativeInstruments = home.appending(path: "Documents/Native Instruments")
        if let folders = try? manager.contentsOfDirectory(
            at: nativeInstruments,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            collectionURL = folders
                .filter { $0.lastPathComponent.hasPrefix("Traktor ") }
                .map { $0.appending(path: "collection.nml") }
                .filter { manager.fileExists(atPath: $0.path) }
                .sorted { $0.deletingLastPathComponent().lastPathComponent > $1.deletingLastPathComponent().lastPathComponent }
                .first
        }
        let defaultStems = home.appending(path: "Music/Traktor/Stems")
        if manager.fileExists(atPath: defaultStems.path) { stemsDirectoryURL = defaultStems }
        refreshTraktorStatus()
    }

    var hasAllFiles: Bool { AudioRole.allCases.allSatisfy { files[$0] != nil } }
    var canCreate: Bool {
        state == .ready && hasAllFiles &&
            (mode == .portableAAC || (collectionURL != nil && stemsDirectoryURL != nil && nativeReadiness?.ready == true))
    }

    var canResolveUnsavedAnalysis: Bool {
        state == .ready && mode == .nativeLossless && hasAllFiles &&
            collectionURL != nil && stemsDirectoryURL != nil &&
            traktorRunning && nativeReadiness?.ready == false
    }

    var primaryActionTitle: String {
        if mode == .portableAAC { return "CREATE PORTABLE STEM FILE" }
        if canResolveUnsavedAnalysis { return "SAVE, CLOSE TRAKTOR & CONTINUE" }
        return "VERIFY & INSTALL LOSSLESS STEMS"
    }

    func setMode(_ newMode: PackagingMode) {
        mode = newMode
        report = nil
        state = .waiting
        statusText = hasAllFiles ? "Checking compatibility…" : "Add the remaining audio files."
        refreshNativeReadiness()
        if hasAllFiles { Task { await validate() } }
    }

    func setFile(_ url: URL, for role: AudioRole) {
        files[role] = url
        report = nil
        state = .waiting
        statusText = hasAllFiles ? "Checking compatibility…" : "Add the remaining audio files."
        if role == .master {
            title = url.deletingPathExtension().lastPathComponent
            Task { await loadMasterMetadata(from: url) }
            refreshNativeReadiness()
        }
        if hasAllFiles { Task { await validate() } }
    }

    func clear(_ role: AudioRole) {
        files[role] = nil
        report = nil
        state = .waiting
        statusText = "Add the remaining audio files."
        if role == .master {
            title = ""
            artist = ""
            album = ""
            genre = ""
            releaseDate = ""
            producer = ""
            label = ""
            discardExtractedArtwork()
            nativeReadiness = nil
        }
    }

    func setCollection(_ url: URL?) {
        collectionURL = url
        refreshNativeReadiness()
    }

    func setStemsDirectory(_ url: URL?) {
        stemsDirectoryURL = url
    }

    func refreshTraktorStatus() {
        traktorRunning = runningTraktorApplication() != nil
    }

    func refreshNativeReadiness() {
        readinessTask?.cancel()
        nativeReadiness = nil
        guard mode == .nativeLossless,
              let master = files[.master],
              let collection = collectionURL else { return }
        readinessTask = Task { [weak self] in
            do {
                let result = try await EngineBridge().checkNativeReadiness(master: master, collection: collection)
                guard !Task.isCancelled,
                      self?.files[.master] == master,
                      self?.collectionURL == collection else { return }
                self?.nativeReadiness = result
            } catch {
                guard !Task.isCancelled else { return }
                self?.nativeReadiness = NativeReadiness(
                    ready: false, found: false, hasAudioId: false,
                    message: error.localizedDescription
                )
            }
        }
    }

    func setArtwork(_ url: URL?) {
        discardExtractedArtwork()
        artworkURL = url
    }

    private func loadMasterMetadata(from url: URL) async {
        do {
            let bridge = try EngineBridge()
            let metadata = try await bridge.readMasterMetadata(master: url)
            guard files[.master] == url else { return }
            title = metadata.title
            artist = metadata.artist
            album = metadata.album
            genre = metadata.genre
            releaseDate = metadata.releaseDate
            producer = metadata.producer
            label = metadata.label
            discardExtractedArtwork()
            if let encoded = metadata.artworkBase64,
               let data = Data(base64Encoded: encoded), !data.isEmpty {
                let fileExtension = metadata.artworkMimeType == "image/png" ? "png" : "jpg"
                let artwork = FileManager.default.temporaryDirectory
                    .appending(path: "traktor-master-artwork-\(UUID().uuidString).\(fileExtension)")
                try data.write(to: artwork, options: .atomic)
                extractedArtworkURL = artwork
                artworkURL = artwork
            }
        } catch {
            // Keep filename fallback and allow packaging when the source has no readable tags.
        }
    }

    private func discardExtractedArtwork() {
        guard let extractedArtworkURL else { return }
        if artworkURL == extractedArtworkURL { artworkURL = nil }
        try? FileManager.default.removeItem(at: extractedArtworkURL)
        self.extractedArtworkURL = nil
    }

    func validate() async {
        guard hasAllFiles else { return }
        state = .validating
        statusText = "Checking sample rate, channels, duration and stem-sum peak…"
        do {
            let bridge = try EngineBridge()
            let result = try await bridge.validate(files: files, mode: mode)
            report = result
            state = .ready
            statusText = result.limiterEnabled
                ? String(format: "Compatible. Peak protection enabled: combined peak %.1f dBFS; ceiling −0.3 dBFS.", result.stemSumTruePeakDbfs)
                : String(format: "Compatible. Protection not needed: combined peak %.1f dBFS.", result.stemSumTruePeakDbfs)
        } catch {
            state = .failed(error.localizedDescription)
            statusText = error.localizedDescription
        }
    }

    func create() async {
        guard canCreate || canResolveUnsavedAnalysis else { return }
        if mode == .nativeLossless {
            await createNativeLossless()
            return
        }
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
                releaseDate: releaseDate,
                producer: producer,
                label: label,
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

    private func createNativeLossless() async {
        guard let collectionURL, let stemsDirectoryURL else { return }
        refreshTraktorStatus()
        let traktor = runningTraktorApplication()
        let shouldRelaunch = traktor != nil
        let traktorURL = traktor?.bundleURL
        let needsSavedAnalysisRefresh = nativeReadiness?.ready != true
        let warning = NSAlert()
        warning.messageText = needsSavedAnalysisRefresh && traktor != nil
            ? "Save Traktor’s analysis and continue?"
            : traktor == nil
            ? "Verify and install lossless stems?"
            : "Close Traktor and install lossless stems?"
        warning.informativeText = needsSavedAnalysisRefresh && traktor != nil
            ? "Traktor appears to have analyzed the master without saving its new track ID to collection.nml. The app will ask Traktor to quit normally, recheck the saved analysis, install the linked stems, then reopen Traktor."
            : traktor == nil
            ? "The app will verify all five decoded PCM streams, back up collection.nml, install the lossless sidecar, and link it to the exact master track."
            : "The app will ask Traktor to quit normally so it can save the collection, verify all five decoded PCM streams, install the linked stems, then reopen Traktor."
        warning.alertStyle = .warning
        warning.addButton(withTitle: needsSavedAnalysisRefresh && traktor != nil
            ? "Save, Close & Continue"
            : traktor == nil ? "Verify & Install" : "Close Traktor & Install")
        warning.addButton(withTitle: "Cancel")
        guard warning.runModal() == .alertFirstButtonReturn else { return }

        state = .packaging
        if let traktor {
            statusText = "Waiting for Traktor to save and close…"
            do {
                try await quitTraktorGracefully(traktor)
            } catch {
                state = .failed(error.localizedDescription)
                statusText = error.localizedDescription
                return
            }
        }
        if needsSavedAnalysisRefresh {
            statusText = "Rechecking Traktor’s saved track analysis…"
            let readiness = await recheckNativeReadinessAfterTraktorQuit(
                master: files[.master],
                collection: collectionURL
            )
            guard readiness?.ready == true else {
                state = .ready
                statusText = readiness?.message ?? "Could not recheck the saved Traktor collection."
                if shouldRelaunch, let traktorURL { _ = NSWorkspace.shared.open(traktorURL) }
                refreshTraktorStatus()
                return
            }
        }
        statusText = "Creating and verifying lossless ALAC streams…"
        do {
            let bridge = try EngineBridge()
            let result = try await bridge.packageNativeLossless(
                files: files,
                collection: collectionURL,
                stemsDirectory: stemsDirectoryURL,
                stemNames: stemNames
            ) { message in
                Task { @MainActor in
                    if !message.isEmpty { self.statusText = message }
                }
            }
            let destination = URL(fileURLWithPath: result.destination)
            state = .complete(destination)
            statusText = "Installed and verified: all five decoded PCM streams match their sources exactly."
            if shouldRelaunch, let traktorURL {
                _ = NSWorkspace.shared.open(traktorURL)
            }
            refreshTraktorStatus()
        } catch {
            state = .failed(error.localizedDescription)
            statusText = error.localizedDescription
        }
    }

    private func recheckNativeReadinessAfterTraktorQuit(
        master: URL?,
        collection: URL
    ) async -> NativeReadiness? {
        guard let master else { return nil }
        for attempt in 0..<8 {
            do {
                let result = try await EngineBridge().checkNativeReadiness(master: master, collection: collection)
                nativeReadiness = result
                if result.ready { return result }
                if attempt < 7 { try await Task.sleep(nanoseconds: 250_000_000) }
            } catch {
                nativeReadiness = NativeReadiness(
                    ready: false, found: false, hasAudioId: false,
                    message: error.localizedDescription
                )
                if attempt < 7 { try? await Task.sleep(nanoseconds: 250_000_000) }
            }
        }
        return nativeReadiness
    }

    private func runningTraktorApplication() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { application in
            application.localizedName == "Traktor Pro 4" ||
                application.bundleURL?.lastPathComponent == "Traktor Pro 4.app"
        }
    }

    private func quitTraktorGracefully(_ application: NSRunningApplication) async throws {
        guard application.terminate() else {
            throw EngineError.failed("Traktor did not accept the quit request. Quit it manually, then try again.")
        }
        for _ in 0..<240 {
            if application.isTerminated {
                refreshTraktorStatus()
                return
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw EngineError.failed("Traktor is still open. Finish any save prompts or quit it manually, then try again.")
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
