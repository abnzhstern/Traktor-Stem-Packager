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
    @Published var statusText = "Add your master and four stem files, or import a five-file folder."
    @Published var validationProblemRoles: Set<AudioRole> = []
    @Published var folderImportNeedsReview = false
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
    var audioSetValidated: Bool { state == .ready && hasAllFiles }
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
        if mode == .portableAAC { return "CREATE AAC STEM FILE" }
        if canResolveUnsavedAnalysis { return "SAVE, CLOSE TRAKTOR & CONTINUE" }
        return "VERIFY & INSTALL LOSSLESS STEMS"
    }

    func setMode(_ newMode: PackagingMode) {
        mode = newMode
        report = nil
        validationProblemRoles = []
        state = .waiting
        statusText = hasAllFiles ? "Checking compatibility…" : "Add your master and four stem files, or import a five-file folder."
        refreshNativeReadiness()
        if hasAllFiles && !folderImportNeedsReview { Task { await validate() } }
    }

    func setFile(_ url: URL, for role: AudioRole) {
        let previousMaster = files[.master]
        if let sourceRole = files.first(where: { $0.value.standardizedFileURL == url.standardizedFileURL })?.key,
           sourceRole != role {
            let displaced = files[role]
            files[role] = url
            files[sourceRole] = displaced
        } else {
            files[role] = url
        }
        report = nil
        validationProblemRoles = []
        state = .waiting
        statusText = folderImportNeedsReview
            ? "Review the folder assignments. Drag files between rows to swap them, then confirm."
            : hasAllFiles ? "Checking compatibility…" : "Add your master and four stem files, or import a five-file folder."
        if files[.master] != previousMaster, let master = files[.master] {
            title = master.deletingPathExtension().lastPathComponent
            Task { await loadMasterMetadata(from: master) }
            refreshNativeReadiness()
        }
        if hasAllFiles && !folderImportNeedsReview { Task { await validate() } }
    }

    func importFolder(_ directory: URL) {
        let supported = Set(["wav", "wave", "aif", "aiff", "m4a", "aac", "mp3"])
        do {
            let audioFiles = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
                .filter { supported.contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

            guard audioFiles.count == 5 else {
                folderImportNeedsReview = false
                validationProblemRoles = []
                state = .failed("This folder contains \(audioFiles.count) supported audio files. Choose a folder containing exactly one master and four stems, or add the files manually.")
                statusText = "This folder contains \(audioFiles.count) supported audio files. Choose a folder containing exactly one master and four stems, or add the files manually."
                return
            }

            var assignments: [AudioRole: URL] = [:]
            var unassigned: [URL] = []
            for file in audioFiles {
                if let role = suggestedRole(for: file), assignments[role] == nil {
                    assignments[role] = file
                } else {
                    unassigned.append(file)
                }
            }
            for role in AudioRole.allCases where assignments[role] == nil {
                if let next = unassigned.first {
                    assignments[role] = next
                    unassigned.removeFirst()
                }
            }

            files = assignments
            report = nil
            validationProblemRoles = []
            folderImportNeedsReview = true
            state = .waiting
            statusText = "Review the folder assignments. Drag files between rows to swap them, then confirm."
            if let master = files[.master] {
                title = master.deletingPathExtension().lastPathComponent
                Task { await loadMasterMetadata(from: master) }
            }
            refreshNativeReadiness()
        } catch {
            folderImportNeedsReview = false
            state = .failed("The folder could not be read. Choose it again or add the files manually.")
            statusText = "The folder could not be read. Choose it again or add the files manually."
        }
    }

    func confirmFolderAssignments() {
        guard folderImportNeedsReview, hasAllFiles else { return }
        folderImportNeedsReview = false
        statusText = "Checking compatibility…"
        Task { await validate() }
    }

    private func suggestedRole(for file: URL) -> AudioRole? {
        let base = file.deletingPathExtension().lastPathComponent.lowercased()
        let tokens = base.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let boundaryTokens = Set([tokens.first, tokens.last].compactMap { $0 })
        if !boundaryTokens.isDisjoint(with: ["drum", "drums", "percussion"]) { return .drums }
        if boundaryTokens.contains("bass") { return .bass }
        if !boundaryTokens.isDisjoint(with: ["vocal", "vocals", "vox", "acapella", "acappella"]) { return .vocals }
        if !boundaryTokens.isDisjoint(with: ["other", "music", "instrumental", "instruments"]) { return .other }
        if boundaryTokens.contains("master") || base.contains("full mix") || base.contains("mixdown") || base.contains("stereo mix") {
            return .master
        }
        return nil
    }

    func clear(_ role: AudioRole) {
        files[role] = nil
        report = nil
        validationProblemRoles = []
        state = .waiting
        statusText = "Add your master and four stem files, or import a five-file folder."
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
            validationProblemRoles = []
            state = .ready
            statusText = result.limiterEnabled
                ? String(format: "Compatible. Peak protection enabled: combined peak %.1f dBFS; ceiling −0.3 dBFS.", result.stemSumTruePeakDbfs)
                : String(format: "Compatible. Protection not needed: combined peak %.1f dBFS.", result.stemSumTruePeakDbfs)
        } catch {
            validationProblemRoles = problemRoles(from: error.localizedDescription)
            state = .failed(error.localizedDescription)
            statusText = error.localizedDescription
        }
    }

    private func problemRoles(from message: String) -> Set<AudioRole> {
        let lowercased = message.lowercased()
        let matched = AudioRole.allCases.filter { role in
            guard let url = files[role] else { return false }
            return lowercased.contains(role.commandName.lowercased()) ||
                lowercased.contains(url.path.lowercased())
        }
        return matched.isEmpty ? Set(AudioRole.allCases) : Set(matched)
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
            ? "Traktor appears to have analyzed the master without saving its new track ID to collection.nml. The app will ask Traktor to quit normally, recheck the saved analysis, install the linked stems, then reopen Traktor. If macOS requests permission for this Traktor handoff, choose Allow."
            : traktor == nil
            ? "The app will verify all five decoded PCM streams, back up collection.nml, install the lossless sidecar, and link it to the exact master track."
            : "The app will ask Traktor to quit normally so it can save the collection, verify all five decoded PCM streams, install the linked stems, then reopen Traktor. If macOS requests permission for this Traktor handoff, choose Allow."
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
