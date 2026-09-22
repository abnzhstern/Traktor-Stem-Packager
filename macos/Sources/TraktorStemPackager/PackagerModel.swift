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
    @Published var recoveryText: String?
    @Published var validationProblemRoles: Set<AudioRole> = []
    @Published var folderImportNeedsReview = false
    @Published var waitingForManualTraktorQuit = false
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
    var audioSetValidated: Bool {
        guard hasAllFiles, report != nil else { return false }
        switch state {
        case .ready, .packaging, .complete: true
        case .waiting, .validating, .failed: false
        }
    }
    var assignmentsLocked: Bool { audioSetValidated && !folderImportNeedsReview }
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
        recoveryText = nil
        state = .waiting
        statusText = hasAllFiles ? "Checking compatibility…" : "Add your master and four stem files, or import a five-file folder."
        refreshNativeReadiness()
        if hasAllFiles && !folderImportNeedsReview { Task { await validate() } }
    }

    func setFile(_ url: URL, for role: AudioRole) {
        guard !assignmentsLocked else { return }
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
        recoveryText = nil
        state = .waiting
        statusText = folderImportNeedsReview
            ? "Review the assignments. Use Move/Swap or drag files between rows, then choose Accept Assignments."
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
                recoveryText = "Choose a folder containing exactly five supported audio files, or add the master and stems individually."
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
            recoveryText = nil
            folderImportNeedsReview = true
            state = .waiting
            statusText = "Review the assignments. Use Move/Swap or drag files between rows, then choose Accept Assignments."
            if let master = files[.master] {
                title = master.deletingPathExtension().lastPathComponent
                Task { await loadMasterMetadata(from: master) }
            }
            refreshNativeReadiness()
        } catch {
            folderImportNeedsReview = false
            state = .failed("The folder could not be read. Choose it again or add the files manually.")
            statusText = "The folder could not be read. Choose it again or add the files manually."
            recoveryText = "Check that the folder still exists and is readable, then choose it again or add the files individually."
        }
    }

    func confirmFolderAssignments() {
        guard folderImportNeedsReview, hasAllFiles else { return }
        folderImportNeedsReview = false
        statusText = "Checking compatibility…"
        Task { await validate() }
    }

    func editAssignments() {
        guard hasAllFiles else { return }
        folderImportNeedsReview = true
        report = nil
        validationProblemRoles = []
        recoveryText = nil
        state = .waiting
        statusText = "Assignments unlocked. Move or replace files, then choose Accept Assignments."
    }

    func moveFile(from source: AudioRole, to destination: AudioRole) {
        guard !assignmentsLocked, source != destination, let sourceURL = files[source] else { return }
        let previousMaster = files[.master]
        let displaced = files[destination]
        files[destination] = sourceURL
        files[source] = displaced
        report = nil
        validationProblemRoles = []
        recoveryText = nil
        folderImportNeedsReview = true
        state = .waiting
        statusText = "Assignments changed. Review all five slots, then choose Accept Assignments."
        if files[.master] != previousMaster, let master = files[.master] {
            title = master.deletingPathExtension().lastPathComponent
            Task { await loadMasterMetadata(from: master) }
            refreshNativeReadiness()
        }
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
        recoveryText = nil
        folderImportNeedsReview = false
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
            artworkURL = nil
            nativeReadiness = nil
        }
    }

    func clearAll() {
        readinessTask?.cancel()
        files.removeAll()
        report = nil
        nativeReadiness = nil
        validationProblemRoles = []
        folderImportNeedsReview = false
        waitingForManualTraktorQuit = false
        recoveryText = nil
        state = .waiting
        title = ""
        artist = ""
        album = ""
        genre = ""
        releaseDate = ""
        producer = ""
        label = ""
        stemNames = [.drums: "Drums", .bass: "Bass", .other: "Other", .vocals: "Vocals"]
        discardExtractedArtwork()
        artworkURL = nil
        statusText = "Queue cleared. Add your master and four stem files, or import a five-file folder."
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

    func pollTraktorStatus() async {
        let wasRunning = traktorRunning
        refreshTraktorStatus()
        if wasRunning,
           !traktorRunning,
           mode == .nativeLossless,
           files[.master] != nil,
           collectionURL != nil,
           nativeReadiness?.ready != true,
           state != .packaging {
            await checkTraktorForMaster()
        }
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

    func checkTraktorForMaster() async {
        guard mode == .nativeLossless else { return }
        guard let master = files[.master] else {
            statusText = "Add the stereo master first."
            recoveryText = "Drop or choose the exact master file you want to use in Traktor."
            return
        }
        guard let collectionURL else {
            statusText = "Choose Traktor’s collection.nml before checking for the master."
            recoveryText = "Use Choose beside Collection, then select the collection.nml used by this Traktor installation."
            return
        }
        statusText = "Checking Traktor’s saved collection for this exact master…"
        recoveryText = nil
        do {
            let result = try await EngineBridge().checkNativeReadiness(master: master, collection: collectionURL)
            nativeReadiness = result
            refreshTraktorStatus()
            if result.ready {
                statusText = "Analyzed master found. Add or confirm the four stems, then continue."
            } else if traktorRunning {
                statusText = "The analyzed master is not in Traktor’s saved collection yet. Finish analysis, then save or close Traktor."
                recoveryText = "After analysis finishes, return here and choose Check Traktor Again. If it is still not found, use Save, Close Traktor & Continue."
            } else {
                statusText = result.message
                recoveryText = "Choose Send Master to Traktor, analyze that exact file, then return here and check again."
            }
        } catch {
            nativeReadiness = NativeReadiness(ready: false, found: false, hasAudioId: false, message: error.localizedDescription)
            statusText = "Traktor’s collection could not be checked."
            recoveryText = "Confirm the Collection path points to collection.nml, then choose Check Traktor Again."
        }
    }

    func sendMasterToTraktor() {
        guard let master = files[.master] else {
            statusText = "Add the stereo master first."
            recoveryText = "Drop or choose the exact master file, then choose Send Master to Traktor."
            return
        }
        guard let traktorURL = traktorApplicationURL() else {
            state = .failed("Traktor Pro 4 could not be found in Applications.")
            statusText = "Traktor Pro 4 could not be found in Applications."
            recoveryText = "Open Traktor manually and import this exact master, or move Traktor Pro 4.app into the Applications folder."
            return
        }
        recoveryText = nil
        statusText = "Opening this exact master in Traktor…"
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([master], withApplicationAt: traktorURL, configuration: configuration) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                self.refreshTraktorStatus()
                if let error {
                    self.state = .failed("Traktor could not open the selected master: \(error.localizedDescription)")
                    self.statusText = "Traktor could not open the selected master."
                    self.recoveryText = "Open Traktor manually, import this exact master, analyze it, then return and choose Check Traktor Again."
                } else {
                    self.statusText = "Master sent to Traktor. Analyze it there, then return and choose Check Traktor Again."
                    self.recoveryText = "If Traktor analyzes imports automatically, wait for analysis to finish. Otherwise choose Analyze in Traktor."
                }
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
        recoveryText = nil
        do {
            let bridge = try EngineBridge()
            let result = try await bridge.validate(files: files, mode: mode)
            report = result
            validationProblemRoles = []
            state = .ready
            statusText = result.limiterEnabled
                ? String(format: "Accepted. All five files match. Peak protection is enabled at a −0.3 dBFS ceiling because the combined peak is %.1f dBFS.", result.stemSumTruePeakDbfs)
                : String(format: "Accepted. All five files match. Peak protection is not needed; the combined peak is %.1f dBFS.", result.stemSumTruePeakDbfs)
        } catch {
            validationProblemRoles = problemRoles(from: error.localizedDescription)
            state = .failed(error.localizedDescription)
            statusText = error.localizedDescription
            recoveryText = recoverySuggestion(for: error.localizedDescription)
        }
    }

    private func recoverySuggestion(for message: String) -> String {
        let text = message.lowercased()
        if text.contains("sample") || text.contains("khz") || text.contains("hz") {
            return "Re-export or replace the highlighted files so all five use the same supported sample rate and bit-depth profile."
        }
        if text.contains("mono") || text.contains("stereo") || text.contains("channel") {
            return "Replace or re-export the highlighted file as stereo audio, then add it again."
        }
        if text.contains("length") || text.contains("duration") || text.contains("seconds different") {
            return "Re-export all five files from exactly the same start and end points, then try again."
        }
        if text.contains("audio_id") || text.contains("analy") || text.contains("collection") {
            return "Analyze the exact master in Traktor, allow Traktor to save its collection, then choose Check Traktor Again."
        }
        return "Review the highlighted file slots and the message above. Replace the affected file, then try again. Your source files have not been changed."
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
            recoveryText = nil
        } catch {
            state = .failed(error.localizedDescription)
            statusText = error.localizedDescription
            recoveryText = recoverySuggestion(for: error.localizedDescription)
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
            ? "Traktor needs to save its collection before the app can verify the track ID. Close Automatically is convenient but macOS may request App Management permission. I’ll Quit Traktor avoids that permission; the app will wait and continue automatically."
            : traktor == nil
            ? "The app will verify all five decoded PCM streams, back up collection.nml, install the lossless sidecar, and link it to the exact master track."
            : "Traktor must close before installation. Close Automatically is convenient but macOS may request App Management permission. I’ll Quit Traktor avoids that permission; the app will wait and continue automatically."
        warning.alertStyle = .warning
        if traktor != nil {
            warning.addButton(withTitle: "I’ll Quit Traktor")
            warning.addButton(withTitle: "Close Automatically")
            warning.addButton(withTitle: "Cancel")
        } else {
            warning.addButton(withTitle: "Verify & Install")
            warning.addButton(withTitle: "Cancel")
        }
        let handoffChoice = warning.runModal()
        if traktor != nil {
            guard handoffChoice != .alertThirdButtonReturn else { return }
        } else {
            guard handoffChoice == .alertFirstButtonReturn else { return }
        }

        state = .packaging
        recoveryText = nil
        if let traktor {
            let closeAutomatically = handoffChoice == .alertSecondButtonReturn
            guard await closeTraktorOrWaitForUser(traktor, automatically: closeAutomatically) else { return }
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
                recoveryText = "Open Traktor and analyze the exact master. After analysis finishes, close Traktor normally and choose Check Traktor Again."
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
            recoveryText = nil
            if shouldRelaunch, let traktorURL {
                _ = NSWorkspace.shared.open(traktorURL)
            }
            refreshTraktorStatus()
        } catch {
            state = .failed(error.localizedDescription)
            statusText = error.localizedDescription
            recoveryText = recoverySuggestion(for: error.localizedDescription)
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

    private func closeTraktorOrWaitForUser(
        _ application: NSRunningApplication,
        automatically: Bool
    ) async -> Bool {
        waitingForManualTraktorQuit = !automatically
        if automatically {
            statusText = "Asking Traktor to save and close…"
            _ = application.terminate()
            for _ in 0..<20 {
                if application.isTerminated {
                    waitingForManualTraktorQuit = false
                    refreshTraktorStatus()
                    return true
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            waitingForManualTraktorQuit = true
            statusText = "macOS did not allow automatic closing. Quit Traktor normally; this app is waiting and will continue by itself."
            recoveryText = "In Traktor, choose Traktor Pro 4 > Quit Traktor Pro 4. Finish any save prompt. Do not restart this process."
        } else {
            statusText = "Quit Traktor normally. This app is waiting and will continue automatically when Traktor closes."
            recoveryText = "In Traktor, choose Traktor Pro 4 > Quit Traktor Pro 4 and finish any save prompt."
        }

        for _ in 0..<2400 {
            if application.isTerminated || runningTraktorApplication() == nil {
                waitingForManualTraktorQuit = false
                recoveryText = nil
                refreshTraktorStatus()
                statusText = "Traktor closed. Rechecking the saved analysis…"
                return true
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        waitingForManualTraktorQuit = false
        state = .ready
        statusText = "Traktor is still open, so installation has paused."
        recoveryText = "Quit Traktor normally, then choose Verify & Install Lossless Stems again. No files were changed."
        return false
    }

    private func traktorApplicationURL() -> URL? {
        if let runningURL = runningTraktorApplication()?.bundleURL { return runningURL }
        let manager = FileManager.default
        let candidates = [
            URL(fileURLWithPath: "/Applications/Traktor Pro 4.app"),
            manager.homeDirectoryForCurrentUser.appending(path: "Applications/Traktor Pro 4.app")
        ]
        return candidates.first { manager.fileExists(atPath: $0.path) }
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
